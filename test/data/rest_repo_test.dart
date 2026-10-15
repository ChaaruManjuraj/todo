import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:todo/data/firestore_rest_codec.dart';
import 'package:todo/data/rest_repo.dart';
import 'package:todo/domain/task.dart';

/// Just enough of Firestore's REST API: list (paged), get, and commit with a precondition.
class FakeFirestore {
  final docs = <String, Map<String, Object?>>{}; // id -> {fields, updateTime}
  final requests = <http.Request>[];
  bool offline = false;
  int? commitStatus; // force every commit to fail with this status
  String validToken = 'old';
  int pageSize = 2;
  var serverNow = DateTime.utc(2026, 10, 15, 12);
  var _n = 0;

  void put(Task t, {DateTime? updatedAt}) {
    docs[t.id] = {
      'fields': toFirestoreFields(t.copyWith(updatedAt: updatedAt ?? t.updatedAt)),
      'updateTime': '2026-10-15T10:00:${(++_n).toString().padLeft(2, '0')}Z',
    };
  }

  Map<String, Object?> _doc(String id) => {'name': 'projects/p/databases/(default)/documents/users/u1/tasks/$id', ...docs[id]!};

  List<http.Request> get commits => requests.where((r) => r.url.path.endsWith(':commit')).toList();
  Map<String, Object?> body(http.Request r) => (jsonDecode(r.body) as Map).cast<String, Object?>();

  http.Response _json(Object? j, [int status = 200]) => http.Response(jsonEncode(j), status, headers: {'content-type': 'application/json'});

  Future<http.Response> handle(http.Request r) async {
    requests.add(r);
    if (offline) throw http.ClientException('offline');
    if (r.headers['Authorization'] != 'Bearer $validToken') return _json({'error': {'status': 'UNAUTHENTICATED'}}, 401);

    if (r.method == 'POST' && r.url.path.endsWith(':commit')) {
      if (commitStatus != null) return _json({'error': {'status': 'X'}}, commitStatus!);
      final w = ((body(r)['writes']) as List).first as Map;
      if (w['delete'] != null) {
        docs.remove((w['delete'] as String).split('/').last);
        return _json({'writeResults': [{}]});
      }
      final u = (w['update'] as Map).cast<String, Object?>();
      final id = (u['name'] as String).split('/').last;
      final pre = (w['currentDocument'] as Map?)?['updateTime'];
      if (pre != null && docs[id]?['updateTime'] != pre) return _json({'error': {'status': 'FAILED_PRECONDITION'}}, 400);
      final fields = {...(u['fields'] as Map).cast<String, Object?>()};
      for (final t in (w['updateTransforms'] as List? ?? const [])) {
        fields[(t as Map)['fieldPath'] as String] = {'timestampValue': serverNow.toIso8601String()};
      }
      docs[id] = {'fields': fields, 'updateTime': '2026-10-15T11:00:${(++_n).toString().padLeft(2, '0')}Z'};
      return _json({'writeResults': [{'updateTime': docs[id]!['updateTime']}]});
    }

    if (r.method == 'GET' && r.url.path.endsWith('/tasks')) {
      final ids = docs.keys.toList()..sort();
      final from = int.tryParse(r.url.queryParameters['pageToken'] ?? '') ?? 0;
      final page = ids.skip(from).take(pageSize).toList();
      return _json({'documents': [for (final id in page) _doc(id)], if (from + pageSize < ids.length) 'nextPageToken': '${from + pageSize}'});
    }

    if (r.method == 'GET') {
      final id = r.url.pathSegments.last;
      return docs.containsKey(id) ? _json(_doc(id)) : _json({'error': {'status': 'NOT_FOUND'}}, 404);
    }
    return _json({}, 400);
  }
}

final t0 = DateTime.utc(2026, 10, 1);
Task mk(String id, {String name = 'task'}) => Task(id: id, name: name, startDate: '2026-10-15', startTime: '10:00', createdAt: t0, updatedAt: t0);

