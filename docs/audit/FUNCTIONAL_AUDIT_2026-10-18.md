# Kisan Dost — Comprehensive Functional, Integration, Security & Production-Readiness Audit

**Date:** 2026-10-18
**Repo:** `TalhaGoharWeb/KisanDost` @ `5c0e8f8` (audit fixes; website commits excluded from scope)
**App:** v1.0.6+7, package `com.talhagohar.kisandost`, Flutter 3.47.5 / Dart 3.13.4, offline-first, no INTERNET permission
**Method:** 4 parallel static-analysis strands + 1 fixes strand; existing suite executed (`flutter test`, 322 tests). No real device available — runtime-dependent items are marked honestly throughout.
**Prior work built upon (not redone):** `AUDIT.md` + `AUDIT_SCREENS.md` (2026-10-01), `docs/audit/*` (2026-10-04: DB hardening, alarm, crash-safety, SQLi, red-team).

**Status summary:** 6 P0/P1 defects found → all 6 fixed with regression tests, suite green (322/322). 0 P0 remaining. 9 P2 + 14 P3 documented, not fixed (per scope). 8 product decisions left to the owner.

---

## 1. Executive summary

The October 2026 development arc transformed the app: the seven critical integrity findings from the 2026-10-01 audit (dead FK cascades, inventory clamp-to-zero, hardcoded 50 kg bag, `double` money, redundant computed columns, theka replace-trap, hard deletes) are now **fixed and verified** — schema v15/19 tables, integer-paisa money, FK pragma ON with a v9→v10 orphan repair, append-only inventory ledger, soft-delete + recycle bin + audit log, backup/restore with hash verification, party ledger, batai, PDF/CSV exports, onboarding + demo mode.

This audit found **6 new P0/P1 defects** (1 data-loss, 5 correctness), all fixed with regression tests in commit `5c0e8f8`:
- **D1 (P0):** demo-mode exit could cascade-delete the farmer's *real* records via FK CASCADE. Now blocked with an Urdu explanation.
- **SEC1 (P1):** expense→inventory save had no `catch` — a mid-save stock failure left a committed expense with no deduction and no error; retry duplicated the expense. Now caught with an Urdu error.
- **S1 (P1):** My Crops profit card used activity-linked expenses only; P&L screen uses the full basis — two different «منافع» figures for one crop. Card now uses `computeFarmPnl` (single source).
- **S6 (P1):** editing a harvest after its expense mirror was soft-deleted wrote the new total into the invisible deleted row. Now repoints to a fresh live row.
- **S4 (P1):** ushr autofill copied any harvest unit into the من field (200 kg → "200 من"). Now converts via `UnitConverter`; unconvertible units leave the field empty.
- **F1–F4 (P1):** 4 pre-existing test failures (stale demo-data expectations; missing provider in widget test). Repaired; suite 322/322.

**Remaining risk centers (all documented, none silently decided):** ushr cash-vs-accrual basis in P&L, batai↔P&L integration, party-ledger↔P&L linkage, sale-on-credit income recognition, theka/ushr hard-delete paths (deliberate, audit-logged), in-app update check (no INTERNET by design — manual Drive distribution), backup encryption, lock-screen notification redaction. Real-device verification is still owed for alarms, reboot reschedule, and the 1.0.6 expense→inventory link.

---

## 2. Actual architecture and module inventory

| Layer | Implementation |
|---|---|
| Presentation | 28 screens (`lib/screens/`), imperative `Navigator.push`, no named routes |
| State | Provider (ChangeNotifier), 11 providers (`lib/providers/`), each with `_txn` DB-transaction helper (51 call sites) |
| Data | sqflite `kisan_dost.db`, **schema v15, 19 tables** (+`strings` l10n cache = 20 names in file), `PRAGMA foreign_keys=ON` in `onConfigure`, migrations v9→v15 |
| Money | Integer paisa everywhere (`lib/services/money.dart`); v12 migration rebuilt all money tables REAL→INTEGER |
| Inventory | Cached `quantity` + append-only `inventory_transactions` ledger; atomic check-and-decrement; `UnitConverter` (package↔weight requires caller-supplied `weightPerUnitKg`) |
| Soft delete | `deleted_at` on expenses/sales/harvests/tasks/parties + recycle bin + restore; theka/ushr/activity hard-delete by deliberate design (audit-logged) |
| Audit | `audit_log` table, append-only, written in the same transaction as the mutation (farms/fields/seasons not yet logged — D9) |
| Backup/restore | Binary DB copy + JSON sidecar (schemaVersion, SHA-256 streamed); replace (with pre-restore safety backup) or merge (ATTACH + INSERT OR IGNORE, FK-safe) |
| Alarms | Dart → MethodChannel → Kotlin `AlarmScheduler` (`setAlarmClock`) + `AlarmService` FGS + `BootReceiver`; native stack reads the DB directly (parameterized queries only) |
| Network | None. No INTERNET permission, zero `https://` literals, no `url_launcher` |
| Tests | 40 files: `test/db/` 22, `test/unit/` 8, `test/widget/` 7, `test/offline/` 2, `test/android/` 1 |

