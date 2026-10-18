# Kisan Dost — Calculation Register

**Date:** 2026-10-18 · **App:** v1.0.6+7 · **Method:** static code audit (strand 3) + fix verification (strand 5)
**Status key:** ✅ observed-from-code (pure functions — deterministic) · 🔶 code-traced, needs runtime end-to-end · ⚠️ known gap (owner decision)

Money is **INTEGER paisa** in the DB and all code paths. Rounding happens ONLY at: user money-input parsing (>2 decimals rejected, never rounded), `Money.fromRupees`, quantity×rate products (half away from zero), ushr percentage, weighted-average cost, and the batai remainder rule. All sums are exact.

---

## 1. Expense totals ✅
- **Formula:** `SUM(amount_paisa)` over `expenses WHERE deleted_at IS NULL` (`ExpenseProvider.totalExpensesPaisa`, expense_provider.dart:88).
- **Test:** Rs 5,000.00 + Rs 2,500.50 → 750,050 paisa → "7,500.50 روپے". Exact integer sum.
- Soft-deleted expenses drop out immediately.

## 2. Harvest gross / net (computed, never stored) ✅
- **Formulas** (models.dart:437-443): `grossPaisa = (quantity × ratePerUnitPaisa).round()`; `totalExpensePaisa = transport + labour + harvesting + commission + other`; `netIncomePaisa = gross − totalExpense`.
- **Test:** 40 من @ Rs 3,500/من, expenses Rs 12,000 → gross = 14,000,000 paisa = Rs 140,000; net = Rs 128,000.
- The auto-created sale uses the same `grossPaisa` — harvest rate and sale total cannot disagree (FIX-4 closed the soft-delete back-ref hole: `updateHarvest` repoints to a fresh live expense row).

## 3. Sale totals ✅
- **Formula:** `totalAmountPaisa = (quantity × pricePerUnitPaisa).round()` — always recomputed in `recordSale`/`updateSale`, never accepted from the caller (harvest_provider.dart:500, 571).
- **Test:** 40 من @ Rs 3,500 → Rs 140,000.

## 4. P&L per-crop + overall ✅ (single source: `computeFarmPnl`, pnl_summary.dart — used by the P&L screen AND the PDF report)
- **Overall:** income = Σ live `sales.total_amount_paisa`; expenses = `totalExpensesPaisa`; net = income − expenses.
- **Per crop:** income = Σ sales of the season's harvests (unsold → 0); expenses = (a) activity-linked + (b) direct `expenses.crop_season_id`, **deduped by expense id** (pnl_summary.dart:78-103) + Σ harvest bucket expenses (computed) + Σ `ushrAmountPaisa` (the obligation).
- **My Crops card now agrees** (FIX-3: card uses `computeFarmPnl(...).crops.single`; regression test `my_crops_pnl_consistency_test.dart` asserts netPaisa == 210,000 on a mixed-expense season).
- **Test:** wheat: sale Rs 140,000; harvest expenses 12,000 + activity 8,000 + ushr due 14,000 → crop net Rs 106,000. Overall net = 140,000 − 20,000 = Rs 120,000 (Ushr Expense mirror is Rs 0 until paid).
- ⚠️ **Design caveat (owner decision):** crop-level ushr books the *obligation*, overall books the *paid* mirror (mirror rows carry no `crop_season_id` — verified, so no double-count); they reconcile only when ushr is fully paid. Auto-created 'Pending' sales count as income at rate-entry (accrual semantic — S2).

## 5. Inventory balances ✅
- **Formula:** `inventory.quantity` cached total; every movement writes an append-only `inventory_transactions` row in the same DB transaction. Purchase merges with weighted-average cost `((oldQty×oldCost)+(qty×cost))/newQty` (paisa-rounded). Usage throws `InventoryException` when `qty > stock` — never clamps; atomic `UPDATE … WHERE quantity >= ?`.
- **Test:** buy 10 بوری @ 2,000 → cost 200,000/unit; buy 10 @ 2,200 → cost 210,000/unit, qty 20; use 6 → qty 14 + one −6 ledger row.
- Item with any ledger row cannot be deleted. Activity-restore reads the exact deducted amount from the ledger row (not recomputed).

