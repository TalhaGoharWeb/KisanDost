import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:kisan_dost/database/db_helper.dart';
import 'package:kisan_dost/providers/activity_provider.dart';
import 'package:kisan_dost/providers/inventory_provider.dart';

void main() {
  setUpAll(sqfliteFfiInit);

  setUp(() async {
    await DatabaseHelper.configureForTesting(factory: databaseFactoryFfi);
  });

  tearDown(() async {
    await DatabaseHelper.resetForTesting();
  });

  Future<int> seedCropSeason() async {
    final db = await DatabaseHelper.instance.database;
    final farmId = await db.insert('farms', {
      'name': 'Test Farm',
      'total_area': 1.0,
      'created_at': '2026-09-30',
    });
    final fieldId = await db.insert('fields', {
      'farm_id': farmId,
      'name': 'Field 1',
      'size_acres': 1.0,
      'canal_water_available': 0,
      'tube_well_available': 0,
    });
    final seasonId = await db.insert('crop_seasons', {
      'field_id': fieldId,
      'crop_name': 'Wheat',
      'variety': 'Test',
      'status': 'Active',
      'start_date': '2026-09-01',
    });
    await db.insert('crop_season_fields', {
      'crop_season_id': seasonId,
      'field_id': fieldId,
    });
    return seasonId;
  }

  Future<void> seedFertilizer(
    InventoryProvider provider, {
    required double quantity,
  }) async {
    await provider.addInventoryItem(
      category: 'Fertilizer',
      name: 'Urea',
      unit: 'کلوگرام',
      quantity: quantity,
      costPerUnit: 100,
    );
  }

  test(
    'activity, expense, and stock deduction save atomically; delete restores stock',
    () async {
      final cropSeasonId = await seedCropSeason();
      final inventoryProvider = InventoryProvider();
      await seedFertilizer(inventoryProvider, quantity: 10);
      final activityProvider = ActivityProvider();

      await activityProvider.addActivity(
        cropSeasonId: cropSeasonId,
        activityType: 'کھاد ڈالی',
        date: '2026-09-30T08:00:00.000',
        details: 'Field application',
        expenseAmount: 200,
        expenseCategory: 'Fertilizer',
        inventoryCategory: 'Fertilizer',
        inventoryName: 'Urea',
        inventoryUnit: 'کلوگرام',
        inventoryQuantity: 2,
        inventoryProvider: inventoryProvider,
      );

      final db = await DatabaseHelper.instance.database;
      expect((await db.query('activities')).length, 1);
      expect((await db.query('expenses')).length, 1);
      expect((await db.query('inventory')).single['quantity'], 8.0);

      final activityId = (await db.query('activities')).single['id'] as int;
      final usageMovements = await db.query(
        'inventory_transactions',
        orderBy: 'id',
      );
      expect(usageMovements.map((row) => row['movement_type']).toList(), [
        'purchase',
        'usage',
      ]);
      expect(usageMovements.last['quantity_delta'], -2.0);
      expect(usageMovements.last['activity_id'], activityId);
      await activityProvider.deleteActivity(
        activityId,
        inventoryProvider: inventoryProvider,
      );

      expect(await db.query('activities'), isEmpty);
      expect(await db.query('expenses'), isEmpty);
      expect((await db.query('inventory')).single['quantity'], 10.0);
      final movementsAfterDelete = await db.query(
        'inventory_transactions',
        orderBy: 'id',
      );
      expect(movementsAfterDelete, hasLength(3));
      expect(movementsAfterDelete.last['movement_type'], 'reversal');
      expect(movementsAfterDelete.last['quantity_delta'], 2.0);
      expect(movementsAfterDelete.last['activity_id'], activityId);
      expect(
        movementsAfterDelete.fold<double>(
          0,
          (sum, row) => sum + (row['quantity_delta'] as num).toDouble(),
        ),
        10.0,
      );
    },
  );

  test(
    'insufficient stock rolls back the linked expense and activity',
    () async {
      final cropSeasonId = await seedCropSeason();
      final inventoryProvider = InventoryProvider();
      await seedFertilizer(inventoryProvider, quantity: 1);
      final activityProvider = ActivityProvider();

      await expectLater(
        activityProvider.addActivity(
          cropSeasonId: cropSeasonId,
          activityType: 'کھاد ڈالی',
          date: '2026-09-30T08:00:00.000',
          details: 'Too much fertilizer',
          expenseAmount: 500,
          expenseCategory: 'Fertilizer',
          inventoryCategory: 'Fertilizer',
          inventoryName: 'Urea',
          inventoryUnit: 'کلوگرام',
          inventoryQuantity: 5,
          inventoryProvider: inventoryProvider,
        ),
        throwsA(isA<StateError>()),
      );

      final db = await DatabaseHelper.instance.database;
      expect(await db.query('activities'), isEmpty);
      expect(await db.query('expenses'), isEmpty);
      expect((await db.query('inventory')).single['quantity'], 1.0);
      expect(
        (await db.query(
          'inventory_transactions',
        )).map((row) => row['movement_type']),
        ['purchase'],
      );
    },
  );

  test(
    'failed activity edit rolls back stock restoration and expense edits',
    () async {
      final cropSeasonId = await seedCropSeason();
      final inventoryProvider = InventoryProvider();
      await seedFertilizer(inventoryProvider, quantity: 1);
      final activityProvider = ActivityProvider();
      await activityProvider.addActivity(
        cropSeasonId: cropSeasonId,
        activityType: 'کھاد ڈالی',
        date: '2026-09-30T08:00:00.000',
        details: 'Original entry',
        expenseAmount: 30,
        expenseCategory: 'Fertilizer',
        inventoryCategory: 'Fertilizer',
        inventoryName: 'Urea',
        inventoryUnit: 'کلوگرام',
        inventoryQuantity: 1,
        inventoryProvider: inventoryProvider,
      );
      final db = await DatabaseHelper.instance.database;
      final activityId = (await db.query('activities')).single['id'] as int;

      await expectLater(
        activityProvider.updateActivity(
          id: activityId,
          cropSeasonId: cropSeasonId,
          activityType: 'کھاد ڈالی',
          date: '2026-09-30T08:00:00.000',
          details: 'Invalid replacement',
          expenseAmount: 999,
          expenseCategory: 'Fertilizer',
          inventoryCategory: 'Fertilizer',
          inventoryName: 'Urea',
          inventoryUnit: 'کلوگرام',
          inventoryQuantity: 2,
          inventoryProvider: inventoryProvider,
        ),
        throwsA(isA<StateError>()),
      );

      expect(
        (await db.query('activities')).single['details'],
        'Original entry',
      );
      expect((await db.query('activities')).single['inventory_quantity'], 1.0);
      expect((await db.query('expenses')).single['amount'], 30.0);
      expect((await db.query('inventory')).single['quantity'], 0.0);
      final movements = await db.query('inventory_transactions');
      expect(movements, hasLength(2));
      expect(movements.map((row) => row['movement_type']).toSet(), {
        'purchase',
        'usage',
      });
    },
  );

  test(
    'direct purchase-and-use does not leave phantom warehouse stock',
    () async {
      final cropSeasonId = await seedCropSeason();
      final inventoryProvider = InventoryProvider();
      final activityProvider = ActivityProvider();

      await activityProvider.addActivity(
        cropSeasonId: cropSeasonId,
        activityType: 'کھاد ڈالی',
        date: '2026-09-30T08:00:00.000',
        details: 'Bought and used same day',
        expenseAmount: 300,
        expenseCategory: 'Fertilizer',
        inventoryCategory: 'Fertilizer',
        inventoryName: 'DAP',
        inventoryUnit: 'بوری',
        inventoryQuantity: 1,
        inventoryPurchasedAndUsed: true,
        inventoryProvider: inventoryProvider,
      );

      final db = await DatabaseHelper.instance.database;
      expect(await db.query('inventory'), isEmpty);
      expect(
        (await db.query('activities')).single['inventory_purchased_and_used'],
        1,
      );
      expect((await db.query('expenses')).single['amount'], 300.0);
      expect(await db.query('inventory_transactions'), isEmpty);
    },
  );

  test(
    'stock adjustments and deletion stay auditable and clear with data',
    () async {
      final provider = InventoryProvider();
      await seedFertilizer(provider, quantity: 10);
      final db = await DatabaseHelper.instance.database;
      final item = provider.inventoryList.single;

      await provider.updateInventoryItem(
        id: item.id!,
        category: item.category,
        name: item.name,
        unit: item.unit,
        quantity: 7,
        costPerUnit: item.costPerUnit,
      );
      await provider.deleteInventoryItem(item.id!);

      expect(await db.query('inventory'), isEmpty);
      final movements = await db.query('inventory_transactions', orderBy: 'id');
      expect(movements.map((row) => row['movement_type']).toList(), [
        'purchase',
        'adjustment',
        'adjustment',
      ]);
      expect(
        movements.fold<double>(
          0,
          (sum, row) => sum + (row['quantity_delta'] as num).toDouble(),
        ),
        0.0,
      );
      expect(
        await provider.fetchInventoryTransactions(inventoryId: item.id),
        hasLength(3),
      );

      await DatabaseHelper.instance.clearAllTables();
      expect(await db.query('inventory_transactions'), isEmpty);
    },
  );
}
