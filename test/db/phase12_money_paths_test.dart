import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:kisan_dost/providers/expense_provider.dart';
import 'package:kisan_dost/providers/theka_provider.dart';
import 'package:kisan_dost/providers/ushr_provider.dart';
import 'package:kisan_dost/services/today_summary.dart';

/// Hermetic Phase 12 money-path tests. They exercise the REAL providers
/// against in-memory FFI databases via each provider's test executor — the
/// app singleton is never touched. FK constraints are omitted on purpose:
/// the code under test doesn't depend on them.
///
/// Covered here:
/// * theka installment pay → partial → full → overpay-throws, with the
///   single cumulative 'Land Rent' expense row tracking the paid total;
/// * the extracted [UshrProvider.computeUshrAmountPaisa] (unit + persisted);
/// * soft-deleted expenses are excluded from TODAY's month total;
/// * party delete+restore with ledger intact — DELIBERATELY NOT duplicated
///   here: party_ledger_test.dart already covers it
///   ('deleteParty is blocked when entries exist; party survives' checks
///   balanceOf + getEntries intact), and the brief's delete→restore
///   sequence is impossible by design — deleteParty throws PartyException
///   when any ledger entry exists.
void main() {
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  TestWidgetsFlutterBinding.ensureInitialized();
  SharedPreferences.setMockInitialValues({});

  /// Minimal theka schema: column lists copied from
  /// DatabaseHelper._onCreate, FK clauses omitted for hermeticity.
  Future<Database> openThekaDb() async {
    final db = await openDatabase(inMemoryDatabasePath);
    for (final t in ['theka_installments', 'thekas', 'expenses', 'audit_log']) {
      await db.execute('DROP TABLE IF EXISTS $t');
    }
    await db.execute('''
      CREATE TABLE thekas (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        farm_id INTEGER NOT NULL,
        field_id INTEGER,
        total_amount_paisa INTEGER NOT NULL,
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
        amount_paisa INTEGER NOT NULL,
        due_date TEXT NOT NULL,
        status TEXT NOT NULL,
        paid_amount_paisa INTEGER NOT NULL DEFAULT 0,
        paid_date TEXT,
        expense_id INTEGER
      )
    ''');
    await db.execute('''
      CREATE TABLE expenses (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        category TEXT NOT NULL,
        amount_paisa INTEGER NOT NULL,
        date TEXT NOT NULL,
        description TEXT,
        deleted_at TEXT
      )
    ''');
    await db.execute('''
      CREATE TABLE audit_log (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        ts TEXT NOT NULL,
        table_name TEXT NOT NULL,
        row_id INTEGER NOT NULL,
        action TEXT NOT NULL,
        details TEXT,
        created_at TEXT NOT NULL
      )
    ''');
    return db;
  }

  Future<int> seedThekaWithOneInstallment(Database db) async {
    final thekaId = await db.insert('thekas', {
      'farm_id': 1,
      'field_id': null,
      'total_amount_paisa': 100000,
      'duration_type': 'Seasonal',
      'duration_details': 'Rabi 2026',
      'payment_method': 'Installment',
      'start_date': '2026-01-01',
      'end_date': '2026-06-30',
      'created_at': '2026-01-01T00:00:00',
    });
    final instId = await db.insert('theka_installments', {
      'theka_id': thekaId,
      'amount_paisa': 100000,
      'due_date': '2026-02-01',
      'status': 'Pending',
      'paid_amount_paisa': 0,
      'paid_date': null,
      'expense_id': null,
    });
    return instId;
  }

  Future<Map<String, dynamic>> installmentRow(Database db, int id) async =>
      (await db.query(
        'theka_installments',
        where: 'id = ?',
        whereArgs: [id],
      )).first;

  group('theka pay / overpay', () {
    test(
      'partial then full payment accumulates into ONE cumulative expense',
      () async {
        final db = await openThekaDb();
        final instId = await seedThekaWithOneInstallment(db);
        final p = ThekaProvider(testExecutor: db);

        // Partial payment: 40,000 of 100,000 paisa.
        await p.payInstallment(
          installmentId: instId,
          paidAmountPaisa: 40000,
          paidDate: '2026-02-01',
          farmName: 'ٹیسٹ فارم',
          installmentIndex: 1,
        );
        var inst = await installmentRow(db, instId);
        expect(inst['status'], 'Partially Paid');
        expect(inst['paid_amount_paisa'], 40000);
        var expenses = await db.query('expenses');
        expect(expenses, hasLength(1));
        expect(expenses.first['amount_paisa'], 40000);

        // Completing payment: expense row is UPDATED to the cumulative total,
        // never duplicated.
        await p.payInstallment(
          installmentId: instId,
          paidAmountPaisa: 60000,
          paidDate: '2026-03-01',
          farmName: 'ٹیسٹ فارم',
          installmentIndex: 1,
        );
        inst = await installmentRow(db, instId);
        expect(inst['status'], 'Paid');
        expect(inst['paid_amount_paisa'], 100000);
        expenses = await db.query('expenses');
        expect(expenses, hasLength(1));
        expect(expenses.first['amount_paisa'], 100000);

        await db.close();
      },
    );

    test('overpayment throws an Urdu error and records nothing', () async {
      final db = await openThekaDb();
      final instId = await seedThekaWithOneInstallment(db);
      final p = ThekaProvider(testExecutor: db);

      await p.payInstallment(
        installmentId: instId,
        paidAmountPaisa: 100000,
        paidDate: '2026-02-01',
        farmName: 'ٹیسٹ فارم',
        installmentIndex: 1,
      );

      // One more paisa over the top must fail loudly, in Urdu.
      await expectLater(
        () => p.payInstallment(
          installmentId: instId,
          paidAmountPaisa: 1,
          paidDate: '2026-02-02',
          farmName: 'ٹیسٹ فارم',
          installmentIndex: 1,
        ),
        throwsA(predicate((e) => e.toString().contains('ادا شدہ رقم'))),
      );

      // The failed payment changed nothing: still exactly 100,000 paid and
      // one cumulative expense row.
      final inst = await installmentRow(db, instId);
      expect(inst['paid_amount_paisa'], 100000);
      expect(inst['status'], 'Paid');
      final expenses = await db.query('expenses');
      expect(expenses, hasLength(1));
      expect(expenses.first['amount_paisa'], 100000);

      await db.close();
    });
  });

  group('ushr computation', () {
    test('computeUshrAmountPaisa matches the screen formula exactly', () {
      // The extraction is verbatim: (marketValuePaisa * percentage / 100.0).round()
      expect(UshrProvider.computeUshrAmountPaisa(100000, 10.0), 10000);
      expect(UshrProvider.computeUshrAmountPaisa(100000, 5.0), 5000);
      expect(UshrProvider.computeUshrAmountPaisa(0, 10.0), 0);
    });

    test('rounding behavior is documented, not guessed', () {
      // 999 paisa @ 10% = 99.9 paisa → .round() (half away from zero) → 100.
      expect(UshrProvider.computeUshrAmountPaisa(999, 10.0), 100);
      // 995 paisa @ 10% = 99.5 paisa → half AWAY from zero → 100.
      expect(UshrProvider.computeUshrAmountPaisa(995, 10.0), 100);
      // 994 paisa @ 10% = 99.4 paisa → 99.
      expect(UshrProvider.computeUshrAmountPaisa(994, 10.0), 99);
    });

    test('addUshrRecord persists ushrAmountPaisa exactly', () async {
      final db = await openDatabase(inMemoryDatabasePath);
      for (final t in [
        'ushr_records',
        'expenses',
        'crop_seasons',
        'fields',
        'farms',
      ]) {
        await db.execute('DROP TABLE IF EXISTS $t');
      }
      // Minimal join parents for fetchUshrRecords()'s query (FKs omitted).
      await db.execute(
        'CREATE TABLE farms (id INTEGER PRIMARY KEY AUTOINCREMENT, name TEXT NOT NULL)',
      );
      await db.execute(
        'CREATE TABLE fields (id INTEGER PRIMARY KEY AUTOINCREMENT, name TEXT NOT NULL, size_acres REAL, farm_id INTEGER)',
      );
      await db.execute(
        'CREATE TABLE crop_seasons (id INTEGER PRIMARY KEY AUTOINCREMENT, crop_name TEXT NOT NULL, field_id INTEGER)',
      );
      await db.execute('''
        CREATE TABLE expenses (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          category TEXT NOT NULL,
          amount_paisa INTEGER NOT NULL,
          date TEXT NOT NULL,
          description TEXT,
          deleted_at TEXT
        )
      ''');
      // ushr_records columns copied from DatabaseHelper._onCreate, FKs omitted.
      await db.execute('''
        CREATE TABLE ushr_records (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          crop_season_id INTEGER NOT NULL,
          harvest_id INTEGER,
          harvest_qty REAL NOT NULL,
          market_value_paisa INTEGER NOT NULL,
          ushr_method TEXT NOT NULL,
          ushr_percentage REAL NOT NULL,
          ushr_amount_paisa INTEGER NOT NULL,
          status TEXT NOT NULL,
          date_paid TEXT,
          notes TEXT,
          expense_id INTEGER,
          pay_method TEXT DEFAULT 'Cash',
          qty_paid REAL DEFAULT 0.0,
          cash_paid_paisa INTEGER DEFAULT 0,
          rate_per_unit_paisa INTEGER DEFAULT 0
        )
      ''');
      final farmId = await db.insert('farms', {'name': 'ٹیسٹ فارم'});
      final fieldId = await db.insert('fields', {
        'name': 'کھیت 1',
        'size_acres': 5.0,
        'farm_id': farmId,
      });
      final seasonId = await db.insert('crop_seasons', {
        'crop_name': 'Wheat',
        'field_id': fieldId,
      });

      final p = UshrProvider(testExecutor: db);
      await p.addUshrRecord(
        cropSeasonId: seasonId,
        harvestQty: 100.0,
        marketValuePaisa: 100000,
        ushrMethod: 'Natural',
        ushrPercentage: 10.0,
        ushrAmountPaisa: UshrProvider.computeUshrAmountPaisa(100000, 10.0),
        status: 'Pending',
        payMethod: 'Cash',
        qtyPaid: 0.0,
        cashPaidPaisa: 0,
        ratePerUnitPaisa: 0,
      );

      // The exact integer the screen computed is what landed in the row.
      final rows = await db.rawQuery(
        'SELECT ushr_amount_paisa FROM ushr_records',
      );
      expect(rows, hasLength(1));
      expect(rows.first['ushr_amount_paisa'], 10000);
      // The provider's own reload sees it too (join over minimal parents).
      expect(p.ushrRecords, hasLength(1));
      expect(p.ushrRecords.first.ushrRecord.ushrAmountPaisa, 10000);

      await db.close();
    });
  });

  group('TODAY soft-delete exclusion', () {
    test('expensesInMonthPaisa counts only the live expense', () async {
      final db = await openDatabase(inMemoryDatabasePath);
      await db.execute('DROP TABLE IF EXISTS expenses');
      await db.execute('DROP TABLE IF EXISTS audit_log');
      // expenses columns copied from DatabaseHelper._onCreate (with
      // deleted_at), FKs omitted.
      await db.execute('''
        CREATE TABLE expenses (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          category TEXT NOT NULL,
          amount_paisa INTEGER NOT NULL,
          date TEXT NOT NULL,
          description TEXT,
          farm_id INTEGER,
          field_id INTEGER,
          crop_season_id INTEGER,
          deleted_at TEXT
        )
      ''');

      final p = ExpenseProvider(testExecutor: db);
      final now = DateTime.now();
      final today =
          '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';
      final liveId = await p.addExpense(
        category: 'Fertilizer',
        amountPaisa: 500000,
        date: today,
        description: 'زندہ خرچہ',
      );
      final deadId = await p.addExpense(
        category: 'Seeds',
        amountPaisa: 250000,
        date: today,
        description: 'حذف شدہ خرچہ',
      );
      await p.deleteExpense(deadId);
      await p.fetchExpenses();

      expect(p.expenses.map((e) => e.id), contains(liveId));
      expect(p.expenses.map((e) => e.id), isNot(contains(deadId)));
      expect(expensesInMonthPaisa(p.expenses, now), 500000);

      await db.close();
    });
  });
}
