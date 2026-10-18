import 'package:flutter/material.dart';
import 'package:sqflite/sqflite.dart';
import '../database/db_helper.dart';
import '../models/models.dart';
import '../services/audit_service.dart';
import '../services/money.dart';
import '../services/quantity.dart';
import '../services/unit_display.dart';

class UshrWithDetails {
  final UshrRecord ushrRecord;
  final String cropName;
  final String fieldName;
  final String farmName;
  final double fieldSize;

  UshrWithDetails({
    required this.ushrRecord,
    required this.cropName,
    required this.fieldName,
    required this.farmName,
    required this.fieldSize,
  });
}

class UshrProvider extends ChangeNotifier {
  /// Test hook: when set, all DB access goes through this executor instead
  /// of the app singleton, so tests never touch the real database file.
  final DatabaseExecutor? testExecutor;

  UshrProvider({this.testExecutor});

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

  List<UshrWithDetails> _ushrRecords = [];

  List<UshrWithDetails> get ushrRecords => _ushrRecords;

  /// Pure ushr-amount computation, extracted verbatim from ushr_screen.dart
  /// so it is unit-testable: (marketValuePaisa * percentage / 100.0).round().
  ///
  /// No behavior change — the screen calls this now.
  static int computeUshrAmountPaisa(int marketValuePaisa, double percentage) =>
      (marketValuePaisa * percentage / 100.0).round();

  /// D2: a payment must never exceed the ushr due — blocks accidental
  /// double-payment at the provider boundary. Also rejects negative
  /// payments. Throws a plain [Exception] with a Urdu message (the theka
  /// overpayment guard follows the same convention) so the screen can show
  /// it directly and keep the dialog open.
  ///
  /// Pure and static, so it is unit-testable without a database.
  static void validatePaymentWithinDue({
    required int ushrAmountPaisa,
    required int cashPaidPaisa,
    required double qtyPaid,
    required int ratePerUnitPaisa,
  }) {
    if (cashPaidPaisa < 0 || qtyPaid < 0) {
      throw Exception('ادائیگی کی رقم منفی نہیں ہو سکتی۔');
    }
    final int totalPaidPaisa =
        cashPaidPaisa + (qtyPaid * ratePerUnitPaisa).round();
    if (totalPaidPaisa > ushrAmountPaisa) {
      throw Exception(
        'ادا شدہ رقم (${Money(totalPaidPaisa).format()}) واجب الادا عشر '
        '(${Money(ushrAmountPaisa).format()}) سے زیادہ ہے۔ ادائیگی درست کر کے دوبارہ کوشش کریں۔',
      );
    }
  }

  /// Audit-details prefix marking that the S7 in-kind deduction logic has
  /// managed an ushr record. Legacy records (created before the deduction
  /// existed) carry no such entry, so deletes and edits can tell them apart
  /// and never invent grain. The trailing ' —' keeps '#7' from matching
  /// '#70' in the LIKE query in [_hasInKindMarker].
  static String _inKindMarker(int ushrId) =>
      'عشر جنس ایڈجسٹمنٹ — ریکارڈ #$ushrId —';

  /// True when the S7 logic previously applied a harvest adjustment for
  /// [ushrId] (see [_inKindMarker]). Best-effort on a missing audit_log
  /// table, mirroring [AuditService.log].
  Future<bool> _hasInKindMarker(DatabaseExecutor txn, int ushrId) async {
    try {
      final rows = await txn.query(
        'audit_log',
        columns: ['id'],
        where: 'table_name = ? AND details LIKE ?',
        whereArgs: ['harvests', '%${_inKindMarker(ushrId)}%'],
        limit: 1,
      );
      return rows.isNotEmpty;
    } on DatabaseException catch (e) {
      if (e.toString().contains('no such table')) return false;
      rethrow;
    }
  }

