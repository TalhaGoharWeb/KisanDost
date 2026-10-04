# Kisan Dost — Crash Safety & Error Handling Audit (2026-10-04)

Auditor: crash-safety subagent. Scope: every screen/service read; fixes applied
only in `lib/services/`, `lib/database/`, `lib/utils/`, Kotlin. Screen/widget/
provider/l10n fixes are specified below as exact deferred patches (another
agent is editing those files right now).

## What was FIXED (in editable scope)

### F1 — HIGH — `NotificationService.init()` could prevent app launch
**File:** `lib/services/notification_service.dart`

`main.dart` does `await NotificationService().init()` before `runApp()`.
`init()` had no try/catch: a single throw from `initialize()`,
`requestNotificationsPermission()`, or `getNotificationAppLaunchDetails()`
(on some OEMs these throw) meant the app never launched at all.

**Fix:** `init()` now delegates to `_initUnsafe()` inside try/catch and never
throws — a notification failure is logged and the app launches without
reminders rather than dying.

### F2 — MEDIUM — Background notification-action handler could throw silently
**File:** `lib/services/notification_service.dart`

`notificationTapBackground` (the `@pragma('vm:entry-point')` background
isolate handler for "complete"/"snooze" actions) did DB + prefs + scheduling
with no try/catch. An error there is invisible and the farmer's tap silently
does nothing.

**Fix:** wrapped in try/catch → `_notificationTapBackgroundUnsafe`; failures
are logged via `debugPrint`.

### F3 — MEDIUM — Corrupt database = permanently dead app
**File:** `lib/database/db_helper.dart`

`_initDatabase()` had no recovery: if `kisan_dost.db` is not a valid SQLite
file (truncated copy, zeroed bytes), `openDatabase` throws on every launch
and the app is bricked with no recovery path.

**Fix:** on open failure, check the SQLite magic header (`"SQLite format 3\0"`).
If the file exists but the magic is wrong/absent → quarantine it to
`kisan_dost.db.corrupt.<timestamp>` (PRESERVED, never deleted) and open a
fresh database so the app stays usable. Any other failure (disk full,
permissions) is rethrown — renaming a healthy DB aside would be data loss.

### F4 — LOW — `cancelNotification` could throw
**File:** `lib/services/notification_service.dart` — now best-effort with
try/catch (cancelling a reminder must never break task CRUD).

### F5 — NEW — Central Urdu error catalogue
**File:** `lib/utils/error_messages.dart` (new)

- `FailureKind` enum: database, storage, missingRecord, corruptData,
  notification, alarm, permission, sharing, import, unknown.
- `urduMessageFor()`: one simple, friendly Urdu string per kind. Each names
  a safe recovery path; none leaks technical details.
- `guessKind()`: best-effort classification from an unknown error.
- `friendlyErrorMessage()`: logs the technical error to `debugPrint` ONLY
  and returns the Urdu string.
- `showFriendlyError(context, error, [kind])`: drop-in replacement for every
  `'…: $e'` snackbar in screens.

**Tests:** `test/unit/error_messages_test.dart` (7/7 pass) — pins that every
kind has Urdu text, no leakage markers, and the raw error never appears in
the user message.

## Verified already-safe (no change needed)

| Area | Evidence |
|---|---|
| Kotlin `AlarmReceiver.onReceive` | try/catch/finally, wakeLock released, `taskId == -1` rejected, extras null-defaulted |
| Kotlin `BootReceiver.onReceive` | action allowlist, `goAsync()` with try/catch/finally |
| `AlarmScheduler.rescheduleAllAlarms` | honors `reminders_enabled` pref; malformed reminder offsets filtered via `toIntOrNull` |
| `maybeAutoBackup` | never throws (try/catch; test-pinned) |
| Demo enter/exit | partial-insert cleanup in catch + rethrow; exit failures caught per-table |
| `cancelTaskNotifications` | already best-effort try/catch |
| `scheduleTaskNotifications` | per-alarm try/catch with exact→inexact fallback |
| Backup/restore/import | `BackupException` carries Urdu messages; verify-before-touch |
| `export_service.dart` | pure functions; unknown IDs → empty cells, never crash |
| `pdf_report_service.dart` | throws Urdu `Exception`s by design for callers to surface |
| `recycle_bin_service.dart` | null-safe casts with fallbacks (throws only if DB itself fails — caller must catch; see D4) |
| `onboarding_service.dart` | trivial prefs reads; failure surfaces at call site (see D5) |

