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

The owner approved the following defaults. Status: DECIDED, pending
implementation on the `prod-readiness` branch.

| # | Decision | Owner's chosen option |
|---|---|---|
| 1 | Unsold harvest (S2, §6.1) | Track remaining produce separately; do not count it as realized sales income |
| 2 | Batai ↔ P&L (S3, §6.3) | Record the farmer's actual share; prevent duplicate income or expenses |
| 3 | Party ledger (S5, §6.4) | Link ledger entries to the underlying transaction, where applicable |
| 4 | Ushr due vs paid (S8, §6.2) | Show due, paid, and remaining separately |
| 5 | Delete/restore (cross-cutting) | Atomic, reversible changes for linked records; prevent duplicate restoration |
| 6 | Backup encryption | Prefer encrypted backups with a recovery method the farmer can actually use |
| 7 | Lock-screen alarms | Hide sensitive details by default; allow a clear, safe notification |
| 8 | In-app updates | DEFERRED — preserves the offline-first design (no INTERNET permission) |
| 9 | Release scope (1.0.7) | Reliability and verified bug fixes only — no new features |

Remaining minor open items (owner has not decided yet):
- S7 follow-up: should in-kind ushr also shrink the linked auto-sale? (§6.5).
- D4: batai double-settle guard — UNIQUE constraint vs product flow (§6.3).
- S11 follow-up: `payment_status` after `restoreSale` stays `Pending`
  (deleteSale's reset value) because the pre-delete status isn't stored.
  Options: store it, or always restore `Paid`.
