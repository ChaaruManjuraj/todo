import 'dart:ui';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';
import 'package:workmanager/workmanager.dart';

import '../data/firestore_repo.dart';
import '../domain/task.dart';
import '../firebase_options.dart';
import 'android_scheduler.dart';
import 'reminder_scheduler.dart';

const reminderSyncTask = 'todo.reminders.sync';
const reminderSyncUniqueName = 'reminder-sync';

/// Every 15 minutes (Android's minimum) when the phone has a network, so a reminder created on another device is
/// armed here without opening the app.
Future<void> registerReminderSync() async {
  await Workmanager().initialize(callbackDispatcher, isInDebugMode: false);
  await Workmanager().registerPeriodicTask(
    reminderSyncUniqueName,
    reminderSyncTask,
    frequency: const Duration(minutes: 15),
    constraints: Constraints(networkType: NetworkType.connected),
    existingWorkPolicy: ExistingWorkPolicy.keep,
  );
}

/// Runs in the background isolate WorkManager starts (hence the entry-point pragma).
@pragma('vm:entry-point')
void callbackDispatcher() {
  Workmanager().executeTask((task, input) async {
    DartPluginRegistrant.ensureInitialized();
    try {
      await syncRemindersInBackground();
      return true;
    } catch (e) {
      debugPrint('reminder sync failed, will retry: $e');
      return false; // WorkManager retries with backoff
    }
  });
}

/// One sync pass. [load] returns the user's tasks, or null when nobody is signed in (then there is nothing to do:
/// sign-out already cleared the notifications). If [load] throws, nothing is touched, so the alarms already armed
/// survive a failed sync.
Future<void> syncReminders({required Future<List<Task>?> Function() load, required NotificationPort port, required DateTime now}) async {
  final tasks = await load();
  if (tasks == null) {
    debugPrint('reminder sync: signed out, nothing to do');
    return;
  }
  await reconcile(tasks, now, port);
  debugPrint('reminder sync: ${tasks.length} tasks reconciled');
}

/// [syncReminders] wired to Firebase and the Android notification port. The parameters exist for tests.
Future<void> syncRemindersInBackground({FirebaseAuth? auth, FirebaseFirestore? db, NotificationPort? port, DateTime Function()? now}) async {
  if (Firebase.apps.isEmpty) await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
  var p = port;
  if (p == null) {
    final android = AndroidNotificationPort();
    await android.init();
    p = android;
  }
  await syncReminders(
    port: p,
    now: (now ?? DateTime.now)(),
    load: () async {
      final a = auth ?? FirebaseAuth.instance;
      final user = a.currentUser ?? await a.authStateChanges().first; // waits for the saved session to load
      if (user == null) return null;
      // Server only: offline must fail (and retry), not fall back to a possibly empty cache that would wipe every alarm.
      final snap = await (db ?? FirebaseFirestore.instance).collection('users/${user.uid}/tasks').get(const GetOptions(source: Source.server));
      return [for (final d in snap.docs) taskFromFirestore(d.id, d.data())];
    },
  );
}
