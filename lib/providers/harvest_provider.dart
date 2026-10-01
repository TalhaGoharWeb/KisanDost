import 'package:flutter/material.dart';
import 'package:sqflite/sqflite.dart';
import '../database/db_helper.dart';
import '../models/models.dart';
import '../services/audit_service.dart';
import '../services/money.dart';

class HarvestWithDetails {
  final Harvest harvest;
  final String cropName;
  final String fieldName;
  final double fieldSize;
  final String farmName;
  final Sale? sale; // Linked sale if sold

  HarvestWithDetails({
    required this.harvest,
    required this.cropName,
    required this.fieldName,
    required this.fieldSize,
    required this.farmName,
    this.sale,
  });
}

class HarvestProvider extends ChangeNotifier {
  /// Test hook: when set, all DB access goes through this executor instead
  /// of the app singleton, so tests never touch the real database file.
  final DatabaseExecutor? testExecutor;

  HarvestProvider({this.testExecutor});

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

  List<HarvestWithDetails> _harvests = [];
  final List<Sale> _sales = [];

  List<HarvestWithDetails> get harvests => _harvests;
  List<Sale> get sales => _sales;

  /// Last load failure, if any. Sections show it as a retryable Urdu error.
  String? _errorMessage;
  String? get errorMessage => _errorMessage;

  /// Marks one row soft-deleted and writes the audit entry. Callers pass a
  /// short Urdu [details] summary.
  Future<void> _softDeleteRow(
    DatabaseExecutor txn,
    String table,
    int id,
    String details,
  ) async {
    await txn.update(
      table,
      {'deleted_at': DateTime.now().toIso8601String()},
      where: 'id = ?',
      whereArgs: [id],
    );
    await AuditService.log(
      txn,
      table: table,
      rowId: id,
      action: AuditService.softDelete,
      details: details,
    );
  }

  /// Restores one soft-deleted row and writes the audit entry.
  Future<void> _restoreRow(
    DatabaseExecutor txn,
    String table,
    int id,
    String details,
  ) async {
    await txn.update(
      table,
      {'deleted_at': null},
      where: 'id = ?',
      whereArgs: [id],
    );
    await AuditService.log(
      txn,
      table: table,
      rowId: id,
      action: AuditService.restore,
      details: details,
    );
  }

  Future<void> fetchHarvests() async {
    _errorMessage = null;
    try {
      await _fetchHarvests();
    } catch (_) {
      _errorMessage = 'پیداوار کا ریکارڈ لوڈ نہیں ہو سکا۔ دوبارہ کوشش کریں۔';
      notifyListeners();
    }
  }

  Future<void> _fetchHarvests() async {
    final db = await _db();
    // gross/total/net are COMPUTED in the Harvest model now — they are never
    // read from (or written to) the database.
    final String query = '''
      SELECT 
        h.id as h_id, h.crop_season_id, h.quantity as h_qty, h.unit as h_unit, h.date as h_date,
        h.rate_per_unit_paisa, h.transportation_expense_paisa, h.labour_expense_paisa,
        h.harvesting_expense_paisa, h.commission_expense_paisa, h.other_expense_paisa,
        h.buyer_name as h_buyer_name, h.payment_status, h.notes, h.expense_id,
        cs.crop_name, f.name as field_name, f.size_acres as field_size, farm.name as farm_name,
        s.id as s_id, s.buyer_name, s.quantity as s_qty, s.price_per_unit_paisa, s.total_amount_paisa, s.date as s_date
      FROM harvests h
      JOIN crop_seasons cs ON h.crop_season_id = cs.id
      JOIN fields f ON cs.field_id = f.id
      JOIN farms farm ON f.farm_id = farm.id
      LEFT JOIN sales s ON h.id = s.harvest_id AND s.deleted_at IS NULL
      WHERE h.deleted_at IS NULL
      ORDER BY h.id DESC
    ''';

    final List<Map<String, dynamic>> results = await db.rawQuery(query);

    _harvests = List.generate(results.length, (i) {
      final harvest = Harvest(
        id: results[i]['h_id'],
        cropSeasonId: results[i]['crop_season_id'],
        quantity: results[i]['h_qty'],
        unit: results[i]['h_unit'],
        date: results[i]['h_date'],
        ratePerUnitPaisa: (results[i]['rate_per_unit_paisa'] ?? 0) as int,
        transportationExpensePaisa:
            (results[i]['transportation_expense_paisa'] ?? 0) as int,
        labourExpensePaisa: (results[i]['labour_expense_paisa'] ?? 0) as int,
        harvestingExpensePaisa:
            (results[i]['harvesting_expense_paisa'] ?? 0) as int,
        commissionExpensePaisa:
            (results[i]['commission_expense_paisa'] ?? 0) as int,
        otherExpensePaisa: (results[i]['other_expense_paisa'] ?? 0) as int,
        buyerName: results[i]['h_buyer_name'],
        paymentStatus: results[i]['payment_status'] ?? 'Pending',
        notes: results[i]['notes'],
        expenseId: results[i]['expense_id'],
      );

      Sale? sale;
      if (results[i]['s_id'] != null) {
        sale = Sale(
          id: results[i]['s_id'],
          harvestId: results[i]['h_id'],
          buyerName: results[i]['buyer_name'],
          quantity: results[i]['s_qty'],
          pricePerUnitPaisa: results[i]['price_per_unit_paisa'] as int,
          totalAmountPaisa: results[i]['total_amount_paisa'] as int,
          date: results[i]['s_date'],
        );
      }

      return HarvestWithDetails(
        harvest: harvest,
        cropName: results[i]['crop_name'],
        fieldName: results[i]['field_name'],
        fieldSize: results[i]['field_size'],
        farmName: results[i]['farm_name'],
        sale: sale,
      );
    });

    notifyListeners();
  }

