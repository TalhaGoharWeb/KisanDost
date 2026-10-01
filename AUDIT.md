# Kisan Dost — Repository Audit (Phase 1)

**Date:** 2026-10-01
**Repo:** https://github.com/TalhaGoharWeb/KisanDost @ `e5e2fa4` (2 commits, initial + README)
**Size:** 35 Dart files, ~15,601 LOC (screens: 19 files / ~11.8K LOC — the bulk)
**Auditor method:** full static source review of every Dart file, DB schema, providers, services, Android native code, configs. The app was NOT run interactively in this pass (no Flutter SDK in this environment at audit time; `flutter analyze`/`flutter test` not yet executed — see §12).

---

## 1. Current architecture

```
Presentation:  19 screens (imperative Navigator.push, no named routes / router)
State:         Provider (ChangeNotifier) — 9 providers, each owns raw sqflite calls
Data:          sqflite single DB `kisan_dost.db`, v9, 13 tables
Services:      NotificationService (flutter_local_notifications + native Kotlin alarm stack)
Theme:         single light ThemeData, forced global RTL, Jameel Noori Nastaleeq everywhere
```

- No repository layer: **SQL lives inside providers AND inside screens** (e.g. `profit_loss_screen.dart` computes P&L inline over provider lists).
- No dependency injection; providers constructed in `main.dart` MultiProvider with eager `..fetchX()` calls (9 parallel DB opens at startup).
- No localization framework: hardcoded Urdu string literals everywhere (thousands), plus some English identifiers shown to users (`'Harvested'`, `'Paid'`, `'Pending'` stored/displayed raw in places).
- Native Android alarm stack (6 Kotlin files): `AlarmScheduler` reads the sqflite DB directly from native code and schedules `AlarmManager.setAlarmClock` exact alarms; `BootReceiver` reschedules on boot; `AlarmService` foreground service with looping `farming_alarm.mp3`.
- Backend: none. 100% offline, no auth, no sync, no analytics.

## 2. Current features — what ACTUALLY exists (verified in code)

| # | Feature | CRUD | Notes |
|---|---------|------|-------|
| 1 | Farms + Fields | C/R/U/D | Farm: name + total_area only. Field: name, size_acres, canal/tubewell flags, location. No ownership type, no area units other than acre. |
| 2 | Crop seasons (فصل) | C/R/U/D | Multi-field linking via `crop_season_fields` join table. Status: Active/Harvested. No seed qty/cost, no expected yield, no sowing/harvest dates beyond start_date. |
| 3 | Activity diary (زرعی سرگرمیاں) | C/R/U/D + duplicate + complete toggle | Activity types incl. irrigation/fertilizer/spray/labour; optional expense + optional inventory deduction. |
| 4 | Expenses (اخراجات) | C/R/D (no update screen) | Flat global list; 16 fixed categories; **no link to farm/field/crop** (see §7). |
| 5 | Inventory (اسٹاک) | C/R/U/D | Single quantity column; purchase merges into weighted-average cost; usage deducts. No ledger. |
| 6 | Harvest + Sale | C/R/U/D | Harvest records quantity/unit/rate/buyer/5 expense buckets; auto-creates `sales` row + `expenses` row. |
| 7 | Theka (land lease) | C/R/D + installment pay/undo/reschedule | Fixed-rent lease: total amount, installments with due dates, partial payments; payments auto-create Land Rent expenses. |
| 8 | Ushr calculator + records | C/R/U/D | 10%/5%/custom method, cash/crop/mixed payment tracking, partial payments, auto-creates Ushr Expense. |
| 9 | Tasks + Alarms (یاد دہانیاں) | C/R/U/D + snooze/complete actions | One-time/daily/weekly; reminder offsets (0/60/1440 min); full-screen native alarm with looping sound; reschedule-on-boot. |
| 10 | Profit & Loss (منافع و نقصان) | Read-only | 4 tabs: overall, per-crop, category breakdown, insights. **Heuristic** (see §7). |
| 11 | Today's Work (آج کا کام) | Read-only | Screen exists (detail in screens audit). |
| 12 | Settings | Read-only toggles | Alarm prefs, battery-optimization + full-screen permission flows, **delete-all-data**, about. No backup/restore/export. |
| 13 | Share APK | Works via native | Dashboard "share" copies own APK through FileProvider (peer-to-peer distribution). |
| 14 | Splash screen | — | Exists. |

