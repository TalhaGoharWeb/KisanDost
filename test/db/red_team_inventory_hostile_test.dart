/// Red-team hostile tests: NaN / Infinity poisoning of the inventory ledger.
///
/// `NaN <= 0` is false in Dart, so a NaN quantity sails past every
/// `quantity <= 0` guard in the provider. If any path (bug, future caller,
/// platform quirk) delivers a non-finite double, it must be rejected loudly
/// — never stored as NaN/Inf in the quantity cache or ledger.
import 'package:flutter_test/flutter_test.dart';
import 'package:kisan_dost/database/db_helper.dart';
import 'package:kisan_dost/models/models.dart';
import 'package:kisan_dost/providers/inventory_provider.dart';
import 'package:kisan_dost/services/unit_converter.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

Future<Database> _freshDb() async {
  sqfliteFfiInit();
  final db = await databaseFactoryFfi.openDatabase(inMemoryDatabasePath);
  await DatabaseHelper.instance.createFreshSchemaForTests(db);
  return db;
}

Future<int> _seedItem(Database db) async {
  final p = InventoryProvider(testExecutor: db);
  return p.recordPurchase(
    category: 'کھاد',
    name: 'یوریا',
    unit: 'بوری',
    quantity: 10,
    costPerUnitPaisa: 500000,
    executor: db,
  );
}

void main() {
  group('red-team: non-finite quantity rejection', () {
    test('recordPurchase rejects NaN quantity', () async {
      final db = await _freshDb();
      final p = InventoryProvider(testExecutor: db);
      await expectLater(
        p.recordPurchase(
          category: 'کھاد',
          name: 'x',
          unit: 'بوری',
          quantity: double.nan,
          costPerUnitPaisa: 100,
          executor: db,
        ),
        throwsA(isA<InventoryException>()),
      );
      await db.close();
    });

    test('recordPurchase rejects infinite quantity', () async {
      final db = await _freshDb();
      final p = InventoryProvider(testExecutor: db);
      await expectLater(
        p.recordPurchase(
          category: 'کھاد',
          name: 'x',
          unit: 'بوری',
          quantity: double.infinity,
          costPerUnitPaisa: 100,
          executor: db,
        ),
        throwsA(isA<InventoryException>()),
      );
      await db.close();
    });

    test('recordUsage rejects NaN quantity (never touches stock)', () async {
      final db = await _freshDb();
      final id = await _seedItem(db);
      final p = InventoryProvider(testExecutor: db);
      await expectLater(
        p.recordUsage(itemId: id, quantity: double.nan, executor: db),
        throwsA(isA<InventoryException>()),
      );
      final item = await p.getItemById(id, executor: db);
      expect(item!.quantity, 10.0);
      await db.close();
    });

    test('recordAdjustment rejects NaN delta', () async {
      final db = await _freshDb();
      final id = await _seedItem(db);
      final p = InventoryProvider(testExecutor: db);
      await expectLater(
        p.recordAdjustment(
          itemId: id,
          quantityDelta: double.nan,
          reason: 'ٹیسٹ',
          executor: db,
        ),
        throwsA(isA<InventoryException>()),
      );
      final item = await p.getItemById(id, executor: db);
      expect(item!.quantity, 10.0);
      await db.close();
    });

    test('ledger has no NaN rows after hostile attempts', () async {
      final db = await _freshDb();
      final id = await _seedItem(db);
      final p = InventoryProvider(testExecutor: db);
      for (final fn in [
        () => p.recordUsage(itemId: id, quantity: double.nan, executor: db),
        () => p.recordAdjustment(
          itemId: id,
          quantityDelta: double.infinity,
          reason: 'ٹیسٹ',
          executor: db,
        ),
      ]) {
        try {
          await fn();
        } catch (_) {}
      }
      final txns = await p.getTransactions(id, executor: db);
      for (final t in txns) {
        expect(t.quantity.isFinite, isTrue,
            reason: 'ledger row ${t.id} has non-finite quantity');
      }
      await db.close();
    });
  });
}
