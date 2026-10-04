# Input Validation Audit — Kisan Dost (2026-10-04)

**Auditor:** input-validation subagent (screens/widgets scope)
**Scope:** `lib/screens/`, `lib/widgets/`, `lib/l10n/` — every user input in all 28 screens.
**Out of scope (parallel audits):** `lib/providers/`, `lib/services/`, `lib/database/`, `lib/models/`, `android/`, `test/db/`.

## Method

Opened every screen file; catalogued every `TextFormField`/`TextField`, dropdown,
date/time picker, and input dialog; traced each value from the field through its
validator (or lack of one) into the save handler; checked `TextInputType`,
parse-crash vectors (`int.parse`/`double.parse` on unvalidated text), upper
bounds, malformed input, locale digits, and message language.

## Architecture found

Screens do light field validation; providers do deep validation throwing Urdu
exceptions (`MoneyParseException`, `QuantityParseException`, `BataiException`,
`PartyException`) surfaced as SnackBars. All `Form`s call
`_formKey.currentState!.validate()` before saving. `Money.parse` /
`Quantity.parse` accept Urdu/Persian digits, commas, and the روپے suffix —
locale handling is good. Date/time inputs all use `showDatePicker` /
`showTimePicker` bounded to 2000–2100; no free-text date parsing on save paths.

## Critical finding: `Money.parse` integer-overflow crash (FIXED at screen level)

`Money.parse` calls raw `int.parse` on the digit group. A ~20-digit input
overflows 64-bit int and throws a raw **`FormatException`** — NOT the Urdu
`MoneyParseException`. Every screen caught only `MoneyParseException`, so typing
e.g. 25 digits into ANY money field (expenses, harvest rate, ushr, theka,
inventory price, party ledger, activity costs) was an **uncaught exception →
app crash**. `Quantity.parse` is safe (`double.tryParse` + NaN/Infinity
rejection). The service itself is out of scope for this audit, so the fix is a
screen-level digit-count guard.

## New shared foundation

**`lib/widgets/field_validators.dart`** (new) — `FieldValidators` with simple-Urdu
messages only:
- `money()` — empty → digit-count guard (>12 digits: 'رقم بہت بڑی ہے — درست رقم درج کریں') → `Money.parse` catching both `MoneyParseException` and `FormatException`.
- `tryMoney()` — non-throwing parse for dialogs without a `Form`; null on ANY bad input incl. overflow.
- `quantity()` / `wholeCount()` / `text()` / `percent()` / `phoneOptional()` — with absurd-value caps (quantity ≤ 1e12 default, text ≤ 200 chars) and digit counting that handles Urdu digits.

**`test/widget/field_validators_test.dart`** (new) — 14 tests, all passing.

## Fixes applied per screen

| Screen | Gap | Fix |
|---|---|---|
| `activity_form_screen.dart` | Hours, water/diesel cost, labor count, labor wage, machinery cost, generic cost, purchase price validators were isEmpty-only — "abc"/"-5" passed field validation | All now use `FieldValidators` (quantity/money/wholeCount) |
| `activity_form_screen.dart` | Labor count embedded raw into details string | `wholeCount` validator (whole number, 1–100000) |
| `activity_form_screen.dart` | 3 save paths caught only `MoneyParseException` | Added `on FormatException` → friendly Urdu SnackBar |
| `activity_form_screen.dart` | Inventory-qty validator had no absurd cap | Added `maxQuantity` cap |
| `theka_form_screen.dart` | Installment-count field: no upper bound — 1000000 installments = UI freeze/memory blowup | Capped at 120 with Urdu message |
| `theka_form_screen.dart` | `Money.parse` in `_generateInstallments`, `_saveForm`, installment `onChanged`, summary builder caught only `MoneyParseException` | Added `FormatException` handling everywhere |
| `theka_form_screen.dart` | Total-amount validator had no overflow guard | `FieldValidators.money` |
| `ushr_screen.dart` | `_parsePaisaOrZero` / `_parsePaisaOrThrow` let `FormatException` escape | Wrapper converts to friendly `MoneyParseException`; `_moneyValidator` and qty validator now use `FieldValidators` |
| `harvest_screen.dart` | 2 qty + 2 money validators lacked overflow/absurd guards; `_parsePaisaOrZero`/`_tryPaisa`/`_parsePaisaOrThrow` leaked `FormatException` (optional expense fields have no validators) | Validators → `FieldValidators`; helpers hardened |
| `theka_details_screen.dart` | Installment-payment validator crashed on 20+ digit input during `validate()` | `on FormatException` → 'رقم بہت بڑی ہے — درست رقم درج کریں'; save hardened |
| `expenses_screen.dart` | Amount validator lacked overflow guard | `FieldValidators.money` |
| `inventory_screen.dart` | 2 price validators lacked overflow guard; qty validators lacked absurd cap; 'صرف نمبر' terse | All → `FieldValidators` |
| `party_detail_screen.dart` | Ledger-entry dialog: `Money.parse` crash on overflow | `FieldValidators.tryMoney` |
| `party_detail_screen.dart` / `parties_screen.dart` | Party name/phone dialogs: no field-level validation (provider-only) | Inline field errors via `StatefulBuilder` + `FieldValidators.text` / `phoneOptional` |
| `batai_detail_screen.dart` | `_save`'s `on Object` catch showed raw `e.toString()` (e.g. "FormatException: …") — technical English to the farmer | `tryMoney` + friendly fallback 'کچھ غلط ہو گیا — دوبارہ کوشش کریں' |
| `batai_screen.dart` | Percentage fields had no screen-level 0–100 range check | Added check: 'حصہ 0 سے 100 تک ہونا چاہیے۔' |
| `my_farms_screen.dart` | Acreage/size accepted absurd values (999999999 acres) | Cap 100000; name fields → `FieldValidators.text` |
| `my_crops_screen.dart` | Variety-name validators isEmpty-only | `FieldValidators.text` (adds 200-char cap) |
| `task_form_screen.dart` | Title validator isEmpty-only | `FieldValidators.text` |

