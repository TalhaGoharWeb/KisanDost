# Kisan Dost — Screen-by-Screen Audit Report

**Date:** 2026-10-01 · **Repo:** `~/workspace/kisan-dost` · **Scope:** all 19 screens in `lib/screens/`, `lib/theme/app_theme.dart`, `lib/widgets/empty_state_widget.dart` (+ providers/services read where needed to verify behavior).

**Method:** Audit only — no source files were modified. All line numbers verified against on-disk files via grep. Cross-screen questions (profit-loss attribution, sale-update recompute, `payInstallment` semantics, inventory stock validation, dashboard query patterns, alarm native registration, backup/restore) were traced end-to-end through screens → providers → `db_helper.dart` → Android native code.

**Glossary of completeness criteria used per screen:** UI exists · navigation works · data model exists · create/read/update/delete work · validation works · calculations correct · persistence works · errors handled · empty states exist · loading states exist · permissions correct · survives restart.

**One environmental note:** during the audit a commit (`9b5f7f0` "fix: enable SQLite foreign key enforcement") added `PRAGMA foreign_keys = ON` in `db_helper.dart:27-28` (`onConfigure`). All cascade-related findings below reflect the **current** on-disk state: `ON DELETE CASCADE` / `SET NULL` declarations are now real.

---

## 1. `lib/screens/splash_screen.dart`

**Purpose / reach:** Branded launch screen (logo, app title, tagline, developer credit, spinner). It is `home:` in `main.dart`; after a fixed 3-second `Future.delayed` it `pushReplacement`s → `DashboardScreen` (lines 15–21).

**Checklist:** UI exists ✓ · navigation works ✓ · no data layer (n/a) · decorative loading spinner only · no permissions · survives restart trivially.

**Concrete bugs:**
- Fixed 3 s delay regardless of real initialization progress (line 15: `Future.delayed(const Duration(seconds: 3), ...)`). Providers load in parallel from `main.dart`, so this is a branding pause in practice — but if any provider fetch ever took >3 s, the dashboard would render with partial data. Design smell, not a crash.

