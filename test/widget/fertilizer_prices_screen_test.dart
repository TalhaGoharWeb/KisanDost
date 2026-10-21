import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:kisan_dost/screens/fertilizer_prices_screen.dart';
import 'package:kisan_dost/services/fertilizer_price_store.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('prices screen prefills saved prices and saves edits', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({
      'khaad_price_paisa_dap': 1660000,
    });
    final prefs = await SharedPreferences.getInstance();
    final store = FertilizerPriceStore(prefs: prefs);

    await tester.pumpWidget(
      MaterialApp(home: FertilizerPricesScreen(store: store)),
    );
    // The saved prices load asynchronously.
    for (var i = 0; i < 5; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }

    // DAP field is prefilled with the saved price in rupees.
    expect(find.text('16600'), findsOneWidget);

    // Enter a urea price and save.
    final ureaField = find.widgetWithText(TextField, 'یوریا (روپے/بوری)');
    expect(ureaField, findsOneWidget);
    await tester.enterText(ureaField, '4700');
    // The save button sits below the price grid — scroll it into view.
    final saveButton = find.text('قیمتیں محفوظ کریں');
    for (var i = 0; i < 10 && saveButton.evaluate().isEmpty; i++) {
      await tester.drag(find.byType(ListView), const Offset(0, -300));
      await tester.pump();
    }
    await tester.ensureVisible(saveButton);
    await tester.pump();
    await tester.tap(saveButton);
    for (var i = 0; i < 5; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }

    expect(await store.loadPrices(), {'dap': 1660000, 'urea': 470000});
  });
}