## 6. Party balances (udhaar) ✅
- **Formula:** signed SUM(`amount_paisa`) GROUP BY party_id (party_provider.dart:127). Signs: udhaar_diya +1, wusooli −1, udhaar_liya −1, adaigi +1 (models/party.dart:76). Positive = party owes me.
- **Test:** udhaar_diya 10,000 → wusooli 4,000 → Rs 6,000 receivable.
- ⚠️ Ledger is a silo: credit sales don't create entries; وصولی/ادائیگی don't touch income/expense (S5 — owner decision).

## 7. Theka installments ✅
- **Formula:** `paid_amount_paisa` accumulates (incremental input); status = paid ≥ amount ? 'Paid' : 'Partially Paid'; linked 'Land Rent' expense = cumulative total; payment > remaining throws Urdu error; zero/negative rejected.
- **Test:** 4 × Rs 30,000. Pay 10,000 → Partially Paid, expense 10,000. Pay 20,000 → Paid, expense **updated to 30,000** (not 20,000). Pay Rs 1 more → throws.

## 8. Batai splits ✅
- **Formula** (models/batai.dart:92): each share truncates (`total × pct ~/ 100`); leftover 0–99 paisa → larger share (owner on tie); `owner + cultivator = total` always (DB CHECK agrees).
- **Tests:** Rs 1,000.00 @ 50/50 → 50,000/50,000. Rs 1,000.01 @ 50/50 → owner 50,001, cultivator 50,000. 100,001 @ 60/40 → owner 60,001, cultivator 40,000.
- ⚠️ Settlement ledger has no P&L integration and no UNIQUE on harvest/sale (S3, D4 — owner decision).

## 9. Ushr (10% / 5% / custom; cash / kind / mixed) ✅ math · ⚠️ policy gaps
- **Formulas:** `ushrAmountPaisa = (marketValuePaisa × percentage / 100.0).round()` (ushr_provider.dart:65); `remainingBalancePaisa = due − cashPaid − (qtyPaid × rate).round()` (models.dart:693, computed); paid mirror = `cashPaid + (qtyPaid × rate).round()`.
- **Test:** Rs 140,000 @ 10% → due Rs 14,000. Pay 5,000 cash + 2 من @ 3,500 → paid 12,000; remaining Rs 2,000; status Pending.
- **FIX-5:** harvest autofill now converts to من via `UnitConverter` (`ushrAutofillMaundsText`); 80 kg → "2", unconvertible units → empty field (never a wrong number).
- ⚠️ Gaps: overpayment accepted (negative remaining — D2); in-kind payment doesn't reduce harvest (S7); due-vs-paid basis split (S8). All need owner policy, not silent changes.

## 10. Money parsing / formatting ✅
- `Money.parse("1,250.50")` → 125,050; `Money.parse("۱۲۵۰")` → 125,000; `Money.parse("1250.555")` → throws (never silently rounds); 13-digit input → Urdu error, not crash. `Money(125050).format()` → "1,250.50 روپے".

## 11. Unit conversions ✅
- 2 من → 80 kg; 2 بوری → 100 kg with `weightPerUnitKg: 50`, throws without it (never assumes 50). من↔ٹن, l↔ml exact; weight↔volume or anything↔piece throws. 'کسٹم' unit unconvertible (D8 — documented).

## Rounding & duplication notes
- Rounding points (only): money input, `Money.fromRupees`, qty×rate, ushr %, weighted-avg cost, batai remainder. All sums exact.
- The dual-link expense path (crop_season_id + auto-activity) is deduped by expense id in `computeFarmPnl`. Ushr mirrors carry no crop link → no per-crop double count. Harvest bucket expenses are computed crop-side, mirrored overall-side — same amounts, one per level.