## Checked and left as-is

- **TextInputType:** every numeric field already uses `TextInputType.number` (or `.numberWithOptions(decimal: true)`); phone uses `TextInputType.phone`. No `FilteringTextInputFormatter.digitsOnly` added deliberately — it would block Urdu-digit keyboards.
- **Dropdowns:** all selection from provider lists; no free-text injection.
- **Date/time:** picker-bounded; text date fields fall back to `tryParse(...) ?? now()` — no crash.
- **Message language:** all validation messages found are simple Urdu; no technical English leaks remain (one raw-`toString` path fixed, see batai_detail).
- **Batai percentage sum:** provider enforces sum=100 with Urdu messages — acceptable, left alone.
- **Optional money fields** (harvest expenses, ushr cash-paid): blank → 0 pattern preserved; hardened against overflow.

## Concurrency note

The parallel accounting audit added `isSaving` double-tap guards to 7 of the same
screen files while this audit was in flight. One of its edits briefly left
`expenses_screen.dart` uncompilable; it self-healed before this audit's analyze
run. All validation edits here were verified intact alongside theirs.

## Follow-up fixes (crash-safety + race-condition + UI/nav audits, 2026-10-04)

Applied as part of this pass, per parent task:

**D1 — raw `'…: $e'` technical errors → `showFriendlyError` (13 sites):**
- `theka_form_screen.dart:285` (save catch) → `FailureKind.database`
- `backup_screen.dart` ×8 (:57 database, :94 storage, :112 database, :163 storage, :173 sharing, :192 import, :403/:424 corruptData) — `_showSnack` calls replaced wholesale
- `reports_screen.dart:140` → unknown; `onboarding_screen.dart:65` → unknown
- `settings_screen.dart:226`/:306 → database

**D2 — `reports_screen._saveAndShare`:** had no try/catch (disk-full/share failure = crash). Wrapped → `showFriendlyError(sharing)`.

**D4 — recycle bin:** `listDeleted()` already had try/catch; routed through `showFriendlyError(database)` with empty-list fallback.

**D6 — inventory transaction history `FutureBuilder`:** added `snapshot.hasError` error state (was silently showing empty list on load failure).

**M1 — party delete confirmation:** both party edit dialogs (`parties_screen`, `party_detail_screen`) had single-tap red delete with no confirmation. Now show the standard Urdu confirmation dialog (red 'جی ہاں، حذف کریں' / grey 'منسوخ کریں') before `deleteParty()`, matching other delete flows.

**M2/H1/H2/race-M1 — double-submit guards:** `_isSaving`/`isSaving` guards added to `task_form_screen._saveTask` (button disabled via `onPressed: _isSaving ? null : _saveTask`), `theka_form_screen._saveForm`, and both inventory dialogs (add-stock, adjust-quantity).

**Race M2 — fire-and-forget mutations:** 10 sites now `await` the provider call in try/catch, pop only on success, `showFriendlyError(database)` on failure:
- `my_farms_screen`: addFarm, updateFarm, deleteFarm/deleteField
- `my_crops_screen`: addCropSeason, updateCropSeason
- `tasks_screen`: deleteTask
- `harvest_screen`: recordSale, updateSale
- `ushr_screen`: deleteUshrRecord
- `inventory_screen`: deleteInventoryItem (was popping BEFORE the await)
- Success snackbars in harvest updateSale / ushr delete moved inside the try (no more false "success" when the write throws).

**Cosmetic — settings `_wipeAllData`:** now resets `DemoDataService.activeKey` so the demo banner can't linger over a wiped database.

## Verification

- `flutter analyze` on the full repo: **0 errors, 0 warnings** (only pre-existing infos).
- New `test/widget/field_validators_test.dart`: **14/14 pass**.
- Full `flutter test` suite: **301/301 pass** (run 2026-10-04 ~06:35 PKT).
  - Note: `test/db/*` FFI tests need `libsqlite3.so`; the sandbox only ships `libsqlite3.so.0`. Workaround used: `ln -s /lib/x86_64-linux-gnu/libsqlite3.so.0 /tmp/sqlite_fix/libsqlite3.so` + `LD_LIBRARY_PATH=/tmp/sqlite_fix`. Without it, all db tests fail environmentally (not code-related).
  - One regression caught during this pass: `money_dialogs_test.dart` party-entry test expected the original detailed `MoneyParseException` message — the entry dialog keeps `Money.parse` + `on FormatException` (message preserved), overflow handled separately.
- `dart format --set-exit-if-changed` on touched files: clean (repo language version 3.7).

## Remaining (not validation issues)

- Upper-bound values (12 money digits, 1e12 quantity, 100000 acres, 120 installments) are typo-guards, not business rules — easy to tune.
- `Money.parse`'s raw `FormatException` on overflow still exists in `lib/services/money.dart` (out of scope); every screen entry point now guards before calling it.
