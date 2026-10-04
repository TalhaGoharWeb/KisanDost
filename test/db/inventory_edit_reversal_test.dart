import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:kisan_dost/database/db_helper.dart';
import 'package:kisan_dost/providers/activity_provider.dart';
import 'package:kisan_dost/providers/inventory_provider.dart';
import 'package:kisan_dost/services/unit_converter.dart';

/// Edit-reversal, delete-restore and concurrency tests for the inventory
/// ledger. They exercise the REAL provider methods ([ActivityProvider]
/// add/update/delete with an [InventoryProvider]) against the REAL
/// fresh-install schema on an in-memory FFI database.
///
/// The farmer-visible contract under test:
/// * EDITING a usage reverses the old deduction and applies the new one —
///   it must NEVER just deduct again (10 bags, use 2 -> 8; edit to 5 must
///   give 5, not 3).
/// * DELETING a usage activity returns the stock.
/// * Unit conversions apply identically to the reversal and the new
///   deduction (deduct in bags, edit in kg — both sides convert).
/// * Two rapid deductions are serialized: one wins, the other is rejected
///   loudly; stock can never go negative.
/// * `inventory.quantity` always equals the signed sum of the
///   `inventory_transactions` rows (ledger/cache can never disagree).
void main() {
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  late Database db;
  late InventoryProvider inventory;
  late ActivityProvider activities;
  late int seasonId;

  Future<Database> openFreshDb() {
    return openDatabase(
      inMemoryDatabasePath,
      onConfigure: (db) async {
        await db.execute('PRAGMA foreign_keys = ON');
      },
    );
  }

  Future<double> stockOf(int itemId) async {
    final item = await inventory.getItemById(itemId, executor: db);
    return item!.quantity;
  }

  /// Signed sum of every ledger row for the item — the source of truth the
  /// cached `inventory.quantity` must always agree with.
  Future<double> ledgerSum(int itemId) async {
    final rows = await db.rawQuery(
      'SELECT SUM(quantity) AS s FROM inventory_transactions WHERE inventory_id = ?',
      [itemId],
    );
    return (rows.first['s'] as num).toDouble();
  }

  Future<int> ledgerRowCount(int itemId) async {
    final rows = await db.rawQuery(
      'SELECT COUNT(*) AS c FROM inventory_transactions WHERE inventory_id = ?',
      [itemId],
    );
    return (rows.first['c'] as int?) ?? 0;
  }

  Future<void> expectLedgerConsistent(int itemId) async {
    expect(
      await stockOf(itemId),
      moreOrLessEquals(await ledgerSum(itemId)),
      reason: 'inventory.quantity must equal the signed ledger sum',
    );
  }

  setUp(() async {
    db = await openFreshDb();
    await DatabaseHelper.instance.createFreshSchemaForTests(db);

    final farmId = await db.insert('farms', {
      'name': 'ٹیسٹ فارم',
      'total_area': 5.0,
      'created_at': DateTime.now().toIso8601String(),
    });
    final fieldId = await db.insert('fields', {
      'farm_id': farmId,
      'name': 'کھیت 1',
      'size_acres': 5.0,
    });
    seasonId = await db.insert('crop_seasons', {
      'field_id': fieldId,
      'crop_name': 'گندم',
      'variety': 'دیسی',
      'status': 'active',
      'start_date': '2026-01-01',
    });
    await db.insert('crop_season_fields', {
      'crop_season_id': seasonId,
      'field_id': fieldId,
    });

    inventory = InventoryProvider(testExecutor: db);
    activities = ActivityProvider(testExecutor: db);
  });

  tearDown(() async {
    await db.close();
  });

  group('edit reversal', () {
    test('edit reverses the old deduction, does not deduct again', () async {
      final itemId = await inventory.recordPurchase(
        category: 'Fertilizer',
        name: 'یوریا',
        unit: 'بوری',
        quantity: 10,
        costPerUnitPaisa: 200000,
        executor: db,
      );

      // Use 2 bags through the real activity path.
      await activities.addActivity(
        cropSeasonId: seasonId,
        activityType: 'کھاد ڈالی',
        date: '2026-02-01',
        details: 'پہلی بار',
        inventoryCategory: 'Fertilizer',
        inventoryName: 'یوریا',
        inventoryUnit: 'بوری',
        inventoryQuantity: 2,
        inventoryItemId: itemId,
        inventoryProvider: inventory,
      );
      expect(await stockOf(itemId), 8);
      await expectLedgerConsistent(itemId);
      final activityId =
          (await db.query('activities', orderBy: 'id DESC')).first['id'] as int;

      // Edit the usage from 2 bags to 5 bags: 8 + 2 (reversal) - 5 = 5.
      // A double-deduct bug would give 3.
      await activities.updateActivity(
        id: activityId,
        cropSeasonId: seasonId,
        activityType: 'کھاد ڈالی',
        date: '2026-02-01',
        details: 'ترمیم شدہ',
        inventoryCategory: 'Fertilizer',
        inventoryName: 'یوریا',
        inventoryUnit: 'بوری',
        inventoryQuantity: 5,
        inventoryItemId: itemId,
        inventoryProvider: inventory,
      );

      expect(await stockOf(itemId), 5);
      await expectLedgerConsistent(itemId);

      // The ledger tells the story: +10 purchase, -2 usage, +2 reversal
      // (adjustment), -5 new usage.
      final rows = await db.query(
        'inventory_transactions',
        where: 'inventory_id = ?',
        whereArgs: [itemId],
        orderBy: 'id ASC',
      );
      expect(rows.map((r) => r['quantity']), [10.0, -2.0, 2.0, -5.0]);
      expect(rows[2]['type'], 'adjustment');
    });

    test('editing to a smaller quantity returns the difference', () async {
      final itemId = await inventory.recordPurchase(
        category: 'Fertilizer',
        name: 'یوریا',
        unit: 'بوری',
        quantity: 10,
        costPerUnitPaisa: 200000,
        executor: db,
      );
      await activities.addActivity(
        cropSeasonId: seasonId,
        activityType: 'کھاد ڈالی',
        date: '2026-02-01',
        details: '',
        inventoryCategory: 'Fertilizer',
        inventoryName: 'یوریا',
        inventoryUnit: 'بوری',
        inventoryQuantity: 5,
        inventoryItemId: itemId,
        inventoryProvider: inventory,
      );
      expect(await stockOf(itemId), 5);
      final activityId =
          (await db.query('activities', orderBy: 'id DESC')).first['id'] as int;

      await activities.updateActivity(
        id: activityId,
        cropSeasonId: seasonId,
        activityType: 'کھاد ڈالی',
        date: '2026-02-01',
        details: '',
        inventoryCategory: 'Fertilizer',
        inventoryName: 'یوریا',
        inventoryUnit: 'بوری',
        inventoryQuantity: 2,
        inventoryItemId: itemId,
        inventoryProvider: inventory,
      );

      // 5 + 5 (reversal) - 2 = 8.
      expect(await stockOf(itemId), 8);
      await expectLedgerConsistent(itemId);
    });

    test('removing the usage on edit restores the full old deduction',
        () async {
      final itemId = await inventory.recordPurchase(
        category: 'Fertilizer',
        name: 'یوریا',
        unit: 'بوری',
        quantity: 10,
        costPerUnitPaisa: 200000,
        executor: db,
      );
      await activities.addActivity(
        cropSeasonId: seasonId,
        activityType: 'کھاد ڈالی',
        date: '2026-02-01',
        details: '',
        inventoryCategory: 'Fertilizer',
        inventoryName: 'یوریا',
        inventoryUnit: 'بوری',
        inventoryQuantity: 2,
        inventoryItemId: itemId,
        inventoryProvider: inventory,
      );
      final activityId =
          (await db.query('activities', orderBy: 'id DESC')).first['id'] as int;

      // Edit that drops the inventory usage entirely (null quantity):
      // the old 2 bags come back, nothing new is deducted.
      await activities.updateActivity(
        id: activityId,
        cropSeasonId: seasonId,
        activityType: 'کھاد ڈالی',
        date: '2026-02-01',
        details: 'بغیر کھاد',
        inventoryQuantity: null,
        inventoryItemId: null,
        inventoryProvider: inventory,
      );

      expect(await stockOf(itemId), 10);
      await expectLedgerConsistent(itemId);
    });

    test('edit that would overuse aborts cleanly: stock untouched', () async {
      final itemId = await inventory.recordPurchase(
        category: 'Fertilizer',
        name: 'یوریا',
        unit: 'بوری',
        quantity: 10,
        costPerUnitPaisa: 200000,
        executor: db,
      );
      await activities.addActivity(
        cropSeasonId: seasonId,
        activityType: 'کھاد ڈالی',
        date: '2026-02-01',
        details: '',
        inventoryCategory: 'Fertilizer',
        inventoryName: 'یوریا',
        inventoryUnit: 'بوری',
        inventoryQuantity: 2,
        inventoryItemId: itemId,
        inventoryProvider: inventory,
      );
      expect(await stockOf(itemId), 8);
      final before = await ledgerRowCount(itemId);
      final activityId =
          (await db.query('activities', orderBy: 'id DESC')).first['id'] as int;

      // 8 in stock; editing to 20 must fail LOUDLY — and the reversal that
      // ran first inside the same transaction must roll back too.
      await expectLater(
        activities.updateActivity(
          id: activityId,
          cropSeasonId: seasonId,
          activityType: 'کھاد ڈالی',
          date: '2026-02-01',
          details: '',
          inventoryCategory: 'Fertilizer',
          inventoryName: 'یوریا',
          inventoryUnit: 'بوری',
          inventoryQuantity: 20,
          inventoryItemId: itemId,
          inventoryProvider: inventory,
        ),
        throwsA(isA<InventoryException>()),
      );

      expect(await stockOf(itemId), 8);
      expect(await ledgerRowCount(itemId), before);
      await expectLedgerConsistent(itemId);
    });
  });

  group('unit-mismatch edits', () {
    test('deduct in bags, edit in kg: both sides convert consistently',
        () async {
      final itemId = await inventory.recordPurchase(
        category: 'Fertilizer',
        name: 'یوریا',
        unit: 'بوری',
        quantity: 10,
        costPerUnitPaisa: 200000,
        weightPerUnitKg: 50,
        executor: db,
      );
      await activities.addActivity(
        cropSeasonId: seasonId,
        activityType: 'کھاد ڈالی',
        date: '2026-02-01',
        details: '',
        inventoryCategory: 'Fertilizer',
        inventoryName: 'یوریا',
        inventoryUnit: 'بوری',
        inventoryQuantity: 2,
        inventoryItemId: itemId,
        inventoryProvider: inventory,
      );
      expect(await stockOf(itemId), 8);
      final activityId =
          (await db.query('activities', orderBy: 'id DESC')).first['id'] as int;

      // Edit to 150 kg = 3 bags: 8 + 2 (reversal) - 3 = 7.
      await activities.updateActivity(
        id: activityId,
        cropSeasonId: seasonId,
        activityType: 'کھاد ڈالی',
        date: '2026-02-01',
        details: '',
        inventoryCategory: 'Fertilizer',
        inventoryName: 'یوریا',
        inventoryUnit: 'کلوگرام',
        inventoryQuantity: 150,
        inventoryItemId: itemId,
        inventoryProvider: inventory,
      );

      expect(await stockOf(itemId), 7);
      await expectLedgerConsistent(itemId);
    });

    test('deduct in kg, edit in bags: the reversal converts too', () async {
      final itemId = await inventory.recordPurchase(
        category: 'Fertilizer',
        name: 'یوریا',
        unit: 'بوری',
        quantity: 10,
        costPerUnitPaisa: 200000,
        weightPerUnitKg: 50,
        executor: db,
      );
      // Deduct 100 kg (= 2 bags) — snapshot stored in kg.
      await activities.addActivity(
        cropSeasonId: seasonId,
        activityType: 'کھاد ڈالی',
        date: '2026-02-01',
        details: '',
        inventoryCategory: 'Fertilizer',
        inventoryName: 'یوریا',
        inventoryUnit: 'کلوگرام',
        inventoryQuantity: 100,
        inventoryItemId: itemId,
        inventoryProvider: inventory,
      );
      expect(await stockOf(itemId), 8);
      final activityId =
          (await db.query('activities', orderBy: 'id DESC')).first['id'] as int;

      // Edit to 1 bag: the reversal converts 100 kg back to 2 bags
      // (8 + 2 - 1 = 9). A reversal that forgot to convert would add back
      // 100 (bags!) and corrupt the stock.
      await activities.updateActivity(
        id: activityId,
        cropSeasonId: seasonId,
        activityType: 'کھاد ڈالی',
        date: '2026-02-01',
        details: '',
        inventoryCategory: 'Fertilizer',
        inventoryName: 'یوریا',
        inventoryUnit: 'بوری',
        inventoryQuantity: 1,
        inventoryItemId: itemId,
        inventoryProvider: inventory,
      );

      expect(await stockOf(itemId), 9);
      await expectLedgerConsistent(itemId);
    });
  });

  group('delete restores stock', () {
    test('deleting a usage activity returns the deducted stock', () async {
      final itemId = await inventory.recordPurchase(
        category: 'Fertilizer',
        name: 'یوریا',
        unit: 'بوری',
        quantity: 10,
        costPerUnitPaisa: 200000,
        executor: db,
      );
      await activities.addActivity(
        cropSeasonId: seasonId,
        activityType: 'کھاد ڈالی',
        date: '2026-02-01',
        details: '',
        inventoryCategory: 'Fertilizer',
        inventoryName: 'یوریا',
        inventoryUnit: 'بوری',
        inventoryQuantity: 2,
        inventoryItemId: itemId,
        inventoryProvider: inventory,
      );
      expect(await stockOf(itemId), 8);
      final activityId =
          (await db.query('activities', orderBy: 'id DESC')).first['id'] as int;

      await activities.deleteActivity(activityId, inventoryProvider: inventory);

      expect(await stockOf(itemId), 10);
      await expectLedgerConsistent(itemId);

      // The usage ledger row survives (immutable history); its activity
      // link is cleared by ON DELETE SET NULL.
      final rows = await db.query(
        'inventory_transactions',
        where: 'inventory_id = ?',
        whereArgs: [itemId],
        orderBy: 'id ASC',
      );
      expect(rows.map((r) => r['quantity']), [10.0, -2.0, 2.0]);
      expect(rows[1]['activity_id'], isNull);
    });

    test('deleting an activity without usage leaves stock alone', () async {
      final itemId = await inventory.recordPurchase(
        category: 'Fertilizer',
        name: 'یوریا',
        unit: 'بوری',
        quantity: 10,
        costPerUnitPaisa: 200000,
        executor: db,
      );
      await activities.addActivity(
        cropSeasonId: seasonId,
        activityType: 'پانی لگایا',
        date: '2026-02-01',
        details: 'نہر',
        inventoryProvider: inventory,
      );
      final activityId =
          (await db.query('activities', orderBy: 'id DESC')).first['id'] as int;

      await activities.deleteActivity(activityId, inventoryProvider: inventory);

      expect(await stockOf(itemId), 10);
      expect(await ledgerRowCount(itemId), 1);
    });
  });

  group('concurrent deductions', () {
    test('two rapid full-stock deductions: one wins, one is rejected',
        () async {
      final itemId = await inventory.recordPurchase(
        category: 'Fertilizer',
        name: 'یوریا',
        unit: 'بوری',
        quantity: 10,
        costPerUnitPaisa: 200000,
        executor: db,
      );

      // Fire both deductions the way the app does (no explicit executor,
      // so each wraps its check+write in its own db.transaction) without
      // awaiting in between — the way two rapid taps would.
      final results = await Future.wait([
        inventory
            .recordUsage(itemId: itemId, quantity: 10)
            .then((_) => 'ok')
            .catchError((e) => 'error:${e.runtimeType}'),
        inventory
            .recordUsage(itemId: itemId, quantity: 10)
            .then((_) => 'ok')
            .catchError((e) => 'error:${e.runtimeType}'),
      ]);

      // Exactly one deduction lands; the loser is rejected loudly.
      expect(results.where((r) => r == 'ok'), hasLength(1));
      expect(
        results.where((r) => r == 'error:InventoryException'),
        hasLength(1),
      );

      // Stock is exactly 0 — never negative, never double-deducted.
      expect(await stockOf(itemId), 0);
      await expectLedgerConsistent(itemId);
      final usageRows = await db.query(
        'inventory_transactions',
        where: 'inventory_id = ? AND type = ?',
        whereArgs: [itemId, 'usage'],
      );
      expect(usageRows, hasLength(1));
    });
  });
}
