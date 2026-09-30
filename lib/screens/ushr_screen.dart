import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import '../providers/ushr_provider.dart';
import '../providers/crop_provider.dart';
import '../providers/harvest_provider.dart';
import '../widgets/empty_state_widget.dart';
import '../models/models.dart';

class UshrScreen extends StatefulWidget {
  const UshrScreen({super.key});

  @override
  State<UshrScreen> createState() => _UshrScreenState();
}

class _UshrScreenState extends State<UshrScreen> {
  @override
  Widget build(BuildContext context) {
    final ushrProvider = Provider.of<UshrProvider>(context);
    final cropProvider = Provider.of<CropProvider>(context);

    double totalUshr = 0.0;
    double totalPaid = 0.0;
    double totalPending = 0.0;

    for (final item in ushrProvider.ushrRecords) {
      final u = item.ushrRecord;
      totalUshr += u.ushrAmount;
      final paidValue = u.cashPaid + (u.qtyPaid * u.ratePerUnit);
      totalPaid += paidValue;
      totalPending += u.remainingBalance;
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('عشر مینجمنٹ'),
      ),
      body: RefreshIndicator(
        onRefresh: () async {
          final harvestProvider = Provider.of<HarvestProvider>(context, listen: false);
          await ushrProvider.fetchUshrRecords();
          await harvestProvider.fetchHarvests();
        },
        child: ushrProvider.ushrRecords.isEmpty
            ? SingleChildScrollView(
                physics: const AlwaysScrollableScrollPhysics(),
                child: SizedBox(
                  height: MediaQuery.of(context).size.height - kToolbarHeight - MediaQuery.of(context).padding.top,
                  child: const EmptyStateWidget(
                    message: 'کوئی عشر ریکارڈ نہیں ہے',
                    subtitle: 'عشر کا حساب لگانے کے لیے نیچے بٹن دبائیں',
                    fallbackIcon: Icons.volunteer_activism,
                    imageAsset: 'assets/images/wheat.png',
                  ),
                ),
              )
            : ListView.builder(
                padding: const EdgeInsets.all(12),
                itemCount: ushrProvider.ushrRecords.length + 1,
                itemBuilder: (context, index) {
                  if (index == 0) {
                    return _buildSummaryCards(totalUshr, totalPaid, totalPending);
                  }

                  final item = ushrProvider.ushrRecords[index - 1];
                  final u = item.ushrRecord;
                  final cropNameUrdu = cropProvider.predefinedCrops[item.cropName] ?? item.cropName;

                  String irrigationUrdu = 'قدرتی آبپاشی (10%)';
                  if (u.ushrMethod == 'Artificial') {
                    irrigationUrdu = 'مصنوعی آبپاشی (5%)';
                  } else if (u.ushrMethod == 'Custom') {
                    irrigationUrdu = 'کسٹم شرح (${u.ushrPercentage}%)';
                  }

                  String payMethodUrdu = 'نقد رقم (Cash)';
                  if (u.payMethod == 'Crop') {
                    payMethodUrdu = 'جنس/پیداوار (Crop)';
                  } else if (u.payMethod == 'Mixed') {
                    payMethodUrdu = 'مخلوط نقد+جنس (Mixed)';
                  }

                  final paidValue = u.cashPaid + (u.qtyPaid * u.ratePerUnit);

                  return Card(
                    elevation: 2,
                    margin: const EdgeInsets.only(bottom: 12),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                    child: Padding(
                      padding: const EdgeInsets.all(16.0),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text(
                                '$cropNameUrdu - عشر',
                                style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.green),
                              ),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                decoration: BoxDecoration(
                                  color: u.status == 'Paid' ? Colors.green.shade50 : Colors.red.shade50,
                                  borderRadius: BorderRadius.circular(8),
                                  border: Border.all(color: u.status == 'Paid' ? Colors.green.shade200 : Colors.red.shade200),
                                ),
                                child: Text(
                                  u.status == 'Paid' ? 'ادا شدہ (Paid)' : 'باقی (Pending)',
                                  style: TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.bold,
                                    color: u.status == 'Paid' ? Colors.green.shade800 : Colors.red.shade800,
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 6),
                          Text('زمین: ${item.farmName} - ${item.fieldName}'),
                          const SizedBox(height: 4),
                          Text('پیداوار مقدار: ${u.harvestQty.toStringAsFixed(0)} من | مارکیٹ ویلیو: Rs. ${u.marketValue.toStringAsFixed(0)}'),
                          const Divider(height: 20),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const Text('آبپاشی کا طریقہ', style: TextStyle(fontSize: 12, color: Colors.grey)),
                                  Text(irrigationUrdu, style: const TextStyle(fontWeight: FontWeight.bold)),
                                ],
                              ),
                              Column(
                                crossAxisAlignment: CrossAxisAlignment.end,
                                children: [
                                  const Text('عشر واجب الادا', style: TextStyle(fontSize: 12, color: Colors.grey)),
                                  Text(
                                    'Rs. ${u.ushrAmount.toStringAsFixed(0)}',
                                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: Colors.green),
                                  ),
                                ],
                              ),
                            ],
                          ),
                          const SizedBox(height: 12),
                          // Payment Breakdown Box
                          Container(
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: Colors.grey.shade50,
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(color: Colors.grey.shade200),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                  children: [
                                    Text('طریقہ ادائیگی:', style: TextStyle(fontSize: 13, color: Colors.grey.shade700)),
                                    Text(payMethodUrdu, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                                  ],
                                ),
                                const SizedBox(height: 6),
                                Row(
                                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                  children: [
                                    Text('نقد ادا شدہ:', style: TextStyle(fontSize: 13, color: Colors.grey.shade700)),
                                    Text('Rs. ${u.cashPaid.toStringAsFixed(0)}', style: const TextStyle(fontSize: 13)),
                                  ],
                                ),
                                const SizedBox(height: 4),
                                Row(
                                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                  children: [
                                    Text('جنس ادا شدہ:', style: TextStyle(fontSize: 13, color: Colors.grey.shade700)),
                                    Text('${u.qtyPaid.toStringAsFixed(1)} من (قیمت: Rs. ${(u.qtyPaid * u.ratePerUnit).toStringAsFixed(0)})', style: const TextStyle(fontSize: 13)),
                                  ],
                                ),
                                const Divider(),
                                Row(
                                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                  children: [
                                    const Text('کل ادا شدہ قدر:', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Colors.green)),
                                    Text('Rs. ${paidValue.toStringAsFixed(0)}', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Colors.green)),
                                  ],
                                ),
                                if (u.remainingBalance > 0) ...[
                                  const SizedBox(height: 4),
                                  Row(
                                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                    children: [
                                      const Text('باقی واجب الادا عشر:', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Colors.red)),
                                      Text('Rs. ${u.remainingBalance.toStringAsFixed(0)}', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Colors.red)),
                                    ],
                                  ),
                                ],
                              ],
                            ),
                          ),
                          if (u.status == 'Paid' && u.datePaid != null) ...[
                            const SizedBox(height: 8),
                            Text(
                              'تاریخ ادائیگی: ${DateFormat('yyyy-MM-dd').format(DateTime.parse(u.datePaid!))}',
                              style: const TextStyle(fontSize: 13, color: Colors.blueGrey),
                            ),
                          ],
                          if (u.notes != null && u.notes!.isNotEmpty) ...[
                            const SizedBox(height: 8),
                            Text(
                              'تفصیل/نوٹس: ${u.notes}',
                              style: const TextStyle(fontSize: 13, fontStyle: FontStyle.italic, color: Colors.grey),
                            ),
                          ],
                          const Divider(height: 20),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.end,
                            children: [
                              TextButton.icon(
                                style: TextButton.styleFrom(foregroundColor: Colors.blueGrey),
                                icon: const Icon(Icons.edit, size: 16),
                                label: const Text('تبدیلی'),
                                onPressed: () => _showAddOrEditUshrDialog(context, cropProvider, existingRecord: u),
                              ),
                              const SizedBox(width: 8),
                              TextButton.icon(
                                style: TextButton.styleFrom(foregroundColor: Colors.red),
                                icon: const Icon(Icons.delete, size: 16),
                                label: const Text('حذف'),
                                onPressed: () => _confirmDeleteUshr(context, u.id!),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _showAddOrEditUshrDialog(context, cropProvider),
        icon: const Icon(Icons.calculate),
        label: const Text('عشر درج کریں'),
        backgroundColor: Colors.green.shade800,
        foregroundColor: Colors.white,
      ),
    );
  }

  Widget _buildSummaryCards(double total, double paid, double pending) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12.0),
      child: Row(
        children: [
          Expanded(
            child: _buildSummaryCard(
              title: 'کل واجب عشر',
              value: 'Rs. ${total.toStringAsFixed(0)}',
              color: Colors.green.shade800,
              bgColor: Colors.green.shade50,
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: _buildSummaryCard(
              title: 'کل ادا شدہ عشر',
              value: 'Rs. ${paid.toStringAsFixed(0)}',
              color: Colors.green.shade900,
              bgColor: Colors.teal.shade50,
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: _buildSummaryCard(
              title: 'کل باقی عشر',
              value: 'Rs. ${pending.toStringAsFixed(0)}',
              color: Colors.red.shade800,
              bgColor: Colors.red.shade50,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSummaryCard({
    required String title,
    required String value,
    required Color color,
    required Color bgColor,
  }) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: TextStyle(fontSize: 11, color: color.withValues(alpha: 0.8), fontWeight: FontWeight.bold)),
          const SizedBox(height: 4),
          FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(
              value,
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: color),
            ),
          ),
        ],
      ),
    );
  }

  void _showAddOrEditUshrDialog(BuildContext context, CropProvider cropProvider, {UshrRecord? existingRecord}) {
    final ushrProvider = Provider.of<UshrProvider>(context, listen: false);
    final harvestProvider = Provider.of<HarvestProvider>(context, listen: false);
    final activeSeasons = cropProvider.activeCropSeasons;
    final harvestsList = harvestProvider.harvests;

    if (activeSeasons.isEmpty && existingRecord == null) {
      showDialog(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('کوئی فعال فصل نہیں ہے'),
          content: const Text('عشر درج کرنے کے لیے پہلے "میری فصلیں" میں جا کر فصل شروع کریں۔'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('ٹھیک ہے'),
            ),
          ],
        ),
      );
      return;
    }

    final formKey = GlobalKey<FormState>();

    // Input Controllers
    final qtyController = TextEditingController(text: existingRecord?.harvestQty.toString() ?? '');
    final marketRateController = TextEditingController(text: existingRecord?.ratePerUnit.toString() ?? '');
    final marketValueController = TextEditingController(text: existingRecord?.marketValue.toString() ?? '');
    final customPercentageController = TextEditingController(text: existingRecord?.ushrPercentage.toString() ?? '10.0');
    final notesController = TextEditingController(text: existingRecord?.notes ?? '');

    final qtyPaidController = TextEditingController(text: existingRecord?.qtyPaid.toString() ?? '0.0');
    final cashPaidController = TextEditingController(text: existingRecord?.cashPaid.toString() ?? '0.0');

    int? selectedCropSeasonId = existingRecord?.cropSeasonId ?? (activeSeasons.isNotEmpty ? activeSeasons.first.cropSeason.id : null);
    int? selectedHarvestId = existingRecord?.harvestId;

    String selectedMethod = existingRecord?.ushrMethod ?? 'Natural';
    String payMethod = existingRecord?.payMethod ?? 'Cash';
    String status = existingRecord?.status ?? 'Pending';
    DateTime selectedDatePaid = existingRecord?.datePaid != null ? DateTime.parse(existingRecord!.datePaid!) : DateTime.now();

    showDialog(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (context, setState) {
            // Conversions & calculations
            final double qty = double.tryParse(qtyController.text) ?? 0.0;
            final double rate = double.tryParse(marketRateController.text) ?? 0.0;
            final double marketValue = qty * rate;
            if (marketValueController.text != marketValue.toStringAsFixed(0) && marketValue > 0) {
              marketValueController.text = marketValue.toStringAsFixed(0);
            }

            double percentage = 10.0;
            if (selectedMethod == 'Natural') {
              percentage = 10.0;
            } else if (selectedMethod == 'Artificial') {
              percentage = 5.0;
            } else {
              percentage = double.tryParse(customPercentageController.text) ?? 0.0;
            }

            final double ushrQty = (qty * percentage) / 100.0;
            final double calculatedUshrAmount = (marketValue * percentage) / 100.0;

            // Unit Conversions
            final double ushrQtyKg = ushrQty * 40.0; // 1 Maund = 40 KG

            // Payment Calculations
            final double qtyPaid = double.tryParse(qtyPaidController.text) ?? 0.0;
            final double cashPaid = double.tryParse(cashPaidController.text) ?? 0.0;
            final double totalPaidPkr = cashPaid + (qtyPaid * rate);
            final double remainingBalance = calculatedUshrAmount - totalPaidPkr;

            // Auto status logic
            status = remainingBalance <= 0.0 ? 'Paid' : 'Pending';

            return AlertDialog(
              title: Text(existingRecord == null ? 'عشر کا حساب لگائیں' : 'عشر کا ریکارڈ تبدیل کریں'),
              content: Form(
                key: formKey,
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // Harvest Selector Dropdown (Optional Autofill)
                      if (existingRecord == null) ...[
                        DropdownButtonFormField<int?>(
                          isExpanded: true,
                          initialValue: selectedHarvestId,
                          decoration: const InputDecoration(
                            labelText: 'فصل کٹائی سے معلومات لیں (آٹو فل)',
                            border: OutlineInputBorder(),
                            prefixIcon: Icon(Icons.agriculture),
                          ),
                          items: [
                            const DropdownMenuItem<int?>(
                              value: null,
                              child: Text('دستی درج کریں (Manual Input)'),
                            ),
                            ...harvestsList.map((hwd) {
                              final name = cropProvider.predefinedCrops[hwd.cropName] ?? hwd.cropName;
                              return DropdownMenuItem<int?>(
                                value: hwd.harvest.id,
                                child: Text('${hwd.farmName} - $name (${hwd.harvest.quantity} ${hwd.harvest.unit})'),
                              );
                            }),
                          ],
                          onChanged: (val) {
                            setState(() {
                              selectedHarvestId = val;
                              if (val != null) {
                                final selectedH = harvestsList.firstWhere((h) => h.harvest.id == val);
                                selectedCropSeasonId = selectedH.harvest.cropSeasonId;
                                qtyController.text = selectedH.harvest.quantity.toString();
                                marketRateController.text = selectedH.harvest.ratePerUnit.toString();
                                marketValueController.text = selectedH.harvest.grossAmount.toString();
                              }
                            });
                          },
                        ),
                        const SizedBox(height: 12),
                      ],
                      DropdownButtonFormField<int>(
                        isExpanded: true,
                        initialValue: selectedCropSeasonId,
                        decoration: const InputDecoration(
                          labelText: 'فصل منتخب کریں',
                          border: OutlineInputBorder(),
                        ),
                        items: [...cropProvider.activeCropSeasons, ...cropProvider.harvestedCropSeasons]
                            .map((details) {
                              final season = details.cropSeason;
                              final nameUrdu = cropProvider.predefinedCrops[season.cropName] ?? season.cropName;
                              return DropdownMenuItem<int>(
                                value: season.id,
                                child: Text('${details.farmDisplayName} - ${details.fieldDisplayName} ($nameUrdu - ${season.variety})'),
                              );
                            })
                            .toList(),
                        onChanged: (val) {
                          setState(() {
                            selectedCropSeasonId = val;
                          });
                        },
                        validator: (v) => v == null ? 'فصل منتخب کریں' : null,
                      ),
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          Expanded(
                            child: TextFormField(
                              controller: qtyController,
                              keyboardType: const TextInputType.numberWithOptions(decimal: true),
                              decoration: const InputDecoration(
                                labelText: 'کل کٹائی مقدار (من/Maund)',
                                border: OutlineInputBorder(),
                              ),
                              onChanged: (v) => setState(() {}),
                              validator: (value) {
                                if (value == null || value.isEmpty) return 'مقدار درج کریں';
                                if (double.tryParse(value) == null) return 'صرف نمبر درج کریں';
                                return null;
                              },
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: TextFormField(
                              controller: marketRateController,
                              keyboardType: const TextInputType.numberWithOptions(decimal: true),
                              decoration: const InputDecoration(
                                labelText: 'ریٹ (روپے فی من)',
                                border: OutlineInputBorder(),
                              ),
                              onChanged: (v) => setState(() {}),
                              validator: (value) {
                                if (value == null || value.isEmpty) return 'ریٹ درج کریں';
                                if (double.tryParse(value) == null) return 'صرف نمبر درج کریں';
                                return null;
                              },
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      TextFormField(
                        controller: marketValueController,
                        readOnly: true,
                        decoration: const InputDecoration(
                          labelText: 'مجموعی مارکیٹ ویلیو (روپے)',
                          border: OutlineInputBorder(),
                          fillColor: Color(0xFFF5F5F5),
                          filled: true,
                        ),
                      ),
                      const SizedBox(height: 12),
                      DropdownButtonFormField<String>(
                        isExpanded: true,
                        initialValue: selectedMethod,
                        decoration: const InputDecoration(
                          labelText: 'آبپاشی کا طریقہ (عشر شرح)',
                          border: OutlineInputBorder(),
                        ),
                        items: const [
                          DropdownMenuItem(value: 'Natural', child: Text('قدرتی آبپاشی بارانی (10%)')),
                          DropdownMenuItem(value: 'Artificial', child: Text('مصنوعی آبپاشی ٹیوب ویل/نہر (5%)')),
                          DropdownMenuItem(value: 'Custom', child: Text('کسٹم شرح فیصد')),
                        ],
                        onChanged: (val) {
                          setState(() {
                            selectedMethod = val!;
                            if (selectedMethod == 'Natural') {
                              customPercentageController.text = '10.0';
                            } else if (selectedMethod == 'Artificial') {
                              customPercentageController.text = '5.0';
                            }
                          });
                        },
                      ),
                      if (selectedMethod == 'Custom') ...[
                        const SizedBox(height: 12),
                        TextFormField(
                          controller: customPercentageController,
                          keyboardType: const TextInputType.numberWithOptions(decimal: true),
                          decoration: const InputDecoration(
                            labelText: 'کسٹم شرح فیصد (Percentage)',
                            border: OutlineInputBorder(),
                          ),
                          onChanged: (v) => setState(() {}),
                          validator: (value) {
                            if (value == null || value.isEmpty) return 'فیصد درج کریں';
                            final double? p = double.tryParse(value);
                            if (p == null || p < 0 || p > 100) return 'صحیح فیصد (0-100) درج کریں';
                            return null;
                          },
                        ),
                      ],
                      const Divider(height: 24),
                      // Payment Methods Redesign
                      DropdownButtonFormField<String>(
                        isExpanded: true,
                        initialValue: payMethod,
                        decoration: const InputDecoration(
                          labelText: 'ادائیگی کا طریقہ (Pay Ushr As)',
                          border: OutlineInputBorder(),
                        ),
                        items: const [
                          DropdownMenuItem(value: 'Cash', child: Text('صرف نقد رقم (Cash)')),
                          DropdownMenuItem(value: 'Crop', child: Text('صرف جنس/پیداوار (Crop Produce)')),
                          DropdownMenuItem(value: 'Mixed', child: Text('مخلوط ادائیگی (Crop + Cash)')),
                        ],
                        onChanged: (val) {
                          setState(() {
                            payMethod = val!;
                            if (payMethod == 'Cash') {
                              qtyPaidController.text = '0.0';
                              cashPaidController.text = calculatedUshrAmount.toStringAsFixed(0);
                            } else if (payMethod == 'Crop') {
                              cashPaidController.text = '0.0';
                              qtyPaidController.text = ushrQty.toStringAsFixed(1);
                            } else {
                              qtyPaidController.text = (ushrQty / 2.0).toStringAsFixed(1);
                              cashPaidController.text = (calculatedUshrAmount / 2.0).toStringAsFixed(0);
                            }
                          });
                        },
                      ),
                      const SizedBox(height: 12),
                      if (payMethod == 'Cash' || payMethod == 'Mixed') ...[
                        TextFormField(
                          controller: cashPaidController,
                          keyboardType: TextInputType.number,
                          decoration: const InputDecoration(
                            labelText: 'ادا شدہ نقد رقم (روپے)',
                            border: OutlineInputBorder(),
                          ),
                          onChanged: (v) => setState(() {}),
                        ),
                        const SizedBox(height: 12),
                      ],
                      if (payMethod == 'Crop' || payMethod == 'Mixed') ...[
                        TextFormField(
                          controller: qtyPaidController,
                          keyboardType: const TextInputType.numberWithOptions(decimal: true),
                          decoration: const InputDecoration(
                            labelText: 'ادا شدہ فصل کی مقدار (من)',
                            border: OutlineInputBorder(),
                          ),
                          onChanged: (v) => setState(() {}),
                        ),
                        const SizedBox(height: 12),
                      ],
                      if (status == 'Paid') ...[
                        ListTile(
                          title: Text('تاریخ ادائیگی: ${DateFormat('yyyy-MM-dd').format(selectedDatePaid)}'),
                          trailing: const Icon(Icons.calendar_today),
                          onTap: () async {
                            final date = await showDatePicker(
                              context: context,
                              initialDate: selectedDatePaid,
                              firstDate: DateTime(2020),
                              lastDate: DateTime(2030),
                            );
                            if (date != null) {
                              setState(() {
                                selectedDatePaid = date;
                              });
                            }
                          },
                        ),
                        const SizedBox(height: 12),
                      ],
                      TextFormField(
                        controller: notesController,
                        maxLines: 2,
                        decoration: const InputDecoration(
                          labelText: 'نوٹس / اضافی تفصیلات',
                          border: OutlineInputBorder(),
                        ),
                      ),
                      const SizedBox(height: 16),
                      // Conversion & Calculation display card
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: Colors.green.shade50,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: Colors.green.shade200),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Text(
                              'کل عشر واجب الادا: ${ushrQty.toStringAsFixed(1)} من (من)',
                              style: TextStyle(fontWeight: FontWeight.bold, color: Colors.green.shade900, fontSize: 14),
                              textAlign: TextAlign.center,
                            ),
                            const SizedBox(height: 4),
                            Text(
                              'یا کلوگرام میں: ${ushrQtyKg.toStringAsFixed(0)} KG (کلوگرام)',
                              style: TextStyle(color: Colors.green.shade800, fontSize: 13),
                              textAlign: TextAlign.center,
                            ),
                            const SizedBox(height: 4),
                            Text(
                              'یا نقد رقم میں: Rs. ${calculatedUshrAmount.toStringAsFixed(0)} (روپے)',
                              style: TextStyle(fontWeight: FontWeight.bold, color: Colors.green.shade800, fontSize: 13),
                              textAlign: TextAlign.center,
                            ),
                            const Divider(color: Colors.green),
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Text('کل ادا شدہ قدر:', style: TextStyle(fontSize: 13, color: Colors.green.shade800)),
                                Text('Rs. ${totalPaidPkr.toStringAsFixed(0)}', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.green.shade900)),
                              ],
                            ),
                            if (remainingBalance > 0)
                              Row(
                                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                children: [
                                  const Text('باقی واجب الادا:', style: TextStyle(fontSize: 13, color: Colors.red)),
                                  Text('Rs. ${remainingBalance.toStringAsFixed(0)}', style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.red)),
                                ],
                              )
                            else
                              const Text(
                                'ماشاءاللہ! ادائیگی مکمل ہو گئی ہے۔',
                                style: TextStyle(color: Colors.green, fontWeight: FontWeight.bold, fontSize: 12),
                                textAlign: TextAlign.center,
                              ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(ctx),
                  child: const Text('کینسل'),
                ),
                ElevatedButton(
                  style: ElevatedButton.styleFrom(backgroundColor: Colors.green.shade800, foregroundColor: Colors.white),
                  onPressed: () {
                    if (formKey.currentState!.validate()) {
                      if (existingRecord == null) {
                        ushrProvider.addUshrRecord(
                          cropSeasonId: selectedCropSeasonId!,
                          harvestId: selectedHarvestId,
                          harvestQty: double.parse(qtyController.text),
                          marketValue: marketValue,
                          ushrMethod: selectedMethod,
                          ushrPercentage: percentage,
                          ushrAmount: calculatedUshrAmount,
                          status: status,
                          datePaid: status == 'Paid' ? selectedDatePaid.toIso8601String() : null,
                          notes: notesController.text,
                          payMethod: payMethod,
                          qtyPaid: qtyPaid,
                          cashPaid: cashPaid,
                          remainingBalance: remainingBalance > 0.0 ? remainingBalance : 0.0,
                          ratePerUnit: rate,
                        );
                      } else {
                        ushrProvider.updateUshrRecord(
                          id: existingRecord.id!,
                          cropSeasonId: selectedCropSeasonId!,
                          harvestId: selectedHarvestId ?? existingRecord.harvestId,
                          harvestQty: double.parse(qtyController.text),
                          marketValue: marketValue,
                          ushrMethod: selectedMethod,
                          ushrPercentage: percentage,
                          ushrAmount: calculatedUshrAmount,
                          status: status,
                          datePaid: status == 'Paid' ? selectedDatePaid.toIso8601String() : null,
                          notes: notesController.text,
                          payMethod: payMethod,
                          qtyPaid: qtyPaid,
                          cashPaid: cashPaid,
                          remainingBalance: remainingBalance > 0.0 ? remainingBalance : 0.0,
                          ratePerUnit: rate,
                        );
                      }
                      Navigator.pop(ctx);
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text(existingRecord == null ? 'عشر کامیابی سے شامل ہو گیا!' : 'عشر کا ریکارڈ کامیابی سے تبدیل ہو گیا!')),
                      );
                    }
                  },
                  child: const Text('محفوظ کریں'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  void _confirmDeleteUshr(BuildContext context, int id) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('ریکارڈ حذف کریں؟'),
        content: const Text('کیا آپ واقعی یہ عشر کا ریکارڈ حذف کرنا چاہتے ہیں؟ اس سے متعلقہ لیجر خرچہ بھی حذف ہو جائے گا۔'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('کینسل'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () {
              Provider.of<UshrProvider>(context, listen: false).deleteUshrRecord(id);
              Navigator.pop(ctx);
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('عشر کا ریکارڈ کامیابی سے حذف ہو گیا!')),
              );
            },
            child: const Text('حذف کریں', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }
}
