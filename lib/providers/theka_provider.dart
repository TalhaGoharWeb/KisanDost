import 'package:flutter/material.dart';
import 'package:sqflite/sqflite.dart';
import '../database/db_helper.dart';
import '../models/models.dart';
import '../services/audit_service.dart';
import '../services/money.dart';

class ThekaProvider extends ChangeNotifier {
  /// Test hook: when set, all DB access goes through this executor instead
  /// of the app singleton, so tests never touch the real database file.
  final DatabaseExecutor? testExecutor;

  ThekaProvider({this.testExecutor});

  Future<DatabaseExecutor> _db() async =>
      testExecutor ?? await DatabaseHelper.instance.database;

  /// Runs [action] inside a real transaction when the executor is a full
  /// [Database]; a bare [Transaction] (or any other executor a test hands
  /// in) already runs inside one, so the action runs directly.
  Future<T> _txn<T>(Future<T> Function(DatabaseExecutor txn) action) async {
    final db = await _db();
    if (db is Database) {
      return await db.transaction(action);
    }
    return await action(db);
  }

  List<Theka> _thekas = [];
  final Map<int, List<ThekaInstallment>> _thekaInstallments = {}; // thekaId -> installments

  List<Theka> get thekas => _thekas;

  /// Last load failure, if any. Sections show it as a retryable Urdu error.
  String? _errorMessage;
  String? get errorMessage => _errorMessage;

  List<ThekaInstallment> getInstallmentsForTheka(int thekaId) {
    return _thekaInstallments[thekaId] ?? [];
  }

  /// All installments across all thekas, read-only (for the home snapshot).
  List<ThekaInstallment> get allInstallments =>
      _thekaInstallments.values.expand((list) => list).toList();

  Theka? getThekaById(int id) {
    for (final t in _thekas) {
      if (t.id == id) return t;
    }
    return null;
  }

  Future<void> fetchThekas() async {
    _errorMessage = null;
    try {
      await _fetchThekas();
    } catch (_) {
      _errorMessage = 'ٹھیکے کا ریکارڈ لوڈ نہیں ہو سکا۔ دوبارہ کوشش کریں۔';
      notifyListeners();
    }
  }

  Future<void> _fetchThekas() async {
    final db = await _db();
    final List<Map<String, dynamic>> maps = await db.query('thekas', orderBy: 'id DESC');
    _thekas = List.generate(maps.length, (i) => Theka.fromMap(maps[i]));

    for (var theka in _thekas) {
      if (theka.id != null) {
        final List<Map<String, dynamic>> instMaps = await db.query(
          'theka_installments',
          where: 'theka_id = ?',
          whereArgs: [theka.id],
          orderBy: 'due_date ASC, id ASC',
        );
        _thekaInstallments[theka.id!] = List.generate(
          instMaps.length,
          (i) => ThekaInstallment.fromMap(instMaps[i]),
        );
      }
    }
    notifyListeners();
  }

  Future<void> addTheka(Theka theka, List<ThekaInstallment> installments) async {
    final db = await _db();
    await _txn((txn) async {
      final thekaId = await txn.insert('thekas', theka.toMap());
      for (var inst in installments) {
        final newInst = ThekaInstallment(
          thekaId: thekaId,
          amountPaisa: inst.amountPaisa,
          dueDate: inst.dueDate,
          status: inst.status,
          paidAmountPaisa: inst.paidAmountPaisa,
          paidDate: inst.paidDate,
          expenseId: inst.expenseId,
        );
        await txn.insert('theka_installments', newInst.toMap());
      }
      await AuditService.log(
        txn,
        table: 'thekas',
        rowId: thekaId,
        action: AuditService.create,
        details:
            'ٹھیکہ — ${Money(theka.totalAmountPaisa).format()} (${theka.paymentMethod})',
      );
    });
    await fetchThekas();
  }

  /// DELIBERATE Phase 11: deleteTheka keeps its hard-delete semantics (the
  /// delete-theka problem is deferred by design). It is logged as a delete.
  Future<void> deleteTheka(int thekaId) async {
    final db = await _db();
    await _txn((txn) async {
      // 1. Delete associated expenses
      final List<Map<String, dynamic>> instMaps = await txn.query(
        'theka_installments',
        where: 'theka_id = ?',
        whereArgs: [thekaId],
      );
      for (var inst in instMaps) {
        final expenseId = inst['expense_id'] as int?;
        if (expenseId != null) {
          await txn.delete('expenses', where: 'id = ?', whereArgs: [expenseId]);
        }
      }
      // 2. Delete theka (cascading deletes installments due to db ON DELETE CASCADE)
      await txn.delete('thekas', where: 'id = ?', whereArgs: [thekaId]);
      await AuditService.log(
        txn,
        table: 'thekas',
        rowId: thekaId,
        action: AuditService.delete,
        details: 'ٹھیکہ حذف',
      );
    });
    await fetchThekas();
  }

