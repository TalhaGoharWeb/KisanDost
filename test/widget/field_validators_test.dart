import 'package:flutter_test/flutter_test.dart';
import 'package:kisan_dost/widgets/field_validators.dart';

/// Unit tests for the shared farmer-facing field validators.
/// Every message must stay simple Urdu — these tests pin the behavior.
void main() {
  group('FieldValidators.money', () {
    test('rejects empty', () {
      expect(FieldValidators.money(''), 'رقم درج کریں');
      expect(FieldValidators.money('   '), 'رقم درج کریں');
      expect(FieldValidators.money(null), 'رقم درج کریں');
    });

    test('accepts valid amounts incl. Urdu digits and commas', () {
      expect(FieldValidators.money('1250'), isNull);
      expect(FieldValidators.money('1,250.50'), isNull);
      expect(FieldValidators.money('۱۲۵۰'), isNull);
      expect(FieldValidators.money('1250 روپے'), isNull);
    });

    test('rejects garbage without crashing', () {
      expect(FieldValidators.money('abc'), isNotNull);
      expect(FieldValidators.money('12.34.56'), isNotNull);
      expect(FieldValidators.money('-500'), isNotNull);
      expect(FieldValidators.money('12.345'), isNotNull); // 3 decimals
    });

    test('rejects absurd values that would overflow int.parse', () {
      // 30 digits: Money.parse would throw a raw FormatException here.
      final huge = '9' * 30;
      final msg = FieldValidators.money(huge);
      expect(msg, isNotNull);
      expect(msg, contains('بہت بڑی'));
      // No exception escapes:
      expect(() => FieldValidators.money(huge), returnsNormally);
    });

    test('positive flag rejects zero', () {
      expect(FieldValidators.money('0', positive: true), isNotNull);
      expect(FieldValidators.money('100', positive: true), isNull);
    });

    test('tryMoney never throws', () {
      expect(FieldValidators.tryMoney('500'), isNotNull);
      expect(FieldValidators.tryMoney('xyz'), isNull);
      expect(FieldValidators.tryMoney('9' * 30), isNull);
      expect(() => FieldValidators.tryMoney('9' * 30), returnsNormally);
    });
  });

  group('FieldValidators.quantity', () {
    test('rejects empty, zero, negatives when positive', () {
      expect(FieldValidators.quantity(''), isNotNull);
      expect(FieldValidators.quantity('0'), isNotNull);
      expect(FieldValidators.quantity('-5'), isNotNull);
      expect(FieldValidators.quantity('2.5'), isNull);
      expect(FieldValidators.quantity('۴۰'), isNull);
    });

    test('rejects malformed and absurd values', () {
      expect(FieldValidators.quantity('abc'), isNotNull);
      expect(FieldValidators.quantity('1.2.3'), isNotNull);
      final huge = FieldValidators.quantity('9' * 40);
      expect(huge, isNotNull);
      expect(huge, contains('بہت بڑی'));
    });

    test('respects custom max', () {
      expect(
        FieldValidators.quantity('200000', max: 100000),
        contains('بہت بڑی'),
      );
      expect(FieldValidators.quantity('50000', max: 100000), isNull);
    });
  });

  group('FieldValidators.wholeCount', () {
    test('requires a whole number in range', () {
      expect(FieldValidators.wholeCount(''), isNotNull);
      expect(FieldValidators.wholeCount('abc'), isNotNull);
      expect(FieldValidators.wholeCount('2.5'), isNotNull);
      expect(FieldValidators.wholeCount('0'), isNotNull);
      expect(FieldValidators.wholeCount('5'), isNull);
      expect(
        FieldValidators.wholeCount('200', max: 120),
        contains('بہت زیادہ'),
      );
    });
  });

  group('FieldValidators.text', () {
    test('rejects empty and overly long names', () {
      expect(FieldValidators.text(''), isNotNull);
      expect(FieldValidators.text('   '), isNotNull);
      expect(FieldValidators.text('علی'), isNull);
      expect(FieldValidators.text('x' * 201), contains('لمبا'));
    });
  });

  group('FieldValidators.percent', () {
    test('accepts 0-100 only', () {
      expect(FieldValidators.percent(''), isNotNull);
      expect(FieldValidators.percent('50'), isNull);
      expect(FieldValidators.percent('0'), isNull);
      expect(FieldValidators.percent('100'), isNull);
      expect(FieldValidators.percent('-1'), isNotNull);
      expect(FieldValidators.percent('101'), isNotNull);
      expect(FieldValidators.percent('abc'), isNotNull);
    });
  });

  group('FieldValidators.phoneOptional', () {
    test('empty is fine; garbage numbers rejected', () {
      expect(FieldValidators.phoneOptional(''), isNull);
      expect(FieldValidators.phoneOptional('03001234567'), isNull);
      expect(FieldValidators.phoneOptional('+92 300 1234567'), isNull);
      expect(FieldValidators.phoneOptional('123'), isNotNull);
      expect(FieldValidators.phoneOptional('not a phone'), isNotNull);
    });
  });

  group('digitCount', () {
    test('counts western and urdu digits', () {
      expect(FieldValidators.digitCount('1,250.50'), 6);
      expect(FieldValidators.digitCount('۱۲۵۰'), 4);
      expect(FieldValidators.digitCount('abc'), 0);
    });
  });
}