---

## 3. Screen-by-screen functionality results

28 screens inventoried (entry points, controls, DB reads/writes, providers — full table in strand-2 working notes). Navigation graph sound: all pushes resolve, both new providers registered in `main.dart`, no TODO/FIXME stubs, no unreachable screens.

**Defects found (all verified in code; static only):**

| ID | Sev | Location | Defect |
|---|---|---|---|
| S1 | P1 | `my_crops_screen.dart:160-166,345-348` | Profit card = sales − activity-linked expenses only; P&L screen uses full basis → two «منافع» figures. **FIXED** — card now uses `computeFarmPnl` |
| S2 | P2 | `harvest_provider.dart:~260` | Unsold harvests auto-book a `sales` row whenever a rate is entered → phantom income in P&L. Product decision (cash vs accrual) — documented, not changed |
| S3 | P2 | `batai_provider.dart:280-336` | `settleAgreement` writes only `batai_settlements`; farmer's share never reaches P&L (or double-counts if harvest sale also recorded). Needs owner policy |
| S4 | P1 | `ushr_screen.dart:~686-696` | Autofill copies any harvest unit into the من field. **FIXED** — converts via `UnitConverter`, blanks unconvertible units |
| S5 | P2 | `party_provider.dart:290-346` | Ledger is a silo: credit sales don't create entries, وصولی/ادائیگی don't touch income/expense. Internally consistent; needs owner policy |
| S6 | P1 | `harvest_provider.dart:314-330` | Edit after expense-mirror soft-delete wrote into the deleted row. **FIXED** — repoints to a fresh live row |
| S7 | P2 | `ushr_provider.dart` | In-kind ushr payment never reduces harvest quantity |
| S8 | P2 | `pnl_summary.dart` vs `ushr_provider.dart:138` | Per-crop P&L books full ushr *due*; overall books *paid* portion. Deliberate; needs owner policy |
| S9 | P2 | `todays_work_screen.dart:65,132` | Lifetime diary mislabeled as "today's work"; no date filter |
| S10 | P2 | `dashboard_screen.dart:266-284` | TODAY section ignores `taskProvider.isLoading` → false "all clear" on cold start |
| S11 | P2 | `harvest_provider.dart:578-692` | `deleteSale` zeroes harvest rate; `restoreSale` restores only the sale row → rate/total disagree |
| S12 | P2 | `alarm_screen.dart` | Unreachable on Android (FLN path never fires); handlers cancel nonexistent FLN IDs |
| S13 | P2 | `AlarmService.kt:125`, `AlarmScheduler.kt:102` | Snooze label uses «سوز» (burn) instead of «سنوز»; user-visible on every alarm |
| S14 | P2 | `reports_screen.dart:296-343` | Export pickers use unbounded `SimpleDialog` lists → overflow risk with 15+ parties |
| S15 | P2 | `expenses_screen.dart:209-219` | `updateExpense` exists in provider but rows show delete-only; no edit UI |
| S16/UPD1 | P2 | `about_us_screen.dart:76` | Version chip hardcoded 'ورژن 1.0.0'; pubspec is 1.0.6+7 (see §15) |
| S17–S27 | P3 | various | Theka delete+reinsert identity hazard; delete-dialog copy contradicts soft-delete (×2); no warning for system-linked expense deletes; merge-restore single-tap; recycle-bin dead `_error` branch; batai party phone unvalidated; 3s splash; `_shareApk` catches only `PlatformException`; tasks 10s rebuild timer; README table count; provider reload fire-and-forget |

---

## 4. Navigation and integration results

Five end-to-end journeys traced statically:

