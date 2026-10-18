import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import '../widgets/digit_text.dart';
import '../providers/expense_provider.dart';
import '../providers/crop_provider.dart';
import '../providers/activity_provider.dart';
import '../providers/farm_provider.dart';
import '../providers/inventory_provider.dart';
import '../models/models.dart';
import '../services/money.dart';
import '../widgets/empty_state_widget.dart';
import '../l10n/strings.dart';
import '../services/unit_converter.dart';
import '../utils/error_messages.dart';
import '../widgets/field_validators.dart';

class ExpensesScreen extends StatefulWidget {
  const ExpensesScreen({super.key});

  @override
  State<ExpensesScreen> createState() => _ExpensesScreenState();
}

class _ExpensesScreenState extends State<ExpensesScreen> {
  /// Expense categories created automatically by other screens
  /// (harvest, theka and ushr mirrors). Deleting one can orphan its source
  /// record, so the delete dialog warns first (S19).
  static const Set<String> _systemLinkedCategories = {
    'Harvest Expenses',
    'Ushr Expense',
    'Land Rent',
  };
  /// Maps an expense category to the inventory category it draws stock from.
  /// Null means the category has no inventory linkage (e.g. Labour).
  static const Map<String, String> _expenseToInventoryCategory = {
    'Fertilizer': 'Fertilizer',
    'Seeds': 'Seed',
    'Sprays': 'Spray',
    'Diesel': 'Diesel',
    'Crop Medicine': 'Medicine',
  };

  /// Recomputes the expense amount from the used inventory quantity:
  /// usedQty (in item units, or kg converted via weightPerUnitKg) ×
  /// costPerUnitPaisa. Writes the rupee value into the amount field so the
  /// farmer sees the true cost and can still override it by hand.
  static void _recalcAmountFromInventory(
    Inventory? item,
    TextEditingController qtyController,
    String qtyUnit,
    TextEditingController amountController,
  ) {
    if (item == null) return;
    final qty = double.tryParse(qtyController.text.trim());
    if (qty == null || qty <= 0) return;
    double qtyInItemUnits = qty;
    if (qtyUnit == 'kg' &&
        item.weightPerUnitKg != null &&
        item.weightPerUnitKg! > 0) {
      qtyInItemUnits = qty / item.weightPerUnitKg!;
    }
    final costPaisa = (qtyInItemUnits * item.costPerUnitPaisa).round();
    amountController.text = _paisaToRupeesText(costPaisa);
  }

  /// Formats integer paisa as the rupees text the amount field expects
  /// ("1500" or "1500.50") — the inverse of [Money.parse].
  static String _paisaToRupeesText(int paisa) {
    final rupees = paisa / 100.0;
    return rupees == rupees.roundToDouble()
        ? rupees.toInt().toString()
        : rupees.toStringAsFixed(2);
  }

  static String _formatPaisa(int paisa) {
    final rupees = paisa / 100.0;
    return rupees == rupees.roundToDouble()
        ? 'روپے ${rupees.toInt()}'
        : 'روپے ${rupees.toStringAsFixed(2)}';
  }

