/// Area units used by Pakistani farmers: acre, kanal, marla.
///
/// Pure Dart — no Flutter imports — so it can be unit-tested anywhere.
///
/// Standards (Punjab revenue system):
/// * 1 acre = 8 kanal
/// * 1 kanal = 20 marla
/// * 1 acre = 160 marla = 43,560 sq ft
///
/// Kisan Dost stores field sizes in acres (`fields.size_acres`); this
/// converter is display/input only and never changes stored data.
library;

enum AreaUnit {
  acre('ایکڑ'),
  kanal('کنال'),
  marla('مرلہ');

  final String urduLabel;
  const AreaUnit(this.urduLabel);

  /// How many acres one unit of this type is.
  double get acresPerUnit => switch (this) {
    AreaUnit.acre => 1.0,
    AreaUnit.kanal => 1.0 / 8.0,
    AreaUnit.marla => 1.0 / 160.0,
  };
}

class AreaConverter {
  static const double kanalPerAcre = 8.0;
  static const double marlaPerKanal = 20.0;
  static const double marlaPerAcre = 160.0;

  static double toAcres(double value, AreaUnit unit) =>
      value * unit.acresPerUnit;

  static double fromAcres(double acres, AreaUnit unit) =>
      acres / unit.acresPerUnit;

  static double convert(double value, AreaUnit from, AreaUnit to) =>
      fromAcres(toAcres(value, from), to);
}
