import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import '../providers/farm_provider.dart';
import '../providers/theka_provider.dart';
import '../models/models.dart';
import '../services/money.dart';

class ThekaFormScreen extends StatefulWidget {
  final Theka? theka; // For editing if applicable

  const ThekaFormScreen({super.key, this.theka});

  @override
  State<ThekaFormScreen> createState() => _ThekaFormScreenState();
}

class _ThekaFormScreenState extends State<ThekaFormScreen> {
  final _formKey = GlobalKey<FormState>();

  int? _selectedFarmId;
  int? _selectedFieldId;
  String _selectedDurationType = 'Yearly'; // 'Yearly', 'Seasonal', 'Custom'
  final _durationDetailsController = TextEditingController();
  final _totalAmountController = TextEditingController();
  String _selectedPaymentMethod = 'Full'; // 'Full', 'Installment'
  
  DateTime _startDate = DateTime.now();
  DateTime _endDate = DateTime.now().add(const Duration(days: 365));

  // Installment support
  final _numInstallmentsController = TextEditingController(text: '2');
  List<Map<String, dynamic>> _installments = []; // List of { 'amount': int (paisa), 'dueDate': DateTime }

  @override
  void initState() {
    super.initState();
    if (widget.theka != null) {
      final t = widget.theka!;
      _selectedFarmId = t.farmId;
      _selectedFieldId = t.fieldId;
      _selectedDurationType = t.durationType;
      _durationDetailsController.text = t.durationDetails ?? '';
      _totalAmountController.text = Money(t.totalAmountPaisa).format();
      _selectedPaymentMethod = t.paymentMethod;
      if (t.startDate != null) _startDate = DateTime.parse(t.startDate!);
      if (t.endDate != null) _endDate = DateTime.parse(t.endDate!);

      // Load installments
      WidgetsBinding.instance.addPostFrameCallback((_) async {
        final thekaProv = Provider.of<ThekaProvider>(context, listen: false);
        final instList = thekaProv.getInstallmentsForTheka(t.id!);
        setState(() {
          _installments = instList.map((inst) => {
            'amount': inst.amountPaisa,
            'dueDate': DateTime.parse(inst.dueDate),
          }).toList();
        });
      });
    }
  }

  @override
  void dispose() {
    _durationDetailsController.dispose();
    _totalAmountController.dispose();
    _numInstallmentsController.dispose();
    super.dispose();
  }

  void _generateInstallments() {
    int totalPaisa;
    try {
      totalPaisa = Money.parse(_totalAmountController.text).paisa;
    } on MoneyParseException catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(e.message),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }
    final int? numInst = int.tryParse(_numInstallmentsController.text);

    if (numInst == null || numInst <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('براہ کرم اقساط کی تعداد درست درج کریں۔'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    final int baseAmount = totalPaisa ~/ numInst;
    int sum = 0;

    final List<Map<String, dynamic>> temp = [];
    
    // Spacing logic: if yearly, space by 12/N months. If seasonal, space by 6/N months. Otherwise, space by 1 month.
    int intervalMonths = 1;
    if (_selectedDurationType == 'Yearly') {
      intervalMonths = (12 / numInst).ceil();
    } else if (_selectedDurationType == 'Seasonal') {
      intervalMonths = (6 / numInst).ceil();
    }
    if (intervalMonths < 1) intervalMonths = 1;

    for (int i = 0; i < numInst; i++) {
      int amt = baseAmount;
      if (i == numInst - 1) {
        // Adjust last installment to handle the remainder
        amt = totalPaisa - sum;
      }
      sum += amt;

      // Calculate future month
      final DateTime dueDate = DateTime(
        _startDate.year,
        _startDate.month + ((i + 1) * intervalMonths),
        _startDate.day,
      );

      temp.add({
        'amount': amt,
        'dueDate': dueDate,
      });
    }

    setState(() {
      _installments = temp;
    });
  }

  int _getInstallmentsSum() {
    return _installments.fold(0, (sum, inst) => sum + (inst['amount'] as int));
  }

  void _saveForm() async {
    if (!_formKey.currentState!.validate()) return;

    if (_selectedFarmId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('براہ کرم فارم (زمین) منتخب کریں۔'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    late final int totalAmountPaisa;
    try {
      totalAmountPaisa = Money.parse(_totalAmountController.text).paisa;
    } on MoneyParseException catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(e.message),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    List<ThekaInstallment> instModels = [];

    if (_selectedPaymentMethod == 'Full') {
      // Create single installment equal to total amount
      instModels.add(ThekaInstallment(
        thekaId: 0,
        amountPaisa: totalAmountPaisa,
        dueDate: DateFormat('yyyy-MM-dd').format(_startDate),
        status: 'Pending',
      ));
    } else {
      if (_installments.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('براہ کرم اقساط کی لسٹ تیار کریں۔'),
            backgroundColor: Colors.red,
          ),
        );
        return;
      }

      final int sum = _getInstallmentsSum();
      if (sum != totalAmountPaisa) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('اقساط کا مجموعہ (${Money(sum).format()}) کل رقم (${Money(totalAmountPaisa).format()}) کے برابر ہونا چاہیے۔'),
            backgroundColor: Colors.red,
          ),
        );
        return;
      }

