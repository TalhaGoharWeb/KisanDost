import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:kisan_dost/database/db_helper.dart';
import 'package:kisan_dost/models/batai.dart';
import 'package:kisan_dost/models/models.dart';
import 'package:kisan_dost/models/party.dart';
import 'package:kisan_dost/providers/batai_provider.dart';
import 'package:kisan_dost/providers/crop_provider.dart';
import 'package:kisan_dost/providers/farm_provider.dart';
import 'package:kisan_dost/providers/harvest_provider.dart';
import 'package:kisan_dost/providers/party_provider.dart';
import 'package:kisan_dost/services/pnl_summary.dart';

/// Batai ↔ P&L integration tests for owner decision #2 (S3 / §6.3).
///
/// They exercise the REAL BataiProvider + HarvestProvider against the REAL
/// fresh-install schema on an in-memory FFI database, then run the P&L
/// through [computeFarmPnl] — the single source of truth.
///
/// The farmer-visible contract under test:
/// * the P&L includes the farmer's ACTUAL batai share per the agreed
///   percentages (role-aware: landowner → owner_paisa, cultivator →
///   cultivator_paisa);
/// * a harvest whose proceeds were split NEVER counts the full sale total
///   as income alongside the distribution (no double-count);
/// * the fractional-paisa rounding rule (remainder → larger share, owner on
///   tie) flows through to the P&L untouched;
/// * settlements are append-only: several settlements on one harvest sum
///   their shares, and the sale stays excluded exactly once;
/// * settlements not linked to a harvest still count (farm-wide, and
///   per-crop when the agreement names a crop season).
void main() {
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  late Database db;
  late HarvestProvider harvests;
  late BataiProvider batai;
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

  Future<int> addParty(String name) async {
    final parties = PartyProvider(testExecutor: db);
    return parties.addParty(
      Party(name: name, createdAt: DateTime.now().toIso8601String()),
    );
  }

  Future<int> addAgreement({
    required int partyId,
    FarmerRole role = FarmerRole.cultivator,
    int owner = 50,
    int cultivator = 50,
    int? cropSeasonId,
  }) {
    return batai.createAgreement(
      farmerRole: role,
      otherPartyId: partyId,
      ownerSharePercent: owner,
      cultivatorSharePercent: cultivator,
      cropSeasonId: cropSeasonId,
      startDate: '2026-01-01',
    );
  }

  /// A harvest of 100 من @ Rs 50/من, genuinely sold: 500,000 paisa.
  /// Returns (harvestId, saleId).
  Future<(int, int)> addSoldHarvest() async {
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
    );
    final saleId = harvests.harvests.single.sale!.id!;
    return (harvestId, saleId);
  }

  FarmPnl pnlOf() => computeFarmPnl(
    harvests: harvests.harvests,
    totalExpensesPaisa: 0,
    seasons: [seasonDetails()],
    activities: const [],
    expenses: const [],
    ushrRecords: const [],
    bataiSettlements: batai.allSettlements,
    bataiAgreements: batai.agreements.map((s) => s.agreement).toList(),
  );

  setUp(() async {
    db = await openFreshDb();
    seasonId = await seedSeason(db);
    harvests = HarvestProvider(testExecutor: db);
    batai = BataiProvider(testExecutor: db);
  });

  tearDown(() async {
    await db.close();
  });

  group('batai farmer share replaces the full sale in P&L', () {
    test('50/50 cultivator: farmer gets half, sale never double-counted',
        () async {
      final (harvestId, saleId) = await addSoldHarvest();
      final partyId = await addParty('زمیندار');
      final agreementId = await addAgreement(partyId: partyId);
      await batai.settleAgreement(
        agreementId: agreementId,
        totalPaisa: 500000,
        harvestId: harvestId,
        saleId: saleId,
        settleDate: '2026-05-15',
      );

      final pnl = pnlOf();
      // 500,000 × 50% = 250,000 — NOT 750,000 (sale + share) and NOT
      // 500,000 (the full sale: the other half is not the farmer's money).
      expect(pnl.bataiIncomePaisa, 250000);
      expect(pnl.salesIncomePaisa, 0);
      expect(pnl.totalSalesPaisa, 250000);
      expect(pnl.unsoldProducePaisa, 0);

      final crop = pnl.crops.single;
      expect(crop.bataiIncomePaisa, 250000);
      expect(crop.incomePaisa, 250000);
    });

    test('60/40 landowner gets the owner share', () async {
      final (harvestId, saleId) = await addSoldHarvest();
      final partyId = await addParty('مزارع');
      final agreementId = await addAgreement(
        partyId: partyId,
        role: FarmerRole.landowner,
        owner: 60,
        cultivator: 40,
      );
      await batai.settleAgreement(
        agreementId: agreementId,
        totalPaisa: 500000,
        harvestId: harvestId,
        saleId: saleId,
        settleDate: '2026-05-15',
      );

      // 500,000 × 60% = 300,000 to the landowner-farmer.
      expect(pnlOf().totalSalesPaisa, 300000);
    });

    test('settlement linked by saleId only still suppresses the sale',
        () async {
      final (_, saleId) = await addSoldHarvest();
      final partyId = await addParty('زمیندار');
      final agreementId = await addAgreement(partyId: partyId);
      await batai.settleAgreement(
        agreementId: agreementId,
        totalPaisa: 500000,
        saleId: saleId,
        settleDate: '2026-05-15',
      );

      final pnl = pnlOf();
      expect(pnl.bataiIncomePaisa, 250000);
      expect(pnl.salesIncomePaisa, 0);
      expect(pnl.totalSalesPaisa, 250000);
    });

    test('fractional paisa: tie remainder goes to the owner', () async {
      // splitBatai(1001, 50): 500 + 500, remainder 1 → owner: 501 / 500.
      final partyId = await addParty('زمیندار');
      final cultivatorAgreement = await addAgreement(partyId: partyId);
      await batai.settleAgreement(
        agreementId: cultivatorAgreement,
        totalPaisa: 1001,
        settleDate: '2026-05-15',
      );
      expect(pnlOf().bataiIncomePaisa, 500);

      final ownerParty = await addParty('مزارع');
      final ownerAgreement = await addAgreement(
        partyId: ownerParty,
        role: FarmerRole.landowner,
      );
      await batai.settleAgreement(
        agreementId: ownerAgreement,
        totalPaisa: 1001,
        settleDate: '2026-05-16',
      );
      // 500 (cultivator share) + 501 (owner share) = 1001: exact, no drift.
      expect(pnlOf().bataiIncomePaisa, 1001);
    });

    test('multiple settlements on one harvest sum; sale excluded once',
        () async {
      final (harvestId, saleId) = await addSoldHarvest();
      final partyId = await addParty('زمیندار');
      final agreementId = await addAgreement(partyId: partyId);
      // The season settles harvest-by-harvest: two distributions.
      await batai.settleAgreement(
        agreementId: agreementId,
        totalPaisa: 300000,
        harvestId: harvestId,
        saleId: saleId,
        settleDate: '2026-05-15',
      );
      await batai.settleAgreement(
        agreementId: agreementId,
        totalPaisa: 200000,
        harvestId: harvestId,
        saleId: saleId,
        settleDate: '2026-05-20',
      );

      // 150,000 + 100,000 = 250,000; the 500,000 sale stays excluded once.
      final pnl = pnlOf();
      expect(pnl.bataiIncomePaisa, 250000);
      expect(pnl.salesIncomePaisa, 0);
      expect(pnl.totalSalesPaisa, 250000);
    });

    test('identical retry settlement: append-only, still no double-count',
        () async {
      // D4 is undecided (no UNIQUE on harvest/sale in settlements), so a
      // retried settlement records a second row — the P&L must still
      // exclude the sale exactly once, never double-exclude it.
      final (harvestId, saleId) = await addSoldHarvest();
      final partyId = await addParty('زمیندار');
      final agreementId = await addAgreement(partyId: partyId);
      for (var i = 0; i < 2; i++) {
        await batai.settleAgreement(
          agreementId: agreementId,
          totalPaisa: 500000,
          harvestId: harvestId,
          saleId: saleId,
          settleDate: '2026-05-15',
        );
      }

      final pnl = pnlOf();
      expect(pnl.bataiIncomePaisa, 500000);
      expect(pnl.salesIncomePaisa, 0);
      expect(pnl.totalSalesPaisa, 500000);
    });

    test('unlinked settlement counts farm-wide + on its crop season',
        () async {
      final partyId = await addParty('زمیندار');
      final agreementId = await addAgreement(
        partyId: partyId,
        cropSeasonId: seasonId,
      );
      await batai.settleAgreement(
        agreementId: agreementId,
        totalPaisa: 200000,
        settleDate: '2026-05-15',
      );

      final pnl = pnlOf();
      expect(pnl.bataiIncomePaisa, 100000);
      expect(pnl.totalSalesPaisa, 100000);
      expect(pnl.crops.single.bataiIncomePaisa, 100000);
    });

    test('unlinked settlement without a crop link counts farm-wide only',
        () async {
      final partyId = await addParty('زمیندار');
      final agreementId = await addAgreement(partyId: partyId);
      await batai.settleAgreement(
        agreementId: agreementId,
        totalPaisa: 200000,
        settleDate: '2026-05-15',
      );

      final pnl = pnlOf();
      expect(pnl.bataiIncomePaisa, 100000);
      expect(pnl.crops.single.bataiIncomePaisa, 0);
      expect(pnl.crops.single.incomePaisa, 0);
    });

    test('P&L is deterministic across repeated computations', () async {
      final (harvestId, saleId) = await addSoldHarvest();
      final partyId = await addParty('زمیندار');
      final agreementId = await addAgreement(partyId: partyId);
      await batai.settleAgreement(
        agreementId: agreementId,
        totalPaisa: 500000,
        harvestId: harvestId,
        saleId: saleId,
        settleDate: '2026-05-15',
      );

      final first = pnlOf();
      final second = pnlOf();
      expect(second.totalSalesPaisa, first.totalSalesPaisa);
      expect(second.bataiIncomePaisa, first.bataiIncomePaisa);
      expect(second.unsoldProducePaisa, first.unsoldProducePaisa);
      expect(second.crops.single.incomePaisa, first.crops.single.incomePaisa);
    });
  });

  group('bataiFarmerSharePaisa', () {
    test('role-aware pick from the stored split', () {
      final owner = BataiAgreement(
        id: 7,
        farmerRole: FarmerRole.landowner,
        otherPartyId: 1,
        ownerSharePercent: 60,
        cultivatorSharePercent: 40,
        startDate: '2026-01-01',
        createdAt: '2026-01-01',
      );
      final cultivator = BataiAgreement(
        id: 7,
        farmerRole: FarmerRole.cultivator,
        otherPartyId: 1,
        ownerSharePercent: 60,
        cultivatorSharePercent: 40,
        startDate: '2026-01-01',
        createdAt: '2026-01-01',
      );
      final settlement = BataiSettlement(
        agreementId: 7,
        totalPaisa: 500000,
        ownerPaisa: 300000,
        cultivatorPaisa: 200000,
        settleDate: '2026-05-15',
        createdAt: '2026-05-15',
      );

      expect(bataiFarmerSharePaisa(settlement, [cultivator]), 200000);
      expect(bataiFarmerSharePaisa(settlement, [owner]), 300000);
    });

    test('unknown agreement contributes 0 (defensive)', () {
      final settlement = BataiSettlement(
        agreementId: 999,
        totalPaisa: 500000,
        ownerPaisa: 250000,
        cultivatorPaisa: 250000,
        settleDate: '2026-05-15',
        createdAt: '2026-05-15',
      );
      expect(bataiFarmerSharePaisa(settlement, const []), 0);

      final pnl = computeFarmPnl(
        harvests: const [],
        totalExpensesPaisa: 0,
        seasons: [seasonDetails()],
        activities: const [],
        expenses: const [],
        ushrRecords: const [],
        bataiSettlements: [settlement],
      );
      expect(pnl.bataiIncomePaisa, 0);
      expect(pnl.totalSalesPaisa, 0);
    });
  });
}