**README claims that are NOT implemented (verified by grep):**
- ❌ "PDF Reports & Invoicing" — `pdf` + `printing` packages are in pubspec but **zero imports** in lib/.
- ❌ "Animations" via Lottie — `lottie` package in pubspec, **zero usage** in lib/ (5 lottie JSONs + 3 animation JSONs are dead weight; `assets/animations/` isn't even declared in pubspec assets).
- ❌ Full localization — `assets/i18n/{en,ur,ur_rom}.json` (135KB) exist but **nothing reads them**; not declared in pubspec assets either (wouldn't bundle).

## 3. Broken / partially-implemented features

### 3.1 P&L is structurally misleading (§7 detail)
`profit_loss_screen.dart`:
- **Per-crop expenses only count activity-linked expenses + harvest expenses + ushr.** The standalone Expenses screen (the primary expense entry path) writes rows with NO crop link — they appear only in the global total and a footnote-ish "indirect expenses" line. A farmer who records expenses the normal way gets per-crop P&L that systematically **understates costs → overstates profit**.
- Per-crop income uses the stored redundant `gross_amount` (fine) but overall revenue uses `sale.totalAmount` — two different columns for the same concept.
- `highestYielding` sums quantities across **mixed units** (maund + kg + bags added together) — meaningless comparison.
- Ushr double logic: per-crop expense adds `ushrAmount` (the *obligation*), while the `expenses` table row records `cashPaid + qtyPaid*rate` (the *actual payment*) — inconsistent bases; global total double counts vs crop view.
- Status filter: anything not literally `'Active'` is "Harvested" (fragile string match).

### 3.2 Inventory integrity holes (CRITICAL)
- `InventoryProvider.deductInventoryItem` **clamps to 0**: using more than available silently succeeds — impossible stock, no error (violates "validate, never silently create impossible stock").
- `ActivityProvider._applyInventoryDelta`: **hardcodes 1 bag = 50 kg** (`weightInKg['bag'] = 50.0`) — violates the product rule "never assume bag size".
- When the named inventory item doesn't exist, usage **silently does nothing** (returns) — the activity is still recorded as if input was applied.
- No transaction ledger: quantity is mutated in place via read-modify-write with **no DB transaction** (race-prone); no history of who/what/when.
- Deduct query ignores `unit` (matches category+name only), then converts — mixing-unit deductions can corrupt.
- Purchase path merges duplicates by (category,name,unit) with weighted-average cost — destroys per-batch purchase price; no batch/expiry tracking.

### 3.3 Harvest/Sale inconsistencies
- `updateSale` updates the `sales` row but does **NOT** recompute `harvests.gross_amount/net_income` → sale and harvest disagree after edit.
- `deleteSale` leaves harvest `payment_status`/`buyer_name` stale.
- `recordSale` sets `payment_status='Paid'` unconditionally — no partial payment support despite model claiming 'Partial'.
- Harvest sale info and `sales` row duplicate each other (two sources of truth for buyer/qty/price).

### 3.4 Theka payment accounting
- `payInstallment(paidAmount:)` **replaces** `paid_amount` instead of accumulating. If the UI passes incremental amounts (verify in screens audit), paying 5,000 twice on a 10,000 installment records only 5,000 paid. If the UI passes cumulative, overpayment can't be distinguished. Either way the API is a trap.
- No overpayment guard, no payment history (each pay overwrites the previous expense row).
- Deleting a theka hard-deletes paid-installment expense rows (rewrites financial history).

### 3.5 Ushr correctness gaps
- Paying ushr **in kind** (`qtyPaid`) never deducts from harvest stock — the crop can be "paid" as ushr and still fully sold.
- `remaining_balance` is a stored input, not computed — can contradict qty/cash paid.
- Ushr treated as business expense in P&L (religious obligation ≠ production cost) — inflates/deflates farm profitability semantics; needs a policy decision.

### 3.6 Expenses module
- No edit/update path at all (add + delete only).
- No crop/farm/field linkage → the single biggest architectural blocker for real crop P&L.
- No payment method (cash/credit), no party linkage → no udhaar foundation.

### 3.7 Missing ledger/udhaar, batai, backup (entirely absent)
- **No Party/Ledger tables** — credit with dealers/labourers/buyers cannot be tracked. The mission's §14 is 0% implemented.
- **No batai/sharecropping** — only fixed-rent theka. i18n strings reference "حصہ دار" (partner) share-splitting ("automatic_split_notice") — planned, never built. Dead strings.
- **No backup/restore/export at all.** `clearAllTables()` + a settings "delete everything" button is the only data-management tool. Single-device SQLite = one lost/broken phone wipes the farmer's entire diary. This is the #1 data-safety production blocker.

### 3.8 Dead code & unused dependencies
- `pdf`, `printing`, `uuid`, `lottie`, `cupertino_icons` (verify) in pubspec, **zero usage** — bloat + larger APK.
- `assets/animations/` (3 JSON), `assets/i18n/` (4 files incl. a stray `.json`), `assets/notification/*.mp3` not declared in pubspec → never bundled, dead weight in repo (14MB assets dir, mostly the unused font + images).
- `CropProvider.getDynamicTimelineForActivities`, `splitAmountAcrossFields` — check usages (likely dead).
- `download_lottie.py` — dev artifact, downloads a Lottie logo into assets; not part of build.

## 4. Missing features (vs mission spec)

| Mission § | Feature | Status |
|-----------|---------|--------|
| 10, 11 | Inventory transaction ledger + package-aware units | ❌ absent |
| 12, 13 | Expense→crop linkage; sale payment status/partial payments | ❌ / partial |
| 14 | Party ledger / udhaar (receivable/payable) | ❌ absent |
| 15 | Batai / muzara'at sharecropping | ❌ absent (theka = fixed rent only) |
| 17 | Season management (Kharif/Rabi, season compare) | ❌ absent |
| 19 | Weather | ❌ absent |
| 20, 21 | AI assistant, voice input | ❌ absent (correctly deferred) |
| 22 | Photos/attachments | ❌ absent |
| 24 | Sync engine | ❌ absent (offline-only; no backend exists) |
| 29, 30 | Backup/restore, CSV/PDF exports | ❌ absent |
| 32 | Search | ❌ absent (no search anywhere — verify in screens audit) |
| 33, 34 | Soft delete, audit log | ❌ absent (hard deletes everywhere, incl. financial records) |
| 4 | Real localization (Urdu/English/Roman Urdu switchable) | ❌ (dead JSON files only) |
| 42 | Onboarding | ❌ (splash → dashboard directly) |
| 43 | Demo mode | ❌ absent |
| 44 | CSV/Excel import | ❌ absent |

## 5. Technical debt

1. **Money as `double`** everywhere (expenses, harvests, installments, ushr) — float rounding in financial sums; no Money type, no paisa integers.
2. **Computed columns stored redundantly**: `gross_amount`, `total_expense`, `net_income` on harvests; `remaining_balance` on ushr — multiple can disagree (see 3.3).
3. **Denormalized inventory snapshot on activities** (`inventory_category/name/unit/quantity` copied onto each activity row) — rename an inventory item → history lies.
4. **Stringly-typed everything**: statuses, categories, activity types as raw strings in 3 languages mixed (`'Paid'`/`'Pending'` English in DB; Urdu in UI) — typo-prone, unqueryable.
5. **No indexes** beyond PKs — `activities`/`expenses` full-table scans on every provider refresh; fine at 100s of rows, degrades at 1000s.
6. **Eager fetch-all on startup**: 9 providers × full table loads before first frame; no pagination anywhere.
7. **Duplicate models**: `Harvest` rebuilt manually in provider instead of `Harvest.fromMap` (drift risk — already drifted once? verify).
8. **Native/Dart DB duality**: Kotlin `DatabaseHelper` opens the same `kisan_dost.db` from native — schema changes must be mirrored by hand; no shared contract.
9. **DB version 9 with try/catch migrations**: duplicate `CREATE TABLE IF NOT EXISTS` for theka/tasks across versions — works but fragile; no migration tests.
10. **No named routes / deep links**; `AlarmScreen` pushed via global navigatorKey from notification tap — works but untestable.
11. **Global forced RTL** via `builder: Directionality(rtl)` — breaks any future English/LTR mode; should come from locale.
12. **Nastaleeq forced on ALL text** including numbers/inputs — numeric readability suffers (mission §4 allows numeric font).
13. **Zero tests**: `test/widget_test.dart` is the default counter template and **fails to compile** against this app (references nonexistent counter UI).
14. **No CI**: no workflows; `flutter analyze`/`flutter test` never run automatically.

## 6. Security issues

- ✅ No API keys/tokens/secrets found in `lib/` (grep for api_key/secret/password/token/supabase/firebase/openai/gemini: clean). No network calls at all → tiny attack surface.
- ⚠️ **Release signing = debug keys** (`signingConfig = signingConfigs.getByName("debug")`) — must fix before any Play Store / production distribution.
- ⚠️ **applicationId `com.example.kisan_dost`** on Android; iOS `com.example.kisanDost` — placeholders, must change (also breaks the FileProvider authority + native channel names which embed it).
- ⚠️ **APK sharing feature** (`shareApk`): distributes the *debug-signed* APK peer-to-peer; fine for field testing, must not ship as the distribution story.
- ⚠️ Full-screen intent + `REQUEST_IGNORE_BATTERY_OPTIMIZATIONS` + exact alarms: legitimate for the alarm feature, but Play Store requires justification video/declaration for `USE_FULL_SCREEN_INTENT` (Android 14+) and battery-optimization exemption; risk of policy rejection.
- ⚠️ No backup encryption story (when backup is built, it must not be plaintext-with-PII... actually farmer financial data in plaintext JSON on shared devices is a privacy consideration; note in roadmap).
- ℹ️ Local DB is unencrypted (sqflite) — acceptable for single-user offline diary; document the tradeoff.

## 7. Data integrity issues (consolidated)

1. Expenses not linked to crop/farm/field → per-crop P&L structurally wrong (§3.1).
2. Inventory mutations without ledger; clamp-to-zero hides overuse (§3.2).
3. Hardcoded 50kg bag conversion (§3.2).
4. Harvest ↔ sale double-entry drift (§3.3).
5. Theka installment `paid_amount` replace-vs-accumulate trap (§3.4).
6. Ushr-in-kind doesn't reduce harvest stock (§3.5).
7. Hard deletes of financial records everywhere (expenses, harvests, thekas with paid installments, ushr) — history rewritten, no audit trail.
8. Redundant computed columns can disagree with source inputs.
9. `crop_season_fields` backfill in `fetchCropSeasons` **writes to DB during a read** (side-effecting getter) — surprising and racy.
10. No FK enforcement at runtime: sqflite does NOT enable `PRAGMA foreign_keys` by default — the `ON DELETE CASCADE` clauses are **dead text** (verified: no `onConfigure`/PRAGMA anywhere in Dart or Kotlin). Deleting a farm/field/crop_season does NOT cascade → orphaned fields, crop_seasons, activities, harvests, ushr_records, thekas accumulate silently. Also `deleteCropSeason`/`deleteFarm` in providers rely on cascade that never fires. ← CONFIRMED CRITICAL.

## 8. UX problems (farmer-lens; screens audit adds detail)

- Dashboard is a 10-tile icon grid — a menu, not a farmer's home (mission §6 wants: greeting, farm summary, TODAY list, quick actions, recent activity).
- No search anywhere (19 screens, 0 search fields — to verify).
- Forms: need validation check per screen (subagent).
- Tiny English parentheticals in labels ("ترتیبات (Settings)") — noise for Urdu users.
- No onboarding, no demo mode — first launch drops into an empty grid.
- No empty states on some lists? (subagent verifying; `EmptyStateWidget` exists — check usage coverage.)
- Numbers in Nastaleeq (hard to scan); no tabular numerals.
- Every destructive action: confirm dialogs? (subagent verifying.)

## 9. Performance problems

- Full-table `SELECT *` loads in all 9 providers at startup; lists rebuilt in-memory for P&L (O(n·m) nested `.where` loops over activities×seasons).
- No pagination; `ListView` fine for hundreds of rows, risky at thousands (multi-year diary).
- 14MB assets (font is the bulk — fine) + 4 unused packages inflate APK.
- P&L screen recomputes everything on every build (no memoization; `Provider.of` without `select`).

## 10. Production blockers (must-fix before any release)

1. **No backup/restore** — single highest data-loss risk.
2. **applicationId + iOS bundle ID are `com.example.*`** — cannot ship.
3. **Release signed with debug keys**; no R8/minify config.
4. **Foreign keys not enforced** (no `PRAGMA foreign_keys=ON`) — confirmed: `ON DELETE CASCADE` is dead text; deletes orphan child rows instead of cascading. Data-integrity-critical.
5. **Zero automated tests; default widget test doesn't compile.**
6. **No CI.**
7. **P&L misleads on costs** (expense→crop linkage missing).
8. **Inventory can go silently inconsistent** (clamp-to-zero, no ledger).
9. Play policy risk: full-screen intent + battery exemption justification.
10. **No crash reporting / logging** — field failures invisible.

## 11. Recommended architecture (evolution, not rewrite)

Keep: sqflite offline-first core, Provider (it's working; standardize it), native alarm stack (it's the app's best feature — keep, but add a schema contract test), Urdu-first UI.

Change (phased):
- **Phase A — integrity**: enable FK pragma; expense→(farm/field/crop) FK columns + migration; inventory transaction ledger table; replace clamp-to-zero with validation error; Money as int paisa (new columns, migrate); remove redundant computed columns (compute in queries/views).
- **Phase B — farmer workflows**: quick-entry home (TODAY + 6 big actions), real crop P&L, inventory ledger UI, party ledger/udhaar (new tables), batai module (new tables), backup/restore (versioned JSON, Replace/Merge/Cancel), CSV/PDF export (actually use `pdf` pkg or drop it).
- **Phase C — hardening**: proper l10n (resurrect `assets/i18n` via real `flutter_localizations` + a small AppStrings layer; keep Urdu default), numeric font for data, unit system (`UnitConversionService`, package-aware units), validation framework, soft-delete + audit log, error-mapping layer.
- **Phase D — release**: applicationId, release signing, R8, Play policy declarations, CI (analyze+test+build), tests per mission §48/49, onboarding + demo mode.
- **Explicitly deferred**: sync backend (no server exists; design schema sync-ready: `updated_at`, `deleted_at`, `sync_status` columns added in Phase A migrations so a future backend doesn't require another migration), weather, AI/voice (no keys in app, server-side only — architecture note), photos (needs storage/retention policy first).

## 12. Implementation roadmap (maps to mission phases)

| Order | Work | Why first |
|-------|------|-----------|
| 1 | FK pragma + migration test harness + delete-orphan repair | integrity foundation |
| 2 | Expense→crop/farm/field linkage (schema + UI pickers + P&L fix) | fixes the flagship misleading screen |
| 3 | Inventory ledger + validation (no clamp, no silent skip, tx ledger) | stops silent data corruption |
| 4 | Money→paisa ints; kill redundant computed columns | financial correctness |
| 5 | Backup/restore (versioned JSON) | #1 data-safety blocker |
| 6 | Home redesign: TODAY + quick actions + summary | farmer retention |
| 7 | Party ledger/udhaar | top farmer-asked question "who owes whom" |
| 8 | Batai module | Pakistan-specific core |
| 9 | Exports (CSV/PDF that actually work), receipts | trust + shareability |
| 10 | l10n resurrection, numeric font, unit service, validation | UX correctness |
| 11 | Soft delete + audit log | financial accountability |
| 12 | Tests (unit §49 list + widget + offline integration) + CI | proof |
| 13 | Android production hardening (id, signing, R8, Play declarations) | shippable |
| 14 | Onboarding + demo mode | adoption |

## 13. Audit limitations

- App not executed: no Flutter SDK in this sandbox at audit time (download in progress, ~1.2GB). Screen-by-screen runtime behavior (nav dead-ends, overflow errors, permission dialogs) assessed statically; a runtime pass on a real device/emulator is still owed before release.
- `flutter analyze` / `flutter test` not yet run — static findings above are from reading code, not the analyzer.
- Screens deep-dive: delegated to a parallel audit worker; its report lands in `AUDIT_SCREENS.md` and its findings should be merged into §3/§8 above.
