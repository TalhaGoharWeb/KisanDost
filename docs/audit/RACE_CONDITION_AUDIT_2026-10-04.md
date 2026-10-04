# Kisan Dost — State Management Race Condition & Stale Data Audit (2026-10-04)

**Mode:** read-only (no code modified — other agents own `lib/providers/`, `lib/screens/`, `lib/widgets/`).
**Method:** static analysis of all 11 providers, 27 screens, `notification_service.dart`, `demo_data_service.dart`.
Each finding below carries file:line evidence, the exact interleaving, and a mechanical fix.

---

## HIGH

### H1 — Task form: double-tap creates duplicate tasks + duplicate alarms
**Files:** `lib/screens/task_form_screen.dart:114` (`_saveTask`), `:288` (`onPressed: _saveTask`)

The save button stays enabled while the async save is in flight:
```dart
void _saveTask() async {                       // line 114 — no _isSaving guard
  if (_formKey.currentState!.validate()) {
    ...
    await context.read<TaskProvider>().addTask(...);   // DB insert + alarm schedule
    if (mounted) Navigator.pop(context);
  }
}
...
ElevatedButton(onPressed: _saveTask, ...)       // line 288 — never disabled
```
**Race:** tap → `addTask` starts (insert row, `fetchTasks`, `scheduleTaskNotifications`) → before it completes, second tap → second `addTask` → **two identical task rows, two alarm sets**. The farmer gets double reminders for one task.
**Fix** (`task_form_screen.dart`):
- Add field: `bool _isSaving = false;`
- Line 114: insert at top of `_saveTask`:
```dart
void _saveTask() async {
  if (_isSaving) return;
  setState(() => _isSaving = true);
  try {
    ... existing body ...
  } finally {
    if (mounted) setState(() => _isSaving = false);
  }
}
```
- Line 288: `onPressed: _isSaving ? null : _saveTask,`

### H2 — Theka form: double-tap creates duplicate contracts (+ installments)
**Files:** `lib/screens/theka_form_screen.dart:149` (`_saveForm`), `:798` (`onPressed: _saveForm`)

Same missing-guard pattern. Worse: the **edit** flow does `deleteTheka(oldId)` then `addTheka(new)`:
a second tap interleaves as `delete(newId?)`/`addTheka` again → duplicate contracts each
with a full installment set, corrupting the theka ledger view.
**Fix:** identical `_isSaving` guard pattern as H1, applied to `_saveForm` and line 798.

---

## MEDIUM

### M1 — Inventory "add stock" dialog: double-tap → duplicate purchase + double stock
**File:** `lib/screens/inventory_screen.dart:536` (`onPressed: () async {`)

No `isSaving` guard; two rapid taps run `recordPurchase` concurrently. The provider side is
transactional (ledger stays consistent), but two purchase rows and 2× stock are real.
**Fix:** add a dialog-local `bool isSaving = false;` (StatefulBuilder state), guard:
```dart
onPressed: () async {
  if (isSaving) return;
  setState(() => isSaving = true);
  try {
    ... existing body (already awaits recordPurchase) ...
  } finally {
    if (context.mounted) setState(() => isSaving = false);
  }
}
```
Same pattern needed at the record-usage dialog (`:885`, currently awaited but unguarded — LOW).

### M2 — Fire-and-forget mutations followed by navigation (stale UI + swallowed errors)
The provider methods are correctly async (`await db.insert` → `await fetchX()` → `notifyListeners`),
but **callers don't await them**, then immediately `Navigator.pop`:

| File:line | Call | Problem |
|---|---|---|
| `my_farms_screen.dart:314` | `addFarm(...)` unawaited → `Navigator.pop(ctx)` | List rebuilds before `fetchFarms` → farm missing; insert error = unhandled async error, user thinks it saved |
| `my_farms_screen.dart:384` | `updateFarm(...)` unawaited → pop | Same |
| `my_farms_screen.dart:635,637` | `deleteFarm`/`deleteField` unawaited → pop | Deleted row may still render until late refresh |
| `my_crops_screen.dart:869` | `addCropSeason(...)` unawaited → pop | Same as addFarm |
| `my_crops_screen.dart:1220` | `updateCropSeason(...)` unawaited → pop | Same |
| `tasks_screen.dart:671` | `deleteTask(id)` unawaited → pop | Task may reappear briefly; alarm cancel races the pop |
| `harvest_screen.dart:1888` | `updateSale(...)` unawaited → pop + **unconditional success snackbar** | Snackbar says "کامیابی سے تبدیل ہو گیا" even if the update threw |
| `ushr_screen.dart:1163` | `deleteUshrRecord(id)` unawaited → pop + unconditional success snackbar | Same false-success |
| `inventory_screen.dart:611` | `Navigator.pop(ctx)` **before** `await deleteInventoryItem` | Dialog closes, then delete runs; error path shows snackbar on a popped context |

