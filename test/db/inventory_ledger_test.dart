import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:kisan_dost/database/db_helper.dart';
import 'package:kisan_dost/providers/inventory_provider.dart';
import 'package:kisan_dost/services/unit_converter.dart';

/// Hermetic tests for the v11 inventory ledger. They exercise the REAL
/// migration SQL ([DatabaseHelper.migrateV10ToV11]) and the REAL provider
/// mutation methods against an in-memory FFI database — the provider is
/// given the test database via its `executor` parameter, so the app
/// singleton (path_provider) is never touched.
///
/// What "correct" means here, from the farmer's point of view:
/// * every stock movement leaves a ledger row AND moves the cached total
///   in one transaction — the two can never disagree;
/// * impossible stock (using more than exists, negative totals) is
///   rejected LOUDLY with a Urdu message — never clamped, never silent.
void main() {
  sqfliteFfiInit();
  // Route package:sqflite through the FFI backend for these tests.
  databaseFactory = databaseFactoryFfi;

  /// The v10-shaped schema: the two tables the v11 migration touches,
  /// without the v11 columns.
  Future<void> createV10Schema(Database db) async {
    await db.execute('''
      CREATE TABLE inventory (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        category TEXT NOT NULL,
        name TEXT NOT NULL,
        unit TEXT NOT NULL,
        quantity REAL NOT NULL,
        cost_per_unit REAL NOT NULL
      )
    ''');
    await db.execute('''
      CREATE TABLE activities (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        crop_season_id INTEGER NOT NULL,
        activity_type TEXT NOT NULL,
        date TEXT NOT NULL,
        details TEXT,
        expense_id INTEGER,
        expense_category TEXT,
        inventory_category TEXT,
        inventory_name TEXT,
        inventory_unit TEXT,
        inventory_quantity REAL,
        is_completed INTEGER NOT NULL DEFAULT 0
      )
    ''');
  }

  Future<Database> openV10Db() {
    return openDatabase(
      inMemoryDatabasePath,
      onConfigure: (db) async {
        // Same as DatabaseHelper._initDatabase: FKs must be enforced for
        // the ledger's ON DELETE CASCADE to work.
        await db.execute('PRAGMA foreign_keys = ON');
      },
    );
  }

  Future<List<Map<String, dynamic>>> ledgerRows(Database db, int itemId) {
    return db.query(
      'inventory_transactions',
      where: 'inventory_id = ?',
      whereArgs: [itemId],
      orderBy: 'id ASC',
    );
  }

  group('DB v11 migration', () {
    test('creates the ledger table, new columns, backfills opening balances',
        () async {
      final db = await openV10Db();
      await createV10Schema(db);

      final itemId = await db.insert('inventory', {
        'category': 'Fertilizer',
        'name': 'یوریا',
        'unit': 'بوری',
        'quantity': 7.0,
        'cost_per_unit': 2000.0,
      });
      await db.insert('inventory', {
        'category': 'Seed',
        'name': 'گندم بیج',
        'unit': 'کلوگرام',
        'quantity': 40.0,
        'cost_per_unit': 100.0,
      });
      // Pre-v11 activity referencing the first item by name.
      final linkedActivity = await db.insert('activities', {
        'crop_season_id': 1,
        'activity_type': 'کھاد ڈالی',
        'date': '2026-01-05',
        'inventory_category': 'Fertilizer',
        'inventory_name': 'یوریا',
        'inventory_unit': 'بوری',
        'inventory_quantity': 2.0,
      });
      // Activity referencing an item that does not exist.
      final orphanActivity = await db.insert('activities', {
        'crop_season_id': 1,
        'activity_type': 'کھاد ڈالی',
        'date': '2026-01-06',
        'inventory_category': 'Fertilizer',
        'inventory_name': 'ڈی اے پی',
        'inventory_unit': 'بوری',
        'inventory_quantity': 1.0,
      });

      await DatabaseHelper.migrateV10ToV11(db);

      // Ledger table exists with the expected columns.
      final tables = await db.rawQuery(
        "SELECT name FROM sqlite_master WHERE type = 'table' AND name = 'inventory_transactions'",
      );
      expect(tables, hasLength(1));
      final txColumns = await db.rawQuery("PRAGMA table_info('inventory_transactions')");
      final txNames = txColumns.map((c) => c['name'] as String).toSet();
      expect(
        txNames,
        containsAll([
          'inventory_id',
          'type',
          'quantity',
          'unit',
          'unit_price',
          'total_amount',
          'activity_id',
          'date',
          'notes',
          'created_at',
        ]),
      );

      // New columns on the old tables.
      final invColumns = await db.rawQuery("PRAGMA table_info('inventory')");
      expect(
        invColumns.map((c) => c['name']),
        contains('weight_per_unit_kg'),
      );
      final actColumns = await db.rawQuery("PRAGMA table_info('activities')");
      expect(
        actColumns.map((c) => c['name']),
        contains('inventory_item_id'),
      );

      // One opening_balance row per pre-existing item.
      final backfill = await db.query(
        'inventory_transactions',
        where: "type = 'opening_balance'",
        orderBy: 'id ASC',
      );
      expect(backfill, hasLength(2));
      expect(backfill[0]['quantity'], 7.0);
      expect(backfill[0]['unit'], 'بوری');
      expect(backfill[1]['quantity'], 40.0);

      // The matching activity is linked to the exact item row; the
      // non-matching one stays NULL instead of guessing.
      final linked = (await db.query('activities',
              where: 'id = ?', whereArgs: [linkedActivity]))
          .single;
      expect(linked['inventory_item_id'], itemId);
      final orphan = (await db.query('activities',
              where: 'id = ?', whereArgs: [orphanActivity]))
          .single;
      expect(orphan['inventory_item_id'], isNull);

      await db.close();
    });

    test('migration is idempotent', () async {
      final db = await openV10Db();
      await createV10Schema(db);
      await db.insert('inventory', {
        'category': 'Fertilizer',
        'name': 'یوریا',
        'unit': 'بوری',
        'quantity': 7.0,
        'cost_per_unit': 2000.0,
      });

      await DatabaseHelper.migrateV10ToV11(db);
      // A second run must not duplicate the backfill (the ALTERs are
      // caught, the backfill is skipped because rows already exist).
      await DatabaseHelper.migrateV10ToV11(db);

      final backfill = await db.query(
        'inventory_transactions',
        where: "type = 'opening_balance'",
      );
      expect(backfill, hasLength(1));
      await db.close();
    });
  });

  group('inventory ledger via InventoryProvider', () {
    late Database db;
    late InventoryProvider provider;

    setUp(() async {
      db = await openV10Db();
      await createV10Schema(db);
      await DatabaseHelper.migrateV10ToV11(db);
      provider = InventoryProvider();
    });

    tearDown(() async {
      await db.close();
    });

    test('recordPurchase creates the item and a purchase ledger row',
        () async {
      final id = await provider.recordPurchase(
        category: 'Fertilizer',
        name: 'یوریا',
        unit: 'بوری',
        quantity: 10,
        costPerUnit: 2000,
        weightPerUnitKg: 50,
        executor: db,
      );

      final item = await provider.getItemById(id, executor: db);
      expect(item, isNotNull);
      expect(item!.quantity, 10);
      expect(item.weightPerUnitKg, 50);

      final rows = await ledgerRows(db, id);
      expect(rows, hasLength(1));
      expect(rows.single['type'], 'purchase');
      expect(rows.single['quantity'], 10);
      expect(rows.single['unit'], 'بوری');
      expect(rows.single['unit_price'], 2000);
      expect(rows.single['total_amount'], 20000);
    });

    test('recordPurchase merges with weighted-average cost', () async {
      final id = await provider.recordPurchase(
        category: 'Fertilizer',
        name: 'یوریا',
        unit: 'بوری',
        quantity: 10,
        costPerUnit: 2000,
        executor: db,
      );
      final id2 = await provider.recordPurchase(
        category: 'Fertilizer',
        name: 'یوریا',
        unit: 'بوری',
        quantity: 10,
        costPerUnit: 3000,
        executor: db,
      );
      expect(id2, id);

      final item = await provider.getItemById(id, executor: db);
      expect(item!.quantity, 20);
      // (10*2000 + 10*3000) / 20 = 2500
      expect(item.costPerUnit, 2500);
      expect(await ledgerRows(db, id), hasLength(2));
    });

    test('recordPurchase merges cleanly over a legacy zero-quantity row',
        () async {
      // Pre-ledger corruption: a row with 0 stock and no ledger history.
      final id = await db.insert('inventory', {
        'category': 'Seed',
        'name': 'گندم بیج',
        'unit': 'کلوگرام',
        'quantity': 0.0,
        'cost_per_unit': 100.0,
      });

      final mergedId = await provider.recordPurchase(
        category: 'Seed',
        name: 'گندم بیج',
        unit: 'کلوگرام',
        quantity: 40,
        costPerUnit: 120,
        executor: db,
      );
      expect(mergedId, id);

      final item = await provider.getItemById(id, executor: db);
      expect(item!.quantity, 40);
      // No division by zero: (0*100 + 40*120) / 40.
      expect(item.costPerUnit, 120);
    });

    test('recordUsage deducts stock and writes a negative ledger row',
        () async {
      final id = await provider.recordPurchase(
        category: 'Fertilizer',
        name: 'یوریا',
        unit: 'بوری',
        quantity: 10,
        costPerUnit: 2000,
        executor: db,
      );
      await provider.recordUsage(
        itemId: id,
        quantity: 3,
        executor: db,
      );

      final item = await provider.getItemById(id, executor: db);
      expect(item!.quantity, 7);

      final rows = await ledgerRows(db, id);
      expect(rows, hasLength(2));
      final usage = rows.last;
      expect(usage['type'], 'usage');
      expect(usage['quantity'], -3);
      expect(usage['unit'], 'بوری');
      expect(usage['activity_id'], isNull);
    });

    test('recordUsage links the ledger row to its activity', () async {
      final id = await provider.recordPurchase(
        category: 'Fertilizer',
        name: 'یوریا',
        unit: 'بوری',
        quantity: 10,
        costPerUnit: 2000,
        executor: db,
      );
      final activityId = await db.insert('activities', {
        'crop_season_id': 1,
        'activity_type': 'کھاد ڈالی',
        'date': '2026-01-05',
      });

      await provider.recordUsage(
        itemId: id,
        quantity: 3,
        activityId: activityId,
        executor: db,
      );

      final usage = (await ledgerRows(db, id)).last;
      expect(usage['activity_id'], activityId);

      // Deleting the activity keeps the ledger row but clears the link.
      await db.delete('activities', where: 'id = ?', whereArgs: [activityId]);
      final kept = (await ledgerRows(db, id)).last;
      expect(kept['type'], 'usage');
      expect(kept['activity_id'], isNull);
    });

    test('recordUsage rejects overuse loudly; stock stays untouched',
        () async {
      final id = await provider.recordPurchase(
        category: 'Fertilizer',
        name: 'یوریا',
        unit: 'بوری',
        quantity: 10,
        costPerUnit: 2000,
        executor: db,
      );

      await expectLater(
        provider.recordUsage(itemId: id, quantity: 11, executor: db),
        throwsA(isA<InventoryException>()),
      );

      // No clamp to zero, no partial deduction, no ledger row.
      final item = await provider.getItemById(id, executor: db);
      expect(item!.quantity, 10);
      expect(await ledgerRows(db, id), hasLength(1));
    });

    test('recordUsage on a missing item throws', () async {
      await expectLater(
        provider.recordUsage(itemId: 9999, quantity: 1, executor: db),
        throwsA(isA<InventoryException>()),
      );
    });

    test('recordUsage converts the entered unit via UnitConverter', () async {
      final id = await provider.recordPurchase(
        category: 'Fertilizer',
        name: 'یوریا',
        unit: 'بوری',
        quantity: 10,
        costPerUnit: 2000,
        weightPerUnitKg: 50,
        executor: db,
      );

      // 100 kg out of 50-kg bags = 2 bags.
      await provider.recordUsage(
        itemId: id,
        quantity: 100,
        fromUnit: 'کلوگرام',
        executor: db,
      );

      final item = await provider.getItemById(id, executor: db);
      expect(item!.quantity, 8);

      final usage = (await ledgerRows(db, id)).last;
      expect(usage['type'], 'usage');
      expect(usage['quantity'], -2);
      expect(usage['unit'], 'بوری');
      expect(usage['notes'], contains('درج:'));
    });

    test('recordUsage without a declared package weight throws, stock kept',
        () async {
      final id = await provider.recordPurchase(
        category: 'Fertilizer',
        name: 'یوریا',
        unit: 'بوری',
        quantity: 10,
        costPerUnit: 2000,
        // No weightPerUnitKg on purpose.
        executor: db,
      );

      // The old code silently assumed 1 bag = 50 kg; now it must throw.
      await expectLater(
        provider.recordUsage(
          itemId: id,
          quantity: 100,
          fromUnit: 'کلوگرام',
          executor: db,
        ),
        throwsA(isA<UnitConversionException>()),
      );

      final item = await provider.getItemById(id, executor: db);
      expect(item!.quantity, 10);
      expect(await ledgerRows(db, id), hasLength(1));
    });

    test('recordAdjustment writes a signed ledger row with a reason',
        () async {
      final id = await provider.recordPurchase(
        category: 'Seed',
        name: 'گندم بیج',
        unit: 'کلوگرام',
        quantity: 40,
        costPerUnit: 100,
        executor: db,
      );
      await provider.recordAdjustment(
        itemId: id,
        quantityDelta: -2.5,
        reason: 'گنتی میں فرق',
        executor: db,
      );

      final item = await provider.getItemById(id, executor: db);
      expect(item!.quantity, 37.5);

      final rows = await ledgerRows(db, id);
      expect(rows, hasLength(2));
      expect(rows.last['type'], 'adjustment');
      expect(rows.last['quantity'], -2.5);
      expect(rows.last['notes'], 'گنتی میں فرق');
    });

    test('recordAdjustment rejects empty reason, zero delta, negative stock',
        () async {
      final id = await provider.recordPurchase(
        category: 'Seed',
        name: 'گندم بیج',
        unit: 'کلوگرام',
        quantity: 40,
        costPerUnit: 100,
        executor: db,
      );

      await expectLater(
        provider.recordAdjustment(
            itemId: id, quantityDelta: -1, reason: '   ', executor: db),
        throwsA(isA<InventoryException>()),
      );
      await expectLater(
        provider.recordAdjustment(
            itemId: id, quantityDelta: 0, reason: 'وجہ', executor: db),
        throwsA(isA<InventoryException>()),
      );
      await expectLater(
        provider.recordAdjustment(
            itemId: id, quantityDelta: -50, reason: 'وجہ', executor: db),
        throwsA(isA<InventoryException>()),
      );

      final item = await provider.getItemById(id, executor: db);
      expect(item!.quantity, 40);
      expect(await ledgerRows(db, id), hasLength(1));
    });

    test('updateItemDetails edits metadata without touching the ledger',
        () async {
      final id = await provider.recordPurchase(
        category: 'Fertilizer',
        name: 'یوریا',
        unit: 'بوری',
        quantity: 10,
        costPerUnit: 2000,
        executor: db,
      );
      await provider.recordPurchase(
        category: 'Fertilizer',
        name: 'ڈی اے پی',
        unit: 'بوری',
        quantity: 5,
        costPerUnit: 3000,
        executor: db,
      );

      // A rename onto another item's (category, name, unit) key is
      // rejected loudly — no silent merge.
      await expectLater(
        provider.updateItemDetails(
          id: id,
          category: 'Fertilizer',
          name: 'ڈی اے پی',
          unit: 'بوری',
          costPerUnit: 2000,
          executor: db,
        ),
        throwsA(isA<InventoryException>()),
      );

      // A clean metadata edit leaves quantity and ledger alone.
      await provider.updateItemDetails(
        id: id,
        category: 'Fertilizer',
        name: 'یوریا دانے دار',
        unit: 'بوری',
        costPerUnit: 2100,
        weightPerUnitKg: 50,
        executor: db,
      );
      final item = await provider.getItemById(id, executor: db);
      expect(item!.name, 'یوریا دانے دار');
      expect(item.costPerUnit, 2100);
      expect(item.weightPerUnitKg, 50);
      expect(item.quantity, 10);
      // Only the original purchase row — metadata edits write no ledger.
      expect(await ledgerRows(db, id), hasLength(1));
    });

    test('getTransactions returns history newest first', () async {
      final id = await provider.recordPurchase(
        category: 'Fertilizer',
        name: 'یوریا',
        unit: 'بوری',
        quantity: 10,
        costPerUnit: 2000,
        executor: db,
      );
      await provider.recordUsage(itemId: id, quantity: 2, executor: db);
      await provider.recordAdjustment(
        itemId: id,
        quantityDelta: 1,
        reason: 'اضافی اسٹاک ملا',
        executor: db,
      );

      final txs = await provider.getTransactions(id, executor: db);
      expect(txs.map((t) => t.type), ['adjustment', 'usage', 'purchase']);
      expect(txs.map((t) => t.typeUrdu), ['تصحیح', 'استعمال', 'خریداری']);
      expect(txs[1].quantity, -2);
      expect(txs[0].notes, 'اضافی اسٹاک ملا');
    });

    test('deleteInventoryItem cascades the ledger rows', () async {
      final id = await provider.recordPurchase(
        category: 'Fertilizer',
        name: 'یوریا',
        unit: 'بوری',
        quantity: 10,
        costPerUnit: 2000,
        executor: db,
      );
      await provider.recordUsage(itemId: id, quantity: 2, executor: db);
      expect(await ledgerRows(db, id), hasLength(2));

      await provider.deleteInventoryItem(id, executor: db);
      expect(await provider.getItemById(id, executor: db), isNull);
      expect(await ledgerRows(db, id), isEmpty);
    });
  });
}
