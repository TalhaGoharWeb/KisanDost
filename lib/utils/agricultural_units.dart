/// Unit conversions used by farm records.
///
/// Area is stored canonically in acres. Mass is stored canonically in kg,
/// using the Pakistan market convention of 1 maund (man) = 40 kg. A bag,
/// bottle, or packet is treated as a count unit because pack sizes vary by
/// product; it must not be converted to a weight/volume without pack metadata.
class AgriculturalUnits {
  AgriculturalUnits._();

  static const double kanalPerAcre = 8;
  static const double marlaPerAcre = 160;
  static const double kgPerMaund = 40;

  static double areaToAcres(double value, String unit) {
    _requireFiniteNonNegative(value, 'area');
    final normalized = _normalize(unit);
    final divisor = switch (normalized) {
      'acre' => 1.0,
      'kanal' => kanalPerAcre,
      'marla' => marlaPerAcre,
      _ => throw ArgumentError.value(unit, 'unit', 'Unsupported area unit'),
    };
    return value / divisor;
  }

  static double areaFromAcres(double acres, String unit) {
    _requireFiniteNonNegative(acres, 'area');
    final normalized = _normalize(unit);
    final multiplier = switch (normalized) {
      'acre' => 1.0,
      'kanal' => kanalPerAcre,
      'marla' => marlaPerAcre,
      _ => throw ArgumentError.value(unit, 'unit', 'Unsupported area unit'),
    };
    return acres * multiplier;
  }

  static double convert(double quantity, String fromUnit, String toUnit) {
    _requireFiniteNonNegative(quantity, 'quantity');
    final from = _normalize(fromUnit);
    final to = _normalize(toUnit);
    if (from == to) return quantity;

    final fromMass = _massInKg[from];
    final toMass = _massInKg[to];
    if (fromMass != null && toMass != null) {
      return quantity * fromMass / toMass;
    }

    final fromVolume = _volumeInLitres[from];
    final toVolume = _volumeInLitres[to];
    if (fromVolume != null && toVolume != null) {
      return quantity * fromVolume / toVolume;
    }

    final fromArea = _areaInAcres[from];
    final toArea = _areaInAcres[to];
    if (fromArea != null && toArea != null) {
      return quantity * fromArea / toArea;
    }

    throw ArgumentError(
      'Cannot convert "$fromUnit" to "$toUnit" without a product-specific pack size.',
    );
  }

  static String _normalize(String unit) {
    final value = unit.trim().toLowerCase().replaceAll(RegExp(r'\s+'), ' ');
    return switch (value) {
      'acre' || 'acres' || 'ایکڑ' || 'ایکڑز' => 'acre',
      'kanal' || 'kanals' || 'کنال' => 'kanal',
      'marla' || 'marlas' || 'مرلہ' || 'مرلے' => 'marla',
      'kg' ||
      'kilogram' ||
      'kilograms' ||
      'کلو' ||
      'کلوگرام' ||
      'کلو گرام' => 'kg',
      'g' || 'gram' || 'grams' || 'گرام' => 'g',
      'ton' || 'tons' || 'tonne' || 'tonnes' || 'ٹن' => 'ton',
      'maund' || 'mann' || 'من' || 'منّ' => 'maund',
      'l' || 'liter' || 'litre' || 'liters' || 'litres' || 'لیٹر' => 'l',
      'ml' || 'milliliter' || 'millilitre' || 'ملی لیٹر' || 'ملی لیٹر' => 'ml',
      'bag' || 'bags' || 'بوری' || 'بوریاں' => 'bag',
      'bottle' || 'bottles' || 'بوتل' || 'بوتلیں' => 'bottle',
      'packet' || 'packets' || 'پیکٹ' => 'packet',
      _ => value,
    };
  }

  static const Map<String, double> _massInKg = {
    'kg': 1,
    'g': 0.001,
    'ton': 1000,
    'maund': kgPerMaund,
  };

  static const Map<String, double> _volumeInLitres = {'l': 1, 'ml': 0.001};

  static const Map<String, double> _areaInAcres = {
    'acre': 1,
    'kanal': 1 / kanalPerAcre,
    'marla': 1 / marlaPerAcre,
  };

  static void _requireFiniteNonNegative(double value, String name) {
    if (!value.isFinite || value < 0) {
      throw ArgumentError.value(
        value,
        name,
        'Must be a finite, non-negative number',
      );
    }
  }
}