**Fix (mechanical, per site):** make the callback `async`, `await` the provider call inside try/catch,
pop only on success, show the Urdu error on failure. Example (`my_farms_screen.dart:311-318`):
```dart
// current:
onPressed: () {
  if (formKey.currentState!.validate()) {
    Provider.of<FarmProvider>(context, listen: false).addFarm(...);
    Navigator.pop(ctx);
  }
},
// replacement:
onPressed: () async {
  if (saving) return;                       // + bool saving guard (see H1)
  if (formKey.currentState!.validate()) {
    setState(() => saving = true);
    try {
      await Provider.of<FarmProvider>(context, listen: false).addFarm(...);
      if (ctx.mounted) Navigator.pop(ctx);
    } catch (e) {
      if (ctx.mounted) ScaffoldMessenger.of(ctx).showSnackBar(
        const SnackBar(content: Text('محفوظ نہیں ہو سکا — دوبارہ کوشش کریں'))),
    } finally {
      if (mounted) setState(() => saving = false);
    }
  }
},
```
For the two false-success snackbars (`harvest_screen.dart:1888`, `ushr_screen.dart:1163`): move the
success snackbar **after** the awaited call.

### M3 — `toggleTaskCompletion` read-modify-write on a stale UI snapshot
**Files:** `lib/providers/task_provider.dart:184-186`, `lib/screens/tasks_screen.dart:423`, `lib/screens/dashboard_screen.dart:326`
```dart
Future<void> toggleTaskCompletion(int id, bool currentStatus) async {
  final newStatus = !currentStatus;   // currentStatus is the pre-tap UI value
```
**Race:** rapid double-tap → tap1 reads `false`→writes `true`; tap2 (before `fetchTasks` refreshes the UI)
reads stale `false`→writes `true` again: two audit rows, two alarm cancel/schedule cycles, and if the
second tap lands after refresh the final state flips back — **non-deterministic outcome**. Both call sites
are unawaited `InkWell.onTap` with no in-flight guard.
**Fix (pick one):**
- (a) Atomic SQL — replace the Dart toggle with:
```dart
await db.rawUpdate(
  'UPDATE tasks SET is_completed = 1 - is_completed, snoozed_until = NULL WHERE id = ?',
  [id],
);
```
then read back the row to decide cancel vs schedule. Immune to stale snapshots.
- (b) Per-task in-flight guard: `final _toggling = <int>{};` in the provider; `if (!_toggling.add(id)) return; try { ... } finally { _toggling.remove(id); }`, plus disable the InkWell while `_toggling.contains(id)`.

### M4 — Inventory availability check is check-then-act in Dart (TOCTOU)
**File:** `lib/providers/inventory_provider.dart:257-295` (`_recordUsageTx`)
```dart
final Inventory? item = await getItemById(itemId, executor: ex);  // read
...
if (qtyInItemUnit > item.quantity) throw ...;                      // check (Dart)
await ex.update('inventory',
  {'quantity': item.quantity - qtyInItemUnit}, ...);               // act (Dart-computed)
```
The whole thing runs inside `db.transaction`, and sqflite serializes writers, so on a single phone
this is *practically* safe — but the pattern is still time-of-check-time-of-use: two overlapping
transactions can both pass the Dart check on the same stale read under a deferred transaction.
**Fix (atomic SQL, no behavior change):**
```dart
// replacement for the check + update pair:
final changed = await ex.rawUpdate(
  'UPDATE inventory SET quantity = quantity - ? WHERE id = ? AND quantity >= ?',
  [qtyInItemUnit, itemId, qtyInItemUnit],
);
if (changed == 0) {
  throw InventoryException(
    'گودام میں صرف ${item.quantity.toStringAsFixed(1)} ${item.unit} دستیاب ہے — '
    'اتنی مقدار استعمال نہیں ہو سکتی');
}
```
The availability gate and the decrement become one atomic statement; concurrent deductions can no
longer both pass a stale check. (Keep the `getItemById` read for unit conversion + error message.)

