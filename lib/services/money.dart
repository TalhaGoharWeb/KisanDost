/// Precise money value object for Kisan Dost.
///
/// All currency in the app is stored and computed as INTEGER paisa
/// (1 rupee = 100 paisa). Floating point (`double`) must never be used for
/// money: binary floating point cannot represent most decimal fractions
/// exactly (e.g. 0.1 + 0.2 != 0.3), which silently corrupts financial sums.
///
/// Rounding policy (the only places rounding ever happens):
/// 1. [Money.parse] REJECTS inputs with more than 2 decimal places — it
///    throws instead of silently rounding.
/// 2. [Money.fromRupees] and quantity x rate multiplications round half
///    AWAY from zero (Dart's [double.round] semantics), matching the
///    `CAST(ROUND(x * 100) AS INTEGER)` used in the DB v12 backfill.
/// 3. Everything else (addition, subtraction, int multiplication,
///    comparisons) is exact integer arithmetic — no rounding at all.
///
/// Pure Dart: no Flutter imports, safe to use in tests and providers.
class Money {
  /// Amount in paisa. Always an exact integer.
  final int paisa;

  const Money(this.paisa);

  /// Zero rupees.
  static const Money zero = Money(0);

  /// Exact construction from paisa.
  factory Money.fromPaisa(int paisa) => Money(paisa);

  /// Convert a rupee amount to paisa, rounding half away from zero.
  ///
  /// Only for legacy interop and tests — new code should build paisa
  /// integers directly or use [Money.parse] on user input.
  factory Money.fromRupees(num rupees) => Money((rupees * 100).round());

  /// Parse farmer-typed input into paisa.
  ///
  /// Accepts:
  /// - Western digits (0-9) and Urdu/Persian digits (۰۱۲۳۴۵۶۷۸۹)
  /// - thousands separators (commas), spaces
  /// - a single decimal point with up to 2 decimals
  /// - optional "روپے" / "Rs" / "روپے" suffix text
  ///
  /// Throws [MoneyParseException] (Urdu message) on empty input, garbage,
  /// negative amounts, or more than 2 decimal places.
  factory Money.parse(String input) {
    final cleaned = _clean(input);
    if (cleaned.isEmpty) {
      throw MoneyParseException('رقم درج کریں');
    }
    final match = RegExp(r'^(\d+)(?:\.(\d+))?$').firstMatch(cleaned);
    if (match == null) {
      throw MoneyParseException('درست رقم درج کریں (مثلاً 1250 یا 1250.50)');
    }
    final decimals = match.group(2) ?? '';
    if (decimals.length > 2) {
      // Deliberate: never silently round the farmer's money.
      throw MoneyParseException(
        'رقم میں دو سے زیادہ اعشاریہ نہیں ہو سکتے (مثلاً 1250.50)',
      );
    }
    final rupees = int.parse(match.group(1)!);
    final paisaPart = decimals.padRight(2, '0');
    final total = rupees * 100 + int.parse(paisaPart);
    return Money(total);
  }

  /// Strip everything that is not part of a plain decimal number.
  ///
  /// Keeps Western digits and at most the '.' the strict regex in [parse]
  /// validates; anything else (second '.', '-', letters) fails that regex
  /// and is rejected with an Urdu message.
  static String _clean(String input) {
    var s = input.trim();
    // Urdu/Persian digits → Western digits.
    const urdu = '۰۱۲۳۴۵۶۷۸۹';
    const western = '0123456789';
    for (var i = 0; i < 10; i++) {
      s = s.replaceAll(urdu[i], western[i]);
    }
    // Drop the Urdu currency word and Latin "Rs"/"Rs." markers.
    s = s.replaceAll('روپے', '').replaceAll(RegExp(r'Rs\.?'), '');
    // Drop thousands separators and whitespace; keep digits and '.'.
    s = s.replaceAll(',', '').replaceAll(RegExp(r'\s+'), '');
    return s;
  }

  /// Whole rupees, truncating any paisa remainder.
  int get rupees => paisa ~/ 100;

  /// Remaining paisa after whole rupees (0..99, sign follows [paisa]).
  int get paisaRemainder => paisa.remainder(100);

  bool get isZero => paisa == 0;
  bool get isNegative => paisa < 0;
  bool get isPositive => paisa > 0;

  Money operator +(Money other) => Money(paisa + other.paisa);
  Money operator -(Money other) => Money(paisa - other.paisa);
  Money operator *(int multiplier) => Money(paisa * multiplier);
  Money operator -() => Money(-paisa);

  bool operator <(Money other) => paisa < other.paisa;
  bool operator >(Money other) => paisa > other.paisa;
  bool operator <=(Money other) => paisa <= other.paisa;
  bool operator >=(Money other) => paisa >= other.paisa;

  @override
  bool operator ==(Object other) => other is Money && other.paisa == paisa;

  @override
  int get hashCode => paisa.hashCode;

  /// Urdu-friendly display: "1,250 روپے", "1,250.50 روپے".
  ///
  /// Thousands separators, decimals shown only when non-zero (always
  /// exactly 2 digits then). Negative amounts render as "-1,250 روپے".
  String format() {
    final negative = paisa < 0;
    final abs = paisa.abs();
    final whole = abs ~/ 100;
    final rest = abs % 100;
    final grouped = _groupThousands(whole);
    final core =
        rest == 0 ? grouped : '$grouped.${rest.toString().padLeft(2, '0')}';
    return '${negative ? '-' : ''}$core روپے';
  }

  static String _groupThousands(int n) {
    final digits = n.toString();
    final buf = StringBuffer();
    for (var i = 0; i < digits.length; i++) {
      if (i > 0 && (digits.length - i) % 3 == 0) buf.write(',');
      buf.write(digits[i]);
    }
    return buf.toString();
  }

  /// Exact double for legacy interop only. Prefer [format] / [paisa].
  @Deprecated('Use paisa or format(); double money loses precision')
  double toRupeesDouble() => paisa / 100.0;

  @override
  String toString() => 'Money($format())';
}

/// Thrown by [Money.parse]; [message] is always Urdu, safe to show
/// directly in a snackbar / validation error.
class MoneyParseException implements Exception {
  final String message;
  MoneyParseException(this.message);

  @override
  String toString() => 'MoneyParseException: $message';
}
