import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:kisan_dost/database/db_helper.dart';
import 'package:kisan_dost/providers/harvest_provider.dart';

typedef SeededCrop = ({int farmId, int fieldId, int cropSeasonId});

void main() {
  setUpAll(sqfliteFfiInit);

  setUp(() async {
    await DatabaseHelper.configureForTesting(factory: databaseFactoryFfi);
  });

  tearDown(() async {
    await DatabaseHelper.resetForTesting();
  });

  Future<SeededCrop> seedCropSeason() async {
    final db = await DatabaseHelper.instance.database;
    final farmId = await db.insert('farms', {
      'name': 'Test Farm',
      'total_area': 5.0,
      'created_at': '2026-09-30',
    });
    final fieldId = await db.insert('fields', {
      'farm_id': farmId,
      'name': 'Field 1',
      'size_acres': 1.0,
      'canal_water_available': 0,
      'tube_well_available': 0,
    });
    final cropSeasonId = await db.insert('crop_seasons', {
      'field_id': fieldId,
      'crop_name': 'Wheat',
      'variety': 'Test',
      'status': 'Active',
      'start_date': '2026-09-01',
    });
    await db.insert('crop_season_fields', {
      'crop_season_id': cropSeasonId,
      'field_id': fieldId,
    });
    return (farmId: farmId, fieldId: fieldId, cropSeasonId: cropSeasonId);
  }

  test(
    'deleting the only sale resets revenue and leaves harvest expenses intact',
    () async {
      final crop = await seedCropSeason();
      final provider = HarvestProvider();
      await provider.addHarvest(
        cropSeasonId: crop.cropSeasonId,
        quantity: 10,
        unit: 'من',
        date: '2026-09-30',
        ratePerUnit: 1000,
        transportationExpense: 100,
        labourExpense: 200,
      );

      final db = await DatabaseHelper.instance.database;
      final harvestBefore = (await db.query('harvests')).single;
      expect(harvestBefore['gross_amount'], 10000.0);
      expect(harvestBefore['net_income'], 9700.0);
      final saleId = (await db.query('sales')).single['id'] as int;

      await provider.deleteSale(saleId);

      final harvestAfter = (await db.query('harvests')).single;
      expect(harvestAfter['gross_amount'], 0.0);
      expect(harvestAfter['net_income'], -300.0);
      expect(harvestAfter['payment_status'], 'Pending');
      expect(await db.query('sales'), isEmpty);
      expect((await db.query('expenses')).single['amount'], 300.0);
    },
  );

  test(
    'sale edits recompute gross revenue and net income from the saved sale',
    () async {
      final crop = await seedCropSeason();
      final provider = HarvestProvider();
      await provider.addHarvest(
        cropSeasonId: crop.cropSeasonId,
        quantity: 10,
        unit: 'من',
        date: '2026-09-30',
        transportationExpense: 100,
      );
      final db = await DatabaseHelper.instance.database;
      final harvestId = (await db.query('harvests')).single['id'] as int;

      await provider.recordSale(
        harvestId: harvestId,
        quantity: 10,
        pricePerUnit: 2000,
        totalAmount: 20000,
        date: '2026-09-30',
        buyerName: 'Buyer',
      );
      var harvest = (await db.query('harvests')).single;
      expect(harvest['gross_amount'], 20000.0);
      expect(harvest['net_income'], 19900.0);
      final saleId = (await db.query('sales')).single['id'] as int;

      await provider.updateSale(
        id: saleId,
        harvestId: harvestId,
        quantity: 10,
        pricePerUnit: 2500,
        totalAmount: 25000,
        date: '2026-10-01',
        buyerName: 'Buyer 2',
      );
      harvest = (await db.query('harvests')).single;
      expect(harvest['gross_amount'], 25000.0);
      expect(harvest['net_income'], 24900.0);
      expect(harvest['rate_per_unit'], 2500.0);
      expect(harvest['buyer_name'], 'Buyer 2');
    },
  );

  test(
    'yield acreage includes every field mapped to the crop season',
    () async {
      final crop = await seedCropSeason();
      final db = await DatabaseHelper.instance.database;
      final secondFieldId = await db.insert('fields', {
        'farm_id': crop.farmId,
        'name': 'Field 2',
        'size_acres': 2.0,
        'canal_water_available': 1,
        'tube_well_available': 0,
      });
      await db.insert('crop_season_fields', {
        'crop_season_id': crop.cropSeasonId,
        'field_id': secondFieldId,
      });

      final provider = HarvestProvider();
      await provider.addHarvest(
        cropSeasonId: crop.cropSeasonId,
        quantity: 60,
        unit: 'من',
        date: '2026-09-30',
      );

      expect(provider.harvests.single.fieldSize, 3.0);
      expect(provider.harvests.single.fieldName, contains('Field 1'));
      expect(provider.harvests.single.fieldName, contains('Field 2'));
      expect(provider.harvests.single.farmName, 'Test Farm');
    },
  );

  test('sales cannot exceed recorded crop quantity', () async {
    final crop = await seedCropSeason();
    final provider = HarvestProvider();
    await provider.addHarvest(
      cropSeasonId: crop.cropSeasonId,
      quantity: 10,
      unit: 'من',
      date: '2026-09-30',
    );
    final db = await DatabaseHelper.instance.database;
    final harvestId = (await db.query('harvests')).single['id'] as int;

    await expectLater(
      provider.recordSale(
        harvestId: harvestId,
        quantity: 11,
        pricePerUnit: 100,
        totalAmount: 1100,
        date: '2026-09-30',
      ),
      throwsArgumentError,
    );
    expect(await db.query('sales'), isEmpty);
    expect((await db.query('harvests')).single['gross_amount'], 0.0);
  });
}