  Future<void> addHarvest({
    required int cropSeasonId,
    required double quantity,
    required String unit,
    required String date,
    int ratePerUnitPaisa = 0,
    int transportationExpensePaisa = 0,
    int labourExpensePaisa = 0,
    int harvestingExpensePaisa = 0,
    int commissionExpensePaisa = 0,
    int otherExpensePaisa = 0,
    String? buyerName,
    String paymentStatus = 'Pending',
    String? notes,
  }) async {

    final int totalExpensePaisa = transportationExpensePaisa +
        labourExpensePaisa +
        harvestingExpensePaisa +
        commissionExpensePaisa +
        otherExpensePaisa;
    final int grossPaisa = (quantity * ratePerUnitPaisa).round();

    await _txn((txn) async {
      int? expenseId;
      if (totalExpensePaisa > 0) {
        expenseId = await txn.insert('expenses', {
          'category': 'Harvest Expenses',
          'amount_paisa': totalExpensePaisa,
          'date': date,
          'description': 'کٹائی کے اخراجات برائے فصل',
        });
        await AuditService.log(
          txn,
          table: 'expenses',
          rowId: expenseId,
          action: AuditService.create,
          details:
              'کٹائی کے اخراجات — ${Money(totalExpensePaisa).format()}',
        );
      }

      final harvestId = await txn.insert('harvests', {
        'crop_season_id': cropSeasonId,
        'quantity': quantity,
        'unit': unit,
        'date': date,
        'rate_per_unit_paisa': ratePerUnitPaisa,
        'transportation_expense_paisa': transportationExpensePaisa,
        'labour_expense_paisa': labourExpensePaisa,
        'harvesting_expense_paisa': harvestingExpensePaisa,
        'commission_expense_paisa': commissionExpensePaisa,
        'other_expense_paisa': otherExpensePaisa,
        'buyer_name': buyerName,
        'payment_status': paymentStatus,
        'notes': notes,
        'expense_id': expenseId,
      });
      await AuditService.log(
        txn,
        table: 'harvests',
        rowId: harvestId,
        action: AuditService.create,
        details: 'پیداوار — $quantity $unit',
      );

      if (grossPaisa > 0) {
        final saleId = await txn.insert('sales', {
          'harvest_id': harvestId,
          'buyer_name': buyerName,
          'quantity': quantity,
          'price_per_unit_paisa': ratePerUnitPaisa,
          'total_amount_paisa': grossPaisa,
          'date': date,
        });
        await AuditService.log(
          txn,
          table: 'sales',
          rowId: saleId,
          action: AuditService.create,
          details: 'فروخت — ${Money(grossPaisa).format()}',
        );
      }
    });

    await fetchHarvests();
  }

