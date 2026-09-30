import 'package:flutter/material.dart';
import '../database/db_helper.dart';
import '../models/models.dart';
import 'inventory_provider.dart';

class ActivityWithDetails {
  final Activity activity;
  final String cropName;
  final List<String> fieldNames;
  final double? expenseAmount;

  ActivityWithDetails({
    required this.activity,
    required this.cropName,
    required this.fieldNames,
    this.expenseAmount,
  });

  String get fieldDisplayName {
    if (fieldNames.isEmpty) {
      return '';
    }
    if (fieldNames.length == 1) {
      return fieldNames.first;
    }
    return '${fieldNames.length} کھیت';
  }
}

class ActivityProvider extends ChangeNotifier {
  List<ActivityWithDetails> _activities = [];

  List<ActivityWithDetails> get activities => _activities;

  Future<void> fetchActivities() async {
    final db = await DatabaseHelper.instance.database;
    final String query = '''
      SELECT
        a.id as a_id,
        a.crop_season_id,
        a.activity_type,
        a.date as a_date,
        a.details,
        a.expense_id,
        a.expense_category,
        a.inventory_category,
        a.inventory_name,
        a.inventory_unit,
        a.inventory_quantity,
        a.is_completed,
        cs.crop_name,
        e.amount as expense_amount
      FROM activities a
      JOIN crop_seasons cs ON a.crop_season_id = cs.id
      LEFT JOIN expenses e ON a.expense_id = e.id
      ORDER BY a.date DESC, a.id DESC
    ''';

    final List<Map<String, dynamic>> results = await db.rawQuery(query);

    final List<Map<String, dynamic>> mappingRows = await db.rawQuery('''
      SELECT
        csf.crop_season_id,
        f.name as field_name
      FROM crop_season_fields csf
      JOIN fields f ON csf.field_id = f.id
    ''');

    final Map<int, List<String>> seasonFields = {};
    for (final row in mappingRows) {
      final int seasonId = row['crop_season_id'] as int;
      seasonFields.putIfAbsent(seasonId, () => []).add(row['field_name'] as String);
    }

    _activities = List.generate(results.length, (i) {
      final activity = Activity(
        id: results[i]['a_id'],
        cropSeasonId: results[i]['crop_season_id'],
        activityType: results[i]['activity_type'],
        date: results[i]['a_date'],
        details: results[i]['details'],
        expenseId: results[i]['expense_id'],
        expenseCategory: results[i]['expense_category'],
        inventoryCategory: results[i]['inventory_category'],
        inventoryName: results[i]['inventory_name'],
        inventoryUnit: results[i]['inventory_unit'],
        inventoryQuantity: results[i]['inventory_quantity'] == null
            ? null
            : (results[i]['inventory_quantity'] as num).toDouble(),
        isCompleted: (results[i]['is_completed'] ?? 0) == 1,
      );
      return ActivityWithDetails(
        activity: activity,
        cropName: results[i]['crop_name'],
        fieldNames: seasonFields[activity.cropSeasonId] ?? [],
        expenseAmount: results[i]['expense_amount'] == null
            ? null
            : (results[i]['expense_amount'] as num).toDouble(),
      );
    });

    notifyListeners();
  }

  Future<void> _applyInventoryDelta({
    required InventoryProvider inventoryProvider,
    required String category,
    required String name,
    required String unit,
    required double quantity,
    required bool deduct,
  }) async {
    Inventory? target;
    for (final item in inventoryProvider.inventoryList) {
      if (item.category == category && item.name == name) {
        target = item;
        break;
      }
    }

    if (target == null) {
      if (deduct) {
        return;
      }
      await inventoryProvider.addInventoryItem(
        category: category,
        name: name,
        unit: unit,
        quantity: quantity,
        costPerUnit: 0,
      );
      return;
    }

    final double convertedQty = _convertUnit(quantity, unit, target.unit);
    final double newQty = deduct
        ? (target.quantity - convertedQty).clamp(0.0, double.infinity)
        : target.quantity + convertedQty;

    await inventoryProvider.updateInventoryItem(
      id: target.id!,
      category: target.category,
      name: target.name,
      unit: target.unit,
      quantity: newQty,
      costPerUnit: target.costPerUnit,
    );
  }

