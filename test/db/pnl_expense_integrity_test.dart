import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:kisan_dost/database/db_helper.dart';
import 'package:kisan_dost/models/models.dart';
import 'package:kisan_dost/providers/activity_provider.dart';
import 'package:kisan_dost/providers/crop_provider.dart';
import 'package:kisan_dost/providers/theka_provider.dart';
import 'package:kisan_dost/providers/ushr_provider.dart';
import 'package:kisan_dost/services/pnl_summary.dart';

/// Financial-integrity tests: soft-delete handling in P&L, audit trails on
/// destructive paths, and payment guards. They exercise the REAL providers
/// against the REAL fresh-install schema on an in-memory FFI database.
///
/// The farmer-visible contract under test:
/// * a soft-deleted expense never leaks back into P&L through a linked
///   activity (the recycle bin must actually hide the cost);
/// * an expense linked to a crop BOTH via an activity and directly is
///   counted exactly once;
/// * deleting/re-editing an activity soft-deletes (never hard-deletes) its
///   auto-created expense, with an audit row;
/// * installment payments reject zero/negative amounts loudly;
/// * reopening an installment or deleting an ushr record leaves an audit
///   trail instead of silently destroying financial history.
void main() {
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  late Database db;
  late ActivityProvider activities;
  late ThekaProvider thekas;
  late UshrProvider ushr;
  late int farmId;
  late int fieldId;
  late int seasonId;

  Future<Database> openFreshDb() {
    return openDatabase(
      inMemoryDatabasePath,
      onConfigure: (db) async {
        await db.execute('PRAGMA foreign_keys = ON');
      },
    );
  }

  Future<List<Map<String, dynamic>>> auditRows(
    String table,
    int rowId,
  ) {
    return db.query(
      'audit_log',
      where: 'table_name = ? AND row_id = ?',
      whereArgs: [table, rowId],
      orderBy: 'id ASC',
    );
  }

  CropSeasonWithDetails seasonDetails() {
    return CropSeasonWithDetails(
      cropSeason: CropSeason(
        id: seasonId,
        fieldId: fieldId,
        cropName: 'گندم',
        variety: 'دیسی',
        status: 'active',
        startDate: '2026-01-01',
      ),
      fields: const [],
      fieldNames: const [],
      farmNames: const [],
      totalArea: 5.0,
    );
  }

  setUp(() async {
    db = await openFreshDb();
    await DatabaseHelper.instance.createFreshSchemaForTests(db);

    farmId = await db.insert('farms', {
      'name': 'ٹیسٹ فارم',
      'total_area': 5.0,
      'created_at': DateTime.now().toIso8601String(),
    });
    fieldId = await db.insert('fields', {
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

    activities = ActivityProvider(testExecutor: db);
    thekas = ThekaProvider(testExecutor: db);
    ushr = UshrProvider(testExecutor: db);
  });

  tearDown(() async {
    await db.close();
  });

  group('soft-deleted expenses stay out of P&L', () {
    test('fetchActivities hides a soft-deleted linked expense', () async {
      final expenseId = await db.insert('expenses', {
        'category': 'Fertilizer',
        'amount_paisa': 100000,
        'date': '2026-02-01',
        'description': 'کھاد',
        'crop_season_id': seasonId,
      });
      await activities.addActivity(
        cropSeasonId: seasonId,
        activityType: 'کھاد ڈالی',
        date: '2026-02-01',
        details: '',
        expenseId: expenseId,
      );

      await activities.fetchActivities();
      expect(activities.activities, hasLength(1));
      expect(activities.activities.single.expenseAmountPaisa, 100000);

      // The farmer deletes the expense from the Expenses screen.
      await db.update(
        'expenses',
        {'deleted_at': DateTime.now().toIso8601String()},
        where: 'id = ?',
        whereArgs: [expenseId],
      );

      await activities.fetchActivities();
      expect(activities.activities, hasLength(1));
      // The join must not resurrect the deleted expense's amount.
      expect(activities.activities.single.expenseAmountPaisa, isNull);
    });

    test('computeFarmPnl excludes the soft-deleted activity expense',
        () async {
      final expenseId = await db.insert('expenses', {
        'category': 'Fertilizer',
        'amount_paisa': 100000,
        'date': '2026-02-01',
        'description': 'کھاد',
        'crop_season_id': seasonId,
      });
      await activities.addActivity(
        cropSeasonId: seasonId,
        activityType: 'کھاد ڈالی',
        date: '2026-02-01',
        details: '',
        expenseId: expenseId,
      );
      await db.update(
        'expenses',
        {'deleted_at': DateTime.now().toIso8601String()},
        where: 'id = ?',
        whereArgs: [expenseId],
      );
      await activities.fetchActivities();

      final pnl = computeFarmPnl(
        harvests: const [],
        totalExpensesPaisa: 0,
        seasons: [seasonDetails()],
        activities: activities.activities,
        expenses: const [],
        ushrRecords: const [],
      );

      expect(pnl.crops.single.expensesPaisa, 0);
    });

    test('an expense linked both ways is counted exactly once', () async {
      final expenseId = await db.insert('expenses', {
        'category': 'Fertilizer',
        'amount_paisa': 100000,
        'date': '2026-02-01',
        'description': 'کھاد',
        'crop_season_id': seasonId,
      });
      await activities.addActivity(
        cropSeasonId: seasonId,
        activityType: 'کھاد ڈالی',
        date: '2026-02-01',
        details: '',
        expenseId: expenseId,
      );
      await activities.fetchActivities();

      final expense = Expense(
        id: expenseId,
        category: 'Fertilizer',
        amountPaisa: 100000,
        date: '2026-02-01',
        description: 'کھاد',
        cropSeasonId: seasonId,
      );

      final pnl = computeFarmPnl(
        harvests: const [],
        totalExpensesPaisa: 100000,
        seasons: [seasonDetails()],
        activities: activities.activities,
        expenses: [expense],
        ushrRecords: const [],
      );

      // Once via the activity link — not twice via the direct link too.
      expect(pnl.crops.single.expensesPaisa, 100000);
    });
  });

  group('activity delete/edit keeps expense history', () {
    test('deleteActivity soft-deletes the linked expense with audit row',
        () async {
      await activities.addActivity(
        cropSeasonId: seasonId,
        activityType: 'کھاد ڈالی',
        date: '2026-02-01',
        details: '',
        expenseAmountPaisa: 50000,
        expenseCategory: 'Fertilizer',
      );
      final activityId =
          (await db.query('activities', orderBy: 'id DESC')).first['id'] as int;
      final expenseId =
          (await db.query('expenses', orderBy: 'id DESC')).first['id'] as int;

      await activities.deleteActivity(activityId);

      // The expense row survives, hidden from lists, restorable.
      final expense =
          (await db.query('expenses', where: 'id = ?', whereArgs: [expenseId]))
              .single;
      expect(expense['deleted_at'], isNotNull);
      expect(expense['amount_paisa'], 50000);

      final logs = await auditRows('expenses', expenseId);
      expect(
        logs.map((l) => l['action']),
        contains('soft_delete'),
      );
    });

    test('updateActivity dropping the expense soft-deletes it', () async {
      await activities.addActivity(
        cropSeasonId: seasonId,
        activityType: 'پانی لگایا',
        date: '2026-02-01',
        details: '',
        expenseAmountPaisa: 20000,
        expenseCategory: 'Water',
      );
      final activityId =
          (await db.query('activities', orderBy: 'id DESC')).first['id'] as int;
      final expenseId =
          (await db.query('expenses', orderBy: 'id DESC')).first['id'] as int;

      await activities.updateActivity(
        id: activityId,
        cropSeasonId: seasonId,
        activityType: 'پانی لگایا',
        date: '2026-02-01',
        details: 'نہر — مفت',
        expenseAmountPaisa: null,
      );

      final expense =
          (await db.query('expenses', where: 'id = ?', whereArgs: [expenseId]))
              .single;
      expect(expense['deleted_at'], isNotNull);
      expect(await auditRows('expenses', expenseId), isNotEmpty);
    });
  });

  group('theka payments', () {
    Future<int> addThekaWithInstallment() async {
      await thekas.addTheka(
        Theka(
          farmId: farmId,
          totalAmountPaisa: 200000,
          durationType: 'Seasonal',
          paymentMethod: 'Installment',
          createdAt: DateTime.now().toIso8601String(),
        ),
        [
          ThekaInstallment(
            thekaId: 0,
            amountPaisa: 200000,
            dueDate: '2026-06-01',
            status: 'Pending',
          ),
        ],
      );
      return (await db.query('theka_installments', orderBy: 'id DESC'))
          .first['id'] as int;
    }

    test('payInstallment rejects zero and negative amounts', () async {
      final installmentId = await addThekaWithInstallment();

      await expectLater(
        thekas.payInstallment(
          installmentId: installmentId,
          paidAmountPaisa: 0,
          paidDate: '2026-03-01',
          farmName: 'ٹیسٹ فارم',
          installmentIndex: 1,
        ),
        throwsA(isA<Exception>()),
      );
      await expectLater(
        thekas.payInstallment(
          installmentId: installmentId,
          paidAmountPaisa: -5000,
          paidDate: '2026-03-01',
          farmName: 'ٹیسٹ فارم',
          installmentIndex: 1,
        ),
        throwsA(isA<Exception>()),
      );

      // Nothing was written: no expense, and no payment audit trail —
      // only addTheka's own 'create' row exists.
      expect(await db.query('expenses'), isEmpty);
      final updates = await db.query(
        'audit_log',
        where: 'action = ?',
        whereArgs: ['update'],
      );
      expect(updates, isEmpty);
    });

    test('markInstallmentPending soft-deletes the expense with audit row',
        () async {
      final installmentId = await addThekaWithInstallment();
      await thekas.payInstallment(
        installmentId: installmentId,
        paidAmountPaisa: 50000,
        paidDate: '2026-03-01',
        farmName: 'ٹیسٹ فارم',
        installmentIndex: 1,
      );
      final expenseId =
          (await db.query('expenses', orderBy: 'id DESC')).first['id'] as int;

      await thekas.markInstallmentPending(installmentId);

      final expense =
          (await db.query('expenses', where: 'id = ?', whereArgs: [expenseId]))
              .single;
      expect(expense['deleted_at'], isNotNull);

      final logs = await auditRows('expenses', expenseId);
      expect(logs.map((l) => l['action']), contains('soft_delete'));

      final inst =
          (await db.query(
            'theka_installments',
            where: 'id = ?',
            whereArgs: [installmentId],
          )).single;
      expect(inst['status'], 'Pending');
      expect(inst['paid_amount_paisa'], 0);
    });
  });

  group('ushr records', () {
    Future<int> addPaidUshr() async {
      await ushr.addUshrRecord(
        cropSeasonId: seasonId,
        harvestQty: 40,
        marketValuePaisa: 400000,
        ushrMethod: 'Cash',
        ushrPercentage: 10,
        ushrAmountPaisa: 40000,
        status: 'Paid',
        datePaid: '2026-04-01',
        payMethod: 'Cash',
        qtyPaid: 0,
        cashPaidPaisa: 40000,
        ratePerUnitPaisa: 0,
      );
      return (await db.query('ushr_records', orderBy: 'id DESC'))
          .first['id'] as int;
    }

    test('updateUshrRecord to zero payment soft-deletes the expense mirror',
        () async {
      final ushrId = await addPaidUshr();
      final expenseId =
          (await db.query('expenses', orderBy: 'id DESC')).first['id'] as int;

      await ushr.updateUshrRecord(
        id: ushrId,
        cropSeasonId: seasonId,
        harvestQty: 40,
        marketValuePaisa: 400000,
        ushrMethod: 'Cash',
        ushrPercentage: 10,
        ushrAmountPaisa: 40000,
        status: 'Pending',
        payMethod: 'Cash',
        qtyPaid: 0,
        cashPaidPaisa: 0,
        ratePerUnitPaisa: 0,
      );

      final expense =
          (await db.query('expenses', where: 'id = ?', whereArgs: [expenseId]))
              .single;
      expect(expense['deleted_at'], isNotNull);
      expect(await auditRows('expenses', expenseId), isNotEmpty);

      final record =
          (await db.query(
            'ushr_records',
            where: 'id = ?',
            whereArgs: [ushrId],
          )).single;
      expect(record['expense_id'], isNull);
    });

    test('deleteUshrRecord writes audit rows for both deletions', () async {
      final ushrId = await addPaidUshr();
      final expenseId =
          (await db.query('expenses', orderBy: 'id DESC')).first['id'] as int;

      await ushr.deleteUshrRecord(ushrId);

      expect(
        await db.query('ushr_records', where: 'id = ?', whereArgs: [ushrId]),
        isEmpty,
      );
      expect(
        await db.query('expenses', where: 'id = ?', whereArgs: [expenseId]),
        isEmpty,
      );

      // The history survives in the audit log, with amounts.
      final ushrLogs = await auditRows('ushr_records', ushrId);
      expect(ushrLogs.map((l) => l['action']), contains('delete'));
      final expenseLogs = await auditRows('expenses', expenseId);
      expect(expenseLogs.map((l) => l['action']), contains('delete'));
    });
  });
}
