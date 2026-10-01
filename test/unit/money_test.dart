import 'package:flutter_test/flutter_test.dart';
import 'package:kisan_dost/services/money.dart';

void main() {
  group('Money.parse', () {
    test('parses plain western digits', () {
      expect(Money.parse('1250').paisa, 125000);
    });

    test('parses decimals up to 2 places', () {
      expect(Money.parse('1250.5').paisa, 125050);
      expect(Money.parse('1250.50').paisa, 125050);
      expect(Money.parse('0.99').paisa, 99);
    });

    test('accepts Urdu/Persian digits', () {
      expect(Money.parse('۱۲۵۰').paisa, 125000);
      expect(Money.parse('۱۲۵۰.۵۰').paisa, 125050);
    });

    test('strips commas, spaces, currency words', () {
      expect(Money.parse('1,250').paisa, 125000);
      expect(Money.parse('1,250 روپے').paisa, 125000);
      expect(Money.parse('Rs 1,250.50').paisa, 125050);
      expect(Money.parse('  2500  ').paisa, 250000);
    });

    test('rejects empty input', () {
      expect(() => Money.parse(''), throwsA(isA<MoneyParseException>()));
      expect(() => Money.parse('   '), throwsA(isA<MoneyParseException>()));
    });

    test('rejects garbage', () {
      expect(() => Money.parse('abc'), throwsA(isA<MoneyParseException>()));
      expect(() => Money.parse('12.5.3'), throwsA(isA<MoneyParseException>()));
      expect(() => Money.parse('12,34,56-'), throwsA(isA<MoneyParseException>()));
    });

    test('rejects negative amounts', () {
      expect(() => Money.parse('-500'), throwsA(isA<MoneyParseException>()));
    });

    test('rejects more than 2 decimals instead of rounding', () {
      // 10.999 must NOT silently become 11.00.
      expect(
          () => Money.parse('10.999'), throwsA(isA<MoneyParseException>()));
      expect(
          () => Money.parse('10.001'), throwsA(isA<MoneyParseException>()));
    });

    test('error messages are Urdu', () {
      try {
        Money.parse('xyz');
        fail('should have thrown');
      } on MoneyParseException catch (e) {
        expect(e.message, isNotEmpty);
        // Contains Urdu characters (Arabic block).
        expect(RegExp(r'[\u0600-\u06FF]').hasMatch(e.message), isTrue);
      }
    });
  });

  group('Money arithmetic stays exact', () {
    test('0.1 + 0.2 style sums are exact in paisa', () {
      // The classic double failure: 0.1 + 0.2 = 0.30000000000000004.
      // In paisa: 10 + 20 = 30 exactly.
      final sum = Money.fromPaisa(10) + Money.fromPaisa(20);
      expect(sum.paisa, 30);
      expect(sum, Money.fromRupees(0.3));
    });

    test('repeated small additions do not drift', () {
      var total = Money.zero;
      for (var i = 0; i < 1000; i++) {
        total = total + Money.fromPaisa(1);
      }
      expect(total.paisa, 1000);
    });

    test('subtraction and int multiplication', () {
      expect((Money.fromPaisa(1000) - Money.fromPaisa(333)).paisa, 667);
      expect((Money.fromPaisa(333) * 3).paisa, 999);
      expect((-Money.fromPaisa(50)).paisa, -50);
    });

    test('comparisons', () {
      expect(Money.fromPaisa(100) < Money.fromPaisa(200), isTrue);
      expect(Money.fromPaisa(200) > Money.fromPaisa(100), isTrue);
      expect(Money.fromPaisa(100) <= Money.fromPaisa(100), isTrue);
      expect(Money.zero.isZero, isTrue);
      expect(Money.fromPaisa(-5).isNegative, isTrue);
    });

    test('fromRupees rounds half away from zero', () {
      expect(Money.fromRupees(10.999).paisa, 1100);
      expect(Money.fromRupees(0.005).paisa, 1);
      expect(Money.fromRupees(2.5).paisa, 250);
    });
  });

  group('Money.format', () {
    test('whole rupees get thousands separators, no decimals', () {
      expect(Money.fromPaisa(125000).format(), '1,250 روپے');
      expect(Money.fromPaisa(10000000).format(), '100,000 روپے');
      expect(Money.zero.format(), '0 روپے');
    });

    test('paisa remainder shows exactly 2 decimals', () {
      expect(Money.fromPaisa(125050).format(), '1,250.50 روپے');
      expect(Money.fromPaisa(99).format(), '0.99 روپے');
    });

    test('negative amounts', () {
      expect(Money.fromPaisa(-125000).format(), '-1,250 روپے');
    });
  });
}
