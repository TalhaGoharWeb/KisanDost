# Kisan Dost — Offline-First Reliability Audit (2026-10-04)

Auditor: senior mobile reliability review (assisted subagent). Read-only audit;
no source files modified (other agents own them). New hermetic tests added
under `test/offline/`.

**Overall: the app is genuinely offline-first.** Zero network code, zero push,
zero background workers. Two low-severity FLAGs below; everything else PASS.

## 1. Network waits — PASS

Grep over `lib/` + `android/` for `connectivity_plus`, `InternetAddress.lookup`,
`HttpClient`, `Dio`, `WebSocket`, `Socket.connect`, `FirebaseMessaging`, FCM,
`WorkManager`, `.timeout(`: **zero hits**. The `http(s)://` literal count is
zero (only `android.resource://` URIs). Release manifest has no `INTERNET`
permission (debug/profile only, for the Flutter tool).

The four `Future.delayed` hits are fixed UX delays (3s splash branding,
settings refresh), not network waits. Nothing blocks UI on connectivity.

## 2. First launch without internet — PASS with one LOW flag

`main()` (`lib/main.dart:23-31`):
- `NotificationService().init()` — internally try/caught (`_initUnsafe`,
  `notification_service.dart:168-174`); a failure logs and continues.
- `maybeAutoBackup()` — `unawaited` + `.catchError` (`main.dart:27-30`):
  never blocks launch, never crashes.
- All 14 pubspec dependencies initialize from local resources: sqflite (local
  file), path_provider (local dirs), shared_preferences (local XML),
  flutter_local_notifications (local), `timezone` (bundled tz database —
  `tz.initializeTimeZones()` needs no network), pdf/crypto (pure Dart),
  share_plus/file_picker (OS intents, on-demand only).
