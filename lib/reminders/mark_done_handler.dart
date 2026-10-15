import 'dart:async';
import 'dart:ui';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

import '../domain/schedule.dart';
import '../firebase_options.dart';
import 'reminder_scheduler.dart';

const _markDone = 'mark_done';

/// Foreground: the "Mark done" button marks the task done, tapping the notification opens it.
void handleNotificationResponse(NotificationResponse r) {
  final id = r.payload;
  if (id == null) return;
  if (r.actionId == _markDone) {
    unawaited(markTaskDone(id));
  } else {
    notificationTaps.value = id;
  }
}

/// Background: the app isn't running, so this starts in a fresh isolate (hence the entry-point pragma).
@pragma('vm:entry-point')
Future<void> onNotificationResponseBackground(NotificationResponse r) async {
  DartPluginRegistrant.ensureInitialized();
  if (r.actionId == _markDone && r.payload != null) await markTaskDone(r.payload!);
}

/// Marks the task done in Firestore and cancels both of its notifications. Works without the UI: it initialises
/// Firebase itself and uses the signed-in user restored from disk. If the network is down the SDK keeps the write
/// and sends it the next time the app runs, so a timeout here is not a failure.
Future<void> markTaskDone(String taskId, {FirebaseFirestore? db, FirebaseAuth? auth, FlutterLocalNotificationsPlugin? plugin}) async {
  if (Firebase.apps.isEmpty) await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
  final notifications = plugin ?? FlutterLocalNotificationsPlugin();
  await notifications.cancel(notificationId(taskId, 0));
  await notifications.cancel(notificationId(taskId, 1)); // the next-day reminder: the task is done, so it shouldn't fire

  final a = auth ?? FirebaseAuth.instance;
  final user = a.currentUser ?? await a.authStateChanges().first; // waits for the saved session to load in a fresh isolate
  if (user == null) return;
  try {
    await (db ?? FirebaseFirestore.instance).doc('users/${user.uid}/tasks/$taskId').update({
      'done': true,
      'doneAt': Timestamp.now(),
      'updatedAt': FieldValue.serverTimestamp(),
    }).timeout(const Duration(seconds: 8));
  } on TimeoutException {
    debugPrint('mark done: offline, the write is queued');
  } on FirebaseException catch (e) {
    // A task deleted in the meantime reads as 'permission-denied' (the rules reject an update that would create an
    // incomplete document before Firestore can say 'not-found'). Either way there is nothing left to mark.
    if (e.code != 'not-found' && e.code != 'permission-denied') rethrow;
    debugPrint('mark done: task $taskId no longer exists (${e.code})');
  }
}