### M5 — Demo entry is not re-entrancy-safe; kill mid-insert orphans demo rows
**Files:** `lib/services/demo_data_service.dart:137-150`, `lib/screens/settings_screen.dart:234`
```dart
Future<void> enterDemo({...}) async {
  if (_active) return;   // memory-only flag; false during a second concurrent call
```
**Race A (double-tap):** two rapid taps on the demo tile → both calls pass `if (_active) return`
(`_active` only becomes true at the end) → two interleaved full demo inserts → duplicate demo farms,
crops, expenses. The `before` max-ID snapshots overlap, so exit-demo's tracked IDs can't cleanly
remove both copies.
**Race B (kill mid-insert):** `idsKey`/`activeKey` are written only after step 9 of 9. Kill the app
mid-insert → ~partial demo rows persist, untracked, indistinguishable from real data; re-entering demo
tracks only the *second* batch, so the first batch's orphans can never be auto-removed.
**Fix:**
- Add `bool _entering = false;` — `if (_active || _entering) return; _entering = true; try { ... } finally { _entering = false; }`, and disable the settings demo tile while entering.
- For crash-safety: wrap the nine insert steps in a single `db.transaction` (all-or-nothing), or write a
`demo_insert_incomplete` marker pref *before* step 1 and clear it at the end; on startup, if the marker
is set, delete rows with `created_at` after the marker timestamp (or simply warn + offer cleanup).

---

## LOW

### L1 — Inventory edit-item dialog: awaited but unguarded
**File:** `lib/screens/inventory_screen.dart:885` — `await updateItemDetails(...)` with no double-tap guard.
Two rapid taps → two concurrent updates; last-writer-wins, no corruption. Add the same `isSaving` guard as M1.

### L2 — `alarm_screen.dart` try/catch around unawaited futures catches nothing
**File:** `lib/screens/alarm_screen.dart:98,149`
```dart
try {
  context.read<TaskProvider>().fetchTasks();   // not awaited → async errors escape the try
} catch (e) { debugPrint('Could not refresh provider: $e'); }
```
Harmless today (`fetchTasks` handles its own errors via `errorMessage`), but the try/catch is misleading.
Fix: `unawaited(context.read<TaskProvider>().fetchTasks());` with a clarifying comment, or await it.

### L3 — Unawaited fetches in initState / post-frame callbacks
`dashboard_screen.dart:54`, `tasks_screen.dart:25`, `backup_screen.dart:74-80`,
`settings_screen.dart:202-207`, `alarm_screen.dart:149`. Fire-and-forget refresh is acceptable here
(they run once per screen entry, providers surface errors via `errorMessage`), but any failure is silent
unless the screen renders `errorMessage`. Verified: dashboard renders `_sectionErrorCard` on error —
acceptable. No change required; noted for completeness.

---

## Verified SAFE (no action needed)

- **P&L never goes stale:** `profit_loss_screen.dart:37` recomputes via `computeFarmPnl(...)` from live
provider lists on every build; all providers are `Provider.of` (listening). No cached P&L state exists.
- **Alarm scheduling is idempotent:** `scheduleTaskNotifications` (`notification_service.dart:237`) starts
with `cancelTaskNotifications(task.id)`; re-scheduling never duplicates.
- **Kill between task-insert and alarm-schedule self-heals:** `NotificationService.initialize()` calls
`rescheduleAllPendingAlarms()` on every launch (`notification_service.dart:234`); the Kotlin
`BootReceiver` reschedules on reboot with `deleted_at IS NULL` filtering.
- **Activity + inventory deduction are atomic:** `activity_provider.dart:262-268,395-401` pass the outer
transaction executor into `inventoryProvider.recordUsage(executor: txn, ...)` — one DB transaction.
- **`notifyListeners` ordering:** all providers notify only after their awaits complete; no optimistic
update-before-write pattern found.
- **Deleted-record detail screens:** `theka_details_screen.dart:302-307` renders "معاہدہ نہیں مل سکا"
when the record is gone; `my_farms_screen.dart:657` guards `currentThekas.first` with `isEmpty`.
- **No fetch storms:** fetches live in `initState`/post-frame/error-retry only; the 10s `Timer` in
`tasks_screen.dart:30` only calls `setState` (rebuild from provider cache), never hits the DB.
- **Backup/restore guarded:** `_isRestoring` (`backup_screen.dart:36`) disables restore buttons;
`_isCreating` (`:466`) disables the create button; both reset in `finally`.
- **Guarded forms (no change):** `activity_form_screen` (`_isSaving`), `batai_detail_screen` (`_isSaving`),
harvest add/edit dialogs (`isSaving`), expense dialog (`isSaving`), ushr dialog (`isSaving`).

---

## Fix priority
1. **H1, H2** — `_isSaving` guards on task + theka forms (duplicate financial/contract records).
2. **M2** — await + try/catch + move success snackbars after the await (stale UI, false "success").
3. **M3** — atomic SQL toggle or in-flight guard (non-deterministic task state).
4. **M1, L1** — `isSaving` guards on inventory dialogs (duplicate stock movements).
5. **M4** — atomic `UPDATE ... WHERE quantity >= ?` in `_recordUsageTx` (TOCTOU).
6. **M5** — demo re-entrancy guard + crash-safe insert (orphan demo rows).
7. **L2** — clarify the misleading try/catch in `alarm_screen.dart`.
