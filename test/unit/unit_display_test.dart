import 'package:flutter_test/flutter_test.dart';
import 'package:kisan_dost/services/unit_display.dart';

void main() {
  group('UnitDisplay.allUnits', () {
    test('is the union of the legacy harvest and inventory lists', () {
      // Harvest offered: من کلوگرام ٹن بوری کسٹم.
      // Inventory offered: بوری کلوگرام لیٹر بوتل پیکٹ گرام ملی لیٹر ٹن.
      for (final u in ['من', 'کلوگرام', 'ٹن', 'بوری', 'کسٹم']) {
        expect(UnitDisplay.allUnits, contains(u), reason: 'harvest unit $u');
      }
      for (final u in ['بوری', 'کلوگرام', 'لیٹر', 'بوتل', 'پیکٹ', 'گرام', 'ملی لیٹر', 'ٹن']) {
        expect(UnitDisplay.allUnits, contains(u), reason: 'inventory unit $u');
      }
    });

    test('has no duplicates', () {
      expect(UnitDisplay.allUnits.toSet().length, UnitDisplay.allUnits.length);
    });
  });

  group('UnitDisplay.format', () {
    test('trims trailing zeros without rounding', () {
      expect(UnitDisplay.format(40.0, 'من'), '40 من');
      expect(UnitDisplay.format(2.5, 'کلوگرام'), '2.5 کلوگرام');
      expect(UnitDisplay.format(2.50, 'کلوگرام'), '2.5 کلوگرام');
      expect(UnitDisplay.format(0.75, 'لیٹر'), '0.75 لیٹر');
    });
  });

  group('UnitDisplay.formatWeightKg', () {
    test('whole maunds render as من (1 maund = 40 kg)', () {
      expect(UnitDisplay.formatWeightKg(40), '1 من');
      expect(UnitDisplay.formatWeightKg(80), '2 من');
      expect(UnitDisplay.formatWeightKg(400), '10 من');
    });

    test('non-maund weights render as کلوگرام', () {
      expect(UnitDisplay.formatWeightKg(50), '50 کلوگرام');
      expect(UnitDisplay.formatWeightKg(45.5), '45.5 کلوگرام');
    });

    test('sub-kilo weights render as گرام', () {
      expect(UnitDisplay.formatWeightKg(0.5), '500 گرام');
    });
  });
}
