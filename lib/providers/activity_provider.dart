import 'package:flutter/material.dart';
import 'package:sqflite/sqflite.dart';
import '../database/db_helper.dart';
import '../models/models.dart';
import '../utils/agricultural_units.dart';
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
        a.inventory_purchased_and_used,
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
      seasonFields
          .putIfAbsent(seasonId, () => [])
          .add(row['field_name'] as String);
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
        inventoryQuantity:
            results[i]['inventory_quantity'] == null
                ? null
                : (results[i]['inventory_quantity'] as num).toDouble(),
        inventoryPurchasedAndUsed:
            (results[i]['inventory_purchased_and_used'] ?? 0) == 1,
        isCompleted: (results[i]['is_completed'] ?? 0) == 1,
      );
      return ActivityWithDetails(
        activity: activity,
        cropName: results[i]['crop_name'],
        fieldNames: seasonFields[activity.cropSeasonId] ?? [],
        expenseAmount:
            results[i]['expense_amount'] == null
                ? null
                : (results[i]['expense_amount'] as num).toDouble(),
      );
    });

    notifyListeners();
  }

  Future<void> _applyInventoryDelta({
    required Transaction txn,
    required String category,
    required String name,
    required String unit,
    required double quantity,
    required bool deduct,
    required int activityId,
    required String activityDate,
  }) async {
    if (!quantity.isFinite || quantity <= 0) {
      throw ArgumentError.value(
        quantity,
        'quantity',
        'Must be a finite positive number',
      );
    }

    final matches = await txn.query(
      'inventory',
      where: 'category = ? AND name = ?',
      whereArgs: [category, name],
      orderBy: 'id ASC',
    );
    if (matches.isEmpty) {
      if (deduct) {
        throw StateError('اس چیز کا اسٹاک گودام میں موجود نہیں ہے: $name');
      }
      // Preserve stock when restoring an activity whose item was removed.
      final inventoryId = await txn.insert('inventory', {
        'category': category,
        'name': name,
        'unit': unit,
        'quantity': quantity,
        'cost_per_unit': 0.0,
      });
      await _recordInventoryMovement(
        txn,
        inventoryId: inventoryId,
        movementType: 'reversal',
        category: category,
        itemName: name,
        quantityDelta: quantity,
        unit: unit,
        unitCost: 0.0,
        activityId: activityId,
        activityDate: activityDate,
        notes: 'سرگرمی سے اسٹاک واپس کیا گیا',
      );
      return;
    }

    final exactMatches = matches.where((row) => row['unit'] == unit).toList();
    final Map<String, dynamic> targetRow;
    if (exactMatches.length == 1) {
      targetRow = exactMatches.single;
    } else if (exactMatches.length > 1 || matches.length > 1) {
      throw StateError(
        'اس نام کے ایک سے زیادہ یونٹ والے اسٹاک موجود ہیں: $name',
      );
    } else {
      targetRow = matches.single;
    }

    final target = Inventory.fromMap(targetRow);
    final convertedQty = AgriculturalUnits.convert(quantity, unit, target.unit);
    final newQty =
        deduct
            ? target.quantity - convertedQty
            : target.quantity + convertedQty;
    if (deduct && convertedQty > target.quantity + 1e-9) {
      throw StateError(
        'گودام میں $name کا اسٹاک ناکافی ہے۔ موجود: ${target.quantity} ${target.unit}',
      );
    }

    await txn.update(
      'inventory',
      {'quantity': newQty < 1e-9 ? 0.0 : newQty},
      where: 'id = ?',
      whereArgs: [target.id],
    );
    await _recordInventoryMovement(
      txn,
      inventoryId: target.id!,
      movementType: deduct ? 'usage' : 'reversal',
      category: target.category,
      itemName: target.name,
      quantityDelta: deduct ? -convertedQty : convertedQty,
      unit: target.unit,
      unitCost: target.costPerUnit,
      activityId: activityId,
      activityDate: activityDate,
      notes: deduct ? 'سرگرمی میں استعمال' : 'سرگرمی سے اسٹاک واپس کیا گیا',
    );
  }

  Future<void> _recordInventoryMovement(
    Transaction txn, {
    required int inventoryId,
    required String movementType,
    required String category,
    required String itemName,
    required double quantityDelta,
    required String unit,
    required double unitCost,
    required int activityId,
    required String activityDate,
    required String notes,
  }) async {
    await txn.insert('inventory_transactions', {
      'inventory_id': inventoryId,
      'movement_type': movementType,
      'category': category,
      'item_name': itemName,
      'quantity_delta': quantityDelta,
      'unit': unit,
      'unit_cost': unitCost,
      'activity_id': activityId,
      'transaction_date': activityDate,
      'notes': notes,
    });
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
    bool inventoryPurchasedAndUsed = false,
    bool isCompleted = false,
    InventoryProvider? inventoryProvider,
  }) async {
    final db = await DatabaseHelper.instance.database;
    if (expenseAmount != null &&
        (!expenseAmount.isFinite || expenseAmount < 0)) {
      throw ArgumentError.value(
        expenseAmount,
        'expenseAmount',
        'Must be finite and non-negative',
      );
    }
    if (inventoryQuantity != null &&
        (!inventoryQuantity.isFinite || inventoryQuantity <= 0)) {
      throw ArgumentError.value(
        inventoryQuantity,
        'inventoryQuantity',
        'Must be finite and positive',
      );
    }
    int? finalExpenseId = expenseId;

    await db.transaction((txn) async {
      if (finalExpenseId == null &&
          expenseAmount != null &&
          expenseAmount > 0) {
        finalExpenseId = await txn.insert(
          'expenses',
          Expense(
            category: expenseCategory ?? 'Other',
            amount: expenseAmount,
            date: date,
            description: '$activityType: $details',
          ).toMap(),
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
        inventoryPurchasedAndUsed: inventoryPurchasedAndUsed,
        isCompleted: isCompleted,
      );
      final activityId = await txn.insert('activities', newActivity.toMap());

      if (!inventoryPurchasedAndUsed &&
          inventoryCategory != null &&
          inventoryName != null &&
          inventoryUnit != null &&
          inventoryQuantity != null) {
        await _applyInventoryDelta(
          txn: txn,
          category: inventoryCategory,
          name: inventoryName,
          unit: inventoryUnit,
          quantity: inventoryQuantity,
          deduct: true,
          activityId: activityId,
          activityDate: date,
        );
      }
    });

    await fetchActivities();
    if (inventoryProvider != null) await inventoryProvider.fetchInventory();
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
    bool inventoryPurchasedAndUsed = false,
    bool? isCompleted,
    InventoryProvider? inventoryProvider,
  }) async {
    final db = await DatabaseHelper.instance.database;
    if (expenseAmount != null &&
        (!expenseAmount.isFinite || expenseAmount < 0)) {
      throw ArgumentError.value(
        expenseAmount,
        'expenseAmount',
        'Must be finite and non-negative',
      );
    }
    if (inventoryQuantity != null &&
        (!inventoryQuantity.isFinite || inventoryQuantity <= 0)) {
      throw ArgumentError.value(
        inventoryQuantity,
        'inventoryQuantity',
        'Must be finite and positive',
      );
    }

    await db.transaction((txn) async {
      final rows = await txn.query(
        'activities',
        where: 'id = ?',
        whereArgs: [id],
      );
      if (rows.isEmpty) return;
      final oldActivity = Activity.fromMap(rows.single);

      if (!oldActivity.inventoryPurchasedAndUsed &&
          oldActivity.inventoryCategory != null &&
          oldActivity.inventoryName != null &&
          oldActivity.inventoryUnit != null &&
          oldActivity.inventoryQuantity != null) {
        await _applyInventoryDelta(
          txn: txn,
          category: oldActivity.inventoryCategory!,
          name: oldActivity.inventoryName!,
          unit: oldActivity.inventoryUnit!,
          quantity: oldActivity.inventoryQuantity!,
          deduct: false,
          activityId: id,
          activityDate: oldActivity.date,
        );
      }

      int? finalExpenseId = oldActivity.expenseId;
      if (expenseAmount != null && expenseAmount > 0) {
        final expense =
            Expense(
                category: expenseCategory ?? 'Other',
                amount: expenseAmount,
                date: date,
                description: '$activityType: $details',
              ).toMap()
              ..remove('id');
        if (finalExpenseId == null) {
          finalExpenseId = await txn.insert('expenses', expense);
        } else {
          await txn.update(
            'expenses',
            expense,
            where: 'id = ?',
            whereArgs: [finalExpenseId],
          );
        }
      } else if (finalExpenseId != null) {
        await txn.delete(
          'expenses',
          where: 'id = ?',
          whereArgs: [finalExpenseId],
        );
        finalExpenseId = null;
      }

      if (!inventoryPurchasedAndUsed &&
          inventoryCategory != null &&
          inventoryName != null &&
          inventoryUnit != null &&
          inventoryQuantity != null) {
        await _applyInventoryDelta(
          txn: txn,
          category: inventoryCategory,
          name: inventoryName,
          unit: inventoryUnit,
          quantity: inventoryQuantity,
          deduct: true,
          activityId: id,
          activityDate: date,
        );
      }

      await txn.update(
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
          'inventory_purchased_and_used': inventoryPurchasedAndUsed ? 1 : 0,
          'is_completed':
              isCompleted == null
                  ? (oldActivity.isCompleted ? 1 : 0)
                  : (isCompleted ? 1 : 0),
        },
        where: 'id = ?',
        whereArgs: [id],
      );
    });

    await fetchActivities();
    if (inventoryProvider != null) await inventoryProvider.fetchInventory();
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
      inventoryPurchasedAndUsed: false,
      isCompleted: false,
    );
  }

  Future<void> deleteActivity(
    int id, {
    InventoryProvider? inventoryProvider,
  }) async {
    final db = await DatabaseHelper.instance.database;

    await db.transaction((txn) async {
      final rows = await txn.query(
        'activities',
        where: 'id = ?',
        whereArgs: [id],
      );
      if (rows.isEmpty) return;
      final activity = Activity.fromMap(rows.single);

      if (!activity.inventoryPurchasedAndUsed &&
          activity.inventoryCategory != null &&
          activity.inventoryName != null &&
          activity.inventoryUnit != null &&
          activity.inventoryQuantity != null) {
        await _applyInventoryDelta(
          txn: txn,
          category: activity.inventoryCategory!,
          name: activity.inventoryName!,
          unit: activity.inventoryUnit!,
          quantity: activity.inventoryQuantity!,
          deduct: false,
          activityId: id,
          activityDate: activity.date,
        );
      }

      await txn.delete('activities', where: 'id = ?', whereArgs: [id]);
      if (activity.expenseId != null) {
        await txn.delete(
          'expenses',
          where: 'id = ?',
          whereArgs: [activity.expenseId],
        );
      }
    });

    await fetchActivities();
    if (inventoryProvider != null) await inventoryProvider.fetchInventory();
  }
}
