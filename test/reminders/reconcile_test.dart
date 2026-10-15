import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:todo/app.dart';
import 'package:todo/data/memory_repo.dart';
import 'package:todo/domain/schedule.dart';
import 'package:todo/domain/task.dart';
import 'package:todo/reminders/mark_done_handler.dart';
import 'package:todo/reminders/reminder_scheduler.dart';
import 'package:todo/ui/clock.dart';
import 'package:todo/ui/task_detail.dart';
import 'package:todo/ui/theme_controller.dart';

typedef Scheduled = ({DateTime at, String title, String body, String payload});

class FakePort implements NotificationPort {
  final scheduled = <int, Scheduled>{};
  final log = <String>[];
  Duration delay = Duration.zero;
  Object? failOnce;

  @override
  Future<void> cancelAll() async {
    log.add('cancel');
    await Future<void>.delayed(delay);
    scheduled.clear();
  }

  @override
  Future<void> schedule({required int id, required DateTime at, required String title, required String body, required String payload}) async {
    log.add('schedule $id');
    await Future<void>.delayed(delay);
    final f = failOnce;
    if (f != null) {
      failOnce = null;
      throw f;
    }
    scheduled[id] = (at: at, title: title, body: body, payload: payload);
  }
}

final t0 = DateTime.utc(2026, 10, 1);
final now = DateTime(2026, 10, 15, 11, 0);

Task mk(String id, {String? date = '2026-10-20', String? time = '10:00', bool reminder = true, bool done = false, String? name}) =>
    Task(id: id, name: name ?? 'task $id', startDate: date, startTime: time, reminder: reminder, done: done, createdAt: t0, updatedAt: t0);

Set<int> idsOf(String taskId) => {notificationId(taskId, 0), notificationId(taskId, 1)};

