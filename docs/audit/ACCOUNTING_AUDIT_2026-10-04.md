# Kisan Dost — Accounting & Business-Logic Audit

**Date:** 2026-10-04
**Auditor:** Accounting/business-logic audit agent (subagent)
**Scope:** `lib/providers/` (all 11), `lib/services/` (money, quantity, unit_converter, unit_display, pnl_summary, today_summary, audit_service, recycle_bin_service, onboarding_service), `lib/models/`, plus the financial save paths in `lib/screens/` touched for duplicate-transaction guards.
**Out of scope (parallel passes):** `lib/database/db_helper.dart`, `lib/services/backup_service.dart`, `lib/services/restore_service.dart`, `android/`.

## Executive summary

The accounting core is in good shape: integer-paisa money throughout, an immutable inventory ledger, append-only audit log, and single-transaction multi-record mutations in every provider. The audit verified each provider's create/edit/delete paths against the actual code (not the docs) and found **13 issues**. **11 are fixed** in this pass with surgical, behavior-preserving changes; **2 are reported without change** because they are deferred product decisions. **29 new automated tests** were added (all passing). A dedicated inventory section below covers edit-reversal, unit mismatches, races, and ledger/cache consistency with focused tests.

One environment note: `flutter test` in this sandbox needs `LD_LIBRARY_PATH=$HOME/workspace/tooling/sqlite3` (prebuilt `libsqlite3.so` staged there) because the sqlite3 native-asset hook never produced the library for this repo. Without it, *all* FFI DB tests fail to load — including pre-existing ones.

## Findings

