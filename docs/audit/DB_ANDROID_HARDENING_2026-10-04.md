# Kisan Dost — Offline Database & Android Security Audit (2026-10-04)

Auditor: senior Flutter/Android security review (assisted). Scope: the entire
offline/local data layer and Android configuration. A parallel accounting /
business-logic audit and an input-validation audit ran separately.

## Method

- Full read of `lib/database/db_helper.dart` (schema, 15 migrations, CRUD),
  `lib/services/backup_service.dart`, `lib/services/restore_service.dart`,
  `android/` manifest + all Kotlin (Alarm/Boot receivers, scheduler, service,
  both DatabaseHelpers), FileProvider paths, permissions, ProGuard/R8.
- Grep sweeps: `rawQuery`/`rawDelete` interpolation (SQLi), `print`/`debugPrint`
  (log leaks), `transaction(` coverage, `DateTime.now()` consistency,
  `http`/socket usage, `clearTables` callers.
- Two independent subagent audits (native Android layer; Dart data layer)
  cross-checked against manual findings.

## Findings fixed (commit 979ce62)

| # | Severity | Finding | Fix |
|---|----------|---------|-----|
| 1 | **High** | `android:allowBackup` unset → default `true`. Android Auto Backup silently uploaded the farmer's **plaintext** SQLite DB (financial records, party ledger, udhaar) to Google Drive. | `android:allowBackup="false"` in manifest. The app has its own backup feature; nothing else changes. |
| 2 | **High** | `restoreReplace` copied the backup **directly over** the live DB. Crash / full disk mid-copy → truncated live database (total data loss; safety backup existed but recovery was manual). | Atomic replace: copy to `$livePath.restore_tmp`, then `rename` (atomic on ext4/f2fs). Temp cleaned up on failure. |
| 3 | **Medium** | Kotlin `DatabaseHelper` (native alarm path) opened the DB **without** `PRAGMA foreign_keys=ON`. FK enforcement is per-connection in SQLite; the Dart side had it, the native side didn't — a hidden inconsistency. | `PRAGMA foreign_keys=ON` after open. |
| 4 | **Medium** | Kotlin `getIncompleteTasks()` / `getTask()` ignored `deleted_at`. After a reboot, **soft-deleted (trashed) tasks had their alarms rescheduled** — the farmer's deleted reminder came back to life. Dart side already filtered; native side didn't. | `AND deleted_at IS NULL` in both queries, matching Dart semantics. |
| 5 | **Low** | `BootReceiver` is exported (required) but acted on **any** broadcast action — a malicious app could trigger spurious alarm rescheduling. | Validate the action against the expected set; ignore anything else. |
| 6 | **Low** | `restoreMerge` interpolated PRAGMA-derived column names as `"$c"` without escaping embedded quotes (crafted-backup identifier breakout). | Escape `"` → `""` in identifiers. Defense in depth. |
| 7 | **Low** | No network security config; `usesCleartextTraffic` unset. App makes **zero** network calls (verified by grep). | `usesCleartextTraffic="false"` + explicit `network_security_config.xml` denying cleartext, so a future dependency can't silently downgrade to HTTP. |

## Verified already-safe (no change needed)

- **No SQL injection**: every `rawQuery`/`rawDelete`/`where:` uses `?` placeholders; the one `${}` hit is a safe placeholder-list expansion in demo code.
- **Migrations**: run inside sqflite's transaction (atomic); idempotent (`IF NOT EXISTS`, try/catch ALTERs); FK toggled off/on only inside the v12 rebuild with `legacy_alter_table`.
- **FK enforcement**: `ON` via `onConfigure` on the Dart connection; schema declares `ON DELETE CASCADE / SET NULL / RESTRICT` appropriately (financial rows are `SET NULL`, never cascade-deleted — deliberate).
- **Money**: integer paisa everywhere; no `double` money arithmetic in providers.
- **Transactions**: all multi-record provider writes wrapped in `db.transaction`.
- **Timestamps**: consistent local `DateTime.now().toIso8601String()` (correct for single-user offline).
- **IDs**: `INTEGER PRIMARY KEY AUTOINCREMENT` (no reuse).
- **Soft delete**: `deleted_at` on expenses/sales/harvests/tasks/parties; list queries filter it; recycle bin restore supported.
- **Wipe**: `clearAllTables` is behind an explicit non-dismissible confirmation dialog.
- **Backup**: WAL checkpoint + close before copy; SHA-256 sidecars; `verifyBackup` (magic bytes, `integrity_check`, required tables, version gate) runs **before** any restore touches the live DB; safety backup taken pre-restore.
- **No sensitive logging**: zero `print`/`debugPrint` in `lib/`; Kotlin logs carry task IDs only, never financial data.
- **PendingIntents**: all `FLAG_IMMUTABLE`; cancel-before-schedule prevents duplicate alarms.
- **Components**: only `MainActivity` (launcher) and the boot receiver are exported; `AlarmActivity`/`AlarmService`/`AlarmReceiver`/`FileProvider` are not.
- **R8**: minify + ProGuard rules configured for release.
- **Debug manifest**: only dev `INTERNET` permission; release has none.
- **Demo mode**: tracks inserted IDs; exit deletes exactly the demo rows.

## Deliberately NOT done (with reasons)

- **SQLCipher / at-rest encryption**: would require key management UX (password the farmer must remember, or Keystore-wrapped key with lockout risk). The realistic exposures are (1) cloud auto-backup — fixed with `allowBackup=false`; (2) user-shared backups/exports — the farmer's explicit choice; (3) rooted device — out of scope. Encryption would add farmer-facing complexity for little gain. Revisit if a Play Data Safety review demands it.
- **WAL journal mode**: default rollback-journal is crash-safe; the Kotlin/Dart concurrent windows are single-statement and microseconds wide. WAL would help marginally; not worth the behavior change now.
- **Removing `SCHEDULE_EXACT_ALARM`** (keeping `USE_EXACT_ALARM`): both serve the core reminder feature; dropping one risks subtle behavior changes on some OEMs. Documented, not changed.
- **Narrowing FileProvider paths**: FileProvider only serves URIs the app explicitly shares; broad paths are standard for `share_plus` and not exploitable alone. Left as-is.

## Verification (second pass)

- `flutter analyze` on changed Dart files: clean.
- `test/db/backup_restore_test.dart`: **15/15 pass**, including the new test `atomic replace leaves no temp file; live DB passes integrity`.
- Manifest + network config: XML-validated; attributes confirmed present.
- Kotlin: brace-balanced; changes are minimal and mirror verified patterns.
- Full `flutter test` suite: deferred until the parallel accounting/input-validation agents finish (they are editing providers/screens now; running the suite concurrently would produce spurious results). Re-run before release.

## Remaining follow-ups (for the user)

1. **Back up the release keystore + key.properties** (still owed) — encrypted USB + password manager.
2. **Real-device pass** of the reminder flow after reboot (verifies fix #4 end-to-end).
3. Re-run the **full test suite + CI** once the parallel audits land, then rebuild the release APK from the green commit.
