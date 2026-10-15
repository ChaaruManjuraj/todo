import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:http/http.dart' as http;

import '../domain/task.dart';
import 'firestore_rest_codec.dart';
import 'outbox.dart';
import 'task_repository.dart';

/// Windows/Linux data path: Firestore over REST, a local JSON cache, and an outbox for offline writes.
/// `watch()` always reads the cache; [refresh] pushes the outbox, then replaces the cache with the server's copy
/// (with still-pending local writes laid over it).
class RestRepo implements TaskRepository {
  RestRepo._(this._client, this._idToken, this._uid, this._project, this._host, this._now, this._tasksFile, this._outboxFile);

  /// [idToken] returns a Firebase ID token; `forceRefresh` is set after a 401.
  static RestRepo open({
    required http.Client client,
    required Future<String> Function({bool forceRefresh}) idToken,
    required Directory cacheDir,
    required String uid,
    String project = 'todo-ba12a',
    String host = 'https://firestore.googleapis.com',
    DateTime Function()? now,
    Duration? poll = const Duration(seconds: 60),
  }) {
    cacheDir.createSync(recursive: true);
    final r = RestRepo._(client, idToken, uid, project, host, now ?? DateTime.now, JsonFile(cacheDir, 'tasks.json'), JsonFile(cacheDir, 'outbox.json'));
    r._load();
    if (poll != null) r._start(poll);
    return r;
  }

  final http.Client _client;
  final Future<String> Function({bool forceRefresh}) _idToken;
  final String _uid, _project, _host;
  final DateTime Function() _now;
  final JsonFile _tasksFile, _outboxFile;

  var _remote = <String, Task>{}; // last copy seen on the server
  var _updateTimes = <String, String>{}; // server updateTime per id, for preconditions
  var _outbox = <Op>[];
  final _listeners = <MultiStreamController<List<Task>>>{};
  Timer? _timer;
  AppLifecycleListener? _lifecycle;
  Future<void>? _current;
  bool _again = false;

  @override
  final ValueNotifier<int> pending = ValueNotifier(0);

  // ---- TaskRepository -------------------------------------------------------------------------

  @override
  Stream<List<Task>> watch() => Stream.multi((c) {
        _listeners.add(c);
        c.onCancel = () => _listeners.remove(c);
        c.add(_view());
      });

  @override
  Future<void> upsert(Task task) async {
    final at = _now();
    _enqueue(Op.upsert(task.copyWith(updatedAt: at.toUtc()), at));
  }

  @override
  Future<void> delete(String id) async => _enqueue(Op.delete(id, _now()));

  void dispose() {
    _timer?.cancel();
    _lifecycle?.dispose();
  }

  // ---- local state ----------------------------------------------------------------------------

  void _load() {
    final t = _tasksFile.read();
    if (t is Map) {
      _remote = {for (final j in (t['tasks'] as List? ?? const [])) (j as Map)['id'] as String: Task.fromJson(j.cast<String, Object?>())};
      _updateTimes = ((t['updateTimes'] as Map?) ?? const {}).cast<String, String>();
    }
    final o = _outboxFile.read();
    if (o is List) _outbox = [for (final j in o) Op.fromJson((j as Map).cast<String, Object?>())];
    pending.value = _outbox.length;
  }

  List<Task> _view() {
    final m = {..._remote};
    for (final op in _outbox) {
      op.delete ? m.remove(op.id) : m[op.id] = op.task!;
    }
    return List.unmodifiable(m.values);
  }

  void _emit() {
    final v = _view();
    for (final c in _listeners) {
      c.add(v);
    }
  }

  void _saveTasks() => _tasksFile.write({'tasks': [for (final t in _remote.values) t.toJson()], 'updateTimes': _updateTimes});

  void _saveOutbox() {
    _outboxFile.write([for (final o in _outbox) o.toJson()]);
    pending.value = _outbox.length;
  }

  void _enqueue(Op op) {
    _outbox = [..._outbox.where((o) => o.id != op.id), op]; // the latest write for a task supersedes earlier ones
    _saveOutbox();
    _emit();
    unawaited(refresh());
  }

  // ---- sync -----------------------------------------------------------------------------------

  void _start(Duration poll) {
    _timer = Timer.periodic(poll, (_) => refresh());
    _lifecycle = AppLifecycleListener(onResume: refresh);
    unawaited(refresh());
  }

  /// Push the outbox, then pull. Never throws for connectivity problems: they leave the outbox and cache as they were.
  /// Calls made while a sync is running share it (and trigger one more pass, so late writes aren't missed).
  Future<void> refresh() {
    if (_current != null) {
      _again = true;
      return _current!;
    }
    return _current = (() async {
      do {
        _again = false;
        try {
          await _flush();
          await _pull();
        } on Exception catch (e) {
          debugPrint('sync deferred: $e'); // offline, 5xx, signed out...
        }
      } while (_again);
    })()
        .whenComplete(() => _current = null);
  }

