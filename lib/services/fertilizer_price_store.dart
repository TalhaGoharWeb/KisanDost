import 'package:shared_preferences/shared_preferences.dart';

/// Saved fertilizer prices (per bag), entered by the farmer from
/// their own market — the SFRI-style «قیمتیں» sheet, persisted on the
/// phone so cost estimates and combination ranking stay correct
/// without re-typing prices on every visit.
///
/// Prices live in SharedPreferences as integer paisa per product id.
/// A product with no saved price is simply absent from the map —
/// never treated as zero cost anywhere in the app.
class FertilizerPriceStore {
  static const String _prefix = 'khaad_price_paisa_';

  final SharedPreferences? _prefsOverride;

  const FertilizerPriceStore({SharedPreferences? prefs})
    : _prefsOverride = prefs;

  Future<SharedPreferences> _prefs() async =>
      _prefsOverride ?? await SharedPreferences.getInstance();

  /// All saved prices: product id → price per bag in paisa.
  Future<Map<String, int>> loadPrices() async {
    final prefs = await _prefs();
    final prices = <String, int>{};
    for (final key in prefs.getKeys()) {
      if (!key.startsWith(_prefix)) continue;
      final value = prefs.getInt(key);
      if (value != null && value > 0) {
        prices[key.substring(_prefix.length)] = value;
      }
    }
    return prices;
  }

  /// Replaces the saved prices with [prices] (product id → paisa).
  /// Products missing from the map have their saved price removed.
  Future<void> savePrices(Map<String, int> prices) async {
    final prefs = await _prefs();
    final stale = prefs
        .getKeys()
        .where((k) => k.startsWith(_prefix))
        .toList();
    for (final key in stale) {
      await prefs.remove(key);
    }
    for (final entry in prices.entries) {
      if (entry.value > 0) {
        await prefs.setInt('$_prefix${entry.key}', entry.value);
      }
    }
  }
}
