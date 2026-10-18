import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:kisan_dost/database/db_helper.dart';
import 'package:kisan_dost/models/models.dart';
import 'package:kisan_dost/providers/crop_provider.dart';
import 'package:kisan_dost/providers/farm_provider.dart';
import 'package:kisan_dost/providers/harvest_provider.dart';
import 'package:kisan_dost/services/pnl_summary.dart';

/// Realized-income regression tests for owner decision #1 (S2 / §6.1).
///
/// They exercise the REAL HarvestProvider against the REAL fresh-install
/// schema on an in-memory FFI database, then run the P&L through
/// [computeFarmPnl] — the single source of truth.
///
/// The farmer-visible contract under test:
/// * a genuine sale (payment_status 'Paid' — incl. credit sales recorded
///   via recordSale — or 'Partial') counts as realized income;
/// * a 'Pending' sale is an ESTIMATE auto-created by merely entering a rate
///   on an unsold harvest: it contributes ZERO income and is tracked as
///   the separate "remaining produce" figure;
/// * a canceled (soft-deleted) sale contributes nothing anywhere;
/// * a restored sale comes back with its PRE-DELETE payment_status
///   (S11, owner decision #5: deleteSale stashes it on the sale row, v17),
///   so a restored genuine sale counts as realized income again.
void main() {
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  late Database db;
  late HarvestProvider harvests;
  late int seasonId;
  late int fieldId;

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
    await farms.addFarm('ٹیسٹ فارم', 10.0);
    final farmId = farms.farms.first.id!;
    await farms.addField(farmId: farmId, name: 'کھیت 1', sizeAcres: 5.0);
    await farms.fetchFields(farmId);
    fieldId = farms.getFieldsForFarm(farmId).first.id!;

    final crops = CropProvider(testExecutor: db);
    await crops.addCropSeason(
      fieldIds: [fieldId],
      cropName: 'گندم',
      variety: 'دیسی',
      startDate: '2026-01-01',
    );
    return crops.activeCropSeasons.first.cropSeason.id!;
  }

  CropSeasonWithDetails seasonDetails() => CropSeasonWithDetails(
    cropSeason: CropSeason(
      id: seasonId,
      fieldId: fieldId,
      cropName: 'گندم',
      variety: 'دیسی',
      status: 'active',
      startDate: '2026-01-01',
    ),
    fields: const [],
    fieldNames: const [],
    farmNames: const [],
    totalArea: 5.0,
  );

  FarmPnl pnlOf(HarvestProvider h) => computeFarmPnl(
    harvests: h.harvests,
    totalExpensesPaisa: 0,
    seasons: [seasonDetails()],
    activities: const [],
    expenses: const [],
    ushrRecords: const [],
  );

  setUp(() async {
    db = await openFreshDb();
    seasonId = await seedSeason(db);
    harvests = HarvestProvider(testExecutor: db);
  });

  tearDown(() async {
    await db.close();
  });

  group('realized income: only genuine sales count', () {
    test('sold harvest (Paid) counts its full sale total as income',
        () async {
      // 100 من @ Rs 50/من = Rs 5,000 = 500,000 paisa.
      await harvests.addHarvest(
        cropSeasonId: seasonId,
        quantity: 100.0,
        unit: 'من',
        date: '2026-05-01',
        ratePerUnitPaisa: 5000,
      );
      final harvestId = harvests.harvests.single.harvest.id!;
      await harvests.recordSale(
        harvestId: harvestId,
        quantity: 100.0,
        pricePerUnitPaisa: 5000,
        date: '2026-05-10',
        buyerName: 'احمد',
      );

      final pnl = pnlOf(harvests);
      expect(pnl.totalSalesPaisa, 500000);
      expect(pnl.salesIncomePaisa, 500000);
      expect(pnl.bataiIncomePaisa, 0);
      expect(pnl.unsoldProducePaisa, 0);
      expect(pnl.crops.single.incomePaisa, 500000);
      expect(pnl.crops.single.unsoldProducePaisa, 0);
    });

    test('unsold harvest (Pending estimate) is excluded from income',
        () async {
      // Rate entered but never sold: 40 من @ Rs 60 = 240,000 paisa of
      // produce still awaiting sale.
      await harvests.addHarvest(
        cropSeasonId: seasonId,
        quantity: 40.0,
        unit: 'من',
        date: '2026-05-01',
        ratePerUnitPaisa: 6000,
      );

      final pnl = pnlOf(harvests);
      expect(pnl.totalSalesPaisa, 0);
      expect(pnl.unsoldProducePaisa, 240000);
      expect(pnl.crops.single.incomePaisa, 0);
      expect(pnl.crops.single.unsoldProducePaisa, 240000);
    });

    test('partial-payment sale (Partial) counts as realized income',
        () async {
      // 50 من @ Rs 40 = 200,000 paisa; farmer marked جزوی ادائیگی.
      await harvests.addHarvest(
        cropSeasonId: seasonId,
        quantity: 50.0,
        unit: 'من',
        date: '2026-05-01',
        ratePerUnitPaisa: 4000,
        paymentStatus: 'Partial',
      );

      final pnl = pnlOf(harvests);
      expect(pnl.totalSalesPaisa, 200000);
      expect(pnl.unsoldProducePaisa, 0);
    });

    test('credit sale (recorded Paid with a buyer) counts as income',
        () async {
      // Sold on credit: 20 من @ Rs 70 = 140,000 paisa. The sale is real;
      // the outstanding amount lives in the party ledger (decision #3).
      await harvests.addHarvest(
        cropSeasonId: seasonId,
        quantity: 20.0,
        unit: 'من',
        date: '2026-05-01',
      );
      final harvestId = harvests.harvests.single.harvest.id!;
      await harvests.recordSale(
        harvestId: harvestId,
        quantity: 20.0,
        pricePerUnitPaisa: 7000,
        date: '2026-05-10',
        buyerName: 'کریڈٹ خریدار',
      );

      final pnl = pnlOf(harvests);
      expect(pnl.totalSalesPaisa, 140000);
      expect(pnl.unsoldProducePaisa, 0);
    });

    test('canceled sale contributes nothing — not income, not unsold',
        () async {
      await harvests.addHarvest(
        cropSeasonId: seasonId,
        quantity: 10.0,
        unit: 'من',
        date: '2026-05-01',
        ratePerUnitPaisa: 5000,
      );
      final harvestId = harvests.harvests.single.harvest.id!;
      await harvests.recordSale(
        harvestId: harvestId,
        quantity: 10.0,
        pricePerUnitPaisa: 5000,
        date: '2026-05-10',
      );
      final saleId = harvests.harvests.single.sale!.id!;
      await harvests.deleteSale(saleId);

      final pnl = pnlOf(harvests);
      expect(pnl.totalSalesPaisa, 0);
      expect(pnl.unsoldProducePaisa, 0);
      expect(pnl.crops.single.incomePaisa, 0);
    });

    test('restored sale comes back as the genuine sale it was (S11 fix)',
        () async {
      // S11 (owner decision #5, 2026-10-18): restoreSale restores the
      // harvest's PRE-DELETE payment_status, stashed by deleteSale on the
      // sale row (sales.harvest_payment_status_at_delete, v17). A sale
      // that was a genuine ('Paid') sale therefore reads as realized
      // income again after restore — not as an unsold estimate. (The old
      // behavior left payment_status at 'Pending', which this test used
      // to pin; that was the S11 bug being fixed, not a contract.)
      await harvests.addHarvest(
        cropSeasonId: seasonId,
        quantity: 10.0,
        unit: 'من',
        date: '2026-05-01',
        ratePerUnitPaisa: 5000,
      );
      final harvestId = harvests.harvests.single.harvest.id!;
      await harvests.recordSale(
        harvestId: harvestId,
        quantity: 10.0,
        pricePerUnitPaisa: 5000,
        date: '2026-05-10',
      );
      final saleId = harvests.harvests.single.sale!.id!;
      await harvests.deleteSale(saleId);
      await harvests.restoreSale(saleId);

      expect(harvests.harvests.single.sale, isNotNull);
      // 10 من @ Rs 50/من, sold Paid before the delete: the pre-delete
      // status comes back exactly.
      expect(harvests.harvests.single.harvest.paymentStatus, 'Paid');

      final pnl = pnlOf(harvests);
      expect(pnl.totalSalesPaisa, 50000);
      expect(pnl.salesIncomePaisa, 50000);
      expect(pnl.unsoldProducePaisa, 0);
    });

    test('harvest with no rate and no sale contributes nothing', () async {
      await harvests.addHarvest(
        cropSeasonId: seasonId,
        quantity: 5.0,
        unit: 'من',
        date: '2026-05-01',
      );

      final pnl = pnlOf(harvests);
      expect(pnl.totalSalesPaisa, 0);
      expect(pnl.unsoldProducePaisa, 0);
    });

    test('mixed harvests aggregate: sold + unsold + partial', () async {
      // Sold: 100 من @ 5000 = 500,000 income.
      await harvests.addHarvest(
        cropSeasonId: seasonId,
        quantity: 100.0,
        unit: 'من',
        date: '2026-05-01',
        ratePerUnitPaisa: 5000,
      );
      final soldId = harvests.harvests.single.harvest.id!;
      await harvests.recordSale(
        harvestId: soldId,
        quantity: 100.0,
        pricePerUnitPaisa: 5000,
        date: '2026-05-10',
      );
      // Unsold estimate: 40 من @ 6000 = 240,000 remaining produce.
      await harvests.addHarvest(
        cropSeasonId: seasonId,
        quantity: 40.0,
        unit: 'من',
        date: '2026-05-02',
        ratePerUnitPaisa: 6000,
      );
      // Partial: 50 من @ 4000 = 200,000 income.
      await harvests.addHarvest(
        cropSeasonId: seasonId,
        quantity: 50.0,
        unit: 'من',
        date: '2026-05-03',
        ratePerUnitPaisa: 4000,
        paymentStatus: 'Partial',
      );

      final pnl = pnlOf(harvests);
      // 500,000 + 200,000 realized; 240,000 still unsold.
      expect(pnl.totalSalesPaisa, 700000);
      expect(pnl.salesIncomePaisa, 700000);
      expect(pnl.unsoldProducePaisa, 240000);
      expect(pnl.netPaisa, 700000);

      final crop = pnl.crops.single;
      expect(crop.incomePaisa, 700000);
      expect(crop.unsoldProducePaisa, 240000);
    });
  });
}
