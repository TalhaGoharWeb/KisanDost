# Kisan Dost — Production Testing Strategy (2026-10-04)

## 1. Current state

**301 tests across 37 files** (was ~210 before the 2026-10-04 audit wave).
All hermetic: in-memory FFI SQLite via `sqfliteFfiInit`, providers take a
`testExecutor`, method channels mocked, `SharedPreferences.setMockInitialValues`.

### Coverage inventory (existing)

| Area | Files | Tests | Verdict |
|---|---|---|---|
| Backup/restore | `test/db/backup_restore_test.dart` | 15 | ✅ strong (atomic restore, tamper, migration, merge) |
| Inventory ledger | `test/db/inventory_ledger_test.dart` | 18 | ✅ strong |
| Inventory edit-reversal | `test/db/inventory_edit_reversal_test.dart` | 9 | ✅ (added by inventory audit) |
| Batai/sharecropping | `test/db/batai_test.dart` | 30 | ✅ strong |
| Party ledger/udhaar | `test/db/party_ledger_test.dart` | 12 | ✅ |
| Soft delete + recycle bin + audit log | `test/db/soft_delete_audit_test.dart` | 10 | ✅ |
| P&L / expense integrity | `test/db/pnl_expense_integrity_test.dart` | 9 | ✅ (added by accounting audit) |
| Money (paisa math, migration) | `test/unit/money_test.dart`, `money_migration_test.dart`, `phase12_money_paths_test.dart` | 26 | ✅ |
| Unit conversion | `test/unit/unit_converter_test.dart`, `quantity_test.dart`, `unit_display_test.dart` | 26 | ✅ |
| Migrations | `test/db/migration_test.dart` | 2 | ⚠️ thin |
| Demo data | `test/db/demo_data_test.dart` | 3 | ✅ |
| Merge audit | `test/db/merge_audit_test.dart` | 3 | ✅ |
| Input validation | `test/widget/field_validators_test.dart` | 14 | ✅ (added by validation audit) |
| Error messages (Urdu) | `test/unit/error_messages_test.dart` | 7 | ✅ (added by crash audit) |
| Theka replace (transactional) | `test/db/theka_replace_test.dart` | 3 | ✅ (added by accounting audit) |
| Task toggle atomicity | `test/db/task_toggle_atomic_test.dart` | 3 | ✅ (added by accounting audit) |
| CSV/PDF export | `test/unit/export_service_test.dart`, `test/widget/pdf_report_test.dart` | 18 | ✅ |
| Widgets (today, onboarding, dialogs, banner, digit text, locale) | `test/widget/*` | 40 | ✅ |
| **NEW — farm/field CRUD** | `test/db/farm_field_crud_test.dart` | 8 | ✅ added this pass |
| **NEW — crop↔field relationships** | `test/db/crop_relationship_test.dart` | 5 | ✅ added this pass |
| **NEW — harvest/sale calculations** | `test/db/harvest_sale_calculations_test.dart` | 6 | ✅ added this pass |
| **NEW — delete-all-data wipe** | `test/db/delete_all_data_test.dart` | 3 | ✅ added this pass |
| **NEW — manifest security** | `test/android/manifest_security_test.dart` | 7 | ✅ added this pass |
| **NEW — audit regressions** | `test/db/audit_regression_test.dart` | 10 | ✅ added this pass |
| **NEW — task↔alarm interactions** | `test/db/task_alarm_interactions_test.dart` | 7 | ✅ added this pass |

## 2. Gap analysis vs priority areas

| # | Priority area | Before | After | Notes |
|---|---|---|---|---|
| 1 | Database CRUD (per table) | partial | **good** | farms/fields/crops/harvests/sales now covered; thekas/ushr/activities covered by accounting agent's tests |
| 2 | Inventory calculations | ✅ | ✅ | edit-reversal, negative-stock, ledger consistency covered |
| 3 | Unit conversions | ✅ | ✅ | no change needed |
| 4 | Expense calculations | ✅ | ✅ | paisa math + P&L integrity covered |
| 5 | Crop/field relationships | ❌ | ✅ | new: FK enforcement, cascade, duplicate-link, empty-selection |
| 6 | Harvest calculations | ❌ | ✅ | new: expense buckets, sale totals, rounding, soft-delete |
| 7 | Sales calculations | ❌ | ✅ | new: recompute-not-trust, missing-harvest no-op |
| 8 | Profit/loss | ✅ | ✅ | accounting agent's tests |
| 9 | Task planner | ⚠️ | ✅ | new: scheduling decision logic (skip completed/past) |
| 10 | Alarm schedule/cancel/reschedule | ❌ | ⚠️ | **platform limit** (see §4): behavioral coverage via provider contract + source-structure regressions; true E2E needs Android instrumentation |
| 11 | Device reboot recovery | ❌ | ⚠️ | Kotlin `rescheduleAllAlarms` logic pinned by source regression (reminders toggle); full boot test needs instrumentation |
| 12 | Delete-all-data | ❌ | ✅ | new: 19-table completeness, idempotent re-wipe, schema intact |
| 13 | Backup/restore | ✅ | ✅ | no duplication; extended only via audit_regression (atomic temp staging, streaming hash) |
| 14 | Critical navigation flows | ⚠️ | ⚠️ | today/onboarding covered; **remaining**: form→list refresh flows (widget-test gap, §5) |