  /// S7: adjusts the linked harvest's quantity for an in-kind ushr payment.
  ///
  /// Exactly one net adjustment is applied per call, inside the caller's
  /// transaction: the previously deducted share is undone first, then the
  /// new share is deducted. A no-op update (same values) therefore nets to
  /// zero — this is what guarantees "never double-reduce".
  ///
  /// The deduction is proportional: harvest.quantity × (qtyPaid /
  /// harvestQty). The ushr record is self-consistent (market value =
  /// harvestQty × rate, in-kind value = qtyPaid × rate), so the ratio is
  /// unit-agnostic — it equals a من→unit conversion whenever harvestQty is
  /// the harvest's quantity in من, and it stays correct for units
  /// [UnitConverter] cannot bridge (بوری، کسٹم، …) where a conversion
  /// would have to throw.
  ///
  /// [oldQtyPaid]/[oldHarvestQty] describe the previous state (0.0/anything
  /// when nothing was deducted before — e.g. a new record, or a legacy
  /// record being managed for the first time); [newQtyPaid]/[newHarvestQty]
  /// the new state. Throws a Urdu error when the harvest row is missing
  /// or the deduction would drive its quantity negative.
  Future<void> _adjustHarvestInKind(
    DatabaseExecutor txn, {
    required int ushrId,
    required int harvestId,
    required double oldQtyPaid,
    required double oldHarvestQty,
    required double newQtyPaid,
    required double newHarvestQty,
  }) async {
    final double oldRatio = oldHarvestQty > 0 ? oldQtyPaid / oldHarvestQty : 0.0;
    final double newRatio;
    if (newQtyPaid <= 0) {
      newRatio = 0.0;
    } else if (newHarvestQty <= 0) {
      throw Exception('عشر کی جنس درج کرنے کے لیے فصل کی مقدار ضروری ہے۔');
    } else {
      newRatio = newQtyPaid / newHarvestQty;
    }
    if (oldRatio == 0.0 && newRatio == 0.0) return;

    final List<Map<String, dynamic>> hMaps = await txn.query(
      'harvests',
      where: 'id = ?',
      whereArgs: [harvestId],
    );
    if (hMaps.isEmpty) {
      throw Exception(
        'منسلک فصل کا ریکارڈ نہیں ملا — عشر کی جنس ایڈجسٹ نہیں ہو سکی۔',
      );
    }
    final double currentQty = (hMaps.first['quantity'] as num).toDouble();
    final String unit = (hMaps.first['unit'] as String?) ?? 'من';

    // Undo exactly what was deducted before, then deduct the new share.
    // The undo is derived from the current quantity, so it is exact as long
    // as the harvest quantity wasn't hand-edited between the two ushr
    // operations (hand-edits make it best-effort — documented, not silent:
    // every adjustment is audit-logged below).
    final double undone =
        oldRatio <= 0
            ? 0.0
            : oldRatio >= 1
            ? currentQty // Degenerate (fully deducted before); best effort.
            : currentQty * oldRatio / (1.0 - oldRatio);
    final double preQty = currentQty + undone;
    final double deduct = preQty * newRatio;
    if (deduct - preQty > 1e-9) {
      throw Exception(
        'عشر میں دی گئی جنس فصل کی دستیاب مقدار '
        '(${UnitDisplay.format(currentQty, unit)}) سے زیادہ ہے۔',
      );
    }
    double updatedQty = preQty - deduct;
    if (updatedQty < 0 && updatedQty > -1e-9) updatedQty = 0.0; // float dust

    await txn.update(
      'harvests',
      {'quantity': updatedQty},
      where: 'id = ?',
      whereArgs: [harvestId],
    );

    final double net = updatedQty - currentQty;
    if (net < -1e-9) {
      await AuditService.log(
        txn,
        table: 'harvests',
        rowId: harvestId,
        action: AuditService.update,
        details:
            '${_inKindMarker(ushrId)} فصل سے ${UnitDisplay.format(-net, unit)} منہا',
      );
    } else if (net > 1e-9) {
      await AuditService.log(
        txn,
        table: 'harvests',
        rowId: harvestId,
        action: AuditService.update,
        details:
            '${_inKindMarker(ushrId)} فصل میں ${UnitDisplay.format(net, unit)} واپس',
      );
    }
  }

  Future<void> fetchUshrRecords() async {
    // Keep the last good list on DB failure (main.dart calls this
    // unawaited at launch); the failure is reported, never thrown.
    try {
      await _fetchUshrRecords();
    } catch (e) {
      debugPrint('fetchUshrRecords failed: $e');
    }
    notifyListeners();
  }

