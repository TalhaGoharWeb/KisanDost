// Unit tests for lock-screen notification redaction (owner decision #7).
//
// Tests the pure content builder only — actual notification display needs a
// real device (NOT verified here).
import 'package:flutter_test/flutter_test.dart';
import 'package:kisan_dost/l10n/strings.dart';
import 'package:kisan_dost/services/notification_service.dart';

void main() {
  // A realistic sensitive task title: party name + amount.
  const sensitiveTitle = 'احمد کو 5000 روپے دینے ہیں';

  group('AlarmNotificationContent.build — redacted default (showDetails: false)', () {
    test('uses generic actionable title/body, not the task title', () {
      final content = AlarmNotificationContent.build(
        taskTitle: sensitiveTitle,
        reminderSuffix: '',
        showDetails: false,
      );
      expect(content.title, Strings.alarmRedactedTitle);
      expect(content.body, Strings.alarmRedactedBody);
    });

    test('leaks no sensitive details (party name / amount)', () {
      final content = AlarmNotificationContent.build(
        taskTitle: sensitiveTitle,
        reminderSuffix: ' (1 گھنٹہ پہلے)',
        showDetails: false,
      );
      expect(content.title.contains('احمد'), isFalse);
      expect(content.title.contains('5000'), isFalse);
      expect(content.body.contains('احمد'), isFalse);
      expect(content.body.contains('5000'), isFalse);
      expect(content.body.contains(sensitiveTitle), isFalse);
    });

    test('redaction ignores the reminder suffix (generic text always)', () {
      final content = AlarmNotificationContent.build(
        taskTitle: sensitiveTitle,
        reminderSuffix: ' (سنوز)',
        showDetails: false,
      );
      expect(content.title, Strings.alarmRedactedTitle);
      expect(content.body, Strings.alarmRedactedBody);
    });
  });

  group('AlarmNotificationContent.build — details mode (showDetails: true)', () {
    test('restores previous behavior: brand title + task title body', () {
      final content = AlarmNotificationContent.build(
        taskTitle: sensitiveTitle,
        reminderSuffix: '',
        showDetails: true,
      );
      expect(content.title, 'کسان دوست - یاد دہانی');
      expect(content.body, sensitiveTitle);
    });

    test('keeps the reminder suffix in details mode', () {
      for (final entry in {
        ' (1 گھنٹہ پہلے)': 'کسان دوست - یاد دہانی (1 گھنٹہ پہلے)',
        ' (1 دن پہلے)': 'کسان دوست - یاد دہانی (1 دن پہلے)',
        ' (سنوز)': 'کسان دوست - یاد دہانی (سنوز)',
      }.entries) {
        final content = AlarmNotificationContent.build(
          taskTitle: sensitiveTitle,
          reminderSuffix: entry.key,
          showDetails: true,
        );
        expect(content.title, entry.value);
        expect(content.body, sensitiveTitle);
      }
    });
  });
}