  Future<void> updateHarvest({
    required int id,
    required int cropSeasonId,
    required double quantity,
    required String unit,
    required String date,
    int ratePerUnitPaisa = 0,
    int transportationExpensePaisa = 0,
    int labourExpensePaisa = 0,
    int harvestingExpensePaisa = 0,
    int commissionExpensePaisa = 0,
    int otherExpensePaisa = 0,
    String? buyerName,
    String paymentStatus = 'Pending',
    String? notes,
  }) async {

    final int totalExpensePaisa = transportationExpensePaisa +
        labourExpensePaisa +
        harvestingExpensePaisa +
        commissionExpensePaisa +
        otherExpensePaisa;
    final int grossPaisa = (quantity * ratePerUnitPaisa).round();

    await _txn((txn) async {
      final List<Map<String, dynamic>> existing = await txn.query(
        'harvests',
        where: 'id = ?',
        whereArgs: [id],
      );
      if (existing.isEmpty) return;

      int? expenseId = existing.first['expense_id'] as int?;

      if (totalExpensePaisa > 0) {
        if (expenseId == null) {
          expenseId = await txn.insert('expenses', {
            'category': 'Harvest Expenses',
            'amount_paisa': totalExpensePaisa,
            'date': date,
            'description': 'کٹائی کے اخراجات برائے فصل',
          });
          await AuditService.log(
            txn,
            table: 'expenses',
            rowId: expenseId,
            action: AuditService.create,
            details:
                'کٹائی کے اخراجات — ${Money(totalExpensePaisa).format()}',
          );
        } else {
          await txn.update(
            'expenses',
            {
              'amount_paisa': totalExpensePaisa,
              'date': date,
            },
            where: 'id = ?',
            whereArgs: [expenseId],
          );
          await AuditService.log(
            txn,
            table: 'expenses',
            rowId: expenseId,
            action: AuditService.update,
            details:
                'کٹائی کے اخراجات — ${Money(totalExpensePaisa).format()}',
          );
        }
      } else {
        if (expenseId != null) {
          await _softDeleteRow(
            txn,
            'expenses',
            expenseId,
            'کٹائی کے اخراجات ختم — ${Money(0).format()}',
          );
          expenseId = null;
        }
      }

      await txn.update(
        'harvests',
        {
          'crop_season_id': cropSeasonId,
          'quantity': quantity,
          'unit': unit,
          'date': date,
          'rate_per_unit_paisa': ratePerUnitPaisa,
          'transportation_expense_paisa': transportationExpensePaisa,
          'labour_expense_paisa': labourExpensePaisa,
          'harvesting_expense_paisa': harvestingExpensePaisa,
          'commission_expense_paisa': commissionExpensePaisa,
          'other_expense_paisa': otherExpensePaisa,
          'buyer_name': buyerName,
          'payment_status': paymentStatus,
          'notes': notes,
          'expense_id': expenseId,
        },
        where: 'id = ?',
        whereArgs: [id],
      );

      final List<Map<String, dynamic>> sales = await txn.query(
        'sales',
        where: 'harvest_id = ? AND deleted_at IS NULL',
        whereArgs: [id],
      );

      if (grossPaisa > 0) {
        if (sales.isEmpty) {
          final saleId = await txn.insert('sales', {
            'harvest_id': id,
            'buyer_name': buyerName,
            'quantity': quantity,
            'price_per_unit_paisa': ratePerUnitPaisa,
            'total_amount_paisa': grossPaisa,
            'date': date,
          });
          await AuditService.log(
            txn,
            table: 'sales',
            rowId: saleId,
            action: AuditService.create,
            details: 'فروخت — ${Money(grossPaisa).format()}',
          );
        } else {
          await txn.update(
            'sales',
            {
              'buyer_name': buyerName,
              'quantity': quantity,
              'price_per_unit_paisa': ratePerUnitPaisa,
              'total_amount_paisa': grossPaisa,
              'date': date,
            },
            where: 'harvest_id = ?',
            whereArgs: [id],
          );
          await AuditService.log(
            txn,
            table: 'sales',
            rowId: (sales.first['id'] as num).toInt(),
            action: AuditService.update,
            details: 'فروخت — ${Money(grossPaisa).format()}',
          );
        }
      } else {
        for (final s in sales) {
          await _softDeleteRow(
            txn,
            'sales',
            (s['id'] as num).toInt(),
            'فروخت ختم — ${Money((s['total_amount_paisa'] as num).toInt()).format()}',
          );
        }
      }

      await AuditService.log(
        txn,
        table: 'harvests',
        rowId: id,
        action: AuditService.update,
        details: 'پیداوار — $quantity $unit',
      );
    });

    await fetchHarvests();
  }