void main() {
  late FakeFirestore fs;
  late Directory dir;
  late DateTime clock;
  late int refreshCalls;
  final opened = <RestRepo>[];

  Future<RestRepo> open({Future<String> Function({bool forceRefresh})? token}) async {
    final r = await RestRepo.open(
      client: MockClient(fs.handle),
      idToken: token ??
          ({bool forceRefresh = false}) async {
            if (forceRefresh) {
              refreshCalls++;
              return 'new';
            }
            return 'old';
          },
      cacheDir: dir,
      uid: 'u1',
      project: 'p',
      now: () => clock,
      poll: null,
    );
    opened.add(r);
    return r;
  }

  Future<List<Task>> current(RestRepo r) => r.watch().first;

  setUp(() {
    fs = FakeFirestore();
    dir = Directory.systemTemp.createTempSync('restrepo');
    clock = DateTime.utc(2026, 10, 15, 11);
    refreshCalls = 0;
  });
  tearDown(() {
    for (final r in opened) {
      r.dispose();
    }
    opened.clear();
    dir.deleteSync(recursive: true);
  });

  test('offline: a write lands in the cache at once and waits in the outbox', () async {
    fs.offline = true;
    final r = await open();
    await r.upsert(mk('a', name: 'offline task'));
    await r.refresh();
    expect((await current(r)).single.name, 'offline task');
    expect(r.pending.value, 1);
  });

  test('the outbox and cache survive a restart', () async {
    fs.offline = true;
    final r = await open();
    await r.upsert(mk('a', name: 'kept'));
    await r.refresh();
    final again = await open();
    expect(again.pending.value, 1);
    expect((await current(again)).single.name, 'kept');
  });

  test('refresh flushes the outbox: server stamps updatedAt, pending goes to 0', () async {
    final r = await open();
    await r.upsert(mk('a'));
    await r.refresh();
    expect(r.pending.value, 0);
    expect(fs.docs.keys, ['a']);
    final w = ((fs.body(fs.commits.single)['writes'] as List).single as Map);
    expect(((w['update'] as Map)['name'] as String), endsWith('users/u1/tasks/a'));
    expect(((w['update'] as Map)['fields'] as Map).containsKey('updatedAt'), isFalse);
    expect(w['updateTransforms'], [
      {'fieldPath': 'updatedAt', 'setToServerValue': 'REQUEST_TIME'}
    ]);
    expect(fs.commits.single.headers['Authorization'], 'Bearer old');
    expect((await current(r)).single.updatedAt, fs.serverNow);
  });

  test('a failed flush (5xx) keeps the outbox and the local edit; a later refresh succeeds', () async {
    fs.commitStatus = 503;
    final r = await open();
    await r.upsert(mk('a', name: 'local'));
    await r.refresh();
    expect(r.pending.value, 1);
    expect((await current(r)).single.name, 'local');
    fs.commitStatus = null;
    await r.refresh();
    expect(r.pending.value, 0);
    expect(fs.docs.keys, ['a']);
  });

  test('a write the server rejects outright (403) is dropped, not retried forever', () async {
    fs.commitStatus = 403;
    final r = await open();
    await r.upsert(mk('a'));
    await r.refresh();
    expect(r.pending.value, 0);
    expect(fs.docs, isEmpty);
  });

  test('a document deleted remotely disappears after refresh', () async {
    fs.put(mk('x'));
    final r = await open();
    await r.refresh();
    expect((await current(r)).map((t) => t.id), ['x']);
    fs.docs.remove('x');
    await r.refresh();
    expect(await current(r), isEmpty);
  });

  test('pagination is followed to the end', () async {
    for (final id in ['a', 'b', 'c', 'd', 'e']) {
      fs.put(mk(id));
    }
    final r = await open();
    await r.refresh();
    expect((await current(r)).map((t) => t.id).toSet(), {'a', 'b', 'c', 'd', 'e'});
    expect(fs.requests.where((q) => q.url.queryParameters.containsKey('pageToken')).length, 2);
  });

  test('a 401 asks for a fresh token once and retries', () async {
    fs.validToken = 'new';
    fs.put(mk('x'));
    final r = await open();
    await r.refresh();
    expect(refreshCalls, 1);
    expect((await current(r)).map((t) => t.id), ['x']);
  });

  test('a token provider that fails (signed out) does not throw and keeps the outbox', () async {
    final r = await open(token: ({bool forceRefresh = false}) async => throw Exception('signed out'));
    await r.upsert(mk('a'));
    await expectLater(r.refresh(), completes);
    expect(r.pending.value, 1);
  });

  test('delete hides the task at once and is sent when online', () async {
    fs.put(mk('a'));
    final r = await open();
    await r.refresh();
    fs.offline = true;
    await r.delete('a');
    await r.refresh();
    expect(await current(r), isEmpty);
    expect(r.pending.value, 1);
    fs.offline = false;
    await r.refresh();
    expect(r.pending.value, 0);
    expect(fs.docs, isEmpty);
  });

  test('later edits to the same task replace earlier queued ones', () async {
    fs.offline = true;
    final r = await open();
    await r.upsert(mk('a', name: 'one'));
    await r.upsert(mk('a', name: 'two'));
    await r.refresh();
    expect(r.pending.value, 1);
    expect((await current(r)).single.name, 'two');
  });

  group('conflicts: the later edit wins', () {
    Future<RestRepo> cachedWithRemoteEdit(DateTime remoteUpdatedAt) async {
      fs.put(mk('a', name: 'original'));
      final r = await open();
      await r.refresh(); // cache now holds updateTime u1
      fs.put(mk('a', name: 'remote edit'), updatedAt: remoteUpdatedAt); // someone else wrote since
      return r;
    }

    test('remote is newer than the local edit: local edit is dropped', () async {
      final r = await cachedWithRemoteEdit(DateTime.utc(2026, 10, 15, 11, 30));
      clock = DateTime.utc(2026, 10, 15, 11, 0);
      await r.upsert(mk('a', name: 'local edit'));
      await r.refresh();
      expect(r.pending.value, 0);
      expect((await current(r)).single.name, 'remote edit');
      expect(fs.docs['a'], isNotNull);
    });

    test('local edit is newer than the remote: it overwrites', () async {
      final r = await cachedWithRemoteEdit(DateTime.utc(2026, 10, 15, 9, 0));
      clock = DateTime.utc(2026, 10, 15, 11, 0);
      await r.upsert(mk('a', name: 'local edit'));
      await r.refresh();
      expect(r.pending.value, 0);
      expect((await current(r)).single.name, 'local edit');
    });
  });

  test('a corrupt cache file is ignored instead of crashing', () async {
    File('${dir.path}/tasks.json').writeAsStringSync('{not json');
    fs.put(mk('a'));
    final r = await open();
    await r.refresh();
    expect((await current(r)).map((t) => t.id), ['a']);
  });

  test('watch replays the current state and emits on change', () async {
    final r = await open();
    final seen = <int>[];
    final sub = r.watch().listen((l) => seen.add(l.length));
    await Future<void>.delayed(Duration.zero);
    await r.upsert(mk('a'));
    await r.refresh();
    await Future<void>.delayed(Duration.zero);
    expect(seen.first, 0);
    expect(seen.last, 1);
    await sub.cancel();
  });
}
