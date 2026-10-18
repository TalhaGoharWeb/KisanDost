# Kisan Dost — Financial Policy (Phase 2–3, §6)

**Date:** 2026-10-18 · **App:** v1.0.6+7 · **Author:** finance/business-logic strand
**Companion docs:** `FUNCTIONAL_AUDIT_2026-10-18.md` (§4–§7), `CALCULATION_REGISTER_2026-10-18.md`

This document records the financial business rules decided in Phase 2–3: for
each of §6.1–§6.7 it states the current behavior, the alternatives
considered, the recommended default, and whether the owner's decision is
needed. Three safe fixes were implemented (D2, S7, S11 — see bottom); every
other product decision is documented here and **not** silently changed.

**Religious/agronomic boundary (hard rule):** ushr rates (10% / 5% /
custom), what ushr applies to, and all religious rules stay **exactly as
implemented**. The in-kind harvest deduction (§6.5) is an *accounting
consistency* rule (grain left the stock → the stock figure drops), not a
religious ruling. Anything uncertain is marked **OWNER DECISION** below —
nothing was invented.

---

## 6.1 Harvest valuation vs realized sales

**Current behavior.**
- Entering a rate on a harvest auto-creates a `sales` row with Pending
  semantics (S2) → P&L counts it as income immediately (accrual basis).
- Two-way sync keeps harvest and sale agreeing: `updateSale` recomputes the
  harvest's rate; `recordSale` sets the harvest rate/buyer/status; the sale
  total is always recomputed as quantity × price, never trusted from input.
- `deleteSale` soft-deletes the sale and zeroes the harvest's
  `rate_per_unit_paisa`/`buyer_name`/`payment_status` so the sale can be
  re-recorded. `restoreSale` (fixed S11, 2026-10-18) restores the harvest's
  rate and buyer from the sale row's own pre-delete values; if the harvest
  was re-sold meanwhile, the live sale's values win and are never clobbered.

**Alternatives considered.**
- (a) Cash basis: income only when the farmer explicitly records receipt.
- (b) Keep accrual, but label the auto-created sale as an estimate.
- (c) Dual figures: expected (rate-based) vs realized (recorded sales).

**Recommended default:** keep the accrual behavior (it matches how farmers
think — "my crop is worth X"), but make the Pending/expected nature of the
auto-created sale visible in the UI rather than silent.

**OWNER DECISION — S2:** whether unsold harvests should book income at all.
Code deliberately unchanged pending the decision.

## 6.2 Ushr payment integrity

**Current behavior (after the D2 fix, 2026-10-18).**
- The provider validates `totalPaid ≤ ushrAmount` on **both** add and edit
  (`UshrProvider.validatePaymentWithinDue`, pure/static, unit-tested).
  Overpayment throws a Urdu error naming both amounts; negative payments are
  rejected too. The dialog shows the message and stays open — the entry is
  never lost.
- `totalPaid = cashPaid + (qtyPaid × rate).round()`; status becomes `Paid`
  exactly when the remaining reaches zero. The remaining can no longer go
  negative, so accidental double-payment is impossible.
- The `Ushr Expense` mirror always carries the cumulative paid amount;
  editing the payment to zero soft-deletes the mirror (restorable).

**Alternatives considered.**
- (a) Allow overpayment as advance credit toward next season's ushr.
- (b) Per-payment ledger rows instead of cumulative `cashPaid`/`qtyPaid`
  fields (better history, needs a migration).

**Recommended default:** block overpayment (implemented). Per-payment rows
are a future enhancement, not a silent change.

**OWNER DECISION:** none required for D2. **S8 stays open:** per-crop P&L
books the ushr *obligation*, overall P&L books the *paid* mirror; they
reconcile only when ushr is fully paid. Cash-vs-accrual for ushr is the
owner's call.

## 6.3 Batai settlement integration

**Current behavior.** `settleAgreement` writes only `batai_settlements`;
the farmer's share never reaches P&L (S3). No double-count risk today, but
the proceeds are invisible in profit figures.

