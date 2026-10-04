// Unit tests for lib/utils/error_messages.dart (crash-safety audit 2026-10-04).
//
// The farmer must never see raw technical errors. These tests pin that:
// every failure kind maps to a non-empty Urdu message, and the raw error
// text never leaks into the user-facing string.
import 'package:flutter_test/flutter_test.dart';
import 'package:kisan_dost/utils/error_messages.dart';

void main() {
  group('urduMessageFor', () {
    test('every FailureKind has a non-empty Urdu message', () {
      for (final kind in FailureKind.values) {
        final msg = urduMessageFor(kind);
        expect(msg, isNotEmpty, reason: 'empty message for $kind');
        // Urdu text should be present (Arabic block range).
        expect(
          RegExp(r'[\u0600-\u06FF]').hasMatch(msg),
          isTrue,
          reason: 'no Urdu text for $kind: $msg',
        );
      }
    });

    test('messages contain no obvious technical leakage markers', () {
      for (final kind in FailureKind.values) {
        final msg = urduMessageFor(kind).toLowerCase();
        expect(msg.contains('exception'), isFalse);
        expect(msg.contains('stacktrace'), isFalse);
        expect(msg.contains('.dart'), isFalse);
      }
    });
  });

  group('guessKind', () {
    test('classifies sqlite errors as database', () {
      expect(
        guessKind(Exception('DatabaseException(no such table: foo)')),
        FailureKind.database,
      );
    });

    test('classifies disk-full as storage', () {
      expect(
        guessKind(Exception('FileSystemException: No space left on device')),
        FailureKind.storage,
      );
    });

    test('classifies denial as permission', () {
      expect(
        guessKind(Exception('permission denied by user')),
        FailureKind.permission,
      );
    });

    test('falls back to unknown', () {
      expect(guessKind(Exception('something weird')), FailureKind.unknown);
    });
  });

  group('friendlyErrorMessage', () {
    test('never includes the raw error text', () {
      const raw = 'DatabaseException(SECRET_PATH/db.sqlite, code 14)';
      final msg = friendlyErrorMessage(Exception(raw), FailureKind.database);
      expect(msg.contains('SECRET_PATH'), isFalse);
      expect(msg.contains('code 14'), isFalse);
      expect(msg, urduMessageFor(FailureKind.database));
    });
  });
}