- **(a) Farm → field → season → activity → expense: CONSISTENT.** `addExpense` takes farm/field/season IDs and still auto-creates the linked activity; `computeFarmPnl` dedupes by expense id — no double-count. Validators hardened (negative areas, negative qty/price, Urdu-digit tolerance).
- **(b) Harvest → sale → P&L: MOSTLY FIXED.** Income basis unified on `sale.totalAmountPaisa`; `updateSale` recomputes the harvest rate; `deleteSale` soft-deletes + resets harvest so re-sale is possible. Remaining: S2, S1 (fixed), S11.
- **(c) Theka → pay installment: FIXED.** Incremental accumulation + overpayment guard (provider + dialog validator); linked 'Land Rent' expense tracks the cumulative total; cancel deletes it.
- **(d) Ushr → payment: CORRECT MATH, 4 defects** (S4 fixed; S7, S8, overpayment-message remain).
- **(e) Party → ledger → balance: INTERNALLY CONSISTENT** (exact paisa sums, uniform signs, delete blocked with history). Siloed from P&L (S5).

**Two-sources-of-truth map:** (1) crop profit — unified by FIX-3; (2) ushr due-vs-paid basis — deliberate, needs owner; (3) batai settlements vs P&L — no integration, needs owner; (4) harvest rate vs sale price — unified except delete→restore path (S11); (5) expense total vs harvest-edit-after-soft-delete — fixed (FIX-4). Money itself is single-source (integer paisa; no `double` money columns).

---

## 5. Cross-module data consistency findings

- Duplicate counting: the one real dual-link path (expense with `crop_season_id` + auto-activity with `expense_id`) is deduped by expense id in `computeFarmPnl` (`pnl_summary.dart:78-103`). Harvest expenses appear once per level (computed buckets crop-side, expense mirror overall-side).
- Ushr mirror rows carry **no** `crop_season_id` (verified `ushr_provider.dart:143-153`) → per-crop P&L cannot double-count them; overall counts the paid mirror. Per-crop vs overall ushr basis differs by design (S8).
- Soft-delete respected by all totals (`deleted_at IS NULL`); FIX-4 closed the back-ref hole.
- Demo-mode exit now aborts (rather than cascade-deletes) when farmer rows reference demo parents (FIX-1).

---

## 6. Database and migration audit

- **Schema v15, 19 tables** (+`strings` cache): farms, fields, crop_seasons, crop_season_fields, expenses, inventory, inventory_transactions, activities, harvests, ushr_records, sales, tasks, thekas, theka_installments, parties, party_ledger_entries, batai_agreements, batai_settlements, audit_log.
- **FK enforcement: FIXED** — `PRAGMA foreign_keys=ON` in `onConfigure` on every open; structural children CASCADE, financial links SET NULL, RESTRICT on ledger parents. v9→v10 migration repaired pre-enforcement orphans. Historical note: v7 created thekas without FK clauses; FKs arrived with the v12 rebuild — versions 7–11 ran unenforced (current v15 correct).
- **Transactions:** all mutating provider paths use `_txn` (51 sites); write + linked writes + audit row atomic; migrations run in sqflite's onUpgrade transaction; backup create checkpoints → closes → copies → reopens in `finally`.
- **Migrations v9→v15:** orphan repair + expense link columns; immutable inventory ledger + idempotent backfill; REAL→INTEGER paisa rebuild (byte-identical to fresh schema); parties ledger; batai with DB CHECKs (shares sum to 100); soft-delete + audit_log.
- **Old critical findings (2026-10-01 §7) — final verdicts:** (a) FK pragma → FIXED; (b) clamp-to-zero → FIXED (atomic check-and-decrement, loud `InventoryException`); (c) 50 kg bag → FIXED (`UnitConverter` requires caller-supplied weight, throws otherwise); (d) double money → FIXED (paisa INTEGER, `Money` value object); (e) redundant computed columns → FIXED (computed in Dart getters); (f) theka replace-trap → FIXED (incremental + guard); (g) hard deletes → FIXED for 5 tables (soft-delete), deliberate+logged for theka/ushr/activity.
- **Dates:** naive strings (`yyyy-MM-dd` business dates; local ISO for timestamps); `Asia/Karachi` only for alarms. Self-consistent; no financial math depends on tz.
- **Indexes:** 5 (`inventory_transactions.item`, `party_ledger_entries.party`, `batai_settlements.agreement`, `audit_log(table,row)` ×2). Adequate — providers load full tables and filter in Dart.

---

## 7. Financial and agricultural calculation audit