  String get _docs => '$_host/v1/projects/$_project/databases/(default)/documents';
  String get _collection => '$_docs/users/$_uid/tasks';
  String _name(String id) => 'projects/$_project/databases/(default)/documents/users/$_uid/tasks/$id';

  Future<http.Response> _send(Future<http.Response> Function(Map<String, String> headers) call) async {
    Map<String, String> headers(String t) => {'Authorization': 'Bearer $t', 'Content-Type': 'application/json'};
    var r = await call(headers(await _idToken())).timeout(const Duration(seconds: 20));
    if (r.statusCode == 401) r = await call(headers(await _idToken(forceRefresh: true))).timeout(const Duration(seconds: 20));
    return r;
  }

  Future<http.Response> _commit(Map<String, Object?> write) =>
      _send((h) => _client.post(Uri.parse('$_docs:commit'), headers: h, body: jsonEncode({'writes': [write]})));

  Map<String, Object?> _upsertWrite(Task t, {String? ifUpdateTime}) => {
        // `updatedAt` is stamped by the server so last-write-wins doesn't depend on device clocks.
        'update': {'name': _name(t.id), 'fields': {...toFirestoreFields(t)}..remove('updatedAt')},
        'updateTransforms': [
          {'fieldPath': 'updatedAt', 'setToServerValue': 'REQUEST_TIME'}
        ],
        if (ifUpdateTime != null) 'currentDocument': {'updateTime': ifUpdateTime},
      };

  Future<void> _flush() async {
    for (final op in [..._outbox]) {
      if (op.delete) {
        final r = await _commit({'delete': _name(op.id)});
        if (r.statusCode == 200) {
          _remote.remove(op.id);
          _updateTimes.remove(op.id);
          _done(op);
          continue;
        }
        _failed(op, r);
        continue;
      }
      var r = await _commit(_upsertWrite(op.task!, ifUpdateTime: _updateTimes[op.id]));
      if (r.statusCode != 200 && _isConflict(r)) {
        // Someone else changed it since we last looked: the later edit wins.
        final current = await _send((h) => _client.get(Uri.parse('$_collection/${op.id}'), headers: h));
        if (current.statusCode == 200) {
          final remote = fromFirestoreDoc((jsonDecode(current.body) as Map).cast<String, Object?>());
          if (remote.updatedAt.isAfter(op.at)) {
            _done(op); // theirs is newer: drop ours, the pull will bring theirs in
            continue;
          }
        }
        r = await _commit(_upsertWrite(op.task!)); // ours is newer (or theirs is gone): overwrite
      }
      if (r.statusCode == 200) {
        final results = (jsonDecode(r.body) as Map)['writeResults'] as List?;
        final t = results?.firstOrNull is Map ? (results!.first as Map)['updateTime'] as String? : null;
        if (t != null) _updateTimes[op.id] = t;
        _remote[op.id] = op.task!;
        _done(op);
      } else {
        _failed(op, r);
      }
    }
  }

  bool _isConflict(http.Response r) => r.statusCode == 409 || r.body.contains('FAILED_PRECONDITION');

  void _done(Op op) {
    _outbox = _outbox.where((o) => !identical(o, op)).toList();
    _saveOutbox();
    _saveTasks();
    _emit();
  }

  /// 5xx / 429 / 408: try again later (stop this pass). Any other 4xx can never succeed, so drop the write.
  void _failed(Op op, http.Response r) {
    final s = r.statusCode;
    if (s >= 500 || s == 429 || s == 408) throw HttpException('HTTP $s');
    debugPrint('dropping rejected write for ${op.id}: HTTP $s ${r.body}');
    _done(op);
  }

  Future<void> _pull() async {
    final remote = <String, Task>{};
    final times = <String, String>{};
    String? page;
    do {
      final uri = Uri.parse('$_collection?pageSize=300${page == null ? '' : '&pageToken=${Uri.encodeQueryComponent(page)}'}');
      final r = await _send((h) => _client.get(uri, headers: h));
      if (r.statusCode != 200) throw HttpException('list failed: HTTP ${r.statusCode}');
      final body = (jsonDecode(r.body) as Map).cast<String, Object?>();
      for (final d in (body['documents'] as List? ?? const [])) {
        final doc = (d as Map).cast<String, Object?>();
        final t = fromFirestoreDoc(doc);
        remote[t.id] = t;
        if (doc['updateTime'] is String) times[t.id] = doc['updateTime'] as String;
      }
      page = body['nextPageToken'] as String?;
    } while (page != null && page.isNotEmpty);
    _remote = remote;
    _updateTimes = times;
    _saveTasks();
    _emit();
  }
}