  Future<void> _fetchUshrRecords() async {
    final db = await _db();
    // remaining_balance is COMPUTED in the UshrRecord model now — never read
    // from (or written to) the database.
    final String query = '''
      SELECT 
        u.id as u_id, u.crop_season_id, u.harvest_id, u.harvest_qty, u.market_value_paisa,
        u.ushr_method, u.ushr_percentage, u.ushr_amount_paisa, u.status, u.date_paid,
        u.notes, u.expense_id, u.pay_method, u.qty_paid, u.cash_paid_paisa, u.rate_per_unit_paisa,
        cs.crop_name, f.name as field_name, f.size_acres as field_size, farm.name as farm_name
      FROM ushr_records u
      JOIN crop_seasons cs ON u.crop_season_id = cs.id
      JOIN fields f ON cs.field_id = f.id
      JOIN farms farm ON f.farm_id = farm.id
      ORDER BY u.id DESC
    ''';

    final List<Map<String, dynamic>> results = await db.rawQuery(query);

    _ushrRecords = List.generate(results.length, (i) {
      final record = UshrRecord(
        id: results[i]['u_id'],
        cropSeasonId: results[i]['crop_season_id'],
        harvestId: results[i]['harvest_id'],
        harvestQty: (results[i]['harvest_qty'] as num).toDouble(),
        marketValuePaisa: results[i]['market_value_paisa'] as int,
        ushrMethod: results[i]['ushr_method'],
        ushrPercentage: (results[i]['ushr_percentage'] as num).toDouble(),
        ushrAmountPaisa: results[i]['ushr_amount_paisa'] as int,
        status: results[i]['status'] ?? 'Pending',
        datePaid: results[i]['date_paid'],
        notes: results[i]['notes'],
        expenseId: results[i]['expense_id'],
        payMethod: results[i]['pay_method'] ?? 'Cash',
        qtyPaid: (results[i]['qty_paid'] ?? 0.0 as num).toDouble(),
        cashPaidPaisa: (results[i]['cash_paid_paisa'] ?? 0) as int,
        ratePerUnitPaisa: (results[i]['rate_per_unit_paisa'] ?? 0) as int,
      );

      return UshrWithDetails(
        ushrRecord: record,
        cropName: results[i]['crop_name'],
        fieldName: results[i]['field_name'],
        fieldSize: (results[i]['field_size'] as num).toDouble(),
        farmName: results[i]['farm_name'],
      );
    });
  }

  /// All money in INTEGER paisa. `totalPaidPaisa` is derived, never passed:
  /// cash paid + (crop-qty paid x rate), rounded to the nearest paisa.
  Future<void> addUshrRecord({
    required int cropSeasonId,
    int? harvestId,
    required double harvestQty,
    required int marketValuePaisa,
    required String ushrMethod,
    required double ushrPercentage,
    required int ushrAmountPaisa,
    required String status,
    String? datePaid,
    String? notes,
    required String payMethod,
    required double qtyPaid,
    required int cashPaidPaisa,
    required int ratePerUnitPaisa,
  }) async {
    Quantity.requireFinite(harvestQty);
    Quantity.requireFinite(ushrPercentage);
    Quantity.requireFinite(qtyPaid);
    // D2: block overpayment (and negative payments) before touching the DB.
    validatePaymentWithinDue(
      ushrAmountPaisa: ushrAmountPaisa,
      cashPaidPaisa: cashPaidPaisa,
      qtyPaid: qtyPaid,
      ratePerUnitPaisa: ratePerUnitPaisa,
    );
    final int totalPaidPaisa =
        cashPaidPaisa + (qtyPaid * ratePerUnitPaisa).round();

    await _txn((txn) async {
      int? expenseId;
      if (totalPaidPaisa > 0) {
        String payTypeUrdu = 'نقد (Cash)';
        if (payMethod == 'Crop') {
          payTypeUrdu = 'جنس/فصل (Crop)';
        } else if (payMethod == 'Mixed') {
          payTypeUrdu = 'نقد + جنس (Mixed)';
        }

        expenseId = await txn.insert('expenses', {
          'category': 'Ushr Expense',
          'amount_paisa': totalPaidPaisa,
          'date': datePaid ?? DateTime.now().toString().split(' ')[0],
          'description': 'عشر ادائیگی برائے فصل کٹائی (طریقہ: $payTypeUrdu)',
        });
      }

      final int ushrId = await txn.insert('ushr_records', {
        'crop_season_id': cropSeasonId,
        'harvest_id': harvestId,
        'harvest_qty': harvestQty,
        'market_value_paisa': marketValuePaisa,
        'ushr_method': ushrMethod,
        'ushr_percentage': ushrPercentage,
        'ushr_amount_paisa': ushrAmountPaisa,
        'status': status,
        'date_paid': datePaid,
        'notes': notes,
        'expense_id': expenseId,
        'pay_method': payMethod,
        'qty_paid': qtyPaid,
        'cash_paid_paisa': cashPaidPaisa,
        'rate_per_unit_paisa': ratePerUnitPaisa,
      });

      // S7: an in-kind payment reduces the linked harvest's quantity —
      // exactly once, inside this same transaction (rolls back with the
      // ushr row when the deduction is impossible).
      if (harvestId != null && qtyPaid > 0) {
        await _adjustHarvestInKind(
          txn,
          ushrId: ushrId,
          harvestId: harvestId,
          oldQtyPaid: 0.0,
          oldHarvestQty: harvestQty,
          newQtyPaid: qtyPaid,
          newHarvestQty: harvestQty,
        );
      }
    });

    await fetchUshrRecords();
  }

