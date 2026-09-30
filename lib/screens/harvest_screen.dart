import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import '../providers/harvest_provider.dart';
import '../providers/crop_provider.dart';
import '../widgets/empty_state_widget.dart';

class HarvestScreen extends StatefulWidget {
  const HarvestScreen({super.key});

  @override
  State<HarvestScreen> createState() => _HarvestScreenState();
}

class _HarvestScreenState extends State<HarvestScreen> with SingleTickerProviderStateMixin {
  late TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final harvestProvider = Provider.of<HarvestProvider>(context);
    final cropProvider = Provider.of<CropProvider>(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('پیداوار اور فروخت'),
        bottom: TabBar(
          controller: _tabController,
          labelColor: Colors.white,
          unselectedLabelColor: Colors.white70,
          indicatorColor: Colors.white,
          tabs: const [
            Tab(text: 'پیداوار کا ریکارڈ'),
            Tab(text: 'فروخت کا ریکارڈ'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          _buildHarvestList(context, harvestProvider.harvests, cropProvider),
          _buildSalesList(context, harvestProvider.harvests, cropProvider),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _showAddHarvestDialog(context, cropProvider),
        icon: const Icon(Icons.add),
        label: const Text('پیداوار درج کریں'),
        backgroundColor: Colors.orange.shade800,
        foregroundColor: Colors.white,
      ),
    );
  }

  Widget _buildSummaryCards(List<HarvestWithDetails> items) {
    double totalGross = 0.0;
    double totalExpenses = 0.0;
    double totalNet = 0.0;

    for (final item in items) {
      totalGross += item.harvest.grossAmount;
      totalExpenses += item.harvest.totalExpense;
      totalNet += item.harvest.netIncome;
    }

    return Padding(
      padding: const EdgeInsets.only(bottom: 12.0),
      child: Row(
        children: [
          Expanded(
            child: _buildSummaryCard(
              title: 'کل آمدنی',
              value: 'Rs. ${totalGross.toStringAsFixed(0)}',
              color: Colors.green.shade800,
              bgColor: Colors.green.shade50,
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: _buildSummaryCard(
              title: 'کل اخراجات',
              value: 'Rs. ${totalExpenses.toStringAsFixed(0)}',
              color: Colors.red.shade800,
              bgColor: Colors.red.shade50,
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: _buildSummaryCard(
              title: 'خالص آمدنی',
              value: 'Rs. ${totalNet.toStringAsFixed(0)}',
              color: Colors.orange.shade800,
              bgColor: Colors.orange.shade50,
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
          Text(title, style: TextStyle(fontSize: 12, color: color.withValues(alpha: 0.8), fontWeight: FontWeight.bold)),
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

  Widget _buildHarvestList(
    BuildContext context,
    List<HarvestWithDetails> harvests,
    CropProvider cropProvider,
  ) {
    return RefreshIndicator(
      onRefresh: () async {
        await Provider.of<HarvestProvider>(context, listen: false).fetchHarvests();
      },
      child: harvests.isEmpty
          ? SingleChildScrollView(
              physics: const AlwaysScrollableScrollPhysics(),
              child: SizedBox(
                height: MediaQuery.of(context).size.height - kToolbarHeight - kTextTabBarHeight - MediaQuery.of(context).padding.top,
                child: const EmptyStateWidget(
                  message: 'کوئی پیداوار ریکارڈ نہیں ہے',
                  subtitle: 'پیداوار درج کرنے کے لیے نیچے بٹن دبائیں',
                  fallbackIcon: Icons.agriculture,
                  imageAsset: 'assets/images/wheat.png',
                ),
              ),
            )
          : ListView.builder(
              padding: const EdgeInsets.all(12),
              itemCount: harvests.length + 1,
              itemBuilder: (context, index) {
                if (index == 0) {
                  return _buildSummaryCards(harvests);
                }

                final item = harvests[index - 1];
                final h = item.harvest;
                final cropNameUrdu = cropProvider.predefinedCrops[item.cropName] ?? item.cropName;
                final double yieldPerAcre = h.quantity / item.fieldSize;

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
                              '$cropNameUrdu - ${h.quantity.toStringAsFixed(0)} ${h.unit}',
                              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                            ),
                            Text(
                              DateFormat('yyyy-MM-dd').format(DateTime.parse(h.date)),
                              style: const TextStyle(color: Colors.grey, fontSize: 13),
                            ),
                          ],
                        ),
                        const SizedBox(height: 6),
                        Text(
                          'زمین: ${item.farmName} - ${item.fieldName} (${item.fieldSize} ایکڑ)',
                          style: TextStyle(color: Colors.grey.shade800),
                        ),
                        const SizedBox(height: 8),
                        Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                              decoration: BoxDecoration(
                                color: Colors.green.shade50,
                                borderRadius: BorderRadius.circular(8),
                                border: Border.all(color: Colors.green.shade200),
                              ),
                              child: Text(
                                'پیداوار فی ایکڑ: ${yieldPerAcre.toStringAsFixed(1)} ${h.unit} / ایکڑ',
                                style: TextStyle(fontWeight: FontWeight.bold, color: Colors.green.shade800, fontSize: 13),
                              ),
                            ),
                            const Spacer(),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                              decoration: BoxDecoration(
                                color: h.paymentStatus == 'Paid'
                                    ? Colors.green.shade50
                                    : (h.paymentStatus == 'Partial' ? Colors.orange.shade50 : Colors.red.shade50),
                                borderRadius: BorderRadius.circular(8),
                                border: Border.all(
                                  color: h.paymentStatus == 'Paid'
                                      ? Colors.green.shade300
                                      : (h.paymentStatus == 'Partial' ? Colors.orange.shade300 : Colors.red.shade300),
                                ),
                              ),
                              child: Text(
                                h.paymentStatus == 'Paid'
                                    ? 'ادائیگی مکمل (Paid)'
                                    : (h.paymentStatus == 'Partial' ? 'جزوی ادائیگی (Partial)' : 'باقی (Pending)'),
                                style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.bold,
                                  color: h.paymentStatus == 'Paid'
                                      ? Colors.green.shade800
                                      : (h.paymentStatus == 'Partial' ? Colors.orange.shade800 : Colors.red.shade800),
                                ),
                              ),
                            ),
                          ],
                        ),
                        const Divider(height: 24),
                        // Financial Grid
                        Row(
                          children: [
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const Text('کل فروخت', style: TextStyle(fontSize: 12, color: Colors.grey)),
                                  Text('Rs. ${h.grossAmount.toStringAsFixed(0)}', style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.green)),
                                ],
                              ),
                            ),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const Text('کل اخراجات', style: TextStyle(fontSize: 12, color: Colors.grey)),
                                  Text('Rs. ${h.totalExpense.toStringAsFixed(0)}', style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.red)),
                                ],
                              ),
                            ),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const Text('خالص آمدنی', style: TextStyle(fontSize: 12, color: Colors.grey)),
                                  Text(
                                    'Rs. ${h.netIncome.toStringAsFixed(0)}',
                                    style: TextStyle(fontWeight: FontWeight.bold, color: h.netIncome >= 0 ? Colors.green.shade800 : Colors.red.shade800),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                        if (h.ratePerUnit > 0) ...[
                          const SizedBox(height: 8),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text('ریٹ: Rs. ${h.ratePerUnit.toStringAsFixed(0)} فی ${h.unit}', style: const TextStyle(fontSize: 13, color: Colors.blueGrey)),
                              if (h.buyerName != null && h.buyerName!.isNotEmpty)
                                Text('خریدار: ${h.buyerName}', style: const TextStyle(fontSize: 13, color: Colors.blueGrey)),
                            ],
                          ),
                        ],
                        if (h.notes != null && h.notes!.isNotEmpty) ...[
                          const SizedBox(height: 8),
                          Text('نوٹ: ${h.notes}', style: const TextStyle(fontSize: 13, fontStyle: FontStyle.italic, color: Colors.grey)),
                        ],
                        const Divider(height: 24),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            if (h.grossAmount == 0)
                              ElevatedButton.icon(
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: Colors.green,
                                  foregroundColor: Colors.white,
                                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                                ),
                                icon: const Icon(Icons.shopping_cart, size: 16),
                                label: const Text('فروخت درج کریں'),
                                onPressed: () => _showRecordSaleDialog(context, item),
                              )
                            else
                              const SizedBox.shrink(),
                            Row(
                              children: [
                                TextButton.icon(
                                  style: TextButton.styleFrom(foregroundColor: Colors.blueGrey),
                                  icon: const Icon(Icons.edit, size: 16),
                                  label: const Text('تبدیلی'),
                                  onPressed: () => _showEditHarvestDialog(context, item, cropProvider),
                                ),
                                const SizedBox(width: 8),
                                TextButton.icon(
                                  style: TextButton.styleFrom(foregroundColor: Colors.red.shade700),
                                  icon: const Icon(Icons.delete, size: 16),
                                  label: const Text('حذف'),
                                  onPressed: () => _confirmDeleteHarvest(context, h.id!),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
    );
  }

  Widget _buildSalesList(
    BuildContext context,
    List<HarvestWithDetails> harvests,
    CropProvider cropProvider,
  ) {
    final soldItems = harvests.where((item) => item.sale != null).toList();

    return RefreshIndicator(
      onRefresh: () async {
        await Provider.of<HarvestProvider>(context, listen: false).fetchHarvests();
      },
      child: soldItems.isEmpty
          ? SingleChildScrollView(
              physics: const AlwaysScrollableScrollPhysics(),
              child: SizedBox(
                height: MediaQuery.of(context).size.height - kToolbarHeight - kTextTabBarHeight - MediaQuery.of(context).padding.top,
                child: const EmptyStateWidget(
                  message: 'کوئی فروخت ریکارڈ نہیں ہے',
                  subtitle: 'پیداوار ریکارڈ کے کارڈ پر "فروخت درج کریں" دبائیں',
                  fallbackIcon: Icons.shopping_bag,
                  imageAsset: 'assets/images/wheat.png',
                ),
              ),
            )
          : ListView.builder(
              padding: const EdgeInsets.all(12),
              itemCount: soldItems.length,
              itemBuilder: (context, index) {
                final item = soldItems[index];
                final s = item.sale!;
                final cropNameUrdu = cropProvider.predefinedCrops[item.cropName] ?? item.cropName;

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
                              '$cropNameUrdu (فروخت)',
                              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.green),
                            ),
                            Text(
                              DateFormat('yyyy-MM-dd').format(DateTime.parse(s.date)),
                              style: const TextStyle(color: Colors.grey, fontSize: 13),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        Text('زمین: ${item.farmName} - ${item.fieldName}'),
                        const SizedBox(height: 4),
                        Text('مقدار: ${s.quantity.toStringAsFixed(0)} ${item.harvest.unit} | ریٹ: Rs. ${s.pricePerUnit.toStringAsFixed(0)} فی ${item.harvest.unit}'),
                        const Divider(height: 20),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(
                              'کل رقم: Rs. ${s.totalAmount.toStringAsFixed(0)}',
                              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.green),
                            ),
                            Text(
                              'خریدار: ${s.buyerName ?? "عام بازار / نامعلوم"}',
                              style: const TextStyle(color: Colors.grey, fontSize: 13),
                            ),
                          ],
                        ),
                        const Divider(height: 20),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.end,
                          children: [
                            TextButton.icon(
                              style: TextButton.styleFrom(foregroundColor: Colors.blueGrey),
                              icon: const Icon(Icons.edit, size: 16),
                              label: const Text('ترمیم'),
                              onPressed: () => _showEditSaleDialog(context, item),
                            ),
                            const SizedBox(width: 8),
                            TextButton.icon(
                              style: TextButton.styleFrom(foregroundColor: Colors.red),
                              icon: const Icon(Icons.delete, size: 16),
                              label: const Text('حذف'),
                              onPressed: () => _confirmDeleteSale(context, s.id!),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
    );
  }

  void _showAddHarvestDialog(BuildContext context, CropProvider cropProvider) {
    final harvestProvider = Provider.of<HarvestProvider>(context, listen: false);
    final activeSeasons = cropProvider.activeCropSeasons;

    if (activeSeasons.isEmpty) {
      showDialog(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('کوئی فعال فصل نہیں ہے'),
          content: const Text('پیداوار درج کرنے کے لیے پہلے "میری فصلیں" میں جا کر فصل شروع کریں۔'),
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
    int? selectedCropSeasonId = activeSeasons.first.cropSeason.id;
    final qtyController = TextEditingController();
    final rateController = TextEditingController();
    final transController = TextEditingController();
    final labourController = TextEditingController();
    final harvestController = TextEditingController();
    final commissionController = TextEditingController();
    final otherController = TextEditingController();
    final buyerNameController = TextEditingController();
    final notesController = TextEditingController();

    String selectedUnit = 'من';
    String paymentStatus = 'Pending';
    DateTime selectedDate = DateTime.now();

    final List<String> unitsList = ['من', 'کلوگرام', 'ٹن', 'بوری', 'کسٹم'];

    showDialog(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (context, setState) {
            final double qty = double.tryParse(qtyController.text) ?? 0.0;
            final double rate = double.tryParse(rateController.text) ?? 0.0;
            final double trans = double.tryParse(transController.text) ?? 0.0;
            final double labour = double.tryParse(labourController.text) ?? 0.0;
            final double harvesting = double.tryParse(harvestController.text) ?? 0.0;
            final double commission = double.tryParse(commissionController.text) ?? 0.0;
            final double other = double.tryParse(otherController.text) ?? 0.0;

            final double grossAmount = qty * rate;
            final double totalExpense = trans + labour + harvesting + commission + other;
            final double netIncome = grossAmount - totalExpense;

            return AlertDialog(
              title: const Text('پیداوار کا ریکارڈ درج کریں'),
              content: Form(
                key: formKey,
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      DropdownButtonFormField<int>(
                        isExpanded: true,
                        value: selectedCropSeasonId,
                        decoration: const InputDecoration(
                          labelText: 'فصل منتخب کریں',
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
                            selectedCropSeasonId = val;
                          });
                        },
                      ),
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          Expanded(
                            flex: 3,
                            child: TextFormField(
                              controller: qtyController,
                              keyboardType: const TextInputType.numberWithOptions(decimal: true),
                              decoration: const InputDecoration(
                                labelText: 'کل پیداوار کی مقدار',
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
                            flex: 2,
                            child: DropdownButtonFormField<String>(
                              isExpanded: true,
                              value: selectedUnit,
                              decoration: const InputDecoration(
                                labelText: 'اکائی',
                                border: OutlineInputBorder(),
                              ),
                              items: unitsList.map((u) {
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
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          Expanded(
                            child: TextFormField(
                              controller: rateController,
                              keyboardType: const TextInputType.numberWithOptions(decimal: true),
                              decoration: InputDecoration(
                                labelText: 'ریٹ (فی $selectedUnit)',
                                border: const OutlineInputBorder(),
                              ),
                              onChanged: (v) => setState(() {}),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: DropdownButtonFormField<String>(
                              isExpanded: true,
                              value: paymentStatus,
                              decoration: const InputDecoration(
                                labelText: 'ادائیگی کا اسٹیٹس',
                                border: OutlineInputBorder(),
                              ),
                              items: const [
                                DropdownMenuItem(value: 'Paid', child: Text('ادائیگی مکمل (Paid)')),
                                DropdownMenuItem(value: 'Partial', child: Text('جزوی ادائیگی (Partial)')),
                                DropdownMenuItem(value: 'Pending', child: Text('باقی (Pending)')),
                              ],
                              onChanged: (val) {
                                setState(() {
                                  paymentStatus = val!;
                                });
                              },
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      TextFormField(
                        controller: buyerNameController,
                        decoration: const InputDecoration(
                          labelText: 'خریدار کا نام',
                          border: OutlineInputBorder(),
                        ),
                      ),
                      const SizedBox(height: 12),
                      const Align(
                        alignment: Alignment.centerRight,
                        child: Text(
                          'کٹائی کے اخراجات (روپے)',
                          style: TextStyle(fontWeight: FontWeight.bold, color: Colors.brown, fontSize: 14),
                        ),
                      ),
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          Expanded(
                            child: TextFormField(
                              controller: transController,
                              keyboardType: TextInputType.number,
                              decoration: const InputDecoration(
                                labelText: 'ٹرانسپورٹ',
                                border: OutlineInputBorder(),
                              ),
                              onChanged: (v) => setState(() {}),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: TextFormField(
                              controller: labourController,
                              keyboardType: TextInputType.number,
                              decoration: const InputDecoration(
                                labelText: 'مزدوری',
                                border: OutlineInputBorder(),
                              ),
                              onChanged: (v) => setState(() {}),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          Expanded(
                            child: TextFormField(
                              controller: harvestController,
                              keyboardType: TextInputType.number,
                              decoration: const InputDecoration(
                                labelText: 'کٹائی چارجز',
                                border: OutlineInputBorder(),
                              ),
                              onChanged: (v) => setState(() {}),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: TextFormField(
                              controller: commissionController,
                              keyboardType: TextInputType.number,
                              decoration: const InputDecoration(
                                labelText: 'آڑھت/کمیشن',
                                border: OutlineInputBorder(),
                              ),
                              onChanged: (v) => setState(() {}),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      TextFormField(
                        controller: otherController,
                        keyboardType: TextInputType.number,
                        decoration: const InputDecoration(
                          labelText: 'دیگر اخراجات',
                          border: OutlineInputBorder(),
                        ),
                        onChanged: (v) => setState(() {}),
                      ),
                      const SizedBox(height: 12),
                      TextFormField(
                        controller: notesController,
                        maxLines: 2,
                        decoration: const InputDecoration(
                          labelText: 'نوٹس / تفاصیل',
                          border: OutlineInputBorder(),
                        ),
                      ),
                      const SizedBox(height: 12),
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
                      const SizedBox(height: 12),
                      // Realtime Financial Card
                      Card(
                        color: Colors.orange.shade50,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        child: Padding(
                          padding: const EdgeInsets.all(12),
                          child: Column(
                            children: [
                              Row(
                                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                children: [
                                  const Text('کل آمدنی:', style: TextStyle(fontWeight: FontWeight.bold)),
                                  Text('Rs. ${grossAmount.toStringAsFixed(0)}', style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.green)),
                                ],
                              ),
                              const Divider(),
                              Row(
                                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                children: [
                                  const Text('کل اخراجات:', style: TextStyle(fontWeight: FontWeight.bold)),
                                  Text('Rs. ${totalExpense.toStringAsFixed(0)}', style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.red)),
                                ],
                              ),
                              const Divider(),
                              Row(
                                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                children: [
                                  const Text('خالص نفع/نقصان:', style: TextStyle(fontWeight: FontWeight.bold)),
                                  Text(
                                    'Rs. ${netIncome.toStringAsFixed(0)}',
                                    style: TextStyle(
                                      fontWeight: FontWeight.bold,
                                      color: netIncome >= 0 ? Colors.green.shade800 : Colors.red.shade800,
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
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
                  style: ElevatedButton.styleFrom(backgroundColor: Colors.orange.shade800, foregroundColor: Colors.white),
                  onPressed: () {
                    if (formKey.currentState!.validate()) {
                      harvestProvider.addHarvest(
                        cropSeasonId: selectedCropSeasonId!,
                        quantity: double.parse(qtyController.text),
                        unit: selectedUnit,
                        date: selectedDate.toIso8601String(),
                        ratePerUnit: double.tryParse(rateController.text) ?? 0.0,
                        transportationExpense: double.tryParse(transController.text) ?? 0.0,
                        labourExpense: double.tryParse(labourController.text) ?? 0.0,
                        harvestingExpense: double.tryParse(harvestController.text) ?? 0.0,
                        commissionExpense: double.tryParse(commissionController.text) ?? 0.0,
                        otherExpense: double.tryParse(otherController.text) ?? 0.0,
                        buyerName: buyerNameController.text,
                        paymentStatus: paymentStatus,
                        notes: notesController.text,
                      );
                      Navigator.pop(ctx);
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('پیداوار کا ریکارڈ کامیابی سے شامل ہو گیا!')),
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

  void _showEditHarvestDialog(BuildContext context, HarvestWithDetails item, CropProvider cropProvider) {
    final harvestProvider = Provider.of<HarvestProvider>(context, listen: false);
    final formKey = GlobalKey<FormState>();
    final h = item.harvest;
    final activeSeasons = cropProvider.activeCropSeasons;

    int? selectedCropSeasonId = h.cropSeasonId;
    final qtyController = TextEditingController(text: h.quantity.toString());
    final rateController = TextEditingController(text: h.ratePerUnit == 0 ? '' : h.ratePerUnit.toString());
    final transController = TextEditingController(text: h.transportationExpense == 0 ? '' : h.transportationExpense.toString());
    final labourController = TextEditingController(text: h.labourExpense == 0 ? '' : h.labourExpense.toString());
    final harvestController = TextEditingController(text: h.harvestingExpense == 0 ? '' : h.harvestingExpense.toString());
    final commissionController = TextEditingController(text: h.commissionExpense == 0 ? '' : h.commissionExpense.toString());
    final otherController = TextEditingController(text: h.otherExpense == 0 ? '' : h.otherExpense.toString());
    final buyerNameController = TextEditingController(text: h.buyerName ?? '');
    final notesController = TextEditingController(text: h.notes ?? '');

    String selectedUnit = h.unit;
    String paymentStatus = h.paymentStatus;
    DateTime selectedDate = DateTime.parse(h.date);

    final List<String> unitsList = ['من', 'کلوگرام', 'ٹن', 'بوری', 'کسٹم'];

    showDialog(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (context, setState) {
            final double qty = double.tryParse(qtyController.text) ?? 0.0;
            final double rate = double.tryParse(rateController.text) ?? 0.0;
            final double trans = double.tryParse(transController.text) ?? 0.0;
            final double labour = double.tryParse(labourController.text) ?? 0.0;
            final double harvesting = double.tryParse(harvestController.text) ?? 0.0;
            final double commission = double.tryParse(commissionController.text) ?? 0.0;
            final double other = double.tryParse(otherController.text) ?? 0.0;

            final double grossAmount = qty * rate;
            final double totalExpense = trans + labour + harvesting + commission + other;
            final double netIncome = grossAmount - totalExpense;

            return AlertDialog(
              title: const Text('پیداوار کے ریکارڈ میں ترمیم'),
              content: Form(
                key: formKey,
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      DropdownButtonFormField<int>(
                        isExpanded: true,
                        value: selectedCropSeasonId,
                        decoration: const InputDecoration(
                          labelText: 'فصل منتخب کریں',
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
                            selectedCropSeasonId = val;
                          });
                        },
                      ),
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          Expanded(
                            flex: 3,
                            child: TextFormField(
                              controller: qtyController,
                              keyboardType: const TextInputType.numberWithOptions(decimal: true),
                              decoration: const InputDecoration(
                                labelText: 'کل پیداوار کی مقدار',
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
                            flex: 2,
                            child: DropdownButtonFormField<String>(
                              isExpanded: true,
                              value: selectedUnit,
                              decoration: const InputDecoration(
                                labelText: 'اکائی',
                                border: OutlineInputBorder(),
                              ),
                              items: unitsList.map((u) {
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
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          Expanded(
                            child: TextFormField(
                              controller: rateController,
                              keyboardType: const TextInputType.numberWithOptions(decimal: true),
                              decoration: InputDecoration(
                                labelText: 'ریٹ (فی $selectedUnit)',
                                border: const OutlineInputBorder(),
                              ),
                              onChanged: (v) => setState(() {}),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: DropdownButtonFormField<String>(
                              isExpanded: true,
                              value: paymentStatus,
                              decoration: const InputDecoration(
                                labelText: 'ادائیگی کا اسٹیٹس',
                                border: OutlineInputBorder(),
                              ),
                              items: const [
                                DropdownMenuItem(value: 'Paid', child: Text('ادائیگی مکمل (Paid)')),
                                DropdownMenuItem(value: 'Partial', child: Text('جزوی ادائیگی (Partial)')),
                                DropdownMenuItem(value: 'Pending', child: Text('باقی (Pending)')),
                              ],
                              onChanged: (val) {
                                setState(() {
                                  paymentStatus = val!;
                                });
                              },
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      TextFormField(
                        controller: buyerNameController,
                        decoration: const InputDecoration(
                          labelText: 'خریدار کا نام',
                          border: OutlineInputBorder(),
                        ),
                      ),
                      const SizedBox(height: 12),
                      const Align(
                        alignment: Alignment.centerRight,
                        child: Text(
                          'کٹائی کے اخراجات (روپے)',
                          style: TextStyle(fontWeight: FontWeight.bold, color: Colors.brown, fontSize: 14),
                        ),
                      ),
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          Expanded(
                            child: TextFormField(
                              controller: transController,
                              keyboardType: TextInputType.number,
                              decoration: const InputDecoration(
                                labelText: 'ٹرانسپورٹ',
                                border: OutlineInputBorder(),
                              ),
                              onChanged: (v) => setState(() {}),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: TextFormField(
                              controller: labourController,
                              keyboardType: TextInputType.number,
                              decoration: const InputDecoration(
                                labelText: 'مزدوری',
                                border: OutlineInputBorder(),
                              ),
                              onChanged: (v) => setState(() {}),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          Expanded(
                            child: TextFormField(
                              controller: harvestController,
                              keyboardType: TextInputType.number,
                              decoration: const InputDecoration(
                                labelText: 'کٹائی چارجز',
                                border: OutlineInputBorder(),
                              ),
                              onChanged: (v) => setState(() {}),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: TextFormField(
                              controller: commissionController,
                              keyboardType: TextInputType.number,
                              decoration: const InputDecoration(
                                labelText: 'آڑھت/کمیشن',
                                border: OutlineInputBorder(),
                              ),
                              onChanged: (v) => setState(() {}),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      TextFormField(
                        controller: otherController,
                        keyboardType: TextInputType.number,
                        decoration: const InputDecoration(
                          labelText: 'دیگر اخراجات',
                          border: OutlineInputBorder(),
                        ),
                        onChanged: (v) => setState(() {}),
                      ),
                      const SizedBox(height: 12),
                      TextFormField(
                        controller: notesController,
                        maxLines: 2,
                        decoration: const InputDecoration(
                          labelText: 'نوٹس / تفاصیل',
                          border: OutlineInputBorder(),
                        ),
                      ),
                      const SizedBox(height: 12),
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
                      const SizedBox(height: 12),
                      Card(
                        color: Colors.orange.shade50,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        child: Padding(
                          padding: const EdgeInsets.all(12),
                          child: Column(
                            children: [
                              Row(
                                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                children: [
                                  const Text('کل آمدنی:', style: TextStyle(fontWeight: FontWeight.bold)),
                                  Text('Rs. ${grossAmount.toStringAsFixed(0)}', style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.green)),
                                ],
                              ),
                              const Divider(),
                              Row(
                                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                children: [
                                  const Text('کل اخراجات:', style: TextStyle(fontWeight: FontWeight.bold)),
                                  Text('Rs. ${totalExpense.toStringAsFixed(0)}', style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.red)),
                                ],
                              ),
                              const Divider(),
                              Row(
                                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                children: [
                                  const Text('خالص نفع/نقصان:', style: TextStyle(fontWeight: FontWeight.bold)),
                                  Text(
                                    'Rs. ${netIncome.toStringAsFixed(0)}',
                                    style: TextStyle(
                                      fontWeight: FontWeight.bold,
                                      color: netIncome >= 0 ? Colors.green.shade800 : Colors.red.shade800,
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
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
                  style: ElevatedButton.styleFrom(backgroundColor: Colors.orange.shade800, foregroundColor: Colors.white),
                  onPressed: () {
                    if (formKey.currentState!.validate()) {
                      harvestProvider.updateHarvest(
                        id: h.id!,
                        cropSeasonId: selectedCropSeasonId!,
                        quantity: double.parse(qtyController.text),
                        unit: selectedUnit,
                        date: selectedDate.toIso8601String(),
                        ratePerUnit: double.tryParse(rateController.text) ?? 0.0,
                        transportationExpense: double.tryParse(transController.text) ?? 0.0,
                        labourExpense: double.tryParse(labourController.text) ?? 0.0,
                        harvestingExpense: double.tryParse(harvestController.text) ?? 0.0,
                        commissionExpense: double.tryParse(commissionController.text) ?? 0.0,
                        otherExpense: double.tryParse(otherController.text) ?? 0.0,
                        buyerName: buyerNameController.text,
                        paymentStatus: paymentStatus,
                        notes: notesController.text,
                      );
                      Navigator.pop(ctx);
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('پیداوار کا ریکارڈ کامیابی سے تبدیل ہو گیا!')),
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

  void _showRecordSaleDialog(BuildContext context, HarvestWithDetails item) {
    final harvestProvider = Provider.of<HarvestProvider>(context, listen: false);
    final formKey = GlobalKey<FormState>();

    final priceController = TextEditingController();
    final buyerController = TextEditingController();
    double totalAmount = 0.0;
    DateTime selectedDate = DateTime.now();

    showDialog(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (context, setState) {
            return AlertDialog(
              title: Text('پیداوار فروخت کریں (${item.harvest.quantity} ${item.harvest.unit})'),
              content: Form(
                key: formKey,
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      TextFormField(
                        controller: priceController,
                        keyboardType: const TextInputType.numberWithOptions(decimal: true),
                        decoration: InputDecoration(
                          labelText: 'ریٹ فی ${item.harvest.unit} (روپے)',
                          border: const OutlineInputBorder(),
                        ),
                        validator: (value) {
                          if (value == null || value.isEmpty) return 'ریٹ درج کریں';
                          if (double.tryParse(value) == null) return 'صرف نمبر درج کریں';
                          return null;
                        },
                        onChanged: (val) {
                          final double? price = double.tryParse(val);
                          if (price != null) {
                            setState(() {
                              totalAmount = price * item.harvest.quantity;
                            });
                          }
                        },
                      ),
                      const SizedBox(height: 16),
                      TextFormField(
                        controller: buyerController,
                        decoration: const InputDecoration(
                          labelText: 'خریدار کا نام (آپشنل)',
                          border: OutlineInputBorder(),
                        ),
                      ),
                      const SizedBox(height: 16),
                      ListTile(
                        title: Text('تاریخ فروخت: ${DateFormat('yyyy-MM-dd').format(selectedDate)}'),
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
                      const SizedBox(height: 16),
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: Colors.blue.shade50,
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: Colors.blue.shade200),
                        ),
                        child: Text(
                          'کل رقم: ${totalAmount.toStringAsFixed(0)} روپے',
                          style: TextStyle(fontWeight: FontWeight.bold, color: Colors.blue.shade800, fontSize: 16),
                          textAlign: TextAlign.center,
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
                  style: ElevatedButton.styleFrom(backgroundColor: Colors.green, foregroundColor: Colors.white),
                  onPressed: () {
                    if (formKey.currentState!.validate()) {
                      harvestProvider.recordSale(
                        harvestId: item.harvest.id!,
                        quantity: item.harvest.quantity,
                        pricePerUnit: double.parse(priceController.text),
                        totalAmount: totalAmount,
                        date: selectedDate.toIso8601String(),
                        buyerName: buyerController.text,
                      );
                      Navigator.pop(ctx);
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

  void _showEditSaleDialog(BuildContext context, HarvestWithDetails item) {
    final harvestProvider = Provider.of<HarvestProvider>(context, listen: false);
    final formKey = GlobalKey<FormState>();
    final sale = item.sale!;

    final priceController = TextEditingController(text: sale.pricePerUnit.toString());
    final buyerController = TextEditingController(text: sale.buyerName ?? '');
    double totalAmount = sale.totalAmount;
    DateTime selectedDate = DateTime.parse(sale.date);

    showDialog(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (context, setState) {
            return AlertDialog(
              title: Text('فروخت کے ریکارڈ میں تبدیلی (${item.harvest.quantity} ${item.harvest.unit})'),
              content: Form(
                key: formKey,
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      TextFormField(
                        controller: priceController,
                        keyboardType: const TextInputType.numberWithOptions(decimal: true),
                        decoration: InputDecoration(
                          labelText: 'ریٹ فی ${item.harvest.unit} (روپے)',
                          border: const OutlineInputBorder(),
                        ),
                        validator: (value) {
                          if (value == null || value.isEmpty) return 'ریٹ درج کریں';
                          if (double.tryParse(value) == null) return 'صرف نمبر درج کریں';
                          return null;
                        },
                        onChanged: (val) {
                          final double? price = double.tryParse(val);
                          if (price != null) {
                            setState(() {
                              totalAmount = price * item.harvest.quantity;
                            });
                          }
                        },
                      ),
                      const SizedBox(height: 16),
                      TextFormField(
                        controller: buyerController,
                        decoration: const InputDecoration(
                          labelText: 'خریدار کا نام (آپشنل)',
                          border: OutlineInputBorder(),
                        ),
                      ),
                      const SizedBox(height: 16),
                      ListTile(
                        title: Text('تاریخ فروخت: ${DateFormat('yyyy-MM-dd').format(selectedDate)}'),
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
                      const SizedBox(height: 16),
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: Colors.blue.shade50,
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: Colors.blue.shade200),
                        ),
                        child: Text(
                          'کل رقم: ${totalAmount.toStringAsFixed(0)} روپے',
                          style: TextStyle(fontWeight: FontWeight.bold, color: Colors.blue.shade800, fontSize: 16),
                          textAlign: TextAlign.center,
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
                  onPressed: () {
                    if (formKey.currentState!.validate()) {
                      harvestProvider.updateSale(
                        id: sale.id!,
                        harvestId: item.harvest.id!,
                        quantity: item.harvest.quantity,
                        pricePerUnit: double.parse(priceController.text),
                        totalAmount: totalAmount,
                        date: selectedDate.toIso8601String(),
                        buyerName: buyerController.text,
                      );
                      Navigator.pop(ctx);
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('فروخت کا ریکارڈ کامیابی سے تبدیل ہو گیا!')),
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

  void _confirmDeleteSale(BuildContext context, int id) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('فروخت حذف کریں؟'),
        content: const Text('کیا آپ واقعی یہ فروخت کا ریکارڈ حذف کرنا چاہتے ہیں؟ اس سے پیداوار کا بنیادی ریکارڈ حذف نہیں ہوگا۔'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('کینسل'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () {
              Provider.of<HarvestProvider>(context, listen: false).deleteSale(id);
              Navigator.pop(ctx);
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('فروخت کا ریکارڈ کامیابی سے حذف ہو گیا!')),
              );
            },
            child: const Text('حذف کریں', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }

  void _confirmDeleteHarvest(BuildContext context, int id) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('پیداوار حذف کریں؟'),
        content: const Text('کیا آپ واقعی یہ پیداوار اور اس کی تمام فروخت کی معلومات حذف کرنا چاہتے ہیں؟'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('کینسل'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () {
              Provider.of<HarvestProvider>(context, listen: false).deleteHarvest(id);
              Navigator.pop(ctx);
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('پیداوار کامیابی سے حذف ہو گئی!')),
              );
            },
            child: const Text('حذف کریں', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }
}