**Alternatives considered.**
- (a) Auto-create sale/expense rows on settlement.
- (b) Make P&L read `batai_settlements` directly.
- (c) Manual farmer action: "record as income/expense" per settlement.

**Recommended default:** (c) — an explicit farmer action. Auto-creation (a)
risks double-counting when the harvest sale is also recorded; (b) bakes a
product decision into the totals silently.

**OWNER DECISION — required** (S3). Related: D4 — no UNIQUE on
(harvest/sale) in settlements, so a double-settle is possible; needs the
owner's product call (constraint vs flow).

## 6.4 Party ledger integration

**Current behavior.** The ledger is a silo (S5): credit sales don't create
entries, وصولی/ادائیگی don't touch income/expense. Internally consistent —
exact paisa sums, uniform signs (positive = party owes me).

**Alternatives considered.**
- (a) Auto-link: credit sale → `udhaar_diya` entry; وصولی → income entry.
- (b) Keep the silo; farmer enters ledger rows manually.

**Recommended default:** (b) for now. Auto-linking without an idempotency
marker double-counts (the sale is already in income). If the owner wants (a)
later, it needs link markers and a "linked, don't double-book" rule.

**OWNER DECISION — required** (S5).

## 6.5 In-kind ushr

**Current behavior (after the S7 fix, 2026-10-18).**
- An in-kind payment reduces the **linked harvest's** quantity, exactly once
  per payment lifecycle: add deducts; edit undoes the old share then deducts
  the new one (a no-op edit nets to zero — never double-reduces, never
  drifts); delete restores; moving/unlinking the harvest restores the old
  harvest and deducts from the new one.
- The deduction is **proportional**: `harvest.quantity × (qtyPaid /
  harvestQty)`. The ushr record is self-consistent (market value =
  harvestQty × rate), so the ratio is unit-agnostic: it equals a من→unit
  conversion for screen entries and stays correct for harvest units a
  converter cannot bridge (بوری، کسٹم، …) — no guessing, no throws on
  legitimate units.
- **Legacy records** (created before the deduction existed) are detected via
  an audit-log marker: deletes restore nothing for them (restoring would
  invent grain); their first managed edit deducts the full new share.
- Unlinked in-kind payments don't touch any harvest. A deduction that would
  drive the harvest negative throws a Urdu error; the whole save rolls back
  atomically. Every adjustment is audit-logged.
- Known approximation (documented, not silent): if the farmer hand-edits
  the harvest quantity *between* ushr operations, the undo is best-effort.

**Alternatives considered.**
- (a) Reduce an inventory item instead of the harvest row.
- (b) No reduction (old behavior — stock stays overstated).

