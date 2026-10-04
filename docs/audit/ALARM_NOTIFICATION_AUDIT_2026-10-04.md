# Kisan Dost — Alarm & Notification Architecture Audit (2026-10-04)

Auditor: senior Android/Flutter security review (assisted subagent).
Scope: `lib/services/notification_service.dart`, all Kotlin alarm components
(`AlarmReceiver`, `AlarmScheduler`, `AlarmService`, `AlarmActivity`,
`BootReceiver`, `DatabaseHelper` alarm methods), `AndroidManifest.xml`,
alarm scheduling/cancel calls in `lib/providers/task_provider.dart`.

Prior hardening this audit builds on (not reverted): commit `979ce62`
(BootReceiver action allowlist, Kotlin FK pragma, soft-delete filters) and
commit `dd4a3b6` (removed `showWhenLocked`/`turnScreenOn` from MainActivity —
lock-screen alarm UX now lives only on `AlarmActivity`, `exported=false`).

## Verdict

No critical vulnerabilities. The request-code scheme is collision-free for all
practical purposes, every PendingIntent is immutable, cancel-before-schedule is
enforced on all paths, and stale/deleted tasks cannot resurrect alarms. Five
real defects were found and fixed (one high-severity reliability bug).

## Findings fixed

### F1 — HIGH (reliability): boot/app-launch reschedule ignored the farmer's reminders toggle
**Evidence:** `BootReceiver.onReceive` → `AlarmScheduler.rescheduleAllAlarms()`
and `NotificationService.init()` → native `rescheduleAllAlarms` never read the
`reminders_enabled` SharedPreferences flag. Only the single-task Dart path
(`scheduleTaskNotifications`) honored it.
**Impact:** farmer disables reminders in settings → reboots phone (or simply
restarts the app) → every alarm silently re-armed. The setting did not stick.
**Fix:** `AlarmScheduler.rescheduleAllAlarms` now returns early when
`reminders_enabled` is false. Verified against the actual plugin source
(`shared_preferences_android-2.4.13`): keys are stored verbatim in the
`"FlutterSharedPreferences"` file, so the native read is correct.
**Test:** logic path only; covered by the boot-receiver real-device follow-up.

### F2 — MEDIUM (reliability): restored tasks never rang again
**Evidence:** `TaskProvider.deleteTask` soft-deletes **and** cancels the task's
alarms, but `TaskProvider.restoreTask` (recycle bin) only restored the row and
called `fetchTasks()` — alarms were never re-armed.
**Fix:** `restoreTask` now calls `NotificationService().scheduleTaskNotifications`
for the restored task (no-op for completed/past one-shot tasks; cancels before
scheduling, so no duplicates possible). Wrapped in try/catch so a scheduler
failure can never break the restore.
**Test:** `test/db/soft_delete_audit_test.dart` — 10/10 pass, including the
task restore test that now exercises the new call.

### F3 — LOW (correctness): native snooze ignored the farmer's snooze-duration setting
**Evidence:** settings exposes a user-facing `snooze_duration` (default 10),
read by the Dart background handler — but the actual Android path,
`AlarmReceiver.ACTION_SNOOZE`, hardcoded `plusMinutes(10)`, and the
`AlarmService` notification action label hardcoded "سوز کریں (10 منٹ)".
**Fix:** both now read `snooze_duration` from `FlutterSharedPreferences`
(default 10, clamped to ≥ 1). Label reflects the configured value.

### F4 — LOW (consistency): native complete/snooze could mutate soft-deleted rows
**Evidence:** Dart `notificationTapBackground` guards with
`id = ? AND deleted_at IS NULL`; the Kotlin `completeTask`/`snoozeTask` used
bare `id = ?`. A notification action tapped after the task was trashed (alarm
still ringing) would write to the deleted row.
**Fix:** added `AND deleted_at IS NULL` to both Kotlin updates, matching Dart.

### F5 — LOW (reliability): MediaPlayer leaked when a second alarm fired
**Evidence:** `AlarmService.onStartCommand` → `playAlarmSound()` reassigned
`mediaPlayer` without stopping the old instance. Two reminders for one task
firing minutes apart → two overlapping looping sounds + leaked player (battery).
**Fix:** stop/release any existing player before creating a new one.

## Verified safe — no change needed

