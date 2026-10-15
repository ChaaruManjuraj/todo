import 'package:flutter_test/flutter_test.dart';
import 'package:todo/domain/schedule.dart';
import 'package:todo/domain/task.dart';
import 'package:todo/reminders/background_sync.dart';

import 'reconcile_test.dart' show FakePort;

final t0 = DateTime.utc(2026, 10, 1);
final now = DateTime(2026, 10, 15, 11, 0);
Task mk(String id, {bool reminder = true}) =>
    Task(id: id, name: 'task $id', startDate: '2026-10-20', startTime: '10:00', reminder: reminder, createdAt: t0, updatedAt: t0);

void main() {
  test('signed in: arms the reminders of every task it loaded', () async {
    final port = FakePort();
    await syncReminders(load: () async => [mk('a'), mk('b', reminder: false)], port: port, now: now);
    expect(port.scheduled.keys.toSet(), {notificationId('a', 0), notificationId('a', 1)});
  });

  test('signed out: does nothing at all (no cancel, no schedule)', () async {
    final port = FakePort()..scheduled[7] = (at: now, title: 'existing', body: '', payload: 'x');
    await syncReminders(load: () async => null, port: port, now: now);
    expect(port.log, isEmpty);
    expect(port.scheduled.keys, [7]);
  });

  test('a failed load propagates (so WorkManager retries) and leaves existing alarms alone', () async {
    final port = FakePort()..scheduled[7] = (at: now, title: 'existing', body: '', payload: 'x');
    await expectLater(syncReminders(load: () async => throw Exception('offline'), port: port, now: now), throwsException);
    expect(port.log, isEmpty);
    expect(port.scheduled.keys, [7]);
  });

  test('a genuinely empty account clears stale alarms', () async {
    final port = FakePort()..scheduled[7] = (at: now, title: 'stale', body: '', payload: 'x');
    await syncReminders(load: () async => [], port: port, now: now);
    expect(port.scheduled, isEmpty);
  });

  test('tasks that are done or already past are not armed', () async {
    final port = FakePort();
    final done = mk('done').copyWith(done: true);
    final past = mk('past').copyWith(startDate: '2026-10-01');
    await syncReminders(load: () async => [done, past], port: port, now: now);
    expect(port.scheduled, isEmpty);
  });
}
