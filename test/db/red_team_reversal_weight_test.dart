/// Red-team regression: reversal must use the ledger-exact deducted quantity,
/// not recompute from the activity snapshot with the item's CURRENT weight.
///
/// Attack: deduct 2 bags (50 kg/bag) as 100 kg, change the item weight to
/// 60 kg/bag, then delete the activity. The old code reversed 2 bags x 60 =
/// 120 kg — creating 20 kg from thin air. The fix reverses the exact 100 kg
/// recorded in the usage ledger row.
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:kisan_dost/database/db_helper.dart';
import 'package:kisan_dost/providers/activity_provider.dart';
import 'package:kisan_dost/providers/inventory_provider.dart';

void main() {
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  late Database db;
  late InventoryProvider inventory;
  late ActivityProvider activities;
  late int seasonId;

  setUp(() async {
    db = await openDatabase(
      inMemoryDatabasePath,
      onConfigure: (db) async {
        await db.execute('PRAGMA foreign_keys = ON');
      },
    );
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

  test('reversal restores exactly what was deducted, not recomputed',
      () async {
    // Item in kg, 50 kg per bag. Stock 500 kg.
    final itemId = await inventory.recordPurchase(
      category: 'کھاد',
      name: 'یوریا',
      unit: 'کلو',
      quantity: 500,
      costPerUnitPaisa: 10000,
      weightPerUnitKg: 50,
      executor: db,
    );

    // Use 2 bags -> deducts exactly 100 kg.
    await activities.addActivity(
      cropSeasonId: seasonId,
      activityType: 'کھاد',
      date: '2026-10-04',
      details: 'ٹیسٹ',
      inventoryCategory: 'کھاد',
      inventoryName: 'یوریا',
      inventoryUnit: 'بوری',
      inventoryQuantity: 2,
      inventoryItemId: itemId,
      inventoryProvider: inventory,
    );
    var item = await inventory.getItemById(itemId, executor: db);
    expect(item!.quantity, 500 - 100);

    // Farmer corrects the bag weight AFTER the deduction.
    await inventory.updateItemDetails(
      id: itemId,
      category: 'کھاد',
      name: 'یوریا',
      unit: 'کلو',
      costPerUnitPaisa: 10000,
      weightPerUnitKg: 60,
      executor: db,
    );

    // Delete the activity -> must restore exactly 100 kg (not 120).
    final acts = await db.query('activities');
    expect(acts, hasLength(1));
    await activities.deleteActivity(acts.first['id'] as int,
        inventoryProvider: inventory);

    item = await inventory.getItemById(itemId, executor: db);
    expect(item!.quantity, 500.0,
        reason: 'reversal must restore the deducted 100 kg, not 120 kg');

    // Ledger/cache consistency still holds.
    final rows = await db.rawQuery(
      'SELECT SUM(quantity) AS s FROM inventory_transactions WHERE inventory_id = ?',
      [itemId],
    );
    expect((rows.first['s'] as num).toDouble(), item.quantity);
  });
}
