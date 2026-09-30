import 'package:flutter_test/flutter_test.dart';
import 'package:kisan_dost/utils/agricultural_units.dart';

void main() {
  group('AgriculturalUnits', () {
    test('converts acres, kanal, and marla using Pakistani land measures', () {
      expect(AgriculturalUnits.areaToAcres(8, 'کنال'), 1);
      expect(AgriculturalUnits.areaToAcres(160, 'مرلہ'), 1);
      expect(AgriculturalUnits.areaToAcres(4, 'kanal'), 0.5);
      expect(AgriculturalUnits.areaFromAcres(0.5, 'کنال'), 4);
    });

    test('converts maund to metric mass using 40 kg per maund', () {
      expect(AgriculturalUnits.convert(1, 'من', 'کلوگرام'), 40);
      expect(AgriculturalUnits.convert(2, 'maund', 'kg'), 80);
      expect(AgriculturalUnits.convert(1, 'ton', 'من'), 25);
      expect(
        AgriculturalUnits.convert(250, 'گرام', 'کلو'),
        closeTo(0.25, 1e-12),
      );
    });

    test('converts only like-for-like volume units', () {
      expect(AgriculturalUnits.convert(1500, 'ملی لیٹر', 'لیٹر'), 1.5);
    });

    test('does not assume every bag has the same weight', () {
      expect(
        () => AgriculturalUnits.convert(1, 'بوری', 'کلوگرام'),
        throwsArgumentError,
      );
      expect(
        () => AgriculturalUnits.convert(2, 'بوتل', 'لیٹر'),
        throwsArgumentError,
      );
    });

    test('rejects negative, NaN, and infinite inputs', () {
      expect(
        () => AgriculturalUnits.convert(-1, 'kg', 'g'),
        throwsArgumentError,
      );
      expect(
        () => AgriculturalUnits.areaToAcres(double.nan, 'acre'),
        throwsArgumentError,
      );
      expect(
        () => AgriculturalUnits.areaFromAcres(double.infinity, 'kanal'),
        throwsArgumentError,
      );
    });
  });
}
