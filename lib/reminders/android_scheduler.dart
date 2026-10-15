import 'dart:ui' show Color;

import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_timezone/flutter_timezone.dart';
import 'package:timezone/data/latest_all.dart' as tz;
import 'package:timezone/timezone.dart' as tz;

import 'mark_done_handler.dart';
import 'reminder_scheduler.dart';

const markDoneActionId = 'mark_done';

class AndroidNotificationPort implements NotificationPort {
  AndroidNotificationPort([FlutterLocalNotificationsPlugin? plugin]) : _plugin = plugin ?? FlutterLocalNotificationsPlugin();

  final FlutterLocalNotificationsPlugin _plugin;

  Future<void> init() async {
    tz.initializeTimeZones();
    await _syncTimezone();
    await _plugin.initialize(
      const InitializationSettings(android: AndroidInitializationSettings('ic_notification')),
      onDidReceiveNotificationResponse: handleNotificationResponse,
      onDidReceiveBackgroundNotificationResponse: onNotificationResponseBackground,
    );
    // The app was started by tapping a reminder.
    final launch = await _plugin.getNotificationAppLaunchDetails();
    final response = launch?.notificationResponse;
    if ((launch?.didNotificationLaunchApp ?? false) && response != null) handleNotificationResponse(response);
  }

  /// Times are wall-clock, so they must be interpreted in whatever timezone the device is in right now.
  Future<void> _syncTimezone() async => tz.setLocalLocation(tz.getLocation(await FlutterTimezone.getLocalTimezone()));

  Future<bool> requestPermission() async {
    final android = _plugin.resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>();
    return await android?.requestNotificationsPermission() ?? false;
  }

  @override
  Future<void> cancelAll() async {
    await _syncTimezone(); // start of every reconcile: picks up a timezone change
    await _plugin.cancelAll();
  }

  @override
  Future<void> schedule({required int id, required DateTime at, required String title, required String body, required String payload}) async {
    final when = tz.TZDateTime(tz.local, at.year, at.month, at.day, at.hour, at.minute);
    if (!when.isAfter(tz.TZDateTime.now(tz.local))) return;
    await _plugin.zonedSchedule(
      id,
      title,
      body,
      when,
      const NotificationDetails(
        android: AndroidNotificationDetails(
          'reminders',
          'Reminders',
          channelDescription: 'Task reminders',
          icon: 'ic_notification',
          color: Color(0xFFBC452B), // the app's clay
          importance: Importance.high,
          priority: Priority.high,
          actions: [AndroidNotificationAction(markDoneActionId, 'Mark done', cancelNotification: true)],
        ),
      ),
      androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
      payload: payload,
    );
  }
}
