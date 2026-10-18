import 'package:kisan_dost/l10n/strings.dart';
import 'package:kisan_dost/services/money.dart';
import 'package:kisan_dost/services/quantity.dart';

/// Shared form-field validators for farmer-facing screens.
///
/// Every message is simple Urdu — never technical, never English.
/// These wrap [Money.parse] / [Quantity.parse] and additionally guard the
/// holes those parsers can't cover on their own:
///
/// * Absurdly large money input (e.g. 30 digits) overflows the 64-bit int
///   inside `Money.parse`, which throws a raw `FormatException` instead of
///   the Urdu `MoneyParseException`. Every money entry point here
///   pre-checks the digit count so that can never reach the user.
/// * Absurd quantities / counts get a friendly "too big" message instead
///   of being stored.
///
/// Use these in every new form; migrate old validators to them when
/// touching a screen.
class FieldValidators {
  FieldValidators._();

  /// Max digits accepted in a money field: 999,999,999,999 روپے — far
  /// above any real farm transaction, far below 64-bit overflow.
  static const int maxMoneyDigits = 12;

  /// Generic ceiling for quantities (acres, kg, bags, ...). Anything
  /// above this is a typo, not a harvest.
  static const double maxQuantity = 1e12;

  /// Names/notes longer than this are almost certainly pasted garbage.
  static const int maxTextLength = 200;

  static const String _urduDigits = '۰۱۲۳۴۵۶۷۸۹';

  /// Counts Western + Urdu/Persian digits in [input].
  static int digitCount(String input) {
    var n = 0;
    for (var i = 0; i < input.length; i++) {
      final c = input[i];
      final code = c.codeUnitAt(0);
      if ((code >= 0x30 && code <= 0x39) || _urduDigits.contains(c)) n++;
    }
    return n;
  }

  /// Non-throwing money parse: returns null on ANY invalid input,
  /// including the 64-bit overflow that `Money.parse` reports as a raw
  /// `FormatException`. For dialogs without a [Form].
  static Money? tryMoney(String input) {
    if (digitCount(input) > maxMoneyDigits) return null;
    try {
      return Money.parse(input);
    } on MoneyParseException {
      return null;
    } on FormatException {
      return null;
    }
  }

  /// Validator for required money fields (prices, costs, wages, amounts).
  static String? money(
    String? value, {
    String emptyMessage = 'رقم درج کریں',
    bool positive = false,
  }) {
    final v = value?.trim() ?? '';
    if (v.isEmpty) return emptyMessage;
    if (digitCount(v) > maxMoneyDigits) {
      return 'رقم بہت بڑی ہے — درست رقم درج کریں';
    }
    late final Money m;
    try {
      m = Money.parse(v);
    } on MoneyParseException catch (e) {
      return e.message;
    } on FormatException {
      return 'درست رقم درج کریں';
    }
    if (positive && m.paisa <= 0) return 'رقم صفر سے زیادہ ہونی چاہیے';
    return null;
  }

  /// Validator for required quantity fields (area, weight, harvest, ...).
  static String? quantity(
    String? value, {
    bool positive = true,
    String? emptyMessage,
    double? max,
  }) {
    final v = value?.trim() ?? '';
    if (v.isEmpty) return emptyMessage ?? Strings.quantityRequired;
    late final double q;
    try {
      q = positive ? Quantity.parsePositive(v) : Quantity.parse(v);
    } on QuantityParseException catch (e) {
      return e.message;
    }
    if (q > (max ?? maxQuantity)) {
      return 'مقدار بہت بڑی ہے — درست مقدار درج کریں';
    }
    return null;
  }

