# assets/i18n — LEGACY DRAFT, not used by the app

These JSON files (`en.json`, `ur.json`, `ur_rom.json`, ~900 keys each) are a
stale translation draft from the original template. They are:

- **not declared** in `pubspec.yaml` assets (never bundled into the APK),
- **not read** by any code in `lib/`,
- **stale**: they reference features that were never built and predate the
  party-ledger, batai, backup, and reports modules (only ~12% of current
  UI strings appear verbatim).

They are kept in the repo as reference material for a future real
translation pass — not deleted, so no translator work is lost.

The living string source is `lib/l10n/strings.dart` (documented
convention: Urdu-first, shared strings centralized). The locale mechanism
is `lib/l10n/app_locale.dart` (Urdu default, direction from locale via
`flutter_localizations`, no forced global RTL).