## DEFERRED FIXES — apply after the input-validation agent finishes

These are in `lib/screens/`, `lib/providers/`, `lib/main.dart` (not editable
right now). Each is a precise patch.

### D1 — 13 raw-exception leaks in snackbars (HIGH — user asked: never show technical errors)

Every `'...: $e'` below must become `showFriendlyError(context, e, FailureKind.<kind>)`
with `import '../../utils/error_messages.dart';` (adjust relative path per file).

| File:line | Current | Replacement call |
|---|---|---|
| `theka_form_screen.dart:285` | `Text('معاہدہ محفوظ کرنے میں خرابی پیش آئی: $e')` | `showFriendlyError(context, e, FailureKind.database)` |
| `backup_screen.dart:57` | `_showSnack('بیک اپ فہرست لوڈ کرنے میں خرابی: $e', …)` | `showFriendlyError(context, e, FailureKind.database)` |
| `backup_screen.dart:94` | `_showSnack('بیک اپ بنانے میں خرابی: $e', …)` | `showFriendlyError(context, e, FailureKind.storage)` |
| `backup_screen.dart:112` | `_showSnack('ترتیب محفوظ کرنے میں خرابی: $e', …)` | `showFriendlyError(context, e, FailureKind.database)` |
| `backup_screen.dart:163` | `_showSnack('بیک اپ حذف کرنے میں خرابی: $e', …)` | `showFriendlyError(context, e, FailureKind.storage)` |
| `backup_screen.dart:173` | `_showSnack('شیئر کرنے میں خرابی: $e', …)` | `showFriendlyError(context, e, FailureKind.sharing)` |
| `backup_screen.dart:192` | `_showSnack('فائل درآمد کرنے میں خرابی: $e', …)` | `showFriendlyError(context, e, FailureKind.import)` |
| `backup_screen.dart:403` | `_showSnack('بحالی میں خرابی: $e', …)` | `showFriendlyError(context, e, FailureKind.corruptData)` |
| `backup_screen.dart:424` | `_showSnack('بحالی میں خرابی: $e', …)` | `showFriendlyError(context, e, FailureKind.corruptData)` |
| `reports_screen.dart:140` | `_snack('خرابی: $e', …)` | `showFriendlyError(context, e, FailureKind.unknown)` |
| `onboarding_screen.dart:65` | `Text('کوشش ناکام ہوئی: $e')` | `showFriendlyError(context, e, FailureKind.unknown)` |
| `settings_screen.dart:226` | `Text('خرابی: $e', …)` | `showFriendlyError(context, e, FailureKind.database)` |
| `settings_screen.dart:306` | `Text('ڈیمو شروع نہ ہو سکا: $e')` | `showFriendlyError(context, e, FailureKind.database)` |

Note: `_showSnack`/`_snack` take a String today — either change them to accept
the call above, or inline `ScaffoldMessenger` calls. Simplest: replace the
whole `_showSnack('…: $e', color)` expression with
`showFriendlyError(context, e, FailureKind.x)`.

### D2 — `reports_screen.dart` `_saveAndShare` has NO try/catch (HIGH)
**File:** `lib/screens/reports_screen.dart:108-115`

```dart
Future<void> _saveAndShare(String filename, List<int> bytes) async {
  final docs = await getApplicationDocumentsDirectory();
  final dir = Directory('${docs.path}/exports');
  if (!await dir.exists()) await dir.create(recursive: true);
  final file = File('${dir.path}/$filename');
  await file.writeAsBytes(bytes, flush: true);
  await SharePlus.instance.share(
    ShareParams(files: [XFile(file.path)], text: 'کسان دوست رپورٹ'),
  );
}
```