  /// Validator for whole-number counts (labourers, installments, ...).
  static String? wholeCount(
    String? value, {
    String? emptyMessage,
    int min = 1,
    int? max,
  }) {
    final v = value?.trim() ?? '';
    if (v.isEmpty) return emptyMessage ?? 'تعداد درج کریں';
    final q = Quantity.tryParse(v);
    if (q == null || q != q.roundToDouble()) {
      return 'صرف پورا عدد درج کریں (مثلاً 5)';
    }
    // Hard ceiling before toInt(): absurd magnitudes saturate to int64max in
    // Dart instead of throwing, which would silently corrupt downstream
    // arithmetic (e.g. wage x count). Reject first, always.
    // (Red-team audit 2026-10-04.)
    if (q > 9e18) {
      return 'تعداد بہت زیادہ ہے — درست تعداد درج کریں';
    }
    final n = q.toInt();
    if (n < min) return 'تعداد $min سے کم نہیں ہو سکتی';
    if (max != null && n > max) {
      return 'تعداد بہت زیادہ ہے — درست تعداد درج کریں';
    }
    return null;
  }

  /// Validator for required free-text fields (names, titles).
  static String? text(
    String? value, {
    String? emptyMessage,
    int maxLength = maxTextLength,
  }) {
    final v = value?.trim() ?? '';
    if (v.isEmpty) return emptyMessage ?? Strings.nameRequired;
    if (v.length > maxLength) return 'نام بہت لمبا ہے — مختصر نام لکھیں';
    return null;
  }

  /// Validator for percentage fields (0–100).
  static String? percent(String? value, {String? emptyMessage}) {
    final v = value?.trim() ?? '';
    if (v.isEmpty) return emptyMessage ?? 'فیصد درج کریں';
    final p = Quantity.tryParse(v);
    if (p == null || p < 0 || p > 100) {
      return 'صحیح فیصد (0-100) درج کریں';
    }
    return null;
  }

  /// Loose Pakistani phone check: empty is OK (optional field); otherwise
  /// 10–15 digits after stripping spaces/dashes/+.
  static String? phoneOptional(String? value) {
    final v = value?.trim() ?? '';
    if (v.isEmpty) return null;
    final digits = v.replaceAll(RegExp(r'[^0-9]'), '');
    if (digits.length < 10 || digits.length > 15) {
      return 'فون نمبر درست نہیں لگتا — دوبارہ دیکھیں';
    }
    return null;
  }

  /// Strict Pakistani *mobile* check for quick-add flows: empty is OK
  /// (optional field). Otherwise the number must be a Pakistani mobile —
  /// 03xx-xxxxxxx (11 digits), optionally with a +92/0092 country prefix.
  /// Spaces, dashes and Urdu/Persian digits are tolerated; landlines and
  /// foreign numbers are rejected.
  ///
  /// The prefix check is deliberately limited to "starts with 03" (rather
  /// than policing operator codes) so newly allocated series are never
  /// wrongly rejected.
  static String? phonePkOptional(String? value) {
    final v = value?.trim() ?? '';
    if (v.isEmpty) return null;
    if (_pkMobileLocal(_phoneDigits(v)) == null) {
      return 'فون نمبر درست نہیں — 03 سے شروع ہونے والا 11 ہندسوں کا پاکستانی موبائل نمبر لکھیں (مثلاً 03001234567)';
    }
    return null;
  }

  /// Reduces a phone string to Western digits only: Urdu/Persian digits
  /// (۰۱۲۳۴۵۶۷۸۹) are converted; everything else non-digit is dropped
  /// (spaces, dashes, '+', parentheses, ...).
  static String _phoneDigits(String input) {
    final sb = StringBuffer();
    for (var i = 0; i < input.length; i++) {
      final c = input[i];
      final code = c.codeUnitAt(0);
      if (code >= 0x30 && code <= 0x39) {
        sb.write(c);
      } else {
        final idx = _urduDigits.indexOf(c);
        if (idx >= 0) sb.write(String.fromCharCode(0x30 + idx));
      }
    }
    return sb.toString();
  }

  /// Reduces [digits] (Western digits only) to the local 11-digit
  /// 03xx-xxxxxxx form; null when the shape doesn't match a Pakistani
  /// mobile number.
  static String? _pkMobileLocal(String digits) {
    final String local;
    if (digits.length == 11) {
      local = digits;
    } else if (digits.length == 12 && digits.startsWith('923')) {
      local = '0${digits.substring(2)}';
    } else if (digits.length == 14 && digits.startsWith('00923')) {
      local = '0${digits.substring(4)}';
    } else {
      return null;
    }
    if (local.length != 11 || !local.startsWith('03')) return null;
    return local;
  }
}
