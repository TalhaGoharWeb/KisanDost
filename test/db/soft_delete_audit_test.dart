import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:kisan_dost/database/db_helper.dart';
import 'package:kisan_dost/models/party.dart';
import 'package:kisan_dost/providers/expense_provider.dart';
import 'package:kisan_dost/providers/harvest_provider.dart';
import 'package:kisan_dost/providers/party_provider.dart';
import 'package:kisan_dost/providers/task_provider.dart';
import 'package:kisan_dost/services/recycle_bin_service.dart';

/// Hermetic tests for Phase 11 (soft delete + audit log). They exercise the
/// REAL migration SQL ([DatabaseHelper.migrateV14ToV15]) and the REAL
/// providers against an in-memory FFI database (via each provider's test
/// executor) — the app singleton is never touched.
///
/// What "correct" means, from the farmer's point of view:
/// * deleting an expense/sale/harvest/task/party HIDES it everywhere
///   (lists, totals, recycle-bin-excluded queries) but keeps the row;
/// * the recycle bin lists it with a readable Urdu label, and restore
///   brings it back exactly;
/// * permanent delete is the only path that truly removes a row, and it is
///   offered only from the recycle bin;
/// * every create/update/delete/soft-delete/restore/permanent-delete writes
///   one row to the append-only audit_log;
/// * ledger tables (inventory_transactions, party_ledger_entries,
///   batai_settlements) are append-only and never appear in the bin.
void main() {
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  TestWidgetsFlutterBinding.ensureInitialized();
  SharedPreferences.setMockInitialValues({});
  // TaskProvider cancels/schedules notifications on delete/add; the plugin
  // has no real backend in tests, so every method call is a no-op.
  const notifChannel = MethodChannel('dexterx.dev/flutter_local_notifications');
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(notifChannel, (call) async => null);

  /// Builds the v14-shaped schema for the tables Phase 11 touches: the same
  /// columns as the real v14 (copied from DatabaseHelper._onCreate) MINUS
  /// `deleted_at`, and WITHOUT audit_log. FK constraints are omitted on
  /// purpose — the migration and the providers under test don't depend on
  /// them, and it keeps the fixture hermetic.
  Future<void> createV14Schema(Database db) async {
    await db.execute('''
      CREATE TABLE expenses (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        category TEXT NOT NULL,
        amount_paisa INTEGER NOT NULL,
        date TEXT NOT NULL,
        description TEXT,
        farm_id INTEGER,
        field_id INTEGER,
        crop_season_id INTEGER
      )
    ''');
    await db.execute('''
      CREATE TABLE harvests (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        crop_season_id INTEGER NOT NULL,
        quantity REAL NOT NULL,
        unit TEXT NOT NULL,
        date TEXT NOT NULL,
        rate_per_unit_paisa INTEGER DEFAULT 0,
        transportation_expense_paisa INTEGER DEFAULT 0,
        labour_expense_paisa INTEGER DEFAULT 0,
        harvesting_expense_paisa INTEGER DEFAULT 0,
        commission_expense_paisa INTEGER DEFAULT 0,
        other_expense_paisa INTEGER DEFAULT 0,
        buyer_name TEXT,
        payment_status TEXT DEFAULT 'Pending',
        notes TEXT,
        expense_id INTEGER
      )
    ''');
    await db.execute('''
      CREATE TABLE sales (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        harvest_id INTEGER NOT NULL,
        buyer_name TEXT,
        quantity REAL NOT NULL,
        price_per_unit_paisa INTEGER NOT NULL,
        total_amount_paisa INTEGER NOT NULL,
        date TEXT NOT NULL
      )
    ''');
    await db.execute('''
      CREATE TABLE tasks (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        title TEXT NOT NULL,
        description TEXT,
        snoozed_until TEXT,
        date_time TEXT NOT NULL,
        is_completed INTEGER NOT NULL DEFAULT 0,
        recurrence TEXT NOT NULL DEFAULT 'none',
        reminders TEXT NOT NULL DEFAULT '0'
      )
    ''');
    await db.execute('''
      CREATE TABLE parties (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        name TEXT NOT NULL,
        phone TEXT,
        notes TEXT,
        created_at TEXT NOT NULL
      )
    ''');
    await db.execute('''
      CREATE TABLE party_ledger_entries (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        party_id INTEGER NOT NULL,
        entry_type TEXT NOT NULL,
        amount_paisa INTEGER NOT NULL,
        date TEXT NOT NULL,
        note TEXT,
        created_at TEXT NOT NULL
      )
    ''');
    await db.execute('''
      CREATE TABLE crop_seasons (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        field_id INTEGER NOT NULL,
        crop_name TEXT NOT NULL,
        variety TEXT NOT NULL,
        status TEXT NOT NULL,
        start_date TEXT NOT NULL
      )
    ''');
    await db.execute('''
      CREATE TABLE farms (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        name TEXT NOT NULL,
        total_area REAL NOT NULL,
        created_at TEXT NOT NULL
      )
    ''');
    await db.execute('''
      CREATE TABLE fields (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        farm_id INTEGER NOT NULL,
        name TEXT NOT NULL,
        size_acres REAL NOT NULL,
        canal_water_available INTEGER NOT NULL DEFAULT 0,
        tube_well_available INTEGER NOT NULL DEFAULT 0,
        location TEXT
      )
    ''');
    // deleteParty blocks deletion when a batai agreement references the
    // party; the table always exists in production (v14+).
    await db.execute('''
      CREATE TABLE batai_agreements (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        farmer_role TEXT NOT NULL,
        other_party_id INTEGER NOT NULL,
        owner_share_percent INTEGER NOT NULL,
        cultivator_share_percent INTEGER NOT NULL,
        status TEXT NOT NULL DEFAULT 'active',
        start_date TEXT NOT NULL,
        created_at TEXT NOT NULL
      )
    ''');
  }

  Future<Database> openV14Db() async {
    // FFI in-memory databases are shared across openDatabase() calls in one
    // test run, and these tests CHANGE the schema (migration adds columns),
    // so every test starts from a pristine v14 schema: drop, then recreate.
    final db = await openDatabase(inMemoryDatabasePath);
    for (final t in [
      'audit_log',
      'expenses',
      'harvests',
      'sales',
      'tasks',
      'parties',
      'party_ledger_entries',
      'batai_agreements',
      'crop_seasons',
      'farms',
      'fields',
    ]) {
      await db.execute('DROP TABLE IF EXISTS $t');
    }
    await createV14Schema(db);
    return db;
  }

  Future<List<Map<String, dynamic>>> auditRows(
    Database db, {
    String? table,
    String? action,
  }) async {
    final where = [
      if (table != null) 'table_name = ?',
      if (action != null) 'action = ?',
    ].join(' AND ');
    final args = [if (table != null) table, if (action != null) action];
    return db.query(
      'audit_log',
      where: where.isEmpty ? null : where,
      whereArgs: args.isEmpty ? null : args,
      orderBy: 'id ASC',
    );
  }

  Future<bool> hasDeletedAt(Database db, String table) async {
    final cols = await db.rawQuery('PRAGMA table_info($table)');
    return cols.any((c) => c['name'] == 'deleted_at');
  }

  group('DB v15 migration', () {
    test(
      'adds deleted_at to the 5 tables and creates audit_log, idempotently',
      () async {
        final db = await openV14Db();
        expect(await hasDeletedAt(db, 'expenses'), isFalse);

        await DatabaseHelper.migrateV14ToV15(db);
        // Second run must be a no-op, not an error.
        await DatabaseHelper.migrateV14ToV15(db);

        for (final t in ['expenses', 'harvests', 'sales', 'tasks', 'parties']) {
          expect(await hasDeletedAt(db, t), isTrue, reason: t);
        }
        // Tables that must NOT gain soft delete.
        for (final t in ['party_ledger_entries', 'crop_seasons']) {
          expect(await hasDeletedAt(db, t), isFalse, reason: t);
        }

        final cols =
            (await db.rawQuery(
              'PRAGMA table_info(audit_log)',
            )).map((c) => c['name'] as String).toSet();
        expect(
          cols,
          containsAll([
            'id',
            'ts',
            'table_name',
            'row_id',
            'action',
            'details',
            'created_at',
          ]),
        );
      },
    );

    test('clearTables empties the Phase-11 tables too', () async {
      final db = await openV14Db();
      await DatabaseHelper.migrateV14ToV15(db);
      // Stubs for the remaining tables clearTables wipes (the fixture
      // already created the rest with real schemas).
      for (final t in [
        'batai_settlements',
        'ushr_records',
        'theka_installments',
        'thekas',
        'activities',
        'crop_season_fields',
        'inventory_transactions',
        'inventory',
      ]) {
        await db.execute('CREATE TABLE $t (id INTEGER PRIMARY KEY)');
        await db.insert(t, {'id': 1});
      }
      await db.insert('expenses', {
        'category': 'کھاد',
        'amount_paisa': 100,
        'date': '2026-10-01',
      });
      await db.insert('audit_log', {
        'ts': '2026-10-01T00:00:00',
        'table_name': 'expenses',
        'row_id': 1,
        'action': 'create',
        'created_at': '2026-10-01T00:00:00',
      });
      await db.insert('parties', {'name': 'x', 'created_at': '2026-10-01'});

      await DatabaseHelper.clearTables(db);

      for (final t in [
        'audit_log',
        'expenses',
        'parties',
        'batai_agreements',
        'party_ledger_entries',
        'farms',
        'tasks',
      ]) {
        final rows = await db.query(t);
        expect(rows, isEmpty, reason: t);
      }
    });
  });

  group('expense soft delete + audit', () {
    Future<ExpenseProvider> openProvider(Database db) async {
      await db.delete('audit_log');
      await db.delete('expenses');
      return ExpenseProvider(testExecutor: db);
    }

    test(
      'delete hides, restore revives, permanent removes; audit tracks all',
      () async {
        final db = await openV14Db();
        await DatabaseHelper.migrateV14ToV15(db);
        final p = await openProvider(db);

        final id = await p.addExpense(
          category: 'کھاد',
          amountPaisa: 500000,
          date: '2026-10-01',
        );
        final id2 = await p.addExpense(
          category: 'بیج',
          amountPaisa: 200000,
          date: '2026-10-01',
        );
        expect(p.expenses.map((e) => e.id), containsAll([id, id2]));
        expect(p.totalExpensesPaisa, 700000);
        var logs = await auditRows(db, table: 'expenses', action: 'create');
        expect(logs, hasLength(2));
        expect(logs.first['row_id'], id);

        // Soft delete: hidden from the list AND the total, row survives.
        await p.deleteExpense(id);
        expect(p.expenses.map((e) => e.id), isNot(contains(id)));
        expect(p.expenses.map((e) => e.id), contains(id2));
        expect(p.totalExpensesPaisa, 200000);
        final raw = await db.query(
          'expenses',
          where: 'id = ?',
          whereArgs: [id],
        );
        expect(raw, hasLength(1));
        expect(raw.first['deleted_at'], isNotNull);
        logs = await auditRows(db, table: 'expenses', action: 'soft_delete');
        expect(logs, hasLength(1));
        expect(logs.first['row_id'], id);

        // Recycle bin sees it with a readable label.
        final bin = await RecycleBinService.listDeleted(executor: db);
        expect(bin.map((i) => i.id), contains(id));
        final binItem = bin.firstWhere((i) => i.id == id);
        expect(binItem.table, 'expenses');
        expect(RecycleBinService.urduFor('expenses'), 'اخراجات');

        // Restore: back in the list and the total.
        await p.restoreExpense(id);
        expect(p.expenses.map((e) => e.id), contains(id));
        expect(p.totalExpensesPaisa, 700000);
        logs = await auditRows(db, table: 'expenses', action: 'restore');
        expect(logs, hasLength(1));
        expect((await RecycleBinService.listDeleted(executor: db)), isEmpty);

        // Permanent delete: the row is truly gone.
        await p.deleteExpense(id);
        await p.permanentDeleteExpense(id);
        expect(
          await db.query('expenses', where: 'id = ?', whereArgs: [id]),
          isEmpty,
        );
        logs = await auditRows(
          db,
          table: 'expenses',
          action: 'permanent_delete',
        );
        expect(logs, hasLength(1));
        // The audit log itself survives the permanent delete.
        expect(await auditRows(db, table: 'expenses'), hasLength(6));
      },
    );

    test('updateExpense writes an audit row', () async {
      final db = await openV14Db();
      await DatabaseHelper.migrateV14ToV15(db);
      final p = await openProvider(db);

      final id = await p.addExpense(
        category: 'کھاد',
        amountPaisa: 500000,
        date: '2026-10-01',
      );
      await p.updateExpense(
        id: id,
        category: 'کھاد',
        amountPaisa: 600000,
        date: '2026-10-01',
      );
      final logs = await auditRows(db, table: 'expenses', action: 'update');
      expect(logs, hasLength(1));
      expect(logs.first['row_id'], id);
    });
  });

  group('task soft delete + audit', () {
    test(
      'delete hides, restore revives, permanent removes; audit tracks all',
      () async {
        final db = await openV14Db();
        await DatabaseHelper.migrateV14ToV15(db);
        final p = TaskProvider(testExecutor: db);

        // A past date: the notification scheduler skips it (no recurrence),
        // so the test never touches real plugin scheduling.
        await p.addTask('پانی لگانا', null, DateTime(2020, 1, 1));
        await p.fetchTasks();
        expect(p.tasks, hasLength(1));
        final id = p.tasks.first.id;
        expect(
          await auditRows(db, table: 'tasks', action: 'create'),
          hasLength(1),
        );

        await p.deleteTask(id);
        await p.fetchTasks();
        expect(p.tasks, isEmpty);
        final raw = await db.query('tasks', where: 'id = ?', whereArgs: [id]);
        expect(raw.first['deleted_at'], isNotNull);
        expect(
          await auditRows(db, table: 'tasks', action: 'soft_delete'),
          hasLength(1),
        );

        final bin = await RecycleBinService.listDeleted(executor: db);
        expect(bin.map((i) => i.table), contains('tasks'));

        await p.restoreTask(id);
        await p.fetchTasks();
        expect(p.tasks.map((t) => t.id), contains(id));
        expect(
          await auditRows(db, table: 'tasks', action: 'restore'),
          hasLength(1),
        );

        await p.deleteTask(id);
        await p.permanentDeleteTask(id);
        expect(
          await db.query('tasks', where: 'id = ?', whereArgs: [id]),
          isEmpty,
        );
        expect(
          await auditRows(db, table: 'tasks', action: 'permanent_delete'),
          hasLength(1),
        );
      },
    );
  });

  group('harvest + sale soft delete + audit', () {
    Future<HarvestProvider> openProvider(Database db) async {
      await db.delete('audit_log');
      await db.delete('sales');
      await db.delete('harvests');
      await db.delete('crop_seasons');
      await db.delete('fields');
      await db.delete('farms');
      await db.insert('farms', {
        'name': 'میرا فارم',
        'total_area': 10.0,
        'created_at': '2026-09-01',
      });
      await db.insert('fields', {
        'farm_id': 1,
        'name': 'کھیت 1',
        'size_acres': 5.0,
      });
      await db.insert('crop_seasons', {
        'field_id': 1,
        'crop_name': 'گندم',
        'variety': 'فیصل آباد',
        'status': 'Active',
        'start_date': '2026-09-01',
      });
      return HarvestProvider(testExecutor: db);
    }

    test(
      'deleteHarvest soft-deletes its sales; subtree restores individually',
      () async {
        final db = await openV14Db();
        await DatabaseHelper.migrateV14ToV15(db);
        final p = await openProvider(db);

        await p.addHarvest(
          cropSeasonId: 1,
          quantity: 100,
          unit: 'من',
          date: '2026-10-01',
        );
        await p.fetchHarvests();
        expect(p.harvests, hasLength(1));
        final harvestId = p.harvests.first.harvest.id!;
        expect(
          await auditRows(db, table: 'harvests', action: 'create'),
          hasLength(1),
        );

        await p.recordSale(
          harvestId: harvestId,
          quantity: 40,
          pricePerUnitPaisa: 500000,
          date: '2026-10-02',
          buyerName: 'آڑھتی',
        );
        await p.fetchHarvests();
        expect(p.sales, hasLength(1));
        final saleId = p.sales.first.id!;
        expect(
          await auditRows(db, table: 'sales', action: 'create'),
          hasLength(1),
        );

        // Deleting the harvest soft-deletes the harvest AND its live sales.
        await p.deleteHarvest(harvestId);
        await p.fetchHarvests();
        expect(p.harvests, isEmpty);
        expect(p.sales, isEmpty);
        expect(
          (await db.query(
            'harvests',
            where: 'id = ?',
            whereArgs: [harvestId],
          )).first['deleted_at'],
          isNotNull,
        );
        expect(
          (await db.query(
            'sales',
            where: 'id = ?',
            whereArgs: [saleId],
          )).first['deleted_at'],
          isNotNull,
        );
        expect(
          await auditRows(db, table: 'harvests', action: 'soft_delete'),
          hasLength(1),
        );
        expect(
          await auditRows(db, table: 'sales', action: 'soft_delete'),
          hasLength(1),
        );

        // The bin lists both, grouped.
        final bin = await RecycleBinService.listDeleted(executor: db);
        expect(bin.map((i) => i.table).toSet(), {'harvests', 'sales'});

        // Restore is individual: restoring the harvest does NOT resurrect
        // the sale — the farmer restores exactly what he means to.
        await p.restoreHarvest(harvestId);
        await p.fetchHarvests();
        expect(p.harvests, hasLength(1));
        expect(p.sales, isEmpty);
        await p.restoreSale(saleId);
        await p.fetchHarvests();
        expect(p.sales, hasLength(1));

        // Permanent delete removes the harvest row itself.
        await p.deleteHarvest(harvestId);
        await p.permanentDeleteHarvest(harvestId);
        expect(
          await db.query('harvests', where: 'id = ?', whereArgs: [harvestId]),
          isEmpty,
        );
        expect(
          await auditRows(db, table: 'harvests', action: 'permanent_delete'),
          hasLength(1),
        );
      },
    );

    test('deleteSale soft-deletes only the sale', () async {
      final db = await openV14Db();
      await DatabaseHelper.migrateV14ToV15(db);
      final p = await openProvider(db);

      await p.addHarvest(
        cropSeasonId: 1,
        quantity: 100,
        unit: 'من',
        date: '2026-10-01',
      );
      await p.fetchHarvests();
      final harvestId = p.harvests.first.harvest.id!;
      await p.recordSale(
        harvestId: harvestId,
        quantity: 40,
        pricePerUnitPaisa: 500000,
        date: '2026-10-02',
      );
      await p.fetchHarvests();
      final saleId = p.sales.first.id!;

      await p.deleteSale(saleId);
      await p.fetchHarvests();
      // The harvest stays live; only the sale is hidden.
      expect(p.harvests, hasLength(1));
      expect(p.sales, isEmpty);
      expect(
        await auditRows(db, table: 'sales', action: 'soft_delete'),
        hasLength(1),
      );
    });
  });

  group('party soft delete + audit', () {
    test(
      'delete hides, restore revives, permanent removes; audit tracks all',
      () async {
        final db = await openV14Db();
        await DatabaseHelper.migrateV14ToV15(db);
        final p = PartyProvider(testExecutor: db);

        final id = await p.addParty(
          Party(name: 'دانش', createdAt: DateTime.now().toIso8601String()),
        );
        expect(p.parties.map((x) => x.id), contains(id));
        expect(
          await auditRows(db, table: 'parties', action: 'create'),
          hasLength(1),
        );

        await p.deleteParty(id);
        expect(p.parties.map((x) => x.id), isNot(contains(id)));
        final raw = await db.query('parties', where: 'id = ?', whereArgs: [id]);
        expect(raw.first['deleted_at'], isNotNull);
        expect(
          await auditRows(db, table: 'parties', action: 'soft_delete'),
          hasLength(1),
        );

        final bin = await RecycleBinService.listDeleted(executor: db);
        expect(bin.map((i) => i.table), contains('parties'));

        await p.restoreParty(id);
        expect(p.parties.map((x) => x.id), contains(id));

        await p.deleteParty(id);
        await p.permanentDeleteParty(id);
        expect(
          await db.query('parties', where: 'id = ?', whereArgs: [id]),
          isEmpty,
        );
        expect(
          await auditRows(db, table: 'parties', action: 'permanent_delete'),
          hasLength(1),
        );
      },
    );

    test(
      'deleteParty is blocked when batai agreements reference the party',
      () async {
        final db = await openV14Db();
        await DatabaseHelper.migrateV14ToV15(db);
        final p = PartyProvider(testExecutor: db);
        final id = await p.addParty(
          Party(name: 'زمیندار', createdAt: DateTime.now().toIso8601String()),
        );
        await db.insert('batai_agreements', {
          'farmer_role': 'landowner',
          'other_party_id': id,
          'owner_share_percent': 50,
          'cultivator_share_percent': 50,
          'start_date': '2026-10-01',
          'created_at': '2026-10-01',
        });

        expect(() => p.deleteParty(id), throwsA(isA<PartyException>()));
        expect(p.parties.map((x) => x.id), contains(id));
      },
    );

    test('addEntry refuses a soft-deleted party', () async {
      final db = await openV14Db();
      await DatabaseHelper.migrateV14ToV15(db);
      final p = PartyProvider(testExecutor: db);
      final id = await p.addParty(
        Party(name: 'عارضی', createdAt: DateTime.now().toIso8601String()),
      );
      await p.deleteParty(id);

      expect(
        () => p.addEntry(
          partyId: id,
          type: PartyEntryType.udhaarDiya,
          amountPaisa: 100000,
          date: '2026-10-01',
        ),
        throwsA(isA<PartyException>()),
      );
    });
  });
}
