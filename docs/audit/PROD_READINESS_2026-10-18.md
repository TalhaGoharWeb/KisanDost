# Kisan Dost — Production-Readiness Final Report (§19)

**Date:** 2026-10-18
**Branch:** `prod-readiness` (from `7344e5e`; audit-fix parent `5c0e8f8` verified present)
**Scope:** all 20 sections of the Master Engineering Prompt. **Owner overrides applied:** app stays purely Urdu (no EN/Roman work); no 1.0.7 release and no APK distribution; nothing pushed — all commits local.
**Method:** 4 parallel engineering strands (finance, functional, UI/UX, security) with strictly disjoint file ownership + coordinator verification (analyze, full test suite, signed release assemble). No real device in sandbox — device-only items marked **Not verified**, never Passed.

---

## A. Updated application

7 local commits on `prod-readiness` (working tree clean):

| Commit | Content |
|---|---|
| `d9b361c` | Phase 1: baseline inventory + defect register (`BASELINE_2026-10-18.md`) |
| `af04b01` | Financial policy + D2/S7/S11 fixes + 19 regression tests (`FINANCIAL_POLICY_2026-10-18.md`) |
| `c6a383a` | Functional completeness: UPD1/S9/S10/S14/S15/S18/S19 (+notification_service S12 hunks) |
| `6cd3ed7` | Removed dead `alarm_screen.dart` (S12) |
| `ee65576` | UI/UX: S22 phone validation, batai cards, RTL fix |
| `e9350f3` | Security: S13 سنوز wording, `SECURITY_2026-10-18.md` |
| (+1) | macOS generated registrant for `package_info_plus` |

## B. Audit resolution report (per finding)

**Previously fixed (5c0e8f8, re-verified by suite):** D1 (P0, demo-exit data loss), SEC1/S1/S6/S4/F1–F4 (P1). All regression tests pass in the 341-test suite.

**Fixed this mission:**

| ID | Sev | Root cause | Files | Fix | Test | Result |
|---|---|---|---|---|---|---|
| D2 | P2 | `addUshrRecord` accepted any amount | `ushr_provider.dart`, `ushr_screen.dart` | `validatePaymentWithinDue` before write; Urdu error, dialog stays open | `test/unit/ushr_payment_guard_test.dart` (7) | ✅ pass |
| S7 | P2 | in-kind ushr never reduced harvest qty | `ushr_provider.dart` | `_adjustHarvestInKind`: proportional undo/redo inside `_txn`; legacy-marker guard | `test/db/ushr_in_kind_harvest_test.dart` (9) | ✅ pass |
| S11 | P2 | `restoreSale` left zeroed rate | `harvest_provider.dart` | restore `rate_per_unit_paisa`+`buyer_name` from sale row; re-sale wins | `test/db/harvest_restore_sale_test.dart` (3) | ✅ pass |
| UPD1 | P2 | hardcoded 'ورژن 1.0.0' | `about_us_screen.dart`, `pubspec.yaml` | `package_info_plus` real version | — (platform channel; verified by reading) | ✅ code-verified |
| S9 | P2 | lifetime diary labeled "today" | `todays_work_screen.dart` | date filter, default today, date-aware headings | — | ✅ code-verified |
| S10 | P2 | TODAY ignored `isLoading` | `dashboard_screen.dart` | spinner until loaded; never false all-clear | — | ✅ code-verified |
| S12 | P2 | dead screen, rogue handlers | `alarm_screen.dart` deleted; `notification_service.dart`, `dashboard_screen.dart` refs removed | native path is 100% of alarms; FLN IDs never existed | zero refs repo-wide | ✅ code-verified |
| S13 | P2 | «سوز» typo (user-visible) | 3 Kotlin/XML + `notification_service.dart` (4×) | → «سنوز» | — | ✅ |
| S14 | P2 | unbounded pickers; fake export success | `reports_screen.dart` | searchable 50%-height pickers; empty-data Urdu notice | — | ✅ code-verified |
| S15 | P2 | delete-only expense rows | `expenses_screen.dart` | edit dialog reusing form+validators; SEC1 catch preserved | — | ✅ code-verified |
| S18 | P3 | "irreversible" delete copy | `expenses_screen.dart` | recycle-bin truthful wording | — | ✅ |
| S19 | P3 | no warning on system-linked deletes | `expenses_screen.dart` | red Urdu warning for Harvest/Ushr/Land-Rent mirrors | — | ✅ |
| S22 | P3 | unvalidated batai phone | `field_validators.dart`, `batai_screen.dart` | `phonePkOptional` (03xx, +92/Urdu-digit tolerant) | 18-case logic script | ✅ pass |

