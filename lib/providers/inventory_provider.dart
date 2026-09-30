import 'package:flutter/material.dart';
import 'package:sqflite/sqflite.dart';
import '../database/db_helper.dart';
import '../models/models.dart';

class InventoryProvider extends ChangeNotifier {
  List<Inventory> _inventoryList = [];

  List<Inventory> get inventoryList => _inventoryList;

  Future<void> fetchInventory() async {
    final db = await DatabaseHelper.instance.database;
    final List<Map<String, dynamic>> maps = await db.query(
      'inventory',
      orderBy: 'id DESC',
    );
    _inventoryList = List.generate(
      maps.length,
      (i) => Inventory.fromMap(maps[i]),
    );
    notifyListeners();
  }

  Future<void> addInventoryItem({
    required String category,
    required String name,
    required String unit,
    required double quantity,
    required double costPerUnit,
  }) async {
    _validateItem(
      category,
      name,
      unit,
      quantity,
      costPerUnit,
      allowZeroQuantity: false,
    );
    final db = await DatabaseHelper.instance.database;
    await db.transaction((txn) async {
      final cleanCategory = category.trim();
      final cleanName = name.trim();
      final cleanUnit = unit.trim();
      final existing = await txn.query(
        'inventory',
        where: 'category = ? AND name = ? AND unit = ?',
        whereArgs: [cleanCategory, cleanName, cleanUnit],
        orderBy: 'id ASC',
      );

      late final int inventoryId;
      if (existing.isNotEmpty) {
        final item = Inventory.fromMap(existing.first);
        inventoryId = item.id!;
        final newQty = item.quantity + quantity;
        if (!newQty.isFinite) {
          throw ArgumentError('اسٹاک کی مجموعی مقدار حد سے زیادہ ہے۔');
        }
        final newCost =
            item.quantity <= 0
                ? costPerUnit
                : ((item.quantity * item.costPerUnit) +
                        (quantity * costPerUnit)) /
                    newQty;
        if (!newCost.isFinite) {
          throw ArgumentError('اوسط قیمت درست نہیں۔');
        }
        await txn.update(
          'inventory',
          {'quantity': newQty, 'cost_per_unit': newCost},
          where: 'id = ?',
          whereArgs: [inventoryId],
        );
      } else {
        inventoryId = await txn.insert(
          'inventory',
          Inventory(
            category: cleanCategory,
            name: cleanName,
            unit: cleanUnit,
            quantity: quantity,
            costPerUnit: costPerUnit,
          ).toMap(),
        );
      }

      await _recordMovement(
        txn,
        inventoryId: inventoryId,
        movementType: 'purchase',
        category: cleanCategory,
        itemName: cleanName,
        quantityDelta: quantity,
        unit: cleanUnit,
        unitCost: costPerUnit,
        notes: 'ذخیرہ میں نیا سامان شامل کیا گیا',
      );
    });
    await fetchInventory();
  }

  Future<void> deductInventoryItem(
    String category,
    String name,
    double qtyToDeduct, {
    String? unit,
  }) async {
    if (!qtyToDeduct.isFinite || qtyToDeduct <= 0) {
      throw ArgumentError.value(
        qtyToDeduct,
        'qtyToDeduct',
        'Must be a finite positive number',
      );
    }
    final db = await DatabaseHelper.instance.database;
    await db.transaction((txn) async {
      final existing = await txn.query(
        'inventory',
        where: 'category = ? AND name = ?',
        whereArgs: [category, name],
        orderBy: 'id ASC',
      );
      final matches =
          unit == null
              ? existing
              : existing.where((row) => row['unit'] == unit).toList();
      if (matches.length != 1) {
        throw StateError(
          matches.isEmpty
              ? 'اس چیز کا اسٹاک موجود نہیں ہے۔'
              : 'اس چیز کی اکائی واضح نہیں؛ اسٹاک آئٹم منتخب کریں۔',
        );
      }
      final item = Inventory.fromMap(matches.single);
      if (unit != null && unit != item.unit) {
        throw ArgumentError(
          'اسٹاک میں کٹوتی کے لیے مقدار کی اکائی اسٹاک کی اکائی جیسی ہونی چاہیے۔',
        );
      }
      if (qtyToDeduct > item.quantity + 1e-9) {
        throw StateError(
          'گودام میں اسٹاک ناکافی ہے۔ موجود: ${item.quantity} ${item.unit}',
        );
      }
      final remaining = item.quantity - qtyToDeduct;
      await txn.update(
        'inventory',
        {'quantity': remaining < 1e-9 ? 0.0 : remaining},
        where: 'id = ?',
        whereArgs: [item.id],
      );
      await _recordMovement(
        txn,
        inventoryId: item.id!,
        movementType: 'usage',
        category: item.category,
        itemName: item.name,
        quantityDelta: -qtyToDeduct,
        unit: item.unit,
        unitCost: item.costPerUnit,
        notes: 'گودام سے استعمال',
      );
    });
    await fetchInventory();
  }

