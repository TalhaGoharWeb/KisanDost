import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import '../widgets/digit_text.dart';
import '../providers/theka_provider.dart';
import '../providers/farm_provider.dart';
import '../providers/expense_provider.dart';
import '../models/models.dart';
import '../services/money.dart';
import 'theka_form_screen.dart';
import '../l10n/strings.dart';

class ThekaDetailsScreen extends StatefulWidget {
  final int thekaId;

  const ThekaDetailsScreen({super.key, required this.thekaId});

  @override
  State<ThekaDetailsScreen> createState() => _ThekaDetailsScreenState();
}

class _ThekaDetailsScreenState extends State<ThekaDetailsScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<ThekaProvider>().fetchThekas();
      context.read<FarmProvider>().fetchFarms();
      context.read<ExpenseProvider>().fetchExpenses();
    });
  }

  void _showRecordPaymentDialog(
    BuildContext context,
    ThekaInstallment inst,
    String farmName,
    int index,
  ) {
    final formKey = GlobalKey<FormState>();
    // Incremental payment: the field is pre-filled with the REMAINING amount.
    // payInstallment ADDS this to the already-recorded paid amount.
    final int remaining = inst.amountPaisa - inst.paidAmountPaisa;
    final amountController = TextEditingController(
      text: Money(remaining).format(),
    );
    DateTime selectedDate =
        inst.paidDate != null ? DateTime.parse(inst.paidDate!) : DateTime.now();

    showDialog(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (context, setState) {
            return AlertDialog(
              title: Text(
                inst.status == 'Pending'
                    ? 'ادائیگی درج کریں'
                    : 'بقایا ادائیگی درج کریں',
              ),
              content: Form(
                key: formKey,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      'قسط رقم: ${Money(inst.amountPaisa).format()}',
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 16,
                      ),
                    ),
                    if (inst.paidAmountPaisa > 0) ...[
                      const SizedBox(height: 8),
                      Text(
                        'ادا شدہ: ${Money(inst.paidAmountPaisa).format()} | بقایا: ${Money(remaining).format()}',
                        style: TextStyle(
                          fontSize: 14,
                          color: Colors.grey.shade700,
                        ),
                      ),
                    ],
                    const SizedBox(height: 16),
                    TextFormField(
                      controller: amountController,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(
                        labelText: 'اس بار ادا کی گئی رقم (روپے)',
                        border: OutlineInputBorder(),
                      ),
                      validator: (value) {
                        if (value!.isEmpty) return 'رقم درج کریں';
                        int parsedPaisa;
                        try {
                          parsedPaisa = Money.parse(value).paisa;
                        } on MoneyParseException {
                          return 'صحیح رقم درج کریں';
                        }
                        if (parsedPaisa <= 0) return 'صحیح رقم درج کریں';
                        if (parsedPaisa > remaining) {
                          return 'رقم بقایا رقم (${Money(remaining).format()}) سے زیادہ نہیں ہو سکتی';
                        }
                        return null;
                      },
                    ),
                    const SizedBox(height: 16),
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      title: Text(
                        'تاریخ: ${DateFormat('yyyy-MM-dd').format(selectedDate)}',
                      ),
                      trailing: const Icon(Icons.calendar_today),
                      onTap: () async {
                        final date = await showDatePicker(
                          context: context,
                          initialDate: selectedDate,
                          firstDate: DateTime(2020),
                          lastDate: DateTime(2035),
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
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(ctx),
                  child: const Text(Strings.cancel),
                ),
                ElevatedButton(
                  onPressed: () async {
                    if (formKey.currentState!.validate()) {
                      int paidAmountPaisa;
                      try {
                        paidAmountPaisa =
                            Money.parse(amountController.text).paisa;
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
                      final String dateStr = DateFormat(
                        'yyyy-MM-dd',
                      ).format(selectedDate);

                      final thekaProv = Provider.of<ThekaProvider>(
                        context,
                        listen: false,
                      );
                      final expProv = Provider.of<ExpenseProvider>(
                        context,
                        listen: false,
                      );

                      try {
                        await thekaProv.payInstallment(
                          installmentId: inst.id!,
                          paidAmountPaisa: paidAmountPaisa,
                          paidDate: dateStr,
                          farmName: farmName,
                          installmentIndex: index,
                        );

                        // Sync ledger/expenses provider
                        await expProv.fetchExpenses();

                        if (context.mounted) {
                          Navigator.pop(ctx);
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text(
                                'ٹھیکہ ادائیگی درج کر دی گئی ہے اور لیجر اپ ڈیٹ کر دیا گیا ہے۔',
                              ),
                              backgroundColor: Colors.green,
                            ),
                          );
                        }
                      } catch (e) {
                        // Overpayment guard (or any payment error): show the
                        // Urdu reason instead of crashing.
                        if (context.mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text(
                                e.toString().replaceFirst('Exception: ', ''),
                              ),
                              backgroundColor: Colors.red,
                            ),
                          );
                        }
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

  void _confirmDeleteAgreement(
    BuildContext context,
    Theka theka,
    String farmName,
    bool hasPayments,
  ) {
    showDialog(
      context: context,
      builder: (ctx) {
        return AlertDialog(
          title: const Text('معاہدہ حذف کریں؟'),
          content: Text(
            hasPayments
                ? 'خبردار! اس معاہدے کی قسطیں ادا کی جا چکی ہیں۔ معاہدہ حذف کرنے سے متعلقہ تمام خرچے اور لیجر ٹرانزیکشنز بھی حذف ہو جائیں گی۔ کیا آپ واقعی حذف کرنا چاہتے ہیں؟'
                : 'کیا آپ واقعی اس ٹھیکہ معاہدے کو حذف کرنا چاہتے ہیں؟',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text(Strings.cancel),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
              onPressed: () async {
                final thekaProv = Provider.of<ThekaProvider>(
                  context,
                  listen: false,
                );
                final expProv = Provider.of<ExpenseProvider>(
                  context,
                  listen: false,
                );

                await thekaProv.deleteTheka(theka.id!);
                await expProv.fetchExpenses();

                if (context.mounted) {
                  Navigator.pop(ctx); // Close dialog
                  Navigator.pop(context); // Go back to list
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('ٹھیکہ معاہدہ حذف کر دیا گیا ہے۔'),
                      backgroundColor: Colors.red,
                    ),
                  );
                }
              },
              child: const Text(Strings.delete),
            ),
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final thekaProvider = Provider.of<ThekaProvider>(context);
    final farmProvider = Provider.of<FarmProvider>(context);

    // Find current theka
    final thekaList =
        thekaProvider.thekas.where((t) => t.id == widget.thekaId).toList();
    if (thekaList.isEmpty) {
      return Scaffold(
        appBar: AppBar(title: const Text('ٹھیکہ کی تفصیلات')),
        body: const Center(child: Text('معاہدہ نہیں مل سکا۔')),
      );
    }

    final theka = thekaList.first;
    final farm = farmProvider.farms.firstWhere(
      (f) => f.id == theka.farmId,
      orElse: () => Farm(name: 'نامعلوم فارم', totalArea: 0.0, createdAt: ''),
    );

    String fieldText = 'تمام زمین / کھیت';
    if (theka.fieldId != null) {
      final fields = farmProvider.getFieldsForFarm(theka.farmId);
      final field = fields.firstWhere(
        (f) => f.id == theka.fieldId,
        orElse:
            () => Field(
              farmId: theka.farmId,
              name: 'نامعلوم کھیت',
              sizeAcres: 0.0,
            ),
      );
      if (field.name.isNotEmpty) {
        fieldText = '${field.name} (${field.sizeAcres} ایکڑ)';
      }
    }

    final insts = thekaProvider.getInstallmentsForTheka(theka.id!);
    int paidAmt = 0;
    for (var inst in insts) {
      paidAmt += inst.paidAmountPaisa;
    }
    final int pendingAmt = theka.totalAmountPaisa - paidAmt;
    final bool hasPayments = insts.any((inst) => inst.status != 'Pending');

    String durationUrdu = theka.durationType;
    if (theka.durationType == 'Yearly') {
      durationUrdu = 'سالانہ';
    } else if (theka.durationType == 'Seasonal') {
      durationUrdu = 'موسمی / فصلاتی';
    } else if (theka.durationType == 'Custom') {
      durationUrdu = 'کسٹم';
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('ٹھیکہ کی تفصیلات'),
        actions: [
          IconButton(
            icon: const Icon(Icons.edit_outlined),
            tooltip: 'ترمیم کریں',
            onPressed:
                hasPayments
                    ? () {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text(
                            'ادائیگیاں ریکارڈ ہونے کی وجہ سے ترمیم بند ہے۔ پہلے ادائیگی کینسل کریں۔',
                          ),
                          backgroundColor: Colors.red,
                        ),
                      );
                    }
                    : () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => ThekaFormScreen(theka: theka),
                        ),
                      );
                    },
          ),
          IconButton(
            icon: const Icon(Icons.delete_outline),
            tooltip: Strings.delete,
            onPressed:
                () => _confirmDeleteAgreement(
                  context,
                  theka,
                  farm.name,
                  hasPayments,
                ),
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Summary Card
            Card(
              elevation: 4,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
              ),
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [Colors.brown.shade800, Colors.brown.shade600],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      farm.name,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 24,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'محدودہ: $fieldText',
                      style: const TextStyle(
                        color: Colors.white70,
                        fontSize: 15,
                      ),
                    ),
                    const Divider(color: Colors.white24, height: 24),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        _buildSummaryHeaderItem(
                          'ٹھیکہ رقم',
                          theka.totalAmountPaisa,
                          Colors.white,
                        ),
                        _buildSummaryHeaderItem(
                          'ادا شدہ',
                          paidAmt,
                          Colors.greenAccent,
                        ),
                        _buildSummaryHeaderItem(
                          'باقی واجب الادا',
                          pendingAmt,
                          Colors.orangeAccent,
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 20),

            // Agreement Details
            const Text(
              'معاہدہ کی تفصیلات',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: Colors.brown,
              ),
            ),
            const SizedBox(height: 10),
            Card(
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  children: [
                    _buildDetailRow('ٹھیکے کی قسم', durationUrdu),
                    if (theka.durationDetails != null &&
                        theka.durationDetails!.isNotEmpty)
                      _buildDetailRow(
                        'تفصیل / فصل کا نام',
                        theka.durationDetails!,
                      ),
                    _buildDetailRow(
                      'تاریخ آغاز',
                      theka.startDate ?? 'درج نہیں',
                    ),
                    _buildDetailRow(
                      'تاریخ اختتام',
                      theka.endDate ?? 'درج نہیں',
                    ),
                    _buildDetailRow(
                      'ادائیگی کی قسم',
                      theka.paymentMethod == 'Full'
                          ? 'ایک بارگی (Lump-sum)'
                          : 'اقساط میں (Installments)',
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 20),

            // Installment Plan
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  'ادائیگی کا شیڈول (اقساط)',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: Colors.brown,
                  ),
                ),
                if (!hasPayments && theka.paymentMethod == 'Installment')
                  TextButton.icon(
                    onPressed: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => ThekaFormScreen(theka: theka),
                        ),
                      );
                    },
                    icon: const Icon(
                      Icons.edit_calendar,
                      size: 18,
                      color: Colors.brown,
                    ),
                    label: const Text(
                      'شیڈول بدلیں',
                      style: TextStyle(color: Colors.brown),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 10),
            ListView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: insts.length,
              itemBuilder: (context, index) {
                final inst = insts[index];
                final instIdx = index + 1;

                Color statusColor = Colors.grey.shade600;
                String statusText = 'غیر ادا شدہ (Pending)';
                if (inst.status == 'Paid') {
                  statusColor = Colors.green.shade700;
                  statusText = 'ادا شدہ (Paid)';
                } else if (inst.status == 'Partially Paid') {
                  statusColor = Colors.orange.shade800;
                  statusText = 'جزوی ادا شدہ (Partially Paid)';
                }

                return Card(
                  margin: const EdgeInsets.only(bottom: 12),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                    side: BorderSide(color: Colors.grey.shade200),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(14.0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(
                              'قسط نمبر $instIdx',
                              style: const TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 16,
                              ),
                            ),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 8,
                                vertical: 3,
                              ),
                              decoration: BoxDecoration(
                                color: statusColor.withValues(alpha: 0.1),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Text(
                                statusText,
                                style: TextStyle(
                                  color: statusColor,
                                  fontWeight: FontWeight.bold,
                                  fontSize: 12,
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            _buildInfoCol(
                              'رقم',
                              Money(inst.amountPaisa).format(),
                            ),
                            _buildInfoCol('آخری تاریخ', inst.dueDate),
                            if (inst.status != 'Pending') ...[
                              _buildInfoCol(
                                'ادا شدہ رقم',
                                Money(inst.paidAmountPaisa).format(),
                                color: Colors.green.shade700,
                              ),
                              _buildInfoCol(
                                'تاریخ ادائیگی',
                                inst.paidDate ?? '-',
                              ),
                            ],
                          ],
                        ),
                        const Divider(height: 20),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.end,
                          children: [
                            if (inst.status == 'Pending')
                              ElevatedButton.icon(
                                onPressed:
                                    () => _showRecordPaymentDialog(
                                      context,
                                      inst,
                                      farm.name,
                                      instIdx,
                                    ),
                                icon: const Icon(Icons.payment, size: 16),
                                label: const Text('ادائیگی درج کریں'),
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: Colors.brown.shade800,
                                  foregroundColor: Colors.white,
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 12,
                                    vertical: 8,
                                  ),
                                ),
                              )
                            else ...[
                              // Record an additional payment only while a
                              // balance remains; overpayment is rejected.
                              if (inst.paidAmountPaisa < inst.amountPaisa)
                                OutlinedButton.icon(
                                  onPressed:
                                      () => _showRecordPaymentDialog(
                                        context,
                                        inst,
                                        farm.name,
                                        instIdx,
                                      ),
                                  icon: const Icon(
                                    Icons.add_circle_outline,
                                    size: 16,
                                  ),
                                  label: const Text('بقایا ادائیگی'),
                                  style: OutlinedButton.styleFrom(
                                    foregroundColor: Colors.brown.shade800,
                                    side: BorderSide(
                                      color: Colors.brown.shade800,
                                    ),
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 12,
                                      vertical: 8,
                                    ),
                                  ),
                                ),
                              const SizedBox(width: 8),
                              OutlinedButton.icon(
                                onPressed: () async {
                                  final thekaProv = Provider.of<ThekaProvider>(
                                    context,
                                    listen: false,
                                  );
                                  final expProv = Provider.of<ExpenseProvider>(
                                    context,
                                    listen: false,
                                  );
                                  await thekaProv.markInstallmentPending(
                                    inst.id!,
                                  );
                                  await expProv.fetchExpenses();
                                  if (context.mounted) {
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      const SnackBar(
                                        content: Text(
                                          'ادائیگی منسوخ کر دی گئی ہے اور لیجر سے خرچہ حذف ہو گیا ہے۔',
                                        ),
                                        backgroundColor: Colors.orange,
                                      ),
                                    );
                                  }
                                },
                                icon: const Icon(Icons.undo, size: 16),
                                label: const Text('ادائیگی منسوخ کریں'),
                                style: OutlinedButton.styleFrom(
                                  foregroundColor: Colors.red.shade700,
                                  side: BorderSide(color: Colors.red.shade200),
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 12,
                                    vertical: 8,
                                  ),
                                ),
                              ),
                            ],
                          ],
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSummaryHeaderItem(String label, int amount, Color textCol) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(color: Colors.white70, fontSize: 13),
        ),
        const SizedBox(height: 4),
        DigitText(
          Money(amount).format(),
          style: TextStyle(
            color: textCol,
            fontSize: 18,
            fontWeight: FontWeight.bold,
          ),
        ),
      ],
    );
  }

  Widget _buildDetailRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8.0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: TextStyle(color: Colors.grey.shade600, fontSize: 14),
          ),
          Text(
            value,
            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
          ),
        ],
      ),
    );
  }

  Widget _buildInfoCol(String label, String val, {Color? color}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: TextStyle(color: Colors.grey.shade500, fontSize: 11),
        ),
        const SizedBox(height: 2),
        Text(
          val,
          style: TextStyle(
            fontWeight: FontWeight.bold,
            fontSize: 13,
            color: color ?? Colors.black87,
          ),
        ),
      ],
    );
  }
}
