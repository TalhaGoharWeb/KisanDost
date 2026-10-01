import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/data/latest.dart' as tz;
import 'package:timezone/timezone.dart' as tz;
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:typed_data';
import 'dart:io';
import 'package:flutter/services.dart';
import '../providers/task_provider.dart';
import '../database/db_helper.dart';
import '../screens/alarm_screen.dart';
import '../l10n/strings.dart';

@pragma('vm:entry-point')
void notificationTapBackground(
  NotificationResponse notificationResponse,
) async {
  WidgetsFlutterBinding.ensureInitialized();

  final payload = notificationResponse.payload;
  final actionId = notificationResponse.actionId;

  if (payload == null) return;
  final taskId = int.tryParse(payload);
  if (taskId == null) return;

  if (actionId == 'action_complete') {
    final db = await DatabaseHelper.instance.database;
    await db.update(
      'tasks',
      {'is_completed': 1, 'snoozed_until': null},
      // A soft-deleted task ignores notification actions.
      where: 'id = ? AND deleted_at IS NULL',
      whereArgs: [taskId],
    );

    // Cancel all notifications for this task (including reminders/snooze)
    final flutterLocalNotificationsPlugin = FlutterLocalNotificationsPlugin();
    for (int i = 0; i < 10; i++) {
      await flutterLocalNotificationsPlugin.cancel(taskId * 10 + i);
    }
  } else if (actionId == 'action_snooze') {
    final db = await DatabaseHelper.instance.database;

    // Get snooze duration from preferences
    final prefs = await SharedPreferences.getInstance();
    final snoozeDuration = prefs.getInt('snooze_duration') ?? 10;
    final playSound = prefs.getBool('alarm_sound_enabled') ?? true;
    final enableVibration = prefs.getBool('vibration_enabled') ?? true;

    final snoozeTime = DateTime.now().add(Duration(minutes: snoozeDuration));

    await db.update(
      'tasks',
      {'snoozed_until': snoozeTime.toIso8601String()},
      where: 'id = ?',
      whereArgs: [taskId],
    );

    final List<Map<String, dynamic>> maps = await db.query(
      'tasks',
      // A soft-deleted task ignores notification actions.
      where: 'id = ? AND deleted_at IS NULL',
      whereArgs: [taskId],
    );

    if (maps.isNotEmpty) {
      final taskTitle = maps.first['title'] as String;

      tz.initializeTimeZones();
      try {
        tz.setLocalLocation(tz.getLocation('Asia/Karachi'));
      } catch (e) {
        debugPrint('Failed to set timezone in background: $e');
      }

      final flutterLocalNotificationsPlugin = FlutterLocalNotificationsPlugin();

      // Cancel the current notification first
      await flutterLocalNotificationsPlugin.cancel(
        notificationResponse.id ?? (taskId * 10),
      );

      // Schedule a new alarm notification using slot 9 for snooze
      await flutterLocalNotificationsPlugin.zonedSchedule(
        taskId * 10 + 9,
        'کسان دوست - یاد دہانی (سوز)',
        taskTitle,
        tz.TZDateTime.from(snoozeTime, tz.local),
        NotificationDetails(
          android: AndroidNotificationDetails(
            'kisan_dost_alarm_channel_v7',
            'Farming Alarms',
            channelDescription: 'Loud farming task reminders',
            importance: Importance.max,
            priority: Priority.high,
            sound:
                playSound
                    ? const RawResourceAndroidNotificationSound('farming_alarm')
                    : null,
            playSound: playSound,
            enableVibration: enableVibration,
            audioAttributesUsage: AudioAttributesUsage.alarm,
            additionalFlags: Int32List.fromList(<int>[
              4,
            ]), // FLAG_INSISTENT for continuous loop
            ongoing: true,
            autoCancel: false,
            fullScreenIntent: true,
            category: AndroidNotificationCategory.alarm,
            visibility: NotificationVisibility.public,
            actions: <AndroidNotificationAction>[
              const AndroidNotificationAction(
                'action_complete',
                Strings.done,
                showsUserInterface: false,
              ),
              AndroidNotificationAction(
                'action_snooze',
                'سوز کریں ($snoozeDuration منٹ)',
                showsUserInterface: false,
              ),
            ],
          ),
        ),
        androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
        uiLocalNotificationDateInterpretation:
            UILocalNotificationDateInterpretation.absoluteTime,
        payload: taskId.toString(),
      );
    }
  }
}

class NotificationService {
  static final NotificationService _instance = NotificationService._internal();
  factory NotificationService() => _instance;
  NotificationService._internal();

  static const MethodChannel _nativeChannel = MethodChannel(
    'com.example.kisan_dost/share',
  );

  final FlutterLocalNotificationsPlugin flutterLocalNotificationsPlugin =
      FlutterLocalNotificationsPlugin();

  static String? launchPayload;
  static final GlobalKey<NavigatorState> navigatorKey =
      GlobalKey<NavigatorState>();

