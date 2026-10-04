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

/// Hermetic tests for "Delete All Data" ([DatabaseHelper.clearTables]).
///
/// What "correct" means, from the farmer's point of view:
/// * after the wipe, NO farmer data remains in ANY table — farms, fields,
///   crops, inventory, expenses, harvests, sales, tasks, parties, audit log;
/// * the wipe is transactional: it cannot leave half-deleted tables behind.
void main() {
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  TestWidgetsFlutterBinding.ensureInitialized();
  SharedPreferences.setMockInitialValues({});
  // TaskProvider schedules/cancels alarms on add/delete; the plugins have
  // no backend in tests, so every method call is a no-op.
  for (final name in [
    'com.talhagohar.kisandost/share',
    'dexterx.dev/flutter_local_notifications',
  ]) {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(MethodChannel(name), (call) async => null);
  }

  /// All user-data tables the wipe must empty (from DatabaseHelper.clearTables).
  const wipedTables = [
    'audit_log',
    'batai_settlements',
    'party_ledger_entries',
    'batai_agreements',
    'parties',
    'ushr_records',
    'theka_installments',
    'thekas',
    'activities',
    'sales',
    'harvests',
    'expenses',
    'crop_season_fields',
    'crop_seasons',
    'inventory_transactions',
    'inventory',
    'fields',
    'farms',
    'tasks',
  ];

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

  /// Seeds one row into the core farmer-data tables via the real providers.
  Future<void> seedFarmerData(Database db) async {
    final farms = FarmProvider(testExecutor: db);
    await farms.addFarm('My Farm', 10.0);
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
    final seasonId = crops.activeCropSeasons.first.cropSeason.id!;

    final inventory = InventoryProvider(testExecutor: db);
    await inventory.recordPurchase(
      category: 'Fertilizer',
      name: 'Urea',
      unit: 'Bag',
      quantity: 10,
      costPerUnitPaisa: 100000,
    );

    final expenses = ExpenseProvider(testExecutor: db);
    await expenses.addExpense(
      category: 'Seed',
      amountPaisa: 500000,
      date: '2026-11-02',
      description: 'Wheat seed',
      farmId: farmId,
      fieldId: fieldId,
      cropSeasonId: seasonId,
    );

    final harvests = HarvestProvider(testExecutor: db);
    await harvests.addHarvest(
      cropSeasonId: seasonId,
      quantity: 40.0,
      unit: 'Maund',
      date: '2026-04-15',
    );

    final parties = PartyProvider(testExecutor: db);
    await parties.addParty(Party(
      name: 'Arif Merchant',
      phone: '03001234567',
      createdAt: DateTime.now().toIso8601String(),
    ));

    final tasks = TaskProvider(testExecutor: db);
    await tasks.addTask(
      'Irrigate the wheat field',
      'Morning watering',
      DateTime.now().add(const Duration(days: 1)),
    );
  }

  Future<int> tableCount(Database db, String table) async {
    final rows =
        await db.rawQuery('SELECT COUNT(*) AS c FROM "$table"');
    return (rows.first['c'] as int?) ?? 0;
  }

  test('clearTables empties every farmer-data table', () async {
    final db = await openFreshDb();
    await seedFarmerData(db);

    // Sanity: the seed actually wrote rows.
    var nonEmpty = 0;
    for (final t in wipedTables) {
      if (await tableCount(db, t) > 0) nonEmpty++;
    }
    expect(nonEmpty, greaterThan(5),
        reason: 'seed should populate several tables');

    await DatabaseHelper.clearTables(db);

    for (final t in wipedTables) {
      expect(await tableCount(db, t), 0, reason: 'table $t not wiped');
    }
    await db.close();
  });

  test('clearTables on an already-empty database is a safe no-op', () async {
    final db = await openFreshDb();
    await DatabaseHelper.clearTables(db);
    for (final t in wipedTables) {
      expect(await tableCount(db, t), 0, reason: 'table $t not empty');
    }
    await db.close();
  });

  test('clearTables leaves the schema intact (app stays usable)', () async {
    final db = await openFreshDb();
    await seedFarmerData(db);
    await DatabaseHelper.clearTables(db);

    // The farmer can immediately start using the app again.
    final farms = FarmProvider(testExecutor: db);
    await farms.addFarm('Fresh Start Farm', 2.0);
    expect(farms.farms, hasLength(1));

    final integrity =
        await db.rawQuery('PRAGMA integrity_check');
    expect(integrity.first.values.first, 'ok');
    await db.close();
  });
}