Full register in `CALCULATION_REGISTER_2026-10-18.md` (11 sections with hand-computed expected values). Headline: **money is exact integer arithmetic end-to-end**; rounding occurs only at input parsing (>2dp rejected, never rounded), quantity×rate products (half away from zero), ushr percentage, weighted-average cost, and the batai remainder rule (remainder 0–99 paisa → larger share, owner on tie; DB CHECK enforces `owner+cultivator=total`).

Spot results: harvest 40 من @ Rs 3,500 → gross Rs 140,000, net Rs 128,000 (Rs 12,000 expenses) — observed from code. Theka 4×Rs 30,000: pay 10,000 → Partially Paid; pay 20,000 → Paid, expense updated to cumulative 30,000; +Rs 1 → throws. Batai Rs 1,000.01 @ 50/50 → owner 50,001 / cultivator 50,000. Ushr Rs 140,000 @ 10% → due Rs 14,000; pay 5,000 + 2 من @ 3,500 → remaining Rs 2,000, status Pending.

**Known calculation gaps (not fixed — owner decisions):** D2 ushr overpayment accepted (negative remaining); S2 phantom income from auto-created Pending sales; S8 ushr due-vs-paid basis split; S3 batai proceeds invisible to P&L.

---

## 8. Offline-first verification

**PASS (code inspection):** zero `http`/`dio`/`connectivity`/`HttpClient` usage in `lib/`; zero `https://` literals repo-wide in Dart/Kotlin; no INTERNET permission; backup/restore/share/export fully local (app-private dirs); share-with-no-handler degrades to Urdu errors (`backup_screen.dart:167-176`, `reports_screen.dart:111-122`); all four previously-unguarded startup fetches now try/caught (Oct offline-audit flags fixed); `OnboardingService.shouldShowOnboarding` fail-open. **Needs device:** backup/restore round-trip on a large real DB; 13-provider startup vs auto-backup timing on low-end hardware.

---

## 9. Notification and background execution results