  Future<void> init() async {
    tz.initializeTimeZones();
    try {
      tz.setLocalLocation(tz.getLocation('Asia/Karachi'));
    } catch (e) {
      debugPrint('Failed to set timezone: $e');
    }

    const AndroidInitializationSettings initializationSettingsAndroid =
        AndroidInitializationSettings('@mipmap/ic_launcher');

    const InitializationSettings initializationSettings =
        InitializationSettings(android: initializationSettingsAndroid);

    await flutterLocalNotificationsPlugin.initialize(
      initializationSettings,
      onDidReceiveNotificationResponse: (NotificationResponse response) {
        debugPrint('Notification clicked: ${response.payload}');
        if (response.payload != null) {
          final taskId = int.tryParse(response.payload!);
          if (taskId != null) {
            if (navigatorKey.currentState != null) {
              navigatorKey.currentState!.push(
                MaterialPageRoute(builder: (_) => AlarmScreen(taskId: taskId)),
              );
            } else {
              launchPayload = response.payload;
            }
          }
        }
      },
      onDidReceiveBackgroundNotificationResponse: notificationTapBackground,
    );

    // Request permissions for Android 13+
    await flutterLocalNotificationsPlugin
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >()
        ?.requestNotificationsPermission();

    await flutterLocalNotificationsPlugin
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >()
        ?.requestExactAlarmsPermission();

    // Check if the app was launched by a notification click
    final launchDetails =
        await flutterLocalNotificationsPlugin.getNotificationAppLaunchDetails();
    if (launchDetails != null && launchDetails.didNotificationLaunchApp) {
      final payload = launchDetails.notificationResponse?.payload;
      if (payload != null) {
        launchPayload = payload;
      }
    }

    // Double-safe backup: Reschedule all active alarms on launch
    await rescheduleAllPendingAlarms();
  }

  Future<void> scheduleTaskNotifications(TaskItem task) async {
    // 1. Cancel any existing notifications for this task ID (slots 0 to 9)
    await cancelTaskNotifications(task.id);

    if (task.isCompleted) return;

    if (Platform.isAndroid) {
      final prefs = await SharedPreferences.getInstance();
      final remindersEnabled = prefs.getBool('reminders_enabled') ?? true;
      if (!remindersEnabled) {
        return;
      }
      try {
        await _nativeChannel.invokeMethod('scheduleAlarm', {'taskId': task.id});
      } catch (e) {
        debugPrint('Error scheduling native alarm: $e');
      }
      return;
    }

    // Load settings from SharedPreferences
    final prefs = await SharedPreferences.getInstance();
    final remindersEnabled = prefs.getBool('reminders_enabled') ?? true;
    if (!remindersEnabled) {
      return; // Respect settings: do not schedule alarms if disabled!
    }

    final playSound = prefs.getBool('alarm_sound_enabled') ?? true;
    final enableVibration = prefs.getBool('vibration_enabled') ?? true;
    final defaultSnooze = prefs.getInt('snooze_duration') ?? 10;

    // 2. Parse the reminder offsets (minutes before event)
    final offsets =
        task.reminders
            .split(',')
            .map((e) => int.tryParse(e.trim()))
            .whereType<int>()
            .toList();
    if (offsets.isEmpty) {
      offsets.add(0); // Default to at the event time
    }

    // 3. For each offset, schedule a notification
    for (int index = 0; index < offsets.length; index++) {
      final offsetMinutes = offsets[index];
      final triggerTime = task.dateTime.subtract(
        Duration(minutes: offsetMinutes),
      );

      // Calculate the stable sub-id for this reminder (slots 0 to 8, slot 9 is snooze)
      final notificationId = task.id * 10 + (index % 9);

      // Determine recurrence components
      DateTimeComponents? matchComponents;
      if (task.recurrence == 'daily') {
        matchComponents = DateTimeComponents.time;
      } else if (task.recurrence == 'weekly') {
        matchComponents = DateTimeComponents.dayOfWeekAndTime;
      }

      // If the trigger time is in the past and there is no recurrence, do not schedule
      if (triggerTime.isBefore(DateTime.now()) && task.recurrence == 'none') {
        continue;
      }

      // Format Urdu alert details based on offset
      String reminderSuffix = '';
      if (offsetMinutes == 60) {
        reminderSuffix = ' (1 گھنٹہ پہلے)';
      } else if (offsetMinutes == 1440) {
        reminderSuffix = ' (1 دن پہلے)';
      }

      try {
        await flutterLocalNotificationsPlugin.zonedSchedule(
          notificationId,
          'کسان دوست - یاد دہانی$reminderSuffix',
          task.title,
          tz.TZDateTime.from(triggerTime, tz.local),
          NotificationDetails(
            android: AndroidNotificationDetails(
              'kisan_dost_alarm_channel_v7',
              'Farming Alarms',
              channelDescription: 'Loud farming task reminders',
              importance: Importance.max,
              priority: Priority.high,
              sound:
                  playSound
                      ? const RawResourceAndroidNotificationSound(
                        'farming_alarm',
                      )
                      : null,
              playSound: playSound,
              enableVibration: enableVibration,
              audioAttributesUsage: AudioAttributesUsage.alarm,
              additionalFlags: Int32List.fromList(<int>[
                4,
              ]), // FLAG_INSISTENT for continuous loop
              ongoing: true,
              autoCancel: false,
              fullScreenIntent: true,
              category: AndroidNotificationCategory.alarm,
              visibility: NotificationVisibility.public,
              actions: <AndroidNotificationAction>[
                const AndroidNotificationAction(
                  'action_complete',
                  Strings.done,
                  showsUserInterface: false,
                ),
                AndroidNotificationAction(
                  'action_snooze',
                  'سوز کریں ($defaultSnooze منٹ)',
                  showsUserInterface: false,
                ),
              ],
            ),
          ),
          androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
          uiLocalNotificationDateInterpretation:
              UILocalNotificationDateInterpretation.absoluteTime,
          matchDateTimeComponents: matchComponents,
          payload: task.id.toString(),
        );
      } catch (e) {
        debugPrint(
          'PlatformException scheduling exact alarm: $e. Falling back to inexact scheduling.',
        );
        try {
          await flutterLocalNotificationsPlugin.zonedSchedule(
            notificationId,
            'کسان دوست - یاد دہانی$reminderSuffix',
            task.title,
            tz.TZDateTime.from(triggerTime, tz.local),
            NotificationDetails(
              android: AndroidNotificationDetails(
                'kisan_dost_alarm_channel_v7',
                'Farming Alarms',
                channelDescription: 'Loud farming task reminders',
                importance: Importance.max,
                priority: Priority.high,
                sound:
                    playSound
                        ? const RawResourceAndroidNotificationSound(
                          'farming_alarm',
                        )
                        : null,
                playSound: playSound,
                enableVibration: enableVibration,
                audioAttributesUsage: AudioAttributesUsage.alarm,
                additionalFlags: Int32List.fromList(<int>[4]),
                ongoing: true,
                autoCancel: false,
                fullScreenIntent: true,
                category: AndroidNotificationCategory.alarm,
                visibility: NotificationVisibility.public,
                actions: <AndroidNotificationAction>[
                  const AndroidNotificationAction(
                    'action_complete',
                    Strings.done,
                    showsUserInterface: false,
                  ),
                  AndroidNotificationAction(
                    'action_snooze',
                    'سوز کریں ($defaultSnooze منٹ)',
                    showsUserInterface: false,
                  ),
                ],
              ),
            ),
            androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
            uiLocalNotificationDateInterpretation:
                UILocalNotificationDateInterpretation.absoluteTime,
            matchDateTimeComponents: matchComponents,
            payload: task.id.toString(),
          );
        } catch (retryError) {
          debugPrint('Failed to schedule inexact fallback: $retryError');
        }
      }
    }
  }