  /// Records a payment against an installment.
  ///
  /// [paidAmountPaisa] is the INCREMENTAL amount being paid right now, in
  /// INTEGER paisa — it is ADDED to the already-recorded
  /// [ThekaInstallment.paidAmountPaisa], never replacing it. The linked
  /// 'Land Rent' expense always reflects the cumulative total paid so far.
  ///
  /// Throws an [Exception] with an Urdu message if the payment would take
  /// the total over the installment amount (overpayment is never recorded).
  Future<void> payInstallment({
    required int installmentId,
    required int paidAmountPaisa,
    required String paidDate,
    required String farmName,
    required int installmentIndex,
  }) async {
    final db = await _db();
    await _txn((txn) async {
      // 1. Fetch current installment
      final List<Map<String, dynamic>> maps = await txn.query(
        'theka_installments',
        where: 'id = ?',
        whereArgs: [installmentId],
      );
      if (maps.isEmpty) return;

      final currentInst = ThekaInstallment.fromMap(maps.first);

      // 2. Accumulate: add this payment to what is already recorded.
      //    All in INTEGER paisa — exact, no floating-point drift.
      final int newPaidTotalPaisa =
          currentInst.paidAmountPaisa + paidAmountPaisa;

      // 3. Overpayment guard: paid can never exceed the installment total.
      if (newPaidTotalPaisa > currentInst.amountPaisa) {
        final remaining = Money(currentInst.amountPaisa - currentInst.paidAmountPaisa);
        throw Exception(
            'ادا شدہ رقم قسط کی کل رقم (${Money(currentInst.amountPaisa).format()}) سے زیادہ نہیں ہو سکتی۔ بقایا رقم: ${remaining.format()}');
      }

      final isFullPayment = newPaidTotalPaisa >= currentInst.amountPaisa;
      final newStatus = isFullPayment ? 'Paid' : 'Partially Paid';

      int? expenseId = currentInst.expenseId;
      final String desc = isFullPayment
          ? 'ٹھیکہ ادائیگی: $farmName (قسط نمبر $installmentIndex)'
          : 'ٹھیکہ جزوی ادائیگی: $farmName (قسط نمبر $installmentIndex)';

      if (expenseId == null) {
        // Insert new expense entry (cumulative total paid so far)
        expenseId = await txn.insert('expenses', {
          'category': 'Land Rent', // standard category
          'amount_paisa': newPaidTotalPaisa,
          'date': paidDate,
          'description': desc,
        });
      } else {
        // Update existing expense entry to the cumulative total
        await txn.update(
          'expenses',
          {
            'amount_paisa': newPaidTotalPaisa,
            'date': paidDate,
            'description': desc,
          },
          where: 'id = ?',
          whereArgs: [expenseId],
        );
      }

      // Update installment
      await txn.update(
        'theka_installments',
        {
          'status': newStatus,
          'paid_amount_paisa': newPaidTotalPaisa,
          'paid_date': paidDate,
          'expense_id': expenseId,
        },
        where: 'id = ?',
        whereArgs: [installmentId],
      );
      await AuditService.log(
        txn,
        table: 'theka_installments',
        rowId: installmentId,
        action: AuditService.update,
        details: 'قسط ادائیگی — ${Money(paidAmountPaisa).format()} ($farmName)',
      );
    });
    await fetchThekas();
  }

  Future<void> markInstallmentPending(int installmentId) async {
    final db = await _db();
    await _txn((txn) async {
      final List<Map<String, dynamic>> maps = await txn.query(
        'theka_installments',
        where: 'id = ?',
        whereArgs: [installmentId],
      );
      if (maps.isEmpty) return;

      final currentInst = ThekaInstallment.fromMap(maps.first);
      final expenseId = currentInst.expenseId;

      if (expenseId != null) {
        await txn.delete('expenses', where: 'id = ?', whereArgs: [expenseId]);
      }

      await txn.update(
        'theka_installments',
        {
          'status': 'Pending',
          'paid_amount_paisa': 0,
          'paid_date': null,
          'expense_id': null,
        },
        where: 'id = ?',
        whereArgs: [installmentId],
      );
      await AuditService.log(
        txn,
        table: 'theka_installments',
        rowId: installmentId,
        action: AuditService.update,
        details: 'قسط دوبارہ زیر التواء',
      );
    });
    await fetchThekas();
  }

  Future<void> updateInstallmentSchedule(int thekaId, List<ThekaInstallment> newSchedule) async {
    final db = await _db();
    await _txn((txn) async {
      // Verify no payments are recorded yet
      final List<Map<String, dynamic>> maps = await txn.query(
        'theka_installments',
        where: 'theka_id = ? AND status != ?',
        whereArgs: [thekaId, 'Pending'],
      );
      if (maps.isNotEmpty) {
        throw Exception('ادائیگیاں ریکارڈ ہونے کی وجہ سے شیڈول تبدیل نہیں کیا جا سکتا۔');
      }

      // Delete old installments
      await txn.delete('theka_installments', where: 'theka_id = ?', whereArgs: [thekaId]);

      // Insert new installments
      for (var inst in newSchedule) {
        final newInst = ThekaInstallment(
          thekaId: thekaId,
          amountPaisa: inst.amountPaisa,
          dueDate: inst.dueDate,
          status: 'Pending',
          paidAmountPaisa: 0,
          paidDate: null,
          expenseId: null,
        );
        await txn.insert('theka_installments', newInst.toMap());
      }
      await AuditService.log(
        txn,
        table: 'thekas',
        rowId: thekaId,
        action: AuditService.update,
        details: 'شیڈول تبدیل',
      );
    });
    await fetchThekas();
  }
}