Disk-full during `writeAsBytes`, or no app to handle the share intent, throws
unhandled → crash. **Replace with:**

```dart
Future<void> _saveAndShare(String filename, List<int> bytes) async {
  try {
    final docs = await getApplicationDocumentsDirectory();
    final dir = Directory('${docs.path}/exports');
    if (!await dir.exists()) await dir.create(recursive: true);
    final file = File('${dir.path}/$filename');
    await file.writeAsBytes(bytes, flush: true);
    await SharePlus.instance.share(
      ShareParams(files: [XFile(file.path)], text: 'کسان دوست رپورٹ'),
    );
  } catch (e) {
    showFriendlyError(context, e, FailureKind.sharing);
  }
}
```

### D3 — Three providers fetch without try/catch (MEDIUM)
`main.dart` calls these unawaited (`..fetchX()`); a DB failure at launch is
an unhandled async error.

- `lib/providers/activity_provider.dart:60` `fetchActivities()`
- `lib/providers/inventory_provider.dart:27` `fetchInventory()`
- `lib/providers/ushr_provider.dart:56` `fetchUshrRecords()`

**Patch pattern** (wrap the body, keep the last good list on failure):

```dart
Future<void> fetchInventory() async {
  try {
    final db = await _executor(testExecutor);
    final maps = await db.query('inventory', orderBy: 'id DESC');
    _inventoryList = List.generate(maps.length, (i) => Inventory.fromMap(maps[i]));
  } catch (e) {
    debugPrint('KisanDost: fetchInventory failed: $e');
  }
  notifyListeners();
}
```

(The other 9 providers already catch internally — verified.)

### D4 — `recycle_bin_service.listDeleted` throws on DB failure (LOW)
**File:** `lib/services/recycle_bin_service.dart` — in my scope, but the
right fix is at the call site (recycle bin screen): wrap the `await
RecycleBinService.listDeleted()` call in try/catch and show
`showFriendlyError(context, e, FailureKind.database)` with an empty-list
fallback. (Service throwing is fine if the screen catches.)

### D5 — `main.dart` hardening (MEDIUM)
**File:** `lib/main.dart` (not editable right now)

1. `await NotificationService().init()` is now safe (F1: init never throws),
   but defense-in-depth: wrap the whole `main()` body in
   `runZonedGuarded(..., (e, s) => debugPrint(...))` so no unhandled async
   error can ever red-screen the app.
2. The 12 `..fetchX()` provider calls are unawaited by design; with D3
   applied they can't throw. No change needed beyond D3.

### D6 — `inventory_screen.dart` FutureBuilder has no error state (LOW)
**File:** `lib/screens/inventory_screen.dart:664-667` — `snapshot.data ?? []`
silently swallows errors. Add:

```dart
if (snapshot.hasError) {
  return const Padding(
    padding: EdgeInsets.all(16),
    child: Text('لین دین لوڈ نہیں ہو سکا — دوبارہ کوشش کریں'),
  );
}
```

## Test report

- `flutter analyze` on `lib/utils/error_messages.dart`,
  `lib/services/notification_service.dart`, `lib/database/db_helper.dart`:
  **clean**.
- `test/unit/error_messages_test.dart` (new): **7/7 pass**.
- `test/db/migration_test.dart` (covers db_helper changes): **pass**.
- Full suite intentionally not run (other agents active).

## Residual risks

- A corrupted DB whose header is *valid* SQLite but whose pages are torn
  will still fail at first query, not at open — the quarantine only catches
  the "not a database at all" case. The backup/restore safety net
  (pre-restore backups, integrity checks) remains the recovery path there.
- `showFriendlyError` needs a valid `BuildContext`; background isolates
  (already guarded) can't show UI by design.
