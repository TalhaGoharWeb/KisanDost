import 'package:flutter/material.dart';
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
  List<UshrWithDetails> _ushrRecords = [];

  List<UshrWithDetails> get ushrRecords => _ushrRecords;

  Future<void> fetchUshrRecords() async {
    final db = await DatabaseHelper.instance.database;
    final String query = '''
      SELECT 
        u.id as u_id, u.crop_season_id, u.harvest_id, u.harvest_qty, u.market_value,
        u.ushr_method, u.ushr_percentage, u.ushr_amount, u.status, u.date_paid,
        u.notes, u.expense_id, u.pay_method, u.qty_paid, u.cash_paid, u.remaining_balance, u.rate_per_unit,
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
        marketValue: (results[i]['market_value'] as num).toDouble(),
        ushrMethod: results[i]['ushr_method'],
        ushrPercentage: (results[i]['ushr_percentage'] as num).toDouble(),
        ushrAmount: (results[i]['ushr_amount'] as num).toDouble(),
        status: results[i]['status'] ?? 'Pending',
        datePaid: results[i]['date_paid'],
        notes: results[i]['notes'],
        expenseId: results[i]['expense_id'],
        payMethod: results[i]['pay_method'] ?? 'Cash',
        qtyPaid: (results[i]['qty_paid'] ?? 0.0 as num).toDouble(),
        cashPaid: (results[i]['cash_paid'] ?? 0.0 as num).toDouble(),
        remainingBalance: (results[i]['remaining_balance'] ?? 0.0 as num).toDouble(),
        ratePerUnit: (results[i]['rate_per_unit'] ?? 0.0 as num).toDouble(),
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

  Future<void> addUshrRecord({
    required int cropSeasonId,
    int? harvestId,
    required double harvestQty,
    required double marketValue,
    required String ushrMethod,
    required double ushrPercentage,
    required double ushrAmount,
    required String status,
    String? datePaid,
    String? notes,
    required String payMethod,
    required double qtyPaid,
    required double cashPaid,
    required double remainingBalance,
    required double ratePerUnit,
  }) async {
    final db = await DatabaseHelper.instance.database;

    final double totalPaidPkr = cashPaid + (qtyPaid * ratePerUnit);

    await db.transaction((txn) async {
      int? expenseId;
      if (totalPaidPkr > 0) {
        String payTypeUrdu = 'نقد (Cash)';
        if (payMethod == 'Crop') {
          payTypeUrdu = 'جنس/فصل (Crop)';
        } else if (payMethod == 'Mixed') {
          payTypeUrdu = 'نقد + جنس (Mixed)';
        }

        expenseId = await txn.insert('expenses', {
          'category': 'Ushr Expense',
          'amount': totalPaidPkr,
          'date': datePaid ?? DateTime.now().toString().split(' ')[0],
          'description': 'عشر ادائیگی برائے فصل کٹائی (طریقہ: $payTypeUrdu)',
        });
      }

      await txn.insert('ushr_records', {
        'crop_season_id': cropSeasonId,
        'harvest_id': harvestId,
        'harvest_qty': harvestQty,
        'market_value': marketValue,
        'ushr_method': ushrMethod,
        'ushr_percentage': ushrPercentage,
        'ushr_amount': ushrAmount,
        'status': status,
        'date_paid': datePaid,
        'notes': notes,
        'expense_id': expenseId,
        'pay_method': payMethod,
        'qty_paid': qtyPaid,
        'cash_paid': cashPaid,
        'remaining_balance': remainingBalance,
        'rate_per_unit': ratePerUnit,
      });
    });

    await fetchUshrRecords();
  }

  Future<void> updateUshrRecord({
    required int id,
    required int cropSeasonId,
    int? harvestId,
    required double harvestQty,
    required double marketValue,
    required String ushrMethod,
    required double ushrPercentage,
    required double ushrAmount,
    required String status,
    String? datePaid,
    String? notes,
    required String payMethod,
    required double qtyPaid,
    required double cashPaid,
    required double remainingBalance,
    required double ratePerUnit,
  }) async {
    final db = await DatabaseHelper.instance.database;

    final double totalPaidPkr = cashPaid + (qtyPaid * ratePerUnit);

    await db.transaction((txn) async {
      final List<Map<String, dynamic>> existing = await txn.query(
        'ushr_records',
        where: 'id = ?',
        whereArgs: [id],
      );
      if (existing.isEmpty) return;

      int? expenseId = existing.first['expense_id'] as int?;

      if (totalPaidPkr > 0) {
        String payTypeUrdu = 'نقد (Cash)';
        if (payMethod == 'Crop') {
          payTypeUrdu = 'جنس/فصل (Crop)';
        } else if (payMethod == 'Mixed') {
          payTypeUrdu = 'نقد + جنس (Mixed)';
        }

        if (expenseId == null) {
          expenseId = await txn.insert('expenses', {
            'category': 'Ushr Expense',
            'amount': totalPaidPkr,
            'date': datePaid ?? DateTime.now().toString().split(' ')[0],
            'description': 'عشر ادائیگی برائے فصل کٹائی (طریقہ: $payTypeUrdu)',
          });
        } else {
          await txn.update(
            'expenses',
            {
              'amount': totalPaidPkr,
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
          'market_value': marketValue,
          'ushr_method': ushrMethod,
          'ushr_percentage': ushrPercentage,
          'ushr_amount': ushrAmount,
          'status': status,
          'date_paid': datePaid,
          'notes': notes,
          'expense_id': expenseId,
          'pay_method': payMethod,
          'qty_paid': qtyPaid,
          'cash_paid': cashPaid,
          'remaining_balance': remainingBalance,
          'rate_per_unit': ratePerUnit,
        },
        where: 'id = ?',
        whereArgs: [id],
      );
    });

    await fetchUshrRecords();
  }

  Future<void> deleteUshrRecord(int id) async {
    final db = await DatabaseHelper.instance.database;

    await db.transaction((txn) async {
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
