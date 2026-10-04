# Kisan Dost — UI & Navigation Safety Audit (2026-10-04)

READ-ONLY audit. No code was modified (another agent is editing `lib/screens/`
and `lib/widgets/`). Every issue below carries the exact fix so it can be
applied mechanically once that agent lands.

**Totals: 3 Medium, 4 Low, 1 Info. 0 Critical, 0 High.**

---

## MEDIUM

### M1 — Party delete is a single tap with no confirmation dialog

**Files:** `lib/screens/parties_screen.dart:283-299`, `lib/screens/party_detail_screen.dart:270-286`

Both party edit dialogs place a red "حذف کریں" (`Strings.delete`) TextButton in
the dialog actions that calls `provider.deleteParty(id)` directly — no
confirmation step. Every other destructive action in the app (farm, crop,
expense, harvest, sale, task, theka, ushr, activity, inventory, backup) has a
confirmation dialog. A farmer editing a party's phone number can fat-finger the
red button and permanently delete the party (and its ledger history).

**Exact fix** — wrap the delete in a confirmation dialog. In
`lib/screens/parties_screen.dart`, replace (lines ~283-299):

```dart
              if (existing != null)
                TextButton(
                  onPressed: () async {
                    try {
                      await provider.deleteParty(existing.id!);
                      if (ctx.mounted) Navigator.pop(ctx);
                    } on PartyException catch (e) {
```

with:

```dart
              if (existing != null)
                TextButton(
                  onPressed: () async {
                    final confirmed = await showDialog<bool>(
                      context: ctx,
                      builder: (dctx) => AlertDialog(
                        title: const Text('پارٹی حذف کریں؟'),
                        content: const Text(
                          'کیا آپ واقعی اس پارٹی کا کھاتہ حذف کرنا چاہتے ہیں؟ یہ عمل واپس نہیں لیا جا سکتا۔',
                        ),
                        actions: [
                          TextButton(
                            onPressed: () => Navigator.pop(dctx, false),
                            child: const Text('منسوخ کریں'),
                          ),
                          ElevatedButton(
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.red,
                              foregroundColor: Colors.white,
                            ),
                            onPressed: () => Navigator.pop(dctx, true),
                            child: const Text('جی ہاں، حذف کریں'),
                          ),
                        ],
                      ),
                    );
                    if (confirmed != true || !ctx.mounted) return;
                    try {
                      await provider.deleteParty(existing.id!);
                      if (ctx.mounted) Navigator.pop(ctx);
                    } on PartyException catch (e) {
```

Apply the identical change in `lib/screens/party_detail_screen.dart` (~line 270),
replacing `provider.deleteParty(party.id!)`.

### M2 — Save buttons without double-submit guards (duplicate records on double-tap)

The expense dialog (`expenses_screen.dart:410`), harvest dialogs
(`harvest_screen.dart:1076,1560`) and activity form
(`activity_form_screen.dart:652`) all use the proven `isSaving`/`_isSaving`
guard pattern. These do NOT:

| Screen | Save entry | Lines |
|---|---|---|
| `task_form_screen.dart` | `onPressed: _saveTask` | 114, 288 |
| `theka_form_screen.dart` | `onPressed: _saveForm` | 149, 798 |
| `inventory_screen.dart` (add-stock dialog) | `onPressed: () async {...}` | 536 |
| `inventory_screen.dart` (adjust-quantity dialog) | `onPressed: () async {...}` | 885 |

A double-tap (common on slow devices / shaky hands) fires two concurrent
saves → duplicate tasks, duplicate theka contracts + installments, duplicate
inventory items or double quantity adjustments.

**Exact fix** — follow the existing `activity_form_screen.dart` pattern:

1. Add state field: `bool _isSaving = false;`
2. Guard at the top of the save method:
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
3. Optionally show progress on the button:
```dart
              ElevatedButton(
                onPressed: _isSaving ? null : _saveTask,
                child: _isSaving
                    ? const SizedBox(
                        width: 20, height: 20,
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: Colors.white),
                      )
                    : const Text('محفوظ کریں'),
              )
```

For the two inventory dialogs (536, 885), add a dialog-local
`bool isSaving = false;` (declared next to `formKey`, same as
`harvest_screen.dart:711`) and the `if (isSaving) return; setState(...);`
guard at the top of `onPressed`, resetting in a `finally` / after the
`Navigator.pop`.

### M3 — Theka edit is delete-then-reinsert with no transaction

**File:** `lib/screens/theka_form_screen.dart:251-268`

Editing a theka runs `await thekaProv.deleteTheka(id)` then
`await thekaProv.addTheka(newTheka, instModels)` as two separate provider
calls. The code itself carries the author's worried comment:

```dart
// Since sqlite cascades delete, we can delete the old one first, then insert new.
// Wait! Let's do that in a single database helper call or transact.
```

If `addTheka` throws (validation, disk-full, DB locked) after the delete
succeeded, the contract AND its installments are gone with no recovery path.
(Also relevant to the accounting audit: `deleteTheka` treatment of linked
paid-installment expenses is guarded by the `hasPayments` check above, which
is correct.)

**Exact fix** — add a transactional replace to `ThekaProvider`
(e.g. `replaceTheka(oldId, newTheka, installments)` wrapping both statements
in `db.transaction`), then replace lines 267-268:

```dart
          await thekaProv.deleteTheka(widget.theka!.id!);
        }
        await thekaProv.addTheka(newTheka, instModels);
```

with:

