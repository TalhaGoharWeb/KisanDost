# Kisan Dost — "Delete All Data" Hardening (2026-10-04)

## Flow (settings_screen.dart)

1. Settings row tap → `_showWipeConfirmDialog()` (explicit AlertDialog, NOT a single tap action).
2. Dialog: title "تصدیق کریں", body warns in Urdu that ALL records (lands, crops,
   expenses, harvests, alarms) will be deleted **forever** and cannot be undone
   ("ہمیشہ کے لیے حذف... یہ عمل واپس نہیں لیا جا سکتا").
3. Two distinct actions: grey "منسوخ کریں" (dismiss) vs red "جی ہاں، حذف کریں".
   Tapping outside the dialog dismisses it (safe direction).
4. `_wipeAllData()`: shows non-dismissible loader → cancels every scheduled
   alarm → `clearAllTables()` → reloads all providers → success snackbar.

Single-tap wipe is impossible: the destructive path always passes through the
confirmation dialog.

## Fix applied (commit pending)

**`DatabaseHelper.clearTables` was not transactional.** 19 sequential
`db.delete()` calls with no transaction: a crash or disk-full mid-wipe left a
half-emptied database (orphaned rows, broken FK references).

- `clearTables` now runs inside `db.transaction(...)` when given a real
  `Database`; falls back to direct deletes for `DatabaseExecutor` (tests).
- Either all 19 tables are emptied or the entire wipe rolls back.
- `flutter analyze`: clean.

## Verified data remnants

| Store | After wipe | Verdict |
|---|---|---|
| SQLite tables (farms, fields, crops, inventory, expenses, harvests, sales, activities, thekas, batai, parties, ushr, tasks, audit_log) | All emptied in one transaction | ✅ |
| Scheduled alarms (AlarmManager + notifications) | Cancelled per task before wipe | ✅ |
| SharedPreferences (`reminders_enabled`, `snooze_duration`, `vibration_enabled`, `alarm_sound_enabled`, reminder offsets) | **Kept** | ✅ deliberate — these are app *settings*, not farmer data; the farmer keeps their alarm preferences |
| Backup files (`backups/`) | **Kept** | ✅ deliberate — the farmer's explicit safety copies; deleting them would destroy the recovery path |
| Temp/cache files | None created by the app (`getTemporaryDirectory` unused) | ✅ nothing to clean |
| Exported CSVs/PDFs (shared via system share sheet) | Outside app storage | ✅ not app data |

## Notes

- The error snackbar shows a raw exception string (`خرابی: $e`); message
  wording for error paths belongs to the input-validation audit (in progress).
- No changes to the dialog were needed: it already meets the two-step,
  simple-Urdu, irreversible-warning requirements.