**Hardcoded English shown to user:**
- `'Developed by:'` (above the developer's Urdu name, ~line 117).

**UX (low-literacy farmer):** Fine — no interaction required, big Urdu text, spinner communicates waiting.

**Empty/loading/error states:** Decorative spinner only; nothing can go wrong.

---

## 2. `lib/screens/activity_form_screen.dart`

**Purpose / reach:** The diary entry form — records one "کام" (activity) against an active crop season: پانی لگایا (irrigation), کھاد ڈالی / سپرے کیا / دوائی ڈالی / ڈیزل استعمال (inventory-linked), مزدور لگائے (labor), مشینری کا استعمال (machinery), or generic. Supports create, edit (`existingActivity`), and duplicate (`duplicateMode`). Reached from **Today's Work screen**: the activity-type grid (`todays_work_screen.dart:68`) and the activity list's edit/duplicate popup menu (`todays_work_screen.dart:168, 178`).

**Checklist:** UI exists ✓ · navigation works ✓ (3 entry points) · data model exists ✓ · create/update via `ActivityProvider` ✓ · delete lives on the list screen · validation ⚠️ partial · calculations ⚠️ (unit conversion has holes) · persistence ✓ (SQLite) · errors handled ❌ (whole save block unguarded) · empty state ✓ ("کوئی فعال فصل موجود نہیں ہے!" guidance) · loading state ❌ · survives restart ✓.

**Concrete bugs:**
- **B1 — Null-check crash on non-numeric direct-purchase price.** Save block, line 550: `costPerUnit: finalExpenseAmount! / inventoryQty`. The price field's validator (~line 348) only checks non-empty — entering "abc" passes validation, `double.tryParse` returns null, `!` throws → **crash**. Entering qty `"0"` passes → division by zero → `costPerUnit = Infinity` written toward SQLite.
- **B2 — Negative quantities accepted.** Qty validator (lines 391–399) rejects empty/non-numeric but not negatives. `-5` is stored in the activity row; `addActivity`'s `inventoryQuantity > 0` guard then silently skips deduction while the record claims −5 used.
- **B3 — Non-numeric junk accepted in water/labor/machinery fields.** `_hoursController` validator: `value!.isEmpty ? 'براہ کرم گھنٹے درج کریں' : null` (line 229) — "abc" passes and is baked into the details string. Same for labor count (~line 415) and machinery/labor cost fields (only `tryParse`, null → silently no expense).
- **B4 — Edit-mode false rejection.** `_loadExistingValues` never restores `_selectedInventoryItem`, and the stock validator (lines 394–398) checks the *new* qty against *current* stock — but `updateActivity` (`activity_provider.dart:230-260`) restores the old qty to stock *before* deducting the new one. Scenario: stock 0 because the old activity used 5; editing 5→3 is wrongly rejected with 'گودام میں اتنی مقدار دستیاب نہیں ہے!' even though the restore would free 5 first.
- **B5 — Unit-conversion holes (silent mis-deduction).** `convertUnit` is **duplicated** in `activity_form_screen.dart` (~line 630+) and `activity_provider.dart` `_convertUnit` (~line 370+). The dropdown `_units` includes 'بوتل' (bottle) and 'پیکٹ' (packet), but neither appears in the conversion maps → `convertUnit` returns the quantity **unchanged** → "5 بوتل" against a "لیٹر" stock deducts **5 لیٹر** silently. Also assumes 1 بوری = 50 kg with no UI note (wrong for seed/spray bags) — undocumented assumption baked into both copies.
- **B6 — Inventory matching ignores unit; wrong-row deduction possible.** `_applyInventoryDelta` (`activity_provider.dart:112-120`) matches by `category + name` only, while `addInventoryItem` upserts by `category + name + unit` (`inventory_provider.dart:27-32`). Two rows "DAP"/بوری and "DAP"/کلوگرام → the delta hits the first in-memory match (id DESC), possibly deducting/converting against the wrong unit row.
- **B7 — Missing inventory item on deduct: silently skipped.** `_applyInventoryDelta` (`activity_provider.dart:121-123`): `if (target == null) { if (deduct) { return; } … }` — the activity is still saved with `inventoryName`/`inventoryQuantity` and the expense is still recorded, but **no stock moves**. Silent book inconsistency (reachable e.g. when the item was deleted from inventory after the form loaded its list, or via provider-level callers).
- **B8 — Missing item on restore: phantom zero-cost stock.** Same function (`activity_provider.dart:124-131`): on the restore path (activity edit/delete) with no matching item, it **auto-creates** the item with `costPerUnit: 0`. Deleting an inventory item and then deleting the activity that consumed it resurrects a zero-cost stock row.
- **B9 — Edit accumulates details prefixes.** Save block (line 565): `_detailsController.text = 'استعمال: $inventoryName | … . ${_detailsController.text}'` mutates the controller; on *edit*, `_loadExistingValues` loads the already-prefixed text, and saving prefixes it again → "استعمال: … . استعمال: … . …" grows with every edit. Same for the water branch (~line 524).
- **B10 — Direct purchase leaves zero-qty clutter.** Direct-purchase path (lines 544–552) inserts the full qty then `addActivity` deducts it all → net zero, but the zero-quantity row stays in inventory forever.
- **B11 — No try/catch around save.** The entire `onPressed` (lines 487–590) — five sequential provider fetches after the write — is unguarded; any DB error leaves the user on the form with no feedback.
- **B12 — Future dates allowed.** Date picker allows up to 2030 with no "not in future" check — a mis-tap logs next year's activity into this season's costs.

**Hardcoded English shown to user:**
- `'نہر (Canal)'`, `'ٹیوب ویل (Tube Well)'`, `'بور کا پانی (Bore)'` (lines 210–212)
- `labelText: 'شروع کے یونٹ (Start Unit)'` (line 251); `'آخری یونٹ (End Unit)'` (line 271)

**UX (low-literacy farmer):** The dynamic per-type form is genuinely good UX. Problems: the "نیا خرید کر ڈائریکٹ ڈالیں؟" checkbox is cryptic for low-literacy users; the unit dropdown mixes weight/volume/count units with no compatibility guard; the screen is very long (scroll) with no section headers beyond the activity title.

**Empty/loading/error states:** No-active-season warning is excellent (icon + explanation + back button). No loading state (cold-start flash of that same warning). No error state on save failure.

---

## 3. `lib/screens/alarm_screen.dart`

**Purpose / reach:** Full-screen "alarm is ringing" UI: pulsating bell, task card, Complete / Dismiss / Snooze (5/10/15) buttons. **On Android it is effectively unreachable dead code.** The only Dart call sites are `dashboard_screen.dart:40-48` (via `NotificationService.launchPayload`) and `notification_service.dart:165` (FLN tap handler) — both only fire for `flutter_local_notifications` notifications, which are **never scheduled on Android** (`notification_service.dart:207-219` early-returns to the native channel). The real ringing UI on Android is the native `AlarmActivity` (Kotlin + `activity_alarm.xml`).

**Checklist:** UI exists (as if reachable) ⚠️ · operates on the wrong alarm subsystem on Android ❌ · persistence ✓ (writes DB directly) · loading state ✓ ('لوڈ ہو رہا ہے...' → 'نامعلوم سرگرمی' fallback).

**Concrete bugs:**
- **B1 — Cancels/schedules the wrong alarms on Android.** `_completeTask` (line 78), `_dismissAlarm` (line 104), `_snoozeTask` (line 122) each construct a **fresh, uninitialized** `FlutterLocalNotificationsPlugin()` and cancel IDs `taskId*10+i`. On Android the actual alarms are native `AlarmManager` PendingIntents (scheduled by `AlarmScheduler.kt`) — the FLN cancel is a silent no-op. If this screen ever displayed on Android: tapping "الارم بند کریں" would update the DB but **the native `AlarmService` would keep ringing**; snooze would schedule a stray FLN notification the native rescheduler knows nothing about. The correct path is `NotificationService().cancelTaskNotifications` / the native channel — not used here.
- **B2 — Dead-code divergence hazard.** The entire FLN alarm pipeline on Android — `alarm_screen.dart`, `notificationTapBackground` (`notification_service.dart`), the `action_complete`/`action_snooze` FLN handlers — never executes, because `scheduleTaskNotifications` returns early on Android. Any future fix applied to only one path silently diverges.
- **B3 — Snooze bypasses `NotificationService`.** Snooze writes `snoozed_until` then schedules FLN directly — inconsistent with the cancel-all-then-schedule discipline used elsewhere.

**Hardcoded English / wrong Urdu:**
- `'الارم بند کریں (ڈسمس)'` — "(ڈسمس)" transliteration.
- **"سوز" is the wrong word**: notification titles `'کسان دوست - یاد دہانی (سوز)'`, native `"سوز کریں: ${task.title}"` (`AlarmService.kt`) — سوز means "burn"; snooze is سنوز. User-visible on every alarm.

**UX:** If it were live: big buttons, good. The three snooze options (۵/۱۰/۱۵ منٹ) use Urdu-Indic digits — nice — but inconsistent with Latin digits everywhere else.

**Empty/loading/error states:** Loading ✓, unknown-task fallback ✓.

---

## 4. `lib/screens/dashboard_screen.dart`

**Purpose / reach:** Home screen. Reached once from splash via `pushReplacement`. Contains: a task-summary card (`_buildTaskSummaryCard`, `Consumer` of `TaskProvider`) + a 2-column grid of 10 module buttons (زمینیں، فصلیں، آج کا کام، خرچے، پیداوار، گودام، منافع و نقصان، کام کی منصوبہ بندی، ٹھیکہ، عشر) + an AppBar popup menu (ایپ کے بارے میں، ترتیبات، Share APK).

**Checklist:** UI exists ✓ · all 10 buttons navigate to existing screens (verified all target files exist) ✓ · popup menu items all wired ✓ · no dead buttons ✓ · persistence n/a.

**Concrete bugs:**
- **B1 — Uncaught exception on share.** `_shareApk()` (lines 59–76) catches only `on PlatformException`. On any platform where the native method is missing (desktop/web/iOS), `invokeMethod('shareApk')` throws `MissingPluginException`, which is **not** a `PlatformException` → uncaught → crash. All native methods exist in `MainActivity.kt`, so Android is safe; still a latent crash path.
- **B2 — Inconsistent snooze handling in badges** (~lines 252–258): the "تاخیر" (overdue) count excludes snoozed tasks (`t.snoozedUntil == null || ...isBefore(now)`), but the "آج" and "آنے والے" counts do NOT exclude snoozed tasks — a snoozed-due-today task appears in the "آج" badge while being deliberately hidden from overdue.
- **B3 — Transient wrong message on first load:** the `Consumer` ignores `TaskProvider.isLoading` (~line 247) and builds the summary from the empty list, showing 'آج کوئی کام باقی نہیں ہے۔ آپ کی فارمنگ ڈائری اپ ٹو ڈیٹ ہے!' ("no work left, diary up to date") before the DB query completes — a first-launch flash of a false all-clear.
- **B4 — Duplicate startup fetch.** `initState` calls `fetchTasks()` once (line 35), but `main.dart` already cascade-fetches every provider at creation — redundant duplicate query (harmless).

**Dashboard query patterns (verified):**
- **What it displays:** Not farm finances — a *task reminder summary* (counts: آج / آنے والے / تاخیر / مکمل) over ALL tasks plus the navigation grid. No farm-expense/profit aggregates here.
- **DB indexes:** **NONE** — `grep -n "CREATE INDEX"` over `db_helper.dart` returns nothing. `TaskProvider.fetchTasks()` (`task_provider.dart:63`) runs `db.query('tasks', orderBy: 'date_time ASC')` — a full-table scan loading **all tasks into memory**, then counts via in-memory `.where()` filters (dashboard ~lines 252–258). Fine at this scale, no indexes anywhere.
- **N+1:** No — it's a single query, not a loop of queries.
- **Refresh on return:** Partially yes. The summary card is a `Consumer<TaskProvider>` and every task mutation refetches + `notifyListeners()`, so it refreshes when tasks change through the provider. Caveat: changes made through any path bypassing `TaskProvider` would leave stale counts until restart.

**Hardcoded English shown to user:** None visible — labels are fully Urdu.

**UX:** Good for the audience — 10 large tappable cards with icons + Urdu labels. The Share-APK entry is buried in a tiny ⋮ popup menu (low discoverability, low importance). Badges use small 12–13 px text — borderline but secondary info.

**Empty/loading/error states:** Summary built from an initially-empty list (B3) — effectively a false "all clear" flash; no spinner.

---

## 5. `lib/screens/expenses_screen.dart`

**Purpose / reach:** Flat expense ledger with a running-total header. Reached via Dashboard → 'خرچے' (`dashboard_screen.dart:183`).

**Checklist:** UI ✓ · navigation ✓ · model ✓ (`expenses` table: `id, category, amount, date, description` — **no `crop_id`/`farm_id`/`season_id`, confirmed in `db_helper.dart`**) · Create ✓ · Read ✓ · **Update ❌ — no edit path at all** · Delete ✓ · validation ⚠️ · persistence ✓ · errors ❌ · empty state ✓ · loading state ❌.

**Concrete bugs:**
- **B1 — No UPDATE.** `ExpenseProvider` exposes only `fetchExpenses`, `addExpense`, `deleteExpense` — no `updateExpense`, and the list rows show only a delete icon. A typo'd amount forces delete + re-add. Worse: if the expense is linked to an activity, deleting it nulls `activities.expense_id` (FK `ON DELETE SET NULL`) and the activity's joined `expenseAmount` (`activity_provider.dart:96`) becomes null — the amount silently vanishes from per-crop P&L.
- **B2 — Negative amounts accepted; null-unsafe validator.** `validator: (value) { if (value!.isEmpty) return 'رقم درج کریں'; if (double.tryParse(value) == null) return 'صرف نمبر درج کریں'; return null; }` (lines 235–236). `value!` force-unwraps a nullable; `-5000` passes validation, *reducing* `totalExpenses` and inflating profit. No zero check either.
- **B3 — Crop link limited to ACTIVE seasons only.** `final activeSeasons = cropProvider.activeCropSeasons;` (line 166) feeds the "فصل منتخب کریں (آپشنل)" dropdown (lines 174–196). Expenses for already-harvested crops can't be linked → they land in "Indirect", skewing that crop's P&L.
- **B4 — System rows deletable, causing orphans.** The list shows *all* expenses including auto-created `'Harvest Expenses'` and `'Ushr Expense'` rows (written by `harvest_provider.dart:123-130` / `ushr_provider.dart:88-95` and referenced back via `harvests.expense_id` / `ushr_records.expense_id`). Deleting one here orphans that back-reference: the harvest card still shows its `totalExpense`, but the ledger total drops — the Expenses total and harvest card now disagree, and a later `updateHarvest` runs `txn.update('expenses', ... where id = expenseId)` matching 0 rows, silently.
- **B5 — Money as `double` (float).** `expenses.amount REAL`, `Expense.amount` double (`models.dart`). `toStringAsFixed(0)` masks it, but repeated sums (e.g. `totalExpenses` fold) can drift by fractions of a rupee. Should be integer paisa.

**How expense→crop linkage works:** When a crop is picked, the dialog inserts the expense, then `activityProvider.addActivity(cropSeasonId:..., activityType: 'دیگر سرگرمی / خرچہ', expenseId: expenseId)` (lines 293–300). That activity row is what the P&L screen joins on. Flat list otherwise — no farm/field/crop columns on `expenses` itself.

**Hardcoded English shown to user:**
- `'خرچے کا زمرہ (Category)'` (line 182); `'فصل منتخب کریں (آپشنل)'` (line 178). Category values like `'کھاد (Fertilizer)'` are intentional bilingual labels from `expenseCategories`.

**UX:** Clear red-gradient total card; rows show Urdu category + amount + date. Missing edit affordance is the big gap vs. other screens (which have ترمیم buttons). Good empty state.

**Empty/loading/error states:** `EmptyStateWidget` ✓, `RefreshIndicator` ✓, no loading spinner, no error state.

---

## 6. `lib/screens/harvest_screen.dart`

**Purpose / reach:** Two-tab screen (پیداوار کا ریکارڈ / فروخت کا ریکارڈ) for recording harvests and their sales. Reached via Dashboard → 'پیداوار' (`dashboard_screen.dart:192`).

**Checklist:** UI ✓ (tabs, summary cards, harvest cards, sale cards, FAB) · navigation ✓ · model ✓ (`harvests` + `sales` tables, `Harvest`/`Sale` models) · Create ✓ (add-harvest dialog; auto-creates linked `sales` row + `expenses` row) · Read ✓ (joined query in `HarvestProvider.fetchHarvests`) · Update ✓ for harvest, **sale edit broken (B1)** · Delete ✓ for harvest (cascades sale + expense row); sale delete leaves stale data (B2) · validation ⚠️ partial (negatives/zero allowed, rate field has no validator) · calculations ⚠️ correct formula, **duplicated in 5 places** · persistence ✓ · errors ❌ (no try/catch on DB writes) · empty states ✓ (`EmptyStateWidget` on both tabs) · loading states ❌ (empty-state flash before data loads) · survives restart ✓.

**Concrete bugs:**
- **B1 — STALE DATA on sale update.** Trace: `_showEditSaleDialog` → `harvestProvider.updateSale(...)` (lines 1361–1369) → `HarvestProvider.updateSale` (`harvest_provider.dart:377-404`) updates **only** the `sales` row and calls `fetchHarvests()`. It never recomputes `harvests.gross_amount` / `net_income`. So after editing a sale's rate, the harvest card, the top summary cards (`_buildSummaryCards` sums `h.grossAmount`/`h.netIncome`), and the P&L per-crop tab (which uses `h.harvest.grossAmount`, `profit_loss_screen.dart:65-66`) all keep showing the OLD numbers, while the overall P&L header uses the new `sale.totalAmount` (`profit_loss_screen.dart:36-37`). Two screens disagree permanently until the harvest itself is edited. Compare with `recordSale` (`harvest_provider.dart:296-335`), which *does* recompute and write `gross_amount`/`net_income` — the update path was simply forgotten.
- **B2 — Dead end after deleting a sale.** `deleteSale` (`harvest_provider.dart:340-348`) deletes only the `sales` row; `harvests.gross_amount` stays at its old non-zero value. The "فروخت درج کریں" button is gated on `if (h.grossAmount == 0)` (line 303), so it **never reappears** — the user can never re-record a sale for that harvest, and the sales tab correctly hides it (`item.sale == null`). The harvest is stuck in a sold-but-unsold limbo.
- **B3 — `updateHarvest` clobbers separately-edited sales.** `updateHarvest` (`harvest_provider.dart:~251-295`) unconditionally INSERTs/UPDATEs the `sales` row from `quantity * ratePerUnit` of the harvest dialog. If the user edited the sale rate via the sales tab (B1's dialog), then later edits anything on the harvest (e.g. just notes), the sale row is silently overwritten with the harvest-dialog rate. Sale edits are effectively second-class and losable.
- **B4 — Division by zero-ish: yield per acre.** `final double yieldPerAcre = h.quantity / item.fieldSize;` (line 175). If `fieldSize` is 0 (field-creation validation doesn't forbid 0), double division yields `Infinity`/`NaN`, displayed as e.g. `پیداوار فی ایکڑ: Infinity من / ایکڑ` (line 215). No crash (double division), garbage UI.
- **B5 — No partial sales.** Both sale dialogs hardcode `quantity: item.harvest.quantity` (line 1245 in record-sale, line 1364 in edit-sale); there is no quantity input. A farmer selling half the harvest gets a wrong `totalAmount` and a wrong sale quantity in the DB.
- **B6 — `recordSale` forces `payment_status='Paid'`.** `harvest_provider.dart:312` sets `'payment_status': 'Paid'` unconditionally, ignoring whatever the user chose in the harvest dialog's payment-status dropdown (Paid/Partial/Pending).
- **B7 — Validation gaps (negatives).** Quantity validator (lines 543–547 and 886–890) only checks non-empty + numeric — `-50` من or `0` pass. The **rate field has no validator at all** (add dialog ~line 560s, edit dialog similar). Expense sub-fields (transport/labour/etc.) have no validators; negatives are silently accepted via `double.tryParse(...) ?? 0.0`.
- **B8 — Misleading dead `totalAmount` parameter.** `_showRecordSaleDialog` passes a computed `totalAmount`, but `recordSale` (`harvest_provider.dart:303`) recomputes `grossAmount = quantity * pricePerUnit` and uses *that* for both tables, ignoring the parameter — dead weight and a future divergence trap.
- **B9 — Duplicated financial logic.** `gross = qty*rate`, `totalExpense = sum(5)`, `net = gross - totalExpense` is retyped in: the add-dialog preview (~470–474), edit-dialog preview, `addHarvest` (`harvest_provider.dart:117-119`), `updateHarvest` (~182–184), `recordSale` (~303–304). Five copies of the same formula.
- **B10 — Unsold harvests booked as income.** `harvest_provider.dart:151` auto-inserts a `sales` row for *every* harvest with `grossAmount > 0`, regardless of `paymentStatus` ('Pending' = not sold). Both profit views overstate income; the farmer sees phantom profit.

**Hardcoded English shown to user:**
- Payment chips `'ادائیگی مکمل (Paid)'` / `'جزوی ادائیگی (Partial)'` / `'باقی (Pending)'` (~lines 234–245).
- Dates rendered as Latin `yyyy-MM-dd` (lines 195, 395); `'Rs.'` prefixes everywhere (acceptable as currency convention, but Latin).

**UX:** The add/edit dialog is very long (crop dropdown, qty+unit, rate+status, buyer, 5 expense fields, notes, date, live finance card) — overwhelming; rate is optional but nothing explains what happens if left blank. `yyyy-MM-dd` Latin-digit dates are not farmer-friendly. Positive: the live net-profit preview card is excellent UX for low literacy.

**Empty/loading/error states:** Good empty states with illustration asset on both tabs + `RefreshIndicator`. No loading spinner (initial `fetchHarvests` → empty-state flash). No error handling — a DB failure shows nothing.

---

## 7. `lib/screens/inventory_screen.dart` — گودام کا اسٹاک

**Purpose / reach:** Warehouse stock list with a total-stock-value header card, horizontal category filter chips, per-item cards (qty, rate, line value, low-stock badge), add/edit/delete via dialogs. Reached from the dashboard. Pull-to-refresh calls `fetchInventory()`.

**Checklist:** UI ✓ · navigation ✓ (dialogs) · model ✓ (`Inventory` model, `inventory` table) · CRUD ✓ (add merges with weighted-average cost; edit overwrites; delete with confirm) · validation ❌ · calculations ⚠️ (avg-cost merge correct in happy path; breaks at qty 0 / negatives) · persistence ✓ (sqflite; seeded at startup `main.dart:32`) · errors ❌ (no try/catch anywhere) · empty state ✓ · loading state ❌ · survives restart ✓.

**Concrete bugs:**
- **B1 — Negative/zero quantity and price accepted.** Add-dialog validators (lines 387–391 qty, 423–427 price) and identical edit-dialog validators (553–557, 589–593) only check non-empty + `double.tryParse`. `-5` qty or `-100` price pass, and `addInventoryItem` inserts/merges them.
- **B2 — No ledger, single quantity mutated in place.** No purchase/use/adjustment history — `inventory_provider.dart` `addInventoryItem`/`updateInventoryItem` just overwrite the row's `quantity`. Usage history is destroyed — which is exactly why overuse can be silently clamped to zero with no trace.
- **B3 — Merge math breaks at qty 0.** `addInventoryItem` (`inventory_provider.dart:34-46`): `newQty = item.quantity + quantity` with no floor; if `newQty == 0`, `newCost = (...)/0` → **Infinity/NaN** `cost_per_unit` → the stock card renders "Infinity روپے". Negative `newQty` yields a nonsense negative cost.
- **B4 — Low-stock threshold is unit-blind.** ~line 178: `final bool isLowStock = item.quantity <= 2;` — "2" means 2 tons for one item and 2 grams for another. Red "اسٹاک ختم!" only at exactly 0.
- **B5 — `deductInventoryItem` is dead code.** Defined (`inventory_provider.dart:63-80`) with the only `clamp(0.0, double.infinity)` floor in the provider — **zero callers**. Actual deductions go through `ActivityProvider._applyInventoryDelta`, which reimplements clamping. Two divergent deduction implementations, one unused.
- **B6 — Negative stock enterable directly.** `updateInventoryItem` has no negative-qty guard, and the screen's validators only check parseability → negative stock can be entered directly in the inventory screen.

**Hardcoded English shown to user:**
- Category map lines 14–21, e.g. `'کھاد (Fertilizer)'`, `'بیج (Seed)'` — English in parens in dropdown and list.
- Label `'اسٹاک کا زمرہ (Category)'` (~line 318, edit dialog ~line 484).

**UX:** Mostly good: big Urdu labels, icon+text FAB. Gaps: Latin-digit-only numeric input — Urdu/Arabic-Indic digits (۱۲۳) fail `double.tryParse` and the validator just says "صرف نمبر" with no hint; category dropdown mixes English parentheticals; no unit guidance (a farmer picking "بوری" vs "کلوگرام" changes all downstream math).

**Empty/loading/error states:** Empty ✅, pull-refresh ✅, loading ❌, error ❌.

---

## 8. `lib/screens/my_crops_screen.dart`

**Purpose / reach:** Crop-season management with per-season profit summary and an activity timeline. Tabs: فعال فصلیں / سابقہ فصلیں. Actions: add season (multi-field), edit, delete, "کٹائی مکمل کریں" (marks Harvested). Reached via **Dashboard → "میری فصلیں"** (`dashboard_screen.dart:165`).

**Checklist:** UI ✓ · navigation ✓ · model ✓ (`CropSeason` + `crop_season_fields` mapping) · CRUD ✓ (add/edit/delete season, status flip to Harvested) · validation ⚠️ (variety required; no date sanity; field deselect-all prevented) · calculations ❌ divergent from Profit/Loss screen (B1); naive per-field split (B4) · persistence ✓ · errors ❌ none · empty states ✓ per-tab · loading states ❌ (cold-start flash of "کوئی فعال فصل موجود نہیں ہے") · survives restart ✓.

**Concrete bugs:**
- **B1 — Profit calc duplicated AND divergent vs Profit/Loss screen.** This screen (lines 117–141, 256–259): `totalExpense = Σ activity.expenseAmount`; `totalIncome = Σ sale.totalAmount` (only harvests having a sale row); `profit = income − expense`. The Profit/Loss screen (`profit_loss_screen.dart:62-88`): `cropIncome = Σ harvest.grossAmount` (all harvests); `expenses = activity expenses + Σ harvest.totalExpense + Σ ushr.ushrAmount`; `net = income − expenses`. Same crop shows **two different "profit" numbers** in two screens — one ignores harvest expenses (transport/labour/commission) and ushr, the other includes them.
- **B2 — Unsold harvests counted as income in BOTH screens.** `harvest_provider.dart:151` auto-inserts a `sales` row for *every* harvest with `grossAmount > 0`, regardless of `paymentStatus` ('Pending' = not sold). "کل آمدن" and "کل منافع" show revenue for produce still sitting unsold. Phantom profit.
- **B3 — Deleting a crop season leaks expense rows.** `deleteCropSeason` (`crop_provider.dart:302-310`) deletes only the season row; FK cascades now remove activities/harvests/sales/ushr_records — but their `expenses` rows survive and permanently inflate `totalExpenses` in the Profit/Loss screen. Note the inconsistency: `deleteActivity`/`deleteHarvest` manually delete their expense rows, the cascade path doesn't.
- **B4 — "کھیت وار رپورٹ (اوسط تقسیم)" is a naive equal split.** `splitAmountAcrossFields` (`crop_provider.dart:81-86`) divides by field *count*, ignoring that fields have different sizes (`details.totalArea` is computed but never used for weighting). A 1-acre and a 10-acre field get identical cost/profit attribution.
- **B5 — `DateTime.parse` crash risk.** Line 204: `DateFormat('dd MMM yyyy').format(DateTime.parse(season.startDate))` — any corrupted/legacy `start_date` throws `FormatException` inside `build` → red screen. (Same pattern ~line 377 in the edit dialog init.)
- **B6 — Empty-fields edge.** Line 129: `fieldCount = details.fields.isEmpty ? 1 : details.fields.length` — if a season somehow has no linked fields, the "کھیت وار رپورٹ" header renders with zero rows beneath it (the `...details.fields.map` at line ~280 emits nothing).
- **B7 — Timeline duplicates steps.** `getDynamicTimelineForActivities` (`crop_provider.dart:70-79`) emits one step per activity with no dedup — two "کھاد ڈالی" entries render as two timeline nodes; completion matching is exact-string equality on Urdu titles (`_isTimelineStepCompleted`, ~line 700), brittle to any title change.
- **B8 — Pull-to-refresh only refetches crops.** `_buildCropList`'s `onRefresh` calls `cropProvider.fetchCropSeasons()` only — activity/harvest numbers refresh only because those providers rebuild; a manual refresh doesn't guarantee fresh activity/expense data.
- **B9 — Stale provider caches after delete.** `_confirmDeleteCrop` → `deleteCropSeason` refetches only crops; `ActivityProvider`/`HarvestProvider` in-memory lists still contain the deleted season's rows until their next fetch.
- **B10 — Hardcoded English default crop.** `_showAddCropSeasonDialog`: `String selectedCropKey = 'Rice'` — the English DB key is fine internally, but it's a magic default.

**Hardcoded English shown to user:**
- `labelText: 'قسم (Variety)'` (lines 577, 846); `'قسم کا نام لکھیں (Variety Name)'` (lines 596, 865).
- Dates via `DateFormat('dd MMM yyyy')` render English month abbreviations ("12 Oct 2026") inside Urdu UI (line 204).

**UX:** The card is information-dense (4 money figures + per-field lines + timeline) in small 13–14px text — heavy for low-literacy users. "اوسط تقسیم" is unexplained jargon. Positive: big green FAB "نئی فصل کاشت کریں", clear active/harvested badges.

**Empty/loading/error states:** Good per-tab empty states with guidance. No loading indicator (cold-start flash). No error state.

---

## 9. `lib/screens/my_farms_screen.dart`

**Purpose / reach:** Farm & field (کھیت) management: list farms with total area, expand each to see its fields (size, canal/tube-well water source), add/edit/delete farms and fields, view the farm's theka (lease) summary. Reached via **Dashboard → "میری زمینیں"** (`dashboard_screen.dart:156`).

**Checklist:** UI ✓ · navigation ✓ (dashboard push; theka details/form pushes) · model ✓ (`Farm`, `Field` models + tables) · CRUD ✓ (add/edit/delete farm + field via dialogs) · validation ⚠️ partial (name non-empty + numeric check only) · calculations ✓ (none needed — raw area display) · persistence ✓ · errors ❌ (no try/catch in the call chain) · empty states ✓ (`EmptyStateWidget` + CTA) · loading states ❌ · survives restart ✓.

**Concrete bugs:**
- **B1 — Delete cascades correctly now, but expense rows leak (data corruption).** With FK enforcement, `deleteFarm` (`farm_provider.dart:87-95`) cascades to fields → crop_seasons → activities/harvests/sales/ushr_records and thekas → installments; the dialog text at line 530 ('...اس سے متعلقہ تمام کھیت بھی حذف ہو جائیں گے۔') is now accurate. **However:** the `expenses` table is referenced *by* activities/harvests/ushr_records/theka_installments but references nothing itself. When activities are cascade-deleted, their linked expense rows are **never deleted** (the `ON DELETE SET NULL` on `activities.expense_id`, `db_helper.dart:111`, only fires when the *expense* is deleted, not the activity). Those orphan expense rows permanently inflate `ExpenseProvider.totalExpenses`, so the Profit/Loss screen's overall net stays wrong forever after any farm/field/season delete.
- **B2 — Only the first theka per farm is shown.** Line 586: `final theka = currentThekas.first;` — if a farm has 2+ thekas, the rest are invisible here (paid/pending computed from the first one's installments only).
- **B3 — "ٹھیکہ شامل کریں" drops farm context.** ~line 545 pushes `const ThekaFormScreen()` with no farmId; `ThekaFormScreen` accepts only an optional `theka` (`theka_form_screen.dart:8-11`). The user must re-select the farm from the form's own dropdown (`theka_form_screen.dart:278`) — friction, and a mis-tap links the theka to the wrong farm.
- **B4 — Negative/zero area accepted.** All four numeric validators (~lines 248–253, 305–310, 370–375, 455–460) only check non-empty + `double.tryParse`. `double.parse('-50')` passes → a farm with **−50 ایکڑ** is saved. No check that the sum of field sizes ≤ farm total area either.
- **B5 — No loading state; empty-state flash on cold start.** `FarmProvider` has no `isLoading`. On launch, `farmProvider.farms.isEmpty` is true until `fetchFarms()` completes (`main.dart:32`), so the screen briefly shows "کوئی زمین موجود نہیں ہے" + "نئی زمین شامل کریں" even when farms exist.
- **B6 — Zero error handling.** `addFarm`/`deleteFarm`/`addField` etc. have no try/catch; a DB failure surfaces as an unhandled async exception with the dialog already dismissed.
- **B7 — Stale theka cache after farm delete.** `deleteFarm` refetches only farms; `ThekaProvider` is not refreshed. Impact now limited since cascades remove the rows, but in-memory `thekaProvider.thekas` still holds them until next fetch; the theka list's `'نامعلوم فارم'` fallback (`theka_list_screen.dart:102-104`) is the safety net.

**Hardcoded English shown to user:** Essentially none — this screen is clean (all labels/buttons Urdu).

**UX:** Good overall — big Urdu labels, icons + text. Weaknesses: the only affordance for edit/delete is the `⋮` (`more_vert`) icon, undiscoverable for low-literacy users (no text label); the ExpansionTile pattern hides fields until tapped, with no hint that tapping expands.

**Empty/loading/error states:** Empty state good (illustration + guidance + CTA). No loading state (B5). No error state at all.

---

## 10. `lib/screens/profit_loss_screen.dart`

**Purpose / reach:** 4-tab report (فصل وار حساب / خرچے کا تجزیہ / ٹھیکہ کی رپورٹ / عشر کی رپورٹ). Reached via Dashboard → 'منافع و نقصان' (`dashboard_screen.dart:210`).

**Checklist:** UI ✓ · navigation ✓ · models ✓ · read-only report (no CRUD) · calculations ⚠️ (correct formulas, **inconsistent bases between views**, mixed-unit comparisons) · persistence n/a (local DB) · errors ❌ · empty states ⚠️ (text-only, no illustration) · loading states ❌ · survives restart ✓.

**How per-crop P&L is computed given `expenses` has no crop/farm FK — answered exactly:**

**Per-crop: a join through `activities`, not a heuristic — mostly correct by construction.** Exact code (lines 55–75):
```dart
final cropActivities = activityProvider.activities
    .where((act) => act.activity.cropSeasonId == seasonId)      // :56
    .toList();
final cropExpenses = cropActivities.fold(
    0.0, (sum, act) => sum + (act.expenseAmount ?? 0.0));        // :58-59
...
final cropIncome = cropHarvests
    .fold(0.0, (sum, h) => sum + h.harvest.grossAmount);          // :65-66
final cropHarvestExpenses = cropHarvests.fold(
    0.0, (sum, h) => sum + h.harvest.totalExpense);               // :68-69
final cropUshrExpenses = ushrProvider.ushrRecords
    .where((u) => u.ushrRecord.cropSeasonId == seasonId)
    .fold(0.0, (sum, u) => sum + u.ushrRecord.ushrAmount);        // :71-73
final totalCropExpenses = cropExpenses + cropHarvestExpenses + cropUshrExpenses; // :75
```
This works because the expense dialog auto-creates an `activities` row with `expense_id` when a crop is selected (`expenses_screen.dart:294-300`). Auto-created `Harvest Expenses`/`Ushr Expense` rows have **no** activity, but they're picked up via the `cropHarvestExpenses` and `cropUshrExpenses` folds — no double-count, and they land on the right crop via `harvests.crop_season_id` / `ushr_records.crop_season_id`. **The gap:** any *unlinked* general expense (متفرق) is attributed to **no** crop — invisible in the crop-wise tab, only surfaced as the aggregate "Indirect" line in the expense-analysis tab (`indirectExpenses = totalExpenses - linkedExpenseSum`, ~lines 125–127). So per-crop nets are systematically *overstated* for farmers with unallocated costs (diesel, electricity, land rent) — and the UI never says so.

**Per-farm: there is no per-farm P&L at all** — not broken, just missing. The Theka tab has a farm-wise theka table and the Ushr tab a farm-wise ushr table, but no farm revenue/expense/profit anywhere.

**Concrete bugs / inconsistencies:**
- **B1 — Overall vs per-crop use different income definitions.** Overall: `totalSales = harvests.where(sale != null).fold(... sale!.totalAmount)` (lines 36–37). Per-crop: `h.harvest.grossAmount` (lines 65–66). These diverge whenever the harvest-screen B1 bites (sale edited → stale `gross_amount`), so the summary header and the crop cards can permanently disagree.
- **B2 — Ushr counted on different bases.** Per-crop deducts the **full religious due** `ushrAmount` (lines 71–73); the overall `totalExpenses` deducts only what the `expenses` table holds for ushr — which is `totalPaidPkr` (only the *paid* portion, `ushr_provider.dart:88`). Partially-paid ushr → per-crop net is lower than the overall net implies. Inconsistent accounting basis.
- **B3 — Mixed-unit yield comparison.** `highestYielding` picks max of `pl.harvests.fold(0.0, (sum,h) => sum + h.harvest.quantity)` (~line 103) — summing من + کلوگرام + ٹن into one number. If two crops use different units the "highest yield" badge is meaningless (the display text breaks down per unit, but the *comparison* is on the mixed sum).
- **B4 — Unpaid ushr grouped under the current year.** Line ~1440–1442: `final String yearStr = u.datePaid != null ? u.datePaid!.split('-').first : DateTime.now().year.toString();` — pending ushr with no date is silently bucketed into *this* year in the yearly table.
- **B5 — Farm-wise ushr keyed by name string.** `farmUshr[item.farmName]` (~line 1434) — two farms with the same name merge; should key by farm id.
- **B6 — Theka yearly table mixes semantics.** `yearStr` uses *paid* year for paid installments and *due* year for pending ones (~lines 1267–1269) in a single table, so "سالانہ" totals blend two different meanings.
- **B7 — `mostProfitable` ignores all-loss case silently** (~lines 88–94): if every crop loses money, the "most successful crop" card just disappears rather than showing the least-bad crop — minor.
- **B8 — Heavy synchronous compute in `build`.** The whole 4-tab computation (folds over all seasons/harvests/activities/expenses/thekas/ushr) runs on every `build`; with large data this janks. No memoization.

**Hardcoded English shown to user:**
- `'اقساط کا تجزیہ (Installment Status)'` (~line 1230); `'زمین وار ٹھیکہ خرچہ (Farm-wise Expenses)'` / `'موسمی ٹھیکہ خرچہ (Seasonal Expenses)'` / `'سالانہ ٹھیکہ خرچہ (Yearly Expenses)'` (~line 1290+); `'اخراجات کی تفصیل بلحاظ زمرہ (Category):'` and `'غیر فصلاتی / متفرق اخراجات (Indirect)'` in the expense tab.

**UX:** Dense `Table` widgets with small text are hard for low-literacy users; 4 tabs with 20sp Nastaleeq labels risk overflow on 360px-wide phones. The crop ExpansionTile cards are the best pattern here. Filter chips ('تمام فصلیں' etc.) are clear.

**Empty/loading/error states:** Text-only empty states ('کوئی ریکارڈ موجود نہیں ہے'), no illustrations, no loading indicator, no error state — providers still fetching on first frame → the tab flashes "no record" then populates.

---

## 11. `lib/screens/settings_screen.dart`

**Purpose / reach:** Via dashboard popup menu → 'ترتیبات (Settings)'. Sections: reminder toggles + snooze dropdown, reminder-default checkboxes, battery/full-screen/exact-alarm permission rows (via `MethodChannel 'com.example.kisan_dost/share'` — all 7 methods verified implemented in `MainActivity.kt`), a backup stub, and a red "wipe all data" button.

**Checklist:** UI ✓ · navigation ✓ · reminder prefs ✓ (SharedPreferences) · permissions ✓ (status check + request flow) · **backup/restore ❌ — confirmed: there is NONE** · wipe-all exposed with two-step confirm ⚠️.

**Backup/restore — confirmed absent:**
- The "بیک اپ اور ڈیٹا بحالی (Backup & Restore)" section (~line 450) contains a single `const ListTile` with **no `onTap`** — a dead tile reading 'جلد آ رہا ہے (Coming Soon)' with a greyed-out icon. Pure stub.
- `clearAllTables` (`db_helper.dart:383-397`) deletes all 13 tables (verified the delete list covers every `CREATE TABLE` — ushr_records, theka_installments, thekas, farms, fields, crop_seasons, crop_season_fields, expenses, inventory, activities, harvests, sales, tasks). It **IS exposed to the user**: `_wipeAllData()` (line 172) is called from the red 'تمام ڈیٹا ہمیشہ کے لیے حذف کریں' button after a two-step confirm (`_showWipeConfirmDialog`, lines 224–262, `barrierDismissible` default true on the confirm — user can back out). **Data-loss risk: real but guarded** — two taps required, and since backup is a stub the wipe is truly irreversible. High severity if ever tapped accidentally (e.g., a child playing with the phone); the button is large and prominent at the bottom of a long settings page.

**Concrete bugs:**
- **B1 — Fire-and-forget refetches after wipe** (lines ~195–201): after `clearAllTables()`, `farmProvider.fetchFarms()` etc. are called **without `await`** (only `taskProvider.fetchTasks()` is awaited). If the user pops back instantly, providers can notify mid-navigation — no crash pattern-wise, but a race.
- **B2 — Double-pop fragility** (lines ~203–215): `navigator.pop()` closes the loader, then `navigator.pop()` "goes back to dashboard". If the loader dialog were ever dismissed by another path, the second pop would pop the Settings screen itself unexpectedly. Currently safe because `barrierDismissible: false`, but brittle.
- Deprecated `activeColor` on SwitchListTile/CheckboxListTile (multiple) — cosmetic deprecation warnings, not bugs.
- `_checkExactAlarmStatus` result is set twice (initState → `_checkExactAlarmStatus` and inside `_loadPreferences`) — redundant native calls, harmless.

**Hardcoded English shown to user (pervasive):**
- `'ترتیبات (Settings)'` (AppBar title, ~line 297); `'جلد آ رہا ہے (Coming Soon)'` (~line 455); plus `'(Reminders & Alarm)'`, `'(Snooze Duration)'`, `'(Ignore Battery Saving)'`, `'(Full Screen Alarm)'`, `'(Exact Alarm)'`, `'(Other App Permissions)'`, `'(Battery & System Settings)'`, `'(Backup & Restore)'` — nearly every section header carries an English parenthetical, heavy for the target audience.

**UX:** Long single scroll with English jargon in parentheses everywhere; permission rows have small `ElevatedButton`s ('اجازت دیں') — tappable, but the concepts (battery optimization, full-screen intent, exact alarms) are technical for a low-literacy farmer. The wipe button is dangerously prominent relative to its irreversibility (no backup exists).

**Empty/loading/error states:** n/a (settings form).

---

## 12. `lib/screens/splash_screen.dart`

*(Same as §1 — included once; see §1 for the full assessment.)* Fixed 3 s delay regardless of init progress (line 15); `'Developed by:'` hardcoded English (~line 117); otherwise fine.

---

## 13. `lib/screens/task_form_screen.dart` — نیا کام / ترمیم

**Purpose / reach:** Create/edit form: title, description, date+time pickers, recurrence (none/daily/weekly), reminder offsets (at-time/1h/1d, multi-select), default reminder prefs loaded from SharedPreferences. Pushed from `tasks_screen.dart` FAB (add) and edit icon (edit); pops on save.

**Checklist:** UI ✓ · navigation ✓ · model ✓ · Create/update ✓ via `TaskProvider.addTask` / `updateTask` (which schedule alarms) · validation ⚠️ (title required; date/time required; **past-date check only for new one-shot tasks**; reminder multi-select enforces ≥1) · persistence ✓ (+ alarm scheduling side-effect) · errors ⚠️ (DB/alarm failures surface only as `debugPrint` — user sees a success pop regardless) · survives restart ✓ (alarms re-armed via native `BootReceiver`).

**Concrete bugs:**
- **B1 — No user feedback if alarm scheduling fails.** `_saveTask` pops and the list shows the task; if the native `scheduleAlarm` channel call threw, `scheduleTaskNotifications` only `debugPrint`s — the farmer believes an alarm exists that doesn't.
- **B2 — Past-time validation gap (by design, undisclosed).** "Only validate past time for new non-recurring tasks" — for a new *recurring* task set in the past, the native scheduler rolls the trigger forward day-by-day, but the UX never tells the user the alarm was moved to tomorrow.
- `_loadDefaultReminderPrefs` keys match settings (`reminder_pref_at_time/1h/1d`) — verified consistent ✓.
- Date picker allows past dates (`firstDate: now - 365d`, comment "allow past dates for editing reference") — coherent with the one-shot past check.

**Hardcoded English shown to user:** Minimal — mostly clean Urdu. Worst: section title `'یاد دہانی کا دہراؤ (فریکوئنسی)'` (transliteration in parens).

**UX:** Excellent for low literacy: big tappable recurrence cards, checkbox rows, enforced ≥1 reminder with an Urdu snackbar. Gap: date shows as `dd MMM yyyy` (English month); time via system picker.

**Empty/loading/error states:** n/a (form); async prefs load has no skeleton but defaults render first — fine.

---

## 14. `lib/screens/tasks_screen.dart` — کام کی منصوبہ بندی

**Purpose / reach:** Task list grouped into Overdue / Today / Upcoming / Completed with a stats header, per-task countdown, alarm-status badge, toggle-complete, edit, delete. Reached from dashboard; FAB and edit button push `TaskFormScreen`.

**Checklist:** UI ✓ · navigation ✓ · model ✓ · CRUD ✓ · calculations ⚠️ (countdown fine; alarm badge is heuristic) · persistence ✓ · restart ✓ (alarms re-armed via native BootReceiver) · errors ❌ (`fetchTasks()` has no try/catch — DB failure → red screen) · empty ✓ · loading ✓ (spinner + `EmptyStateWidget` + pull-refresh).

**Concrete bugs:**
- **B1 — "الارم بج رہا ہے" badge is a guess, not state.** `_getAlarmStatusWidget` declares the alarm ringing when `now.difference(task.dateTime).abs().inMinutes <= 1` — it never checks whether the native `AlarmService` is actually running. Cosmetic, but the badge can claim "ringing" when nothing is.
- **B2 — 10-second full rebuild timer.** `initState` starts `Timer.periodic(10s)` calling `setState` forever (cancelled in `dispose` — OK). Every tick rebuilds the whole categorized list; on a low-end device this is constant CPU/battery churn for a countdown that only changes by the minute. Should be 60 s or driven by the next due time.
- **B3 — Snooze badge math:** `'الارم سوز ہے ($snoozeMin منٹ)'` where `snoozeMin = diff.inMinutes + 1` — the +1 fudge is unexplained.
- **B4 — `TaskItem.dateTime` is non-nullable** and `DateTime.parse(map['date_time'])` throws on any corrupt row — one bad row kills the entire task list load. Should be defensive.
- **B5 — "Self-healing" migration in `addTask`/`updateTask`** catches insert/update failure and runs `ALTER TABLE tasks ADD COLUMN ...` blindly, then retries. On the current schema (v9, columns exist) the ALTERs throw and are swallowed — harmless but it masks the *real* error, and if the retry also fails the task is silently not created while the UI already popped.
- **B6 — Toggle-complete on long-past one-shot tasks** re-schedules notifications that the native layer then skips — harmless but noisy.

**Hardcoded English shown to user:**
- Section headers: `'التوا کے کام (Overdue Tasks)'`, `'آج کے کام (Today's Tasks)'`, `'آنے والے کام (Upcoming Tasks)'`, `'مکمل شدہ کام (Completed Tasks)'`.
- `DateFormat('dd MMM yyyy, hh:mm a')` renders English month abbreviations and AM/PM to the farmer.

**UX:** Good visual hierarchy (color side-border, big toggle circle). Gaps: English dates; the "التوا (اوورڈیو)" badge mixes transliteration; countdown says "X دن میں شروع ہوگا" ("will start in X days") for a *due* task — wrong verb, should be "باقی".

**Empty/loading/error states:** Loading ✓, empty ✓, error ❌.

---

## 15. `lib/screens/theka_details_screen.dart` — ٹھیکہ کی تفصیلات

**Purpose / reach:** Contract detail: summary header (total/paid/pending), agreement facts, installment schedule with per-installment Pay / Edit-payment / Cancel-payment actions, app-bar edit + delete. Pushed from list card tap and `my_farms_screen.dart`. Edit-payment reuses the record-payment dialog.

**Checklist:** UI ✓ · navigation ✓ · model ✓ · read / pay / edit-payment / cancel-payment / delete-contract ✓ · validation ❌ (overpayment not blocked) · calculations ❌ (pending can go negative) · persistence ✓ (`payInstallment` in transaction; expense ledger synced) · errors ⚠️ (no try/catch around `payInstallment`/`markInstallmentPending`) · empty state ✓ ('معاہدہ نہیں مل سکا' fallback) · loading state ❌ · survives restart ✓.

**`payInstallment` semantics — traced end to end (answers the cross-screen question):**
- **Semantics = CUMULATIVE (total paid so far), implemented as replace.** Dialog prefill (line 33): `text: (inst.status == 'Pending' ? inst.amount : inst.paidAmount).toStringAsFixed(0)` — pending prefilled with the *full* installment amount, previously-paid prefilled with current `paidAmount`. On save (lines 104–110) the raw field value is passed as `paidAmount:` → `theka_provider.dart:96`: `isFullPayment = paidAmount >= currentInst.amount`; line 131 writes `'paid_amount': paidAmount` (**replace, not accumulate**); the linked `expenses` row is inserted/updated with the same amount (lines 104–128). The label 'ادا شدہ رقم (روپے)' reads as cumulative, so replace is internally consistent — **but:**
- **B1 — OVERPAYMENT BUG (confirmed).** The dialog validator (lines 61–66) only rejects empty / non-numeric / ≤ 0. Entering **more than the installment amount** (e.g. 100,000 on a 50,000 qist) → `isFullPayment = true` → status `'Paid'`, and a **100,000 expense row** is written to the ledger. Downstream: `pendingAmt = totalAmount − ΣpaidAmount` goes **negative** in both list and details headers, and the list progress bar computes >100% ("120%"). No cap at `inst.amount`, no warning, no "change/advance" concept.
- **B2 — Partial-payment UX trap.** On a 'Partially Paid' installment the field is prefilled with the current cumulative total, so a farmer who paid 20k of 50k and now pays another 30k will type "30000" meaning *this* payment — but replace-semantics records 30k total, silently *reducing* the recorded paid amount. The dialog never explains it wants the running total.
- **B3 — No try/catch** around `payInstallment` / `markInstallmentPending` — a DB error mid-transaction leaves the dialog open with no feedback (the provider itself doesn't throw to the UI).
- **B4 — Cumulative-replace is unenforced.** `'paid_amount': paidAmount` (provider line 131) is correct *only if* every caller passes cumulative totals — the dialog does, but nothing documents or enforces it; a future caller passing an increment silently corrupts.
- **B5 — Cancel-payment** (`markInstallmentPending`) correctly deletes the linked expense and zeroes the installment ✓.
- **B6 — No validation that `paidDate` is sane** (future dates accepted) — minor.

**Hardcoded English shown to user:**
- Status chips: `'غیر ادا شدہ (Pending)'`, `'ادا شدہ (Paid)'`, `'جزوی ادا شدہ (Partially Paid)'`; `'ایک بارگی (Lump-sum)'` / `'اقساط میں (Installments)'` in the facts card.

**UX:** Strong: per-qist Pay/Edit/Cancel, destructive confirm for contract delete with an honest warning that expenses/ledger rows go too. Gaps: the cumulative-total field semantics (above) will confuse; payment date defaults to today with a picker — good.

**Empty/loading/error states:** Missing-contract ✓; loading ❌; error ❌.

---

## 16. `lib/screens/theka_form_screen.dart` — نیا ٹھیکہ / ترمیم

**Purpose / reach:** Create/edit lease: farm+field pickers, duration type + auto end-date, total amount, payment method (lump-sum vs installments) with an installment schedule builder (auto-generate, per-row amount/date editing, add/remove rows, sum-vs-total validation banner). Pushed from list FAB/CTA, from details "شیڈول بدلیں", and from `my_farms_screen.dart`. Edit mode loads existing schedule; **refuses edit if any installment isn't Pending**.

**Checklist:** UI ✓ · navigation ✓ · model ✓ · Create ✓ (`addTheka` in a DB transaction) · Update ⚠️ implemented as **delete + re-insert** · validation ✓ (installment sum must equal total ±0.01; farm required; amount numeric) · calculations ⚠️ (installment spacing + date overflow quirks) · persistence ✓ · errors ✓ (try/catch with red snackbar) · survives restart ✓.

**Concrete bugs:**
- **B1 — Edit = delete + re-insert** (~lines 195–225; the code comments admit the uncertainty: "Wait, for simplicity let's delete the old one and add new, or do update"). Consequences: `createdAt` is reset to now on every edit; the theka row keeps its old id only because `toMap()` carries `id` and the old row was deleted first — fragile; all installment rows get **new ids**. The `hasPayments` guard makes this safe today (edit blocked once any payment exists), but it's a data-identity hazard. The provider's purpose-built `updateInstallmentSchedule` (`theka_provider.dart:174-213`) is **dead code** — the "شیڈول بدلیں" button routes to this form instead.
- **B2 — First installment is never due at start.** `_generateInstallments` computes `dueDate` at `(i+1) * intervalMonths` — for a yearly 2-installment plan the dues are +6mo and +12mo. A farmer expecting the first qist at signing gets a schedule with no immediate due. Debatable product decision, but undisclosed.
- **B3 — "سہ ماہی" mislabeled.** The duration dropdown says `'سہ ماہی/فصلاتی (Seasonal)'` — سہ ماہی means *quarterly/3-month*, but the code treats Seasonal as **6 months** (`_endDate = +6 months`; installment spacing `6/N`). Should read "ششماہی".
- **B4 — Start/end date cross-validation missing.** The end-date picker constrains `firstDate: _startDate` ✓, but the *start*-date picker allows picking a start **after** the already-chosen end (`firstDate: DateTime(2020)`, no upper bound), and `_saveForm` never checks `endDate >= startDate`. Result: negative-duration contracts saved silently.
- **B5 — `DateTime` month-overflow silently shifts due dates.** `DateTime(year, month + k, day)` normalizes (e.g. day=31 → March 3) with no warning to the user.
- `double.parse(_totalAmountController.text)` at line 141 is validator-guarded ✓ — no crash.

**Hardcoded English shown to user:**
- `'سالانہ (Yearly)'`, `'سہ ماہی/فصلاتی (Seasonal)'`, `'کسٹم (Custom)'` in the duration dropdown; `'ایک بارگی ادائیگی (Lump-sum)'`, `'اقساط میں ادائیگی (Installments)'` in the payment-method dropdown; labels `'زمین (Farm) منتخب کریں'`, `'ادائیگی کا طریقہ (Payment Method)'`.

**UX:** The installment builder is powerful but heavy for low literacy: generate → hand-edit rows → watch the sum banner. The red/green sum-validation banner is genuinely good feedback. Gaps: no explanation of the (i+1)-interval due-date behavior; per-row date buttons show `yyyy-MM-dd`.

**Empty/loading/error states:** Validation summary banner ✓; no async loading states (all local).

---

## 17. `lib/screens/theka_list_screen.dart` — زمین کا ٹھیکہ

**Purpose / reach:** Lease-contract list with a financial summary header (total / paid / pending), per-contract cards with progress bar and installment counts, tap → `ThekaDetailsScreen`. Reached from dashboard; FAB + empty-state CTA push `ThekaFormScreen`.

**Checklist:** UI ✓ · navigation ✓ · model ✓ · CRUD ✓ (via details/form screens) · calculations ❌ (overpayment breaks them) · persistence ✓ · errors ❌ (no loading/error state; `fetchThekas` has no try/catch) · empty ✓ (+ CTA) · loading ❌ · restart ✓.

**Concrete bugs:**
- **B1 — Progress >100% on overpayment.** Line 129: `progress = paidAmt / totalAmount` is uncapped; the overpayment bug (§15) lets `paidAmt > totalAmount`, rendering e.g. "120%" text next to a full bar. Should clamp to 1.0 and flag overpayment.
- **B2 — `overallPaid` trusts `paidAmount`.** Line 41 sums `inst.paidAmount` across installments — consistent with cumulative semantics, OK unless overpaid (see §15).
- **B3 — Dead helper** `elementsId(int id) => id` (~line 262) used once as a no-op wrapper — confusing, delete.
- **B4 — No loading indicator** — `fetchThekas` in `initState` with no `isLoading`; first paint shows the empty state briefly even when contracts exist.

**Hardcoded English shown to user:** Minimal — worst is fine. The duration chip maps Yearly/Seasonal/Custom to Urdu ✓; `'نامعلوم فارم'` fallback is Urdu ✓.

**UX:** Good: summary header, progress bar, color-coded amounts. Gaps: amounts in Latin digits with "روپے" — fine; no due-date/overdue surfacing on the card (a farmer can't see *which* installment is due next without tapping in).

**Empty/loading/error states:** Empty ✓, loading ❌, error ❌.

---

## 18. `lib/screens/todays_work_screen.dart`

**Purpose / reach:** Reached from dashboard via 'آج کا کام'. Two parts: (1) grid of 12 hardcoded activity-type buttons (پانی لگایا … دیگر کام), each pushing `ActivityFormScreen(activityTitle: ...)`; (2) "حالیہ سرگرمیاں (ڈیجیٹل ڈائری)" list with per-item popup menu: ترمیم / ڈپلیکیٹ / مکمل-نشان toggle / حذف. Pull-to-refresh re-fetches.

**Checklist:** UI ✓ · navigation to form ✓ · full CRUD on activities via `ActivityProvider` (add in form screen, read list, update, duplicate, delete w/ linked expense + inventory restock) ✓ · delete has confirm dialog ✓ · after delete it refreshes Inventory/Expense/Crop/Harvest/Task providers (lines ~252–257) ✓ · uses `EmptyStateWidget` ✓ · persistence ✓.

**Concrete bugs:**
- **B1 — Title promises "today", shows all history.** Line ~51 vs. `activity_provider.dart:14-38`: AppBar says 'آج آپ نے کھیت میں کیا کیا؟' ("What did you do in the field *today*?") and the empty state says 'آج کے لیے کوئی کام نہیں ہے' ("no work *for today*") — but `fetchActivities()` has **no date filter** (`ORDER BY a.date DESC` over the whole table). The screen is the full lifetime diary, not today's work. Misleading label + wrong empty-state copy.
- **B2 — Crash-prone parse** (~line 199): `DateTime.parse(act.date)` inside the list builder — a `FormatException` would crash the whole list. Writes always use `toIso8601String()` (`activity_form_screen.dart:582, 597`), so low risk in practice, but no `tryParse` guard.
- **B3 — Bang operators on nullable ids** (~lines 232, 239, 243): `act.id!` in toggle-complete and delete paths. Safe in practice (rows come from DB with autoincrement ids) but unguarded.

**Hardcoded English shown to user:** None in UI (all Urdu labels). The `DateFormat('yyyy-MM-dd HH:mm')` pattern is code, not user-facing.

**UX:** Excellent for low-literacy users — big icon grid, one tap per activity type. The per-item `PopupMenuButton` (⋮) is a small target hiding 4 actions; a farmer may not discover edit/delete there. Urdu numerals not used in dates (Latin digits) — acceptable.

**Empty/loading/error states:** Empty state via `EmptyStateWidget` ✓ (but with the wrong "today" copy noted above). `RefreshIndicator` ✓. No error state if fetch fails (no try/catch — an exception leaves the old list silently).

---

## 19. `lib/screens/ushr_screen.dart`

**Purpose / reach:** Ushr (Islamic crop-zakat) calculator + payment tracker. Reached via Dashboard → 'عشر مینجمنٹ' (`dashboard_screen.dart:237`).

**Checklist:** UI ✓ · navigation ✓ · model ✓ (`ushr_records` table, `UshrRecord` model) · CRUD ✓ (all four wired) · validation ⚠️ (custom % validated 0–100, but qty/rate accept negatives) · calculations ✓ correct (verified below) · persistence ✓ · errors ❌ · empty state ✓ · loading state ❌ · survives restart ✓.

**Ushr math — VERIFIED CORRECT against fiqh:**
- Natural (rain-fed): `percentage = 10.0` (lines 377–378) → 1/10 ✓
- Artificial (irrigated): `percentage = 5.0` (line 379) → 1/20 ✓
- Custom: user %, validated `0–100` (~lines 520–526) ✓
- `ushrQty = (qty * percentage) / 100.0` (line 384) ✓; `calculatedUshrAmount = (marketValue * percentage) / 100.0` (line 385) ✓; `ushrQtyKg = ushrQty * 40.0` (line 388, 1 من = 40 kg ✓); `remainingBalance = calculatedUshrAmount - totalPaidPkr` (line 394) with `remainingBalance > 0 ? remainingBalance : 0` clamp on save; status auto `Paid`/`Pending` (~line 397). The on-screen card showing من / KG / روپے equivalents is genuinely good UX.

**Concrete bugs:**
- **B1 — Hardcoded من unit vs. any harvest unit.** The dialog labels are 'کل کٹائی مقدار (من/Maund)' (~line 490), 'ادا شدہ فصل کی مقدار (من)' (~line 620), and the kg conversion assumes maunds (line 388). If the linked harvest was recorded in کلوگرام/ٹن/بوری, the ushr quantity and the ×40 conversion are **wrong** — and the harvest-autofill copies that unit's quantity straight in (~lines 440–447).
- **B2 — In-kind ushr doesn't reduce the harvest.** Paying ushr in crop (`qtyPaid`) writes an `expenses` row for `qtyPaid * rate` but never decrements the harvest quantity — the harvest card still shows the full quantity, P&L counts the full income, *and* the given-away crop is counted as a cash-equivalent expense. Theologically ushr comes *out of* the produce; here it's counted on top of full income.
- **B3 — Controller mutation inside `build`.** `if (marketValueController.text != marketValue.toStringAsFixed(0) && marketValue > 0) { marketValueController.text = ...; }` (~lines 370–373) — side-effect during build; when `marketValue == 0` the field keeps stale text from a previous entry.
- **B4 — Negative/zero qty & rate accepted.** Validators (~lines 505–518) require non-empty + numeric only. Negative qty → negative ushr due; the custom-% validator is the only one with range checking.
- **B5 — Overpayment shows "complete" with no warning.** If `remainingBalance < 0` (paid more than due), the card shows 'ماشاءاللہ! ادائیگی مکمل ہو گئی ہے۔' (~lines 676–680) — no overpayment notice, and the saved `remainingBalance` is clamped to 0, silently discarding the overpaid amount.
- **B6 — Delete dialog references a non-existent "ledger".** 'اس سے متعلقہ لیجر خرچہ بھی حذف ہو جائے گا' (~line 760) — there is no ledger feature; it's the `expenses` row. Copy inconsistency.
- **B7 — Edit-mode rigidity.** `selectedDatePaid` initializes from `existingRecord.datePaid` or `DateTime.now()` (~line 345); on *add*, if status flips to Paid the date picker appears — fine. Editing a Pending record can't set a future intended date — rigid but not a bug.

**Hardcoded English shown to user:**
- `'ادائیگی کا طریقہ (Pay Ushr As)'` (~line 545); `'کسٹم شرح فیصد (Percentage)'` (~line 510); `'یا کلوگرام میں: ... KG (کلوگرام)'` (line 663); status chips `'ادا شدہ (Paid)'`/`'باقی (Pending)'`.

**UX:** The calculation card (من/KG/روپے + paid/remaining) is the best in the app. Downsides: Latin `yyyy-MM-dd` dates; very long dialog; the harvest-autofill dropdown is only on the add path (fine).

**Empty/loading/error states:** `EmptyStateWidget` ✓, `RefreshIndicator` ✓, no loading spinner, no error handling on DB writes.

---

## 20. `lib/theme/app_theme.dart` — design system assessment

**Is there a real design system?** **Partial — more of a theme file than a system.**
- **Defines:** 6 color constants (primary green `0xFF2E7D32`, accent, background, card white, error, success); a complete Nastaleeq `TextTheme` scale (display → label, all with `Jameel Noori Nastaleeq`); `AppBarTheme` (green bg, white fg, centered, 26 sp Nastaleeq title); `ElevatedButtonTheme` (green, 22 sp); `CardTheme` (white, elevation 4, 16 dp radius, 8 dp margin). Material 3 via `ColorScheme.fromSeed`.
- **Missing:** no `inputDecorationTheme` (text fields unstyled), no spacing/radius constants, no icon/dialog/snackbar/bottom-sheet themes, no dark mode.
- **The real problem — it's largely ignored:** `dashboard_screen` uses a deepPurple/indigo gradient summary card and `Colors.brown/green/blue...shade600` buttons; `settings_screen` and `about_us_screen` set `backgroundColor: Colors.deepPurple.shade600` on their AppBars, overriding the theme's green. So the app has two competing identities (theme green vs. hardcoded deepPurple) — the "system" exists on paper but screens don't follow it.

---

## 21. `lib/widgets/empty_state_widget.dart`

**What it looks like:** `Center` → animated floating image (`AnimationController`, 3 s `repeat(reverse: true)`, ±8 px vertical `easeInOutSine` translate), 180×180 `Image.asset` with `errorBuilder` fallback to a `CircleAvatar` + icon, then a 24 sp bold Nastaleeq message and optional 18 sp grey subtitle. Clean, friendly, Urdu-first.

**Actually used?** Yes — by 9 screens: `expenses`, `harvest`, `inventory`, `my_crops`, `my_farms`, `tasks`, `theka_list`, `todays_work`, `ushr` (verified via grep). **Not** used by `profit_loss_screen` (text-only empty states) — worth aligning. The `errorBuilder` means a missing asset degrades gracefully instead of red-screening. Well built.

---

## 22. `lib/main.dart` — routing & provider wiring (supporting check)

**Routing:** No named routes at all — every navigation is an inline `MaterialPageRoute` push from the calling screen. `home: SplashScreen()`. Navigation graph is implicit; traced: Splash → Dashboard → {10 module screens}; Dashboard popup → {About, Settings}; Dashboard → TodaysWork → ActivityForm; notification launch → AlarmScreen. All target screens exist on disk — **no missing-route bugs**.

**Provider wiring (verified against every screen audited):**
```dart
FarmProvider, CropProvider, InventoryProvider, ActivityProvider,
HarvestProvider, ExpenseProvider, TaskProvider, ThekaProvider, UshrProvider
```
each created with a cascade `..fetchX()` at startup. Every `Provider.of` target in the audited screens resolves to a registered provider — **no missing-provider bug, no undefined methods**. `NotificationService` exposes all methods called from screens (verified against the service), and all 7 MethodChannel methods called from settings/dashboard exist in `MainActivity.kt`.

**Notes:** `builder` wraps everything in forced `Directionality(TextDirection.rtl)` — correct for an Urdu-only app, but it also flips any inherently-LTR content. `NotificationService().init()` is awaited before `runApp` — good. No `TODO`/`FIXME`/`XXX` stubs found anywhere in `lib/` (grep clean).

---

## Cross-screen findings

### CS1. Profit logic is duplicated and divergent (HIGH)
`my_crops_screen.dart:117-141` computes profit = Σ(`sale.totalAmount`) − Σ(`activity.expenseAmount`); `profit_loss_screen.dart:62-88` computes crop net = Σ(`harvest.grossAmount`) − (activity expenses + Σ(`harvest.totalExpense`) + Σ(`ushr.ushrAmount`)). Same crop shows **two different "profit" numbers** in two screens. Additionally the overall P&L header uses `sale.totalAmount` while per-crop uses `harvest.grossAmount` (lines 36–37 vs 65–66), and ushr is costed at the full religious due per-crop but only the paid portion overall. **Fix:** one shared `computeCropPL()`; one income definition.

### CS2. Sale update/delete leaves stale harvest aggregates (HIGH)
`HarvestProvider.updateSale` (:377-404) updates only the `sales` row and never recomputes `harvests.gross_amount`/`net_income`; `deleteSale` (:340-348) leaves `gross_amount` non-zero so the "فروخت درج کریں" button (gated on `grossAmount == 0`, line 303) never reappears. Harvest card, summary cards, and P&L per-crop tab all disagree with the sales tab permanently.

### CS3. Cascade deletes leak expense rows (HIGH — data corruption)
With `PRAGMA foreign_keys = ON` (db_helper.dart:27-28, landed mid-audit), structural cascades work. But `expenses` has no inbound FKs: cascade-deleting activities/harvests/ushr records/theka installments (farm/field/season/theka delete) leaves their expense rows behind, permanently inflating `ExpenseProvider.totalExpenses` and corrupting the P&L net. `deleteActivity`/`deleteHarvest` clean their own expense rows manually — the cascade path doesn't. Fix: delete linked expense rows in `deleteFarm`/`deleteField`/`deleteCropSeason`/`deleteTheka`, or add the cleanup to the cascade path.

### CS4. `payInstallment` is cumulative-replace with an unblocked overpayment bug (HIGH)
Dialog passes the full field value; provider **replaces** `paid_amount` (theka_provider.dart:131), with `isFullPayment = paidAmount >= amount` (line 96). Validator (theka_details_screen.dart:61-66) blocks only empty/non-numeric/≤0. Overpayment (e.g. 100k on a 50k qist) → status 'Paid', 100k expense row in the ledger, negative pending totals, >100% progress bar (theka_list_screen.dart:129). Also a UX trap: on a partially-paid qist the field is prefilled with the *running total*, so typing "this payment's amount" silently reduces the recorded total.

### CS5. Inventory: no ledger, negative stock possible, silent over-deduction (HIGH)
- No purchase/use/adjustment records — a single `quantity` column mutated in place; usage history destroyed.
- Inventory dialogs accept negative qty/price (inventory_screen.dart:387-391, 423-427, 553-557, 589-593); provider merge has no floor and divides by zero at `newQty == 0` → Infinity/NaN cost (inventory_provider.dart:34-46).
- Stock can't go negative only because `_applyInventoryDelta` (activity_provider.dart:137) **silently clamps** — overuse is discarded with no record, while the expense for the full requested qty is still recorded.
- Missing item on deduct → silent `return`, activity + expense still saved, no stock moves (activity_provider.dart:121-123). Missing item on restore (edit/delete) → **auto-creates a zero-cost stock row** (lines 124-131).
- `convertUnit` duplicated in form and provider with identical holes: 'بوتل'/'پیکٹ' unconvertible → quantity passed through unchanged → wrong-unit deduction (e.g. 5 bottles deduct 5 liters); 1 بوری = 50 kg hardcoded with no UI note.
- `InventoryProvider.deductInventoryItem` (lines 63-80) and `ActivityProvider.duplicateActivity` are dead code; `ThekaProvider.updateInstallmentSchedule` (lines 174-213) is dead code; theka_list `elementsId` (~line 262) is a dead no-op helper.
- Null-check crash: `costPerUnit: finalExpenseAmount! / inventoryQty` (activity_form_screen.dart:550) — non-numeric price crashes; qty 0 → Infinity cost.

### CS6. Unsold harvests booked as income (MEDIUM-HIGH)
`harvest_provider.dart:151` auto-inserts a `sales` row for *every* harvest with `grossAmount > 0`, regardless of `paymentStatus`. Both profit views show revenue for unsold produce — phantom profit. A sale row should only exist after an actual sale (`recordSale`).

### CS7. Alarm architecture: native side is real; the Flutter `alarm_screen.dart` is the dead component (MEDIUM)
- `android/app/src/main/kotlin/com/example/kisan_dost/` contains `MainActivity.kt` (MethodChannel `com.example.kisan_dost/share`: `scheduleAlarm`/`cancelAlarm`/`rescheduleAllAlarms`/`canScheduleExactAlarms`/`requestExactAlarmPermission`), `AlarmScheduler.kt` (AlarmManager `setAlarmClock`, slots `taskId*10+0..8` + slot 9 snooze), `AlarmReceiver.kt`, `BootReceiver.kt` (BOOT_COMPLETED etc.), `AlarmService.kt` (foreground service, looping `res/raw/farming_alarm.mp3` which exists), `AlarmActivity.kt` (native full-screen UI, `res/layout/activity_alarm.xml` exists), `DatabaseHelper.kt` (opens the same `kisan_dost.db` via `getDatabasePath`). Manifest registers `AlarmReceiver` + `BootReceiver` + all needed permissions (SCHEDULE_EXACT_ALARM, USE_FULL_SCREEN_INTENT, POST_NOTIFICATIONS, FOREGROUND_SERVICE, etc.). **Alarms DO survive reboot.**
- Mismatch is the reverse of what one might fear: the native side is real and registered; the **Flutter** `alarm_screen.dart` is unreachable dead code on Android and its Complete/Dismiss/Snooze handlers cancel **FLN IDs** — a silent no-op against native alarms (alarm_screen.dart:78, 104, 122). If it ever displayed, "الارم بند کریں" would update the DB while the native `AlarmService` keeps ringing.
- Gaps on the native path: recurring tasks don't truly repeat (one-shot `setAlarmClock`; next day only scheduled on app launch/reboot — non-Android FLN path uses `matchDateTimeComponents` and repeats properly); native snooze hardcodes 10 min and ignores the user's snooze-duration pref (`AlarmReceiver.kt`); scheduling failure is `debugPrint`-only — farmer believes an alarm exists that doesn't.
- "سوز" is the wrong word for snooze (means "burn"; should be سنوز) — user-visible on every alarm (notification titles, native action label).

### CS8. No backup + irreversible wipe = biggest product risk (HIGH)
Settings advertises backup as a dead "Coming Soon" tile with **no `onTap`** (settings_screen.dart:~450) while exposing `clearAllTables()` — a real, irreversible wipe of all 13 tables — behind a two-step confirm (lines 172, 224-262). One confused tap chain and a farmer's entire diary is gone with no recovery path. Ship backup before (or with) the wipe button, or demote the wipe.

### CS9. Zero DB indexes (LOW at current scale)
`CREATE INDEX` is absent everywhere. `TaskProvider.fetchTasks()` loads the whole `tasks` table and counts in memory (dashboard_screen.dart:~252-258). Fine for hundreds of rows; pattern to watch as data grows. No N+1 patterns found — single queries per screen, not loops of queries.

### CS10. Loading/error/empty-state hygiene (MEDIUM)
- **No loading states on:** farms, crops, inventory, harvest, expenses, ushr, profit_loss, theka list, activity form. Every one flashes its empty state on cold start while `main.dart` fetches complete (including the alarming "کوئی فعال فصل موجود نہیں ہے!" on the activity form and a false "diary up to date" all-clear on the dashboard).
- **No error states anywhere** — zero try/catch on any provider read/write path; one corrupt row (`DateTime.parse` in `TaskItem.fromMap`) or a locked DB → red screen or silent failure.
- **Empty states are good where they exist** (`EmptyStateWidget`, reused by 9 screens, with asset-failure `errorBuilder`) — except `profit_loss_screen` (text-only) and `todays_work_screen` (wrong "today" copy).

### CS11. "Today's Work" is mislabeled (MEDIUM)
`todays_work_screen.dart` title says 'آج آپ نے کھیت میں کیا کیا؟' and the empty state says 'آج کے لیے کوئی کام نہیں ہے', but `fetchActivities()` has **no date filter** — it's the lifetime diary. Either add the filter or rename.

### CS12. Validation gaps are systemic (MEDIUM-HIGH)
Negative/zero accepted in: farm/field area (my_farms_screen.dart:~248-460), inventory qty/price, activity qty (391-399), harvest qty/rate (rate has no validator at all), expense amounts (expenses_screen.dart:235-236), ushr qty/rate, theka paidDate (future dates OK), activity dates (up to 2030, no future check). Urdu/Arabic-Indic digits (۱۲۳) fail `double.tryParse` everywhere with an unhelpful "صرف نمبر" message. No kanal/marla unit support anywhere — areas are acres-only (real UX gap for Pakistani farmers; no conversion code exists to verify).

### CS13. Money as `double` everywhere (MEDIUM)
`REAL` columns, `double` in all models (`expenses.amount`, `harvest.grossAmount`, `inventory.costPerUnit`, …). `toStringAsFixed(0)` masks it, but repeated folds can drift by fractions of a rupee. Should be integer paisa via a central money utility.

### CS14. English-in-parentheses pattern + two visual identities (LOW-MEDIUM)
`(Settings)`, `(Coming Soon)`, `(Exact Alarm)`, `(Overdue Tasks)`, `(Variety)`, `(Maund)`, `(Pending)`… run through settings, tasks, crops, harvest, theka, ushr — at odds with the Urdu-first goal and the Nastaleeq work. `AppTheme` says green; dashboard summary card and settings/about AppBars say deepPurple. Pick one.

### CS15. Navigation & provider wiring: sound (POSITIVE)
No named routes — inline `MaterialPageRoute` everywhere — but all 10 dashboard targets, popup items, and form pushes resolve to existing screens; no missing routes. All providers referenced by screens are registered in `main.dart`; no missing-provider bug, no undefined methods, no TODO/FIXME stubs anywhere in `lib/`. All 7 MethodChannel methods called from Dart exist in `MainActivity.kt`. Delete flows on today's-work refresh dependent providers correctly.

---

## Highest-priority fix order (by user impact)

1. Ship backup (or demote the wipe): no-backup + irreversible `clearAllTables()` is the worst data-loss risk in the app.
2. `updateSale`/`deleteSale` must recompute `harvests.gross_amount`/`net_income` — stale-data bug corrupts summaries + P&L permanently.
3. Cap/reject overpayment in the theka payment dialog (and clamp progress); clarify cumulative-total semantics in the dialog label.
4. Fix the expense-row leak on cascade deletes (farm/field/season/theka) — otherwise every deletion permanently corrupts `totalExpenses` and the P&L net.
5. Reject negative/zero qty+price in inventory dialogs; floor merge math; null/zero-guard `activity_form_screen.dart:550` (live crash path).
6. Unify crop-profit computation into one shared function (screens currently show two different profits); define one income basis (sold vs harvested); stop auto-creating sale rows for unsold harvests.
7. Negative/zero validation sweep across all numeric forms; Urdu-digit parsing support; add kanal/marla.
8. Money as integer paisa; stop duplicating financial formulas (harvest gross/net in 5 places; `convertUnit` in 2 places).
9. True repeat for native daily/weekly alarms; user-visible failure when alarm scheduling fails; fix سوز → سنوز; decide the FLN-vs-native alarm path (delete or wire up `alarm_screen.dart`).
10. Loading + error states on all list screens; fix the "today's work" mislabel; align English-parenthetical labels to Urdu-first; unify the theme identity.
