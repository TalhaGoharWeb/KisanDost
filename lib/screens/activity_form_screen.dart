import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import '../providers/crop_provider.dart';
import '../providers/inventory_provider.dart';
import '../providers/activity_provider.dart';
import '../providers/expense_provider.dart';
import '../providers/harvest_provider.dart';
import '../providers/task_provider.dart';
import '../models/models.dart';
import '../services/money.dart';
import '../services/quantity.dart';
import '../services/unit_converter.dart';
import '../services/unit_display.dart';
import '../l10n/strings.dart';

class ActivityFormScreen extends StatefulWidget {
  final String activityTitle;
  final ActivityWithDetails? existingActivity;
  final bool duplicateMode;

  const ActivityFormScreen({
    super.key,
    required this.activityTitle,
    this.existingActivity,
    this.duplicateMode = false,
  });

  @override
  State<ActivityFormScreen> createState() => _ActivityFormScreenState();
}

class _ActivityFormScreenState extends State<ActivityFormScreen> {
  final _formKey = GlobalKey<FormState>();
  int? _selectedCropSeasonId;
  DateTime _selectedDate = DateTime.now();
  final _detailsController = TextEditingController();

  // Irrigation specific
  String _waterSource = 'نہر';
  final _hoursController = TextEditingController();
  final _waterCostController = TextEditingController();
  final _startUnitController = TextEditingController();
  final _endUnitController = TextEditingController();

  // Inventory specific (Fertilizer, Spray, Medicine, Diesel)
  String? _inventoryCategory;
  Inventory? _selectedInventoryItem;
  bool _directPurchase = false;
  final _itemNameController = TextEditingController();
  final _qtyController = TextEditingController();
  String _selectedUnit = 'بوری';
  final _priceController = TextEditingController();

  // Predefined Units
  final List<String> _units = UnitDisplay.allUnits;

