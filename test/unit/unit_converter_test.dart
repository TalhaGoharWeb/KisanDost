import 'package:flutter_test/flutter_test.dart';

import 'package:kisan_dost/services/unit_converter.dart';

/// Unit tests for the central [UnitConverter].
///
/// These encode the farmer-safety rules: no hardcoded package weights,
/// maund = 40 kg, and loud failures (never silent wrong numbers) for
/// impossible conversions.
void main() {
  group('UnitConverter.convert', () {
    test('identity conversion returns the quantity untouched', () {
      expect(UnitConverter.convert(5, 'بوری', 'بوری'), 5);
      expect(UnitConverter.convert(5, 'Bag', 'بوری'), 5);
      // Identity needs no package weight.
      expect(UnitConverter.convert(3, 'بوری', 'بوری'), 3);
    });

    test('same-family weight math', () {
      expect(UnitConverter.convert(1, 'کلوگرام', 'گرام'), 1000);
      expect(UnitConverter.convert(1000, 'گرام', 'کلوگرام'), 1);
      expect(UnitConverter.convert(1, 'ٹن', 'کلوگرام'), 1000);
      expect(UnitConverter.convert(2.5, 'KG', 'کلوگرام'), 2.5);
      expect(UnitConverter.convert(500, 'گرام', 'کلو'), 0.5);
    });

    test('maund is 40 kg (Pakistani standard)', () {
      expect(UnitConverter.maundInKg, 40.0);
      expect(UnitConverter.convert(1, 'من', 'کلوگرام'), 40);
      expect(UnitConverter.convert(80, 'کلوگرام', 'من'), 2);
      expect(UnitConverter.convert(1, 'Maund', 'گرام'), 40000);
    });

    test('same-family volume math', () {
      expect(UnitConverter.convert(1, 'لیٹر', 'ملی لیٹر'), 1000);
      expect(UnitConverter.convert(250, 'ملی', 'لیٹر'), 0.25);
    });

    test('package to weight with the farmer-declared weight', () {
      expect(
        UnitConverter.convert(2, 'بوری', 'کلوگرام', weightPerUnitKg: 50),
        100,
      );
      expect(
        UnitConverter.convert(100, 'کلوگرام', 'بوری', weightPerUnitKg: 50),
        2,
      );
      // A 25 kg bag converts differently — the weight is per item.
      expect(
        UnitConverter.convert(2, 'بوری', 'کلوگرام', weightPerUnitKg: 25),
        50,
      );
    });

    test('package conversion without a declared weight throws loudly', () {
      expect(
        () => UnitConverter.convert(2, 'بوری', 'کلوگرام'),
        throwsA(isA<UnitConversionException>()),
      );
      expect(
        () => UnitConverter.convert(2, 'بوری', 'کلوگرام', weightPerUnitKg: 0),
        throwsA(isA<UnitConversionException>()),
      );
    });

    test('cross-family conversion throws', () {
      expect(
        () => UnitConverter.convert(1, 'کلوگرام', 'لیٹر'),
        throwsA(isA<UnitConversionException>()),
      );
      expect(
        () => UnitConverter.convert(1, 'عدد', 'کلوگرام'),
        throwsA(isA<UnitConversionException>()),
      );
      expect(
        () => UnitConverter.convert(1, 'بوری', 'بوتل'),
        throwsA(isA<UnitConversionException>()),
      );
    });

    test('unknown unit throws', () {
      expect(
        () => UnitConverter.convert(1, 'foo', 'کلوگرام'),
        throwsA(isA<UnitConversionException>()),
      );
      expect(
        () => UnitConverter.convert(1, 'کلوگرام', 'bar'),
        throwsA(isA<UnitConversionException>()),
      );
    });
  });

  group('UnitConverter.isPackageUnit', () {
    test('package units are detected across aliases', () {
      expect(UnitConverter.isPackageUnit('بوری'), isTrue);
      expect(UnitConverter.isPackageUnit('Bag'), isTrue);
      expect(UnitConverter.isPackageUnit('بوتل'), isTrue);
      expect(UnitConverter.isPackageUnit('پیکٹ'), isTrue);
    });

    test('non-package units return false', () {
      expect(UnitConverter.isPackageUnit('کلوگرام'), isFalse);
      expect(UnitConverter.isPackageUnit('لیٹر'), isFalse);
      expect(UnitConverter.isPackageUnit('من'), isFalse);
      expect(UnitConverter.isPackageUnit('عدد'), isFalse);
      expect(UnitConverter.isPackageUnit('nonsense'), isFalse);
    });
  });
}
