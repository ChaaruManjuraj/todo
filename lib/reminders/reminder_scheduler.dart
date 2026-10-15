import 'dart:async';

import 'package:flutter/widgets.dart';

import '../data/task_repository.dart';
import '../domain/schedule.dart';
import '../domain/task.dart';

/// The one thing that touches the OS notification system, so everything above it is testable with a fake.
abstract class NotificationPort {
  Future<void> cancelAll();
  Future<void> schedule({required int id, required DateTime at, required String title, required String body, required String payload});
}

/// A tap on a reminder asks the home screen to open that task. The home screen clears it once handled.
final notificationTaps = ValueNotifier<String?>(null);

/// Android only: shows the system permission prompt, resolving to whether notifications are allowed. Null elsewhere
/// (the reminder toggle still works on every platform, only Android fires it).
Future<bool> Function()? requestNotificationPermission;

/// Makes the scheduled notifications equal the reminder instants of every open reminder task: cancel everything, then
/// schedule everything (the set is small, so this is simpler and safer than diffing).
Future<void> reconcile(List<Task> tasks, DateTime now, NotificationPort port) async {
  await port.cancelAll();
  for (final t in tasks) {
    for (final r in reminderInstants(t, now)) {
      // the id's low bit is the slot: 0 = at the start time, 1 = the next morning
      await port.schedule(id: r.id, at: r.at, title: t.name, body: r.id.isOdd ? 'Still due' : 'Due', payload: t.id);
    }
  }
}

/// Keeps notifications in step with the repo: reconciles on every change and whenever the app comes back to the
/// foreground (which also covers a changed device timezone). Runs never overlap.
class ReminderSync {
  ReminderSync(this._repo, this._port, {DateTime Function()? now}) : _now = now ?? DateTime.now;

  final TaskRepository _repo;
  final NotificationPort _port;
  final DateTime Function() _now;

  StreamSubscription<List<Task>>? _sub;
  AppLifecycleListener? _lifecycle;
  List<Task> _tasks = const [];
  Future<void> _queue = Future.value();
  bool _stopped = false;

  /// Completes when every reconcile requested so far has finished.
  Future<void> get idle => _queue;

  void start() {
    _sub = _repo.watch().listen((t) {
      _tasks = t;
      _run();
    }, onError: (Object e) => debugPrint('reminders: watch error: $e')); // e.g. permission denied right after sign-out
    _lifecycle = AppLifecycleListener(onResume: _run);
  }

  void _run() {
    if (_stopped) return;
    _queue = _queue.then((_) async {
      if (_stopped) return;
      try {
        await reconcile(_tasks, _now(), _port); // reads the latest tasks when it actually runs
      } catch (e) {
        debugPrint('reminders: reconcile failed: $e'); // keep the queue alive for the next trigger
      }
    });
  }

  /// Stops listening. Does not cancel notifications; sign-out does that separately.
  Future<void> stop() async {
    _stopped = true;
    await _sub?.cancel();
    _lifecycle?.dispose();
    await _queue;
  }
}