  // Other activity specific
  final _genericCostController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _setInventoryCategory();
    _loadExistingValues();
  }

  void _setInventoryCategory() {
    if (widget.activityTitle == 'کھاد ڈالی') {
      _inventoryCategory = 'Fertilizer';
      _selectedUnit = 'بوری';
    } else if (widget.activityTitle == 'سپرے کیا') {
      _inventoryCategory = 'Spray';
      _selectedUnit = 'بوتل';
    } else if (widget.activityTitle == 'دوائی ڈالی') {
      _inventoryCategory = 'Medicine';
      _selectedUnit = 'پیکٹ';
    } else if (widget.activityTitle == 'ڈیزل استعمال') {
      _inventoryCategory = 'Diesel';
      _selectedUnit = 'لیٹر';
    }
  }

  void _loadExistingValues() {
    final existing = widget.existingActivity;
    if (existing == null) {
      return;
    }

    _selectedCropSeasonId = existing.activity.cropSeasonId;
    _selectedDate = DateTime.tryParse(existing.activity.date) ?? DateTime.now();
    _detailsController.text = existing.activity.details ?? '';

    if (existing.activity.inventoryCategory != null) {
      _inventoryCategory = existing.activity.inventoryCategory;
    }
    if (existing.activity.inventoryName != null) {
      _itemNameController.text = existing.activity.inventoryName!;
    }
    if (existing.activity.inventoryUnit != null) {
      _selectedUnit = existing.activity.inventoryUnit!;
    }
    if (existing.activity.inventoryQuantity != null) {
      _qtyController.text = existing.activity.inventoryQuantity!.toString();
    }
    // Restore the exact warehouse item so edit mode deducts/restores
    // against the same row (not a fuzzy name match).
    final int? itemId = existing.activity.inventoryItemId;
    if (itemId != null) {
      final inventoryProvider =
          Provider.of<InventoryProvider>(context, listen: false);
      for (final item in inventoryProvider.inventoryList) {
        if (item.id == itemId) {
          _selectedInventoryItem = item;
          break;
        }
      }
    }
    if (existing.expenseAmountPaisa != null) {
      final restored = Money(existing.expenseAmountPaisa!).format();
      _genericCostController.text = restored;
      _priceController.text = restored;
      _waterCostController.text = restored;
    }
  }

  @override
  Widget build(BuildContext context) {
    final cropProvider = Provider.of<CropProvider>(context);
    final inventoryProvider = Provider.of<InventoryProvider>(context);
    final activityProvider = Provider.of<ActivityProvider>(context);
    
    final activeSeasons = cropProvider.activeCropSeasons;

    // Filter inventory items matching the category
    final matchingInventoryItems = inventoryProvider.inventoryList
        .where((item) => item.category == _inventoryCategory)
        .toList();

    final hasSelectedItem = matchingInventoryItems.any((item) => item.id == _selectedInventoryItem?.id);
    final dropdownValue = hasSelectedItem ? _selectedInventoryItem?.id : null;

    return Scaffold(
      appBar: AppBar(title: Text(widget.activityTitle)),
      body: activeSeasons.isEmpty
          ? Center(
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(Icons.warning, size: 80, color: Colors.orange),
                    const SizedBox(height: 16),
                    const Text(
                      'کوئی فعال فصل موجود نہیں ہے!',
                      style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      'کام ریکارڈ کرنے سے پہلے "میری فصلیں" سیکشن میں جا کر فصل کاشت کریں۔',
                      style: TextStyle(fontSize: 18),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 16),
                    ElevatedButton(
                      onPressed: () => Navigator.pop(context),
                      child: const Text('واپس جائیں'),
                    ),
                  ],
                ),
              ),
            )
          : Padding(
              padding: const EdgeInsets.all(16.0),
              child: Form(
                key: _formKey,
                child: ListView(
                  children: [
                    DropdownButtonFormField<int>(
                      value: _selectedCropSeasonId ?? activeSeasons.first.cropSeason.id,
                      decoration: const InputDecoration(
                        labelText: Strings.selectCrop,
                        border: OutlineInputBorder(),
                      ),
                      items: activeSeasons.map((details) {
                        final season = details.cropSeason;
                        final nameUrdu = cropProvider.predefinedCrops[season.cropName] ?? season.cropName;
                        return DropdownMenuItem<int>(
                          value: season.id,
                          child: Text('${details.farmDisplayName} - ${details.fieldDisplayName} ($nameUrdu - ${season.variety})'),
                        );
                      }).toList(),
                      onChanged: (val) {
                        setState(() {
                          _selectedCropSeasonId = val;
                        });
                      },
                    ),
                    const SizedBox(height: 16),
                    ListTile(
                      title: Text('کام کی تاریخ: ${DateFormat('yyyy-MM-dd').format(_selectedDate)}'),
                      trailing: const Icon(Icons.calendar_today),
                      onTap: () async {
                        final date = await showDatePicker(
                          context: context,
                          initialDate: _selectedDate,
                          firstDate: DateTime(2020),
                          lastDate: DateTime(2030),
                        );
                        if (date != null) {
                          setState(() {
                            _selectedDate = date;
                          });
                        }
                      },
                    ),
                    const Divider(height: 32),

                    // 1. Irrigation Water
                    if (widget.activityTitle == 'پانی لگایا') ...[
                      DropdownButtonFormField<String>(
                        value: _waterSource,
                        decoration: const InputDecoration(
                          labelText: 'پانی کا ذریعہ',
                          border: OutlineInputBorder(),
                        ),
                        items: const [
                          DropdownMenuItem(value: 'نہر', child: Text('نہر (Canal)')),
                          DropdownMenuItem(value: 'ٹیوب ویل', child: Text('ٹیوب ویل (Tube Well)')),
                          DropdownMenuItem(value: 'بورنگ', child: Text('بور کا پانی (Bore)')),
                        ],
                        onChanged: (val) {
                          setState(() {
                            _waterSource = val!;
                          });
                        },
                      ),
                      const SizedBox(height: 16),
                      TextFormField(
                        controller: _hoursController,
                        keyboardType: TextInputType.number,
                        decoration: const InputDecoration(
                          labelText: 'کتنے گھنٹے چلایا؟',
                          border: OutlineInputBorder(),
                        ),
                        validator: (value) => value!.isEmpty ? 'براہ کرم گھنٹے درج کریں' : null,
                      ),
                      const SizedBox(height: 16),
                      if (_waterSource != 'نہر') ...[
                        TextFormField(
                          controller: _waterCostController,
                          keyboardType: TextInputType.number,
                          decoration: const InputDecoration(
                            labelText: 'ڈیزل / بجلی کا خرچہ (روپے)',
                            border: OutlineInputBorder(),
                          ),
                          validator: (value) => value!.isEmpty ? 'خرچہ درج کریں' : null,
                        ),
                        const SizedBox(height: 16),
                      ],
                      if (_waterSource == 'ٹیوب ویل' || _waterSource == 'بورنگ') ...[
                        Row(
                          children: [
                            Expanded(
                              child: TextFormField(
                                controller: _startUnitController,
                                keyboardType: TextInputType.number,
                                decoration: const InputDecoration(
                                  labelText: 'شروع کے یونٹ (Start Unit)',
                                  border: OutlineInputBorder(),
                                ),
                                validator: (value) {
                                  if (value != null && value.isNotEmpty) {
                                    try {
                                      Quantity.parse(value);
                                    } on QuantityParseException catch (e) {
                                      return e.message;
                                    }
                                  }
                                  return null;
                                },
                                onChanged: (_) => setState(() {}),
                              ),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: TextFormField(
                                controller: _endUnitController,
                                keyboardType: TextInputType.number,
                                decoration: const InputDecoration(
                                  labelText: 'آخری یونٹ (End Unit)',
                                  border: OutlineInputBorder(),
                                ),
                                validator: (value) {
                                  final startVal = Quantity.tryParse(_startUnitController.text);
                                  if (startVal != null) {
                                    if (value == null || value.isEmpty) {
                                      return 'آخری یونٹ درج کریں';
                                    }
                                    final endVal = Quantity.tryParse(value);
                                    if (endVal == null) {
                                      return 'صرف نمبر درج کریں';
                                    }
                                    if (endVal < startVal) {
                                      return 'آخری یونٹ شروع کے یونٹ سے زیادہ یا برابر ہونا چاہیے';
                                    }
                                  }
                                  return null;
                                },
                                onChanged: (_) => setState(() {}),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 16),
                        () {
                          final start = Quantity.tryParse(_startUnitController.text);
                          final end = Quantity.tryParse(_endUnitController.text);
                          if (start != null && end != null && end >= start) {
                            final double consumed = end - start;
                            return Container(
                              margin: const EdgeInsets.only(bottom: 16),
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(
                                color: Colors.green.shade50,
                                borderRadius: BorderRadius.circular(8),
                                border: Border.all(color: Colors.green.shade200),
                              ),
                              child: Text(
                                'کل استعمال شدہ یونٹ: ${consumed.toStringAsFixed(1)} یونٹس',
                                style: TextStyle(fontWeight: FontWeight.bold, color: Colors.green.shade800, fontSize: 16),
                                textAlign: TextAlign.center,
                              ),
                            );
                          }
                          return const SizedBox.shrink();
                        }(),
                      ],
                    ]

                    // 2. Inventory Items (Fertilizer, Spray, Medicine, Diesel)
                    else if (_inventoryCategory != null) ...[
                      if (matchingInventoryItems.isNotEmpty) ...[
                        CheckboxListTile(
                          title: const Text('نیا خرید کر ڈائریکٹ ڈالیں؟'),
                          value: _directPurchase,
                          onChanged: (val) {
                            setState(() {
                              _directPurchase = val ?? false;
                              _selectedInventoryItem = null;
                            });
                          },
                        ),
                        const SizedBox(height: 8),
                      ],
                      if (!_directPurchase && matchingInventoryItems.isNotEmpty) ...[
                        DropdownButtonFormField<int>(
                          value: dropdownValue,
                          decoration: const InputDecoration(
                            labelText: 'گودام سے آئٹم منتخب کریں',
                            border: OutlineInputBorder(),
                          ),
                          items: matchingInventoryItems.map((item) {
                            return DropdownMenuItem<int>(
                              value: item.id!,
                              child: Text('${item.name} (${item.quantity} ${item.unit} گودام میں ہے)'),
                            );
                          }).toList(),
                          onChanged: (val) {
                            setState(() {
                              _selectedInventoryItem = matchingInventoryItems.firstWhere((item) => item.id == val);
                              _selectedUnit = _selectedInventoryItem!.unit;
                            });
                          },
                          validator: (value) => value == null ? 'آئٹم منتخب کریں' : null,
                        ),
                        const SizedBox(height: 16),
                      ] else ...[
                        TextFormField(
                          controller: _itemNameController,
                          decoration: InputDecoration(
                            labelText: '${widget.activityTitle.replaceAll("ڈالی", "").replaceAll("کیا", "")} کا نام لکھیں',
                            border: const OutlineInputBorder(),
                          ),
                          validator: (value) => value!.isEmpty ? Strings.nameRequired : null,
                        ),
                        const SizedBox(height: 16),
                        TextFormField(
                          controller: _priceController,
                          keyboardType: TextInputType.number,
                          decoration: const InputDecoration(
                            labelText: 'قیمت خرید (روپے)',
                            border: OutlineInputBorder(),
                          ),
                          validator: (value) {
                            if (value!.isEmpty) return 'قیمت درج کریں';
                            try {
                              Money.parse(value);
                            } on MoneyParseException catch (e) {
                              return e.message;
                            }
                            return null;
                          },
                        ),
                        const SizedBox(height: 16),
                      ],
                      Row(
                        children: [
                          Expanded(
                            flex: 3,
                            child: TextFormField(
                              controller: _qtyController,
                              keyboardType: TextInputType.number,
                              decoration: const InputDecoration(
                                  labelText: 'کتنی مقدار استعمال کی؟',
                                border: OutlineInputBorder(),
                              ),
                              validator: (value) {
                                if (value!.isEmpty) return Strings.quantityRequired;
                                final double qty;
                                try {
                                  qty = Quantity.parsePositive(value);
                                } on QuantityParseException catch (e) {
                                  return e.message;
                                }
                                if (!_directPurchase && _selectedInventoryItem != null) {
                                  try {
                                    final double convertedQty = UnitConverter.convert(
                                      qty,
                                      _selectedUnit,
                                      _selectedInventoryItem!.unit,
                                      weightPerUnitKg: _selectedInventoryItem!.weightPerUnitKg,
                                    );
                                    if (convertedQty > _selectedInventoryItem!.quantity) {
                                      return 'گودام میں اتنی مقدار دستیاب نہیں ہے!';
                                    }
                                  } on UnitConversionException catch (e) {
                                    return e.message;
                                  }
                                }
                                return null;
                              },
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            flex: 2,
                            child: DropdownButtonFormField<String>(
                              value: _selectedUnit,
                              decoration: const InputDecoration(
                                labelText: 'اکائی',
                                border: OutlineInputBorder(),
                              ),
                              items: _units.map((u) {
                                return DropdownMenuItem(value: u, child: Text(u));
                              }).toList(),
                              onChanged: (val) {
                                setState(() {
                                  _selectedUnit = val!;
                                });
                              },
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),
                    ]

                    // 3. Labor Activity
                    else if (widget.activityTitle == 'مزدور لگائے') ...[
                      TextFormField(
                        controller: _qtyController,
                        keyboardType: TextInputType.number,
                        decoration: const InputDecoration(
                          labelText: 'کتنے مزدور کام پر لگائے؟',
                          border: OutlineInputBorder(),
                        ),
                        validator: (value) => value!.isEmpty ? 'مزدوروں کی تعداد درج کریں' : null,
                      ),
                      const SizedBox(height: 16),
                      TextFormField(
                        controller: _genericCostController,
                        keyboardType: TextInputType.number,
                        decoration: const InputDecoration(
                          labelText: 'مزدوروں کی کل اجرت (روپے)',
                          border: OutlineInputBorder(),
                        ),
                        validator: (value) => value!.isEmpty ? 'اجرت درج کریں' : null,
                      ),
                      const SizedBox(height: 16),
                    ]

                    // 4. Machinery Activity
                    else if (widget.activityTitle == 'مشینری کا استعمال') ...[
                      TextFormField(
                        controller: _itemNameController,
                        decoration: const InputDecoration(
                          labelText: 'مشینری کا نام (ٹریکٹر، تھریشر، وغیرہ)',
                          border: OutlineInputBorder(),
                        ),
                        validator: (value) => value!.isEmpty ? 'مشینری کا نام درج کریں' : null,
                      ),
                      const SizedBox(height: 16),
                      TextFormField(
                        controller: _genericCostController,
                        keyboardType: TextInputType.number,
                        decoration: const InputDecoration(
                          labelText: 'کرایہ / ڈیزل کا خرچہ (روپے)',
                          border: OutlineInputBorder(),
                        ),
                        validator: (value) => value!.isEmpty ? 'خرچہ درج کریں' : null,
                      ),
                      const SizedBox(height: 16),
                    ]

                    // 5. Generic Activity with Expense
                    else ...[
                      TextFormField(
                        controller: _genericCostController,
                        keyboardType: TextInputType.number,
                        decoration: const InputDecoration(
                          labelText: 'اگر کوئی خرچہ ہوا تو لکھیں (روپے)',
                          border: OutlineInputBorder(),
                        ),
                      ),
                      const SizedBox(height: 16),
                    ],

                    TextFormField(
                      controller: _detailsController,
                      maxLines: 3,
                      decoration: const InputDecoration(
                        labelText: 'اضافی تفصیل یا نوٹ (آپشنل)',
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 32),
                    ElevatedButton(
                      onPressed: () async {
                        if (_formKey.currentState!.validate()) {
                          final navigator = Navigator.of(context);
                          final messenger = ScaffoldMessenger.of(context);
                          final expenseProvider = Provider.of<ExpenseProvider>(context, listen: false);
                          final harvestProvider = Provider.of<HarvestProvider>(context, listen: false);
                          final taskProvider = Provider.of<TaskProvider>(context, listen: false);
                          final int targetCropSeasonId = _selectedCropSeasonId ?? activeSeasons.first.cropSeason.id!;
                          
                          // Smart Automation logic variables
                          int? finalExpenseAmountPaisa;
                          String? finalExpenseCategory = widget.activityTitle;
                          String? inventoryCategory;
                          String? inventoryName;
                          String? inventoryUnit;
                          double? inventoryQty;
                          int? inventoryItemId;

                          // 1. Water calculations
                          if (widget.activityTitle == 'پانی لگایا') {
                            finalExpenseCategory = 'Water';
                            if (_waterSource != 'نہر') {
                              try {
                                finalExpenseAmountPaisa =
                                    Money.parse(_waterCostController.text).paisa;
                              } on MoneyParseException catch (e) {
                                messenger.showSnackBar(
                                  SnackBar(
                                    content: Text(e.message),
                                    backgroundColor: Colors.red,
                                  ),
                                );
                                return;
                              }
                            }
                            String unitsStr = '';
                            if (_waterSource == 'ٹیوب ویل' || _waterSource == 'بورنگ') {
                              final start = Quantity.tryParse(_startUnitController.text);
                              final end = Quantity.tryParse(_endUnitController.text);
                              if (start != null && end != null) {
                                unitsStr = ' | یونٹ: $start سے $end (استعمال شدہ: ${end - start})';
                              }
                            }
                            _detailsController.text = 'ذریعہ: $_waterSource | وقت: ${_hoursController.text} گھنٹے$unitsStr. ${_detailsController.text}';
                          }
                          
                          // 2. Inventory logic
                          else if (_inventoryCategory != null) {
                            finalExpenseCategory = _inventoryCategory;
                            inventoryCategory = _inventoryCategory;
                            final double enteredQty = Quantity.tryParse(_qtyController.text) ?? 0.0;

                            if (_directPurchase || matchingInventoryItems.isEmpty) {
                              inventoryName = _itemNameController.text;
                              inventoryQty = enteredQty;
                              inventoryUnit = _selectedUnit;
                              try {
                                finalExpenseAmountPaisa =
                                    Money.parse(_priceController.text).paisa;
                              } on MoneyParseException catch (e) {
                                messenger.showSnackBar(
                                  SnackBar(
                                    content: Text(e.message),
                                    backgroundColor: Colors.red,
                                  ),
                                );
                                return;
                              }

                              // Guard: never divide by a null price or a
                              // zero/negative quantity. Validators should catch
                              // this first, but a division must never trust the
                              // form alone — show an error instead of crashing.
                              if (inventoryQty <= 0) {
                                messenger.showSnackBar(
                                  const SnackBar(
                                    content: Text('مقدار اور قیمت درست درج کریں (صفر سے زیادہ)'),
                                    backgroundColor: Colors.red,
                                  ),
                                );
                                return;
                              }

                              // Create in inventory first so we can deduct it.
                              // The purchase is a proper ledger entry, and the
                              // returned id links the activity to the exact row.
                              try {
                                inventoryItemId = await inventoryProvider.recordPurchase(
                                  category: _inventoryCategory!,
                                  name: inventoryName,
                                  unit: _selectedUnit,
                                  quantity: inventoryQty,
                                  costPerUnitPaisa:
                                      (finalExpenseAmountPaisa / inventoryQty)
                                          .round(),
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
                            } else {
                              final Inventory? selected = _selectedInventoryItem;
                              if (selected == null) {
                                messenger.showSnackBar(
                                  const SnackBar(
                                    content: Text('گودام سے آئٹم منتخب کریں'),
                                    backgroundColor: Colors.red,
                                  ),
                                );
                                return;
                              }
                              inventoryItemId = selected.id;
                              inventoryName = selected.name;
                              // Convert entered quantity to the warehouse item's
                              // unit; the activity snapshot is stored in the
                              // item's own unit for exact restores.
                              double convertedQty;
                              try {
                                convertedQty = UnitConverter.convert(
                                  enteredQty,
                                  _selectedUnit,
                                  selected.unit,
                                  weightPerUnitKg: selected.weightPerUnitKg,
                                );
                              } on UnitConversionException catch (e) {
                                messenger.showSnackBar(
                                  SnackBar(
                                    content: Text(e.message),
                                    backgroundColor: Colors.red,
                                  ),
                                );
                                return;
                              }
                              inventoryUnit = selected.unit;
                              inventoryQty = convertedQty;

                              // Calculate expense cost based on the converted quantity
                              finalExpenseAmountPaisa =
                                  (convertedQty * selected.costPerUnitPaisa)
                                      .round();
                            }
                            _detailsController.text = 'استعمال: $inventoryName | مقدار: $enteredQty $_selectedUnit. ${_detailsController.text}';
                          }
                          
                          // 3. Labor and Generic calculations
                          else if (widget.activityTitle == 'مزدور لگائے') {
                            finalExpenseCategory = 'Labour';
                            try {
                              finalExpenseAmountPaisa =
                                  Money.parse(_genericCostController.text).paisa;
                            } on MoneyParseException catch (e) {
                              messenger.showSnackBar(
                                SnackBar(
                                  content: Text(e.message),
                                  backgroundColor: Colors.red,
                                ),
                              );
                              return;
                            }
                            _detailsController.text = 'مزدور تعداد: ${_qtyController.text}. ${_detailsController.text}';
                          } else if (widget.activityTitle == 'مشینری کا استعمال') {
                            finalExpenseCategory = 'Machinery';
                            try {
                              finalExpenseAmountPaisa =
                                  Money.parse(_genericCostController.text).paisa;
                            } on MoneyParseException catch (e) {
                              messenger.showSnackBar(
                                SnackBar(
                                  content: Text(e.message),
                                  backgroundColor: Colors.red,
                                ),
                              );
                              return;
                            }
                            _detailsController.text = 'مشینری: ${_itemNameController.text}. ${_detailsController.text}';
                          } else {
                            try {
                              finalExpenseAmountPaisa =
                                  Money.parse(_genericCostController.text).paisa;
                            } on MoneyParseException catch (e) {
                              messenger.showSnackBar(
                                SnackBar(
                                  content: Text(e.message),
                                  backgroundColor: Colors.red,
                                ),
                              );
                              return;
                            }
                          }

                          // Inventory deductions run inside the provider transaction:
                          // overuse or a missing item aborts the whole save
                          // loudly instead of corrupting stock.
                          try {
                            if (widget.existingActivity != null && !widget.duplicateMode) {
                              await activityProvider.updateActivity(
                                id: widget.existingActivity!.activity.id!,
                                cropSeasonId: targetCropSeasonId,
                                activityType: widget.activityTitle,
                                date: _selectedDate.toIso8601String(),
                                details: _detailsController.text,
                                expenseAmountPaisa: finalExpenseAmountPaisa,
                                expenseCategory: finalExpenseCategory,
                                inventoryCategory: inventoryCategory,
                                inventoryName: inventoryName,
                                inventoryUnit: inventoryUnit,
                                inventoryQuantity: inventoryQty,
                                inventoryItemId: inventoryItemId,
                                isCompleted: widget.existingActivity!.activity.isCompleted,
                                inventoryProvider: inventoryProvider,
                              );
                            } else {
                              await activityProvider.addActivity(
                                cropSeasonId: targetCropSeasonId,
                                activityType: widget.activityTitle,
                                date: _selectedDate.toIso8601String(),
                                details: _detailsController.text,
                                expenseAmountPaisa: finalExpenseAmountPaisa,
                                expenseCategory: finalExpenseCategory,
                                inventoryCategory: inventoryCategory,
                                inventoryName: inventoryName,
                                inventoryUnit: inventoryUnit,
                                inventoryQuantity: inventoryQty,
                                inventoryItemId: inventoryItemId,
                                inventoryProvider: inventoryProvider,
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
                          } on UnitConversionException catch (e) {
                            messenger.showSnackBar(
                              SnackBar(
                                content: Text(e.message),
                                backgroundColor: Colors.red,
                              ),
                            );
                            return;
                          }

                          await expenseProvider.fetchExpenses();
                          await inventoryProvider.fetchInventory();
                          await cropProvider.fetchCropSeasons();
                          await harvestProvider.fetchHarvests();
                          await taskProvider.fetchTasks();

                          messenger.showSnackBar(
                            SnackBar(
                              content: Text(
                                (widget.existingActivity != null && !widget.duplicateMode)
                                    ? 'سرگرمی کامیابی سے اپڈیٹ ہو گئی!'
                                    : 'روزانہ کی سرگرمی کامیابی سے محفوظ ہو گئی!',
                              ),
                            ),
                          );
                          navigator.pop();
                        }
                      },
                      style: ElevatedButton.styleFrom(
                        minimumSize: const Size(double.infinity, 50),
                      ),
                      child: const Text(Strings.save),
                    ),
                  ],
                ),
              ),
            ),
    );
  }

  // Unit conversions go through the central UnitConverter
  // (lib/services/unit_converter.dart) — no local copies.
}
