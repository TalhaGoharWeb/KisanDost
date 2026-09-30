import 'package:flutter/material.dart';
import '../database/db_helper.dart';
import '../models/models.dart';

class InventoryProvider extends ChangeNotifier {
  List<Inventory> _inventoryList = [];

  List<Inventory> get inventoryList => _inventoryList;

  Future<void> fetchInventory() async {
    final db = await DatabaseHelper.instance.database;
    final List<Map<String, dynamic>> maps = await db.query('inventory', orderBy: 'id DESC');
    _inventoryList = List.generate(maps.length, (i) => Inventory.fromMap(maps[i]));
    notifyListeners();
  }

  Future<void> addInventoryItem({
    required String category,
    required String name,
    required String unit,
    required double quantity,
    required double costPerUnit,
  }) async {
    final db = await DatabaseHelper.instance.database;
    
    // Check if item already exists in inventory
    final List<Map<String, dynamic>> existing = await db.query(
      'inventory',
      where: 'category = ? AND name = ? AND unit = ?',
      whereArgs: [category, name, unit],
    );

    if (existing.isNotEmpty) {
      // Update quantity and recalculate average cost
      final item = Inventory.fromMap(existing.first);
      final double newQty = item.quantity + quantity;
      final double newCost = ((item.quantity * item.costPerUnit) + (quantity * costPerUnit)) / newQty;
      
      await db.update(
        'inventory',
        {
          'quantity': newQty,
          'cost_per_unit': newCost,
        },
        where: 'id = ?',
        whereArgs: [item.id],
      );
    } else {
      // Insert new item
      final newItem = Inventory(
        category: category,
        name: name,
        unit: unit,
        quantity: quantity,
        costPerUnit: costPerUnit,
      );
      await db.insert('inventory', newItem.toMap());
    }
    
    await fetchInventory();
  }

  Future<void> deductInventoryItem(String category, String name, double qtyToDeduct) async {
    final db = await DatabaseHelper.instance.database;
    
    final List<Map<String, dynamic>> existing = await db.query(
      'inventory',
      where: 'category = ? AND name = ?',
      whereArgs: [category, name],
    );

    if (existing.isNotEmpty) {
      final item = Inventory.fromMap(existing.first);
      final double remainingQty = (item.quantity - qtyToDeduct).clamp(0.0, double.infinity);
      
      await db.update(
        'inventory',
        {'quantity': remainingQty},
        where: 'id = ?',
        whereArgs: [item.id],
      );
      await fetchInventory();
    }
  }

  Future<void> deleteInventoryItem(int id) async {
    final db = await DatabaseHelper.instance.database;
    await db.delete(
      'inventory',
      where: 'id = ?',
      whereArgs: [id],
    );
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
    final db = await DatabaseHelper.instance.database;
    await db.update(
      'inventory',
      {
        'category': category,
        'name': name,
        'unit': unit,
        'quantity': quantity,
        'cost_per_unit': costPerUnit,
      },
      where: 'id = ?',
      whereArgs: [id],
    );
    await fetchInventory();
  }
}
