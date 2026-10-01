import 'package:flutter/material.dart';
import 'package:sqflite/sqflite.dart';
import '../database/db_helper.dart';
import '../models/models.dart';
import '../services/unit_converter.dart';
import 'inventory_provider.dart';

class ActivityWithDetails {
  final Activity activity;
  final String cropName;
  final List<String> fieldNames;
  /// Linked expense amount in INTEGER paisa (null when no expense).
  final int? expenseAmountPaisa;

  ActivityWithDetails({
    required this.activity,
    this.expenseAmountPaisa,
    required this.cropName,
    required this.fieldNames,
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
        a.inventory_item_id,
        a.is_completed,
        cs.crop_name,
        e.amount_paisa as expense_amount_paisa
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
        inventoryItemId: results[i]['inventory_item_id'],
        isCompleted: (results[i]['is_completed'] ?? 0) == 1,
      );
      return ActivityWithDetails(
        activity: activity,
        cropName: results[i]['crop_name'],
        fieldNames: seasonFields[activity.cropSeasonId] ?? [],
        expenseAmountPaisa: results[i]['expense_amount_paisa'] == null
            ? null
            : results[i]['expense_amount_paisa'] as int,
      );
    });

    notifyListeners();
  }

  /// Resolves the exact inventory row an activity consumed, for restores.
  /// Prefers the stored [Activity.inventoryItemId]; falls back to the
  /// (category, name, unit) snapshot for pre-v11 rows. Throws loudly when
  /// the item no longer exists — restores are never silently skipped and
  /// phantom zero-cost stock is never auto-created.
  Future<Inventory> _resolveItemForRestore(
    DatabaseExecutor ex,
    InventoryProvider inventoryProvider,
    Activity activity,
  ) async {
    if (activity.inventoryItemId != null) {
      final Inventory? byId = await inventoryProvider.getItemById(
        activity.inventoryItemId!,
        executor: ex,
      );
      if (byId != null) return byId;
    }
    if (activity.inventoryCategory != null &&
        activity.inventoryName != null &&
        activity.inventoryUnit != null) {
      final Inventory? byKey = await inventoryProvider.findItem(
        category: activity.inventoryCategory!,
        name: activity.inventoryName!,
        unit: activity.inventoryUnit!,
        executor: ex,
      );
      if (byKey != null) return byKey;
    }
    throw const InventoryException(
      'اس سرگرمی کا اسٹاک آئٹم گودام میں موجود نہیں ہے — پہلے آئٹم شامل کریں',
    );
  }

  /// Returns previously deducted stock to the warehouse inside [ex].
  /// The restore is an 'adjustment' ledger entry, never a silent add-back.
  Future<void> _restoreInventoryTx(
    DatabaseExecutor ex, {
    required InventoryProvider inventoryProvider,
    required Activity activity,
  }) async {
    if (activity.inventoryQuantity == null || activity.inventoryQuantity! <= 0) {
      return;
    }
    if (activity.inventoryCategory == null ||
        activity.inventoryName == null ||
        activity.inventoryUnit == null) {
      return;
    }
    final Inventory item =
        await _resolveItemForRestore(ex, inventoryProvider, activity);
    double qtyInItemUnit = activity.inventoryQuantity!;
    if (activity.inventoryUnit != item.unit) {
      qtyInItemUnit = UnitConverter.convert(
        activity.inventoryQuantity!,
        activity.inventoryUnit!,
        item.unit,
        weightPerUnitKg: item.weightPerUnitKg,
      );
    }
    await inventoryProvider.recordAdjustment(
      itemId: item.id!,
      quantityDelta: qtyInItemUnit,
      reason: 'سرگرمی حذف/تبدیل ہونے پر اسٹاک واپس',
      date: activity.date,
      executor: ex,
    );
  }

  Future<void> addActivity({
    required int cropSeasonId,
    required String activityType,
    required String date,
    required String details,
    int? expenseAmountPaisa,
    String? expenseCategory,
    int? expenseId,
    String? inventoryCategory,
    String? inventoryName,
    String? inventoryUnit,
    double? inventoryQuantity,
    int? inventoryItemId,
    bool isCompleted = false,
    InventoryProvider? inventoryProvider,
  }) async {
    final db = await DatabaseHelper.instance.database;

    // Expense + activity row + inventory deduction happen in ONE transaction:
    // if the deduction is rejected (overuse / missing item), nothing is saved.
    await db.transaction((txn) async {
      int? finalExpenseId = expenseId;
      if (finalExpenseId == null && expenseAmountPaisa != null && expenseAmountPaisa > 0) {
        final newExpense = Expense(
          category: expenseCategory ?? 'Other',
          amountPaisa: expenseAmountPaisa,
          date: date,
          description: '$activityType: $details',
        );
        finalExpenseId = await txn.insert('expenses', newExpense.toMap());
      }

      final int activityId = await txn.insert(
        'activities',
        Activity(
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
          inventoryItemId: inventoryItemId,
          isCompleted: isCompleted,
        ).toMap(),
      );

      if (inventoryProvider != null &&
          inventoryItemId != null &&
          inventoryQuantity != null &&
          inventoryQuantity > 0) {
        await inventoryProvider.recordUsage(
          itemId: inventoryItemId,
          quantity: inventoryQuantity,
          fromUnit: inventoryUnit,
          activityId: activityId,
          date: date,
          executor: txn,
        );
      }
    });

    await fetchActivities();
    if (inventoryProvider != null) {
      await inventoryProvider.fetchInventory();
    }
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
    int? expenseAmountPaisa,
    String? expenseCategory,
    String? inventoryCategory,
    String? inventoryName,
    String? inventoryUnit,
    double? inventoryQuantity,
    int? inventoryItemId,
    bool? isCompleted,
    InventoryProvider? inventoryProvider,
  }) async {
    final db = await DatabaseHelper.instance.database;

    await db.transaction((txn) async {
      final List<Map<String, dynamic>> maps = await txn.query(
        'activities',
        where: 'id = ?',
        whereArgs: [id],
      );
      if (maps.isEmpty) {
        return;
      }
      final Activity oldActivity = Activity.fromMap(maps.first);

      // Return the old deduction first (loud if the item is gone).
      if (inventoryProvider != null) {
        await _restoreInventoryTx(
          txn,
          inventoryProvider: inventoryProvider,
          activity: oldActivity,
        );
      }

      int? finalExpenseId = oldActivity.expenseId;
      if (expenseAmountPaisa != null && expenseAmountPaisa > 0) {
        if (finalExpenseId == null) {
          finalExpenseId = await txn.insert(
            'expenses',
            Expense(
              category: expenseCategory ?? 'Other',
              amountPaisa: expenseAmountPaisa,
              date: date,
              description: '$activityType: $details',
            ).toMap(),
          );
        } else {
          await txn.update(
            'expenses',
            {
              'category': expenseCategory ?? 'Other',
              'amount_paisa': expenseAmountPaisa,
              'date': date,
              'description': '$activityType: $details',
            },
            where: 'id = ?',
            whereArgs: [finalExpenseId],
          );
        }
      } else if (finalExpenseId != null) {
        await txn.delete('expenses',
            where: 'id = ?', whereArgs: [finalExpenseId]);
        finalExpenseId = null;
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
          'inventory_item_id': inventoryItemId,
          'is_completed': isCompleted == null
              ? (oldActivity.isCompleted ? 1 : 0)
              : (isCompleted ? 1 : 0),
        },
        where: 'id = ?',
        whereArgs: [id],
      );

      if (inventoryProvider != null &&
          inventoryItemId != null &&
          inventoryQuantity != null &&
          inventoryQuantity > 0) {
        await inventoryProvider.recordUsage(
          itemId: inventoryItemId,
          quantity: inventoryQuantity,
          fromUnit: inventoryUnit,
          activityId: id,
          date: date,
          executor: txn,
        );
      }
    });

    await fetchActivities();
    if (inventoryProvider != null) {
      await inventoryProvider.fetchInventory();
    }
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
      expenseAmountPaisa: null,
      expenseCategory: activity.expenseCategory,
      inventoryCategory: activity.inventoryCategory,
      inventoryName: activity.inventoryName,
      inventoryUnit: activity.inventoryUnit,
      inventoryQuantity: null,
      isCompleted: false,
    );
  }

  Future<void> deleteActivity(int id,
      {InventoryProvider? inventoryProvider}) async {
    final db = await DatabaseHelper.instance.database;

    await db.transaction((txn) async {
      final List<Map<String, dynamic>> maps = await txn.query(
        'activities',
        where: 'id = ?',
        whereArgs: [id],
      );
      if (maps.isEmpty) {
        return;
      }
      final Activity activity = Activity.fromMap(maps.first);

      // Restore deducted stock first. Throws loudly when the item is gone —
      // the delete is aborted rather than silently losing stock history.
      if (inventoryProvider != null) {
        await _restoreInventoryTx(
          txn,
          inventoryProvider: inventoryProvider,
          activity: activity,
        );
      }

      await txn.delete(
        'activities',
        where: 'id = ?',
        whereArgs: [id],
      );

      if (activity.expenseId != null) {
        await txn.delete(
          'expenses',
          where: 'id = ?',
          whereArgs: [activity.expenseId],
        );
      }
    });

    await fetchActivities();
    if (inventoryProvider != null) {
      await inventoryProvider.fetchInventory();
    }
  }
}
