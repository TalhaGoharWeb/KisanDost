import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:kisan_dost/services/fertilizer_price_store.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('save then load round-trips prices in paisa', () async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final store = FertilizerPriceStore(prefs: prefs);

    expect(await store.loadPrices(), isEmpty);

    await store.savePrices({'dap': 1660000, 'urea': 470000});
    expect(await store.loadPrices(), {'dap': 1660000, 'urea': 470000});

    // Saving a smaller map removes the products left out.
    await store.savePrices({'urea': 480000});
    expect(await store.loadPrices(), {'urea': 480000});

    // Zero/negative prices are never stored.
    await store.savePrices({'dap': 0, 'urea': -5});
    expect(await store.loadPrices(), isEmpty);
  });
}