  Future<void> recordSale({
    required int harvestId,
    required double quantity,
    required int pricePerUnitPaisa,
    required String date,
    String? buyerName,
  }) async {
    await _txn((txn) async {
      final List<Map<String, dynamic>> hMaps = await txn
          .query('harvests', where: 'id = ?', whereArgs: [harvestId]);
      if (hMaps.isEmpty) return;

      // The sale total is ALWAYS recomputed from quantity x price (rounded to
      // the paisa) — never taken from a caller-supplied total, so the sale
      // and the harvest's rate can never disagree.
      final int grossPaisa = (quantity * pricePerUnitPaisa).round();

      await txn.update(
        'harvests',
        {
          'rate_per_unit_paisa': pricePerUnitPaisa,
          'buyer_name': buyerName,
          'payment_status': 'Paid',
        },
        where: 'id = ?',
        whereArgs: [harvestId],
      );

      final List<Map<String, dynamic>> sMaps = await txn
          .query('sales', where: 'harvest_id = ? AND deleted_at IS NULL', whereArgs: [harvestId]);
      if (sMaps.isEmpty) {
        final saleId = await txn.insert('sales', {
          'harvest_id': harvestId,
          'buyer_name': buyerName,
          'quantity': quantity,
          'price_per_unit_paisa': pricePerUnitPaisa,
          'total_amount_paisa': grossPaisa,
          'date': date,
        });
        await AuditService.log(
          txn,
          table: 'sales',
          rowId: saleId,
          action: AuditService.create,
          details: 'فروخت — ${Money(grossPaisa).format()}',
        );
      } else {
        await txn.update(
          'sales',
          {
            'buyer_name': buyerName,
            'quantity': quantity,
            'price_per_unit_paisa': pricePerUnitPaisa,
            'total_amount_paisa': grossPaisa,
            'date': date,
          },
          where: 'harvest_id = ?',
          whereArgs: [harvestId],
        );
        await AuditService.log(
          txn,
          table: 'sales',
          rowId: (sMaps.first['id'] as num).toInt(),
          action: AuditService.update,
          details: 'فروخت — ${Money(grossPaisa).format()}',
        );
      }
      await AuditService.log(
        txn,
        table: 'harvests',
        rowId: harvestId,
        action: AuditService.update,
        details: 'فروخت درج — ${Money(grossPaisa).format()}',
      );
    });
    await fetchHarvests();
  }

  /// Soft delete: the harvest, its sales and its linked harvest-expense are
  /// hidden everywhere but kept for history and the recycle bin.
  Future<void> deleteHarvest(int id) async {
    await _txn((txn) async {
      final List<Map<String, dynamic>> existing = await txn.query(
        'harvests',
        where: 'id = ?',
        whereArgs: [id],
      );
      if (existing.isEmpty) return;
      final row = existing.first;
      final int? expenseId = row['expense_id'] as int?;
      if (expenseId != null) {
        await _softDeleteRow(
          txn,
          'expenses',
          expenseId,
          'کٹائی کے اخراجات (پیداوار حذف)',
        );
      }

      final sales = await txn.query(
        'sales',
        where: 'harvest_id = ? AND deleted_at IS NULL',
        whereArgs: [id],
      );
      for (final s in sales) {
        await _softDeleteRow(
          txn,
          'sales',
          (s['id'] as num).toInt(),
          'فروخت (پیداوار حذف)',
        );
      }
      await _softDeleteRow(
        txn,
        'harvests',
        id,
        'پیداوار — ${row['quantity']} ${row['unit']}',
      );
    });
    await fetchHarvests();
  }

