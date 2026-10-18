import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:kisan_dost/database/db_helper.dart';
import 'package:kisan_dost/models/party.dart';
import 'package:kisan_dost/providers/crop_provider.dart';
import 'package:kisan_dost/providers/expense_provider.dart';
import 'package:kisan_dost/providers/farm_provider.dart';
import 'package:kisan_dost/providers/harvest_provider.dart';
import 'package:kisan_dost/providers/inventory_provider.dart';
import 'package:kisan_dost/providers/party_provider.dart';
import 'package:kisan_dost/providers/task_provider.dart';

/// Owner decision #5 regression: atomic, reversible, idempotent
/// delete/restore for every SOFT-deleted record type.
///
/// Each path is driven through delete → restore → delete-again →
/// restore-again with hand-computed money/stock/status values asserted at
/// every step. The contract under test:
/// * one transaction per delete/restore (row + linked rows + audit rows);
/// * restore returns the linked graph to its exact pre-delete state;
/// * repeating a delete or a restore is a safe no-op — never duplicate
///   rows, never duplicate audit entries, never double-apply money/stock.
///
/// Hand-computed references used below:
/// * harvest: 100 من @ Rs 50/من (5,000 paisa/من) → gross/total 500,000
///   paisa; harvest expenses Rs 200 transport + Rs 300 labour = 50,000
///   paisa mirror.
/// * expense: Rs 2,500 (250,000 paisa) with 3 بوری inventory usage out of
///   10 بوری purchased.
void main() {
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  TestWidgetsFlutterBinding.ensureInitialized();
  SharedPreferences.setMockInitialValues({});
  // TaskProvider cancels/schedules notifications on delete/restore; the
  // plugin has no backend in tests, so every call is a no-op.
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(
        const MethodChannel('dexterx.dev/flutter_local_notifications'),
        (call) async => null,
      );

  late Database db;
  late int seasonId;

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
    final farmId = farms.farms.first.id!;
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

  Future<String?> deletedAt(String table, int id) async {
    final rows = await db.query(
      table,
      columns: const ['deleted_at'],
      where: 'id = ?',
      whereArgs: [id],
      limit: 1,
    );
    if (rows.isEmpty) return 'missing';
    return rows.first['deleted_at'] as String?;
  }

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    db = await openFreshDb();
    await seedSeason();
  });

  tearDown(() async {
    await db.close();
  });

  group('harvest subtree: atomic, reversible, idempotent', () {
    /// 100 من @ 5,000 paisa/من → sale 500,000; expenses 50,000 mirror.
    Future<(int, int, int)> addFullHarvest() async {
      final harvests = HarvestProvider(testExecutor: db);
      await harvests.addHarvest(
        cropSeasonId: seasonId,
        quantity: 100.0,
        unit: 'من',
        date: '2026-05-01',
        ratePerUnitPaisa: 5000,
        transportationExpensePaisa: 20000,
        labourExpensePaisa: 30000,
      );
      final harvestId =
          (await db.query('harvests', orderBy: 'id DESC')).first['id'] as int;
      final saleId =
          (await db.query('sales', orderBy: 'id DESC')).first['id'] as int;
      final expenseId =
          (await db.query('expenses', orderBy: 'id DESC')).first['id'] as int;
      return (harvestId, saleId, expenseId);
    }

    test('delete → restore → delete-again → restore-again is exact',
        () async {
      final harvests = HarvestProvider(testExecutor: db);
      final (harvestId, saleId, expenseId) = await addFullHarvest();

      // Sanity: everything live, values as computed by hand.
      expect(await deletedAt('harvests', harvestId), isNull);
      expect(await deletedAt('sales', saleId), isNull);
      expect(await deletedAt('expenses', expenseId), isNull);
      expect(
        (await db.query(
          'expenses',
          where: 'id = ?',
          whereArgs: [expenseId],
        )).first['amount_paisa'],
        50000,
      );

      await harvests.deleteHarvest(harvestId);

      // The whole subtree hides in ONE transaction…
      expect(await deletedAt('harvests', harvestId), isNotNull);
      expect(await deletedAt('sales', saleId), isNotNull);
      expect(await deletedAt('expenses', expenseId), isNotNull);
      expect(await auditCount('harvests', 'soft_delete'), 1);
      expect(await auditCount('sales', 'soft_delete'), 1);
      expect(await auditCount('expenses', 'soft_delete'), 1);
      await harvests.fetchHarvests();
      expect(harvests.harvests, isEmpty);

      // …and deleting again is a safe no-op (no duplicate audit rows).
      await harvests.deleteHarvest(harvestId);
      expect(await auditCount('harvests', 'soft_delete'), 1);
      expect(await auditCount('sales', 'soft_delete'), 1);
      expect(await auditCount('expenses', 'soft_delete'), 1);

      // Restore is individual by design: the harvest comes back, its sale
      // and expense mirror stay deleted until restored themselves — a
      // farmer never accidentally resurrects a whole subtree.
      await harvests.restoreHarvest(harvestId);
      expect(await deletedAt('harvests', harvestId), isNull);
      expect(await deletedAt('sales', saleId), isNotNull);
      expect(await deletedAt('expenses', expenseId), isNotNull);
      expect(await auditCount('harvests', 'restore'), 1);

      // Restoring again is a safe no-op.
      await harvests.restoreHarvest(harvestId);
      expect(await auditCount('harvests', 'restore'), 1);

      // The linked rows restore individually, completing the graph.
      await harvests.restoreSale(saleId);
      await ExpenseProvider(testExecutor: db).restoreExpense(expenseId);
      expect(await deletedAt('sales', saleId), isNull);
      expect(await deletedAt('expenses', expenseId), isNull);
      await harvests.fetchHarvests();
      final hwd = harvests.harvests.single;
      expect(hwd.harvest.grossPaisa, 500000);
      expect(hwd.sale!.totalAmountPaisa, 500000);
      // The harvest still points at its original mirror — no duplicate.
      final mirrorId =
          (await db.query(
            'harvests',
            columns: const ['expense_id'],
            where: 'id = ?',
            whereArgs: [harvestId],
          )).first['expense_id'];
      expect(mirrorId, expenseId);
      expect(
        await db.rawQuery(
          'SELECT COUNT(*) AS c FROM expenses WHERE deleted_at IS NULL',
        ).then((r) => r.first['c']),
        1,
      );
    });

    test('permanentDeleteHarvest destroys only the soft-deleted mirror',
        () async {
      final harvests = HarvestProvider(testExecutor: db);
      final expenses = ExpenseProvider(testExecutor: db);
      final (harvestId, saleId, expenseId) = await addFullHarvest();

      await harvests.deleteHarvest(harvestId);
      await harvests.permanentDeleteHarvest(harvestId);

      expect(await db.query('harvests'), isEmpty);
      expect(await db.query('sales'), isEmpty);
      // The mirror (still soft-deleted) goes with the subtree…
      expect(await db.query('expenses'), isEmpty);
      expect(await auditCount('harvests', 'permanent_delete'), 1);
      // …and repeating is a safe no-op.
      await harvests.permanentDeleteHarvest(harvestId);
      expect(await auditCount('harvests', 'permanent_delete'), 1);

      // D1: an expense the farmer restored individually is a LIVE
      // standalone row — the harvest's permanent delete must not destroy
      // it.
      final (h2, _, e2) = await addFullHarvest();
      await harvests.deleteHarvest(h2);
      await expenses.restoreExpense(e2);
      await harvests.permanentDeleteHarvest(h2);
      expect(await db.query('harvests'), isEmpty);
      expect(await db.query('sales'), isEmpty);
      final survivor = await db.query('expenses');
      expect(survivor, hasLength(1));
      expect(survivor.first['id'], e2);
      expect(survivor.first['deleted_at'], isNull);
    });
  });

  group('S11: sale delete/restore is an exact inverse', () {
    test('Paid status stashed at delete, restored exactly', () async {
      final harvests = HarvestProvider(testExecutor: db);
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
        buyerName: 'آڑھتی',
      );
      final saleId = harvests.harvests.single.sale!.id!;
      expect(harvests.harvests.single.harvest.paymentStatus, 'Paid');

      await harvests.deleteSale(saleId);

      // Reset for re-sale…
      var hRow =
          (await db.query(
            'harvests',
            where: 'id = ?',
            whereArgs: [harvestId],
          )).single;
      expect(hRow['rate_per_unit_paisa'], 0);
      expect(hRow['buyer_name'], isNull);
      expect(hRow['payment_status'], 'Pending');
      // …but the pre-delete status is stashed on the sale row.
      final sRow =
          (await db.query(
            'sales',
            where: 'id = ?',
            whereArgs: [saleId],
          )).single;
      expect(sRow['deleted_at'], isNotNull);
      expect(sRow['harvest_payment_status_at_delete'], 'Paid');

      // Deleting again is a safe no-op: the stash is not overwritten and
      // no second audit row appears.
      await harvests.deleteSale(saleId);
      expect(await auditCount('sales', 'soft_delete'), 1);
      expect(
        (await db.query(
          'sales',
          columns: const ['harvest_payment_status_at_delete'],
          where: 'id = ?',
          whereArgs: [saleId],
        )).single['harvest_payment_status_at_delete'],
        'Paid',
      );

      await harvests.restoreSale(saleId);

      // Exact inverse: rate, buyer AND the pre-delete status come back.
      hRow =
          (await db.query(
            'harvests',
            where: 'id = ?',
            whereArgs: [harvestId],
          )).single;
      expect(hRow['rate_per_unit_paisa'], 5000);
      expect(hRow['buyer_name'], 'آڑھتی');
      expect(hRow['payment_status'], 'Paid');
      expect(await deletedAt('sales', saleId), isNull);
      expect(await auditCount('sales', 'restore'), 1);
      await harvests.fetchHarvests();
      expect(harvests.harvests.single.harvest.grossPaisa, 50000);

      // Restoring again is a safe no-op.
      await harvests.restoreSale(saleId);
      expect(await auditCount('sales', 'restore'), 1);

      // A full second cycle keeps the exact status — no drift.
      await harvests.deleteSale(saleId);
      await harvests.restoreSale(saleId);
      hRow =
          (await db.query(
            'harvests',
            where: 'id = ?',
            whereArgs: [harvestId],
          )).single;
      expect(hRow['payment_status'], 'Paid');
      expect(
        (await db.query('sales', where: 'deleted_at IS NULL')),
        hasLength(1),
      );
    });

    test('Partial status round-trips exactly', () async {
      final harvests = HarvestProvider(testExecutor: db);
      // 50 من @ 4,000 paisa/من, جزوی ادائیگی → auto-sale 200,000 paisa.
      await harvests.addHarvest(
        cropSeasonId: seasonId,
        quantity: 50.0,
        unit: 'من',
        date: '2026-05-01',
        ratePerUnitPaisa: 4000,
        paymentStatus: 'Partial',
      );
      final harvestId = harvests.harvests.single.harvest.id!;
      final saleId = harvests.harvests.single.sale!.id!;

      await harvests.deleteSale(saleId);
      expect(
        (await db.query(
          'sales',
          columns: const ['harvest_payment_status_at_delete'],
          where: 'id = ?',
          whereArgs: [saleId],
        )).single['harvest_payment_status_at_delete'],
        'Partial',
      );

      await harvests.restoreSale(saleId);
      final hRow =
          (await db.query(
            'harvests',
            where: 'id = ?',
            whereArgs: [harvestId],
          )).single;
      expect(hRow['payment_status'], 'Partial');
      expect(hRow['rate_per_unit_paisa'], 4000);
      await harvests.fetchHarvests();
      expect(harvests.harvests.single.harvest.grossPaisa, 200000);
    });

    test('restoreSale never clobbers a newer re-sale (status included)',
        () async {
      final harvests = HarvestProvider(testExecutor: db);
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
      final oldSaleId = harvests.harvests.single.sale!.id!;
      await harvests.deleteSale(oldSaleId);

      // Re-sold at a new price before the old sale is restored.
      await harvests.recordSale(
        harvestId: harvestId,
        quantity: 10.0,
        pricePerUnitPaisa: 6000,
        date: '2026-05-11',
        buyerName: 'نیا آڑھتی',
      );
      await harvests.restoreSale(oldSaleId);

      // The live re-sale wins on every field.
      final hRow =
          (await db.query(
            'harvests',
            where: 'id = ?',
            whereArgs: [harvestId],
          )).single;
      expect(hRow['rate_per_unit_paisa'], 6000);
      expect(hRow['buyer_name'], 'نیا آڑھتی');
      expect(hRow['payment_status'], 'Paid');
      // The old sale row itself still comes back, as history.
      expect(await deletedAt('sales', oldSaleId), isNull);
    });
  });

  group('expense: idempotent, SEC1 stock-neutral', () {
    test('delete → restore → repeat never moves stock or duplicates',
        () async {
      final expenses = ExpenseProvider(testExecutor: db);
      final inventory = InventoryProvider(testExecutor: db);

      // 10 بوری purchased, then a 250,000-paisa expense that uses 3 بوری.
      final itemId = await inventory.recordPurchase(
        category: 'کھاد',
        name: 'یوریا',
        unit: 'بوری',
        quantity: 10.0,
        costPerUnitPaisa: 100000,
      );
      final expenseId = await expenses.addExpense(
        category: 'Fertilizer',
        amountPaisa: 250000,
        date: '2026-05-01',
        description: 'یوریا',
      );
      await inventory.recordUsage(
        itemId: itemId,
        quantity: 3.0,
        notes: 'خرچہ #$expenseId: یوریا',
      );
      Future<double> stock() async =>
          (await inventory.getItemById(itemId))!.quantity;
      expect(await stock(), 7.0);
      expect(expenses.totalExpensesPaisa, 250000);

      await expenses.deleteExpense(expenseId);
      // SEC1: the physical use stays deducted — no phantom restock…
      expect(await stock(), 7.0);
      expect(await deletedAt('expenses', expenseId), isNotNull);
      expect(await auditCount('expenses', 'soft_delete'), 1);
      await expenses.fetchExpenses();
      expect(expenses.totalExpensesPaisa, 0);

      // …and deleting again changes nothing.
      await expenses.deleteExpense(expenseId);
      expect(await stock(), 7.0);
      expect(await auditCount('expenses', 'soft_delete'), 1);

      await expenses.restoreExpense(expenseId);
      // …nor does restore re-deduct: the cycle's net stock effect is zero.
      expect(await stock(), 7.0);
      expect(await deletedAt('expenses', expenseId), isNull);
      expect(await auditCount('expenses', 'restore'), 1);
      await expenses.fetchExpenses();
      expect(expenses.totalExpensesPaisa, 250000);

      await expenses.restoreExpense(expenseId);
      expect(await stock(), 7.0);
      expect(await auditCount('expenses', 'restore'), 1);

      await expenses.deleteExpense(expenseId);
      await expenses.permanentDeleteExpense(expenseId);
      expect(await db.query('expenses'), isEmpty);
      expect(await auditCount('expenses', 'permanent_delete'), 1);
      // The ledger still shows the real physical use.
      expect(await stock(), 7.0);
    });
  });

  group('task: atomic + idempotent', () {
    test('delete → restore → repeat with single audit rows', () async {
      final tasks = TaskProvider(testExecutor: db);
      await tasks.addTask(
        'پانی لگانا',
        null,
        DateTime.now().add(const Duration(days: 1)),
      );
      final id = tasks.tasks.single.id;

      await tasks.deleteTask(id);
      expect(await deletedAt('tasks', id), isNotNull);
      expect(await auditCount('tasks', 'soft_delete'), 1);
      expect(tasks.tasks, isEmpty);

      await tasks.deleteTask(id);
      expect(await auditCount('tasks', 'soft_delete'), 1);

      await tasks.restoreTask(id);
      expect(await deletedAt('tasks', id), isNull);
      expect(await auditCount('tasks', 'restore'), 1);
      await tasks.fetchTasks();
      expect(tasks.tasks, hasLength(1));

      await tasks.restoreTask(id);
      expect(await auditCount('tasks', 'restore'), 1);

      await tasks.deleteTask(id);
      await tasks.permanentDeleteTask(id);
      expect(await db.query('tasks'), isEmpty);
      expect(await auditCount('tasks', 'permanent_delete'), 1);
    });

    test('delete/restore of a missing task are safe no-ops', () async {
      final tasks = TaskProvider(testExecutor: db);
      await tasks.deleteTask(999999);
      await tasks.restoreTask(999999);
      expect(await auditCount('tasks', 'soft_delete'), 0);
      expect(await auditCount('tasks', 'restore'), 0);
    });
  });

  group('party: idempotent, entry-block preserved', () {
    test('delete → restore → repeat with single audit rows', () async {
      final parties = PartyProvider(testExecutor: db);
      final id = await parties.addParty(
        Party(name: 'دانش', createdAt: DateTime.now().toIso8601String()),
      );

      await parties.deleteParty(id);
      expect(await deletedAt('parties', id), isNotNull);
      expect(await auditCount('parties', 'soft_delete'), 1);
      await parties.fetchParties();
      expect(parties.parties, isEmpty);

      await parties.deleteParty(id);
      expect(await auditCount('parties', 'soft_delete'), 1);

      await parties.restoreParty(id);
      expect(await deletedAt('parties', id), isNull);
      expect(await auditCount('parties', 'restore'), 1);

      await parties.restoreParty(id);
      expect(await auditCount('parties', 'restore'), 1);

      await parties.deleteParty(id);
      await parties.permanentDeleteParty(id);
      expect(await db.query('parties'), isEmpty);
      expect(await auditCount('parties', 'permanent_delete'), 1);
    });

    test('party with ledger entries still cannot be deleted', () async {
      final parties = PartyProvider(testExecutor: db);
      final id = await parties.addParty(
        Party(name: 'ادھار پارٹی', createdAt: DateTime.now().toIso8601String()),
      );
      await parties.addEntry(
        partyId: id,
        type: PartyEntryType.udhaarDiya,
        amountPaisa: 50000,
        date: '2026-05-01',
      );
      expect(() => parties.deleteParty(id), throwsA(isA<PartyException>()));
      expect(await deletedAt('parties', id), isNull);
    });
  });
}