  Future<void> updateUshrRecord({
    required int id,
    required int cropSeasonId,
    int? harvestId,
    required double harvestQty,
    required int marketValuePaisa,
    required String ushrMethod,
    required double ushrPercentage,
    required int ushrAmountPaisa,
    required String status,
    String? datePaid,
    String? notes,
    required String payMethod,
    required double qtyPaid,
    required int cashPaidPaisa,
    required int ratePerUnitPaisa,
  }) async {
    Quantity.requireFinite(harvestQty);
    Quantity.requireFinite(ushrPercentage);
    Quantity.requireFinite(qtyPaid);
    // D2: block overpayment (and negative payments) before touching the DB.
    validatePaymentWithinDue(
      ushrAmountPaisa: ushrAmountPaisa,
      cashPaidPaisa: cashPaidPaisa,
      qtyPaid: qtyPaid,
      ratePerUnitPaisa: ratePerUnitPaisa,
    );
    final int totalPaidPaisa =
        cashPaidPaisa + (qtyPaid * ratePerUnitPaisa).round();

    await _txn((txn) async {
      final List<Map<String, dynamic>> existing = await txn.query(
        'ushr_records',
        where: 'id = ?',
        whereArgs: [id],
      );
      if (existing.isEmpty) return;

      // S7: previous in-kind state, for consistent re-adjustment below.
      final int? oldHarvestId = existing.first['harvest_id'] as int?;
      final double oldQtyPaid =
          (existing.first['qty_paid'] as num?)?.toDouble() ?? 0.0;
      final double oldHarvestQty =
          (existing.first['harvest_qty'] as num?)?.toDouble() ?? 0.0;
      // Whether the S7 logic ever deducted for this record. Legacy records
      // (created before the deduction existed) never deducted, so their
      // first managed edit deducts the full new share instead of a delta.
      final bool managedBefore = await _hasInKindMarker(txn, id);

      int? expenseId = existing.first['expense_id'] as int?;

      if (totalPaidPaisa > 0) {
        String payTypeUrdu = 'نقد (Cash)';
        if (payMethod == 'Crop') {
          payTypeUrdu = 'جنس/فصل (Crop)';
        } else if (payMethod == 'Mixed') {
          payTypeUrdu = 'نقد + جنس (Mixed)';
        }

        if (expenseId == null) {
          expenseId = await txn.insert('expenses', {
            'category': 'Ushr Expense',
            'amount_paisa': totalPaidPaisa,
            'date': datePaid ?? DateTime.now().toString().split(' ')[0],
            'description': 'عشر ادائیگی برائے فصل کٹائی (طریقہ: $payTypeUrdu)',
          });
        } else {
          await txn.update(
            'expenses',
            {
              'amount_paisa': totalPaidPaisa,
              'date': datePaid ?? DateTime.now().toString().split(' ')[0],
              'description':
                  'عشر ادائیگی برائے فصل کٹائی (طریقہ: $payTypeUrdu)',
            },
            where: 'id = ?',
            whereArgs: [expenseId],
          );
        }
      } else {
        if (expenseId != null) {
          // Soft-delete (never hard-delete): the 'Ushr Expense' mirror stays
          // restorable in the recycle bin and the audit log keeps the record.
          await txn.update(
            'expenses',
            {'deleted_at': DateTime.now().toIso8601String()},
            where: 'id = ? AND deleted_at IS NULL',
            whereArgs: [expenseId],
          );
          await AuditService.log(
            txn,
            table: 'expenses',
            rowId: expenseId,
            action: AuditService.softDelete,
            details: 'عشر ریکارڈ تبدیل — ادائیگی صفر ہونے پر خرچہ حذف',
          );
          expenseId = null;
        }
      }

      await txn.update(
        'ushr_records',
        {
          'crop_season_id': cropSeasonId,
          'harvest_id': harvestId,
          'harvest_qty': harvestQty,
          'market_value_paisa': marketValuePaisa,
          'ushr_method': ushrMethod,
          'ushr_percentage': ushrPercentage,
          'ushr_amount_paisa': ushrAmountPaisa,
          'status': status,
          'date_paid': datePaid,
          'notes': notes,
          'expense_id': expenseId,
          'pay_method': payMethod,
          'qty_paid': qtyPaid,
          'cash_paid_paisa': cashPaidPaisa,
          'rate_per_unit_paisa': ratePerUnitPaisa,
        },
        where: 'id = ?',
        whereArgs: [id],
      );

      // S7: re-adjust the linked harvest(s) consistently, inside this same
      // transaction. Link moved or removed -> restore the old harvest in
      // full (only when the S7 logic had deducted from it); then deduct
      // the new share from the (possibly same) new harvest. A no-op edit
      // nets to zero — never double-reduces.
      if (oldHarvestId != null && oldHarvestId != harvestId && oldQtyPaid > 0) {
        await _adjustHarvestInKind(
          txn,
          ushrId: id,
          harvestId: oldHarvestId,
          oldQtyPaid: managedBefore ? oldQtyPaid : 0.0,
          oldHarvestQty: oldHarvestQty,
          newQtyPaid: 0.0,
          newHarvestQty: oldHarvestQty,
        );
      }
      if (harvestId != null &&
          (qtyPaid > 0 ||
              (managedBefore &&
                  oldHarvestId == harvestId &&
                  oldQtyPaid > 0))) {
        await _adjustHarvestInKind(
          txn,
          ushrId: id,
          harvestId: harvestId,
          oldQtyPaid:
              managedBefore && oldHarvestId == harvestId ? oldQtyPaid : 0.0,
          oldHarvestQty: oldHarvestQty,
          newQtyPaid: qtyPaid,
          newHarvestQty: harvestQty,
        );
      }
    });

    await fetchUshrRecords();
  }

