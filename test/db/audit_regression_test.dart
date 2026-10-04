import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Source-structure regression tests for audit fixes whose runtime behavior
/// lives in Kotlin or behind unmockable plugins. Each test asserts the fix
/// is present in the source tree; removing the fix breaks the test.
///
/// These complement (not replace) behavioral tests: they are cheap,
/// deterministic, and catch accidental reversions of security fixes.
void main() {
  late String taskProvider;
  late String alarmScheduler;
  late String alarmReceiver;
  late String alarmService;
  late String kotlinDbHelper;
  late String mainActivityKt;
  late String dartDbHelper;

  setUpAll(() {
    String read(String path) {
      final file = File(path);
      expect(file.existsSync(), isTrue, reason: 'missing: $path');
      return file.readAsStringSync();
    }

    taskProvider = read('lib/providers/task_provider.dart');
    alarmScheduler = read(
        'android/app/src/main/kotlin/com/talhagohar/kisandost/AlarmScheduler.kt');
    alarmReceiver = read(
        'android/app/src/main/kotlin/com/talhagohar/kisandost/AlarmReceiver.kt');
    alarmService = read(
        'android/app/src/main/kotlin/com/talhagohar/kisandost/AlarmService.kt');
    kotlinDbHelper = read(
        'android/app/src/main/kotlin/com/talhagohar/kisandost/DatabaseHelper.kt');
    mainActivityKt = read(
        'android/app/src/main/kotlin/com/talhagohar/kisandost/MainActivity.kt');
    dartDbHelper = read('lib/database/db_helper.dart');
  });

  group('alarm audit regressions (2026-10-04)', () {
    test('F2: restoreTask re-arms the task alarm', () {
      // The restoreTask method body must call scheduleTaskNotifications.
      final idx = taskProvider.indexOf('Future<void> restoreTask');
      expect(idx, isNot(-1));
      final nextMethod =
          taskProvider.indexOf('Future<void> permanentDeleteTask', idx);
      final body = taskProvider.substring(idx, nextMethod);
      expect(
        body.contains('scheduleTaskNotifications'),
        isTrue,
        reason:
            'F2 regression: restoreTask must re-arm alarms or restored tasks stay silent',
      );
    });

    test('F1: boot reschedule honors the reminders toggle', () {
      expect(
        alarmScheduler.contains('reminders_enabled'),
        isTrue,
        reason:
            'F1 regression: rescheduleAllAlarms must not re-arm disabled reminders',
      );
    });

    test('F3: native snooze honors the snooze_duration setting', () {
      expect(
        alarmReceiver.contains('snooze_duration'),
        isTrue,
        reason: 'F3 regression: snooze must not be hardcoded to 10 minutes',
      );
      expect(
        alarmService.contains('snooze_duration'),
        isTrue,
        reason: 'F3 regression: notification label must reflect the setting',
      );
    });

    test('F4: native complete/snooze ignore soft-deleted rows', () {
      final completeIdx = kotlinDbHelper.indexOf('fun completeTask');
      final snoozeIdx = kotlinDbHelper.indexOf('fun snoozeTask');
      expect(completeIdx, isNot(-1));
      expect(snoozeIdx, isNot(-1));
      expect(
        kotlinDbHelper.substring(completeIdx, completeIdx + 800).contains(
            'deleted_at IS NULL'),
        isTrue,
        reason: 'F4 regression: completeTask must not touch trashed rows',
      );
      expect(
        kotlinDbHelper.substring(snoozeIdx, snoozeIdx + 800).contains(
            'deleted_at IS NULL'),
        isTrue,
        reason: 'F4 regression: snoozeTask must not touch trashed rows',
      );
    });

    test('F5: AlarmService releases the old player before starting a new one',
        () {
      final idx = alarmService.indexOf('private fun playAlarmSound');
      expect(idx, isNot(-1));
      final body = alarmService.substring(idx, idx + 1200);
      expect(
        body.contains('mediaPlayer?.release()') ||
            body.contains('mediaPlayer?.stop()'),
        isTrue,
        reason: 'F5 regression: overlapping alarms must not leak MediaPlayer',
      );
    });
  });

  group('lock-screen bypass regression (native audit F1, HIGH)', () {
    test('MainActivity.onCreate never shows over the lock screen', () {
      // Strip // comments: the fix left an explanatory comment naming the
      // removed calls, which must not trip the assertion.
      final code = mainActivityKt
          .split('\n')
          .where((line) => !line.trimLeft().startsWith('//'))
          .join('\n');
      expect(
        code.contains('setShowWhenLocked(true)'),
        isFalse,
        reason:
            'HIGH regression: MainActivity must not bypass the lock screen',
      );
      expect(
        code.contains('setTurnScreenOn(true)'),
        isFalse,
      );
      expect(
        code.contains('FLAG_DISMISS_KEYGUARD'),
        isFalse,
      );
    });
  });

  group('delete-all regression (2026-10-04)', () {
    test('clearTables runs inside a transaction', () {
      final idx = dartDbHelper.indexOf('static Future<void> clearTables');
      expect(idx, isNot(-1));
      final body = dartDbHelper.substring(idx, idx + 600);
      expect(
        body.contains('transaction'),
        isTrue,
        reason:
            'regression: the wipe must be all-or-nothing, never half-deleted',
      );
    });
  });

  group('restore hardening regressions (2026-10-04)', () {
    test('restoreReplace stages through a temp file (atomic)', () {
      final src = File('lib/services/restore_service.dart').readAsStringSync();
      expect(
        src.contains('.restore_tmp'),
        isTrue,
        reason:
            'regression: restore must not copy directly over the live database',
      );
    });

    test('backup hashing streams the file (no whole-file read)', () {
      final src = File('lib/services/backup_service.dart').readAsStringSync();
      expect(
        src.contains('_sha256OfFile'),
        isTrue,
        reason: 'regression: hashing must stream, not readAsBytes',
      );
    });
  });
}
