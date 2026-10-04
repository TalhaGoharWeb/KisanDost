# Kisan Dost — Privacy Audit (2026-10-04)

**Scope:** full offline privacy posture — network, analytics, telemetry, ads,
location, third-party SDKs, permissions, file access, logs, clipboard.
**Method:** read-only static audit (grep + manifest + pubspec review). No code modified.

## Verdict: PASS — no silent data exfiltration found

The app is genuinely offline. The one historical silent off-device flow
(Android Auto Backup uploading the plaintext DB) was already fixed
(`allowBackup=false`, commit `979ce62`).

## Per-area findings

### 1. Network requests — PASS
- `lib/`: zero hits for `HttpClient`, `Dio`, `WebSocket`, `Socket`, `http.get/post`,
  `connectivity_plus`, `InternetAddress` — and **zero `http(s)://` string literals
  anywhere** (not even in comments).
- `android/app/src/main/kotlin/`: zero hits for `HttpURLConnection`, `OkHttp`,
  `URL(`, `Socket`.
- Release manifest declares **no `INTERNET` permission** (`INTERNET` exists only in
  `src/debug` / `src/profile` manifests for the Flutter tool).

### 2. Analytics / telemetry / crash reporting — PASS
- `pubspec.yaml` / `pubspec.lock`: no `firebase_analytics`, `firebase_crashlytics`,
  `sentry`, `mixpanel`, `amplitude`, or any telemetry package.
- No Crashlytics/Sentry init in Dart or Kotlin.

### 3. Advertising SDKs — PASS
- No `google_mobile_ads` or any ads package.

### 4. Location access — PASS
- No `geolocator` / `location` package; no `ACCESS_FINE_LOCATION` /
  `ACCESS_COARSE_LOCATION` in any manifest.
- The word "location" in code (`lib/models/models.dart:72`,
  `lib/providers/farm_provider.dart:97`) is a **user-typed text field**
  (the farmer's written field/village name), never GPS.

### 5. Third-party SDKs — PASS (all local-only)
| Package | Used for | Data it could access vs. actual use |
|---|---|---|
| sqflite | On-device SQLite | Local DB only |
| path / path_provider | File paths, app dirs | Local filesystem only |
| shared_preferences | Settings (reminder toggles, snooze) | Local key-value only |
| provider | State management | In-memory only |
| intl / timezone | Formatting, alarm scheduling | Local |
| uuid / crypto | IDs, backup SHA-256 | Local computation |
| pdf / printing | Report generation | Local file; printing targets user-chosen local printers |
| share_plus | Share backup / reports / APK | Hands files to the **OS share sheet** — user picks the destination |
| file_picker | Backup import | Opens the **OS file picker** — user picks the file |
| flutter_local_notifications | Reminder notifications | Local notifications only |
| cupertino_icons / flutter_localizations | UI | None |

### 6. Permissions — PASS (all justified, none excessive)
Release manifest (`android/app/src/main/AndroidManifest.xml`):
`RECEIVE_BOOT_COMPLETED`, `VIBRATE`, `WAKE_LOCK`, `POST_NOTIFICATIONS`,
`SCHEDULE_EXACT_ALARM`, `USE_EXACT_ALARM`, `USE_FULL_SCREEN_INTENT`,
`REQUEST_IGNORE_BATTERY_OPTIMIZATIONS`, `FOREGROUND_SERVICE`,
`FOREGROUND_SERVICE_MEDIA_PLAYBACK` — every one serves the task-reminder/alarm
feature. No `INTERNET`, no location, no contacts, no storage permissions
(scoped app-private storage needs none).
- Plugin manifests add nothing new: `flutter_local_notifications` declares only
  `VIBRATE`/`POST_NOTIFICATIONS` (already declared); `share_plus`, `file_picker`,
  `printing` declare no permissions.

### 7. File access — PASS (every off-device transfer is an explicit user action)
- `lib/screens/backup_screen.dart:169` — share backup: user taps share →
  **OS share sheet**. `backup_screen.dart:179` — import backup: user taps import →
  **OS file picker** (`.db` filter), then `verifyBackup` before restore.
- `lib/screens/reports_screen.dart:114` — share CSV/PDF report: user taps share →
  file written to app-private `exports/` → **OS share sheet**.
- `MainActivity.shareApkFile()` — shares only the app's own APK
  (`context.packageCodePath`) via `FileProvider`; detailed FileProvider audit is
  covered separately by the Share APK audit.
- No background sync, no auto-upload, no silent writes outside app-private dirs.

### 8. Logs — PASS (no PII / financial data)
- Dart `debugPrint` sites (`task_provider.dart:129,240`, `alarm_screen.dart:100,158`,
  `settings_screen.dart:59,75,88,99,121`, `backup_service.dart:367`,
  `notification_service.dart:74,156`): all log **exception messages in error paths
  only** — no record contents, amounts, names, or credentials.
- `notification_service.dart:168` logs `response.payload`, which is only
  `taskId.toString()` (an integer) — no PII.
- Kotlin `Log.*`: task IDs, alarm IDs, broadcast actions, and error messages only.
  Never financial records, party names, or amounts.

### 9. Clipboard — PASS
- Zero `Clipboard` usage in `lib/`.

## Recommendations
1. **None required.** No data collection to remove, no permissions to drop.
2. Optional hardening (not privacy-critical): the remaining `debugPrint` error-path
   logs are harmless but could be gated behind `kDebugMode` for tidier release
   logcats. Left as-is per read-only scope.
3. Keep `allowBackup=false` (already set) — this was the single privacy-critical
   finding of the broader audit and it is fixed.
