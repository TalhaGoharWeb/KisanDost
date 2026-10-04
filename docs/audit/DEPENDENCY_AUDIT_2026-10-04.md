# Kisan Dost — Dependency Audit (2026-10-04)

Auditor: dependency/security review (assisted). Local toolchain: Flutter 3.35.5
(note: task brief said 3.47.5; the sandbox tooling at `~/workspace/tooling/flutter`
is 3.35.5 — CI may differ; findings below are SDK-independent).

## Verdict up front

- **0 known vulnerabilities** (OSV.dev queried for all 19 direct+key transitive
  packages at their locked versions — clean).
- **0 abandoned packages** (every direct dep published within the last ~13 months;
  most within the last 30 days; `provider` 6.1.5+1 is the oldest at 2025-08-19 and
  is a mature stable package, not abandoned).
- **0 plugins with excessive permissions** (checked each plugin's
  `android/src/main/AndroidManifest.xml`: file_picker declares no permissions,
  share_plus none, flutter_local_notifications only VIBRATE + POST_NOTIFICATIONS —
  all appropriate for a reminder app).
- **3 unused dependencies removed**, 2 safe upgrades applied, all verified.

## Changes made (uncommitted — for parent review)

| Change | Reason | Verification |
|--------|--------|--------------|
| Removed `cupertino_icons: ^1.0.8` | Zero imports in lib/ or test/ (template leftover; app is Material-only) | `flutter analyze`: no new issues |
| Removed `uuid: ^4.5.3` | Zero usage; DB uses integer autoincrement IDs (stays as **transitive** dep of `share_plus_platform_interface` — unavoidable, harmless) | `flutter analyze`: no new issues |
| Removed `printing: ^5.14.3` | Zero imports; PDF generation uses `pdf` directly. Also drops transitive `http`, `http_parser`, `pdf_widget_wrapper` and printing's own FileProvider from the build | `flutter analyze`: no new issues |
| `pdf` 3.11.3 → **3.12.0** | Minor, resolvable within `^3.11.3` | `test/widget/pdf_report_test.dart`: **4/4 pass** |
| `shared_preferences` 2.5.3 → **2.5.5** | Patch, resolvable within `^2.5.3` | analyze clean; patch-level, no API change |

`flutter pub get` also regenerated linux/macos/windows plugin registrants
(printing's entries removed) — expected.

`flutter analyze` after changes: 104 issues, **none** related to these changes
(no uuid/printing/cupertino/pdf/shared_preferences/unresolved-import hits);
the 104 are in-progress work from parallel agents (e.g. new test files being
written). Full-suite re-run deferred to the parent's final pass.

## Per-package table (locked versions after changes)

| Package | Locked | Used for (verified) | Status |
|---------|--------|---------------------|--------|
| sqflite 2.4.2 | DB engine, 19 files | current-ish (2.4.4 latest patch) | ⚠️ patch behind — left alone, see below |
| path 1.9.1 | pure-Dart path joins (3 files) | current | ✅ |
| path_provider 2.1.5 | app-documents dir for DB/backups (2 files) | patch behind (2.1.6; SDK-constrained) | ✅ |
| provider 6.1.5+1 | state management (32 files) | current | ✅ |
| intl 0.20.2 | date/number formatting (14 files) | patch behind (0.20.3; SDK-constrained) | ✅ |
| pdf 3.12.0 | Urdu P&L/expense PDF reports | **upgraded**, tested | ✅ |
| shared_preferences 2.5.5 | settings/reminder prefs (16 files) | **upgraded** | ✅ |
| flutter_local_notifications 18.0.1 | task reminders (2 files) | major behind (22.3.1) | ⚠️ see below |
| timezone 0.9.4 | tz-aware alarm scheduling (2 files) | minor behind (resolvable 0.10.1) | ⚠️ see below |
| crypto 3.0.7 | SHA-256 backup sidecars | current | ✅ |
| share_plus 12.0.2 | share backups/CSVs/PDFs (2 files) | major behind (13.3.1) | ⚠️ see below |
| file_picker 11.0.3 | import backup file (1 file) | major behind (13.1.0) | ⚠️ see below |
| flutter_lints 5.0.0 (dev) | analysis_options | major behind (6.0.0) | ⚠️ dev-only, see below |
| sqflite_common_ffi 2.3.7+1 (dev) | tests only (11 files) | minor behind (2.4.3) | ⚠️ test-only, see below |

## Deliberately NOT upgraded (recommendations for the parent/user)

1. **flutter_local_notifications 18 → 22** (major): touches the alarm subsystem
   currently under parallel audit. v19–22 changelogs need review (Android 16
   notification changes). Recommend a dedicated upgrade pass with real-device
   alarm testing, not bundled into this audit.
2. **share_plus 12 → 13** (major): share flows are farmer-facing; needs
   changelog review + share-sheet testing on device.
3. **file_picker 11 → 13** (major): backup-import is safety-critical; needs
   changelog review + import testing.
4. **timezone 0.9.4 → 0.10.1** (minor, resolvable): safe on paper, but the
   alarm-scheduling agent is actively editing that code path — deferred to
   avoid mid-flight interference. Recommend upgrading right after that agent
   lands (it's a one-line constraint bump + `pub upgrade`).
5. **sqflite 2.4.2 → 2.4.4** (patch): normally safe, but the DB layer is under
   active parallel audit; native-driver change mid-audit adds risk. Recommend
   after audits land.
6. **flutter_lints 5 → 6** (major, dev-only): new lint sets can fail CI's
   `analyze`; upgrade only with a full analyze pass and fix-up commit.
7. **intl 0.20.2 / path_provider 2.1.5**: patch updates exist but are pinned by
   the Flutter SDK constraint — they move when the SDK moves. No action.

## Other findings

- **No duplicate functionality.** `path` (pure path strings) vs `path_provider`
  (platform directories) are complementary, not duplicates. `pdf` vs (removed)
  `printing`: printing was dead weight — removed.
- **No analytics/crash-reporting/network packages** — consistent with the
  offline-first posture (also verified: no `http` usage in lib/ after printing
  removal dropped the transitive `http` package entirely).
- **Android native versions** (settings.gradle.kts): AGP **8.7.0**, Kotlin
  **2.2.0**. compileSdk/targetSdk/minSdk come from the Flutter SDK:
  **36 / 36 / 24** under Flutter 3.35.5 — current (Android 16 API 36; exceeds
  Play's target-SDK requirements). AGP 8.7.0 is not the newest AGP, but it is
  what the sandbox can build with (newer AGP versions hit the proxy/HTTP-client
  issue documented in memory); do not bump without a working build pipeline.
  Native impl deps (appcompat 1.6.1, constraintlayout 2.1.4, material 1.9.0,
  desugar_jdk_libs 2.0.4) are older but stable and vulnerability-free per OSV;
  bumping them is optional maintenance, not a security need.
- `uuid` survives only as a transitive dep via `share_plus_platform_interface`
  — no action needed.

## Residual risks / follow-ups

- Re-run `flutter pub outdated` quarterly; the four deferred majors
  (flutter_local_notifications, share_plus, file_picker, flutter_lints) are the
  ones to watch.
- When the parallel agents finish, run the FULL suite + `flutter analyze` on a
  clean tree before release; the 104 current analyze issues belong to in-flight
  agent work, not to these dependency changes.
