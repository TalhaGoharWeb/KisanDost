import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import '../widgets/digit_text.dart';
import '../providers/expense_provider.dart';
import '../providers/crop_provider.dart';
import '../providers/activity_provider.dart';
import '../providers/farm_provider.dart';
import '../models/models.dart';
import '../services/money.dart';
import '../widgets/empty_state_widget.dart';
import '../l10n/strings.dart';

class ExpensesScreen extends StatefulWidget {
  const ExpensesScreen({super.key});

  @override
  State<ExpensesScreen> createState() => _ExpensesScreenState();
}

class _ExpensesScreenState extends State<ExpensesScreen> {
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
                  style: TextStyle(color: Colors.white70, fontSize: 18, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 8),
                DigitText(Money(expenseProvider.totalExpensesPaisa).format(),
                  style: const TextStyle(color: Colors.white, fontSize: 36, fontWeight: FontWeight.bold),
                ),
              ],
            ),
          ),

          // 2. List of recorded expenses
          Expanded(
            child: expenseProvider.expenses.isEmpty
                ? SingleChildScrollView(
                    physics: const AlwaysScrollableScrollPhysics(),
                    child: SizedBox(
                      height: MediaQuery.of(context).size.height * 0.5,
                      child: const EmptyStateWidget(
                        message: 'کوئی خرچہ ریکارڈ نہیں ہے',
                        subtitle: 'نیا خرچہ درج کرنے کے لیے نیچے بٹن دبائیں',
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
                      final catUrdu = expenseProvider.expenseCategories[exp.category] ?? exp.category;

                      return Card(
                        margin: const EdgeInsets.only(bottom: 12),
                        child: ListTile(
                          leading: CircleAvatar(
                            backgroundColor: Colors.red.shade50,
                            child: const Icon(Icons.trending_down, color: Colors.red),
                          ),
                          title: Text(
                            catUrdu,
                            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
                          ),
                          subtitle: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              if (exp.description != null && exp.description!.isNotEmpty)
                                Text(exp.description!),
                              Text(
                                DateFormat('yyyy-MM-dd').format(DateTime.parse(exp.date)),
                                style: const TextStyle(fontSize: 12, color: Colors.grey),
                              ),
                            ],
                          ),
                          trailing: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              DigitText(Money(exp.amountPaisa).format(),
                                style: const TextStyle(
                                  color: Colors.red,
                                  fontWeight: FontWeight.bold,
                                  fontSize: 18,
                                ),
                              ),
                              const SizedBox(width: 8),
                              IconButton(
                                icon: const Icon(Icons.delete_outline, color: Colors.grey),
                                onPressed: () => _confirmDeleteExpense(context, exp.id!),
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

  void _showAddExpenseDialog(BuildContext context) {
    final expenseProvider = Provider.of<ExpenseProvider>(context, listen: false);
    final cropProvider = Provider.of<CropProvider>(context, listen: false);
    final activityProvider = Provider.of<ActivityProvider>(context, listen: false);
    final farmProvider = Provider.of<FarmProvider>(context, listen: false);
    final formKey = GlobalKey<FormState>();

    String selectedCategory = 'Miscellaneous';
    int? selectedFarmId;
    int? selectedFieldId;
    int? selectedCropSeasonId;
    final amountController = TextEditingController();
    final descController = TextEditingController();
    DateTime selectedDate = DateTime.now();

    showDialog(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (context, setState) {
            // Cascading pickers: Farm -> Field -> Crop season. All optional.
            final List<Field> fieldsForFarm = selectedFarmId == null
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
                        .where((d) =>
                            d.fields.any((f) => f.id == selectedFieldId))
                        .toList();

            return AlertDialog(
              title: const Text('نیا خرچہ درج کریں'),
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
                        items: expenseProvider.expenseCategories.entries.map((e) {
                          return DropdownMenuItem<String>(
                            value: e.key,
                            child: Text(e.value),
                          );
                        }).toList(),
                        onChanged: (val) {
                          setState(() {
                            selectedCategory = val!;
                          });
                        },
                      ),
                      const SizedBox(height: 16),
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
                        onChanged: selectedFarmId == null
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
                            final nameUrdu = cropProvider.predefinedCrops[season.cropName] ?? season.cropName;
                            return DropdownMenuItem<int?>(
                              value: season.id,
                              child: Text('$nameUrdu (${season.status})'),
                            );
                          }),
                        ],
                        onChanged: selectedFieldId == null
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
                        validator: (value) {
                          if (value!.isEmpty) return 'رقم درج کریں';
                          try {
                            Money.parse(value);
                          } on MoneyParseException catch (e) {
                            return e.message;
                          }
                          return null;
                        },
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
                        title: Text('تاریخ: ${DateFormat('yyyy-MM-dd').format(selectedDate)}'),
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
                      final String categoryUrdu = expenseProvider.expenseCategories[selectedCategory] ?? selectedCategory;
                      final String finalDesc = descController.text.isNotEmpty 
                          ? descController.text 
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

                      if (context.mounted) {
                        Navigator.pop(ctx);
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('خرچہ کامیابی سے محفوظ ہو گیا!')),
                        );
                      }
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

  void _confirmDeleteExpense(BuildContext context, int id) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('خرچہ حذف کریں؟'),
        content: const Text('کیا آپ واقعی یہ خرچہ حذف کرنا چاہتے ہیں؟'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text(Strings.cancel),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () {
              Provider.of<ExpenseProvider>(context, listen: false).deleteExpense(id);
              Navigator.pop(ctx);
            },
            child: const Text(Strings.delete, style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }
}