## 3. What was added this pass (46 tests, all passing, analyze clean)

1. **`test/db/farm_field_crud_test.dart`** (8) — farm/field CRUD, FK rejects
   orphan fields, farm delete cascades to fields, field update/delete.
2. **`test/db/crop_relationship_test.dart`** (5) — season↔field links exact,
   empty selection throws, duplicate link ignored (UNIQUE), bad field FK
   rejected, season delete keeps fields.
3. **`test/db/harvest_sale_calculations_test.dart`** (6) — expense bucket
   sums, sale total recomputed (never trusted), paisa rounding, missing
   harvest no-op, sale soft-delete keeps history + resets rate.
4. **`test/db/delete_all_data_test.dart`** (3) — all 19 tables emptied,
   re-wipe safe, schema usable immediately after.
5. **`test/android/manifest_security_test.dart`** (7) — allowBackup=false,
   cleartext denied + config present, MainActivity lock-screen flags absent,
   alarm components not exported, not debuggable, no INTERNET permission.
6. **`test/db/audit_regression_test.dart`** (10) — source-structure pins for
   every Kotlin/Dart audit fix that can't be behavior-tested on the host
   (F1–F5 alarm fixes, lock-screen bypass, transactional wipe, atomic
   restore, streaming hash).
7. **`test/db/task_alarm_interactions_test.dart`** (7) — best-effort
   contract: mutations never throw with backend down; scheduling decision
   logic (completed/past/no-op) through NotificationService.

## 4. Known test-platform limits (documented, not worked around)

- **AlarmManager / exact alarms / boot receiver** are Kotlin/Android-only.
  `flutter test` runs on Linux where `Platform.isAndroid` is false and the
  notification plugin resolves to the Linux implementation (not the method
  channel), so plugin calls are unobservable. Mitigation: source-structure
  regression tests + a **real-device checklist** (reboot with reminders off,
  restore-from-bin re-arm, deny exact-alarm → fallback, alarm fires in Doze).
- **FileProvider / share sheet / permission dialogs** need instrumentation
  or manual tests.
- **R8/minify correctness** is verified by the release build, not unit tests.

## 5. Remaining work (prioritized)

1. **Widget tests for 3 critical flows** (form→save→list-refresh for expense,
   harvest, task) — catches double-submit and stale-list regressions the
   UI/nav audit flagged. Estimated 6–9 tests.
2. **Migration test depth** — only 2 tests; add v15→v16 when the next
   migration lands (the pattern in `migration_test.dart` is the template).
3. **Android instrumentation tests** (new `androidTest/` dir) for: boot
   reschedule, exact-alarm permission denial, FileProvider share round-trip.
   Requires a device/emulator; out of scope for `flutter test`.
4. **Fuzz/property tests** for the unit converter (round-trip across all
   unit pairs) — cheap, high value for the "never wrong units" guarantee.
5. **Performance**: backup of a large DB (streaming hash is covered; add a
   10k-row insert benchmark as a regression guard if insert paths change).

## 6. How to run

```bash
# Sandbox needs the system sqlite for FFI tests:
export LD_LIBRARY_PATH=/tmp/sqlitelib:$LD_LIBRARY_PATH   # /tmp/sqlitelib/libsqlite3.so -> libsqlite3.so.0

# One file (do NOT run the full suite while other agents are editing):
flutter test test/db/<file>_test.dart

# Static analysis on changed files:
flutter analyze <paths...>

# Full suite (only when no agent is working):
flutter test
```

Test conventions (follow these for new tests):
- `sqfliteFfiInit(); databaseFactory = databaseFactoryFfi;` at top of `main()`.
- Real schema via `DatabaseHelper.instance.createFreshSchemaForTests(db)`
  — never hand-copy DDL (it drifts).
- Providers take `testExecutor: db` — the app singleton is never touched.
- `TestWidgetsFlutterBinding.ensureInitialized()` +
  `SharedPreferences.setMockInitialValues({})` when providers/services need them.
- Mock `MethodChannel('com.talhagohar.kisandost/share')` and
  `'dexterx.dev/flutter_local_notifications'` as no-ops for task tests.
- Name files `test/<area>/<name>_test.dart`; never edit another agent's test file.