**Documented, not changed (owner decisions — see FINANCIAL_POLICY_2026-10-18.md):** S2 (accrual vs cash), S3 (batai↔P&L), S5 (ledger↔P&L), S8 (ushr due-vs-paid), `deleteTheka` expenses, `restoreHarvest` mirror, backup encryption, lock-screen redaction, in-app-update approach, new Q7 (`payment_status` after restoreSale).

**Remaining P3 (not fixed, listed):** D3–D9, S17, S20, S21, S23–S27, PERF1–3, UPD2 (`kAppVersion` in backup_service), parties-dialog phone consistency, `EmptyStateWidget` 24sp on short screens.

## C. Feature verification matrix

28/28 features inventoried (`BASELINE_2026-10-18.md`). **Implemented and verified:** 1, 3, 4, 5, 6, 8, 9, 11, 15, 22, 23, 24, 27, 28. **Implemented, code-verified, device-pending:** 2, 7, 10, 12, 13, 14, 16, 17, 18, 19, 20, 21, 25, 26. **None** partially implemented / defective / planned. English mode: not applicable (Urdu-only per owner).

## D. Financial calculation report

Integer-paisa arithmetic end-to-end (unchanged). New verified cases (hand-computed): ushr overpayment blocked at exactly remaining+1 paisa; in-kind 2 من of 100 من harvest → 98.0 remaining; kg proportionality 4000→3920; no-drift across edit chains (98→95→95→99); restoreSale: 40 من @ Rs 3,500 → harvest gross 14,000,000 paisa agrees with sale total. Rounding rules unchanged (input >2dp rejected; half-away-from-zero on qty×rate; batai remainder→larger share). Full register: `CALCULATION_REGISTER_2026-10-18.md` + `FINANCIAL_POLICY_2026-10-18.md`.

## E. Security report

