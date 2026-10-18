import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:kisan_dost/database/db_helper.dart';
import 'package:kisan_dost/providers/crop_provider.dart';
import 'package:kisan_dost/providers/farm_provider.dart';
import 'package:kisan_dost/providers/harvest_provider.dart';

/// S11 regression (2026-10-18): [HarvestProvider.deleteSale] zeroes the
/// parent harvest's rate/buyer/status so the sale can be re-recorded.
/// [HarvestProvider.restoreSale] must restore the harvest's rate (and buyer)
/// from the sale's own pre-delete values — otherwise the harvest card
/// (rate 0 → gross 0) disagrees with the restored sale row.
///
/// Hand-computed reference: 40 من @ Rs 3,500/من → gross/total
/// 14,000,000 paisa. deleteSale zeroes the rate; restoreSale must bring
/// back 350,000 paisa/من so harvest and sale agree again.
void main() {
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  TestWidgetsFlutterBinding.ensureInitialized();
  SharedPreferences.setMockInitialValues({});

  late Database db;
  late FarmProvider farms;
  late CropProvider crops;
  late HarvestProvider harvests;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    db = await databaseFactoryFfi.openDatabase(inMemoryDatabasePath);
    await db.execute('PRAGMA foreign_keys = ON');
    await DatabaseHelper.instance.createFreshSchemaForTests(db);
    farms = FarmProvider(testExecutor: db);
    crops = CropProvider(testExecutor: db);
    harvests = HarvestProvider(testExecutor: db);
  });

  tearDown(() async {
    await db.close();
  });

  Future<int> seedSeason() async {
    await farms.addFarm('ٹیسٹ فارم', 5);
    final farmId =
        (await db.query('farms', columns: ['id'])).single['id'] as int;
    await farms.addField(farmId: farmId, name: 'ٹیسٹ کھیت', sizeAcres: 5);
    final fieldId =
        (await db.query('fields', columns: ['id'])).single['id'] as int;
    await crops.addCropSeason(
      fieldIds: [fieldId],
      cropName: 'گندم',
      variety: 'دیسی',
      startDate: '2026-10-01',
    );
    return (await db.query('crop_seasons', columns: ['id'])).single['id']
        as int;
  }

  /// Adds a 40 من harvest at Rs 3,500/من (auto-creates its sale).
  /// Returns (harvestId, saleId).
  Future<(int, int)> addSoldHarvest(int seasonId, {String buyer = 'آڑھتی'}) async {
    await harvests.addHarvest(
      cropSeasonId: seasonId,
      quantity: 40,
      unit: 'من',
      date: '2026-10-10',
      ratePerUnitPaisa: 350000,
      buyerName: buyer,
    );
    final harvestId =
        (await db.query('harvests', orderBy: 'id DESC')).first['id'] as int;
    final saleId =
        (await db.query('sales', orderBy: 'id DESC')).first['id'] as int;
    return (harvestId, saleId);
  }

  Future<Map<String, Object?>> harvestRow(int harvestId) async =>
      (await db.query(
        'harvests',
        where: 'id = ?',
        whereArgs: [harvestId],
      )).single;

  test('restoreSale restores the harvest rate/buyer to the pre-delete values',
      () async {
    final seasonId = await seedSeason();
    final (harvestId, saleId) = await addSoldHarvest(seasonId);

    await harvests.deleteSale(saleId);

    // deleteSale zeroes the harvest for re-sale…
    expect((await harvestRow(harvestId))['rate_per_unit_paisa'], 0);
    expect((await harvestRow(harvestId))['buyer_name'], isNull);

    await harvests.restoreSale(saleId);

    // …and restoreSale brings the pre-delete values back.
    final row = await harvestRow(harvestId);
    expect(row['rate_per_unit_paisa'], 350000);
    expect(row['buyer_name'], 'آڑھتی');
    expect(
      (await db.query('sales', where: 'id = ?', whereArgs: [saleId]))
          .single['deleted_at'],
      isNull,
    );

    // Provider view: harvest gross and sale total agree again.
    await harvests.fetchHarvests();
    final hwd = harvests.harvests.single;
    expect(hwd.harvest.grossPaisa, 14000000);
    expect(hwd.sale, isNotNull);
    expect(hwd.sale!.totalAmountPaisa, 14000000);
    expect(hwd.sale!.pricePerUnitPaisa, hwd.harvest.ratePerUnitPaisa);
  });

  test('restoreSale does not clobber a newer re-sale', () async {
    final seasonId = await seedSeason();
    final (harvestId, oldSaleId) = await addSoldHarvest(
      seasonId,
      buyer: 'پہلا آڑھتی',
    );

    await harvests.deleteSale(oldSaleId);

    // The farmer re-sells at a new price before restoring the old sale.
    await harvests.recordSale(
      harvestId: harvestId,
      quantity: 40,
      pricePerUnitPaisa: 400000,
      date: '2026-10-11',
      buyerName: 'دوسرا آڑھتی',
    );
    expect((await harvestRow(harvestId))['rate_per_unit_paisa'], 400000);

    await harvests.restoreSale(oldSaleId);

    // The live re-sale wins: the harvest keeps the newer rate/buyer.
    final row = await harvestRow(harvestId);
    expect(row['rate_per_unit_paisa'], 400000);
    expect(row['buyer_name'], 'دوسرا آڑھتی');
    // The old sale row itself is still restored (as history).
    expect(
      (await db.query('sales', where: 'id = ?', whereArgs: [oldSaleId]))
          .single['deleted_at'],
      isNull,
    );
  });

  test('restoreSale on a missing sale is a safe no-op', () async {
    await harvests.restoreSale(999999);
    expect(await db.query('sales'), isEmpty);
  });
}
