import 'package:flutter/material.dart';
import 'package:sqflite/sqflite.dart';
import '../database/db_helper.dart';
import '../models/models.dart';
import '../services/unit_converter.dart';

/// Inventory with an immutable transaction ledger.
///
/// `inventory.quantity` is a cached running total. Every stock movement
/// writes one row to `inventory_transactions` AND updates the cache inside
/// a single DB transaction, so the two can never disagree.
///
/// Impossible stock is rejected loudly ([InventoryException] with an Urdu
/// message) — never clamped to zero, never silently skipped.
class InventoryProvider extends ChangeNotifier {
  List<Inventory> _inventoryList = [];

  List<Inventory> get inventoryList => _inventoryList;

  Future<void> fetchInventory() async {
    final db = await DatabaseHelper.instance.database;
    final List<Map<String, dynamic>> maps =
        await db.query('inventory', orderBy: 'id DESC');
    _inventoryList = List.generate(maps.length, (i) => Inventory.fromMap(maps[i]));
    notifyListeners();
  }

  Future<DatabaseExecutor> _executor(DatabaseExecutor? executor) async {
    if (executor != null) return executor;
    return await DatabaseHelper.instance.database;
  }

  /// Finds an item by its unique (category, name, unit) key.
  Future<Inventory?> findItem({
    required String category,
    required String name,
    required String unit,
    DatabaseExecutor? executor,
  }) async {
    final db = await _executor(executor);
    final List<Map<String, dynamic>> maps = await db.query(
      'inventory',
      where: 'category = ? AND name = ? AND unit = ?',
      whereArgs: [category, name, unit],
    );
    if (maps.isEmpty) return null;
    return Inventory.fromMap(maps.first);
  }

  Future<Inventory?> getItemById(int id, {DatabaseExecutor? executor}) async {
    final db = await _executor(executor);
    final List<Map<String, dynamic>> maps = await db.query(
      'inventory',
      where: 'id = ?',
      whereArgs: [id],
    );
    if (maps.isEmpty) return null;
    return Inventory.fromMap(maps.first);
  }

  /// Records a purchase: merges into the existing (category, name, unit) row
  /// with weighted-average cost, or creates the row. Always writes a
  /// 'purchase' ledger entry. Returns the item id.
  Future<int> recordPurchase({
    required String category,
    required String name,
    required String unit,
    required double quantity,
    required int costPerUnitPaisa,
    double? weightPerUnitKg,
    String? date,
    String? notes,
    DatabaseExecutor? executor,
  }) async {
    if (quantity <= 0) {
      throw const InventoryException('خریداری کی مقدار صفر سے زیادہ ہونی چاہیے');
    }
    if (costPerUnitPaisa < 0) {
      throw const InventoryException('فی اکائی قیمت منفی نہیں ہو سکتی');
    }
    if (weightPerUnitKg != null && weightPerUnitKg <= 0) {
      throw const InventoryException('فی پیکٹ وزن صفر سے زیادہ ہونا چاہیے');
    }

    Future<int> run(DatabaseExecutor ex) => _recordPurchaseTx(
          ex,
          category: category,
          name: name,
          unit: unit,
          quantity: quantity,
          costPerUnitPaisa: costPerUnitPaisa,
          weightPerUnitKg: weightPerUnitKg,
          date: date,
          notes: notes,
        );
    // Copy to a local so flow analysis can promote the null check.
    // The singleton DB is only resolved when no executor was supplied,
    // so tests can inject an in-memory database hermetically.
    final DatabaseExecutor? transactionExecutor = executor;
    late final int itemId;
    if (transactionExecutor == null) {
      final db = await DatabaseHelper.instance.database;
      itemId = await db.transaction(run);
    } else {
      itemId = await run(transactionExecutor);
    }
    // Refresh only when we own the transaction: inside an outer transaction
    // (e.g. ActivityProvider's) a fresh read here would deadlock.
    if (transactionExecutor == null) await fetchInventory();
    return itemId;
  }