      for (var inst in _installments) {
        instModels.add(ThekaInstallment(
          thekaId: 0,
          amountPaisa: inst['amount'] as int,
          dueDate: DateFormat('yyyy-MM-dd').format(inst['dueDate']),
          status: 'Pending',
        ));
      }
    }

    final newTheka = Theka(
      id: widget.theka?.id,
      farmId: _selectedFarmId!,
      fieldId: _selectedFieldId,
      totalAmountPaisa: totalAmountPaisa,
      durationType: _selectedDurationType,
      durationDetails: _durationDetailsController.text,
      paymentMethod: _selectedPaymentMethod,
      startDate: DateFormat('yyyy-MM-dd').format(_startDate),
      endDate: DateFormat('yyyy-MM-dd').format(_endDate),
      createdAt: DateTime.now().toIso8601String(),
    );

    final thekaProv = Provider.of<ThekaProvider>(context, listen: false);

    try {
      if (widget.theka == null) {
        await thekaProv.addTheka(newTheka, instModels);
      } else {
        // If editing, we update the theka row first, then if all are pending, we update installments
        // In theka_provider we have updateInstallmentSchedule, but here we can keep it simple or do it
        // Wait, for simplicity let's delete the old one and add new, or do update
        // Since sqlite cascades delete, we can delete the old one first, then insert new.
        // Wait! Let's do that in a single database helper call or transact.
        if (widget.theka != null) {
          // Verify if any old installments are paid.
          final oldInsts = thekaProv.getInstallmentsForTheka(widget.theka!.id!);
          final hasPayments = oldInsts.any((inst) => inst.status != 'Pending');
          if (hasPayments) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('معاہدے کی کسی قسط کی ادائیگی ہو چکی ہے، لہذا ترمیم نہیں کی جا سکتی۔ پہلے ادائیگی کو کینسل کریں۔'),
                backgroundColor: Colors.red,
              ),
            );
            return;
          }
          await thekaProv.deleteTheka(widget.theka!.id!);
        }
        await thekaProv.addTheka(newTheka, instModels);
      }

      if (mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('ٹھیکہ معاہدہ کامیابی سے محفوظ کر لیا گیا ہے۔'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('معاہدہ محفوظ کرنے میں خرابی پیش آئی: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final farmProvider = Provider.of<FarmProvider>(context);

    // Get fields for selected farm
    final fields = _selectedFarmId != null ? farmProvider.getFieldsForFarm(_selectedFarmId!) : <Field>[];

    return Scaffold(
      appBar: AppBar(
        title: Text(widget.theka == null ? 'نیا ٹھیکہ معاہدہ' : 'ٹھیکہ معاہدے میں ترمیم'),
      ),
      body: Form(
        key: _formKey,
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Card(
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                child: Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'زمین اور مدت کی تفصیلات',
                        style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.brown),
                      ),
                      const SizedBox(height: 16),
                      DropdownButtonFormField<int>(
                        isExpanded: true,
                        value: _selectedFarmId,
                        decoration: const InputDecoration(
                          labelText: 'زمین (Farm) منتخب کریں',
                          border: OutlineInputBorder(),
                          prefixIcon: Icon(Icons.landscape),
                        ),
                        items: farmProvider.farms.map((f) {
                          return DropdownMenuItem<int>(
                            value: f.id,
                            child: Text(f.name),
                          );
                        }).toList(),
                        onChanged: (val) {
                          setState(() {
                            _selectedFarmId = val;
                            _selectedFieldId = null; // Reset field
                          });
                        },
                        validator: (val) => val == null ? 'براہ کرم فارم منتخب کریں' : null,
                      ),
                      const SizedBox(height: 16),
                      DropdownButtonFormField<int?>(
                        isExpanded: true,
                        value: _selectedFieldId,
                        decoration: const InputDecoration(
                          labelText: 'مخصوص کھیت (Field) - اختیاری',
                          border: OutlineInputBorder(),
                          prefixIcon: Icon(Icons.grid_on),
                        ),
                        items: [
                          const DropdownMenuItem<int?>(
                            value: null,
                            child: Text('تمام زمین / کھیت شامل ہیں'),
                          ),
                          ...fields.map((f) {
                            return DropdownMenuItem<int?>(
                              value: f.id,
                              child: Text('${f.name} (${f.sizeAcres} ایکڑ)'),
                            );
                          }),
                        ],
                        onChanged: (val) {
                          setState(() {
                            _selectedFieldId = val;
                          });
                        },
                      ),
                      const SizedBox(height: 16),
                      Row(
                        children: [
                          Expanded(
                            child: DropdownButtonFormField<String>(
                              isExpanded: true,
                              value: _selectedDurationType,
                              decoration: const InputDecoration(
                                labelText: 'ٹھیکے کی مدت (Duration)',
                                border: OutlineInputBorder(),
                              ),
                              items: const [
                                DropdownMenuItem(value: 'Yearly', child: Text('سالانہ (Yearly)')),
                                DropdownMenuItem(value: 'Seasonal', child: Text('سہ ماہی/فصلاتی (Seasonal)')),
                                DropdownMenuItem(value: 'Custom', child: Text('کسٹم (Custom)')),
                              ],
                              onChanged: (val) {
                                setState(() {
                                  _selectedDurationType = val!;
                                  // Update end date based on duration type
                                  if (_selectedDurationType == 'Yearly') {
                                    _endDate = DateTime(_startDate.year + 1, _startDate.month, _startDate.day);
                                  } else if (_selectedDurationType == 'Seasonal') {
                                    _endDate = DateTime(_startDate.year, _startDate.month + 6, _startDate.day);
                                  }
                                });
                              },
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: TextFormField(
                              controller: _durationDetailsController,
                              decoration: const InputDecoration(
                                labelText: 'مدت کی تفصیل (مثال: ربیع 2026)',
                                border: OutlineInputBorder(),
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),
                      Row(
                        children: [
                          Expanded(
                            child: ListTile(
                              title: const Text('شروع کی تاریخ', style: TextStyle(fontSize: 12, color: Colors.grey)),
                              subtitle: Text(DateFormat('yyyy-MM-dd').format(_startDate), style: const TextStyle(fontWeight: FontWeight.bold)),
                              trailing: const Icon(Icons.calendar_today, size: 20),
                              onTap: () async {
                                final date = await showDatePicker(
                                  context: context,
                                  initialDate: _startDate,
                                  firstDate: DateTime(2020),
                                  lastDate: DateTime(2035),
                                );
                                if (date != null) {
                                  setState(() {
                                    _startDate = date;
                                    // auto-adjust end date if yearly/seasonal
                                    if (_selectedDurationType == 'Yearly') {
                                      _endDate = DateTime(_startDate.year + 1, _startDate.month, _startDate.day);
                                    } else if (_selectedDurationType == 'Seasonal') {
                                      _endDate = DateTime(_startDate.year, _startDate.month + 6, _startDate.day);
                                    }
                                  });
                                }
                              },
                            ),
                          ),
                          Container(width: 1, height: 40, color: Colors.grey.shade300),
                          Expanded(
                            child: ListTile(
                              title: const Text('ختم کی تاریخ', style: TextStyle(fontSize: 12, color: Colors.grey)),
                              subtitle: Text(DateFormat('yyyy-MM-dd').format(_endDate), style: const TextStyle(fontWeight: FontWeight.bold)),
                              trailing: const Icon(Icons.calendar_today, size: 20),
                              onTap: () async {
                                final date = await showDatePicker(
                                  context: context,
                                  initialDate: _endDate,
                                  firstDate: _startDate,
                                  lastDate: DateTime(2035),
                                );
                                if (date != null) {
                                  setState(() {
                                    _endDate = date;
                                  });
                                }
                              },
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Card(
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                child: Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'ٹھیکہ رقم اور ادائیگی کا طریقہ',
                        style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.brown),
                      ),
                      const SizedBox(height: 16),
                      TextFormField(
                        controller: _totalAmountController,
                        keyboardType: TextInputType.number,
                        decoration: const InputDecoration(
                          labelText: 'کل ٹھیکہ رقم (روپے)',
                          border: OutlineInputBorder(),
                          prefixIcon: Icon(Icons.attach_money),
                        ),
                        validator: (value) {
                          if (value!.isEmpty) return 'براہ کرم ٹھیکہ رقم درج کریں';
                          try {
                            Money.parse(value);
                          } on MoneyParseException {
                            return 'صرف نمبر درج کریں';
                          }
                          return null;
                        },
                        onChanged: (val) {
                          // Trigger UI update to re-evaluate installment sum warning
                          setState(() {});
                        },
                      ),
                      const SizedBox(height: 16),
                      DropdownButtonFormField<String>(
                        isExpanded: true,
                        value: _selectedPaymentMethod,
                        decoration: const InputDecoration(
                          labelText: 'ادائیگی کا طریقہ (Payment Method)',
                          border: OutlineInputBorder(),
                        ),
                        items: const [
                          DropdownMenuItem(value: 'Full', child: Text('ایک بارگی ادائیگی (Lump-sum)')),
                          DropdownMenuItem(value: 'Installment', child: Text('اقساط میں ادائیگی (Installments)')),
                        ],
                        onChanged: (val) {
                          setState(() {
                            _selectedPaymentMethod = val!;
                            if (_selectedPaymentMethod == 'Installment' && _installments.isEmpty) {
                              _generateInstallments();
                            }
                          });
                        },
                      ),
                    ],
                  ),
                ),
              ),
              if (_selectedPaymentMethod == 'Installment') ...[
                const SizedBox(height: 16),
                Card(
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                  child: Padding(
                    padding: const EdgeInsets.all(16.0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            const Text(
                              'اقساط کا شیڈول تیار کریں',
                              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.brown),
                            ),
                            IconButton(
                              icon: const Icon(Icons.refresh, color: Colors.brown),
                              tooltip: 'اقساط دوبارہ تیار کریں',
                              onPressed: _generateInstallments,
                            ),
                          ],
                        ),
                        const SizedBox(height: 16),
                        Row(
                          children: [
                            Expanded(
                              child: TextFormField(
                                controller: _numInstallmentsController,
                                keyboardType: TextInputType.number,
                                decoration: const InputDecoration(
                                  labelText: 'اقساط کی تعداد',
                                  border: OutlineInputBorder(),
                                ),
                              ),
                            ),
                            const SizedBox(width: 12),
                            ElevatedButton(
                              onPressed: _generateInstallments,
                              style: ElevatedButton.styleFrom(
                                backgroundColor: Colors.brown.shade700,
                                foregroundColor: Colors.white,
                                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 18),
                              ),
                              child: const Text('قسطیں تیار کریں'),
                            ),
                          ],
                        ),
                        const Divider(height: 32),
                        ListView.builder(
                          shrinkWrap: true,
                          physics: const NeverScrollableScrollPhysics(),
                          itemCount: _installments.length,
                          itemBuilder: (context, idx) {
                            final inst = _installments[idx];
                            final amountController = TextEditingController(text: Money(inst['amount'] as int).format());

                            return Padding(
                              padding: const EdgeInsets.only(bottom: 12.0),
                              child: Row(
                                children: [
                                  CircleAvatar(
                                    backgroundColor: Colors.brown.shade50,
                                    child: Text('${idx + 1}', style: const TextStyle(fontWeight: FontWeight.bold)),
                                  ),
                                  const SizedBox(width: 10),
                                  Expanded(
                                    flex: 3,
                                    child: TextFormField(
                                      controller: amountController,
                                      keyboardType: TextInputType.number,
                                      decoration: const InputDecoration(
                                        labelText: 'قسط کی رقم',
                                        border: OutlineInputBorder(),
                                      ),
                                      onChanged: (val) {
                                        try {
                                          _installments[idx]['amount'] = Money.parse(val).paisa;
                                          setState(() {}); // refresh sum check
                                        } on MoneyParseException {
                                          // Keep the previous valid amount.
                                        }
                                      },
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    flex: 4,
                                    child: OutlinedButton(
                                      style: OutlinedButton.styleFrom(
                                        padding: const EdgeInsets.symmetric(vertical: 16),
                                        shape: RoundedRectangleBorder(
                                          borderRadius: BorderRadius.circular(8),
                                        ),
                                      ),
                                      onPressed: () async {
                                        final date = await showDatePicker(
                                          context: context,
                                          initialDate: inst['dueDate'],
                                          firstDate: DateTime(2020),
                                          lastDate: DateTime(2035),
                                        );
                                        if (date != null) {
                                          setState(() {
                                            _installments[idx]['dueDate'] = date;
                                          });
                                        }
                                      },
                                      child: Text(
                                        DateFormat('yyyy-MM-dd').format(inst['dueDate']),
                                        style: const TextStyle(fontWeight: FontWeight.bold),
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 4),
                                  IconButton(
                                    icon: const Icon(Icons.remove_circle_outline, color: Colors.red),
                                    onPressed: () {
                                      setState(() {
                                        _installments.removeAt(idx);
                                      });
                                    },
                                  ),
                                ],
                              ),
                            );
                          },
                        ),
                        const SizedBox(height: 12),
                        OutlinedButton.icon(
                          onPressed: () {
                            setState(() {
                              _installments.add({
                                'amount': 0,
                                'dueDate': DateTime.now().add(const Duration(days: 30)),
                              });
                            });
                          },
                          icon: const Icon(Icons.add),
                          label: const Text('نئی قسط شامل کریں'),
                        ),
                        const SizedBox(height: 16),
                        _buildInstallmentValidationSummary(),
                      ],
                    ),
                  ),
                ),
              ],
              const SizedBox(height: 24),
              ElevatedButton(
                onPressed: _saveForm,
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.brown.shade800,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                child: const Text(
                  'ٹھیکہ معاہدہ محفوظ کریں',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildInstallmentValidationSummary() {
    int totalAmtPaisa;
    try {
      totalAmtPaisa = Money.parse(_totalAmountController.text).paisa;
    } on MoneyParseException {
      totalAmtPaisa = 0;
    }
    final int instSum = _getInstallmentsSum();
    final int diff = totalAmtPaisa - instSum;

    final isMatched = diff == 0;

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: isMatched ? Colors.green.shade50 : Colors.red.shade50,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: isMatched ? Colors.green.shade300 : Colors.red.shade300),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'کل رقم: ${Money(totalAmtPaisa).format()}',
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
              Text(
                'اقساط کا مجموعہ: ${Money(instSum).format()}',
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  color: isMatched ? Colors.green : Colors.red,
                ),
              ),
            ],
          ),
          if (!isMatched) ...[
            const SizedBox(height: 6),
            Text(
              diff > 0
                  ? 'رقم کم ہے: ${Money(diff).format()} اور تقسیم کریں'
                  : 'رقم زیادہ ہے: ${Money(diff.abs()).format()} اقساط سے کم کریں',
              style: const TextStyle(color: Colors.red, fontSize: 13, fontWeight: FontWeight.bold),
            ),
          ],
        ],
      ),
    );
  }
}