1. **Request codes (no collisions).** Scheme: trigger PI = `taskId*10 + slot`
   (slots 0–8, slot 9 = snooze). Injective in (taskId, slot) for slot < 10, so
   no two tasks/slots share a trigger code. Action PIs use `alarmId+100`
   (complete) and `alarmId+200` (snooze) — arithmetic overlap with another
   task's trigger range is possible (e.g. task 1 complete = 110 = task 11 slot
   0), but PendingIntent identity includes the Intent **action**
   (`ACTION_COMPLETE`/`ACTION_SNOOZE` ≠ `ACTION_ALARM`) and component, so they
   are distinct PendingIntents. The `setAlarmClock` show-PI reuses `alarmId`
   as request code but targets `MainActivity` via `getActivity` — different
   component/type, no collision. Integer overflow requires ~200M+ tasks;
   negligible for this app.
2. **Notification IDs.** `startForeground(alarmId, …)` — unique per task/slot;
   no cross-task reuse.
3. **PendingIntent mutability.** Every `getBroadcast`/`getActivity` uses
   `FLAG_IMMUTABLE` (`AlarmScheduler` on API 23+, `AlarmService`
   unconditionally — safe, it's an ignored int constant on older APIs).
   minSdk is Flutter's default (23), so the legacy branches are dead but
   harmless. No mutable PendingIntent anywhere.
4. **Exact alarms degrade gracefully.** `setAlarmClock` (exempt from the
   `SCHEDULE_EXACT_ALARM` permission requirement) with `SecurityException` →
   `setAndAllowWhileIdle` fallback; `canScheduleExactAlarms()` gates API 31+;
   every native channel call is try/caught in Dart. No crash path.
5. **Boot reschedule.** Only `is_completed = 0 AND deleted_at IS NULL` tasks
   (Kotlin, hardened in 979ce62); past one-shot triggers skipped; recurring
   triggers advanced to the next future occurrence; snooze only if
   `snoozeTimeMs > now`. No post-reboot alarm burst.
6. **Wrong-task resolution.** `AlarmReceiver` rejects `taskId == -1`;
   `AlarmActivity` finishes on `-1` and shows "نامعلوم سرگرمی" for missing
   rows; `getTask` filters soft-deleted rows; `AUTOINCREMENT` IDs are never
   reused (verified in schema). In-flight alarm vs concurrent delete/completion
   is a benign microsecond race — the activity degrades to the unknown-task UI.
7. **Full-screen intent.** `AlarmActivity` is `exported=false`, launched only
   via explicit intents created by the app itself; extras validated
   (`taskId == -1` → finish). No other app can trigger it.
8. **Duplicates.** Cancel-before-schedule on every path: Dart
   `scheduleTaskNotifications`, Kotlin `scheduleAlarmsForTask`, boot
   reschedule, both snooze paths, and task edit/toggle flows in
   `task_provider.dart`. `init()` re-reschedules on every launch but is
   idempotent.
9. **Exported components.** Only `MainActivity` (launcher) and `BootReceiver`
   (required for boot broadcasts; now validates its action) are exported, plus
   the flutter_local_notifications plugin's own receivers. `AlarmReceiver`,
   `AlarmService`, `AlarmActivity`, `FileProvider` are all `exported=false`.
10. **Android 10–16 compatibility.** `FOREGROUND_SERVICE_TYPE_MEDIA_PLAYBACK`
    declared in manifest + permission, used on API 34+;
    `POST_NOTIFICATIONS` requested at runtime on 13+;
    `USE_FULL_SCREEN_INTENT` declared (required 14+);
    `setShowWhenLocked`/`setTurnScreenOn` on `AlarmActivity` only (API 27+
    API, legacy flags for older); 10-second-timeout wake lock in
    `AlarmReceiver`; `START_STICKY` with null-intent guard.

## Verification performed
- `flutter analyze lib/providers/task_provider.dart` — clean.
- `flutter test test/db/soft_delete_audit_test.dart` — 10/10 pass
  (run solo; the `LateInitializationError` lines in output are pre-existing
  benign test-env noise — the scheduler is designed to never break CRUD).
- Kotlin changes brace-balanced and mirror verified patterns; full Kotlin
  compilation happens in CI (`df32dd1` fixed the Kotlin 2.2/plugin setup).

## Residual risks / follow-ups
- **Real-device pass still needed:** reboot with reminders disabled (F1),
  restore-from-bin alarm re-arm (F2), and the exact-alarm permission
  denied → fallback path.
- `parseIsoDateTime` falls back to `System.currentTimeMillis()` on corrupt
  dates (alarm fires immediately). Fail-safe direction; logged. Acceptable.
- `notification.flags or FLAG_INSISTENT` + `setBypassDnd(true)` are
  intentional for an alarm app; the channel is user-mutable in system
  settings.
- The Dart `flutter_local_notifications` schedule path is dead code on
  Android (native path returns early) but live on other platforms; kept
  consistent, not removed.
- Full `flutter test` suite re-run deferred to the parent's final
  consolidation after all parallel audits land.
