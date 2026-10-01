import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:kisan_dost/database/db_helper.dart';
import 'package:kisan_dost/models/batai.dart';
import 'package:kisan_dost/providers/batai_provider.dart';
import 'package:kisan_dost/providers/crop_provider.dart';
import 'package:kisan_dost/providers/expense_provider.dart';
import 'package:kisan_dost/providers/farm_provider.dart';
import 'package:kisan_dost/providers/harvest_provider.dart';
import 'package:kisan_dost/providers/inventory_provider.dart';
import 'package:kisan_dost/providers/party_provider.dart';
import 'package:kisan_dost/providers/task_provider.dart';
import 'package:kisan_dost/providers/theka_provider.dart';
import 'package:kisan_dost/services/demo_data_service.dart';

/// Phase 14: [DemoDataService] against the REAL production schema
/// ([DatabaseHelper.createFreshSchemaForTests]) in an in-memory FFI database.
/// A farmer row is present before demo entry, so the suite proves exit-demo
/// removes exactly the demo rows and zero user rows — plus the guarded
/// skip-and-report path when the farmer linked their own record to a demo
/// row (batai agreement → demo party, FK RESTRICT).
void main() {
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  TestWidgetsFlutterBinding.ensureInitialized();
  SharedPreferences.setMockInitialValues({});
  // TaskProvider schedules/cancels notifications; the plugin has no real
  // backend in tests, so every method call is a no-op.
  const notifChannel = MethodChannel('dexterx.dev/flutter_local_notifications');
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(notifChannel, (call) async => null);

  late Database db;
  late FarmProvider farms;
  late CropProvider crops;
  late ExpenseProvider expenses;
  late HarvestProvider harvests;
  late TaskProvider tasks;
  late PartyProvider parties;
  late InventoryProvider inventory;
  late ThekaProvider thekas;
  late BataiProvider batai;
  late DemoDataService demo;

  Future<int> count(String table) async {
    final rows = await db.rawQuery('SELECT COUNT(*) AS c FROM $table');
    return (rows.first['c'] as int?) ?? 0;
  }

  Future<Map<String, List<int>>> trackedIds() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(DemoDataService.idsKey)!;
    return (jsonDecode(raw) as Map<String, dynamic>).map(
      (k, v) => MapEntry(k, (v as List).map((e) => e as int).toList()),
    );
  }

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    db = await databaseFactoryFfi.openDatabase(inMemoryDatabasePath);
    await db.execute('PRAGMA foreign_keys = ON');
    await DatabaseHelper.instance.createFreshSchemaForTests(db);

    farms = FarmProvider(testExecutor: db);
    crops = CropProvider(testExecutor: db);
    expenses = ExpenseProvider(testExecutor: db);
    harvests = HarvestProvider(testExecutor: db);
    tasks = TaskProvider(testExecutor: db);
    parties = PartyProvider(testExecutor: db);
    inventory = InventoryProvider(testExecutor: db);
    thekas = ThekaProvider(testExecutor: db);
    batai = BataiProvider(testExecutor: db);
    demo = DemoDataService(testExecutor: db);
    await demo.load();
  });

  tearDown(() async {
    await db.close();
  });

  Future<void> enterDemo() => demo.enterDemo(
    farms: farms,
    crops: crops,
    expenses: expenses,
    harvests: harvests,
    tasks: tasks,
    parties: parties,
    inventory: inventory,
    thekas: thekas,
    batai: batai,
  );

  test(
    'enter inserts a coherent dataset; exit removes exactly the demo rows',
    () async {
      // The farmer's own rows, present BEFORE demo entry.
      await farms.addFarm('میرا فارم', 5);
      await expenses.addExpense(
        category: 'Labour',
        amountPaisa: 100000,
        date: '2026-09-01',
        description: 'میرا خرچہ',
      );
      expect(await demo.hasRealData(), isTrue);

      await enterDemo();

      // Row counts across every demo table.
      expect(await count('farms'), 2);
      expect(await count('fields'), 2);
      expect(await count('crop_seasons'), 2);
      expect(await count('expenses'), 9); // 8 demo + 1 farmer
      expect(await count('harvests'), 2);
      expect(await count('sales'), 1);
      expect(await count('tasks'), 3);
      expect(await count('inventory'), 4);
      expect(await count('inventory_transactions'), 4);
      expect(await count('parties'), 1);
      expect(await count('party_ledger_entries'), 2);
      expect(await count('thekas'), 1);
      expect(await count('theka_installments'), 2);
      expect(await count('batai_agreements'), 1);

      // Tracking + active flag persisted.
      expect(demo.isActive, isTrue);
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getBool(DemoDataService.activeKey), isTrue);
      final ids = await trackedIds();
      expect(ids['farms'], hasLength(1));
      expect(ids['fields'], hasLength(2));
      expect(ids['expenses'], hasLength(8));
      expect(ids['parties'], hasLength(1));

      // The demo is coherent: sale belongs to the wheat harvest, entries to
      // the demo party, the batai agreement names the demo party.
      final saleRows = await db.query('sales');
      final harvestRows = await db.query('harvests');
      expect(
        saleRows.single['harvest_id'],
        harvestRows.firstWhere((h) => h['id'] == ids['harvests']!.first)['id'],
      );

      final result = await demo.exitDemo();
      expect(result.ok, isTrue);

      // Exactly the farmer's rows survive.
      expect(await count('farms'), 1);
      expect(await count('fields'), 0);
      expect(await count('crop_seasons'), 0);
      expect(await count('expenses'), 1);
      expect(await count('harvests'), 0);
      expect(await count('sales'), 0);
      expect(await count('tasks'), 0);
      expect(await count('inventory'), 0);
      expect(await count('inventory_transactions'), 0);
      expect(await count('parties'), 0);
      expect(await count('party_ledger_entries'), 0);
      expect(await count('thekas'), 0);
      expect(await count('theka_installments'), 0);
      expect(await count('batai_agreements'), 0);
      final farmNames = await db.query('farms', columns: ['name']);
      expect(farmNames.single['name'], 'میرا فارم');
      final expenseDescs = await db.query('expenses', columns: ['description']);
      expect(expenseDescs.single['description'], 'میرا خرچہ');

      expect(demo.isActive, isFalse);
      expect(prefs.getBool(DemoDataService.activeKey), isFalse);
      expect(prefs.getString(DemoDataService.idsKey), isNull);
    },
  );

  test(
    'exit is blocked (not crashed) when a farmer row references a demo row',
    () async {
      await enterDemo();
      final ids = await trackedIds();
      final demoPartyId = ids['parties']!.single;

      // The farmer creates their own batai agreement naming the DEMO party:
      // parties is FK RESTRICT, so deleting the demo party must not crash.
      await batai.createAgreement(
        farmerRole: FarmerRole.cultivator,
        otherPartyId: demoPartyId,
        ownerSharePercent: 50,
        cultivatorSharePercent: 50,
        startDate: '2026-01-01',
        notes: 'میرا معاہدہ',
      );
      final userAgreementId = (await db.query(
            'batai_agreements',
            columns: ['id'],
          ))
          .map((r) => r['id'] as int)
          .firstWhere((id) => !ids['batai_agreements']!.contains(id));

      final blocked = await demo.exitDemo();
      expect(blocked.ok, isFalse);
      expect(blocked.message, contains('پارٹیاں'));

      // Demo mode stays active; the demo party and the farmer's agreement
      // both survive.
      expect(demo.isActive, isTrue);
      expect(await count('parties'), 1);
      expect(await count('batai_agreements'), 1);

      // After the farmer removes their own agreement, exit completes.
      await batai.deleteAgreement(userAgreementId);
      final result = await demo.exitDemo();
      expect(result.ok, isTrue);
      expect(await count('parties'), 0);
      expect(await count('batai_agreements'), 0);
      expect(demo.isActive, isFalse);
    },
  );

  test('enter is idempotent while demo is already active', () async {
    await enterDemo();
    await enterDemo(); // second call is a no-op
    expect(await count('farms'), 1);
    expect(await count('expenses'), 8);
  });
}