No `android/` changes since the 2026-10-04 native audit — re-verified intact: `AlarmScheduler` (`setAlarmClock`), `AlarmService` FGS, `BootReceiver` reschedule honoring `reminders_enabled`, parameterized native queries, snooze-duration pref now honored (`AlarmReceiver.kt:70-71`). **Still owed on a real device:** alarm sound in release build, lock-screen full-screen alarm (user's 2026-10-04 pass found it failing — no code change here proves runtime behavior), reboot reschedule on the 1.0.6 build, exact-alarm-denied fallback, 5/10/15-min snooze. Do not claim guaranteed exact delivery.

---

## 10. Security findings and remediation

**Threat model:** single-user offline app, no network, no accounts — local-data + supply-chain scope.

- **Secrets sweep: CLEAN** (re-run on `lib/` + `android/app/src/main/`; 0 hits; new commits add none).
- **Manifest: SAFE** — no INTERNET; only exported components are `MainActivity` (launcher) and `BootReceiver` (boot broadcast, action-allowlisted).
- **Release signing: SAFE** — `build.gradle.kts` reads `key.properties` null-on-absent (fails loudly, never debug-signs); R8 minify + shrinkResources on; `Log.d/v` stripped.
- **Native SQL: SAFE** — parameterized queries only; single static `PRAGMA` execSQL.
- **Backup/restore files: SAFE** — app-private dirs; import generates dest filename from timestamp (picked path only read, never a write path — no traversal); `verifyBackup` (magic, integrity_check, schema floor, SHA-256) precedes restore; CSV formula-injection neutralized.
- **Log hygiene: CLEAN.**
- **SEC1 (P1) FIXED:** expense save now catches mid-save failures with Urdu error instead of silent partial write.
- **Accepted risks (owner decisions):** unencrypted plaintext backups; no UNIQUE on `inventory(category,name,unit)`; `restoreHarvest` not restoring the expense mirror; ushr cash-vs-accrual.

---

## 11. UI/UX and localization findings

- **RTL:** forced `TextDirection.rtl` in `main.dart`; new screens don't fight it; no new LTR breakage statically.
- **Numbers:** `DigitText` (Noto Sans, tabular) has 53 usages; money never renders in Nastaleeq in new code. Remaining `toStringAsFixed` hits are quantities/dates/percentages.
- **Empty/loading/error states:** new screens (audit_log, recycle_bin, backup, party_detail, batai_detail) all have spinners + error + retry; `EmptyStateWidget` on 9 screens. Gaps: dashboard TODAY ignores `isLoading` (S10); `reports_screen` exports header-only CSVs with a success snackbar on empty data.
- **Destructive actions:** theka/ushr/activity deletes confirm; recycle-bin permanent deletes confirm; merge-restore is single-tap (S20).
- **Validation:** `FieldValidators` hardened (negative/zero areas, Urdu-digit-tolerant money/quantity); batai quick-add phone unvalidated (S22); expense rows delete-only (S15).
- **User-visible language issues:** «سوز» for snooze (S13); delete-dialog copy claims irreversibility for soft-deletes (S18); no warning for system-linked expense deletes (S19); Today's-Work mislabel (S9).
- **Overflow risks (static):** unbounded `SimpleDialog` pickers (S14); untruncated joined names on batai cards; 24–30sp Nastaleeq on 360px screens — needs runtime check.

---

## 12. Performance measurements

Static assessment (no profiler in sandbox): startup fires 13 concurrent full-table fetches + a concurrent auto-backup (checkpoint→close→copy→reopen) — guarded with try/catch today, O(total rows) memory at launch (PERF2, P3). P&L recomputes in `build` — pure-Dart O(n) over in-memory lists, cheap at farmer scale (PERF1, P3). 5 indexes; providers filter in Dart (offline-first pattern) so sparse SQL indexes don't bite (PERF3, P3). Backup SHA-256 streams (`openRead`), not a main-thread blocker. No N+1 query patterns found; lists use builders. **No measured timings** — DevTools unavailable here; treat as static findings.

---

## 13. Tests executed and their actual outcomes

- `flutter analyze`: **0 errors, 0 warnings**, 43 info (all pre-existing deprecations/`use_build_context_synchronously` — untouched).
- `flutter test` (full suite, run alone): baseline **305/309** (4 pre-existing failures: F1–F3 stale demo-data expectations from commit `5627f36`; F4 missing `InventoryProvider` after `eb363dc`) → after fixes **322/322 PASS** (+13 new regression tests).
- New regression tests: demo-exit block (D1), throwing-provider expense save (SEC1), my_crops↔P&L consistency (S1), harvest-expense-mirror repoint (S6), ushr autofill units (S4).
- Dependency CVEs: 0 at locked versions (OSV.dev cross-checked for sqflite_common_ffi, sqlite3, pdf, crypto, file_picker, flutter_local_notifications, share_plus).
- **Not executed:** Android debug/release assemble (Gradle), integration tests on device, alarm/reboot/backup round-trip on hardware. `JAVA_HOME=/home/hatch/jdk21` from the task brief does not exist on this machine (real JDK: `/home/hatch/.jdk21`) — release-build verification needs that path corrected.

---

## 14. Bugs fixed, with affected files

| ID | Fix | Files | Regression test | Verification |
|---|---|---|---|---|
| D1 (P0) | `exitDemo` aborts when farmer rows reference demo parents (scans 12 CASCADE + 3 RESTRICT relations; Urdu message; never auto-deletes) | `lib/services/demo_data_service.dart` | `test/db/demo_data_test.dart` — new block test; F2 now passes | 322/322 |
| SEC1 (P1) | Save wrapped in `catch`: Urdu snackbar (InventoryException message or friendly fallback), dialog stays open, no silent state | `lib/screens/expenses_screen.dart` | `test/widget/money_dialogs_test.dart` — ThrowingInventoryProvider | 322/322 |
| S1 (P1) | My Crops card uses `computeFarmPnl(...).crops.single` — single source of truth | `lib/screens/my_crops_screen.dart` | `test/unit/my_crops_pnl_consistency_test.dart` | 322/322 |
| S6 (P1) | `updateHarvest` checks linked expense liveness; soft-deleted → inserts fresh row, repoints `expense_id` | `lib/providers/harvest_provider.dart` | `test/db/harvest_expense_mirror_test.dart` (2 tests) | 322/322 |
| S4 (P1) | `ushrAutofillMaundsText()` converts via `UnitConverter`; unconvertible → empty field | `lib/screens/ushr_screen.dart` | `test/unit/ushr_autofill_test.dart` (5 tests) | 322/322 |
| F1–F4 (P1) | Stale demo expectations updated to enriched dataset; `InventoryProvider` added to widget test tree | `test/db/demo_data_test.dart`, `test/widget/money_dialogs_test.dart` | the tests themselves | 322/322 |

Commit: `5c0e8f8` (fixes + tests; not pushed). Left out of scope: ushr rate-per-unit autofill (still copies harvest rate into «فی من»), `computeFarmPnl` ushr-basis question, 43 pre-existing analyzer infos.

---

## 15. Remaining issues and severity

**P2 (9):** D2 ushr overpayment accepted; S2 phantom income from auto Pending sales (product decision); S3 batai↔P&L gap (product decision); S5 party-ledger silo (product decision); S7 ushr in-kind doesn't reduce harvest; S8 ushr due-vs-paid basis (product decision); S9/S10 dashboard/today labels; S11 restore-sale rate divergence; S12 dead `alarm_screen`; S13 «سوز» wording; S14 dialog overflow; S15 no expense edit UI; UPD1 stale 'ورژن 1.0.0' chip (+`kAppVersion` P3).
**P3 (14):** D3 (documented accrual semantic), D4 batai double-settle (no UNIQUE), D5 accepted hard-delete paths, D6 restore skew, D7 float-modulo display, D8 custom-unit conversions, D9 farm/season audit gap, S17–S27, PERF1–3, UPD2.
**Update flow:** no in-app mechanism by design (no INTERNET); distribution is manual via Drive link; Share-APK intact. Open question: add opt-in update check (needs INTERNET + endpoint) vs status quo.

---

## 16. Installation and release instructions

- **Build (sandbox-verified recipe):** `export PATH=$HOME/flutter-sdk/flutter/bin:$PATH; export JAVA_HOME=/home/hatch/.jdk21 GRADLE_USER_HOME=/home/hatch/.gradle JAVA_TOOL_OPTIONS=-Djava.net.preferIPv4Stack=true; cd android && ./gradlew assembleRelease --no-daemon` (not `flutter build apk`). If Gradle TLS fails while curl works, the JDK truststore holds a stale Hatch proxy CA — compare `keytool -list` fingerprint vs `/etc/ssl/certs/hatch-egress-ca.pem` and re-import.
- **Do NOT cut 1.0.7 yet** — owner hasn't specified its contents; these audit fixes are committed but unreleased and unpushed.
- **Signing:** release keystore + `key.properties` gitignored (copies on Drive); `build.gradle.kts` fails loudly if absent — never debug-signs.
- **Fresh install →** splash → onboarding (fresh/demo) → dashboard. **Update install →** same package + cert = in-place update, DB preserved via `onUpgrade`.

---

## 17. Production-readiness assessment

**Not yet production-ready — but the remaining blockers are verification and product decisions, not code defects.**

| Requirement | Status |
|---|---|
| Core screens reachable, all controls implemented | ✅ 28/28, no dead stubs |
| CRUD correct | ✅ (6 P0/P1 defects fixed + tested) |
| Calculations pass test cases | ✅ exact paisa arithmetic; register verified |
| Migrations preserve data | ✅ v9→v15 chain; orphan repair |
| Backup/restore works | ✅ code-verified; **needs device round-trip** |
| Offline workflows | ✅ no network paths exist |
| Notifications as documented | ⚠️ code intact; **lock-screen alarm failed the 2026-10-04 device pass — unresolved** |
| RTL/LTR correct | ✅ (Urdu-first; English mode is future work) |
| Security findings resolved/accepted | ✅ clean sweep; accepted risks documented |
| No secrets committed | ✅ |
| Signed release APK installs & launches | ❌ **not executed here** (Gradle/JAVA_HOME path issue); 1.0.6 device-tested by user for alarms only |
| 1.0.6 expense→inventory link device-tested | ❌ **user has not tested yet** |
| README reflects actual behavior | ⚠️ 2 claims disproved (§3 table: P&L tabs, table count) — flag, don't silently rewrite |
| Tests + limitations documented | ✅ 322/322; gaps listed in §13 |

**The single highest remaining risk is the same as in October: no real-device pass on the current build.** Static evidence is strong; the lock-screen alarm failure from 2026-10-04 is still unexplained on-device, and the flagship 1.0.6 inventory link has never run on a phone.

---

## Appendix A — Method & provenance

Strand 1 (baseline): env/analyze/test/CVE. Strand 2 (screens/nav/UI): 28-screen inventory, 5 journey traces, README cross-check. Strand 3 (DB/calc): schema/FK/txn/migration verdicts, calculation register. Strand 4 (security/offline/perf): manifest/secrets/native-SQL re-verification, 1.0.6 link review. Strand 5 (fixes): 6 fixes + 13 regression tests, commit `5c0e8f8`. Parent addendum: in-app update-flow audit (§15). All static except the executed unit/widget/db suite. Nothing was pushed.