Full: `SECURITY_2026-10-18.md`. Threat model: single-user offline — local-data + supply-chain scope. **Findings:** S13 fixed; F1 (third exported receiver — flutter_local_notifications' documented boot receiver, negligible); F2 lock-screen visibility = owner decision (documented, unchanged); F3 Cloudflare token in website config = public identifier, not a leak. **Re-verified clean:** no INTERNET permission; minimal exports; PendingIntents immutable; native SQL parameterized; backup import traversal-safe; signing fails loudly without config; secrets sweep over 110 commits clean; 0 dependency CVEs at locked versions (re-checked post-`package_info_plus`).

## F. Test report (real output)

- `flutter analyze`: **0 errors, 0 warnings**, 44 info (43 pre-existing + 1 pre-existing category; none new-error class).
- `flutter test` (full suite, run alone, /tmp cleared, sqlite symlink present): **341/341 PASS** — 322 baseline + 19 new (7 ushr-guard unit, 9 ushr-in-kind db, 3 harvest-restore db). 0 failed, 0 skipped.
- Widget/integration: new tests are db/unit-level; scenario traces A–I verified statically (no device). **Not run:** Gradle assemble before this mission (now Phase 8), on-device alarm/backup/upgrade tests — marked Not verified.

## G. Release artifact (build evidence — verification only, NOT distributed)

- **Command:** `cd android && ./gradlew assembleRelease --no-daemon` with `JAVA_HOME=/home/hatch/.jdk21` (the prompt's `/home/hatch/jdk21` does not exist — corrected). **BUILD SUCCESSFUL** in ~8.5 min.
- **Artifact:** `build/app/outputs/apk/release/app-release.apk` (kept local; not uploaded anywhere)
- **Identity:** package `com.talhagohar.kisandost`, versionCode **7**, versionName **1.0.6**
- **Size:** 76,678,536 bytes
- **SHA-256:** `446328cda303b3e0c85347582d7ac415fa47c54081b0bf99a78b96e130dc1f26`
- **Signing:** release cert `CN=Kisan Dost, OU=Farming App, O=Talha Gohar, L=Lahore, C=PK`, cert SHA-256 `f0357ce7…fae6e150` (matches the 1.0.6 release identity; apksigner verify clean)
- **1.0.0+1 regression check:** alarm sound asset `res/xA.mp3` (66,708 B) present — shrinker did not strip it; native `AlarmScheduler` classes present in classes.dex
- **Environment trap found & fixed:** stale `android/local.properties` (gitignored) carried `flutter.versionName=1.0.1`/`versionCode=2` from an old build; first assemble produced a 1.0.1+2 APK. Fixed the two lines to 1.0.6/7 and rebuilt. Lesson: when running Gradle directly (not `flutter build`), the Flutter plugin reads versions from `local.properties`, never pubspec.
- **Not done:** install/launch on a device (no device in sandbox); no distribution per owner override; version stays 1.0.6+7.

## H. Documentation and release notes

New: `BASELINE_2026-10-18.md`, `FINANCIAL_POLICY_2026-10-18.md`, `SECURITY_2026-10-18.md`, this report. Updated: none of the user docs needed changes (behavior changes are bug fixes, not feature changes). **Known doc debts (flagged, not silently rewritten):** README "P&L per-farm tabs" and "19 tables" claims disproved by code (from Oct audit); `kAppVersion` P3.

## I. Executive summary

1. **What was wrong?** 1 P0 (demo-exit data loss) + 5 P1 from October, all already fixed; this mission fixed 10 P2 + 4 P3 (overpayment acceptance, in-kind ushr not reducing harvest, restore-sale rate divergence, stale version chip, mislabeled diary, dashboard false all-clear, dead alarm screen, picker overflows, fake export success, delete-only expenses, snooze typo, phone validation).
2. **What was fixed?** §B table — every fix has a regression test or code-verification note.
3. **Features improved?** Ushr integrity, harvest lifecycle, expenses CRUD, diary filtering, dashboard honesty, reports UX, version truthfulness.
4. **Security risks remaining?** Accepted: plaintext backups, lock-screen alarm content visibility, no UNIQUE on inventory identity. No critical/high open findings.
5. **Tests passed?** 341/341, analyze clean.
6. **APK built/installed?** Built ✅ (§G: 1.0.6+7, signed, 76.7 MB, SHA-256 recorded, alarm asset present). Install/launch on device: Not verified (no device in sandbox).
7. **Verified on real hardware?** Nothing this mission — device pass is the top remaining item (alarms, 1.0.6 inventory link, backup round-trip).
8. **Production-ready?** **Not yet** — code is in the strongest state it's been (341 green, 0 analyzer errors, 10 P2s closed), but production-ready requires the real-device pass and 9 owner decisions (§B).
9. **Exact blockers:** (a) real-device verification (alarms incl. lock-screen, reboot, snooze; 1.0.6 expense→inventory; backup/restore round-trip; upgrade from 1.0.5); (b) owner decisions on S2/S3/S5/S8/deleteTheka/restoreHarvest-mirror/backup-encryption/lock-redaction/update-approach/payment_status; (c) 1.0.7 scope definition (owner hasn't specified contents — these fixes are committed, unreleased, unpushed).
