import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:kisan_dost/database/db_helper.dart';
import 'package:kisan_dost/models/batai.dart';
import 'package:kisan_dost/models/models.dart';
import 'package:kisan_dost/models/party.dart';
import 'package:kisan_dost/providers/activity_provider.dart';
import 'package:kisan_dost/providers/batai_provider.dart';
import 'package:kisan_dost/providers/crop_provider.dart';
import 'package:kisan_dost/providers/farm_provider.dart';
import 'package:kisan_dost/providers/harvest_provider.dart';
import 'package:kisan_dost/providers/inventory_provider.dart';
import 'package:kisan_dost/providers/party_provider.dart';
import 'package:kisan_dost/providers/theka_provider.dart';
import 'package:kisan_dost/providers/ushr_provider.dart';
import 'package:kisan_dost/services/unit_converter.dart';

/// Owner decision #5 regression: the HARD-delete paths (no `deleted_at`
/// column by design) are atomic, audited, and never cascade into real
/// farmer data (D1).
///
/// Hand-computed references used below:
/// * theka: Rs 10,000 (1,000,000 paisa) in 2 installments; Rs 2,000 then
///   Rs 3,000 paid on installment 1 → cumulative 'Land Rent' expense
///   Rs 5,000 (500,000 paisa).
/// * activity: 10 بوری purchased, 3 بوری used → stock 7.0; delete returns
///   exactly 3.0 → 10.0.
/// * ushr: 100 من harvest, عشر 10% of Rs 5,000 (500,000 paisa market) =
///   Rs 500 (50,000 paisa); 10 من paid in kind → harvest 90 من; delete
///   returns exactly 10 من → 100 من.
void main() {
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  late Database db;
  late int seasonId;
  late int farmId;

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

  Future<void> seedSeason() async {
    final farms = FarmProvider(testExecutor: db);
    await farms.addFarm('ٹیسٹ فارم', 10.0);
    farmId = farms.farms.first.id!;
    await farms.addField(farmId: farmId, name: 'کھیت 1', sizeAcres: 5.0);
    await farms.fetchFields(farmId);
    final fieldId = farms.getFieldsForFarm(farmId).first.id!;
    final crops = CropProvider(testExecutor: db);
    await crops.addCropSeason(
      fieldIds: [fieldId],
      cropName: 'گندم',
      variety: 'دیسی',
      startDate: '2026-01-01',
    );
    seasonId = crops.activeCropSeasons.first.cropSeason.id!;
  }

  Future<int> auditCount(String table, String action) async {
    final rows = await db.rawQuery(
      'SELECT COUNT(*) AS c FROM audit_log WHERE table_name = ? AND action = ?',
      [table, action],
    );
    return ((rows.first['c'] as num?) ?? 0).toInt();
  }

  Future<int> addHarvest(HarvestProvider harvests, double qty) async {
    await harvests.addHarvest(
      cropSeasonId: seasonId,
      quantity: qty,
      unit: 'من',
      date: '2026-05-01',
    );
    return (await db.query('harvests', orderBy: 'id DESC')).first['id'] as int;
  }

  setUp(() async {
    db = await openFreshDb();
    await seedSeason();
  });

  tearDown(() async {
    await db.close();
  });

  group('theka: atomic delete of theka + installments + expenses', () {
    test('deleteTheka removes everything in one transaction', () async {
      final thekas = ThekaProvider(testExecutor: db);
      await thekas.addTheka(
        Theka(
          farmId: farmId,
          totalAmountPaisa: 1000000,
          durationType: 'سالانہ',
          paymentMethod: 'نقد',
          createdAt: DateTime.now().toIso8601String(),
        ),
        [
          ThekaInstallment(
            thekaId: 0,
            amountPaisa: 500000,
            dueDate: '2026-06-01',
            status: 'Pending',
          ),
          ThekaInstallment(
            thekaId: 0,
            amountPaisa: 500000,
            dueDate: '2026-12-01',
            status: 'Pending',
          ),
        ],
      );
      final thekaId = thekas.thekas.single.id!;
      final instId = thekas.getInstallmentsForTheka(thekaId).first.id!;

      // Rs 2,000 + Rs 3,000 on installment 1 → cumulative expense 500,000.
      await thekas.payInstallment(
        installmentId: instId,
        paidAmountPaisa: 200000,
        paidDate: '2026-06-02',
        farmName: 'ٹیسٹ فارم',
        installmentIndex: 1,
      );
      await thekas.payInstallment(
        installmentId: instId,
        paidAmountPaisa: 300000,
        paidDate: '2026-06-03',
        farmName: 'ٹیسٹ فارم',
        installmentIndex: 1,
      );
      var expenseRows = await db.query('expenses');
      expect(expenseRows, hasLength(1));
      expect(expenseRows.first['amount_paisa'], 500000);

      await thekas.deleteTheka(thekaId);

      // One transaction took the theka, both installments (FK cascade)
      // and the installment's linked expense — nothing orphaned.
      expect(await db.query('thekas'), isEmpty);
      expect(await db.query('theka_installments'), isEmpty);
      expect(await db.query('expenses'), isEmpty);
      expect(await auditCount('thekas', 'delete'), 1);
      expect(await auditCount('expenses', 'delete'), 1);

      // Deleting again is a safe no-op — no second audit row.
      await thekas.deleteTheka(thekaId);
      expect(await auditCount('thekas', 'delete'), 1);
      expect(await auditCount('expenses', 'delete'), 1);
    });

    test('deleteTheka of a missing theka is a safe no-op', () async {
      final thekas = ThekaProvider(testExecutor: db);
      await thekas.deleteTheka(999999);
      expect(await auditCount('thekas', 'delete'), 0);
    });
  });

  group('batai: settlement block preserved', () {
    test('agreement without settlements deletes; with settlements blocks',
        () async {
      final batai = BataiProvider(testExecutor: db);
      final parties = PartyProvider(testExecutor: db);
      final partyId = await parties.addParty(
        Party(
          name: 'مزارع',
          createdAt: DateTime.now().toIso8601String(),
        ),
      );

      final freeId = await batai.createAgreement(
        farmerRole: FarmerRole.landowner,
        otherPartyId: partyId,
        ownerSharePercent: 50,
        cultivatorSharePercent: 50,
        startDate: '2026-01-01',
      );
      await batai.deleteAgreement(freeId);
      expect(await db.query('batai_agreements'), isEmpty);
      expect(await auditCount('batai_agreements', 'delete'), 1);

      final lockedId = await batai.createAgreement(
        farmerRole: FarmerRole.landowner,
        otherPartyId: partyId,
        ownerSharePercent: 60,
        cultivatorSharePercent: 40,
        startDate: '2026-01-01',
      );
      // 60/40 split of Rs 1,000 (100,000 paisa) → 60,000 / 40,000.
      await batai.settleAgreement(
        agreementId: lockedId,
        totalPaisa: 100000,
        settleDate: '2026-06-01',
      );
      expect(
        () => batai.deleteAgreement(lockedId),
        throwsA(isA<BataiException>()),
      );
      // The agreement AND its settlement survive the blocked delete.
      expect(
        (await db.query('batai_agreements')),
        hasLength(1),
      );
      expect(
        (await db.query('batai_settlements')),
        hasLength(1),
      );
      expect(
        (await db.query('batai_settlements')).first['owner_paisa'],
        60000,
      );
    });
  });

  group('activity: stock returned ledger-exact, expense soft-deleted', () {
    test('delete → delete-again never double-restores stock', () async {
      final inventory = InventoryProvider(testExecutor: db);
      final activities = ActivityProvider(testExecutor: db);

      final itemId = await inventory.recordPurchase(
        category: 'کھاد',
        name: 'یوریا',
        unit: 'بوری',
        quantity: 10.0,
        costPerUnitPaisa: 100000,
      );
      await activities.addActivity(
        cropSeasonId: seasonId,
        activityType: 'کھاد',
        date: '2026-05-01',
        details: 'یوریا چھٹا',
        expenseAmountPaisa: 300000,
        expenseCategory: 'Fertilizer',
        inventoryCategory: 'کھاد',
        inventoryName: 'یوریا',
        inventoryUnit: 'بوری',
        inventoryQuantity: 3.0,
        inventoryItemId: itemId,
        inventoryProvider: inventory,
      );
      final activityId =
          (await db.query('activities', orderBy: 'id DESC')).first['id']
              as int;
      final expenseId =
          (await db.query(
            'activities',
            columns: const ['expense_id'],
            where: 'id = ?',
            whereArgs: [activityId],
          )).first['expense_id']
              as int;
      Future<double> stock() async =>
          (await inventory.getItemById(itemId))!.quantity;
      expect(await stock(), 7.0);

      await activities.deleteActivity(activityId, inventoryProvider: inventory);

      // Exactly the 3.0 deducted بوری come back; the linked expense is
      // soft-deleted (restorable); the activity delete is audit-logged.
      expect(await stock(), 10.0);
      expect(
        (await db.query(
          'expenses',
          columns: const ['deleted_at'],
          where: 'id = ?',
          whereArgs: [expenseId],
        )).first['deleted_at'],
        isNotNull,
      );
      expect(await auditCount('activities', 'delete'), 1);
      expect(await auditCount('expenses', 'soft_delete'), 1);
      // The usage ledger keeps its history (append-only).
      final usages = await db.query(
        'inventory_transactions',
        where: "type = 'usage'",
      );
      expect(usages, hasLength(1));

      // Deleting again is a safe no-op — stock stays exactly 10.0.
      await activities.deleteActivity(activityId, inventoryProvider: inventory);
      expect(await stock(), 10.0);
      expect(await auditCount('activities', 'delete'), 1);
    });
  });

  group('ushr: in-kind grain returned, mirror hard-deleted as a pair', () {
    test('deleteUshrRecord reverses the harvest deduction exactly', () async {
      final harvests = HarvestProvider(testExecutor: db);
      final ushr = UshrProvider(testExecutor: db);

      final harvestId = await addHarvest(harvests, 100.0);
      // Market Rs 5,000 (500,000 paisa); عشر 10% = Rs 500 (50,000 paisa);
      // 10 من in kind @ Rs 50/من = Rs 500 — exactly the due.
      await ushr.addUshrRecord(
        cropSeasonId: seasonId,
        harvestId: harvestId,
        harvestQty: 100.0,
        marketValuePaisa: 500000,
        ushrMethod: 'بارانی',
        ushrPercentage: 10.0,
        ushrAmountPaisa: 50000,
        status: 'Paid',
        datePaid: '2026-05-10',
        payMethod: 'Crop',
        qtyPaid: 10.0,
        cashPaidPaisa: 0,
        ratePerUnitPaisa: 5000,
      );
      final ushrId =
          (await db.query('ushr_records', orderBy: 'id DESC')).first['id']
              as int;
      Future<double> harvestQty() async =>
          ((await db.query(
                'harvests',
                columns: const ['quantity'],
                where: 'id = ?',
                whereArgs: [harvestId],
              )).first['quantity']
              as num)
              .toDouble();
      expect(await harvestQty(), 90.0);
      expect(
        (await db.query('expenses')).first['amount_paisa'],
        50000,
      );

      await ushr.deleteUshrRecord(ushrId);

      // The 10 من come back exactly; the record and its auto-created
      // expense mirror are hard-deleted as a pair, all audit-logged.
      expect(await harvestQty(), 100.0);
      expect(await db.query('ushr_records'), isEmpty);
      expect(await db.query('expenses'), isEmpty);
      expect(await auditCount('ushr_records', 'delete'), 1);
      expect(await auditCount('expenses', 'delete'), 1);
      // Two harvest updates: the in-kind deduction at creation and its
      // exact reversal at delete.
      expect(await auditCount('harvests', 'update'), 2);

      // Deleting again is a safe no-op — the harvest keeps its 100 من.
      await ushr.deleteUshrRecord(ushrId);
      expect(await harvestQty(), 100.0);
      expect(await auditCount('ushr_records', 'delete'), 1);
    });
  });

  group('inventory: ledger block preserved; bare delete atomic', () {
    test('item with history cannot be deleted; bare item deletes + audits',
        () async {
      final inventory = InventoryProvider(testExecutor: db);

      final usedId = await inventory.recordPurchase(
        category: 'کھاد',
        name: 'یوریا',
        unit: 'بوری',
        quantity: 5.0,
        costPerUnitPaisa: 100000,
      );
      expect(
        () => inventory.deleteInventoryItem(usedId),
        throwsA(isA<InventoryException>()),
      );
      expect(await inventory.getItemById(usedId), isNotNull);

      // An item with no ledger rows deletes cleanly with one audit row.
      final bareId = await db.insert('inventory', {
        'category': 'بیج',
        'name': 'گندم بیج',
        'unit': 'بوری',
        'quantity': 2.0,
        'cost_per_unit_paisa': 200000,
      });
      await inventory.deleteInventoryItem(bareId);
      expect(await inventory.getItemById(bareId), isNull);
      expect(await auditCount('inventory', 'delete'), 1);

      // Deleting again is a safe no-op.
      await inventory.deleteInventoryItem(bareId);
      expect(await auditCount('inventory', 'delete'), 1);
    });
  });

  group('farm/field/crop: hard deletes are audited, never silent', () {
    test('deleteField, deleteFarm and deleteCropSeason write audit rows',
        () async {
      final farms = FarmProvider(testExecutor: db);
      final crops = CropProvider(testExecutor: db);

      await farms.fetchFields(farmId);
      final fieldId = farms.getFieldsForFarm(farmId).first.id!;

      await farms.deleteField(fieldId, farmId);
      expect(await auditCount('fields', 'delete'), 1);
      await farms.deleteField(fieldId, farmId); // no-op
      expect(await auditCount('fields', 'delete'), 1);

      await farms.deleteFarm(farmId);
      expect(await auditCount('farms', 'delete'), 1);
      await farms.deleteFarm(farmId); // no-op
      expect(await auditCount('farms', 'delete'), 1);

      // Fresh farm/field/season for the crop delete.
      await farms.addFarm('دوسری زمین', 5.0);
      final farm2 = farms.farms.first.id!;
      await farms.addField(farmId: farm2, name: 'کھیت ا', sizeAcres: 5.0);
      await farms.fetchFields(farm2);
      final field2 = farms.getFieldsForFarm(farm2).first.id!;
      await crops.addCropSeason(
        fieldIds: [field2],
        cropName: 'کپاس',
        variety: 'دیسی',
        startDate: '2026-02-01',
      );
      final season2 = crops.activeCropSeasons.first.cropSeason.id!;
      await crops.deleteCropSeason(season2);
      expect(await auditCount('crop_seasons', 'delete'), 1);
      await crops.deleteCropSeason(season2); // no-op
      expect(await auditCount('crop_seasons', 'delete'), 1);
    });
  });

  group('worker B: party ledger source links survive source deletion', () {
    test('permanentDeleteSale keeps the linked ledger entry as a marker',
        () async {
      final harvests = HarvestProvider(testExecutor: db);
      final parties = PartyProvider(testExecutor: db);

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

      final partyId = await parties.addParty(
        Party(name: 'آڑھتی', createdAt: DateTime.now().toIso8601String()),
      );
      await parties.addLinkedEntry(
        partyId: partyId,
        type: PartyEntryType.udhaarDiya,
        amountPaisa: 50000,
        date: '2026-05-10',
        sourceType: PartyEntrySourceType.sale,
        sourceId: saleId,
      );

      await harvests.deleteSale(saleId);
      await harvests.permanentDeleteSale(saleId);

      // The sale row is gone, but the ledger link survives as a trace
      // marker — deleting a source never rewrites financial history.
      expect(await db.query('sales'), isEmpty);
      final links = await db.query('party_ledger_entries');
      expect(links, hasLength(1));
      expect(links.first['source_type'], 'sale');
      expect(links.first['source_id'], saleId);
      expect(links.first['amount_paisa'], 50000);
      expect(parties.balanceOf(partyId), 50000);
    });
  });
}
