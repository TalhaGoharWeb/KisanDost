import 'package:flutter/material.dart';
import '../database/db_helper.dart';
import '../models/models.dart';

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
  List<HarvestWithDetails> _harvests = [];
  final List<Sale> _sales = [];

  List<HarvestWithDetails> get harvests => _harvests;
  List<Sale> get sales => _sales;

  Future<void> fetchHarvests() async {
    final db = await DatabaseHelper.instance.database;
    final String query = '''
      SELECT 
        h.id as h_id, h.crop_season_id, h.quantity as h_qty, h.unit as h_unit, h.date as h_date,
        h.rate_per_unit, h.gross_amount, h.transportation_expense, h.labour_expense,
        h.harvesting_expense, h.commission_expense, h.other_expense, h.total_expense,
        h.net_income, h.buyer_name as h_buyer_name, h.payment_status, h.notes, h.expense_id,
        cs.crop_name, f.name as field_name, f.size_acres as field_size, farm.name as farm_name,
        s.id as s_id, s.buyer_name, s.quantity as s_qty, s.price_per_unit, s.total_amount, s.date as s_date
      FROM harvests h
      JOIN crop_seasons cs ON h.crop_season_id = cs.id
      JOIN fields f ON cs.field_id = f.id
      JOIN farms farm ON f.farm_id = farm.id
      LEFT JOIN sales s ON h.id = s.harvest_id
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
        ratePerUnit: (results[i]['rate_per_unit'] ?? 0.0 as num).toDouble(),
        grossAmount: (results[i]['gross_amount'] ?? 0.0 as num).toDouble(),
        transportationExpense: (results[i]['transportation_expense'] ?? 0.0 as num).toDouble(),
        labourExpense: (results[i]['labour_expense'] ?? 0.0 as num).toDouble(),
        harvestingExpense: (results[i]['harvesting_expense'] ?? 0.0 as num).toDouble(),
        commissionExpense: (results[i]['commission_expense'] ?? 0.0 as num).toDouble(),
        otherExpense: (results[i]['other_expense'] ?? 0.0 as num).toDouble(),
        totalExpense: (results[i]['total_expense'] ?? 0.0 as num).toDouble(),
        netIncome: (results[i]['net_income'] ?? 0.0 as num).toDouble(),
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
          pricePerUnit: results[i]['price_per_unit'],
          totalAmount: results[i]['total_amount'],
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
    double ratePerUnit = 0.0,
    double transportationExpense = 0.0,
    double labourExpense = 0.0,
    double harvestingExpense = 0.0,
    double commissionExpense = 0.0,
    double otherExpense = 0.0,
    String? buyerName,
    String paymentStatus = 'Pending',
    String? notes,
  }) async {
    final db = await DatabaseHelper.instance.database;

    final double grossAmount = quantity * ratePerUnit;
    final double totalExpense = transportationExpense + labourExpense + harvestingExpense + commissionExpense + otherExpense;
    final double netIncome = grossAmount - totalExpense;

    await db.transaction((txn) async {
      int? expenseId;
      if (totalExpense > 0) {
        expenseId = await txn.insert('expenses', {
          'category': 'Harvest Expenses',
          'amount': totalExpense,
          'date': date,
          'description': 'کٹائی کے اخراجات برائے فصل',
        });
      }

      final harvestId = await txn.insert('harvests', {
        'crop_season_id': cropSeasonId,
        'quantity': quantity,
        'unit': unit,
        'date': date,
        'rate_per_unit': ratePerUnit,
        'gross_amount': grossAmount,
        'transportation_expense': transportationExpense,
        'labour_expense': labourExpense,
        'harvesting_expense': harvestingExpense,
        'commission_expense': commissionExpense,
        'other_expense': otherExpense,
        'total_expense': totalExpense,
        'net_income': netIncome,
        'buyer_name': buyerName,
        'payment_status': paymentStatus,
        'notes': notes,
        'expense_id': expenseId,
      });

      if (grossAmount > 0) {
        await txn.insert('sales', {
          'harvest_id': harvestId,
          'buyer_name': buyerName,
          'quantity': quantity,
          'price_per_unit': ratePerUnit,
          'total_amount': grossAmount,
          'date': date,
        });
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
    double ratePerUnit = 0.0,
    double transportationExpense = 0.0,
    double labourExpense = 0.0,
    double harvestingExpense = 0.0,
    double commissionExpense = 0.0,
    double otherExpense = 0.0,
    String? buyerName,
    String paymentStatus = 'Pending',
    String? notes,
  }) async {
    final db = await DatabaseHelper.instance.database;

    final double grossAmount = quantity * ratePerUnit;
    final double totalExpense = transportationExpense + labourExpense + harvestingExpense + commissionExpense + otherExpense;
    final double netIncome = grossAmount - totalExpense;

    await db.transaction((txn) async {
      final List<Map<String, dynamic>> existing = await txn.query(
        'harvests',
        where: 'id = ?',
        whereArgs: [id],
      );
      if (existing.isEmpty) return;
      
      int? expenseId = existing.first['expense_id'] as int?;

      if (totalExpense > 0) {
        if (expenseId == null) {
          expenseId = await txn.insert('expenses', {
            'category': 'Harvest Expenses',
            'amount': totalExpense,
            'date': date,
            'description': 'کٹائی کے اخراجات برائے فصل',
          });
        } else {
          await txn.update(
            'expenses',
            {
              'amount': totalExpense,
              'date': date,
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
        'harvests',
        {
          'crop_season_id': cropSeasonId,
          'quantity': quantity,
          'unit': unit,
          'date': date,
          'rate_per_unit': ratePerUnit,
          'gross_amount': grossAmount,
          'transportation_expense': transportationExpense,
          'labour_expense': labourExpense,
          'harvesting_expense': harvestingExpense,
          'commission_expense': commissionExpense,
          'other_expense': otherExpense,
          'total_expense': totalExpense,
          'net_income': netIncome,
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
        where: 'harvest_id = ?',
        whereArgs: [id],
      );

      if (grossAmount > 0) {
        if (sales.isEmpty) {
          await txn.insert('sales', {
            'harvest_id': id,
            'buyer_name': buyerName,
            'quantity': quantity,
            'price_per_unit': ratePerUnit,
            'total_amount': grossAmount,
            'date': date,
          });
        } else {
          await txn.update(
            'sales',
            {
              'buyer_name': buyerName,
              'quantity': quantity,
              'price_per_unit': ratePerUnit,
              'total_amount': grossAmount,
              'date': date,
            },
            where: 'harvest_id = ?',
            whereArgs: [id],
          );
        }
      } else {
        if (sales.isNotEmpty) {
          await txn.delete('sales', where: 'harvest_id = ?', whereArgs: [id]);
        }
      }
    });

    await fetchHarvests();
  }

  Future<void> recordSale({
    required int harvestId,
    required double quantity,
    required double pricePerUnit,
    required double totalAmount,
    required String date,
    String? buyerName,
  }) async {
    final db = await DatabaseHelper.instance.database;
    await db.transaction((txn) async {
      final List<Map<String, dynamic>> hMaps = await txn.query('harvests', where: 'id = ?', whereArgs: [harvestId]);
      if (hMaps.isEmpty) return;
      final current = Harvest.fromMap(hMaps.first);

      final double grossAmount = quantity * pricePerUnit;
      final double netIncome = grossAmount - current.totalExpense;

      await txn.update(
        'harvests',
        {
          'rate_per_unit': pricePerUnit,
          'gross_amount': grossAmount,
          'net_income': netIncome,
          'buyer_name': buyerName,
          'payment_status': 'Paid',
        },
        where: 'id = ?',
        whereArgs: [harvestId],
      );

      final List<Map<String, dynamic>> sMaps = await txn.query('sales', where: 'harvest_id = ?', whereArgs: [harvestId]);
      if (sMaps.isEmpty) {
        await txn.insert('sales', {
          'harvest_id': harvestId,
          'buyer_name': buyerName,
          'quantity': quantity,
          'price_per_unit': pricePerUnit,
          'total_amount': grossAmount,
          'date': date,
        });
      } else {
        await txn.update(
          'sales',
          {
            'buyer_name': buyerName,
            'quantity': quantity,
            'price_per_unit': pricePerUnit,
            'total_amount': grossAmount,
            'date': date,
          },
          where: 'harvest_id = ?',
          whereArgs: [harvestId],
        );
      }
    });
    await fetchHarvests();
  }

  Future<void> deleteHarvest(int id) async {
    final db = await DatabaseHelper.instance.database;
    await db.transaction((txn) async {
      final List<Map<String, dynamic>> existing = await txn.query(
        'harvests',
        where: 'id = ?',
        whereArgs: [id],
      );
      if (existing.isNotEmpty) {
        final int? expenseId = existing.first['expense_id'] as int?;
        if (expenseId != null) {
          await txn.delete('expenses', where: 'id = ?', whereArgs: [expenseId]);
        }
      }
      
      await txn.delete('sales', where: 'harvest_id = ?', whereArgs: [id]);
      await txn.delete('harvests', where: 'id = ?', whereArgs: [id]);
    });
    await fetchHarvests();
  }

  Future<void> deleteSale(int id) async {
    final db = await DatabaseHelper.instance.database;
    await db.delete(
      'sales',
      where: 'id = ?',
      whereArgs: [id],
    );
    await fetchHarvests();
  }

  Future<void> updateSale({
    required int id,
    required int harvestId,
    required double quantity,
    required double pricePerUnit,
    required double totalAmount,
    required String date,
    String? buyerName,
  }) async {
    final db = await DatabaseHelper.instance.database;
    await db.update(
      'sales',
      {
        'harvest_id': harvestId,
        'quantity': quantity,
        'price_per_unit': pricePerUnit,
        'total_amount': totalAmount,
        'date': date,
        'buyer_name': buyerName,
      },
      where: 'id = ?',
      whereArgs: [id],
    );
    await fetchHarvests();
  }
}