- 11 providers fire `fetch*` at startup; 7 of 11 guard with try/catch + Urdu
  error state (see §6 for the 4 that don't).

**FLAG (low):** `OnboardingService.shouldShowOnboarding()`
(`lib/services/onboarding_service.dart:11-14`) has no try/catch. If
`SharedPreferences.getInstance()` ever throws, the splash's delayed callback
throws unhandled and the app sits on the splash forever. Same shape in
`DemoDataService.load()` (`demo_data_service.dart:88-92`) and
`AppLocale.load()` (`app_locale.dart:27-36`) — though those two degrade more
gracefully (banner/locale just stay default).
**Precise fix** (`onboarding_service.dart`):
```dart
static Future<bool> shouldShowOnboarding() async {
  try {
    final prefs = await SharedPreferences.getInstance();
    return !(prefs.getBool(onboardingDoneKey) ?? false);
  } catch (_) {
    return true; // fail open: replaying onboarding is always safe
  }
}
```

## 3. Normal use offline — PASS

CRUD (all providers → sqflite), backup/restore (local file copy + SHA-256),
CSV/PDF export (pure-Dart `pdf` package), share flows (OS share sheet via
`share_plus`), backup import (file picker → local copy → `verifyBackup`).
No code path requires connectivity; verified by the zero-network grep in §1.

## 4. Device restart — PASS (with one INFO)

`BootReceiver` (`BootReceiver.kt:14-34`): exported (required), validates the
broadcast action, uses `goAsync()` + background thread, try/catch, and
`finish()` in `finally` — it cannot ANR or crash the boot sequence. Calls
`AlarmScheduler.rescheduleAllAlarms()`, which needs no network and now honors
the farmer's `reminders_enabled` toggle (fixed by the alarm audit).

**Direct Boot note (INFO, no change needed):** the receiver is *not*
`directBootAware`, so the `LOCKED_BOOT_COMPLETED` intent-filter entry
(`AndroidManifest.xml:60`) can never fire — it is dead but harmless. This is
actually the *correct* posture: the database lives in credential-protected
storage, which is unreadable before first unlock, so rescheduling must wait
for `BOOT_COMPLETED` anyway. AlarmManager likewise defers non-directBootAware
alarms until unlock. Everything resumes consistently after first unlock.
Optional cleanup: remove the dead filter line to avoid confusion.

## 5. App force-close / removed from recents — PASS

Alarms are `AlarmManager.setAlarmClock` entries owned by the OS — they survive
kills and recents-swipes. There is no in-memory-only alarm state: every alarm
is re-derivable from the `tasks` table, and app launch re-runs the (idempotent)
reschedule. Unsaved form input is the only in-memory state, and losing it on
kill is acceptable.

## 6. Low storage — FLAG (low-medium)

A full disk makes SQLite throw (`SQLITE_FULL` / "database or disk is full" /
ENOSPC). The crash-safety agent's `lib/utils/error_messages.dart` already maps
these to a friendly Urdu message (`FailureKind.storage`: "فون کی میموری بھری
ہوئی لگتی ہے۔ کچھ جگہ خالی کر کے دوبارہ کوشش کریں۔") via `guessKind()` — the
utility exists and other agents are wiring it in.

**FLAG:** 4 startup fetch paths are unguarded, so a disk-full (or any DB-open)
failure at launch becomes an unhandled async error instead of that message:
- `lib/providers/inventory_provider.dart:27` `fetchInventory()`
- `lib/providers/activity_provider.dart:60` `fetchActivities()`
- `lib/providers/ushr_provider.dart:56` `fetchUshrRecords()`
- `lib/providers/farm_provider.dart:67` `fetchFields()` (note: `fetchFarms`
  at line 29 *is* guarded — copy its pattern)

**Precise fix** (per method, following the `fetchFarms` pattern):
```dart
Future<void> fetchInventory() async {
  try {
    ...existing body...
  } catch (_) {
    _errorMessage = 'فہرست لوڈ نہیں ہو سکی۔ دوبارہ کوشش کریں۔';
    notifyListeners();
  }
}
```
(Requires an `_errorMessage` field + getter where missing; `farm_provider`
already has one to copy.)

Backup creation under low storage: `createBackup` copies then hashes; a
mid-copy ENOSPC throws → caught by `maybeAutoBackup`'s try/catch (silent
skip) or surfaces as `BackupException` (Urdu) in the manual flow. No partial
backup is left behind: `verifyBackup` runs before any restore consumes it.

## 7. Database migration — PASS

- All migrations run inside sqflite's `onUpgrade` transaction: a kill
  mid-migration rolls back, and the next open retries from the old version.
  No migration step touches the network (pure SQL, verified by reading
  `migrateV9ToV10`…`migrateV14ToV15`).
- `_initDatabase` (`db_helper.dart:51-77`, added by the crash-safety audit):
  a non-SQLite file is quarantined (timestamped rename, never deleted) and
  the app starts fresh; any *other* failure (disk full, permissions) is
  rethrown — it never renames a healthy database aside.
- Hermetic coverage exists: `test/db/migration_test.dart` exercises the real
  migration SQL via FFI with no app singleton, filesystem, or plugins.

## 8. Interrupted writes — PASS (new tests)

Spot-check of 10 providers (`activity`, `inventory` ×3, `theka`, `ushr`,
`party`, `batai`, `expense`, `harvest`): every multi-step write runs inside
`db.transaction(...)`. SQLite's rollback journal therefore guarantees a kill
mid-write leaves no torn state. New hermetic tests
(`test/offline/interrupted_write_test.dart`) prove the mechanism:
- throw inside a transaction → earlier writes in the same transaction are
  undone;
- a clearTables-style multi-table wipe that fails midway → all tables keep
  their rows (atomicity);
- a completed transaction → all writes durable.

## 9. Notification / alarm scheduling — PASS

100% local: `AlarmManager.setAlarmClock` (Doze-exempt by design) with
`setAndAllowWhileIdle` fallback when the exact-alarm permission is denied
(`AlarmScheduler.kt:134-138`); `flutter_local_notifications` for the
notification UI. Zero push/FCM dependencies in pubspec or native code.
Every native scheduling call is try/caught on the Dart side and degrades
gracefully (alarm audit verified the paths).

## 10. Long periods without opening the app — PASS

- `setAlarmClock` alarms are exempt from Doze/App Standby — they fire even
  after weeks of inactivity (this is exactly what `setAlarmClock` is for).
- `maybeAutoBackup` runs only on app open (documented in `main.dart:26`).
  There is no WorkManager — acceptable for a farmer app: backups are a
  best-effort convenience, and the manual backup flow always exists.
- Battery-optimization exemption is user-opt-in via settings (Play-policy
  legitimate for an alarm app).

## 11. Stale first-launch flags — PASS

Kill mid-onboarding → `onboarding_done` is never written →
`shouldShowOnboarding()` returns true → onboarding replays. The failure
direction is always safe: the flag is written only at the *end* of the flow,
so there is no half-onboarded stuck state. Same for demo mode (`demo_active`
written after rows are inserted); the cosmetic banner-linger edge is owned by
the input-validation agent per the auth audit.

## New tests

`test/offline/interrupted_write_test.dart` — 3 tests, hermetic FFI:
transaction rollback on simulated kill; atomic multi-table wipe under
mid-way failure; full commit on success.

`test/offline/offline_startup_test.dart` — 3 tests, hermetic:
onboarding flag round-trip (fresh → true, completed → false, kill-mid-flow →
true/safe); `FarmProvider.fetchFarms` against a broken executor does not
throw and sets a non-empty Urdu `errorMessage`; `DatabaseHelper.schemaVersion`
is sane.

Run (one file at a time, per instructions):
```
cd ~/workspace/kisan-dost
export PATH="$HOME/workspace/tooling/flutter/bin:$PATH"
export LD_LIBRARY_PATH="/tmp/sqlitelib:$LD_LIBRARY_PATH"
flutter test test/offline/interrupted_write_test.dart
flutter test test/offline/offline_startup_test.dart
```
(LD_LIBRARY_PATH works around the sandbox's missing `libsqlite3.so`; the
symlink was created during this audit's verification runs.)

## Residual / out of scope

- Real-device verification still needed: reboot → alarms fire; weeks-idle →
  alarm fires; disk-full → Urdu message shown (sandbox cannot fill disks or
  run the Android UI).
- The 4 unguarded fetches (§6) and the onboarding try/catch (§2) are
  precise, mechanical fixes for the owning agents — no redesign involved.