  Future<void> addActivity({
    required int cropSeasonId,
    required String activityType,
    required String date,
    required String details,
    double? expenseAmount,
    String? expenseCategory,
    int? expenseId,
    String? inventoryCategory,
    String? inventoryName,
    String? inventoryUnit,
    double? inventoryQuantity,
    bool isCompleted = false,
    InventoryProvider? inventoryProvider,
  }) async {
    final db = await DatabaseHelper.instance.database;
    int? finalExpenseId = expenseId;

    if (finalExpenseId == null && expenseAmount != null && expenseAmount > 0) {
      final newExpense = Expense(
        category: expenseCategory ?? 'Other',
        amount: expenseAmount,
        date: date,
        description: '$activityType: $details',
      );
      finalExpenseId = await db.insert('expenses', newExpense.toMap());
    }

    if (inventoryProvider != null &&
        inventoryCategory != null &&
        inventoryName != null &&
        inventoryUnit != null &&
        inventoryQuantity != null &&
        inventoryQuantity > 0) {
      await _applyInventoryDelta(
        inventoryProvider: inventoryProvider,
        category: inventoryCategory,
        name: inventoryName,
        unit: inventoryUnit,
        quantity: inventoryQuantity,
        deduct: true,
      );
    }

    final newActivity = Activity(
      cropSeasonId: cropSeasonId,
      activityType: activityType,
      date: date,
      details: details,
      expenseId: finalExpenseId,
      expenseCategory: expenseCategory,
      inventoryCategory: inventoryCategory,
      inventoryName: inventoryName,
      inventoryUnit: inventoryUnit,
      inventoryQuantity: inventoryQuantity,
      isCompleted: isCompleted,
    );
    await db.insert('activities', newActivity.toMap());

    await fetchActivities();
  }

  Future<Activity?> getActivityById(int id) async {
    final db = await DatabaseHelper.instance.database;
    final maps = await db.query('activities', where: 'id = ?', whereArgs: [id]);
    if (maps.isEmpty) {
      return null;
    }
    return Activity.fromMap(maps.first);
  }

  Future<void> updateActivity({
    required int id,
    required int cropSeasonId,
    required String activityType,
    required String date,
    required String details,
    double? expenseAmount,
    String? expenseCategory,
    String? inventoryCategory,
    String? inventoryName,
    String? inventoryUnit,
    double? inventoryQuantity,
    bool? isCompleted,
    InventoryProvider? inventoryProvider,
  }) async {
    final db = await DatabaseHelper.instance.database;

    final Activity? oldActivity = await getActivityById(id);
    if (oldActivity == null) {
      return;
    }

    if (inventoryProvider != null &&
        oldActivity.inventoryCategory != null &&
        oldActivity.inventoryName != null &&
        oldActivity.inventoryUnit != null &&
        oldActivity.inventoryQuantity != null &&
        oldActivity.inventoryQuantity! > 0) {
      await _applyInventoryDelta(
        inventoryProvider: inventoryProvider,
        category: oldActivity.inventoryCategory!,
        name: oldActivity.inventoryName!,
        unit: oldActivity.inventoryUnit!,
        quantity: oldActivity.inventoryQuantity!,
        deduct: false,
      );
    }

    int? finalExpenseId = oldActivity.expenseId;
    if (expenseAmount != null && expenseAmount > 0) {
      if (finalExpenseId == null) {
        finalExpenseId = await db.insert(
          'expenses',
          Expense(
            category: expenseCategory ?? 'Other',
            amount: expenseAmount,
            date: date,
            description: '$activityType: $details',
          ).toMap(),
        );
      } else {
        await db.update(
          'expenses',
          {
            'category': expenseCategory ?? 'Other',
            'amount': expenseAmount,
            'date': date,
            'description': '$activityType: $details',
          },
          where: 'id = ?',
          whereArgs: [finalExpenseId],
        );
      }
    } else if (finalExpenseId != null) {
      await db.delete('expenses', where: 'id = ?', whereArgs: [finalExpenseId]);
      finalExpenseId = null;
    }

    if (inventoryProvider != null &&
        inventoryCategory != null &&
        inventoryName != null &&
        inventoryUnit != null &&
        inventoryQuantity != null &&
        inventoryQuantity > 0) {
      await _applyInventoryDelta(
        inventoryProvider: inventoryProvider,
        category: inventoryCategory,
        name: inventoryName,
        unit: inventoryUnit,
        quantity: inventoryQuantity,
        deduct: true,
      );
    }

    await db.update(
      'activities',
      {
        'crop_season_id': cropSeasonId,
        'activity_type': activityType,
        'date': date,
        'details': details,
        'expense_id': finalExpenseId,
        'expense_category': expenseCategory,
        'inventory_category': inventoryCategory,
        'inventory_name': inventoryName,
        'inventory_unit': inventoryUnit,
        'inventory_quantity': inventoryQuantity,
        'is_completed': isCompleted == null
            ? (oldActivity.isCompleted ? 1 : 0)
            : (isCompleted ? 1 : 0),
      },
      where: 'id = ?',
      whereArgs: [id],
    );

    await fetchActivities();
  }