  Future<void> deleteUshrRecord(int id) async {
    await _txn((txn) async {
      final List<Map<String, dynamic>> existing = await txn.query(
        'ushr_records',
        where: 'id = ?',
        whereArgs: [id],
      );
      if (existing.isNotEmpty) {
        // S7: give the deducted grain back to the linked harvest — but only
        // when the S7 logic actually deducted it (audit marker). Restoring
        // for a legacy record would invent grain that never left the stock.
        final int? linkedHarvestId = existing.first['harvest_id'] as int?;
        final double paidQty =
            (existing.first['qty_paid'] as num?)?.toDouble() ?? 0.0;
        if (linkedHarvestId != null &&
            paidQty > 0 &&
            await _hasInKindMarker(txn, id)) {
          final double recordHarvestQty =
              (existing.first['harvest_qty'] as num?)?.toDouble() ?? 0.0;
          try {
            await _adjustHarvestInKind(
              txn,
              ushrId: id,
              harvestId: linkedHarvestId,
              oldQtyPaid: paidQty,
              oldHarvestQty: recordHarvestQty,
              newQtyPaid: 0.0,
              newHarvestQty: recordHarvestQty,
            );
          } on Exception {
            // Best-effort: the ushr record must stay deletable even if the
            // harvest changed incompatibly after the deduction. The
            // shortfall is audit-logged, never silent.
            await AuditService.log(
              txn,
              table: 'harvests',
              rowId: linkedHarvestId,
              action: AuditService.update,
              details: '${_inKindMarker(id)} واپسی ناکام — عشر ریکارڈ حذف',
            );
          }
        }

        final int? expenseId = existing.first['expense_id'] as int?;
        if (expenseId != null) {
          // ushr_records has no soft-delete column, so the record and its
          // auto-created expense mirror are hard-deleted as a pair — but
          // both deletions are written to the audit log first, with amounts,
          // so the financial history is never silently lost.
          await AuditService.log(
            txn,
            table: 'expenses',
            rowId: expenseId,
            action: AuditService.delete,
            details:
                'عشر ریکارڈ حذف ہونے پر خرچہ حذف — ${Money((existing.first['cash_paid_paisa'] as int?) ?? 0).format()}',
          );
          await txn.delete('expenses', where: 'id = ?', whereArgs: [expenseId]);
        }
        await AuditService.log(
          txn,
          table: 'ushr_records',
          rowId: id,
          action: AuditService.delete,
          details:
              'عشر ریکارڈ حذف — واجب الادا ${Money((existing.first['ushr_amount_paisa'] as int?) ?? 0).format()}',
        );
      }

      await txn.delete('ushr_records', where: 'id = ?', whereArgs: [id]);
    });

    await fetchUshrRecords();
  }
}
