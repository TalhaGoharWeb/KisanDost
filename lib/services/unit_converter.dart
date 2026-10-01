// Central unit conversion for Kisan Dost.
//
// Pure Dart — no Flutter imports — so it can be unit-tested anywhere.
//
// Rules (farmer-safety first):
// * Never hardcode a package weight. Converting a package unit (bag, bottle,
//   packet) to/from a weight unit requires the caller to supply
//   [weightPerUnitKg] — the weight of ONE package of that specific item,
//   entered by the farmer. Without it, conversion throws instead of guessing.
// * 1 maund = 40 kg (Pakistani standard).
// * Cross-family conversions (weight <-> volume, anything <-> count)
//   throw — they are physically meaningless without a density the app
//   does not know.

/// Thrown when a conversion is impossible or unsafe. [message] is Urdu,
/// suitable for showing directly to the farmer.
class UnitConversionException implements Exception {
  final String message;
  const UnitConversionException(this.message);

  @override
  String toString() => 'UnitConversionException: $message';
}

/// Thrown for inventory business-rule violations (overuse, missing item).
/// [message] is Urdu, suitable for showing directly to the farmer.
class InventoryException implements Exception {
  final String message;
  const InventoryException(this.message);

  @override
  String toString() => 'InventoryException: $message';
}

class UnitConverter {
  /// Pakistani standard: one maund is 40 kg.
  static const double maundInKg = 40.0;

  /// Canonical weight units -> kg per unit.
  static const Map<String, double> _weightInKg = {
    'kg': 1.0,
    'g': 0.001,
    'maund': maundInKg,
    'ton': 1000.0,
  };

  /// Canonical volume units -> litre per unit.
  static const Map<String, double> _volumeInLitre = {'l': 1.0, 'ml': 0.001};

  /// Canonical package units. Their weight is per-item data, never assumed.
  static const Set<String> _packageUnits = {'bag', 'bottle', 'packet'};

  /// Urdu + English aliases -> canonical key. Unknown strings throw.
  static String canonical(String unit) {
    final u = unit.trim();
    switch (u) {
      // weight
      case 'kg':
      case 'KG':
      case 'کلوگرام':
      case 'کلو':
        return 'kg';
      case 'g':
      case 'G':
      case 'Gram':
      case 'گرام':
        return 'g';
      case 'maund':
      case 'Maund':
      case 'من':
        return 'maund';
      case 'ton':
      case 'Ton':
      case 'ٹن':
        return 'ton';
      // volume
      case 'l':
      case 'L':
      case 'Litre':
      case 'لیٹر':
        return 'l';
      case 'ml':
      case 'ML':
      case 'ملی لیٹر':
      case 'ملی':
        return 'ml';
      // package
      case 'bag':
      case 'Bag':
      case 'بوری':
        return 'bag';
      case 'bottle':
      case 'Bottle':
      case 'بوتل':
        return 'bottle';
      case 'packet':
      case 'Packet':
      case 'پیکٹ':
        return 'packet';
      // count
      case 'piece':
      case 'Piece':
      case 'عدد':
      case 'دانا':
        return 'piece';
      default:
        throw UnitConversionException('نامعلوم اکائی: "$u"');
    }
  }

  /// True when the unit is a package unit (bag / bottle / packet) whose
  /// weight must be supplied per item.
  static bool isPackageUnit(String unit) {
    try {
      return _packageUnits.contains(canonical(unit));
    } on UnitConversionException {
      return false;
    }
  }

  /// Urdu display name of a canonical unit key.
  static String urduName(String canonicalUnit) {
    switch (canonicalUnit) {
      case 'kg':
        return 'کلوگرام';
      case 'g':
        return 'گرام';
      case 'maund':
        return 'من';
      case 'ton':
        return 'ٹن';
      case 'l':
        return 'لیٹر';
      case 'ml':
        return 'ملی لیٹر';
      case 'bag':
        return 'بوری';
      case 'bottle':
        return 'بوتل';
      case 'packet':
        return 'پیکٹ';
      case 'piece':
        return 'عدد';
      default:
        return canonicalUnit;
    }
  }

  /// Converts [quantity] from [fromUnit] to [toUnit].
  ///
  /// [weightPerUnitKg] is the farmer-entered weight of ONE package of the
  /// specific item being converted. It is REQUIRED for any conversion
  /// between a package unit and a weight unit; omitting it throws instead
  /// of guessing (the old code assumed 1 bag = 50 kg — that assumption
  /// silently corrupted deductions).
  static double convert(
    double quantity,
    String fromUnit,
    String toUnit, {
    double? weightPerUnitKg,
  }) {
    final String from = canonical(fromUnit);
    final String to = canonical(toUnit);
    if (from == to) return quantity;

    final bool fromWeight = _weightInKg.containsKey(from);
    final bool toWeight = _weightInKg.containsKey(to);
    final bool fromVolume = _volumeInLitre.containsKey(from);
    final bool toVolume = _volumeInLitre.containsKey(to);
    final bool fromPackage = _packageUnits.contains(from);
    final bool toPackage = _packageUnits.contains(to);

    // weight <-> weight
    if (fromWeight && toWeight) {
      return quantity * _weightInKg[from]! / _weightInKg[to]!;
    }
    // volume <-> volume
    if (fromVolume && toVolume) {
      return quantity * _volumeInLitre[from]! / _volumeInLitre[to]!;
    }
    // piece <-> piece
    if (from == 'piece' && to == 'piece') return quantity;

    // package <-> weight needs the per-item package weight.
    if ((fromPackage && toWeight) || (fromWeight && toPackage)) {
      if (weightPerUnitKg == null || weightPerUnitKg <= 0) {
        throw UnitConversionException(
          'اس آئٹم کا فی ${urduName(fromPackage ? from : to)} وزن (کلوگرام) درج کریں، '
          'تب ہی اکائی تبدیل ہو سکتی ہے',
        );
      }
      final double qtyInKg =
          fromPackage
              ? quantity * weightPerUnitKg
              : quantity * _weightInKg[from]!;
      if (toPackage) return qtyInKg / weightPerUnitKg;
      return qtyInKg / _weightInKg[to]!;
    }

    // package <-> package of different kinds, weight <-> volume,
    // volume <-> package, anything <-> piece: no safe bridge.
    throw UnitConversionException(
      '"${urduName(from)}" سے "${urduName(to)}" میں تبدیلی ممکن نہیں',
    );
  }
}
