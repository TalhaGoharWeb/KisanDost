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
import '../l10n/strings.dart';

/// Background notification-action handler. Runs in a separate isolate with
/// no UI: it must NEVER throw — an unhandled error here is silent and the
/// farmer's tap simply does nothing. (Crash-safety audit 2026-10-04.)
@pragma('vm:entry-point')
void notificationTapBackground(
  NotificationResponse notificationResponse,
) async {
  try {
    await _notificationTapBackgroundUnsafe(notificationResponse);
  } catch (e) {
    debugPrint('KisanDost: background notification action failed: $e');
  }
}

Future<void> _notificationTapBackgroundUnsafe(
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
      final showDetails = prefs.getBool('lockscreen_show_details') ?? false;
      final snoozeContent = AlarmNotificationContent.build(
        taskTitle: taskTitle,
        reminderSuffix: ' (سنوز)',
        showDetails: showDetails,
      );
      await flutterLocalNotificationsPlugin.zonedSchedule(
        taskId * 10 + 9,
        snoozeContent.title,
        snoozeContent.body,
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
                'سنوز کریں ($snoozeDuration منٹ)',
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

/// Lock-screen redaction for alarm notifications (owner decision #7,
/// 2026-10-18).
///
/// The notification body carries the farmer's free-text task title, which
/// routinely holds sensitive details (amounts owed/received, party names,
/// financial titles). By default the notification is REDACTED: a generic,
/// actionable title/body that reveals nothing about the task. Enabling the
/// «لاک اسکرین پر تفصیل» settings toggle restores the task title.
///
/// Pure and unit-testable: no plugin, no prefs, no platform code — the
/// caller reads the `lockscreen_show_details` preference and passes the
/// boolean in. (SharedPreferences in the background isolate and on the
/// native side use the same key with default `false`.)
///
/// Visibility semantics: we keep `NotificationVisibility.public` even when
/// redacted. `secret` is NOT the right semantic here — it hides the
/// notification from a secure lock screen entirely (no "clear and
/// actionable" reminder). `private` would show only the app name. Once the
/// text itself is redacted there is no sensitive content left to protect,
/// so `public` with generic text is exactly what the owner asked for:
/// title «یاد دہانی» / body «کام کا وقت ہو گیا — کھولنے کے لیے
/// تھپتھپائیں». When the toggle is on, `public` restores the previous
/// behavior (task title visible).
class AlarmNotificationContent {
  final String title;
  final String body;

  const AlarmNotificationContent({required this.title, required this.body});

  static AlarmNotificationContent build({
    required String taskTitle,
    required String reminderSuffix,
    required bool showDetails,
  }) {
    if (showDetails) {
      return AlarmNotificationContent(
        title: 'کسان دوست - یاد دہانی$reminderSuffix',
        body: taskTitle,
      );
    }
    // Redacted default: generic and actionable, no task details.
    return const AlarmNotificationContent(
      title: Strings.alarmRedactedTitle,
      body: Strings.alarmRedactedBody,
    );
  }
}

class NotificationService {
  static final NotificationService _instance = NotificationService._internal();
  factory NotificationService() => _instance;
  NotificationService._internal();

  static const MethodChannel _nativeChannel = MethodChannel(
    'com.talhagohar.kisandost/share',
  );

  final FlutterLocalNotificationsPlugin flutterLocalNotificationsPlugin =
      FlutterLocalNotificationsPlugin();

  static String? launchPayload;
  static final GlobalKey<NavigatorState> navigatorKey =
      GlobalKey<NavigatorState>();

  /// Initializes notifications. NEVER throws: if anything here fails
  /// (missing plugin, channel error, permission API crash), the app must
  /// still launch — the farmer's data matters more than reminders.
  /// (Crash-safety audit 2026-10-04.)
  Future<void> init() async {
    try {
      await _initUnsafe();
    } catch (e) {
      debugPrint('KisanDost: notification init failed, continuing: $e');
    }
  }

  /// Requests notification + exact-alarm permissions. MUST be called after
  /// the Flutter UI is attached (e.g. from SplashScreen's post-frame
  /// callback) — calling before runApp() silently shows no dialog on
  /// Android 13+. Safe to call repeatedly; the system only prompts once.
  /// (Alarm diagnostic 2026-10-04.)
  Future<void> requestPermissions() async {
    try {
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
    } catch (e) {
      debugPrint('KisanDost: permission request failed: $e');
    }
  }

  Future<void> _initUnsafe() async {
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
        // S12: the FLN alarm UI (AlarmScreen) was removed — on Android all
        // alarms are delivered by the native stack (AlarmActivity), so an
        // FLN tap has no screen to open. The payload is stashed for
        // diagnostics only.
        launchPayload = response.payload;
      },
      onDidReceiveBackgroundNotificationResponse: notificationTapBackground,
    );

    // NOTE: Runtime permission requests (notification, exact alarm) are NOT
    // requested here. They must run after the Flutter UI is attached —
    // requesting from main() before runApp() silently fails on Android 13+
    // because there is no Activity to host the dialog. SplashScreen calls
    // NotificationService().requestPermissions() once the first frame is up.
    // (Alarm diagnostic 2026-10-04.)

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
    // Owner decision #7: lock-screen redaction, default off (redacted).
    final showDetails = prefs.getBool('lockscreen_show_details') ?? false;

    // 2. Parse the reminder offsets (minutes before event)
    final offsets =
        task.reminders
            .split(',')
            .map((e) => int.tryParse(e.trim()))
            .whereType<int>()
            .toList();
    if (offsets.isEmpty) {
      // No reminders set by the user — do NOT schedule any alarm.
      // (Bug fix 2026-10-19: previously defaulted to offset 0, causing
      // alarms for tasks where the user set no reminder.)
      return;
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

      // Apply lock-screen redaction (owner decision #7): the body is the
      // farmer's free-text task title, so it is replaced with generic text
      // unless the farmer opted in to lock-screen details.
      final content = AlarmNotificationContent.build(
        taskTitle: task.title,
        reminderSuffix: reminderSuffix,
        showDetails: showDetails,
      );

      try {
        await flutterLocalNotificationsPlugin.zonedSchedule(
          notificationId,
          content.title,
          content.body,
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
                  'سنوز کریں ($defaultSnooze منٹ)',
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
            content.title,
            content.body,
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
                    'سنوز کریں ($defaultSnooze منٹ)',
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

  /// Best-effort: cancelling one notification must never throw.
  /// (Crash-safety audit 2026-10-04.)
  Future<void> cancelNotification(int id) async {
    try {
      await flutterLocalNotificationsPlugin.cancel(id);
    } catch (e) {
      debugPrint('KisanDost: cancelNotification($id) failed: $e');
    }
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

  /// Diagnostic: asks the native side to schedule a synthetic alarm 15
  /// seconds in the future, bypassing the database. Returns true when the
  /// native scheduler accepted it. Used by the Settings "Test Alarm" button
  /// to isolate native alarm delivery from task storage on the user's device.
  Future<bool> scheduleTestAlarm() async {
    if (!Platform.isAndroid) return false;
    try {
      final ok = await _nativeChannel.invokeMethod('scheduleTestAlarm');
      return ok == true;
    } catch (e) {
      debugPrint('Error scheduling test alarm: $e');
      return false;
    }
  }

  /// Returns true when the app may launch the full-screen alarm activity
  /// over the lock screen (Android 14+ requires an explicit user grant).
  Future<bool> canUseFullScreenIntent() async {
    if (!Platform.isAndroid) return true;
    try {
      return await _nativeChannel.invokeMethod('canUseFullScreenIntent') ??
          false;
    } catch (e) {
      debugPrint('Error checking full-screen intent permission: $e');
      return false;
    }
  }

  /// Opens the system settings page where the user grants the full-screen
  /// intent permission (Android 14+).
  Future<void> requestFullScreenIntentPermission() async {
    if (!Platform.isAndroid) return;
    try {
      await _nativeChannel.invokeMethod('requestFullScreenIntentPermission');
    } catch (e) {
      debugPrint('Error requesting full-screen intent permission: $e');
    }
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