  /// Best-effort: cancelling a reminder must NEVER break task CRUD. If the
  /// notification plugin is unavailable (or throws), the task operation
  /// still succeeds — the farmer's data matters more than the reminder.
  Future<void> cancelTaskNotifications(int taskId) async {
    try {
      if (Platform.isAndroid) {
        try {
          await _nativeChannel.invokeMethod('cancelAlarm', {'taskId': taskId});
        } catch (e) {
          debugPrint('Error cancelling native alarm: $e');
        }
        return;
      }
      for (int i = 0; i < 10; i++) {
        await flutterLocalNotificationsPlugin.cancel(taskId * 10 + i);
      }
    } catch (e) {
      debugPrint('Error cancelling task notifications: $e');
    }
  }

  Future<void> cancelNotification(int id) async {
    await flutterLocalNotificationsPlugin.cancel(id);
  }

  Future<bool> canScheduleExactAlarms() async {
    if (Platform.isAndroid) {
      try {
        return await _nativeChannel.invokeMethod('canScheduleExactAlarms') ??
            false;
      } catch (e) {
        debugPrint('Error checking exact alarm permission: $e');
      }
    }
    return true;
  }

  Future<void> requestExactAlarmPermission() async {
    if (Platform.isAndroid) {
      try {
        await _nativeChannel.invokeMethod('requestExactAlarmPermission');
      } catch (e) {
        debugPrint('Error requesting exact alarm permission: $e');
      }
    }
  }

  Future<void> rescheduleAllPendingAlarms() async {
    if (Platform.isAndroid) {
      try {
        await _nativeChannel.invokeMethod('rescheduleAllAlarms');
        debugPrint('Rescheduled all native alarms.');
      } catch (e) {
        debugPrint('Error rescheduling native alarms: $e');
      }
      return;
    }
    try {
      final db = await DatabaseHelper.instance.database;
      final List<Map<String, dynamic>> maps = await db.query(
        'tasks',
        // Soft-deleted tasks must never get alarms rescheduled.
        where: 'is_completed = ? AND deleted_at IS NULL',
        whereArgs: [0],
      );
      final List<TaskItem> pendingTasks =
          maps.map((e) => TaskItem.fromMap(e)).toList();
      for (var task in pendingTasks) {
        await scheduleTaskNotifications(task);
      }
      debugPrint('Rescheduled all pending tasks: ${pendingTasks.length}');
    } catch (e) {
      debugPrint('Failed to reschedule pending tasks on boot/init: $e');
    }
  }
}