**Recommended default:** implemented behavior (b is a data-integrity bug;
a needs an inventory↔harvest identity that doesn't exist).

**OWNER DECISION:** should the auto-created *sale* also shrink when in-kind
ushr is paid? (Tied to the S2 accrual question in §6.1 — deliberately not
changed.)

## 6.6 Theka installments

**Current behavior.** Incremental accumulation (`paid_amount_paisa` grows);
overpayment throws at provider and dialog level with the remaining shown;
the linked `Land Rent` expense always equals the cumulative total; cancel
deletes it. `deleteTheka` hard-deletes installments + linked expenses —
**deliberate, audit-logged, NOT changed** (accepted in the October audit).

**Alternatives considered.** Per-installment expense rows (more history,
more clutter).

**Recommended default:** keep as is. No change needed or made.

**OWNER DECISION:** none (existing accepted behavior).

## 6.7 Calculation standard (ratified)

- **Money is integer paisa end-to-end** (`Money` value object; INTEGER
  columns since the v12 REAL→INTEGER rebuild). No `double` money anywhere.
- Rounding happens **only** at: money-input parsing (>2 decimals rejected,
  never rounded), quantity×rate products (`.round()`, half away from zero),
  ushr percentage, weighted-average inventory cost, and the batai remainder
  rule (0–99 paisa → larger share, owner on tie; DB CHECK enforces
  owner + cultivator = total). All sums are exact.
- Quantities are REAL doubles (they are not money); proportional deductions
  use 1e-9 epsilon guards, never exact `==` on computed doubles.
- Full hand-computed register: `CALCULATION_REGISTER_2026-10-18.md`.

**OWNER DECISION:** none — standard ratified as implemented.

---

## Deliberately unchanged (owner decisions, not code defects)

| ID | Item | Policy section |
|---|---|---|
| S2 | Phantom income from auto-created Pending sales | §6.1 |
| S3 | Batai ↔ P&L integration | §6.3 |
| S5 | Party-ledger ↔ P&L linkage | §6.4 |
| S8 | Ushr due-vs-paid basis split (per-crop vs overall) | §6.2 |
| — | `deleteTheka` destroying linked expenses (audit-logged by design) | §6.6 |
| — | `restoreHarvest` mirror behavior (sales/expense restored individually) | — |

## Implemented 2026-10-18 (this phase)

- **D2** — `UshrProvider.validatePaymentWithinDue` (static, pure) wired into
  `addUshrRecord`/`updateUshrRecord` before any DB write; `ushr_screen`
  catches the Urdu error and keeps the dialog open.
- **S7** — `_adjustHarvestInKind` + audit-log marker (`_inKindMarker`,
  `_hasInKindMarker`); full lifecycle add/edit/delete/link-change with
  undo-then-redo semantics; legacy-record safety.
- **S11** — `restoreSale` restores the harvest's `rate_per_unit_paisa` and
  `buyer_name` from the sale row; re-sale guard keeps a newer live sale's
  values. (Note: `payment_status` is intentionally left as deleteSale left
  it — the pre-delete status isn't stored anywhere; see open question 7.)
- **Tests** — `test/unit/ushr_payment_guard_test.dart` (7 tests),
  `test/db/ushr_in_kind_harvest_test.dart` (9 tests),
  `test/db/harvest_restore_sale_test.dart` (3 tests). All values
  hand-computed; no assertions weakened.

## Owner decisions — DECIDED 2026-10-18 (owner's words, recorded verbatim)

The owner approved the following defaults. Status: **IMPLEMENTED**
on the `prod-readiness` branch 2026-10-18 (commits below; nothing pushed).
Decision 8 is deferred by design; decision 9 is scope guidance, not code.

| # | Decision | Owner's chosen option |
|---|---|---|
| 1 | Unsold harvest (S2, §6.1) | Track remaining produce separately; do not count it as realized sales income | `f5686cb` ✅ |
| 2 | Batai ↔ P&L (S3, §6.3) | Record the farmer's actual share; prevent duplicate income or expenses | `f5686cb` ✅ |
| 3 | Party ledger (S5, §6.4) | Link ledger entries to the underlying transaction, where applicable | `cdb7749` ✅ |
| 4 | Ushr due vs paid (S8, §6.2) | Show due, paid, and remaining separately | `38568c0` ✅ |
| 5 | Delete/restore (cross-cutting) | Atomic, reversible changes for linked records; prevent duplicate restoration | `025eca6` ✅ |
| 6 | Backup encryption | Prefer encrypted backups with a recovery method the farmer can actually use | `21c0658` ✅ |
| 7 | Lock-screen alarms | Hide sensitive details by default; allow a clear, safe notification | `1520b32`+`3fd9ea7` ✅ |
| 8 | In-app updates | DEFERRED — preserves the offline-first design (no INTERNET permission) |
| 9 | Release scope (1.0.7) | Reliability and verified bug fixes only — no new features |

Remaining minor open items (owner has not decided yet):
- S7 follow-up: should in-kind ushr also shrink the linked auto-sale? (§6.5).
- D4: batai double-settle guard — UNIQUE constraint vs product flow (§6.3).

## Implementation notes — owner decisions implemented 2026-10-18

All work on the `prod-readiness` branch. Nothing pushed. No version bump.
App remains purely Urdu; no INTERNET permission added. Full suite green
(see verification line per decision).

### #1 Unsold harvest excluded from realized income (`f5686cb`)
- **Rule** (documented in code at `computeFarmPnl`): a harvest's linked sale
  counts as income only when `harvest.payment_status` is `'Paid'` or
  `'Partial'`. `'Pending'` sales are rate-only estimates (auto-created by
  `addHarvest`/`updateHarvest`; only `recordSale` flips status to `'Paid'`)
  and are excluded from income, summed instead into the new visible
  `unsoldProducePaisa` figure («غیر فروخت شدہ پیداوار»).
- `FarmPnl`/`CropPnlResult` gained `salesIncomePaisa`, `bataiIncomePaisa`,
  `unsoldProducePaisa` (optional params — `reports_screen.dart` untouched,
  gets the corrected rule automatically). P&L header relabeled
  «کل فروخت (آمدنی)» → «کل آمدنی (وصول شدہ)» with a 3-row breakdown;
  per-harvest cards label Pending sales «تخمینہ:» (orange), not «آمدنی:».
- **Tests**: `test/db/pnl_realized_income_test.dart` (8: sold / unsold-estimate /
  Partial / credit / canceled / restored / no-sale / mixed), hand-computed.

### #2 Batai actual-share in P&L (`f5686cb`)
- New `bataiFarmerSharePaisa()`: role-aware share math from the stored split
  (terms lock on first settlement). A harvest with ≥1 settlement (linked by
  `harvest_id` or `sale_id`) has its full sale total EXCLUDED and only the
  farmer's share of each settlement added — sale + distribution can never
  double-count. Fractional-paisa remainder → larger share (existing rule).
- `batai_provider.dart` gained an `allSettlements` cache + `getAllSettlements()`;
  `my_crops_screen.dart` passes batai data into `computeFarmPnl` (single
  source of truth holds; card matches P&L screen).
- **Tests**: `test/db/pnl_batai_integration_test.dart` (11: 50/50, 60/40,
  saleId-only linking, fractional paisa incl. tie→owner, multiple settlements,
  idempotent retry, unlinked settlements, determinism), hand-computed.

### #3 Party ledger linked to transactions (`cdb7749`)
- **Schema v15→v16** (idempotent): nullable `source_type TEXT` /
  `source_id INTEGER` on `party_ledger_entries` + index
  `idx_party_ledger_entries_source`. No FK — the link is a trace marker that
  survives source deletion (mirrors the audit-log pattern); the provider
  verifies the source row exists at write time. Legacy rows read as unlinked.
- `PartyEntrySourceType {sale, expense, payment, collection}` with Urdu labels;
  `addLinkedEntry` validates amount/date, rejects dangling links (Urdu
  `PartyException`, nothing written), audit-logs the link. Documented sign
  convention: a collection on a recognized sale only shrinks the receivable,
  never books income.
- Party detail screen: tappable «منسلک: فروخت #N» chip → trace dialog (source
  facts, linked count, live balance); entry dialog has an optional source-link
  section.
- **Tests**: `test/db/party_ledger_source_link_test.dart` (9: migration
  idempotency, full credit-sale lifecycle 60,000→25,000→reversal→settlement with
  income provably unchanged, payable side, deleted-source survival,
  dangling-link rejection, legacy rows), hand-computed.

### #4 Ushr due/paid/remaining shown separately (`38568c0`)
- Additive only — D2 overpayment guard and S7 in-kind logic untouched.
- New `UshrTotals` / `UshrSeasonTotals` / `UshrCropTotals` (integer paisa) +
  `paidValuePaisaOf` (cash + qtyPaid×rate, same rounding as the guard).
  Getters `totalsOverall`, `totalsBySeason`, `totalsByCrop`. No religious-rule
  changes.
- Ushr screen: overall summary cards + new per-crop section «فصل کے حساب سے
  عشر کا خلاصہ», each showing واجب الادا / ادا شدہ / باقی distinctly; the باقی
  row is always shown (0 in green when fully paid).
- **Tests**: `test/unit/ushr_totals_test.dart` (14: cash-only, in-kind, mixed,
  partial, fully-paid, rounding 1.333×33,333=44,433, roll-ups, reconciliation),
  hand-computed. All 37 ushr tests pass unchanged.

### #5 Atomic, reversible delete/restore (`025eca6`)
- **S11 resolved**: new nullable `sales.harvest_payment_status_at_delete TEXT`
  (DB v16→v17, idempotent). `deleteSale` stashes the pre-delete status;
  `restoreSale` writes rate + buyer + stashed status back. Pre-v17 schemas
  degrade gracefully (falls back to `'Pending'`, never crashes).
- Row-state idempotency on `_softDeleteRow`/`_restoreRow` (skip on state, no
  duplicate audits); delete/restore/permanent-delete are safe no-ops on
  wrong-state rows. Previously non-transactional paths fixed: task provider
  gained `_txn`; inventory delete+audit wrapped in one transaction; farm
  provider gained `_txn`; activity deletion now writes its missing audit row.
- **D1 follow-up**: `permanentDeleteHarvest` destroys the expense mirror only
  while still soft-deleted — a farmer-restored live expense survives.
- SEC1 contract tested: delete/restore never move stock. Ushr has no restore
  path by design (no `deleted_at`) — noted, not added.
- **Tests**: `test/db/delete_restore_idempotency_test.dart` (10),
  `test/db/hard_delete_paths_test.dart` (8), 1 v17 migration test;
  delete→restore→delete-again→restore-again per path, hand-computed.

### #6 Backup encryption (`21c0658`)
- Design: `docs/audit/BACKUP_ENCRYPTION_DESIGN.md`. AES-256-GCM via
  `package:encrypt` (vetted PointyCastle); PBKDF2-HMAC-SHA256 ×210k KDF via
  pointycastle (`package:crypto` has no KDF; nothing hand-rolled).
- Per-backup random salt+nonce in the `.db.enc` header; sidecar carries only
  non-secret metadata (`encrypted:true`, plaintext hint, KDF params). No
  escrow; passphrase never stored. Loud Urdu warning: forgotten passphrase =
  unrecoverable. Plaintext verifier distinguishes wrong-passphrase from
  tampered-file. Interrupted export leaves no partial file (temp + atomic
  rename). Safety backups inherit the passphrase. Unencrypted backup remains
  an explicit choice.
- UI: encrypted/unencrypted choice, passphrase + confirm + hint fields, lock
  badge + hint on cards, passphrase prompt on restore/import.
- **Tests**: `test/db/backup_encryption_test.dart` (18: round-trip,
  wrong password, tampered file, interrupted write, unencrypted path).

### #7 Lock-screen notification redaction (`1520b32` + `3fd9ea7`)
- Evidence: task titles are free text (e.g. «احمد کو 5000 روپے دینے ہیں») and
  were shown verbatim on the lock screen — redaction covers content, not just
  the visibility flag.
- New pure `AlarmNotificationContent.build(taskTitle:, reminderSuffix:,
  showDetails:)`; all 3 FLN paths + native `AlarmService` (early + full
  notifications) read pref `lockscreen_show_details` (default `false`).
  Default text: «کسان دوست — یاد دہانی» / «کام کا وقت ہو گیا — کھولنے کے
  لیے تھپتھپائیں». Visibility stays `public`: `secret` would hide the reminder
  entirely, `private` shows only the app name — with redacted text there is
  nothing sensitive left, so `public` is exactly "clear and actionable".
- Settings toggle «لاک اسکرین پر تفصیل» (default OFF), disabled when reminders
  are off.
- **Tests**: `test/unit/notification_content_test.dart` (5).
- Recovery note: the implementation files were stranded in the git index by a
  parallel worker's accidental `git stash`; verified coherent with the tests
  and committed as `3fd9ea7` (see `~/AGENTS.md` "NEVER git stash" lesson).
- **Needs a real device**: actual lock-screen rendering (FLN + native);
  native Kotlin change needs a Gradle compile. `AlarmActivity` (full-screen
  alarm UI) still shows the task title by design — owner may want a separate
  decision on it.
