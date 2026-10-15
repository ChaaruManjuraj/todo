// On-device check of the real Android notification path (and the "Mark done" action's handler).
//   adb shell pm grant com.chaaru.todo android.permission.POST_NOTIFICATIONS   # once, after the first install
//   firebase emulators:exec --only firestore,auth --project todo-ba12a \
//     "adb reverse tcp:8085 tcp:8085 && adb reverse tcp:9099 tcp:9099 && \
//      flutter test integration_test/reminders_test.dart -d <device> --dart-define=EMULATOR_HOST=LOCALHOST"
// Without EMULATOR_HOST the Firestore-backed group is skipped. See firestore_repo_test.dart for why "LOCALHOST".
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:todo/data/firestore_repo.dart';
import 'package:todo/domain/schedule.dart';
import 'package:todo/domain/task.dart';
import 'package:todo/firebase_options.dart';
import 'package:todo/reminders/android_scheduler.dart';
import 'package:todo/reminders/mark_done_handler.dart';
import 'package:todo/reminders/reminder_scheduler.dart';

const emulatorHost = String.fromEnvironment('EMULATOR_HOST');

Task mk(String id, DateTime at, {String name = 'Water the plants'}) {
  final now = DateTime.now().toUtc();
  return Task(id: id, name: name, startDate: fmtDate(at), startTime: '${at.hour.toString().padLeft(2, '0')}:${at.minute.toString().padLeft(2, '0')}', reminder: true, createdAt: now, updatedAt: now);
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  final port = AndroidNotificationPort();
  final plugin = FlutterLocalNotificationsPlugin();

  setUpAll(() => port.init());
  tearDown(() => plugin.cancelAll());

  testWidgets('reconcile arms both reminders with the OS and cancelAll clears them', (t) async {
    final at = DateTime.now().add(const Duration(days: 2));
    await reconcile([mk('arm1', at, name: 'Buy milk')], DateTime.now(), port);
    final pending = await plugin.pendingNotificationRequests();
    expect(pending.map((p) => p.id).toSet(), {notificationId('arm1', 0), notificationId('arm1', 1)});
    expect(pending.every((p) => p.title == 'Buy milk' && p.payload == 'arm1'), isTrue);

    await reconcile([], DateTime.now(), port);
    expect(await plugin.pendingNotificationRequests(), isEmpty);
  });

  testWidgets('editing the start time replaces the armed reminder', (t) async {
    final first = DateTime.now().add(const Duration(days: 2));
    await reconcile([mk('edit1', first)], DateTime.now(), port);
    await reconcile([mk('edit1', first.add(const Duration(hours: 3)))], DateTime.now(), port);
    expect((await plugin.pendingNotificationRequests()).length, 2);
  });

  testWidgets('a reminder actually fires at its minute, showing the task name', (t) async {
    final now = DateTime.now();
    final at = DateTime(now.year, now.month, now.day, now.hour, now.minute).add(const Duration(minutes: 2));
    await reconcile([mk('fire1', at, name: 'Take the bins out')], now, port);
    expect((await plugin.pendingNotificationRequests()).map((p) => p.id), contains(notificationId('fire1', 0)));

    final id = notificationId('fire1', 0);
    ActiveNotification? shown;
    final deadline = DateTime.now().add(const Duration(minutes: 3, seconds: 30));
    while (shown == null && DateTime.now().isBefore(deadline)) {
      await Future<void>.delayed(const Duration(seconds: 3));
      shown = (await plugin.getActiveNotifications()).where((n) => n.id == id).firstOrNull;
    }
    expect(shown, isNotNull, reason: 'the notification never appeared');
    expect(shown!.title, 'Take the bins out');
    expect(shown.body, 'Due');
    // it fired once; the next-day reminder is still armed
    expect((await plugin.pendingNotificationRequests()).map((p) => p.id), contains(notificationId('fire1', 1)));
  }, timeout: const Timeout(Duration(minutes: 5)));

  group('"Mark done" action', skip: emulatorHost.isEmpty ? 'needs the emulators (EMULATOR_HOST unset)' : false, () {
    late FirestoreRepo repo;

    setUpAll(() async {
      await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
      FirebaseFirestore.instance.useFirestoreEmulator(emulatorHost, 8085);
      await FirebaseAuth.instance.useAuthEmulator(emulatorHost, 9099);
      repo = FirestoreRepo((await FirebaseAuth.instance.signInAnonymously()).user!.uid);
    });

    testWidgets('marks the task done in Firestore and cancels both of its notifications', (t) async {
      final at = DateTime.now().add(const Duration(days: 2));
      final task = mk('md1', at);
      await repo.upsert(task);
      await reconcile([task], DateTime.now(), port);
      expect((await plugin.pendingNotificationRequests()).length, 2);

      await markTaskDone('md1');

      final done = (await repo.watch().firstWhere((l) => l.any((x) => x.id == 'md1' && x.done)).timeout(const Duration(seconds: 10))).firstWhere((x) => x.id == 'md1');
      expect(done.done, isTrue);
      expect(done.doneAt, isNotNull);
      expect(await plugin.pendingNotificationRequests(), isEmpty, reason: 'the next-day reminder must be cancelled too');
    });

    testWidgets('a task deleted in the meantime is not an error', (t) async {
      await markTaskDone('never-existed');
    });
  });
}
