# Kisan Dost — Authentication, Authorization & Privileged-Functionality Audit (2026-10-04)

Auditor: senior Flutter security review (subagent). Scope: `lib/` except
`lib/providers/` and `lib/services/` (edited by parallel agents — read-only
there). Fully offline single-user app: no backend, no accounts.

## Verdict up front

**There is no authentication or authorization code in this app — and that is
correct.** No login, signup, password, PIN, biometric, token, session, or
app-level role check exists anywhere in `lib/`, `pubspec.yaml` declares no
auth packages, and there is no dead auth scaffolding to remove. Per the
standing directive, no login system was added. The one "role" in the codebase
(`farmer_role`: landowner/cultivator in `lib/models/batai.dart`) is a
sharecropping domain concept, not access control. The `crypto` package is
used only for SHA-256 backup sidecars — legitimate, keep.

## 1. Authentication / authorization inventory

| Check | Result |
|---|---|
| Login/signup/password/PIN/biometric screens or logic | **None found** (grep across `lib/`) |
| Auth tokens / session handling | **None** |
| App-level roles / `isAdmin` / permission tiers | **None** |
| `local_auth` / `pin_code` / `oauth` packages | **None** in pubspec |
| `kDebugMode`-gated screens or debug panels | **None** (only `assert()`s in `batai.dart` model validation) |
| Named routes / `onGenerateRoute` / `RouteSettings` | **None** — all navigation is direct `MaterialPageRoute` pushes from visible UI |
| Hidden gestures / secret taps / deep links | **None** (manifest has no `<data>`/VIEW/BROWSABLE filters — verified) |

## 2. Demo mode

- **Entry is explicit user choice only:** onboarding "ڈیمو دیکھیں" button
  (`onboarding_screen.dart:50`) and a settings tile (`settings_screen.dart:297`).
  Both warn with a confirmation dialog when real data already exists
  ("ڈیمو کا نمونہ ڈیٹا آپ کے اصل ڈیٹا کے ساتھ شامل کیا جائے گا").
- **Exit is explicit:** persistent amber banner ("ڈیمو ڈیٹا — یہ اصل ڈیٹا نہیں
  ہے") with "ڈیمو ختم کریں" + info dialog, and a settings tile; both show a
  confirmation dialog before wiping.
- **No data leakage:** `DemoDataService` records per-table max IDs before
  inserting and deletes only rows with `id > beforeMax` on exit; `_cleanupPartial`
  rolls back partial entries. Real rows are never touched.
- **No hidden bypass:** no gesture, route, or pref shortcut enters demo mode.
  `enterDemo` no-ops if already active.

## 3. Privileged operations — reachability

All privileged actions are reachable **only** through visible settings UI:

| Operation | Entry point | Guard |
|---|---|---|
| Backup create / import / replace / merge | Settings → "ڈیٹا بیک اپ اور بحالی" → `backup_screen.dart` | File picker + `verifyBackup` before restore; replace shows **two** confirmations incl. "⚠ خبردار: موجودہ تمام ڈیٹا مستقل طور پر ضائع ہو جائے گا!" and "آخری تصدیق" |
| Delete all data | Settings → "تمام ڈیٹا ہمیشہ کے لیے حذف کریں" | Explicit Urdu dialog: "…ہمیشہ کے لیے حذف کرنا چاہتے ہیں؟ یہ عمل واپس نہیں لیا جا سکتا۔" with منسوخ کریں / جی ہاں، حذف کریں; non-dismissible progress; alarms cancelled first |
| Demo enter/exit | Settings tile / onboarding / banner | Confirmation dialogs both ways |
| Recycle bin restore/permanent delete | Settings → "حذف شدہ" | Per-row actions in `recycle_bin_screen.dart` |
| Audit log | Settings → "تبدیلیوں کا ریکارڈ" | Read-only view |
| Share APK | Dashboard menu | In-process method channel → FileProvider (audited separately) |

- **Route/parameter manipulation:** impossible — no named routes, no arguments
  parsed from anywhere.
- **Local-state manipulation:** `SharedPreferences` keys are all benign UX
  toggles (`reminders_enabled`, `alarm_sound_enabled`, `vibration_enabled`,
  `snooze_duration`, `reminder_pref_*`, `onboarding_done`, demo `activeKey`).
  Flipping them changes cosmetics only; none gates a privileged operation.
  Requires root/filesystem access on a non-rooted device anyway.
- **Method-channel calls:** `MainActivity.kt` exposes `scheduleAlarm`,
  `cancelAlarm`, `rescheduleAllAlarms`, `shareApk`, permission helpers, etc.
  `MethodChannel` is **in-process only** (Dart ↔ native in the same app);
  external apps cannot invoke it. No issue.
- **Cross-app intents:** only `MainActivity` (LAUNCHER) and `BootReceiver` are
  exported; `AlarmReceiver`/`AlarmService`/`AlarmActivity`/`FileProvider` are
  `exported="false"`. BootReceiver validates its action. No deep links exist.

## 4. Code removed

**None.** The audit found zero unused authentication/authorization scaffolding.
Nothing was added either, per the user's explicit constraint.

## 5. Residual risks / follow-ups (for parent routing)

1. **Minor logic edge (cosmetic):** `_wipeAllData` does not reset the demo
   `activeKey` pref. If demo mode is active during a full wipe, the banner can
   linger with no demo rows, and re-entering demo silently no-ops
   (`if (_active) return` while the UI reports success). Not a security hole;
   suggest the owning agent clears the flag in the wipe flow.
2. **Out of scope, assumed safe:** `lib/providers/` and `lib/services/` were
   read but not modified (parallel agents own them). The demo service's
   ID-range tracking was reviewed read-only and is sound.
3. `flutter analyze` was not re-run by this agent — no files were changed.