  Future<void> deleteInventoryItem(int id) async {
    final db = await DatabaseHelper.instance.database;
    await db.transaction((txn) async {
      final rows = await txn.query(
        'inventory',
        where: 'id = ?',
        whereArgs: [id],
      );
      if (rows.isEmpty) return;
      final item = Inventory.fromMap(rows.single);
      if (item.quantity > 1e-9) {
        await _recordMovement(
          txn,
          inventoryId: id,
          movementType: 'adjustment',
          category: item.category,
          itemName: item.name,
          quantityDelta: -item.quantity,
          unit: item.unit,
          unitCost: item.costPerUnit,
          notes: 'اسٹاک آئٹم حذف ہونے پر باقی مقدار خارج کی گئی',
        );
      }
      await txn.delete('inventory', where: 'id = ?', whereArgs: [id]);
    });
    await fetchInventory();
  }

  Future<void> updateInventoryItem({
    required int id,
    required String category,
    required String name,
    required String unit,
    required double quantity,
    required double costPerUnit,
  }) async {
    _validateItem(
      category,
      name,
      unit,
      quantity,
      costPerUnit,
      allowZeroQuantity: true,
    );
    final db = await DatabaseHelper.instance.database;
    await db.transaction((txn) async {
      final rows = await txn.query(
        'inventory',
        where: 'id = ?',
        whereArgs: [id],
      );
      if (rows.isEmpty) throw StateError('یہ اسٹاک آئٹم اب موجود نہیں ہے۔');
      final oldItem = Inventory.fromMap(rows.single);
      final newCategory = category.trim();
      final newName = name.trim();
      final newUnit = unit.trim();

      if (oldItem.unit != newUnit) {
        if (oldItem.quantity > 1e-9) {
          await _recordMovement(
            txn,
            inventoryId: id,
            movementType: 'adjustment',
            category: oldItem.category,
            itemName: oldItem.name,
            quantityDelta: -oldItem.quantity,
            unit: oldItem.unit,
            unitCost: oldItem.costPerUnit,
            notes: 'اکائی تبدیل ہونے پر پرانا بیلنس بند کیا گیا',
          );
        }
        if (quantity > 1e-9) {
          await _recordMovement(
            txn,
            inventoryId: id,
            movementType: 'adjustment',
            category: newCategory,
            itemName: newName,
            quantityDelta: quantity,
            unit: newUnit,
            unitCost: costPerUnit,
            notes: 'نئی اکائی میں ابتدائی بیلنس درج کیا گیا',
          );
        }
      } else {
        final delta = quantity - oldItem.quantity;
        if (delta.abs() > 1e-9) {
          await _recordMovement(
            txn,
            inventoryId: id,
            movementType: 'adjustment',
            category: newCategory,
            itemName: newName,
            quantityDelta: delta,
            unit: newUnit,
            unitCost: costPerUnit,
            notes: 'اسٹاک کی مقدار میں ترمیم',
          );
        }
      }

      await txn.update(
        'inventory',
        {
          'category': newCategory,
          'name': newName,
          'unit': newUnit,
          'quantity': quantity,
          'cost_per_unit': costPerUnit,
        },
        where: 'id = ?',
        whereArgs: [id],
      );
    });
    await fetchInventory();
  }

  Future<List<Map<String, dynamic>>> fetchInventoryTransactions({
    int? inventoryId,
    int limit = 100,
  }) async {
    if (limit <= 0) {
      throw ArgumentError.value(limit, 'limit', 'Must be positive');
    }
    final db = await DatabaseHelper.instance.database;
    return db.query(
      'inventory_transactions',
      where: inventoryId == null ? null : 'inventory_id = ?',
      whereArgs: inventoryId == null ? null : [inventoryId],
      orderBy: 'transaction_date DESC, id DESC',
      limit: limit,
    );
  }

  Future<void> _recordMovement(
    Transaction txn, {
    required int inventoryId,
    required String movementType,
    required String category,
    required String itemName,
    required double quantityDelta,
    required String unit,
    required double unitCost,
    int? activityId,
    String? notes,
  }) async {
    if (!quantityDelta.isFinite || quantityDelta.abs() <= 1e-9) {
      throw ArgumentError.value(
        quantityDelta,
        'quantityDelta',
        'Stock movements must have a finite, non-zero quantity',
      );
    }
    if (!unitCost.isFinite || unitCost < 0) {
      throw ArgumentError.value(unitCost, 'unitCost', 'Must be non-negative');
    }
    await txn.insert('inventory_transactions', {
      'inventory_id': inventoryId,
      'movement_type': movementType,
      'category': category,
      'item_name': itemName,
      'quantity_delta': quantityDelta,
      'unit': unit,
      'unit_cost': unitCost,
      'activity_id': activityId,
      'transaction_date': DateTime.now().toIso8601String(),
      'notes': notes,
    });
  }

  void _validateItem(
    String category,
    String name,
    String unit,
    double quantity,
    double costPerUnit, {
    required bool allowZeroQuantity,
  }) {
    if (category.trim().isEmpty || name.trim().isEmpty || unit.trim().isEmpty) {
      throw ArgumentError('اسٹاک کا زمرہ، نام اور اکائی درج کرنا ضروری ہے۔');
    }
    if (!quantity.isFinite ||
        (allowZeroQuantity ? quantity < 0 : quantity <= 0)) {
      throw ArgumentError.value(quantity, 'quantity', 'اسٹاک کی مقدار غلط ہے۔');
    }
    if (!costPerUnit.isFinite || costPerUnit < 0) {
      throw ArgumentError.value(
        costPerUnit,
        'costPerUnit',
        'فی اکائی قیمت درست ہونی چاہیے۔',
      );
    }
  }
}
