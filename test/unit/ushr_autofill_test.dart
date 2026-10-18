import 'package:flutter_test/flutter_test.dart';

import 'package:kisan_dost/screens/ushr_screen.dart';

/// S4 regression (2026-10-18): the ushr dialog's harvest autofill must
/// convert the harvest's quantity into من for the «کل کٹائی مقدار
/// (من/Maund)» field — never copy the raw number, and never invent a
/// conversion that does not exist.
void main() {
  group('ushrAutofillMaundsText', () {
    test('80 kg harvest autofills "2" من', () {
      expect(ushrAutofillMaundsText(80, 'kg'), '2');
    });

    test('ton and gram units convert correctly', () {
      expect(ushrAutofillMaundsText(1, 'ton'), '25');
      expect(ushrAutofillMaundsText(40000, 'g'), '1');
    });

    test('maund unit passes through unchanged', () {
      expect(ushrAutofillMaundsText(7, 'من'), '7');
      expect(ushrAutofillMaundsText(2.5, 'maund'), '2.5');
    });

    test('Urdu unit aliases convert', () {
      expect(ushrAutofillMaundsText(80, 'کلو'), '2');
    });

    test('unconvertible unit (بوری/bag without a known weight) leaves the '
        'field EMPTY — never a wrong number', () {
      expect(ushrAutofillMaundsText(10, 'بوری'), '');
      expect(ushrAutofillMaundsText(10, 'bag'), '');
    });

    test('unknown custom unit leaves the field EMPTY', () {
      expect(ushrAutofillMaundsText(10, 'ٹوکری'), '');
    });

    test('a 200-kg harvest does NOT become "200 من"', () {
      expect(ushrAutofillMaundsText(200, 'kg'), isNot('200'));
      expect(ushrAutofillMaundsText(200, 'kg'), '5');
    });
  });
}
