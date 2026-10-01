/// Centralized user-facing strings for Kisan Dost.
///
/// CONVENTION (Phase 10):
/// * The app is Urdu-first. Screen-local Urdu strings stay where they are —
///   do NOT churn every screen to reference this file.
/// * Strings used in 5+ places (action words, common field labels,
///   shared validation messages) live here as constants so wording
///   changes happen once. New shared strings MUST be added here, not
///   copy-pasted across screens.
/// * Roman Urdu is the secondary display form where it already exists in
///   the UI; English is tertiary. A future locale toggle will swap these
///   constants per [AppLocale] — never branch on locale inside widgets.
///
/// NOTE on `assets/i18n/*.json`: those files are a stale legacy draft
/// (they reference unbuilt features and predate the party/batai/reports
/// modules) and are NOT read by the app. See `assets/i18n/README.md`.
/// This file is the living string source until a real ARB migration
/// happens.
class Strings {
  Strings._();

  // ---- actions ----
  static const String cancel = 'کینسل';
  static const String save = 'محفوظ کریں';
  static const String delete = 'حذف کریں';
  static const String done = 'مکمل ہو گیا';

  // ---- common fields ----
  static const String date = 'تاریخ';
  static const String noteOptional = 'نوٹ (اختیاری)';
  static const String selectCrop = 'فصل منتخب کریں';

  // ---- shared validation ----
  static const String quantityRequired = 'مقدار درج کریں';
  static const String nameRequired = 'نام درج کریں';
}