  Future<int> _recordPurchaseTx(
    DatabaseExecutor ex, {
    required String category,
    required String name,
    required String unit,
    required double quantity,
    required int costPerUnitPaisa,
    double? weightPerUnitKg,
    String? date,
    String? notes,
  }) async {
    final String now = DateTime.now().toIso8601String();
    final Inventory? existing = await findItem(
      category: category,
      name: name,
      unit: unit,
      executor: ex,
    );

    late final int itemId;
    if (existing != null) {
      final double newQty = existing.quantity + quantity;
      if (newQty <= 0) {
        // Legacy corrupted (negative) stock: adding stock must never leave
        // a non-positive total silently.
        throw const InventoryException(
            'اسٹاک کی موجودہ مقدار درست نہیں؛ پہلے تصحیح کریں');
      }
      // newQty > 0 guaranteed: the old divide-by-zero (Infinity cost) path
      // cannot happen.
      // Weighted average in INTEGER paisa: the numerator is a double
      // (quantity x paisa); the average rounds to the nearest paisa
      // (half away from zero).
      final int newCostPaisa =
          (((existing.quantity * existing.costPerUnitPaisa) +
                      (quantity * costPerUnitPaisa)) /
                  newQty)
              .round();
      await ex.update(
        'inventory',
        {
          'quantity': newQty,
          'cost_per_unit_paisa': newCostPaisa,
          'weight_per_unit_kg': weightPerUnitKg ?? existing.weightPerUnitKg,
        },
        where: 'id = ?',
        whereArgs: [existing.id],
      );
      itemId = existing.id!;
    } else {
      itemId = await ex.insert('inventory', {
        'category': category,
        'name': name,
        'unit': unit,
        'quantity': quantity,
        'cost_per_unit_paisa': costPerUnitPaisa,
        'weight_per_unit_kg': weightPerUnitKg,
      });
    }

    await ex.insert('inventory_transactions', {
      'inventory_id': itemId,
      'type': 'purchase',
      'quantity': quantity,
      'unit': unit,
      'unit_price_paisa': costPerUnitPaisa,
      'total_amount_paisa': (quantity * costPerUnitPaisa).round(),
      'date': date ?? now,
      'notes': notes,
      'created_at': now,
    });
    return itemId;
  }

  /// Records usage of stock. [quantity] is in the item's own unit unless
  /// [fromUnit] is given, in which case it is converted via [UnitConverter]
  /// (package units need the item's [weightPerUnitKg]).
  ///
  /// Throws [InventoryException] when the item does not exist or when the
  /// usage exceeds available stock — impossible stock is never created.
  Future<void> recordUsage({
    required int itemId,
    required double quantity,
    String? fromUnit,
    int? activityId,
    String? date,
    String? notes,
    DatabaseExecutor? executor,
  }) async {
    if (quantity <= 0) {
      throw const InventoryException('استعمال کی مقدار صفر سے زیادہ ہونی چاہیے');
    }
    Future<void> run(DatabaseExecutor ex) => _recordUsageTx(
          ex,
          itemId: itemId,
          quantity: quantity,
          fromUnit: fromUnit,
          activityId: activityId,
          date: date,
          notes: notes,
        );
    // Copy to a local so flow analysis can promote the null check.
    // The singleton DB is only resolved when no executor was supplied,
    // so tests can inject an in-memory database hermetically.
    final DatabaseExecutor? transactionExecutor = executor;
    if (transactionExecutor == null) {
      final db = await DatabaseHelper.instance.database;
      await db.transaction(run);
    } else {
      await run(transactionExecutor);
    }
    // Refresh only when we own the transaction: inside an outer transaction
    // (e.g. ActivityProvider's) a fresh read here would deadlock.
    if (transactionExecutor == null) await fetchInventory();
  }

  Future<void> _recordUsageTx(
    DatabaseExecutor ex, {
    required int itemId,
    required double quantity,
    String? fromUnit,
    int? activityId,
    String? date,
    String? notes,
  }) async {
    final Inventory? item = await getItemById(itemId, executor: ex);
    if (item == null) {
      throw const InventoryException('یہ آئٹم گودام میں موجود نہیں ہے');
    }

    double qtyInItemUnit = quantity;
    String? enteredNote = notes;
    if (fromUnit != null && fromUnit != item.unit) {
      // May throw UnitConversionException (e.g. package unit without a
      // defined weight) — loud by design.
      qtyInItemUnit = UnitConverter.convert(
        quantity,
        fromUnit,
        item.unit,
        weightPerUnitKg: item.weightPerUnitKg,
      );
      enteredNote = 'درج: $quantity $fromUnit';
    }

    if (qtyInItemUnit > item.quantity) {
      throw InventoryException(
        'گودام میں صرف ${item.quantity.toStringAsFixed(1)} ${item.unit} دستیاب ہے — '
        'اتنی مقدار استعمال نہیں ہو سکتی',
      );
    }

    final String now = DateTime.now().toIso8601String();
    await ex.update(
      'inventory',
      {'quantity': item.quantity - qtyInItemUnit},
      where: 'id = ?',
      whereArgs: [itemId],
    );
    await ex.insert('inventory_transactions', {
      'inventory_id': itemId,
      'type': 'usage',
      'quantity': -qtyInItemUnit,
      'unit': item.unit,
      'activity_id': activityId,
      'date': date ?? now,
      'notes': enteredNote,
      'created_at': now,
    });
  }

