import 'package:flutter_test/flutter_test.dart';
import 'package:kisan_dost/services/quantity.dart';

void main() {
  group('Quantity.parse', () {
    test('parses plain western digits and decimals', () {
      expect(Quantity.parse('40'), 40.0);
      expect(Quantity.parse('2.5'), 2.5);
      expect(Quantity.parse('0.5'), 0.5);
    });

    test('accepts Urdu/Persian digits', () {
      expect(Quantity.parse('۱۲۳'), 123.0);
      expect(Quantity.parse('۲.۵'), 2.5);
    });

    test('accepts thousands separators and spaces', () {
      expect(Quantity.parse('1,000'), 1000.0);
      expect(Quantity.parse('  40 '), 40.0);
    });

    test('throws Urdu error on empty input', () {
      expect(
        () => Quantity.parse(''),
        throwsA(
          isA<QuantityParseException>().having(
            (e) => e.message,
            'message',
            'مقدار درج کریں',
          ),
        ),
      );
      expect(
        () => Quantity.parse('   '),
        throwsA(isA<QuantityParseException>()),
      );
    });

    test('throws Urdu error on garbage', () {
      expect(
        () => Quantity.parse('abc'),
        throwsA(isA<QuantityParseException>()),
      );
      expect(
        () => Quantity.parse('12.5.3'),
        throwsA(isA<QuantityParseException>()),
      );
    });

    test('allows zero and negatives in the base parse', () {
      expect(Quantity.parse('0'), 0.0);
      expect(Quantity.parse('-5'), -5.0);
    });
  });

  group('Quantity.parsePositive', () {
    test('accepts positive values', () {
      expect(Quantity.parsePositive('40'), 40.0);
      expect(Quantity.parsePositive('۲.۵'), 2.5);
    });

    test('rejects zero and negatives with Urdu error', () {
      expect(
        () => Quantity.parsePositive('0'),
        throwsA(isA<QuantityParseException>()),
      );
      expect(
        () => Quantity.parsePositive('-3'),
        throwsA(isA<QuantityParseException>()),
      );
      try {
        Quantity.parsePositive('0');
        fail('should have thrown');
      } on QuantityParseException catch (e) {
        expect(e.message, 'مقدار صفر سے زیادہ ہونی چاہیے');
      }
    });

    test('rejects empty and garbage', () {
      expect(
        () => Quantity.parsePositive(''),
        throwsA(isA<QuantityParseException>()),
      );
      expect(
        () => Quantity.parsePositive('xyz'),
        throwsA(isA<QuantityParseException>()),
      );
    });
  });

  group('Quantity.tryParse', () {
    test('returns null instead of throwing', () {
      expect(Quantity.tryParse('40'), 40.0);
      expect(Quantity.tryParse('۱۲۳'), 123.0);
      expect(Quantity.tryParse(''), isNull);
      expect(Quantity.tryParse('abc'), isNull);
    });
  });
}
