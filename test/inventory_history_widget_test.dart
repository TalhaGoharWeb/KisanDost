import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:kisan_dost/models/models.dart';
import 'package:kisan_dost/providers/inventory_provider.dart';
import 'package:kisan_dost/screens/inventory_screen.dart';

class _FakeInventoryProvider extends InventoryProvider {
  @override
  List<Inventory> get inventoryList => [
    Inventory(
      id: 1,
      category: 'Fertilizer',
      name: 'Urea',
      unit: 'کلوگرام',
      quantity: 10,
      costPerUnit: 100,
    ),
  ];

  @override
  Future<List<Map<String, dynamic>>> fetchInventoryTransactions({
    int? inventoryId,
    int limit = 100,
  }) async => [
    {
      'id': 1,
      'inventory_id': 1,
      'movement_type': 'purchase',
      'category': 'Fertilizer',
      'item_name': 'Urea',
      'quantity_delta': 10.0,
      'unit': 'کلوگرام',
      'unit_cost': 100.0,
      'activity_id': null,
      'transaction_date': '2026-09-30T10:00:00.000',
      'notes': 'ذخیرہ میں نیا سامان شامل کیا گیا',
    },
  ];
}

void main() {
  testWidgets('inventory item opens readable Urdu stock movement history', (
    tester,
  ) async {
    final inventoryProvider = _FakeInventoryProvider();
    await tester.pumpWidget(
      ChangeNotifierProvider<InventoryProvider>.value(
        value: inventoryProvider,
        child: const MaterialApp(home: InventoryScreen()),
      ),
    );
    await tester.pump();

    await tester.tap(find.byTooltip('اسٹاک کی تاریخ'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 350));
    await tester.pump();

    expect(find.text('Urea — اسٹاک کی تاریخ'), findsOneWidget);
    expect(find.textContaining('خرید / اسٹاک وصول'), findsOneWidget);
    expect(find.textContaining('+10.00 کلوگرام'), findsOneWidget);

    await tester.tapAt(const Offset(10, 10));
    await tester.pump(const Duration(milliseconds: 350));
  });
}
