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
    final db = await DatabaseHelper.instance.database;

    final int totalExpensePaisa = transportationExpensePaisa +
        labourExpensePaisa +
        harvestingExpensePaisa +
        commissionExpensePaisa +
        otherExpensePaisa;
    final int grossPaisa = (quantity * ratePerUnitPaisa).round();

    await db.transaction((txn) async {
      int? expenseId;
      if (totalExpensePaisa > 0) {
        expenseId = await txn.insert('expenses', {
          'category': 'Harvest Expenses',
          'amount_paisa': totalExpensePaisa,
          'date': date,
          'description': 'کٹائی کے اخراجات برائے فصل',
        });
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

      if (grossPaisa > 0) {
        await txn.insert('sales', {
          'harvest_id': harvestId,
          'buyer_name': buyerName,
          'quantity': quantity,
          'price_per_unit_paisa': ratePerUnitPaisa,
          'total_amount_paisa': grossPaisa,
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
    final db = await DatabaseHelper.instance.database;

    final int totalExpensePaisa = transportationExpensePaisa +
        labourExpensePaisa +
        harvestingExpensePaisa +
        commissionExpensePaisa +
        otherExpensePaisa;
    final int grossPaisa = (quantity * ratePerUnitPaisa).round();

    await db.transaction((txn) async {
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
        where: 'harvest_id = ?',
        whereArgs: [id],
      );

      if (grossPaisa > 0) {
        if (sales.isEmpty) {
          await txn.insert('sales', {
            'harvest_id': id,
            'buyer_name': buyerName,
            'quantity': quantity,
            'price_per_unit_paisa': ratePerUnitPaisa,
            'total_amount_paisa': grossPaisa,
            'date': date,
          });
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
    required int pricePerUnitPaisa,
    required String date,
    String? buyerName,
  }) async {
    final db = await DatabaseHelper.instance.database;
    await db.transaction((txn) async {
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
          .query('sales', where: 'harvest_id = ?', whereArgs: [harvestId]);
      if (sMaps.isEmpty) {
        await txn.insert('sales', {
          'harvest_id': harvestId,
          'buyer_name': buyerName,
          'quantity': quantity,
          'price_per_unit_paisa': pricePerUnitPaisa,
          'total_amount_paisa': grossPaisa,
          'date': date,
        });
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
    await db.transaction((txn) async {
      final List<Map<String, dynamic>> sMaps = await txn.query(
        'sales',
        where: 'id = ?',
        whereArgs: [id],
      );
      final int? harvestId =
          sMaps.isEmpty ? null : sMaps.first['harvest_id'] as int?;

      await txn.delete(
        'sales',
        where: 'id = ?',
        whereArgs: [id],
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
    final db = await DatabaseHelper.instance.database;
    await db.transaction((txn) async {
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
    });
    await fetchHarvests();
  }
}
