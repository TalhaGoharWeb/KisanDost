import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:kisan_dost/database/db_helper.dart';
import 'package:kisan_dost/models/fertilizer_plan.dart';
import 'package:kisan_dost/providers/fertilizer_plan_provider.dart';

/// Hermetic tests for Khaad Hisaab saved plans + the v17 -> v18
/// migration, against the REAL production schema (in-memory FFI).
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

  FertilizerPlan samplePlan() => FertilizerPlan(
    cropName: 'گندم',
    variantName: 'آبپاشی علاقہ — اوسط زرخیز زمین',
    areaAcres: 3.5,
    targetNKg: 57,
    targetPKg: 46,
    targetKKg: 25,
    source: 'محکمہ زراعت پنجاب (پاکٹ بک 2022)',
    isOfficial: true,
    createdAt: '2026-10-21T10:00:00',
    items: const [
      FertilizerPlanItem(
        productId: 'dap',
        productName: 'ڈی اے پی',
        kgPerAcre: 100,
        totalKg: 350,
        pricePerBagPaisa: 1450000,
      ),
      FertilizerPlanItem(
        productId: 'urea',
        productName: 'یوریا',
        kgPerAcre: 84.8,
        totalKg: 296.7,
      ),
    ],
  );

  group('migration v17 -> v18', () {
    test('creates plan tables and is idempotent', () async {
      final db = await openDatabase(inMemoryDatabasePath);
      // Simulate a v17 database: no fertilizer tables.
      await db.execute(
        'CREATE TABLE farms (id INTEGER PRIMARY KEY, name TEXT)',
      );
      await db.insert('farms', {'id': 1, 'name': 'موجودہ زمین'});

      await DatabaseHelper.migrateV17ToV18(db);
      await DatabaseHelper.migrateV17ToV18(db); // second run: no error

      final tables = await db.rawQuery(
        "SELECT name FROM sqlite_master WHERE type='table' "
        "AND name LIKE 'fertilizer_plan%' ORDER BY name",
      );
      expect(tables.map((t) => t['name']), [
        'fertilizer_plan_items',
        'fertilizer_plans',
      ]);
      // Pre-existing data untouched.
      final farms = await db.query('farms');
      expect(farms.single['name'], 'موجودہ زمین');
      await db.close();
    });
  });

  group('FertilizerPlanProvider', () {
    test('fresh schema includes the plan tables', () async {
      final db = await openFreshDb();
      final tables = await db.rawQuery(
        "SELECT name FROM sqlite_master WHERE type='table' "
        "AND name LIKE 'fertilizer_plan%'",
      );
      expect(tables, hasLength(2));
      await db.close();
    });

    test('save then fetch returns the plan with its items', () async {
      final db = await openFreshDb();
      final provider = FertilizerPlanProvider(testExecutor: db);

      final id = await provider.savePlan(samplePlan());
      expect(id, greaterThan(0));
      expect(provider.plans, hasLength(1));

      final saved = provider.plans.single;
      expect(saved.cropName, 'گندم');
      expect(saved.areaAcres, 3.5);
      expect(saved.items, hasLength(2));
      expect(saved.items.first.productId, 'dap');
      // Cost snapshot: DAP 350 kg = 7 bags x Rs 14,500.
      expect(saved.estimatedCostPaisa, 7 * 1450000);
      await db.close();
    });

    test('delete is a soft delete: hidden from list, audit written', () async {
      final db = await openFreshDb();
      final provider = FertilizerPlanProvider(testExecutor: db);
      final id = await provider.savePlan(samplePlan());

      await provider.deletePlan(id);
      expect(provider.plans, isEmpty);

      // Row still exists with deleted_at set (recycle-bin pattern).
      final rows = await db.query('fertilizer_plans', where: 'id = ?', whereArgs: [id]);
      expect(rows, hasLength(1));
      expect(rows.single['deleted_at'], isNotNull);

      // Second delete is a safe no-op.
      await provider.deletePlan(id);

      final audit = await db.query(
        'audit_log',
        where: 'table_name = ?',
        whereArgs: ['fertilizer_plans'],
      );
      expect(
        audit.map((a) => a['action']),
        containsAll(['create', 'soft_delete']),
      );
      await db.close();
    });

    test('deleting a plan does not touch other tables', () async {
      final db = await openFreshDb();
      await db.insert('farms', {
        'name': 'زمین',
        'total_area': 5.0,
        'created_at': '2026-01-01',
      });
      final provider = FertilizerPlanProvider(testExecutor: db);
      final id = await provider.savePlan(samplePlan());
      await provider.deletePlan(id);
      final farms = await db.query('farms');
      expect(farms, hasLength(1));
      await db.close();
    });
  });
}
