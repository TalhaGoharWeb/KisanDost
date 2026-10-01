import '../l10n/strings.dart';

/// Quantity parsing for farmer-typed numeric input (amounts of produce,
/// areas, weights — anything that is NOT money).
///
/// Mirrors the safety rules of [Money.parse]: accepts Western digits (0-9)
/// and Urdu/Persian digits (۰۱۲۳۴۵۶۷۸۹), thousands separators, and a single
/// decimal point — and THROWS an Urdu [QuantityParseException] on empty,
/// malformed, or (for [parsePositive]) non-positive input instead of
/// silently storing a wrong value.
///
/// Why this exists: `double.tryParse` rejects Urdu digits and comma
/// separators ("۱۲۳" or "1,000" failed validation), and plain `double.parse`
/// after a weak validator let negative quantities through. Every quantity
/// input in the app must go through here.
///
/// Pure Dart: no Flutter imports, safe to use in tests and providers.
class QuantityParseException implements Exception {
  final String message;
  const QuantityParseException(this.message);

  @override
  String toString() => 'QuantityParseException: $message';
}

class Quantity {
  /// Parse any real-valued quantity. Negative values are allowed here only
  /// for the rare legitimate case; prefer [parsePositive].
  static double parse(String input) {
    final cleaned = _clean(input);
    if (cleaned.isEmpty) {
      throw const QuantityParseException(Strings.quantityRequired);
    }
    final value = double.tryParse(cleaned);
    if (value == null || value.isNaN || value.isInfinite) {
      throw const QuantityParseException('صرف نمبر درج کریں (مثلاً 40 یا 2.5)');
    }
    return value;
  }

  /// Parse a quantity that must be greater than zero (harvest yield, area,
  /// weight, price inputs). Rejects zero and negatives with an Urdu error —
  /// a negative harvest or a zero-area farm is never valid data.
  static double parsePositive(String input) {
    final value = parse(input);
    if (value <= 0) {
      throw const QuantityParseException('مقدار صفر سے زیادہ ہونی چاہیے');
    }
    return value;
  }

  /// Non-throwing variant for live previews: null when the input is not
  /// yet a valid quantity.
  static double? tryParse(String input) {
    try {
      return parse(input);
    } on QuantityParseException {
      return null;
    }
  }

  /// Same cleaning rules as [Money.parse]: Urdu/Persian digits become
  /// Western digits; commas and whitespace are dropped; letters and extra
  /// dots fail the numeric check in [parse].
  static String _clean(String input) {
    var s = input.trim();
    const urdu = '۰۱۲۳۴۵۶۷۸۹';
    const western = '0123456789';
    for (var i = 0; i < 10; i++) {
      s = s.replaceAll(urdu[i], western[i]);
    }
    s = s.replaceAll(',', '').replaceAll(RegExp(r'\s+'), '');
    return s;
  }
}