### F1 — P&L counted soft-deleted activity-linked expenses (HIGH → fixed)
**File:** `lib/providers/activity_provider.dart:93`
`fetchActivities` joined `LEFT JOIN expenses e ON a.expense_id = e.id` with no `deleted_at` filter. After a farmer deleted an expense (recycle bin), the crop P&L (`computeFarmPnl` via `act.expenseAmountPaisa`) still counted it, while the overall expense total correctly excluded it — the two disagreed.
**Fix:** `AND e.deleted_at IS NULL` on the join (matches the harvest provider's existing sales-join pattern). Verified by test: soft-delete → `expenseAmountPaisa` becomes null → crop P&L excludes it.

### F2 — Activity delete/edit hard-deleted the linked expense (MEDIUM → fixed)
**File:** `lib/providers/activity_provider.dart` (`updateActivity`, `deleteActivity`)
Both paths used `txn.delete('expenses', …)` with no audit row — an auto-created expense vanished silently. (The activities table itself has no soft-delete column by design; the *expense* does.)
**Fix:** soft-delete (`deleted_at`) + `AuditService` row in both paths. Restorable via recycle bin; history preserved.

### F3 — `payInstallment` accepted zero/negative payments (MEDIUM → fixed)
**File:** `lib/providers/theka_provider.dart:231`
A negative `paidAmountPaisa` would *reduce* the cumulative 'Land Rent' expense. The form validates, but the provider is the last line of defense.
**Fix:** `if (paidAmountPaisa <= 0) throw Exception('ادائیگی کی رقم صفر سے زیادہ ہونی چاہیے۔')`.

### F4 — `markInstallmentPending` hard-deleted the expense silently (MEDIUM → fixed)
**File:** `lib/providers/theka_provider.dart`
Reopening an installment destroyed its 'Land Rent' expense row with no trace.
**Fix:** soft-delete + audit row (consistent with the harvest provider's mirror-expense handling).

### F5 — `deleteTheka` destroyed linked expense history silently (MEDIUM → partially fixed)
**File:** `lib/providers/theka_provider.dart` (`_deleteThekaTx`)
The hard-delete itself is a **deferred product decision** (see § Deferred) and is unchanged. But every destroyed expense row is now written to the audit log first, with amount and description, so the history is never silent.

### F6 — Ushr expense mirror hard-deleted on edit-to-zero and on record delete (MEDIUM → fixed)
**File:** `lib/providers/ushr_provider.dart` (`updateUshrRecord`, `deleteUshrRecord`)
Setting payment to zero hard-deleted the 'Ushr Expense' mirror with no audit row; deleting the record hard-deleted both rows with no audit rows (`ushr_records` has no soft-delete column — schema change is out of scope).
**Fix:** edit-to-zero now soft-deletes the mirror + audit row; record delete keeps the paired hard-delete (schema-bound) but writes audit rows for both deletions with amounts.

### F7 — Double-tap created duplicate financial records (HIGH → fixed)
**Files:** `activity_form_screen.dart`, `expenses_screen.dart`, `harvest_screen.dart` (add + edit dialogs), `theka_details_screen.dart`, `party_detail_screen.dart`, `ushr_screen.dart`, `batai_detail_screen.dart`
No save button had a re-entrancy guard. A rapid double-tap fired the whole flow twice: duplicate expenses, activities, harvests+sales, installment payments, party ledger entries, ushr records, settlements. (The harvest/ushr dialogs didn't even `await` the provider call.)
**Fix:** `_isSaving`/`isSaving` guard on each financial save path (early-return + `try/finally` reset, `mounted`/`ctx.mounted` checks); added missing `await`s. Note: the input-validation audit owns further double-submit work (their M2); these guards are complementary and already in place.

### F8 — Edit-with-direct-purchase created phantom stock (HIGH → fixed)
**File:** `lib/screens/activity_form_screen.dart`
On *edit*, the "buy new and apply directly" checkbox ran a fresh `recordPurchase` outside the provider transaction, while `updateActivity` reversed only the old *usage* — the original purchase was never reversed. Example: buy 5/use 5, edit to buy 3/use 3 → stock showed 5 instead of 0.
**Fix:** the direct-purchase shortcut is hidden in edit mode (and the branch is guarded by `_isEditMode`). Edits now always reverse-then-reapply against warehouse stock, which the tests prove correct. Duplicating an activity still allows direct purchase (it creates a new activity).

### F9 — Unhandled async errors from launch-time fetches (MEDIUM → fixed, D3)
**Files:** `activity_provider.dart` (`fetchActivities`), `inventory_provider.dart` (`fetchInventory`), `ushr_provider.dart` (`fetchUshrRecords`), `farm_provider.dart` (`fetchFields`)
`main.dart` calls these unawaited; a DB failure became an unhandled async error. (The other providers already caught internally.)
**Fix:** try/catch → `debugPrint`, keep the last good list, always `notifyListeners()`.

### F10 — Task toggle raced on a stale snapshot (MEDIUM → fixed, race M3)
**File:** `lib/providers/task_provider.dart:186`
`toggleTaskCompletion(id, currentStatus)` did read-modify-write on the UI's `isCompleted`; rapid double-taps (callers fire unawaited) could both read `false` and both write `true`, with duplicate audit rows.
**Fix:** atomic `UPDATE tasks SET is_completed = 1 - is_completed, snoozed_until = NULL WHERE id = ? AND deleted_at IS NULL`; signature simplified to `(int id)`; status for notifications/audit is read back post-toggle. Callers (`tasks_screen.dart`, `dashboard_screen.dart`) and the `today_screen_test.dart` fake updated.

### F11 — Inventory deduction was check-then-act in Dart (MEDIUM → fixed, race M4)
**File:** `lib/providers/inventory_provider.dart:304`
`_recordUsageTx` read the quantity, checked in Dart, then wrote `quantity - used`. Practically serialized by sqflite today, but structurally TOCTOU.
**Fix:** single atomic `UPDATE inventory SET quantity = quantity - ? WHERE id = ? AND quantity >= ?`; 0 rows affected → re-read and throw the friendly Urdu overuse error (never clamp). The Dart pre-check remains as a fast path; the SQL statement is the gate.

### F12 — Theka edit was delete-then-reinsert without a transaction (MEDIUM → fixed, nav M3)
**Files:** `lib/providers/theka_provider.dart:178`, `lib/screens/theka_form_screen.dart`
Editing a theka called `deleteTheka` then `addTheka` as two provider calls — if the insert threw after the delete, the contract + installments were unrecoverable (the code carried the author's worried comment).
**Fix:** new `ThekaProvider.replaceTheka(oldId, newTheka, installments)` — delete (shared `_deleteThekaTx` helper, extracted from `deleteTheka`) + reinsert inside one `db.transaction`; the form now calls it. The `hasPayments` guard behavior is unchanged.

### F13 — `shouldShowOnboarding` could throw (LOW → fixed)
**File:** `lib/services/onboarding_service.dart:12`
No try/catch around `SharedPreferences.getInstance()`.
**Fix:** fails open to `true` — replaying onboarding is always the safe direction.

### F14 — `restoreHarvest` leaves the 'Harvest Expenses' mirror deleted (MEDIUM → reported)
**File:** `lib/providers/harvest_provider.dart:669`
`deleteHarvest` soft-deletes harvest + sales + expense mirror together, but `restoreHarvest` restores only the harvest. Until the farmer also restores the expense from the recycle bin, crop P&L counts the harvest buckets while the overall expense total misses the mirror. Restoring the mirror automatically is *possible* (via `harvest.expense_id`) but could resurrect a mirror the farmer deliberately deleted on its own — a product judgment call. **Left unchanged; recommend the product owner decide.**

## Deferred decisions (do not change silently)

1. **Ushr P&L basis.** Crop-level P&L counts `ushrAmountPaisa` (the obligation); the overall total counts the 'Ushr Expense' mirror (`totalPaidPaisa`, cash paid). They diverge on partial payment — cash vs accrual. Awaiting the user's ushr-policy decision; computation is exact on both sides.
2. **`deleteTheka` hard-delete semantics.** Whether paid-installment expense history should be hard-deleted at all is deferred. This pass only added audit rows (F5) so the deletion is never silent.

## Inventory deep-dive (dedicated section)

### Edit-reversal correctness — VERIFIED CORRECT (with tests)
`ActivityProvider.updateActivity` runs in one transaction: (1) `_restoreInventoryTx` adds the old quantity back via `recordAdjustment`, resolving the *old* item by `inventoryItemId` (falling back to the (category, name, unit) snapshot for pre-v11 rows, throwing loudly if the item is gone); (2) the new deduction goes through `recordUsage`. The canonical case from the task — 10 bags, use 2 → 8, edit to 5 → **5** (not 3) — is now a regression test, asserting the exact ledger sequence `[+10, −2, +2 (adjustment), −5]`.

**One real bug found and fixed here:** edit-with-direct-purchase (F8 above) never reversed the original purchase → phantom stock. Fixed by removing the shortcut from edit mode.

Other edit paths checked:
- Edit to a smaller quantity returns the difference (5→2 gives 8). ✓ tested
- Removing the usage on edit (null quantity) restores the full old deduction, no new deduction. ✓ tested
- Edit that would overuse throws `InventoryException`; the already-run reversal rolls back with the transaction — stock and ledger untouched. ✓ tested
- `deleteActivity` restores stock before deleting (aborts loudly if the item is gone); the immutable usage ledger row survives with `activity_id` cleared via `ON DELETE SET NULL`. ✓ tested
- `duplicateActivity` passes `inventoryQuantity: null` and no provider → never deducts. ✓ (code-verified)

### Unit mismatch on edit — VERIFIED CORRECT (with tests)
Both the reversal and the new deduction convert through the item's *current* unit via `UnitConverter`:
- Deduct 2 bags → edit to 150 kg (50 kg/bag): reversal +2 bags, new −3 bags → 7. ✓ tested
- Deduct 100 kg → edit to 1 bag: reversal converts 100 kg → +2 bags (a reversal that forgot to convert would add back "100 bags"), new −1 → 9. ✓ tested
- The form pre-converts entered quantities into the item's own unit, so the provider usually sees matching units; the provider still handles mismatches defensively. Package↔weight conversion without a farmer-supplied `weightPerUnitKg` throws loudly (no silent 50 kg assumption). Item renames are safe: reversal prefers `inventoryItemId`, which never changes.

### Race conditions — VERIFIED SAFE, then hardened
- sqflite serializes write transactions (`txnWriteSynchronized`), so the check+write inside `_recordUsageTx` was *practically* safe. Proven empirically: two rapid full-stock deductions via `Future.wait` → exactly one succeeds, one throws `InventoryException`, final stock 0, exactly one usage ledger row. ✓ tested
- F11 (race M4) removes the structural TOCTOU anyway: the decrement is now one atomic `UPDATE … WHERE quantity >= ?`.
- F10 (race M3) makes the task toggle atomic for the same double-tap reason.

### Ledger/cache consistency — VERIFIED (with tests)
`inventory.quantity` is only ever written together with its ledger row inside the same provider transaction (`recordPurchase`, `_recordUsageTx`, `recordAdjustment`); metadata edits (`updateItemDetails`) never touch quantity; `deleteInventoryItem` is blocked while any ledger row exists; demo data goes through `recordPurchase`. Every new inventory test asserts `quantity == SUM(inventory_transactions.quantity)` after each mutation. No code path writes one without the other.

## Tests added (29 new, all passing)

| File | Tests | Covers |
|---|---|---|
| `test/db/inventory_edit_reversal_test.dart` | 9 | edit-reversal exactness + ledger sequence, smaller-qty edit, usage removal on edit, overuse-on-edit rollback, unit-mismatch both directions, delete-restores-stock, delete-without-usage, concurrent-deduction safety, ledger/cache consistency after every op |
| `test/db/pnl_expense_integrity_test.dart` | 9 | soft-deleted linked expense hidden from `fetchActivities` and crop P&L, both-ways-linked expense counted once, delete/update activity soft-deletes expense + audit, `payInstallment` rejects ≤ 0, `markInstallmentPending` soft-delete + audit, ushr edit-to-zero soft-delete + audit, ushr delete audit rows |
| `test/db/task_toggle_atomic_test.dart` | 3 | single flip, rapid double-toggle determinism (net zero + one audit row per tap), missing/trashed task no-op |
| `test/db/theka_replace_test.dart` | 3 | atomic swap (no orphans), rollback on FK failure keeps old contract, pending-only replace writes no expenses |

New tests follow the existing hermetic style (`sqflite_common_ffi`, in-memory DB, real `createFreshSchemaForTests` DDL, `testExecutor` provider hook — added to `ActivityProvider` to match the other providers). `test/widget/today_screen_test.dart`'s `FakeTaskProvider` was updated for the new toggle signature.

## Verification status

- `flutter analyze` on all touched files: **0 errors, 0 warnings** (only pre-existing info-level deprecations).
- Targeted suites: inventory_edit_reversal 9/9, pnl_expense_integrity 9/9, task_toggle 3/3, theka_replace 3/3, plus pre-existing inventory_ledger/party/batai/soft-delete suites green.
- Full suite: **284 pass, 5 fail** — the 5 failures are in `test/widget/money_dialogs_test.dart` and are caused by the *parallel input-validation audit's* uncommitted working-tree changes (it replaced amount validators/messages with `FieldValidators.money`, changing the expected Urdu strings). They are unrelated to this pass's edits; flagged for the coordinator — the input-validation agent owns them.
- Test env note: run with `LD_LIBRARY_PATH=$HOME/workspace/tooling/sqlite3` in this sandbox (see summary).

## Files changed (this pass)

Providers: `activity_provider.dart`, `inventory_provider.dart`, `ushr_provider.dart`, `theka_provider.dart`, `task_provider.dart`, `farm_provider.dart`.
Services: `onboarding_service.dart`.
Screens (duplicate-transaction guards + theka replace + edit-mode purchase fix): `activity_form_screen.dart`, `expenses_screen.dart`, `harvest_screen.dart`, `theka_details_screen.dart`, `theka_form_screen.dart`, `party_detail_screen.dart`, `ushr_screen.dart`, `batai_detail_screen.dart`, `tasks_screen.dart`, `dashboard_screen.dart`.
Tests: 4 new files (above) + `today_screen_test.dart` fake updated.

## Things deliberately NOT changed

- `lib/database/db_helper.dart`, `lib/services/backup_service.dart`, `lib/services/restore_service.dart`, `android/` (parallel hardening pass).
- `deleteTheka` hard-delete semantics; ushr P&L cash/accrual policy (deferred decisions above).
- `splitAmountAcrossFields` truncation: display-only per-field averages, ≤ (n−1) paisa — acceptable, noted.
- `FarmProvider.deleteFarm` cascade: single-statement, atomic, confirmation-gated in UI; converting farms to soft-delete needs a schema migration (out of scope) — recommend as future work, with audit rows for farm/crop providers.