  @override
  Widget build(BuildContext context) {
    final expenseProvider = Provider.of<ExpenseProvider>(context);
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('خرچے کا ریکارڈ'),
        actions: [
          IconButton(
            icon: const Icon(Icons.add_card),
            tooltip: 'نیا خرچہ درج کریں',
            onPressed: () => _showAddExpenseDialog(context),
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: () async {
          await expenseProvider.fetchExpenses();
        },
        child: Column(
          children: [
            // 1. Highlight Total Expense Summary Card
            Container(
              width: double.infinity,
              margin: const EdgeInsets.all(16),
              padding: const EdgeInsets.symmetric(vertical: 24, horizontal: 16),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [theme.colorScheme.error, Colors.red.shade700],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.circular(20),
                boxShadow: [
                  BoxShadow(
                    color: theme.colorScheme.error.withValues(alpha: 0.3),
                    blurRadius: 10,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: Column(
                children: [
                  const Text(
                    'کل اخراجات (خرچے)',
                    style: TextStyle(
                      color: Colors.white70,
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 8),
                  DigitText(
                    Money(expenseProvider.totalExpensesPaisa).format(),
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 36,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
            ),

            // 2. List of recorded expenses
            Expanded(
              child:
                  expenseProvider.expenses.isEmpty
                      ? SingleChildScrollView(
                        physics: const AlwaysScrollableScrollPhysics(),
                        child: SizedBox(
                          height: math.max(
                            MediaQuery.of(context).size.height * 0.5,
                            400.0,
                          ),
                          child: const EmptyStateWidget(
                            message: 'کوئی خرچہ ریکارڈ نہیں ہے',
                            subtitle:
                                'نیا خرچہ درج کرنے کے لیے نیچے بٹن دبائیں',
                            fallbackIcon: Icons.trending_down,
                            imageAsset: 'assets/images/wheat.png',
                          ),
                        ),
                      )
                      : ListView.builder(
                        padding: const EdgeInsets.symmetric(horizontal: 12),
                        itemCount: expenseProvider.expenses.length,
                        itemBuilder: (context, index) {
                          final exp = expenseProvider.expenses[index];
                          final catUrdu =
                              expenseProvider.expenseCategories[exp.category] ??
                              exp.category;

                          return Card(
                            margin: const EdgeInsets.only(bottom: 12),
                            child: ListTile(
                              leading: CircleAvatar(
                                backgroundColor: Colors.red.shade50,
                                child: const Icon(
                                  Icons.trending_down,
                                  color: Colors.red,
                                ),
                              ),
                              title: Text(
                                catUrdu,
                                style: const TextStyle(
                                  fontWeight: FontWeight.bold,
                                  fontSize: 18,
                                ),
                              ),
                              subtitle: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  if (exp.description != null &&
                                      exp.description!.isNotEmpty)
                                    Text(exp.description!),
                                  Text(
                                    DateFormat(
                                      'yyyy-MM-dd',
                                    ).format(DateTime.parse(exp.date)),
                                    style: const TextStyle(
                                      fontSize: 12,
                                      color: Colors.grey,
                                    ),
                                  ),
                                ],
                              ),
                              trailing: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  DigitText(
                                    Money(exp.amountPaisa).format(),
                                    style: const TextStyle(
                                      color: Colors.red,
                                      fontWeight: FontWeight.bold,
                                      fontSize: 18,
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  IconButton(
                                    icon: const Icon(
                                      Icons.edit_outlined,
                                      color: Colors.grey,
                                    ),
                                    tooltip: 'ترمیم کریں',
                                    onPressed:
                                        () => _showAddExpenseDialog(
                                          context,
                                          existing: exp,
                                        ),
                                  ),
                                  IconButton(
                                    icon: const Icon(
                                      Icons.delete_outline,
                                      color: Colors.grey,
                                    ),
                                    onPressed:
                                        () => _confirmDeleteExpense(
                                          context,
                                          exp,
                                        ),
                                  ),
                                ],
                              ),
                            ),
                          );
                        },
                      ),
            ),
          ],
        ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _showAddExpenseDialog(context),
        icon: const Icon(Icons.add),
        label: const Text('نیا خرچہ درج کریں'),
        backgroundColor: Colors.red.shade700,
        foregroundColor: Colors.white,
      ),
    );
  }

  /// Shows the add/edit expense form. When [existing] is given the form is
  /// pre-filled and saving calls [ExpenseProvider.updateExpense] instead of
  /// [ExpenseProvider.addExpense] (S15). Edit mode skips the inventory
  /// linkage: stock was already deducted at creation time and there is no
  /// stock-reversal path on edit.
  void _showAddExpenseDialog(BuildContext context, {Expense? existing}) {
    final isEdit = existing != null;
    final expenseProvider = Provider.of<ExpenseProvider>(
      context,
      listen: false,
    );
    final cropProvider = Provider.of<CropProvider>(context, listen: false);
    final activityProvider = Provider.of<ActivityProvider>(
      context,
      listen: false,
    );
    final farmProvider = Provider.of<FarmProvider>(context, listen: false);
    final inventoryProvider = Provider.of<InventoryProvider>(
      context,
      listen: false,
    );
    final formKey = GlobalKey<FormState>();

    String selectedCategory = existing?.category ?? 'Miscellaneous';
    int? selectedFarmId = existing?.farmId;
    int? selectedFieldId = existing?.fieldId;
    int? selectedCropSeasonId = existing?.cropSeasonId;
    // Inventory linkage: when the expense category maps to a stocked
    // inventory category, the farmer can pick an item and enter the used
    // quantity — the amount auto-calculates and stock is deducted on save.
    int? selectedInventoryItemId;
    final usedQtyController = TextEditingController();
    String usedQtyUnit = 'item'; // 'item' or 'kg'
    final amountController = TextEditingController(
      text: existing == null ? '' : _paisaToRupeesText(existing.amountPaisa),
    );
    final descController = TextEditingController(
      text: existing?.description ?? '',
    );
    DateTime selectedDate =
        existing == null ? DateTime.now() : DateTime.parse(existing.date);
    // Double-tap guard: the save writes an expense (+ an activity when
    // crop-linked) — a second tap would create a full duplicate set.
    bool isSaving = false;

    showDialog(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (context, setState) {
            // Cascading pickers: Farm -> Field -> Crop season. All optional.
            final List<Field> fieldsForFarm =
                selectedFarmId == null
                    ? <Field>[]
                    : farmProvider.getFieldsForFarm(selectedFarmId!);
            final List<CropSeasonWithDetails> allSeasons = [
              ...cropProvider.activeCropSeasons,
              ...cropProvider.harvestedCropSeasons,
            ];
            final List<CropSeasonWithDetails> seasonsForField =
                selectedFieldId == null
                    ? <CropSeasonWithDetails>[]
                    : allSeasons
                        .where(
                          (d) => d.fields.any((f) => f.id == selectedFieldId),
                        )
                        .toList();

            return AlertDialog(
              title: Text(isEdit ? 'خرچے میں ترمیم کریں' : 'نیا خرچہ درج کریں'),
              content: Form(
                key: formKey,
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      DropdownButtonFormField<String>(
                        value: selectedCategory,
                        decoration: const InputDecoration(
                          labelText: 'خرچے کا زمرہ (Category)',
                          border: OutlineInputBorder(),
                        ),
                        items:
                            expenseProvider.expenseCategories.entries.map((e) {
                              return DropdownMenuItem<String>(
                                value: e.key,
                                child: Text(e.value),
                              );
                            }).toList(),
                        onChanged: (val) {
                          setState(() {
                            selectedCategory = val!;
                            // Reset inventory selection when category changes.
                            selectedInventoryItemId = null;
                            usedQtyController.clear();
                          });
                        },
                      ),
                      const SizedBox(height: 16),
                      // Inventory linkage: if this expense category draws from
                      // stock, let the farmer pick an item and enter the used
                      // quantity. The amount auto-calculates from the item's
                      // recorded cost; stock is deducted on save.
                      Builder(
                        builder: (context) {
                          final invCat =
                              _expenseToInventoryCategory[selectedCategory];
                          // Edit mode never touches stock: it was deducted
                          // when the expense was created.
                          if (invCat == null || isEdit) {
                            return const SizedBox.shrink();
                          }
                          final items =
                              inventoryProvider.inventoryList
                                  .where(
                                    (it) =>
                                        it.category == invCat && it.quantity > 0,
                                  )
                                  .toList();
                          if (items.isEmpty) {
                            return const SizedBox.shrink();
                          }
                          Inventory? selectedItem;
                          for (final it in items) {
                            if (it.id == selectedInventoryItemId) {
                              selectedItem = it;
                              break;
                            }
                          }
                          return Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              DropdownButtonFormField<int?>(
                                value: selectedInventoryItemId,
                                decoration: const InputDecoration(
                                  labelText:
                                      'اسٹاک سے شے منتخب کریں (آپشنل)',
                                  border: OutlineInputBorder(),
                                ),
                                items: [
                                  const DropdownMenuItem<int?>(
                                    value: null,
                                    child: Text('اسٹاک استعمال نہیں کرنا'),
                                  ),
                                  ...items.map((it) {
                                    return DropdownMenuItem<int?>(
                                      value: it.id,
                                      child: Text(
                                        '${it.name} — دستیاب: ${it.quantity} ${it.unit}',
                                      ),
                                    );
                                  }),
                                ],
                                onChanged: (val) {
                                  setState(() {
                                    selectedInventoryItemId = val;
                                    usedQtyController.clear();
                                    usedQtyUnit = 'item';
                                  });
                                },
                              ),
                              if (selectedItem != null) ...[
                                const SizedBox(height: 12),
                                Row(
                                  children: [
                                    Expanded(
                                      flex: 2,
                                      child: TextFormField(
                                        controller: usedQtyController,
                                        keyboardType:
                                            const TextInputType.numberWithOptions(
                                              decimal: true,
                                            ),
                                        decoration: InputDecoration(
                                          labelText:
                                              'استعمال شدہ مقدار (${usedQtyUnit == 'kg' ? 'کلو' : selectedItem.unit})',
                                          border: const OutlineInputBorder(),
                                        ),
                                        validator: (value) {
                                          if (value == null ||
                                              value.trim().isEmpty) {
                                            return null;
                                          }
                                          final q = double.tryParse(
                                            value.trim(),
                                          );
                                          if (q == null || q <= 0) {
                                            return 'صحیح مقدار لکھیں';
                                          }
                                          return null;
                                        },
                                        onChanged: (_) {
                                          _recalcAmountFromInventory(
                                            selectedItem,
                                            usedQtyController,
                                            usedQtyUnit,
                                            amountController,
                                          );
                                        },
                                      ),
                                    ),
                                    const SizedBox(width: 8),
                                    if (selectedItem.weightPerUnitKg != null)
                                      Expanded(
                                        child: DropdownButtonFormField<String>(
                                          value: usedQtyUnit,
                                          decoration: const InputDecoration(
                                            labelText: 'اکائی',
                                            border: OutlineInputBorder(),
                                          ),
                                          items: const [
                                            DropdownMenuItem(
                                              value: 'item',
                                              child: Text('پیکٹ/بوری'),
                                            ),
                                            DropdownMenuItem(
                                              value: 'kg',
                                              child: Text('کلو گرام'),
                                            ),
                                          ],
                                          onChanged: (val) {
                                            setState(() {
                                              usedQtyUnit = val ?? 'item';
                                              _recalcAmountFromInventory(
                                                selectedItem,
                                                usedQtyController,
                                                usedQtyUnit,
                                                amountController,
                                              );
                                            });
                                          },
                                        ),
                                      ),
                                  ],
                                ),
                                const SizedBox(height: 8),
                                Text(
                                  'فی ${selectedItem.unit} قیمت: ${_formatPaisa(selectedItem.costPerUnitPaisa)}',
                                  style: const TextStyle(
                                    fontSize: 12,
                                    color: Colors.grey,
                                  ),
                                ),
                              ],
                              const SizedBox(height: 16),
                            ],
                          );
                        },
                      ),
                      // 1. Farm picker (optional)
                      DropdownButtonFormField<int?>(
                        value: selectedFarmId,
                        decoration: const InputDecoration(
                          labelText: 'فارم منتخب کریں (آپشنل)',
                          border: OutlineInputBorder(),
                        ),
                        items: [
                          const DropdownMenuItem<int?>(
                            value: null,
                            child: Text('متفرق / غیر فصلاتی خرچہ'),
                          ),
                          ...farmProvider.farms.map((farm) {
                            return DropdownMenuItem<int?>(
                              value: farm.id,
                              child: Text(farm.name),
                            );
                          }),
                        ],
                        onChanged: (val) {
                          setState(() {
                            selectedFarmId = val;
                            selectedFieldId = null;
                            selectedCropSeasonId = null;
                          });
                        },
                      ),
                      const SizedBox(height: 16),
                      // 2. Field picker (optional; needs a farm first)
                      DropdownButtonFormField<int?>(
                        value: selectedFieldId,
                        decoration: const InputDecoration(
                          labelText: 'کھیت منتخب کریں (آپشنل)',
                          border: OutlineInputBorder(),
                        ),
                        items: [
                          const DropdownMenuItem<int?>(
                            value: null,
                            child: Text('پورے فارم کا خرچہ'),
                          ),
                          ...fieldsForFarm.map((field) {
                            return DropdownMenuItem<int?>(
                              value: field.id,
                              child: Text(field.name),
                            );
                          }),
                        ],
                        onChanged:
                            selectedFarmId == null
                                ? null
                                : (val) {
                                  setState(() {
                                    selectedFieldId = val;
                                    selectedCropSeasonId = null;
                                  });
                                },
                      ),
                      const SizedBox(height: 16),
                      // 3. Crop season picker (optional; needs a field first)
                      DropdownButtonFormField<int?>(
                        value: selectedCropSeasonId,
                        decoration: const InputDecoration(
                          labelText: 'فصل منتخب کریں (آپشنل)',
                          border: OutlineInputBorder(),
                        ),
                        items: [
                          const DropdownMenuItem<int?>(
                            value: null,
                            child: Text('فصل سے غیر منسلک'),
                          ),
                          ...seasonsForField.map((details) {
                            final season = details.cropSeason;
                            final nameUrdu =
                                cropProvider.predefinedCrops[season.cropName] ??
                                season.cropName;
                            return DropdownMenuItem<int?>(
                              value: season.id,
                              child: Text('$nameUrdu (${season.status})'),
                            );
                          }),
                        ],
                        onChanged:
                            selectedFieldId == null
                                ? null
                                : (val) {
                                  setState(() {
                                    selectedCropSeasonId = val;
                                  });
                                },
                      ),
                      const SizedBox(height: 16),
                      TextFormField(
                        controller: amountController,
                        keyboardType: TextInputType.number,
                        decoration: const InputDecoration(
                          labelText: 'خرچے کی رقم (روپے)',
                          border: OutlineInputBorder(),
                        ),
                        validator:
                            (value) =>
                                FieldValidators.money(value),
                      ),
                      const SizedBox(height: 16),
                      TextFormField(
                        controller: descController,
                        decoration: const InputDecoration(
                          labelText: 'تفصیل (مثال: ٹھیکے کی پہلی قسط)',
                          border: OutlineInputBorder(),
                        ),
                      ),
                      const SizedBox(height: 16),
                      ListTile(
                        title: Text(
                          'تاریخ: ${DateFormat('yyyy-MM-dd').format(selectedDate)}',
                        ),
                        trailing: const Icon(Icons.calendar_today),
                        onTap: () async {
                          final date = await showDatePicker(
                            context: context,
                            initialDate: selectedDate,
                            firstDate: DateTime(2020),
                            lastDate: DateTime(2030),
                          );
                          if (date != null) {
                            setState(() {
                              selectedDate = date;
                            });
                          }
                        },
                      ),
                    ],
                  ),
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(ctx),
                  child: const Text(Strings.cancel),
                ),
                ElevatedButton(
                  onPressed: () async {
                    if (isSaving) return;
                    setState(() => isSaving = true);
                    try {
                      if (formKey.currentState!.validate()) {
                      int amountPaisa;
                      try {
                        amountPaisa = Money.parse(amountController.text).paisa;
                      } on MoneyParseException catch (e) {
                        if (context.mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text(e.message),
                              backgroundColor: Colors.red,
                            ),
                          );
                        }
                        return;
                      }
                      final String categoryUrdu =
                          expenseProvider.expenseCategories[selectedCategory] ??
                          selectedCategory;
                      if (isEdit) {
                        // Edit path: update only the expense row. Inventory
                        // stock was deducted at creation time and any linked
                        // activity keeps its original reference — neither is
                        // touched here.
                        await expenseProvider.updateExpense(
                          id: existing!.id!,
                          category: selectedCategory,
                          amountPaisa: amountPaisa,
                          date: selectedDate.toIso8601String(),
                          description:
                              descController.text.isEmpty
                                  ? null
                                  : descController.text,
                          farmId: selectedFarmId,
                          fieldId: selectedFieldId,
                          cropSeasonId: selectedCropSeasonId,
                        );
                      } else {
                      // Resolve the linked inventory item, if any, and validate
                      // stock BEFORE writing anything.
                      Inventory? usedItem;
                      double usedQtyInItemUnits = 0;
                      if (selectedInventoryItemId != null) {
                        for (final it in inventoryProvider.inventoryList) {
                          if (it.id == selectedInventoryItemId) {
                            usedItem = it;
                            break;
                          }
                        }
                        final rawQty = double.tryParse(
                          usedQtyController.text.trim(),
                        );
                        if (usedItem != null &&
                            rawQty != null &&
                            rawQty > 0) {
                          usedQtyInItemUnits = rawQty;
                          if (usedQtyUnit == 'kg' &&
                              usedItem.weightPerUnitKg != null &&
                              usedItem.weightPerUnitKg! > 0) {
                            usedQtyInItemUnits =
                                rawQty / usedItem.weightPerUnitKg!;
                          }
                          if (usedQtyInItemUnits > usedItem.quantity) {
                            if (context.mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                  content: Text(
                                    'اسٹاک ناکافی ہے — دستیاب: ${usedItem.quantity} ${usedItem.unit}',
                                  ),
                                  backgroundColor: Colors.red,
                                ),
                              );
                            }
                            return;
                          }
                        } else {
                          // Item picked but no usable quantity: treat as no
                          // linkage rather than blocking the expense.
                          usedItem = null;
                        }
                      }
                      final String finalDesc =
                          descController.text.isNotEmpty
                              ? descController.text
                              : usedItem != null
                              ? '${usedItem.name} ${usedQtyController.text.trim()} ${usedQtyUnit == 'kg' ? 'کلو' : usedItem.unit} — $categoryUrdu'
                              : 'خرچہ برائے $categoryUrdu';

                      // 1. Add general expense entry to SQL table
                      final int expenseId = await expenseProvider.addExpense(
                        category: selectedCategory,
                        amountPaisa: amountPaisa,
                        date: selectedDate.toIso8601String(),
                        description: finalDesc,
                        farmId: selectedFarmId,
                        fieldId: selectedFieldId,
                        cropSeasonId: selectedCropSeasonId,
                      );

                      // 1b. Deduct the used quantity from inventory stock.
                      if (usedItem != null && usedQtyInItemUnits > 0) {
                        await inventoryProvider.recordUsage(
                          itemId: usedItem.id!,
                          quantity: usedQtyInItemUnits,
                          date: selectedDate.toIso8601String(),
                          notes: 'خرچہ #$expenseId: $finalDesc',
                        );
                      }

                      // 2. If linked to a crop, automatically create a matching activity
                      if (selectedCropSeasonId != null) {
                        await activityProvider.addActivity(
                          cropSeasonId: selectedCropSeasonId!,
                          activityType: 'دیگر سرگرمی / خرچہ',
                          date: selectedDate.toIso8601String(),
                          details: '$finalDesc ($categoryUrdu)',
                          expenseId: expenseId,
                        );
                      }
                      } // end else (add path)

                      if (context.mounted) {
                        Navigator.pop(ctx);
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text(
                              isEdit
                                  ? 'خرچہ کامیابی سے اپ ڈیٹ ہو گیا!'
                                  : 'خرچہ کامیابی سے محفوظ ہو گیا!',
                            ),
                          ),
                        );
                      }
                    }
                    } catch (e) {
                      // SEC1: the add-path writes run in sequence — if
                      // recordUsage or addActivity throws AFTER the expense
                      // row is already committed, the raw exception must
                      // never reach the farmer, and the dialog must show an
                      // honest message: re-tapping Save blindly would
                      // duplicate the expense, so the farmer must check the
                      // list first to see what actually got saved.
                      // (Edit mode is a single atomic updateExpense, so
                      // retry is safe there — the same honest message
                      // still applies.)
                      // Input is preserved: the dialog stays open.
                      if (ctx.mounted) {
                        final detail =
                            e is InventoryException
                                ? e.message
                                : friendlyErrorMessage(e);
                        ScaffoldMessenger.of(ctx).showSnackBar(
                          SnackBar(
                            content: Text(
                              '$detail دوبارہ محفوظ کرنے سے پہلے خرچے کی '
                              'فہرست دیکھ لیں۔',
                              style: const TextStyle(fontSize: 16),
                            ),
                            backgroundColor: Colors.red,
                          ),
                        );
                      }
                    } finally {
                      // The dialog is popped on success — only reset the
                      // guard while it is still in the tree.
                      if (ctx.mounted) setState(() => isSaving = false);
                    }
                  },
                  child: const Text(Strings.save),
                ),
              ],
            );
          },
        );
      },
    );
  }

  void _confirmDeleteExpense(BuildContext context, Expense exp) {
    // S19: harvest/theka/ushr mirrors are created automatically by other
    // screens — deleting one can orphan its source record.
    final isSystemLinked = _systemLinkedCategories.contains(exp.category);
    showDialog(
      context: context,
      builder:
          (ctx) => AlertDialog(
            title: const Text('خرچہ حذف کریں؟'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('کیا آپ واقعی یہ خرچہ حذف کرنا چاہتے ہیں؟'),
                const SizedBox(height: 8),
                // S18: expense deletes are soft deletes — say so instead of
                // implying the record is gone forever.
                const Text(
                  'یہ خرچہ کوڑے دان (ریسائیکل بن) میں چلا جائے گا — ضرورت ہو تو وہاں سے بحال کیا جا سکتا ہے۔',
                  style: TextStyle(fontSize: 13, color: Colors.grey),
                ),
                if (isSystemLinked) ...[
                  const SizedBox(height: 8),
                  const Text(
                    'خبردار: یہ خرچہ کسی خودکار ریکارڈ (کٹائی، ٹھیکہ یا عشر) سے جڑا ہو سکتا ہے۔ رقم درست کرنے کے لیے حذف کرنے کے بجائے ترمیم کا استعمال کریں۔',
                    style: TextStyle(
                      fontSize: 13,
                      color: Colors.red,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text(Strings.cancel),
              ),
              ElevatedButton(
                style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
                onPressed: () {
                  Provider.of<ExpenseProvider>(
                    context,
                    listen: false,
                  ).deleteExpense(exp.id!);
                  Navigator.pop(ctx);
                },
                child: const Text(
                  Strings.delete,
                  style: TextStyle(color: Colors.white),
                ),
              ),
            ],
          ),
    );
  }
}