```dart
          await thekaProv.replaceTheka(widget.theka!.id!, newTheka, instModels);
        } else {
          await thekaProv.addTheka(newTheka, instModels);
        }
```

where `replaceTheka` deletes the old row + installments and inserts the new
ones inside a single `db.transaction` (all-or-nothing).

---

## LOW

### L1 — Deleted party renders a "zombie" detail screen instead of not-found

**File:** `lib/screens/party_detail_screen.dart:57-80`

If the party is deleted while the detail screen is open (or in the back
stack), `party` is null but the screen still renders: title falls back to
'پارٹی کھاتہ', the balance card shows `balanceOf(ghostId)` (0 or stale
ledger math), and only the edit button is hidden. The batai detail screen
(`batai_detail_screen.dart:56`, 'معاہدہ نہیں ملا') and theka detail screen
(`theka_details_screen.dart:303`, 'معاہدہ نہیں مل سکا') both do this right.

**Exact fix** — after the `party` lookup loop (~line 63), add:

```dart
    if (party == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('پارٹی کھاتہ')),
        body: const Center(
          child: Text(
            'یہ پارٹی اب موجود نہیں ہے۔',
            style: TextStyle(fontSize: 16),
          ),
        ),
      );
    }
```

### L2 — Inventory transaction history has no loading or error state

**File:** `lib/screens/inventory_screen.dart:656-659`

```dart
) => FutureBuilder<List<InventoryTransaction>>(
      future: inventoryProvider.getTransactions(item.id!),
      builder: (ctx, snapshot) {
        final txs = snapshot.data ?? const <InventoryTransaction>[];
```

On error, `snapshot.data` is null → silently renders an empty history; while
loading there is no indicator. A failed query looks identical to "no
transactions", which is misleading for stock reconciliation.

**Exact fix** — inside the builder, before the `final txs` line:

```dart
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Padding(
            padding: EdgeInsets.all(24),
            child: Center(child: CircularProgressIndicator()),
          );
        }
        if (snapshot.hasError) {
          return const Padding(
            padding: EdgeInsets.all(24),
            child: Center(
              child: Text('لین دین کی تاریخ لوڈ نہ ہو سکی۔'),
            ),
          );
        }
```

### L3 — Farm/field delete-confirm button fires without await or disable

**File:** `lib/screens/my_farms_screen.dart:633-640`

```dart
                if (isFarm) {
                  provider.deleteFarm(id);
                } else {
                  provider.deleteField(id, parentId!);
                }
                Navigator.pop(ctx);
```

The red confirm button neither awaits the delete nor disables itself, so a
rapid double-tap fires the delete twice. Second delete is almost certainly
harmless (idempotent soft-delete), but the dialog also pops before the write
completes, so a failure is silent.

**Exact fix:**

```dart
              onPressed: () async {
                Navigator.pop(ctx); // close dialog first
                if (isFarm) {
                  await provider.deleteFarm(id);
                } else {
                  await provider.deleteField(id, parentId!);
                }
              },
```

(Apply the same await pattern to the other delete-confirm buttons that
fire-and-forget; most already await.)

### L4 — Reports / P&L screens don't use the shared empty-state widget

`reports_screen.dart` and `profit_loss_screen.dart` are the only two screens
not using `EmptyStateWidget`. Both handle empty lists inline
(`profit_loss_screen.dart:444, 986, 1112, 1709`), so this is not a blank-page
bug — but verify on-device that a brand-new farmer sees a friendly
"no data yet" message on each report tab, not just zeros and empty charts.

---

## INFO

### I1 — Dashboard has 11 navigation cards (low-literacy note)

`dashboard_screen.dart:840-912` — farms, crops, today's work, expenses,
inventory, P&L, tasks, theka, parties, batai, reports, plus settings. This
exceeds the "~3 primary actions" guideline, but it is a labeled icon grid
with large Urdu labels, which is the standard accessible pattern for this
audience. **No change recommended** — flagged only for the record.

---

## Verified safe (no issue)

- **Navigation arguments:** every `Navigator.push` uses typed constructor
  arguments (`ThekaFormScreen(theka: theka)`, `PartyDetailScreen(partyId: …)`,
  etc.). No `ModalRoute` argument maps, no `!` on route args, no `int.parse`
  on route params anywhere — navigation-arg crashes are structurally
  impossible.
- **Destructive confirmations:** all other deletes (farm, field, crop season,
  expense, harvest, sale, task, activity, theka, ushr, inventory item, backup
  file, delete-all-data) sit behind Urdu confirmation dialogs with a grey
  "منسوخ کریں" and a visually distinct red confirm button.
- **Dialog dismissal direction:** all confirm dialogs are barrier-dismissible
  (tap-outside = cancel, the safe direction). Only progress/loader dialogs
  (`backup_screen.dart:312`, `reports_screen.dart:125`,
  `settings_screen.dart:185`) are non-dismissible — correct.
- **Empty states:** `EmptyStateWidget` is used on 14 screens; list screens
  without it handle emptiness inline.
- **Back-stack after wipe:** `_wipeAllData` pops the loader then settings,
  landing on the dashboard which reloads from the emptied DB — no stale
  screens over deleted data. Splash uses `pushReplacement` (no back-nav to
  splash). Onboarding uses `pushReplacement` to dashboard.
- **Stale-record handling:** theka and batai detail screens show friendly
  Urdu "not found" states; theka uses `orElse` fallbacks for missing farm /
  field instead of throwing.
- **Form validation:** all forms call `_formKey.currentState!.validate()`
  before saving (wording quality is the input-validation audit's scope).
