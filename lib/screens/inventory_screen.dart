import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../widgets/digit_text.dart';
import '../providers/inventory_provider.dart';
import '../models/models.dart';
import '../services/unit_converter.dart';
import '../services/unit_display.dart';
import '../services/money.dart';
import '../services/quantity.dart';
import '../widgets/empty_state_widget.dart';
import '../l10n/strings.dart';

class InventoryScreen extends StatefulWidget {
  const InventoryScreen({super.key});

  @override
  State<InventoryScreen> createState() => _InventoryScreenState();
}

class _InventoryScreenState extends State<InventoryScreen> {
  String _selectedCategoryFilter = 'All'; // 'All', 'Fertilizer', 'Seed', 'Spray', 'Medicine', 'Diesel', 'Other'

  // Categories map for translation
  final Map<String, String> _categories = {
    'Fertilizer': 'کھاد (Fertilizer)',
    'Seed': 'بیج (Seed)',
    'Spray': 'سپرے (Spray)',
    'Medicine': 'فصل کی دوا (Medicine)',
    'Diesel': 'ڈیزل (Diesel)',
    'Other': 'دیگر اشیاء (Other)',
  };

  // Predefined Units
  final List<String> _units = UnitDisplay.allUnits;

  @override
  Widget build(BuildContext context) {
    final inventoryProvider = Provider.of<InventoryProvider>(context);

    // 1. Calculate Total Stock Value (integer paisa)
    final int totalStockValuePaisa = inventoryProvider.inventoryList.fold<int>(
      0,
      (sum, item) => sum + (item.quantity * item.costPerUnitPaisa).round(),
    );

    // 2. Filter Stock List
    final filteredStock = inventoryProvider.inventoryList.where((item) {
      if (_selectedCategoryFilter == 'All') return true;
      return item.category == _selectedCategoryFilter;
    }).toList();

    return Scaffold(
      appBar: AppBar(
        title: const Text('گودام کا اسٹاک'),
        actions: [
          IconButton(
            icon: const Icon(Icons.add_box),
            tooltip: 'نیا اسٹاک درج کریں',
            onPressed: () => _showAddStockDialog(context),
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: () async {
          await inventoryProvider.fetchInventory();
        },
        child: Column(
          children: [
          // Total Stock Value Summary Card
          Container(
            width: double.infinity,
            margin: const EdgeInsets.all(16),
            padding: const EdgeInsets.symmetric(vertical: 24, horizontal: 16),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [Colors.blueGrey.shade700, Colors.blueGrey.shade500],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(20),
              boxShadow: [
                BoxShadow(
                  color: Colors.blueGrey.withValues(alpha: 0.3),
                  blurRadius: 10,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: Column(
              children: [
                const Text(
                  'گودام کے اسٹاک کی کل مالیت',
                  style: TextStyle(
                    color: Colors.white70,
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    fontFamily: 'Jameel Noori Nastaleeq',
                  ),
                ),
                const SizedBox(height: 8),
                DigitText(Money(totalStockValuePaisa).format(),
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 36,
                    fontWeight: FontWeight.bold,
                    fontFamily: 'Jameel Noori Nastaleeq',
                  ),
                ),
              ],
            ),
          ),

          // Filters row
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16.0),
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              physics: const BouncingScrollPhysics(),
              child: Row(
                children: [
                  _buildFilterChip('All', 'تمام اشیاء'),
                  const SizedBox(width: 8),
                  _buildFilterChip('Fertilizer', 'کھاد'),
                  const SizedBox(width: 8),
                  _buildFilterChip('Seed', 'بیج'),
                  const SizedBox(width: 8),
                  _buildFilterChip('Spray', 'سپرے'),
                  const SizedBox(width: 8),
                  _buildFilterChip('Medicine', 'دوائی'),
                  const SizedBox(width: 8),
                  _buildFilterChip('Diesel', 'ڈیزل'),
                  const SizedBox(width: 8),
                  _buildFilterChip('Other', 'دیگر'),
                ],
              ),
            ),
          ),

          const SizedBox(height: 8),

          // List of inventory items
          Expanded(
            child: filteredStock.isEmpty
                ? SingleChildScrollView(
                    physics: const AlwaysScrollableScrollPhysics(),
                    child: SizedBox(
                      height: MediaQuery.of(context).size.height * 0.5,
                      child: const EmptyStateWidget(
                        message: 'کوئی اسٹاک موجود نہیں ہے',
                        subtitle: 'گودام میں سامان داخل کرنے کے لیے نیچے بٹن دبائیں',
                        fallbackIcon: Icons.store,
                        imageAsset: 'assets/images/wheat.png',
                      ),
                    ),
                  )
                : ListView.builder(
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    itemCount: filteredStock.length,
                    itemBuilder: (context, index) {
                      final item = filteredStock[index];
                      final catUrdu = _categories[item.category] ?? item.category;

                      // Low stock alert indicator
                      final bool isLowStock = item.quantity <= 2;
                      final bool isOutOfStock = item.quantity == 0;
                      Color stockColor = Colors.green;
                      String stockStatus = 'اسٹاک موجود ہے';
                      if (isOutOfStock) {
                        stockColor = Colors.red;
                        stockStatus = 'اسٹاک ختم!';
                      } else if (isLowStock) {
                        stockColor = Colors.orange;
                        stockStatus = 'اسٹاک کم ہے!';
                      }

                      return InkWell(
                        onTap: () => _showHistorySheet(context, item),
                        borderRadius: BorderRadius.circular(12),
                        child: Card(
                          margin: const EdgeInsets.only(bottom: 12),
                          child: Padding(
                            padding: const EdgeInsets.all(12.0),
                            child: Row(
                              children: [
                                CircleAvatar(
                                  radius: 24,
                                  backgroundColor: stockColor.withValues(alpha: 0.1),
                                  child: Icon(
                                    Icons.store,
                                    color: stockColor,
                                    size: 28,
                                  ),
                                ),
                                const SizedBox(width: 16),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        item.name,
                                        style: const TextStyle(
                                          fontWeight: FontWeight.bold,
                                          fontSize: 18,
                                          fontFamily: 'Jameel Noori Nastaleeq',
                                        ),
                                      ),
                                      Text(
                                        catUrdu,
                                        style: const TextStyle(
                                          fontSize: 13,
                                          color: Colors.grey,
                                          fontFamily: 'Jameel Noori Nastaleeq',
                                        ),
                                      ),
                                      const SizedBox(height: 4),
                                      Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                        decoration: BoxDecoration(
                                          color: stockColor.withValues(alpha: 0.1),
                                          borderRadius: BorderRadius.circular(6),
                                        ),
                                        child: Text(
                                          stockStatus,
                                          style: TextStyle(
                                            color: stockColor,
                                            fontSize: 12,
                                            fontWeight: FontWeight.bold,
                                            fontFamily: 'Jameel Noori Nastaleeq',
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                Column(
                                  crossAxisAlignment: CrossAxisAlignment.end,
                                  children: [
                                    Text(
                                      '${item.quantity.toStringAsFixed(1)} ${item.unit}',
                                      style: TextStyle(
                                        color: stockColor,
                                        fontWeight: FontWeight.bold,
                                        fontSize: 20,
                                        fontFamily: 'Jameel Noori Nastaleeq',
                                      ),
                                    ),
                                    Text(
                                      'شرح: ${Money(item.costPerUnitPaisa).format()}',
                                      style: const TextStyle(
                                        color: Colors.grey,
                                        fontSize: 12,
                                        fontFamily: 'Jameel Noori Nastaleeq',
                                      ),
                                    ),
                                    Text(
                                      'کل قیمت: ${Money((item.quantity * item.costPerUnitPaisa).round()).format()}',
                                      style: const TextStyle(
                                        fontWeight: FontWeight.bold,
                                        fontSize: 14,
                                        fontFamily: 'Jameel Noori Nastaleeq',
                                      ),
                                    ),
                                    Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        IconButton(
                                          icon: const Icon(Icons.history_outlined, color: Colors.teal, size: 20),
                                          tooltip: 'لین دین کی تاریخ',
                                          onPressed: () => _showHistorySheet(context, item),
                                        ),
                                        IconButton(
                                          icon: const Icon(Icons.edit_outlined, color: Colors.blueGrey, size: 20),
                                          onPressed: () => _showEditStockDialog(context, item),
                                        ),
                                        IconButton(
                                          icon: const Icon(Icons.delete_outline, color: Colors.grey, size: 20),
                                          onPressed: () => _confirmDeleteStock(context, item),
                                        ),
                                      ],
                                    ),
                                  ],
                                ),
                              ],
                            ),
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
        onPressed: () => _showAddStockDialog(context),
        icon: const Icon(Icons.add),
        label: const Text('نیا اسٹاک درج کریں'),
        backgroundColor: Colors.blueGrey.shade700,
        foregroundColor: Colors.white,
      ),
    );
  }

  Widget _buildFilterChip(String category, String label) {
    final isSelected = _selectedCategoryFilter == category;
    return ChoiceChip(
      label: Text(label),
      selected: isSelected,
      onSelected: (val) {
        if (val) {
          setState(() {
            _selectedCategoryFilter = category;
          });
        }
      },
      selectedColor: Colors.blueGrey.shade700,
      backgroundColor: Colors.white,
      labelStyle: TextStyle(
        fontFamily: 'Jameel Noori Nastaleeq',
        fontSize: 16,
        fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
        color: isSelected ? Colors.white : Colors.black87,
      ),
    );
  }

  void _showAddStockDialog(BuildContext context) {
    final inventoryProvider = Provider.of<InventoryProvider>(context, listen: false);
    final formKey = GlobalKey<FormState>();

    String selectedCategory = 'Fertilizer';
    final nameController = TextEditingController();
    final qtyController = TextEditingController();
    String selectedUnit = 'بوری';
    final priceController = TextEditingController();
    final weightController = TextEditingController();

    showDialog(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (context, setState) {
            return AlertDialog(
              title: const Text('نیا اسٹاک گودام میں شامل کریں'),
              content: Form(
                key: formKey,
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      DropdownButtonFormField<String>(
                        value: selectedCategory,
                        decoration: const InputDecoration(
                          labelText: 'اسٹاک کا زمرہ (Category)',
                          border: OutlineInputBorder(),
                        ),
                        items: _categories.entries.map((e) {
                          return DropdownMenuItem<String>(
                            value: e.key,
                            child: Text(e.value),
                          );
                        }).toList(),
                        onChanged: (val) {
                          setState(() {
                            selectedCategory = val!;
                            // Automatically update default unit based on category
                            if (selectedCategory == 'Fertilizer') {
                              selectedUnit = 'بوری';
                            } else if (selectedCategory == 'Seed') {
                              selectedUnit = 'کلوگرام';
                            } else if (selectedCategory == 'Spray') {
                              selectedUnit = 'بوتل';
                            } else if (selectedCategory == 'Medicine') {
                              selectedUnit = 'پیکٹ';
                            } else if (selectedCategory == 'Diesel') {
                              selectedUnit = 'لیٹر';
                            }
                          });
                        },
                      ),
                      const SizedBox(height: 16),
                      TextFormField(
                        controller: nameController,
                        decoration: const InputDecoration(
                          labelText: 'چیز کا نام (جیسے: یوریا کھاد، ڈی اے پی، بجائی بیج)',
                          border: OutlineInputBorder(),
                        ),
                        validator: (value) => value!.isEmpty ? Strings.nameRequired : null,
                      ),
                      const SizedBox(height: 16),
                      Row(
                        children: [
                          Expanded(
                            flex: 3,
                            child: TextFormField(
                              controller: qtyController,
                              keyboardType: TextInputType.number,
                              decoration: const InputDecoration(
                                labelText: 'مقدار (تعداد)',
                                border: OutlineInputBorder(),
                              ),
                              validator: (value) {
                                if (value!.isEmpty) return Strings.quantityRequired;
                                final qty = Quantity.tryParse(value);
                                if (qty == null) return 'صرف نمبر';
                                if (qty <= 0) return 'مقدار صفر سے زیادہ ہونی چاہیے';
                                return null;
                              },
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            flex: 2,
                            child: DropdownButtonFormField<String>(
                              value: selectedUnit,
                              decoration: const InputDecoration(
                                labelText: 'اکائی',
                                border: OutlineInputBorder(),
                              ),
                              items: _units.map((u) {
                                return DropdownMenuItem(value: u, child: Text(u));
                              }).toList(),
                              onChanged: (val) {
                                setState(() {
                                  selectedUnit = val!;
                                });
                              },
                            ),
                          ),
                        ],
                      ),
                      // Package units (bag/bottle/packet): optional per-package
                      // weight in kg — never assumed, needed for conversions.
                      if (UnitConverter.isPackageUnit(selectedUnit)) ...[
                        const SizedBox(height: 16),
                        TextFormField(
                          controller: weightController,
                          keyboardType: TextInputType.number,
                          decoration: const InputDecoration(
                            labelText: 'فی بوری/پیکٹ وزن (کلوگرام)',
                            border: OutlineInputBorder(),
                          ),
                          validator: (value) {
                            if (value == null || value.isEmpty) return null;
                            try {
                              Quantity.parsePositive(value);
                            } on QuantityParseException catch (e) {
                              return e.message;
                            }
                            return null;
                          },
                        ),
                      ],
                      const SizedBox(height: 16),
                      TextFormField(
                        controller: priceController,
                        keyboardType: TextInputType.number,
                        decoration: const InputDecoration(
                          labelText: 'فی اکائی قیمت (روپے)',
                          border: OutlineInputBorder(),
                        ),
                        validator: (value) {
                          if (value == null || value.isEmpty) return 'قیمت درج کریں';
                          try {
                            Money.parse(value);
                          } on MoneyParseException catch (e) {
                            return e.message;
                          }
                          return null;
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
                      final messenger = ScaffoldMessenger.of(context);
                      final navigator = Navigator.of(ctx);
                      final double? weight = weightController.text.isEmpty
                          ? null
                          : Quantity.parsePositive(weightController.text);
                      final int costPerUnitPaisa;
                      try {
                        costPerUnitPaisa = Money.parse(priceController.text).paisa;
                      } on MoneyParseException catch (e) {
                        messenger.showSnackBar(
                          SnackBar(
                            content: Text(e.message),
                            backgroundColor: Colors.red,
                          ),
                        );
                        return;
                      }
                      try {
                        await inventoryProvider.recordPurchase(
                          category: selectedCategory,
                          name: nameController.text,
                          unit: selectedUnit,
                          quantity: Quantity.parsePositive(qtyController.text),
                          costPerUnitPaisa: costPerUnitPaisa,
                          weightPerUnitKg: weight,
                        );
                      } on InventoryException catch (e) {
                        messenger.showSnackBar(
                          SnackBar(
                            content: Text(e.message),
                            backgroundColor: Colors.red,
                          ),
                        );
                        return;
                      }
                      navigator.pop();
                      messenger.showSnackBar(
                        const SnackBar(content: Text('اسٹاک گودام میں کامیابی سے شامل ہو گیا!')),
                      );
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

  void _confirmDeleteStock(BuildContext context, Inventory item) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('اسٹاک حذف کریں؟'),
        content: Text('کیا آپ واقعی گودام سے "${item.name}" کا ریکارڈ حذف کرنا چاہتے ہیں؟'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text(Strings.cancel),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () async {
              Navigator.pop(ctx);
              try {
                await Provider.of<InventoryProvider>(context, listen: false)
                    .deleteInventoryItem(item.id!);
                if (!context.mounted) return;
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('اسٹاک کامیابی سے حذف ہو گیا!')),
                );
              } on InventoryException catch (e) {
                if (!context.mounted) return;
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text(e.message)),
                );
              }
            },
            child: const Text(Strings.delete, style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }

  void _showHistorySheet(BuildContext context, Inventory item) {
    final inventoryProvider =
        Provider.of<InventoryProvider>(context, listen: false);
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => DraggableScrollableSheet(
        expand: false,
        builder: (ctx, scrollController) =>
            FutureBuilder<List<InventoryTransaction>>(
          future: inventoryProvider.getTransactions(item.id!),
          builder: (ctx, snapshot) {
            final txs = snapshot.data ?? const <InventoryTransaction>[];
            return Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    '${item.name} — لین دین کی تاریخ',
                    style: Theme.of(ctx).textTheme.titleLarge,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'موجودہ اسٹاک: ${item.quantity.toStringAsFixed(2)} ${item.unit}',
                    style: const TextStyle(color: Colors.grey),
                  ),
                  const SizedBox(height: 12),
                  Expanded(
                    child: snapshot.connectionState == ConnectionState.waiting
                        ? const Center(child: CircularProgressIndicator())
                        : txs.isEmpty
                            ? const Center(
                                child: Text('ابھی تک کوئی لین دین نہیں ہے'),
                              )
                            : ListView.builder(
                                controller: scrollController,
                                itemCount: txs.length,
                                itemBuilder: (ctx, i) {
                                  final tx = txs[i];
                                  final isIn = tx.quantity >= 0;
                                  final note =
                                      (tx.notes != null && tx.notes!.isNotEmpty)
                                          ? ' — ${tx.notes}'
                                          : '';
                                  return ListTile(
                                    leading: Icon(
                                      isIn
                                          ? Icons.add_circle
                                          : Icons.remove_circle,
                                      color: isIn ? Colors.green : Colors.red,
                                    ),
                                    title: Text(tx.typeUrdu),
                                    subtitle: Text(
                                      '${tx.date.length >= 10 ? tx.date.substring(0, 10) : tx.date}$note',
                                    ),
                                    trailing: Text(
                                      '${isIn ? '+' : ''}${tx.quantity.toStringAsFixed(2)} ${tx.unit}',
                                      style: TextStyle(
                                        fontWeight: FontWeight.bold,
                                        color:
                                            isIn ? Colors.green : Colors.red,
                                      ),
                                    ),
                                  );
                                },
                              ),
                  ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }

  void _showEditStockDialog(BuildContext context, Inventory item) {
    final inventoryProvider = Provider.of<InventoryProvider>(context, listen: false);
    final formKey = GlobalKey<FormState>();

    String selectedCategory = item.category;
    final nameController = TextEditingController(text: item.name);
    final qtyController = TextEditingController(text: item.quantity.toString());
    String selectedUnit = item.unit;
    final priceController = TextEditingController(text: (item.costPerUnitPaisa / 100).toString());
    final weightController = TextEditingController(
      text: item.weightPerUnitKg?.toString() ?? '',
    );

    showDialog(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (context, setState) {
            return AlertDialog(
              title: const Text('اسٹاک میں تبدیلی کریں'),
              content: Form(
                key: formKey,
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      DropdownButtonFormField<String>(
                        value: selectedCategory,
                        decoration: const InputDecoration(
                          labelText: 'اسٹاک کا زمرہ (Category)',
                          border: OutlineInputBorder(),
                        ),
                        items: _categories.entries.map((e) {
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
                      TextFormField(
                        controller: nameController,
                        decoration: const InputDecoration(
                          labelText: 'چیز کا نام',
                          border: OutlineInputBorder(),
                        ),
                        validator: (value) => value!.isEmpty ? Strings.nameRequired : null,
                      ),
                      const SizedBox(height: 16),
                      Row(
                        children: [
                          Expanded(
                            flex: 3,
                            child: TextFormField(
                              controller: qtyController,
                              keyboardType: TextInputType.number,
                              decoration: const InputDecoration(
                                labelText: 'مقدار (تعداد)',
                                border: OutlineInputBorder(),
                              ),
                              validator: (value) {
                                if (value!.isEmpty) return Strings.quantityRequired;
                                try {
                                  Quantity.parse(value);
                                } on QuantityParseException catch (e) {
                                  return e.message;
                                }
                                return null;
                              },
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            flex: 2,
                            child: DropdownButtonFormField<String>(
                              value: selectedUnit,
                              decoration: const InputDecoration(
                                labelText: 'اکائی',
                                border: OutlineInputBorder(),
                              ),
                              items: _units.map((u) {
                                return DropdownMenuItem(value: u, child: Text(u));
                              }).toList(),
                              onChanged: (val) {
                                setState(() {
                                  selectedUnit = val!;
                                });
                              },
                            ),
                          ),
                        ],
                      ),
                      if (UnitConverter.isPackageUnit(selectedUnit)) ...[
                        const SizedBox(height: 16),
                        TextFormField(
                          controller: weightController,
                          keyboardType: TextInputType.number,
                          decoration: const InputDecoration(
                            labelText: 'فی بوری/پیکٹ وزن (کلوگرام)',
                            border: OutlineInputBorder(),
                          ),
                          validator: (value) {
                            if (value == null || value.isEmpty) return null;
                            try {
                              Quantity.parsePositive(value);
                            } on QuantityParseException catch (e) {
                              return e.message;
                            }
                            return null;
                          },
                        ),
                      ],
                      const SizedBox(height: 16),
                      TextFormField(
                        controller: priceController,
                        keyboardType: TextInputType.number,
                        decoration: const InputDecoration(
                          labelText: 'فی اکائی قیمت (روپے)',
                          border: OutlineInputBorder(),
                        ),
                        validator: (value) {
                          if (value == null || value.isEmpty) return 'قیمت درج کریں';
                          try {
                            Money.parse(value);
                          } on MoneyParseException catch (e) {
                            return e.message;
                          }
                          return null;
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
                      final messenger = ScaffoldMessenger.of(context);
                      final navigator = Navigator.of(ctx);
                      final double newQty = Quantity.parsePositive(qtyController.text);
                      final double delta = newQty - item.quantity;
                      final double? weight = weightController.text.isEmpty
                          ? null
                          : Quantity.parsePositive(weightController.text);
                      final int costPerUnitPaisa;
                      try {
                        costPerUnitPaisa = Money.parse(priceController.text).paisa;
                      } on MoneyParseException catch (e) {
                        messenger.showSnackBar(
                          SnackBar(
                            content: Text(e.message),
                            backgroundColor: Colors.red,
                          ),
                        );
                        return;
                      }
                      try {
                        await inventoryProvider.updateItemDetails(
                          id: item.id!,
                          category: selectedCategory,
                          name: nameController.text,
                          unit: selectedUnit,
                          costPerUnitPaisa: costPerUnitPaisa,
                          weightPerUnitKg: weight,
                        );
                        // Quantity never overwrites silently: the difference
                        // is a ledger adjustment with a reason.
                        if (delta != 0) {
                          await inventoryProvider.recordAdjustment(
                            itemId: item.id!,
                            quantityDelta: delta,
                            reason:
                                'اسٹاک کی دستی تصحیح (${item.quantity.toStringAsFixed(1)} سے ${newQty.toStringAsFixed(1)} $selectedUnit)',
                          );
                        }
                      } on InventoryException catch (e) {
                        messenger.showSnackBar(
                          SnackBar(
                            content: Text(e.message),
                            backgroundColor: Colors.red,
                          ),
                        );
                        return;
                      }
                      navigator.pop();
                      messenger.showSnackBar(
                        const SnackBar(content: Text('اسٹاک میں تبدیلی کامیابی سے محفوظ ہو گئی!')),
                      );
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
}
