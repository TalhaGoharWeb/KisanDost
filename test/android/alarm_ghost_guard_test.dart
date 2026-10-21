import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Regression tests for the ghost-alarm bug (owner report 2026-10-21:
/// "no task exists in the app, yet alarms and notifications keep
/// coming"). Root causes pinned here:
///
/// 1. Dart `cancelTaskNotifications` used to return right after the
///    native cancel on Android, never cancelling the task's
///    flutter_local_notifications entries. Entries scheduled by older
///    builds through the plugin (including daily/weekly repeats)
///    therefore survived every delete/complete forever.
/// 2. Nothing swept plugin notifications whose task id is unknown to
///    the current build, so legacy orphans could never be reached.
/// 3. The native AlarmReceiver rang for any AlarmManager entry,
///    trusting the intent extras without checking the task still
///    exists in the database.
///
/// These are source-pin tests (same style as manifest_security_test):
/// the behaviour spans the Android platform boundary and cannot be
/// exercised by a Dart unit test on the host.
void main() {
  late String notificationService;
  late String alarmReceiver;

  setUpAll(() {
    notificationService =
        File('lib/services/notification_service.dart').readAsStringSync();
    alarmReceiver = File(
      'android/app/src/main/kotlin/com/talhagohar/kisandost/AlarmReceiver.kt',
    ).readAsStringSync();
  });

  group('ghost-alarm fixes (2026-10-21)', () {
    test('cancelTaskNotifications cancels plugin ids before the native '
        'cancel, with no early return on Android', () {
      final fnStart = notificationService.indexOf(
        'Future<void> cancelTaskNotifications(int taskId)',
      );
      expect(fnStart, isNot(-1));
      final body = notificationService.substring(fnStart);
      final pluginCancel = body.indexOf(
        'flutterLocalNotificationsPlugin.cancel(taskId * 10 + i)',
      );
      final nativeCancel = body.indexOf("invokeMethod('cancelAlarm'");
      expect(pluginCancel, isNot(-1), reason: 'plugin cancel loop missing');
      expect(nativeCancel, isNot(-1), reason: 'native cancel missing');
      expect(
        pluginCancel,
        lessThan(nativeCancel),
        reason: 'plugin entries must be cancelled first, on all platforms',
      );
      // The old Android early return must not come back inside this
      // function (it skipped the plugin cancels entirely).
      final fnEnd = body.indexOf('Future<void>', 10);
      final fnBody = fnEnd == -1 ? body : body.substring(0, fnEnd);
      expect(
        fnBody.contains("if (Platform.isAndroid) {\n        try {\n          await _nativeChannel"),
        isFalse,
        reason: 'Android branch must not wrap-and-return before plugin cancel',
      );
    });

    test('orphaned plugin notifications are swept at startup', () {
      expect(
        notificationService.contains('sweepOrphanedPluginNotifications'),
        isTrue,
      );
      expect(
        notificationService.contains('pendingNotificationRequests()'),
        isTrue,
      );
      expect(
        notificationService.contains(
          'await sweepOrphanedPluginNotifications();',
        ),
        isTrue,
        reason: 'initialize() must run the sweep on every launch',
      );
    });

    test('AlarmReceiver refuses to ring for a missing/completed task', () {
      final guard = alarmReceiver.indexOf('Ghost-alarm guard');
      expect(guard, isNot(-1), reason: 'DB guard missing in AlarmReceiver');
      final serviceStart = alarmReceiver.indexOf('startForegroundService');
      expect(serviceStart, isNot(-1));
      expect(
        guard,
        lessThan(serviceStart),
        reason: 'the guard must run before AlarmService is started',
      );
      expect(alarmReceiver.contains('guardTask == null'), isTrue);
      expect(
        alarmReceiver.contains('AlarmScheduler.cancelAlarmsForTask'),
        isTrue,
        reason: 'a ghost fire must cancel the task\u2019s remaining alarms',
      );
    });
  });
}