  Future<void> toggleCompleted(int id, bool completed) async {
    final db = await DatabaseHelper.instance.database;
    await db.update(
      'activities',
      {'is_completed': completed ? 1 : 0},
      where: 'id = ?',
      whereArgs: [id],
    );
    await fetchActivities();
  }

  Future<void> duplicateActivity(int id) async {
    final Activity? activity = await getActivityById(id);
    if (activity == null) {
      return;
    }

    await addActivity(
      cropSeasonId: activity.cropSeasonId,
      activityType: activity.activityType,
      date: DateTime.now().toIso8601String(),
      details: activity.details ?? '',
      expenseAmount: null,
      expenseCategory: activity.expenseCategory,
      inventoryCategory: activity.inventoryCategory,
      inventoryName: activity.inventoryName,
      inventoryUnit: activity.inventoryUnit,
      inventoryQuantity: null,
      isCompleted: false,
    );
  }

  Future<void> deleteActivity(int id, {InventoryProvider? inventoryProvider}) async {
    final db = await DatabaseHelper.instance.database;

    final Activity? activity = await getActivityById(id);
    if (activity == null) {
      return;
    }

    if (inventoryProvider != null &&
        activity.inventoryCategory != null &&
        activity.inventoryName != null &&
        activity.inventoryUnit != null &&
        activity.inventoryQuantity != null &&
        activity.inventoryQuantity! > 0) {
      await _applyInventoryDelta(
        inventoryProvider: inventoryProvider,
        category: activity.inventoryCategory!,
        name: activity.inventoryName!,
        unit: activity.inventoryUnit!,
        quantity: activity.inventoryQuantity!,
        deduct: false,
      );
    }

    await db.delete(
      'activities',
      where: 'id = ?',
      whereArgs: [id],
    );

    if (activity.expenseId != null) {
      await db.delete(
        'expenses',
        where: 'id = ?',
        whereArgs: [activity.expenseId],
      );
    }

    await fetchActivities();
  }

  double _convertUnit(double quantity, String fromUnit, String toUnit) {
    if (fromUnit == toUnit) {
      return quantity;
    }

    String standardize(String u) {
      if (u == 'KG' || u == 'کلوگرام' || u == 'کلو') return 'kg';
      if (u == 'Gram' || u == 'گرام') return 'g';
      if (u == 'Bag' || u == 'بوری') return 'bag';
      if (u == 'Litre' || u == 'لیٹر') return 'l';
      if (u == 'ML' || u == 'ملی لیٹر' || u == 'ملی') return 'ml';
      if (u == 'Ton' || u == 'ٹن') return 'ton';
      return u.toLowerCase();
    }

    final String from = standardize(fromUnit);
    final String to = standardize(toUnit);

    final Map<String, double> weightInKg = {
      'kg': 1.0,
      'g': 0.001,
      'bag': 50.0,
      'ton': 1000.0,
    };

    final Map<String, double> volumeInLitre = {
      'l': 1.0,
      'ml': 0.001,
    };

    if (weightInKg.containsKey(from) && weightInKg.containsKey(to)) {
      final double quantityInKg = quantity * weightInKg[from]!;
      return quantityInKg / weightInKg[to]!;
    }

    if (volumeInLitre.containsKey(from) && volumeInLitre.containsKey(to)) {
      final double quantityInLitre = quantity * volumeInLitre[from]!;
      return quantityInLitre / volumeInLitre[to]!;
    }

    return quantity;
  }
}
