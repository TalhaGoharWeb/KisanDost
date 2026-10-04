import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:kisan_dost/database/db_helper.dart';
import 'package:kisan_dost/providers/crop_provider.dart';
import 'package:kisan_dost/providers/farm_provider.dart';
import 'package:kisan_dost/providers/harvest_provider.dart';

/// Hermetic tests for harvest + sale calculations using the REAL production
/// schema. The app singleton is never touched.
///
/// What "correct" means, from the farmer's point of view:
/// * recording a harvest stores the quantity and its expense buckets, and
///   the total expense is the exact sum of the buckets;
/// * a sale's total is ALWAYS recomputed as quantity × price (rounded to the
///   paisa) — never trusted from caller input — so the sale and the
///   harvest's rate can never disagree;
/// * a sale against a non-existent harvest is a safe no-op, never a crash.
void main() {
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  Future<Database> openFreshDb() async {
    final db = await openDatabase(
      inMemoryDatabasePath,
      onConfigure: (db) async {
        await db.execute('PRAGMA foreign_keys = ON');
      },
    );
    await DatabaseHelper.instance.createFreshSchemaForTests(db);
    return db;
  }

  /// Seeds farm → field → crop season; returns the season id.
  Future<int> seedSeason(Database db) async {
    final farms = FarmProvider(testExecutor: db);
    await farms.addFarm('Test Farm', 10.0);
    final farmId = farms.farms.first.id!;
    await farms.addField(farmId: farmId, name: 'Plot', sizeAcres: 5.0);
    await farms.fetchFields(farmId);
    final fieldId = farms.getFieldsForFarm(farmId).first.id!;

    final crops = CropProvider(testExecutor: db);
    await crops.addCropSeason(
      fieldIds: [fieldId],
      cropName: 'Wheat',
      variety: 'Galaxy-13',
      startDate: '2026-11-01',
    );
    return crops.activeCropSeasons.first.cropSeason.id!;
  }

  group('harvest calculations', () {
    test('addHarvest stores quantity, unit and summed expenses', () async {
      final db = await openFreshDb();
      final seasonId = await seedSeason(db);
      final harvests = HarvestProvider(testExecutor: db);

      await harvests.addHarvest(
        cropSeasonId: seasonId,
        quantity: 40.0,
        unit: 'Maund',
        date: '2026-04-15',
        transportationExpensePaisa: 50000,
        labourExpensePaisa: 200000,
        harvestingExpensePaisa: 100000,
        commissionExpensePaisa: 75000,
        otherExpensePaisa: 25000,
      );

      expect(harvests.harvests, hasLength(1));
      final h = harvests.harvests.first.harvest;
      expect(h.quantity, 40.0);
      expect(h.unit, 'Maund');
      // Total = 50000 + 200000 + 100000 + 75000 + 25000 = 450000 paisa.
      expect(h.totalExpensePaisa, 450000);
      await db.close();
    });

    test('harvest with zero expenses has zero total expense', () async {
      final db = await openFreshDb();
      final seasonId = await seedSeason(db);
      final harvests = HarvestProvider(testExecutor: db);

      await harvests.addHarvest(
        cropSeasonId: seasonId,
        quantity: 10.0,
        unit: 'Maund',
        date: '2026-04-15',
      );

      expect(harvests.harvests.first.harvest.totalExpensePaisa, 0);
      await db.close();
    });
  });

  group('sale calculations', () {
    test('sale total is recomputed as quantity x price (never trusted)',
        () async {
      final db = await openFreshDb();
      final seasonId = await seedSeason(db);
      final harvests = HarvestProvider(testExecutor: db);

      await harvests.addHarvest(
        cropSeasonId: seasonId,
        quantity: 40.0,
        unit: 'Maund',
        date: '2026-04-15',
      );
      final harvestId = harvests.harvests.first.harvest.id!;

      // 25 maunds @ Rs 3,800/maund = Rs 95,000 = 9,500,000 paisa.
      await harvests.recordSale(
        harvestId: harvestId,
        quantity: 25.0,
        pricePerUnitPaisa: 380000,
        date: '2026-04-20',
        buyerName: 'Grain Merchant',
      );

      final saleRows = await db.query('sales');
      expect(saleRows, hasLength(1));
      expect(saleRows.first['total_amount_paisa'], 9500000);
      expect(saleRows.first['quantity'], 25.0);

      // The harvest row's rate/buyer are updated to match the sale.
      final hRows =
          await db.query('harvests', where: 'id = ?', whereArgs: [harvestId]);
      expect(hRows.first['rate_per_unit_paisa'], 380000);
      expect(hRows.first['buyer_name'], 'Grain Merchant');
      await db.close();
    });

    test('fractional paisa rounds to the nearest paisa', () async {
      final db = await openFreshDb();
      final seasonId = await seedSeason(db);
      final harvests = HarvestProvider(testExecutor: db);

      await harvests.addHarvest(
        cropSeasonId: seasonId,
        quantity: 3.0,
        unit: 'Maund',
        date: '2026-04-15',
      );
      final harvestId = harvests.harvests.first.harvest.id!;

      // 3 × 333333.33... → use a price that yields a fraction: 3 × 100001/3.
      // Simpler: quantity 1.5 × price 1 paisa = 1.5 → rounds to 2.
      await harvests.recordSale(
        harvestId: harvestId,
        quantity: 1.5,
        pricePerUnitPaisa: 1,
        date: '2026-04-20',
      );

      final saleRows = await db.query('sales');
      expect(saleRows.first['total_amount_paisa'], 2);
      await db.close();
    });

    test('sale against a missing harvest is a safe no-op', () async {
      final db = await openFreshDb();
      final harvests = HarvestProvider(testExecutor: db);

      await harvests.recordSale(
        harvestId: 999999,
        quantity: 10.0,
        pricePerUnitPaisa: 100000,
        date: '2026-04-20',
      );

      final saleRows = await db.query('sales');
      expect(saleRows, isEmpty);
      await db.close();
    });

    test('deleteSale soft-deletes the sale (row kept, hidden)', () async {
      final db = await openFreshDb();
      final seasonId = await seedSeason(db);
      final harvests = HarvestProvider(testExecutor: db);

      await harvests.addHarvest(
        cropSeasonId: seasonId,
        quantity: 40.0,
        unit: 'Maund',
        date: '2026-04-15',
      );
      final harvestId = harvests.harvests.first.harvest.id!;
      await harvests.recordSale(
        harvestId: harvestId,
        quantity: 10.0,
        pricePerUnitPaisa: 380000,
        date: '2026-04-20',
      );
      final saleId =
          (await db.query('sales')).first['id'] as int;

      await harvests.deleteSale(saleId);

      // Row is kept (financial history is never hard-deleted) but hidden.
      final all = await db.query('sales');
      expect(all, hasLength(1));
      expect(all.first['deleted_at'], isNotNull);
      final live = await db.query('sales', where: 'deleted_at IS NULL');
      expect(live, isEmpty);

      // The parent harvest's rate is reset so the sale can be re-recorded.
      final hRows =
          await db.query('harvests', where: 'id = ?', whereArgs: [harvestId]);
      expect(hRows.first['rate_per_unit_paisa'], 0);
      await db.close();
    });
  });
}
