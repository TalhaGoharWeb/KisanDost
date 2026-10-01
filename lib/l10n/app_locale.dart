import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// App UI locale.
///
/// Urdu ('ur') is the default and currently the only fully-supported
/// locale. Text direction (RTL) comes from this locale through
/// `flutter_localizations` — NOT from a forced `Directionality` widget
/// (the old global RTL hack was removed in Phase 10; see main.dart).
///
/// The [supported] list is the seam for a future Roman-Urdu/English
/// toggle: adding a locale here plus translated [Strings] is all it
/// takes — no widget in the app hardcodes a text direction anymore.
class AppLocale extends ChangeNotifier {
  static const _prefsKey = 'app_locale';

  /// Locales the UI can actually render today.
  static const List<String> supported = ['ur'];

  Locale _locale = const Locale('ur');
  Locale get locale => _locale;

  String get code => _locale.languageCode;

  /// Load the saved locale (defaults to Urdu). Called once at startup;
  /// notifies so [MaterialApp.locale] rebuilds if it changed.
  Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    final code = prefs.getString(_prefsKey);
    if (code != null && code != _locale.languageCode) {
      if (supported.contains(code)) {
        _locale = Locale(code);
        notifyListeners();
      }
    }
  }

  /// Switch locale (persisted). Unsupported codes are ignored.
  Future<void> setLocale(String code) async {
    if (!supported.contains(code) || code == _locale.languageCode) return;
    _locale = Locale(code);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_prefsKey, code);
    notifyListeners();
  }
}