  /// Soft delete of one sale; the parent harvest is reset so the sale can
  /// be re-recorded.
  Future<void> deleteSale(int id) async {
    await _txn((txn) async {
      final List<Map<String, dynamic>> sMaps = await txn.query(
        'sales',
        where: 'id = ?',
        whereArgs: [id],
      );
      final int? harvestId =
          sMaps.isEmpty ? null : sMaps.first['harvest_id'] as int?;

      await _softDeleteRow(
        txn,
        'sales',
        id,
        sMaps.isEmpty
            ? 'فروخت حذف'
            : 'فروخت — ${Money((sMaps.first['total_amount_paisa'] as num).toInt()).format()}',
      );

      // Reset the parent harvest so the sale can be re-recorded instead of
      // leaving a stale rate, buyer and payment status behind. gross/net are
      // computed from the rate, so resetting the rate to 0 resets them too.
      if (harvestId != null) {
        await txn.update(
          'harvests',
          {
            'rate_per_unit_paisa': 0,
            'buyer_name': null,
            'payment_status': 'Pending',
          },
          where: 'id = ?',
          whereArgs: [harvestId],
        );
        await AuditService.log(
          txn,
          table: 'harvests',
          rowId: harvestId,
          action: AuditService.update,
          details: 'فروخت حذف پر ری سیٹ',
        );
      }
    });
    await fetchHarvests();
  }

  Future<void> updateSale({
    required int id,
    required int harvestId,
    required double quantity,
    required int pricePerUnitPaisa,
    required String date,
    String? buyerName,
  }) async {
    await _txn((txn) async {
      // Same rule as recordSale: the total is recomputed, never accepted
      // from the caller.
      final int totalPaisa = (quantity * pricePerUnitPaisa).round();

      await txn.update(
        'sales',
        {
          'harvest_id': harvestId,
          'quantity': quantity,
          'price_per_unit_paisa': pricePerUnitPaisa,
          'total_amount_paisa': totalPaisa,
          'date': date,
          'buyer_name': buyerName,
        },
        where: 'id = ?',
        whereArgs: [id],
      );

      // Keep the parent harvest in sync with the edited sale: the harvest's
      // rate mirrors the sale's price; gross/net are computed from it, so
      // the two can never disagree.
      await txn.update(
        'harvests',
        {
          'rate_per_unit_paisa': pricePerUnitPaisa,
          'buyer_name': buyerName,
        },
        where: 'id = ?',
        whereArgs: [harvestId],
      );
      await AuditService.log(
        txn,
        table: 'sales',
        rowId: id,
        action: AuditService.update,
        details: 'فروخت — ${Money(totalPaisa).format()}',
      );
    });
    await fetchHarvests();
  }

  /// Restores a soft-deleted harvest (recycle bin only). Its sales and
  /// linked expense stay deleted — they are restored individually, so a
  /// farmer never accidentally resurrects a whole subtree.
  Future<void> restoreHarvest(int id) async {
    await _txn((txn) async {
      await _restoreRow(txn, 'harvests', id, 'پیداوار بحال');
    });
    await fetchHarvests();
  }

  /// Restores a soft-deleted sale (recycle bin only).
  Future<void> restoreSale(int id) async {
    await _txn((txn) async {
      await _restoreRow(txn, 'sales', id, 'فروخت بحال');
    });
    await fetchHarvests();
  }

  /// Permanent delete of a harvest and its subtree — recycle bin only,
  /// with the caller's destructive confirmation. The audit log keeps the
  /// record.
  Future<void> permanentDeleteHarvest(int id) async {
    await _txn((txn) async {
      final existing = await txn.query(
        'harvests',
        where: 'id = ?',
        whereArgs: [id],
      );
      final int? expenseId = existing.isEmpty
          ? null
          : existing.first['expense_id'] as int?;
      if (expenseId != null) {
        await txn.delete('expenses', where: 'id = ?', whereArgs: [expenseId]);
      }
      await txn.delete('sales', where: 'harvest_id = ?', whereArgs: [id]);
      await txn.delete('harvests', where: 'id = ?', whereArgs: [id]);
      await AuditService.log(
        txn,
        table: 'harvests',
        rowId: id,
        action: AuditService.permanentDelete,
        details: 'پیداوار مستقل حذف',
      );
    });
    await fetchHarvests();
  }

  /// Permanent delete of a sale — recycle bin only.
  Future<void> permanentDeleteSale(int id) async {
    await _txn((txn) async {
      await txn.delete('sales', where: 'id = ?', whereArgs: [id]);
      await AuditService.log(
        txn,
        table: 'sales',
        rowId: id,
        action: AuditService.permanentDelete,
        details: 'فروخت مستقل حذف',
      );
    });
    await fetchHarvests();
  }
}
