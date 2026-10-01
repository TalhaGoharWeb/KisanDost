import 'package:flutter/material.dart';
import 'package:sqflite/sqflite.dart';
import '../database/db_helper.dart';
import '../models/models.dart';

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

  Future<void> fetchUshrRecords() async {
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

    notifyListeners();
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

      await txn.insert('ushr_records', {
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
    final int totalPaidPaisa =
        cashPaidPaisa + (qtyPaid * ratePerUnitPaisa).round();

    await _txn((txn) async {
      final List<Map<String, dynamic>> existing = await txn.query(
        'ushr_records',
        where: 'id = ?',
        whereArgs: [id],
      );
      if (existing.isEmpty) return;

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
              'description': 'عشر ادائیگی برائے فصل کٹائی (طریقہ: $payTypeUrdu)',
            },
            where: 'id = ?',
            whereArgs: [expenseId],
          );
        }
      } else {
        if (expenseId != null) {
          await txn.delete('expenses', where: 'id = ?', whereArgs: [expenseId]);
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
        final int? expenseId = existing.first['expense_id'] as int?;
        if (expenseId != null) {
          await txn.delete('expenses', where: 'id = ?', whereArgs: [expenseId]);
        }
      }

      await txn.delete(
        'ushr_records',
        where: 'id = ?',
        whereArgs: [id],
      );
    });

    await fetchUshrRecords();
  }
}
