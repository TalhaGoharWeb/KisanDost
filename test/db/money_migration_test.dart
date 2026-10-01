import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:kisan_dost/database/db_helper.dart';

/// Hermetic tests for the v11 -> v12 money migration. They exercise the REAL
/// migration SQL ([DatabaseHelper.migrateV11ToV12]) against an in-memory FFI
/// database.
///
/// What "correct" means:
/// * every money table is REBUILT with INTEGER `<name>_paisa` columns,
///   backfilled as `CAST(ROUND(<name> * 100) AS INTEGER)` — exact, with the
///   single documented rounding rule (half away from zero);
/// * the old REAL money columns are GONE afterwards (a rebuild, not a
///   deprecation: keeping `NOT NULL` REAL columns would break every future
///   insert), so upgraded devices end up with the fresh-install schema;
/// * redundant COMPUTED columns (harvest gross/total/net, ushr remaining)
///   are DROPPED — they are derived in Dart now, so they can never drift
///   from their inputs.
void main() {
  sqfliteFfiInit();
  // Route package:sqflite through the FFI backend for these tests.
  databaseFactory = databaseFactoryFfi;

  /// Full v11-shaped schema (all columns, FKs omitted — the migration only
  /// renames/creates/copies). Every table the v12 migration rebuilds must
  /// exist with its complete v11 column set, because the rebuild copies all
  /// non-money columns verbatim.
  Future<void> createV11MoneySchema(Database db) async {
    await db.execute('''
      CREATE TABLE expenses (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        category TEXT NOT NULL,
        amount REAL NOT NULL,
        date TEXT NOT NULL,
        description TEXT,
        farm_id INTEGER,
        field_id INTEGER,
        crop_season_id INTEGER
      )
    ''');
    await db.execute('''
      CREATE TABLE inventory (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        category TEXT NOT NULL,
        name TEXT NOT NULL,
        unit TEXT NOT NULL,
        quantity REAL NOT NULL,
        cost_per_unit REAL NOT NULL,
        weight_per_unit_kg REAL
      )
    ''');
    await db.execute('''
      CREATE TABLE inventory_transactions (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        inventory_id INTEGER NOT NULL,
        type TEXT NOT NULL,
        quantity REAL NOT NULL,
        unit TEXT NOT NULL,
        unit_price REAL,
        total_amount REAL,
        activity_id INTEGER,
        date TEXT NOT NULL,
        notes TEXT,
        created_at TEXT NOT NULL
      )
    ''');
    await db.execute('''
      CREATE TABLE harvests (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        crop_season_id INTEGER NOT NULL,
        quantity REAL NOT NULL,
        unit TEXT NOT NULL,
        date TEXT NOT NULL,
        rate_per_unit REAL DEFAULT 0.0,
        gross_amount REAL DEFAULT 0.0,
        transportation_expense REAL DEFAULT 0.0,
        labour_expense REAL DEFAULT 0.0,
        harvesting_expense REAL DEFAULT 0.0,
        commission_expense REAL DEFAULT 0.0,
        other_expense REAL DEFAULT 0.0,
        total_expense REAL DEFAULT 0.0,
        net_income REAL DEFAULT 0.0,
        buyer_name TEXT,
        payment_status TEXT DEFAULT 'Pending',
        notes TEXT,
        expense_id INTEGER
      )
    ''');
    await db.execute('''
      CREATE TABLE ushr_records (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        crop_season_id INTEGER NOT NULL,
        harvest_id INTEGER,
        harvest_qty REAL NOT NULL,
        market_value REAL NOT NULL,
        ushr_method TEXT NOT NULL,
        ushr_percentage REAL NOT NULL,
        ushr_amount REAL NOT NULL,
        status TEXT NOT NULL,
        date_paid TEXT,
        notes TEXT,
        expense_id INTEGER,
        pay_method TEXT DEFAULT 'Cash',
        qty_paid REAL DEFAULT 0.0,
        cash_paid REAL DEFAULT 0.0,
        remaining_balance REAL DEFAULT 0.0,
        rate_per_unit REAL DEFAULT 0.0
      )
    ''');
    await db.execute('''
      CREATE TABLE sales (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        harvest_id INTEGER NOT NULL,
        buyer_name TEXT,
        quantity REAL NOT NULL,
        price_per_unit REAL NOT NULL,
        total_amount REAL NOT NULL,
        date TEXT NOT NULL
      )
    ''');
    await db.execute('''
      CREATE TABLE thekas (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        farm_id INTEGER NOT NULL,
        field_id INTEGER,
        total_amount REAL NOT NULL,
        duration_type TEXT NOT NULL,
        duration_details TEXT,
        payment_method TEXT NOT NULL,
        start_date TEXT,
        end_date TEXT,
        created_at TEXT NOT NULL
      )
    ''');
    await db.execute('''
      CREATE TABLE theka_installments (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        theka_id INTEGER NOT NULL,
        amount REAL NOT NULL,
        due_date TEXT NOT NULL,
        status TEXT NOT NULL,
        paid_amount REAL NOT NULL DEFAULT 0.0,
        paid_date TEXT,
        expense_id INTEGER
      )
    ''');
  }

  Future<Database> openDb() => openDatabase(
        inMemoryDatabasePath,
        onConfigure: (db) async {
          // Same as DatabaseHelper._initDatabase.
          await db.execute('PRAGMA foreign_keys = ON');
        },
      );

  test('backfills every money column to integer paisa', () async {
    final db = await openDb();
    await createV11MoneySchema(db);

    await db.insert('expenses',
        {'category': 'Labour', 'amount': 1250.75, 'date': '2026-01-05'});
    await db.insert('inventory', {
      'category': 'Fertilizer',
      'name': 'یوریا',
      'unit': 'بوری',
      'quantity': 10.0,
      'cost_per_unit': 2000.0
    });
    await db.insert('inventory_transactions', {
      'inventory_id': 1,
      'type': 'purchase',
      'quantity': 10.0,
      'unit': 'بوری',
      'unit_price': 2000.0,
      'total_amount': 20000.0,
      'date': '2026-01-05',
      'created_at': '2026-01-05T00:00:00'
    });
    await db.insert('harvests', {
      'crop_season_id': 1,
      'quantity': 40.0,
      'unit': 'من',
      'date': '2026-01-05',
      'rate_per_unit': 1500.5,
      'transportation_expense': 500.0,
      'labour_expense': 0.0,
      'harvesting_expense': 0.0,
      'commission_expense': 0.0,
      'other_expense': 0.0,
      // Deprecated computed columns: must NOT get a paisa twin.
      'gross_amount': 999.99,
      'total_expense': 1.0,
      'net_income': 2.0,
    });
    await db.insert('ushr_records', {
      'crop_season_id': 1,
      'harvest_qty': 40.0,
      'market_value': 100000.0,
      'ushr_method': 'Natural',
      'ushr_percentage': 10.0,
      'ushr_amount': 10000.0,
      'status': 'Pending',
      'cash_paid': 2500.25,
      // Deprecated computed: no paisa twin.
      'remaining_balance': 7500.0,
      'rate_per_unit': 3000.0,
    });
    await db.insert('sales', {
      'harvest_id': 1,
      'quantity': 10.0,
      'price_per_unit': 1500.5,
      'total_amount': 15005.0,
      'date': '2026-01-05'
    });
    await db.insert('thekas', {
      'farm_id': 1,
      'total_amount': 500000.0,
      'duration_type': 'Yearly',
      'payment_method': 'Full',
      'created_at': '2026-01-05T00:00:00'
    });
    await db.insert('theka_installments', {
      'theka_id': 1,
      'amount': 125000.0,
      'paid_amount': 62500.5,
      'due_date': '2026-06-05',
      'status': 'Pending'
    });

    await DatabaseHelper.migrateV11ToV12(db);

    expect((await db.query('expenses')).single['amount_paisa'], 125075);
    final expCols = (await db.rawQuery("PRAGMA table_info('expenses')"))
        .map((c) => c['name'] as String)
        .toSet();
    // No deprecated REAL money column survives the rebuild.
    expect(expCols, isNot(contains('amount')));
    expect(expCols, contains('amount_paisa'));
    expect(
        (await db.query('inventory')).single['cost_per_unit_paisa'], 200000);
    final tx = (await db.query('inventory_transactions')).single;
    expect(tx['unit_price_paisa'], 200000);
    expect(tx['total_amount_paisa'], 2000000);

    final h = (await db.query('harvests')).single;
    expect(h['rate_per_unit_paisa'], 150050);
    expect(h['transportation_expense_paisa'], 50000);
    expect(h['labour_expense_paisa'], 0);
    final hCols = (await db.rawQuery("PRAGMA table_info('harvests')"))
        .map((c) => c['name'] as String)
        .toSet();
    expect(hCols, isNot(contains('gross_amount_paisa')));
    expect(hCols, isNot(contains('total_expense_paisa')));
    expect(hCols, isNot(contains('net_income_paisa')));
    // The old REAL money columns are gone entirely (rebuilt, not deprecated).
    expect(hCols, isNot(contains('rate_per_unit')));
    expect(hCols, isNot(contains('gross_amount')));
    expect(hCols, isNot(contains('total_expense')));
    expect(hCols, isNot(contains('net_income')));

    final u = (await db.query('ushr_records')).single;
    expect(u['market_value_paisa'], 10000000);
    expect(u['ushr_amount_paisa'], 1000000);
    expect(u['cash_paid_paisa'], 250025);
    expect(u['rate_per_unit_paisa'], 300000);
    final uCols = (await db.rawQuery("PRAGMA table_info('ushr_records')"))
        .map((c) => c['name'] as String)
        .toSet();
    expect(uCols, isNot(contains('remaining_balance_paisa')));
    expect(uCols, isNot(contains('market_value')));
    expect(uCols, isNot(contains('remaining_balance')));

    final s = (await db.query('sales')).single;
    expect(s['price_per_unit_paisa'], 150050);
    expect(s['total_amount_paisa'], 1500500);

    expect((await db.query('thekas')).single['total_amount_paisa'], 50000000);

    final inst = (await db.query('theka_installments')).single;
    expect(inst['amount_paisa'], 12500000);
    expect(inst['paid_amount_paisa'], 6250050);

    await db.close();
  });

  test('rounding is half away from zero; NULLs stay NULL', () async {
    final db = await openDb();
    await createV11MoneySchema(db);

    await db.insert('expenses',
        {'category': 'Labour', 'amount': 10.999, 'date': '2026-01-05'}); // -> 1100
    await db.insert('expenses',
        {'category': 'Labour', 'amount': 0.005, 'date': '2026-01-05'}); // -> 1
    await db.insert('expenses',
        {'category': 'Labour', 'amount': 0.004, 'date': '2026-01-05'}); // -> 0
    await db.insert('inventory_transactions', {
      'inventory_id': 1,
      'type': 'purchase',
      'quantity': 1.0,
      'unit': 'بوری',
      'unit_price': null,
      'total_amount': null,
      'date': '2026-01-05',
      'created_at': '2026-01-05T00:00:00'
    });

    await DatabaseHelper.migrateV11ToV12(db);

    final amounts = await db.query('expenses', orderBy: 'id ASC');
    expect(
        amounts.map((r) => r['amount_paisa']).toList(), [1100, 1, 0]);
    final tx = (await db.query('inventory_transactions')).single;
    expect(tx['unit_price_paisa'], isNull);
    expect(tx['total_amount_paisa'], isNull);

    await db.close();
  });

  test('migration is idempotent and tolerates missing tables', () async {
    final db = await openDb();
    await createV11MoneySchema(db);
    await db.insert('expenses',
        {'category': 'Labour', 'amount': 100.0, 'date': '2026-01-05'});

    await DatabaseHelper.migrateV11ToV12(db);
    // A second run detects the paisa columns and skips the rebuild —
    // the migration is idempotent.
    await DatabaseHelper.migrateV11ToV12(db);
    expect((await db.query('expenses')).single['amount_paisa'], 10000);
    await db.close();

    // A database with none of the money tables (minimal schemas, as used by
    // other test files) migrates cleanly instead of throwing. (The previous
    // db is closed first: sqflite singleInstances :memory: by path.)
    final bare = await openDb();
    await bare.execute(
        'CREATE TABLE tasks (id INTEGER PRIMARY KEY AUTOINCREMENT, title TEXT NOT NULL)');
    await DatabaseHelper.migrateV11ToV12(bare);
    final bareTables = (await bare
            .rawQuery("SELECT name FROM sqlite_master WHERE type = 'table'"))
        .map((r) => r['name'] as String)
        .toSet();
    expect(bareTables, contains('tasks'));
    expect(bareTables, isNot(contains('expenses')));
    await bare.close();
  });
}