  /// Records a manual stock correction. [quantityDelta] is signed
  /// (+ adds, − removes); [reason] is a required Urdu note.
  Future<void> recordAdjustment({
    required int itemId,
    required double quantityDelta,
    required String reason,
    String? date,
    DatabaseExecutor? executor,
  }) async {
    if (reason.trim().isEmpty) {
      throw const InventoryException('تصحیح کی وجہ درج کرنا ضروری ہے');
    }
    if (quantityDelta == 0) {
      throw const InventoryException('تصحیح کی مقدار صفر نہیں ہو سکتی');
    }
    Future<void> run(DatabaseExecutor ex) async {
      final Inventory? item = await getItemById(itemId, executor: ex);
      if (item == null) {
        throw const InventoryException('یہ آئٹم گودام میں موجود نہیں ہے');
      }
      final double newQty = item.quantity + quantityDelta;
      if (newQty < 0) {
        throw const InventoryException('تصحیح کے بعد اسٹاک منفی نہیں ہو سکتا');
      }
      final String now = DateTime.now().toIso8601String();
      await ex.update(
        'inventory',
        {'quantity': newQty},
        where: 'id = ?',
        whereArgs: [itemId],
      );
      await ex.insert('inventory_transactions', {
        'inventory_id': itemId,
        'type': 'adjustment',
        'quantity': quantityDelta,
        'unit': item.unit,
        'date': date ?? now,
        'notes': reason,
        'created_at': now,
      });
    }

    // Copy to a local so flow analysis can promote the null check.
    // The singleton DB is only resolved when no executor was supplied,
    // so tests can inject an in-memory database hermetically.
    final DatabaseExecutor? transactionExecutor = executor;
    if (transactionExecutor == null) {
      final db = await DatabaseHelper.instance.database;
      await db.transaction(run);
    } else {
      await run(transactionExecutor);
    }
    // Refresh only when we own the transaction: inside an outer transaction
    // (e.g. ActivityProvider's) a fresh read here would deadlock.
    if (transactionExecutor == null) await fetchInventory();
  }

  /// Updates an item's descriptive fields (NOT its quantity — quantity only
  /// moves through the ledger). Throws if the rename would collide with
  /// another item's (category, name, unit) key.
  Future<void> updateItemDetails({
    required int id,
    required String category,
    required String name,
    required String unit,
    required int costPerUnitPaisa,
    double? weightPerUnitKg,
    DatabaseExecutor? executor,
  }) async {
    if (costPerUnitPaisa < 0) {
      throw const InventoryException('فی اکائی قیمت منفی نہیں ہو سکتی');
    }
    if (weightPerUnitKg != null && weightPerUnitKg <= 0) {
      throw const InventoryException('فی پیکٹ وزن صفر سے زیادہ ہونا چاہیے');
    }
    // Copy to a local so flow analysis can promote the null check.
    final DatabaseExecutor? transactionExecutor = executor;
    final db = await _executor(transactionExecutor);
    final List<Map<String, dynamic>> clash = await db.query(
      'inventory',
      where: 'category = ? AND name = ? AND unit = ? AND id != ?',
      whereArgs: [category, name, unit, id],
    );
    if (clash.isNotEmpty) {
      throw const InventoryException('اس نام اور اکائی کا آئٹم پہلے سے موجود ہے');
    }
    await db.update(
      'inventory',
      {
        'category': category,
        'name': name,
        'unit': unit,
        'cost_per_unit_paisa': costPerUnitPaisa,
        'weight_per_unit_kg': weightPerUnitKg,
      },
      where: 'id = ?',
      whereArgs: [id],
    );
    if (transactionExecutor == null) await fetchInventory();
  }

  /// Deletes the item row. Ledger rows cascade with it (documented
  /// trade-off: history of a deleted item goes with it).
  Future<void> deleteInventoryItem(int id, {DatabaseExecutor? executor}) async {
    final db = await _executor(executor);
    await db.delete(
      'inventory',
      where: 'id = ?',
      whereArgs: [id],
    );
    if (executor == null) await fetchInventory();
  }

  /// Full transaction history of one item, newest first.
  Future<List<InventoryTransaction>> getTransactions(
    int itemId, {
    DatabaseExecutor? executor,
  }) async {
    final db = await _executor(executor);
    final List<Map<String, dynamic>> maps = await db.query(
      'inventory_transactions',
      where: 'inventory_id = ?',
      whereArgs: [itemId],
      orderBy: 'id DESC',
    );
    return maps.map(InventoryTransaction.fromMap).toList();
  }
}