void main() {
  group('reconcile', () {
    test('schedules the start and the next-day reminder with the task as the payload', () async {
      final port = FakePort();
      await reconcile([mk('a', name: 'Buy milk')], now, port);
      expect(port.scheduled.keys.toSet(), idsOf('a'));
      final start = port.scheduled[notificationId('a', 0)]!;
      final next = port.scheduled[notificationId('a', 1)]!;
      expect(start.at, DateTime(2026, 10, 20, 10));
      expect(next.at, DateTime(2026, 10, 21, 9));
      expect([start.title, start.body, start.payload], ['Buy milk', 'Due', 'a']);
      expect([next.title, next.body, next.payload], ['Buy milk', 'Still due', 'a']);
    });

    test('a date-only reminder fires at 09:00, and the next-day one crosses the month end', () async {
      final port = FakePort();
      await reconcile([mk('a', date: '2026-10-31', time: null)], now, port);
      expect(port.scheduled[notificationId('a', 0)]!.at, DateTime(2026, 10, 31, 9));
      expect(port.scheduled[notificationId('a', 1)]!.at, DateTime(2026, 11, 1, 9));
    });

    test('cancels everything first, exactly once, then schedules', () async {
      final port = FakePort();
      await reconcile([mk('a'), mk('b')], now, port);
      expect(port.log.first, 'cancel');
      expect(port.log.where((e) => e == 'cancel').length, 1);
      expect(port.log.length, 5);
    });

    test('done tasks, tasks without a reminder, undated tasks and past instants get nothing', () async {
      final port = FakePort();
      await reconcile([
        mk('done', done: true),
        mk('off', reminder: false),
        mk('undated', date: null, time: null),
        mk('past', date: '2026-10-01'),
      ], now, port);
      expect(port.scheduled, isEmpty);
    });

    test('only the instants still in the future are scheduled', () async {
      final port = FakePort();
      await reconcile([mk('a', date: '2026-10-15', time: '10:00')], now, port); // start passed, next morning ahead
      expect(port.scheduled.keys.toSet(), {notificationId('a', 1)});
    });

    test('no tasks still clears any stale notifications', () async {
      final port = FakePort()..scheduled[1] = (at: now, title: 'old', body: '', payload: 'x');
      await reconcile([], now, port);
      expect(port.scheduled, isEmpty);
    });

    test('an edited start time replaces the old schedule', () async {
      final port = FakePort();
      await reconcile([mk('a', time: '10:00')], now, port);
      await reconcile([mk('a', time: '15:30')], now, port);
      expect(port.scheduled[notificationId('a', 0)]!.at, DateTime(2026, 10, 20, 15, 30));
      expect(port.scheduled.length, 2);
    });

    test("a deleted task's notifications are gone", () async {
      final port = FakePort();
      await reconcile([mk('a'), mk('b')], now, port);
      await reconcile([mk('b')], now, port);
      expect(port.scheduled.keys.toSet(), idsOf('b'));
    });
  });

  group('ReminderSync', () {
    late MemoryRepo repo;
    late FakePort port;
    late DateTime clock;

    setUp(() {
      repo = MemoryRepo([mk('a')]);
      port = FakePort();
      clock = now;
    });

    ReminderSync startSync() => ReminderSync(repo, port, now: () => clock)..start();

    testWidgets('reconciles on the first load and after every change', (tester) async {
      await tester.runAsync(() async {
        final sync = startSync(); // inside runAsync: its timers must use real time, not the test's fake clock
        await Future<void>.delayed(Duration.zero);
        await sync.idle;
        expect(port.scheduled.keys.toSet(), idsOf('a'));
        await repo.upsert(mk('b'));
        await Future<void>.delayed(Duration.zero);
        await sync.idle;
        expect(port.scheduled.keys.toSet(), {...idsOf('a'), ...idsOf('b')});
        await sync.stop();
      });
    });

    testWidgets('completing cancels the reminders and Undo brings them back', (tester) async {
      await tester.runAsync(() async {
        final sync = startSync(); // inside runAsync: its timers must use real time, not the test's fake clock
        await Future<void>.delayed(Duration.zero);
        await repo.upsert(mk('a', done: true));
        await Future<void>.delayed(Duration.zero);
        await sync.idle;
        expect(port.scheduled, isEmpty);
        await repo.upsert(mk('a')); // Undo
        await Future<void>.delayed(Duration.zero);
        await sync.idle;
        expect(port.scheduled.keys.toSet(), idsOf('a'));
        await sync.stop();
      });
    });

    testWidgets('coming back to the app reconciles again, with the new "now"', (tester) async {
      await tester.runAsync(() async {
        final sync = startSync(); // inside runAsync: its timers must use real time, not the test's fake clock
        await Future<void>.delayed(Duration.zero);
        await sync.idle;
        expect(port.scheduled.length, 2);
        clock = DateTime(2026, 10, 20, 12, 0); // the start instant has passed while the app was in the background
        tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
        tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
        await sync.idle;
        expect(port.scheduled.keys.toSet(), {notificationId('a', 1)});
        await sync.stop();
      });
    });

    testWidgets('after stop() nothing is reconciled any more', (tester) async {
      await tester.runAsync(() async {
        final sync = startSync(); // inside runAsync: its timers must use real time, not the test's fake clock
        await Future<void>.delayed(Duration.zero);
        await sync.stop();
        final before = List.of(port.log);
        await repo.upsert(mk('b'));
        await Future<void>.delayed(Duration.zero);
        tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
        tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
        await Future<void>.delayed(Duration.zero);
        expect(port.log, before);
      });
    });

    testWidgets('runs never overlap: a burst of changes ends with exactly the latest set', (tester) async {
      port.delay = const Duration(milliseconds: 5); // slow port: overlapping runs would interleave cancel/schedule
      await tester.runAsync(() async {
        final sync = startSync(); // inside runAsync: its timers must use real time, not the test's fake clock
        await Future<void>.delayed(Duration.zero);
        await repo.upsert(mk('b'));
        await repo.upsert(mk('c'));
        await repo.delete('a');
        await Future<void>.delayed(Duration.zero);
        await sync.idle;
        expect(port.scheduled.keys.toSet(), {...idsOf('b'), ...idsOf('c')});
        // every run is a cancel followed by its own schedules: a "cancel" never lands between two schedules of one run
        var runs = 0;
        for (final e in port.log) {
          if (e == 'cancel') runs++;
        }
        expect(runs, greaterThanOrEqualTo(2));
        await sync.stop();
      });
    });

    testWidgets('a failing port does not stop later reconciles', (tester) async {
      port.failOnce = Exception('boom');
      await tester.runAsync(() async {
        final sync = startSync(); // inside runAsync: its timers must use real time, not the test's fake clock
        await Future<void>.delayed(Duration.zero);
        await sync.idle;
        await repo.upsert(mk('b'));
        await Future<void>.delayed(Duration.zero);
        await sync.idle;
        expect(port.scheduled.keys.toSet(), {...idsOf('a'), ...idsOf('b')});
        await sync.stop();
      });
    });
  });

  group('tapping a reminder / permission prompt', () {
    final fakeNow = DateTime(2026, 10, 15, 11, 0);

    Future<void> pumpHome(WidgetTester tester, List<Task> tasks, {Size size = const Size(400, 900)}) async {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      SharedPreferences.setMockInitialValues({});
      await tester.pumpWidget(TodoApp(repo: MemoryRepo(tasks), clock: Clock(now: () => fakeNow, tick: null), theme: await ThemeController.load()));
      await tester.pump();
    }

    tearDown(() {
      notificationTaps.value = null;
      requestNotificationPermission = null;
    });

    testWidgets('tapping the notification opens that task and clears the request', (tester) async {
      await pumpHome(tester, [mk('a'), mk('b')]);
      notificationTaps.value = 'b';
      await tester.pumpAndSettle();
      expect(find.byType(TaskDetail), findsOneWidget);
      expect(tester.widget<TaskDetail>(find.byType(TaskDetail)).task.id, 'b');
      expect(notificationTaps.value, isNull);
    });

    testWidgets('a tap that launched the app is honoured once the list has loaded', (tester) async {
      notificationTaps.value = 'a'; // set before the app is even built (cold start)
      await pumpHome(tester, [mk('a')]);
      await tester.pumpAndSettle();
      expect(find.byType(TaskDetail), findsOneWidget);
      expect(notificationTaps.value, isNull);
    });

    testWidgets('a tap for a task that no longer exists is ignored', (tester) async {
      await pumpHome(tester, [mk('a')]);
      notificationTaps.value = 'gone';
      await tester.pumpAndSettle();
      expect(find.byType(TaskDetail), findsNothing);
    });

    test('the foreground handler turns a notification tap into an open request', () {
      handleNotificationResponse(const NotificationResponse(notificationResponseType: NotificationResponseType.selectedNotification, payload: 'a'));
      expect(notificationTaps.value, 'a');
    });

    Future<int> openAndToggleReminder(WidgetTester tester, {required Future<bool> Function()? ask}) async {
      var asked = 0;
      requestNotificationPermission = ask == null
          ? null
          : () {
              asked++;
              return ask();
            };
      await pumpHome(tester, [mk('a', reminder: false)]);
      await tester.tap(find.text('task a'));
      await tester.pumpAndSettle();
      await tester.tap(find.byType(Switch));
      await tester.pumpAndSettle();
      return asked;
    }

    testWidgets('turning a reminder on asks for notification permission', (tester) async {
      final asked = await openAndToggleReminder(tester, ask: () async => true);
      expect(asked, 1);
      expect(find.textContaining('Notifications are blocked'), findsNothing);
    });

    testWidgets('denied permission leaves the reminder on but warns it will not fire', (tester) async {
      await openAndToggleReminder(tester, ask: () async => false);
      expect(tester.widget<Switch>(find.byType(Switch)).value, isTrue);
      expect(find.textContaining("this reminder won't fire"), findsOneWidget);
    });

    testWidgets('turning the reminder off removes the warning and does not ask again', (tester) async {
      final asked = await openAndToggleReminder(tester, ask: () async => false);
      await tester.tap(find.byType(Switch));
      await tester.pumpAndSettle();
      expect(find.textContaining('Notifications are blocked'), findsNothing);
      expect(asked, 1);
    });

    testWidgets('on platforms that cannot fire reminders nothing is asked and nothing is warned', (tester) async {
      await openAndToggleReminder(tester, ask: null);
      expect(tester.widget<Switch>(find.byType(Switch)).value, isTrue);
      expect(find.textContaining('Notifications are blocked'), findsNothing);
    });
  });
}
