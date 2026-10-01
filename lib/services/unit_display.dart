import 'unit_converter.dart';

/// Centralized unit display for Kisan Dost.
///
/// Before this service, each screen kept its own hardcoded unit list
/// (harvest used ['من','کلوگرام','ٹن','بوری','کسٹم'], inventory used a
/// different list) and its own ad-hoc "$value $unit" concatenation. This
/// class is the single source of truth for:
///
/// * the canonical picker list ([allUnits]) — the union of every unit the
///   app has ever offered, so no existing data becomes unpickable;
/// * formatting a quantity for display ([format]);
/// * choosing a display unit for a weight known only in kg
///   ([formatWeightKg]) — shows whole maunds as من (the unit farmers
///   think in), otherwise کلوگرام.
///
/// Conversions reuse [UnitConverter] (1 maund = 40 kg; package units need
/// the farmer-entered per-package weight and are never converted without
/// it). No new units are invented here.
///
/// Pure Dart: no Flutter imports, safe to use in tests and providers.
class UnitDisplay {
  /// Every unit the app offers, in picker order. Union of the harvest and
  /// inventory lists that existed before — nothing removed.
  static const List<String> allUnits = [
    'من',
    'کلوگرام',
    'گرام',
    'ٹن',
    'بوری',
    'پیکٹ',
    'بوتل',
    'لیٹر',
    'ملی لیٹر',
    'کسٹم',
  ];

  /// "40 من", "2.5 کلوگرام" — trims meaningless trailing zeros
  /// ("40.0" -> "40") but never rounds the value itself.
  static String format(double value, String unit) {
    return '${_trim(value)} $unit';
  }

  /// Display a weight known in kg. Whole maunds render as من; anything
  /// else as کلوگرام (sub-kilo as گرام). This is display-only — stored
  /// values keep the unit the farmer entered.
  static String formatWeightKg(double kg) {
    if (kg >= UnitConverter.maundInKg &&
        (kg % UnitConverter.maundInKg) == 0) {
      final maunds = kg ~/ UnitConverter.maundInKg;
      return '$maunds من';
    }
    if (kg > 0 && kg < 1) {
      final grams = (kg * 1000).round();
      return '$grams گرام';
    }
    return '${_trim(kg)} کلوگرام';
  }

  /// "40.0" -> "40", "2.50" -> "2.5". Keeps up to 2 decimal places —
  /// display trimming only, the underlying double is untouched.
  static String _trim(double value) {
    var s = value.toStringAsFixed(2);
    if (s.contains('.')) {
      s = s.replaceAll(RegExp(r'0+$'), '').replaceAll(RegExp(r'\.$'), '');
    }
    return s;
  }
}
