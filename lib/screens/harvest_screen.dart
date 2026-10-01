import 'package:flutter/material.dart';
import '../widgets/digit_text.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import '../providers/harvest_provider.dart';
import '../providers/crop_provider.dart';
import '../widgets/empty_state_widget.dart';
import '../services/money.dart';
import '../services/quantity.dart';
import '../services/unit_display.dart';
import '../l10n/strings.dart';

class HarvestScreen extends StatefulWidget {
  const HarvestScreen({super.key});

  @override
  State<HarvestScreen> createState() => _HarvestScreenState();
}

class _HarvestScreenState extends State<HarvestScreen>
    with SingleTickerProviderStateMixin {
  /// Parses an optional money field: blank means 0 paisa; garbage throws
  /// [MoneyParseException] (Urdu message, safe for a SnackBar).
  int _parsePaisaOrThrow(String text) {
    if (text.trim().isEmpty) return 0;
    return Money.parse(text).paisa;
  }

  /// Lenient parse for live-preview cards: blank or garbage shows as 0 paisa.
  int _parsePaisaOrZero(String text) {
    try {
      return _parsePaisaOrThrow(text);
    } on MoneyParseException {
      return 0;
    }
  }

  /// Lenient parse returning null on blank or garbage (for onChanged previews).
  int? _tryPaisa(String text) {
    if (text.trim().isEmpty) return null;
    try {
      return Money.parse(text).paisa;
    } on MoneyParseException {
      return null;
    }
  }

  /// Shows an Urdu money-parse error without closing the dialog.
  void _showMoneyError(BuildContext ctx, MoneyParseException e) {
    ScaffoldMessenger.of(ctx).showSnackBar(
      SnackBar(content: Text(e.message), backgroundColor: Colors.red),
    );
  }

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
    int totalGrossPaisa = 0;
    int totalExpensesPaisa = 0;
    int totalNetPaisa = 0;

    for (final item in items) {
      totalGrossPaisa += item.harvest.grossPaisa;
      totalExpensesPaisa += item.harvest.totalExpensePaisa;
      totalNetPaisa += item.harvest.netIncomePaisa;
    }

    return Padding(
      padding: const EdgeInsets.only(bottom: 12.0),
      child: Row(
        children: [
          Expanded(
            child: _buildSummaryCard(
              title: 'کل آمدنی',
              value: Money(totalGrossPaisa).format(),
              color: Colors.green.shade800,
              bgColor: Colors.green.shade50,
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: _buildSummaryCard(
              title: 'کل اخراجات',
              value: Money(totalExpensesPaisa).format(),
              color: Colors.red.shade800,
              bgColor: Colors.red.shade50,
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: _buildSummaryCard(
              title: 'خالص آمدنی',
              value: Money(totalNetPaisa).format(),
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
          Text(
            title,
            style: TextStyle(
              fontSize: 12,
              color: color.withValues(alpha: 0.8),
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 4),
          FittedBox(
            fit: BoxFit.scaleDown,
            child: DigitText(
              value,
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
                color: color,
              ),
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
        await Provider.of<HarvestProvider>(
          context,
          listen: false,
        ).fetchHarvests();
      },
      child:
          harvests.isEmpty
              ? SingleChildScrollView(
                physics: const AlwaysScrollableScrollPhysics(),
                child: SizedBox(
                  height:
                      MediaQuery.of(context).size.height -
                      kToolbarHeight -
                      kTextTabBarHeight -
                      MediaQuery.of(context).padding.top,
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
                  final cropNameUrdu =
                      cropProvider.predefinedCrops[item.cropName] ??
                      item.cropName;
                  final double yieldPerAcre = h.quantity / item.fieldSize;

                  return Card(
                    elevation: 2,
                    margin: const EdgeInsets.only(bottom: 12),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
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
                                style: const TextStyle(
                                  fontSize: 18,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              Text(
                                DateFormat(
                                  'yyyy-MM-dd',
                                ).format(DateTime.parse(h.date)),
                                style: const TextStyle(
                                  color: Colors.grey,
                                  fontSize: 13,
                                ),
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
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 10,
                                  vertical: 4,
                                ),
                                decoration: BoxDecoration(
                                  color: Colors.green.shade50,
                                  borderRadius: BorderRadius.circular(8),
                                  border: Border.all(
                                    color: Colors.green.shade200,
                                  ),
                                ),
                                child: Text(
                                  'پیداوار فی ایکڑ: ${yieldPerAcre.toStringAsFixed(1)} ${h.unit} / ایکڑ',
                                  style: TextStyle(
                                    fontWeight: FontWeight.bold,
                                    color: Colors.green.shade800,
                                    fontSize: 13,
                                  ),
                                ),
                              ),
                              const Spacer(),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 8,
                                  vertical: 4,
                                ),
                                decoration: BoxDecoration(
                                  color:
                                      h.paymentStatus == 'Paid'
                                          ? Colors.green.shade50
                                          : (h.paymentStatus == 'Partial'
                                              ? Colors.orange.shade50
                                              : Colors.red.shade50),
                                  borderRadius: BorderRadius.circular(8),
                                  border: Border.all(
                                    color:
                                        h.paymentStatus == 'Paid'
                                            ? Colors.green.shade300
                                            : (h.paymentStatus == 'Partial'
                                                ? Colors.orange.shade300
                                                : Colors.red.shade300),
                                  ),
                                ),
                                child: Text(
                                  h.paymentStatus == 'Paid'
                                      ? 'ادائیگی مکمل (Paid)'
                                      : (h.paymentStatus == 'Partial'
                                          ? 'جزوی ادائیگی (Partial)'
                                          : 'باقی (Pending)'),
                                  style: TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.bold,
                                    color:
                                        h.paymentStatus == 'Paid'
                                            ? Colors.green.shade800
                                            : (h.paymentStatus == 'Partial'
                                                ? Colors.orange.shade800
                                                : Colors.red.shade800),
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
                                    const Text(
                                      'کل فروخت',
                                      style: TextStyle(
                                        fontSize: 12,
                                        color: Colors.grey,
                                      ),
                                    ),
                                    DigitText(
                                      Money(h.grossPaisa).format(),
                                      style: const TextStyle(
                                        fontWeight: FontWeight.bold,
                                        color: Colors.green,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    const Text(
                                      'کل اخراجات',
                                      style: TextStyle(
                                        fontSize: 12,
                                        color: Colors.grey,
                                      ),
                                    ),
                                    DigitText(
                                      Money(h.totalExpensePaisa).format(),
                                      style: const TextStyle(
                                        fontWeight: FontWeight.bold,
                                        color: Colors.red,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    const Text(
                                      'خالص آمدنی',
                                      style: TextStyle(
                                        fontSize: 12,
                                        color: Colors.grey,
                                      ),
                                    ),
                                    DigitText(
                                      Money(h.netIncomePaisa).format(),
                                      style: TextStyle(
                                        fontWeight: FontWeight.bold,
                                        color:
                                            h.netIncomePaisa >= 0
                                                ? Colors.green.shade800
                                                : Colors.red.shade800,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                          if (h.ratePerUnitPaisa > 0) ...[
                            const SizedBox(height: 8),
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Text(
                                  'ریٹ: ${Money(h.ratePerUnitPaisa).format()} فی ${h.unit}',
                                  style: const TextStyle(
                                    fontSize: 13,
                                    color: Colors.blueGrey,
                                  ),
                                ),
                                if (h.buyerName != null &&
                                    h.buyerName!.isNotEmpty)
                                  Text(
                                    'خریدار: ${h.buyerName}',
                                    style: const TextStyle(
                                      fontSize: 13,
                                      color: Colors.blueGrey,
                                    ),
                                  ),
                              ],
                            ),
                          ],
                          if (h.notes != null && h.notes!.isNotEmpty) ...[
                            const SizedBox(height: 8),
                            Text(
                              'نوٹ: ${h.notes}',
                              style: const TextStyle(
                                fontSize: 13,
                                fontStyle: FontStyle.italic,
                                color: Colors.grey,
                              ),
                            ),
                          ],
                          const Divider(height: 24),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              if (h.grossPaisa == 0)
                                ElevatedButton.icon(
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: Colors.green,
                                    foregroundColor: Colors.white,
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 12,
                                      vertical: 8,
                                    ),
                                  ),
                                  icon: const Icon(
                                    Icons.shopping_cart,
                                    size: 16,
                                  ),
                                  label: const Text('فروخت درج کریں'),
                                  onPressed:
                                      () =>
                                          _showRecordSaleDialog(context, item),
                                )
                              else
                                const SizedBox.shrink(),
                              Row(
                                children: [
                                  TextButton.icon(
                                    style: TextButton.styleFrom(
                                      foregroundColor: Colors.blueGrey,
                                    ),
                                    icon: const Icon(Icons.edit, size: 16),
                                    label: const Text('تبدیلی'),
                                    onPressed:
                                        () => _showEditHarvestDialog(
                                          context,
                                          item,
                                          cropProvider,
                                        ),
                                  ),
                                  const SizedBox(width: 8),
                                  TextButton.icon(
                                    style: TextButton.styleFrom(
                                      foregroundColor: Colors.red.shade700,
                                    ),
                                    icon: const Icon(Icons.delete, size: 16),
                                    label: const Text('حذف'),
                                    onPressed:
                                        () => _confirmDeleteHarvest(
                                          context,
                                          h.id!,
                                        ),
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
        await Provider.of<HarvestProvider>(
          context,
          listen: false,
        ).fetchHarvests();
      },
      child:
          soldItems.isEmpty
              ? SingleChildScrollView(
                physics: const AlwaysScrollableScrollPhysics(),
                child: SizedBox(
                  height:
                      MediaQuery.of(context).size.height -
                      kToolbarHeight -
                      kTextTabBarHeight -
                      MediaQuery.of(context).padding.top,
                  child: const EmptyStateWidget(
                    message: 'کوئی فروخت ریکارڈ نہیں ہے',
                    subtitle:
                        'پیداوار ریکارڈ کے کارڈ پر "فروخت درج کریں" دبائیں',
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
                  final cropNameUrdu =
                      cropProvider.predefinedCrops[item.cropName] ??
                      item.cropName;

                  return Card(
                    elevation: 2,
                    margin: const EdgeInsets.only(bottom: 12),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
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
                                style: const TextStyle(
                                  fontSize: 18,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.green,
                                ),
                              ),
                              Text(
                                DateFormat(
                                  'yyyy-MM-dd',
                                ).format(DateTime.parse(s.date)),
                                style: const TextStyle(
                                  color: Colors.grey,
                                  fontSize: 13,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 8),
                          Text('زمین: ${item.farmName} - ${item.fieldName}'),
                          const SizedBox(height: 4),
                          Text(
                            'مقدار: ${s.quantity.toStringAsFixed(0)} ${item.harvest.unit} | ریٹ: ${Money(s.pricePerUnitPaisa).format()} فی ${item.harvest.unit}',
                          ),
                          const Divider(height: 20),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              DigitText(
                                Money(s.totalAmountPaisa).format(),
                                style: const TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.green,
                                ),
                              ),
                              Text(
                                'خریدار: ${s.buyerName ?? "عام بازار / نامعلوم"}',
                                style: const TextStyle(
                                  color: Colors.grey,
                                  fontSize: 13,
                                ),
                              ),
                            ],
                          ),
                          const Divider(height: 20),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.end,
                            children: [
                              TextButton.icon(
                                style: TextButton.styleFrom(
                                  foregroundColor: Colors.blueGrey,
                                ),
                                icon: const Icon(Icons.edit, size: 16),
                                label: const Text('ترمیم'),
                                onPressed:
                                    () => _showEditSaleDialog(context, item),
                              ),
                              const SizedBox(width: 8),
                              TextButton.icon(
                                style: TextButton.styleFrom(
                                  foregroundColor: Colors.red,
                                ),
                                icon: const Icon(Icons.delete, size: 16),
                                label: const Text('حذف'),
                                onPressed:
                                    () => _confirmDeleteSale(context, s.id!),
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
    final harvestProvider = Provider.of<HarvestProvider>(
      context,
      listen: false,
    );
    final activeSeasons = cropProvider.activeCropSeasons;

    if (activeSeasons.isEmpty) {
      showDialog(
        context: context,
        builder:
            (ctx) => AlertDialog(
              title: const Text('کوئی فعال فصل نہیں ہے'),
              content: const Text(
                'پیداوار درج کرنے کے لیے پہلے "میری فصلیں" میں جا کر فصل شروع کریں۔',
              ),
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

    final List<String> unitsList = UnitDisplay.allUnits;

    showDialog(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (context, setState) {
            final double qty = Quantity.tryParse(qtyController.text) ?? 0.0;
            final int ratePaisa = _parsePaisaOrZero(rateController.text);
            final int transPaisa = _parsePaisaOrZero(transController.text);
            final int labourPaisa = _parsePaisaOrZero(labourController.text);
            final int harvestingPaisa = _parsePaisaOrZero(
              harvestController.text,
            );
            final int commissionPaisa = _parsePaisaOrZero(
              commissionController.text,
            );
            final int otherPaisa = _parsePaisaOrZero(otherController.text);

            final int grossPaisa = (qty * ratePaisa).round();
            final int totalExpensePaisa =
                transPaisa +
                labourPaisa +
                harvestingPaisa +
                commissionPaisa +
                otherPaisa;
            final int netIncomePaisa = grossPaisa - totalExpensePaisa;

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
                          labelText: Strings.selectCrop,
                          border: OutlineInputBorder(),
                        ),
                        items:
                            activeSeasons.map((details) {
                              final season = details.cropSeason;
                              final nameUrdu =
                                  cropProvider.predefinedCrops[season
                                      .cropName] ??
                                  season.cropName;
                              return DropdownMenuItem<int>(
                                value: season.id,
                                child: Text(
                                  '${details.farmDisplayName} - ${details.fieldDisplayName} ($nameUrdu - ${season.variety})',
                                ),
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
                              keyboardType:
                                  const TextInputType.numberWithOptions(
                                    decimal: true,
                                  ),
                              decoration: const InputDecoration(
                                labelText: 'کل پیداوار کی مقدار',
                                border: OutlineInputBorder(),
                              ),
                              onChanged: (v) => setState(() {}),
                              validator: (value) {
                                if (value == null || value.isEmpty) {
                                  return Strings.quantityRequired;
                                }
                                try {
                                  Quantity.parsePositive(value);
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
                              isExpanded: true,
                              value: selectedUnit,
                              decoration: const InputDecoration(
                                labelText: 'اکائی',
                                border: OutlineInputBorder(),
                              ),
                              items:
                                  unitsList.map((u) {
                                    return DropdownMenuItem(
                                      value: u,
                                      child: Text(u),
                                    );
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
                              keyboardType:
                                  const TextInputType.numberWithOptions(
                                    decimal: true,
                                  ),
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
                                DropdownMenuItem(
                                  value: 'Paid',
                                  child: Text('ادائیگی مکمل (Paid)'),
                                ),
                                DropdownMenuItem(
                                  value: 'Partial',
                                  child: Text('جزوی ادائیگی (Partial)'),
                                ),
                                DropdownMenuItem(
                                  value: 'Pending',
                                  child: Text('باقی (Pending)'),
                                ),
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
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            color: Colors.brown,
                            fontSize: 14,
                          ),
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
                      const SizedBox(height: 12),
                      // Realtime Financial Card
                      Card(
                        color: Colors.orange.shade50,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Padding(
                          padding: const EdgeInsets.all(12),
                          child: Column(
                            children: [
                              Row(
                                mainAxisAlignment:
                                    MainAxisAlignment.spaceBetween,
                                children: [
                                  const Text(
                                    'کل آمدنی:',
                                    style: TextStyle(
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                  DigitText(
                                    Money(grossPaisa).format(),
                                    style: const TextStyle(
                                      fontWeight: FontWeight.bold,
                                      color: Colors.green,
                                    ),
                                  ),
                                ],
                              ),
                              const Divider(),
                              Row(
                                mainAxisAlignment:
                                    MainAxisAlignment.spaceBetween,
                                children: [
                                  const Text(
                                    'کل اخراجات:',
                                    style: TextStyle(
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                  DigitText(
                                    Money(totalExpensePaisa).format(),
                                    style: const TextStyle(
                                      fontWeight: FontWeight.bold,
                                      color: Colors.red,
                                    ),
                                  ),
                                ],
                              ),
                              const Divider(),
                              Row(
                                mainAxisAlignment:
                                    MainAxisAlignment.spaceBetween,
                                children: [
                                  const Text(
                                    'خالص نفع/نقصان:',
                                    style: TextStyle(
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                  DigitText(
                                    Money(netIncomePaisa).format(),
                                    style: TextStyle(
                                      fontWeight: FontWeight.bold,
                                      color:
                                          netIncomePaisa >= 0
                                              ? Colors.green.shade800
                                              : Colors.red.shade800,
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
                  child: const Text(Strings.cancel),
                ),
                ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.orange.shade800,
                    foregroundColor: Colors.white,
                  ),
                  onPressed: () {
                    if (formKey.currentState!.validate()) {
                      final int ratePaisa;
                      final int transPaisa;
                      final int labourPaisa;
                      final int harvestingPaisa;
                      final int commissionPaisa;
                      final int otherPaisa;
                      try {
                        ratePaisa = _parsePaisaOrThrow(rateController.text);
                        transPaisa = _parsePaisaOrThrow(transController.text);
                        labourPaisa = _parsePaisaOrThrow(labourController.text);
                        harvestingPaisa = _parsePaisaOrThrow(
                          harvestController.text,
                        );
                        commissionPaisa = _parsePaisaOrThrow(
                          commissionController.text,
                        );
                        otherPaisa = _parsePaisaOrThrow(otherController.text);
                      } on MoneyParseException catch (e) {
                        _showMoneyError(ctx, e);
                        return;
                      }
                      harvestProvider.addHarvest(
                        cropSeasonId: selectedCropSeasonId!,
                        quantity: Quantity.parsePositive(qtyController.text),
                        unit: selectedUnit,
                        date: selectedDate.toIso8601String(),
                        ratePerUnitPaisa: ratePaisa,
                        transportationExpensePaisa: transPaisa,
                        labourExpensePaisa: labourPaisa,
                        harvestingExpensePaisa: harvestingPaisa,
                        commissionExpensePaisa: commissionPaisa,
                        otherExpensePaisa: otherPaisa,
                        buyerName: buyerNameController.text,
                        paymentStatus: paymentStatus,
                        notes: notesController.text,
                      );
                      Navigator.pop(ctx);
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text(
                            'پیداوار کا ریکارڈ کامیابی سے شامل ہو گیا!',
                          ),
                        ),
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

  void _showEditHarvestDialog(
    BuildContext context,
    HarvestWithDetails item,
    CropProvider cropProvider,
  ) {
    final harvestProvider = Provider.of<HarvestProvider>(
      context,
      listen: false,
    );
    final formKey = GlobalKey<FormState>();
    final h = item.harvest;
    final activeSeasons = cropProvider.activeCropSeasons;

    int? selectedCropSeasonId = h.cropSeasonId;
    final qtyController = TextEditingController(text: h.quantity.toString());
    final rateController = TextEditingController(
      text: h.ratePerUnitPaisa == 0 ? '' : Money(h.ratePerUnitPaisa).format(),
    );
    final transController = TextEditingController(
      text:
          h.transportationExpensePaisa == 0
              ? ''
              : Money(h.transportationExpensePaisa).format(),
    );
    final labourController = TextEditingController(
      text:
          h.labourExpensePaisa == 0 ? '' : Money(h.labourExpensePaisa).format(),
    );
    final harvestController = TextEditingController(
      text:
          h.harvestingExpensePaisa == 0
              ? ''
              : Money(h.harvestingExpensePaisa).format(),
    );
    final commissionController = TextEditingController(
      text:
          h.commissionExpensePaisa == 0
              ? ''
              : Money(h.commissionExpensePaisa).format(),
    );
    final otherController = TextEditingController(
      text: h.otherExpensePaisa == 0 ? '' : Money(h.otherExpensePaisa).format(),
    );
    final buyerNameController = TextEditingController(text: h.buyerName ?? '');
    final notesController = TextEditingController(text: h.notes ?? '');

    String selectedUnit = h.unit;
    String paymentStatus = h.paymentStatus;
    DateTime selectedDate = DateTime.parse(h.date);

    final List<String> unitsList = UnitDisplay.allUnits;

    showDialog(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (context, setState) {
            final double qty = Quantity.tryParse(qtyController.text) ?? 0.0;
            final int ratePaisa = _parsePaisaOrZero(rateController.text);
            final int transPaisa = _parsePaisaOrZero(transController.text);
            final int labourPaisa = _parsePaisaOrZero(labourController.text);
            final int harvestingPaisa = _parsePaisaOrZero(
              harvestController.text,
            );
            final int commissionPaisa = _parsePaisaOrZero(
              commissionController.text,
            );
            final int otherPaisa = _parsePaisaOrZero(otherController.text);

            final int grossPaisa = (qty * ratePaisa).round();
            final int totalExpensePaisa =
                transPaisa +
                labourPaisa +
                harvestingPaisa +
                commissionPaisa +
                otherPaisa;
            final int netIncomePaisa = grossPaisa - totalExpensePaisa;

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
                          labelText: Strings.selectCrop,
                          border: OutlineInputBorder(),
                        ),
                        items:
                            activeSeasons.map((details) {
                              final season = details.cropSeason;
                              final nameUrdu =
                                  cropProvider.predefinedCrops[season
                                      .cropName] ??
                                  season.cropName;
                              return DropdownMenuItem<int>(
                                value: season.id,
                                child: Text(
                                  '${details.farmDisplayName} - ${details.fieldDisplayName} ($nameUrdu - ${season.variety})',
                                ),
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
                              keyboardType:
                                  const TextInputType.numberWithOptions(
                                    decimal: true,
                                  ),
                              decoration: const InputDecoration(
                                labelText: 'کل پیداوار کی مقدار',
                                border: OutlineInputBorder(),
                              ),
                              onChanged: (v) => setState(() {}),
                              validator: (value) {
                                if (value == null || value.isEmpty) {
                                  return Strings.quantityRequired;
                                }
                                try {
                                  Quantity.parsePositive(value);
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
                              isExpanded: true,
                              value: selectedUnit,
                              decoration: const InputDecoration(
                                labelText: 'اکائی',
                                border: OutlineInputBorder(),
                              ),
                              items:
                                  unitsList.map((u) {
                                    return DropdownMenuItem(
                                      value: u,
                                      child: Text(u),
                                    );
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
                              keyboardType:
                                  const TextInputType.numberWithOptions(
                                    decimal: true,
                                  ),
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
                                DropdownMenuItem(
                                  value: 'Paid',
                                  child: Text('ادائیگی مکمل (Paid)'),
                                ),
                                DropdownMenuItem(
                                  value: 'Partial',
                                  child: Text('جزوی ادائیگی (Partial)'),
                                ),
                                DropdownMenuItem(
                                  value: 'Pending',
                                  child: Text('باقی (Pending)'),
                                ),
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
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            color: Colors.brown,
                            fontSize: 14,
                          ),
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
                      const SizedBox(height: 12),
                      Card(
                        color: Colors.orange.shade50,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Padding(
                          padding: const EdgeInsets.all(12),
                          child: Column(
                            children: [
                              Row(
                                mainAxisAlignment:
                                    MainAxisAlignment.spaceBetween,
                                children: [
                                  const Text(
                                    'کل آمدنی:',
                                    style: TextStyle(
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                  DigitText(
                                    Money(grossPaisa).format(),
                                    style: const TextStyle(
                                      fontWeight: FontWeight.bold,
                                      color: Colors.green,
                                    ),
                                  ),
                                ],
                              ),
                              const Divider(),
                              Row(
                                mainAxisAlignment:
                                    MainAxisAlignment.spaceBetween,
                                children: [
                                  const Text(
                                    'کل اخراجات:',
                                    style: TextStyle(
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                  DigitText(
                                    Money(totalExpensePaisa).format(),
                                    style: const TextStyle(
                                      fontWeight: FontWeight.bold,
                                      color: Colors.red,
                                    ),
                                  ),
                                ],
                              ),
                              const Divider(),
                              Row(
                                mainAxisAlignment:
                                    MainAxisAlignment.spaceBetween,
                                children: [
                                  const Text(
                                    'خالص نفع/نقصان:',
                                    style: TextStyle(
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                  DigitText(
                                    Money(netIncomePaisa).format(),
                                    style: TextStyle(
                                      fontWeight: FontWeight.bold,
                                      color:
                                          netIncomePaisa >= 0
                                              ? Colors.green.shade800
                                              : Colors.red.shade800,
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
                  child: const Text(Strings.cancel),
                ),
                ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.orange.shade800,
                    foregroundColor: Colors.white,
                  ),
                  onPressed: () {
                    if (formKey.currentState!.validate()) {
                      final int ratePaisa;
                      final int transPaisa;
                      final int labourPaisa;
                      final int harvestingPaisa;
                      final int commissionPaisa;
                      final int otherPaisa;
                      try {
                        ratePaisa = _parsePaisaOrThrow(rateController.text);
                        transPaisa = _parsePaisaOrThrow(transController.text);
                        labourPaisa = _parsePaisaOrThrow(labourController.text);
                        harvestingPaisa = _parsePaisaOrThrow(
                          harvestController.text,
                        );
                        commissionPaisa = _parsePaisaOrThrow(
                          commissionController.text,
                        );
                        otherPaisa = _parsePaisaOrThrow(otherController.text);
                      } on MoneyParseException catch (e) {
                        _showMoneyError(ctx, e);
                        return;
                      }
                      harvestProvider.updateHarvest(
                        id: h.id!,
                        cropSeasonId: selectedCropSeasonId!,
                        quantity: Quantity.parsePositive(qtyController.text),
                        unit: selectedUnit,
                        date: selectedDate.toIso8601String(),
                        ratePerUnitPaisa: ratePaisa,
                        transportationExpensePaisa: transPaisa,
                        labourExpensePaisa: labourPaisa,
                        harvestingExpensePaisa: harvestingPaisa,
                        commissionExpensePaisa: commissionPaisa,
                        otherExpensePaisa: otherPaisa,
                        buyerName: buyerNameController.text,
                        paymentStatus: paymentStatus,
                        notes: notesController.text,
                      );
                      Navigator.pop(ctx);
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text(
                            'پیداوار کا ریکارڈ کامیابی سے تبدیل ہو گیا!',
                          ),
                        ),
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

  void _showRecordSaleDialog(BuildContext context, HarvestWithDetails item) {
    final harvestProvider = Provider.of<HarvestProvider>(
      context,
      listen: false,
    );
    final formKey = GlobalKey<FormState>();

    final priceController = TextEditingController();
    final buyerController = TextEditingController();
    int totalAmountPaisa = 0;
    DateTime selectedDate = DateTime.now();

    showDialog(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (context, setState) {
            return AlertDialog(
              title: Text(
                'پیداوار فروخت کریں (${item.harvest.quantity} ${item.harvest.unit})',
              ),
              content: Form(
                key: formKey,
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      TextFormField(
                        controller: priceController,
                        keyboardType: const TextInputType.numberWithOptions(
                          decimal: true,
                        ),
                        decoration: InputDecoration(
                          labelText: 'ریٹ فی ${item.harvest.unit} (روپے)',
                          border: const OutlineInputBorder(),
                        ),
                        validator: (value) {
                          if (value == null || value.isEmpty) {
                            return 'ریٹ درج کریں';
                          }
                          try {
                            Money.parse(value);
                          } on MoneyParseException catch (e) {
                            return e.message;
                          }
                          return null;
                        },
                        onChanged: (val) {
                          final int? pricePaisa = _tryPaisa(val);
                          if (pricePaisa != null) {
                            setState(() {
                              totalAmountPaisa =
                                  (pricePaisa * item.harvest.quantity).round();
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
                        title: Text(
                          'تاریخ فروخت: ${DateFormat('yyyy-MM-dd').format(selectedDate)}',
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
                          'کل رقم: ${Money(totalAmountPaisa).format()}',
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            color: Colors.blue.shade800,
                            fontSize: 16,
                          ),
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
                  child: const Text(Strings.cancel),
                ),
                ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.green,
                    foregroundColor: Colors.white,
                  ),
                  onPressed: () {
                    if (formKey.currentState!.validate()) {
                      final int pricePaisa;
                      try {
                        pricePaisa = Money.parse(priceController.text).paisa;
                      } on MoneyParseException catch (e) {
                        _showMoneyError(ctx, e);
                        return;
                      }
                      harvestProvider.recordSale(
                        harvestId: item.harvest.id!,
                        quantity: item.harvest.quantity,
                        pricePerUnitPaisa: pricePaisa,
                        date: selectedDate.toIso8601String(),
                        buyerName: buyerController.text,
                      );
                      Navigator.pop(ctx);
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

  void _showEditSaleDialog(BuildContext context, HarvestWithDetails item) {
    final harvestProvider = Provider.of<HarvestProvider>(
      context,
      listen: false,
    );
    final formKey = GlobalKey<FormState>();
    final sale = item.sale!;

    final priceController = TextEditingController(
      text: Money(sale.pricePerUnitPaisa).format(),
    );
    final buyerController = TextEditingController(text: sale.buyerName ?? '');
    int totalAmountPaisa = sale.totalAmountPaisa;
    DateTime selectedDate = DateTime.parse(sale.date);

    showDialog(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (context, setState) {
            return AlertDialog(
              title: Text(
                'فروخت کے ریکارڈ میں تبدیلی (${item.harvest.quantity} ${item.harvest.unit})',
              ),
              content: Form(
                key: formKey,
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      TextFormField(
                        controller: priceController,
                        keyboardType: const TextInputType.numberWithOptions(
                          decimal: true,
                        ),
                        decoration: InputDecoration(
                          labelText: 'ریٹ فی ${item.harvest.unit} (روپے)',
                          border: const OutlineInputBorder(),
                        ),
                        validator: (value) {
                          if (value == null || value.isEmpty) {
                            return 'ریٹ درج کریں';
                          }
                          try {
                            Money.parse(value);
                          } on MoneyParseException catch (e) {
                            return e.message;
                          }
                          return null;
                        },
                        onChanged: (val) {
                          final int? pricePaisa = _tryPaisa(val);
                          if (pricePaisa != null) {
                            setState(() {
                              totalAmountPaisa =
                                  (pricePaisa * item.harvest.quantity).round();
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
                        title: Text(
                          'تاریخ فروخت: ${DateFormat('yyyy-MM-dd').format(selectedDate)}',
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
                          'کل رقم: ${Money(totalAmountPaisa).format()}',
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            color: Colors.blue.shade800,
                            fontSize: 16,
                          ),
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
                  child: const Text(Strings.cancel),
                ),
                ElevatedButton(
                  onPressed: () {
                    if (formKey.currentState!.validate()) {
                      final int pricePaisa;
                      try {
                        pricePaisa = Money.parse(priceController.text).paisa;
                      } on MoneyParseException catch (e) {
                        _showMoneyError(ctx, e);
                        return;
                      }
                      harvestProvider.updateSale(
                        id: sale.id!,
                        harvestId: item.harvest.id!,
                        quantity: item.harvest.quantity,
                        pricePerUnitPaisa: pricePaisa,
                        date: selectedDate.toIso8601String(),
                        buyerName: buyerController.text,
                      );
                      Navigator.pop(ctx);
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text(
                            'فروخت کا ریکارڈ کامیابی سے تبدیل ہو گیا!',
                          ),
                        ),
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

  void _confirmDeleteSale(BuildContext context, int id) {
    showDialog(
      context: context,
      builder:
          (ctx) => AlertDialog(
            title: const Text('فروخت حذف کریں؟'),
            content: const Text(
              'کیا آپ واقعی یہ فروخت کا ریکارڈ حذف کرنا چاہتے ہیں؟ اس سے پیداوار کا بنیادی ریکارڈ حذف نہیں ہوگا۔',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text(Strings.cancel),
              ),
              ElevatedButton(
                style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
                onPressed: () {
                  Provider.of<HarvestProvider>(
                    context,
                    listen: false,
                  ).deleteSale(id);
                  Navigator.pop(ctx);
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('فروخت کا ریکارڈ کامیابی سے حذف ہو گیا!'),
                    ),
                  );
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

  void _confirmDeleteHarvest(BuildContext context, int id) {
    showDialog(
      context: context,
      builder:
          (ctx) => AlertDialog(
            title: const Text('پیداوار حذف کریں؟'),
            content: const Text(
              'کیا آپ واقعی یہ پیداوار اور اس کی تمام فروخت کی معلومات حذف کرنا چاہتے ہیں؟',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text(Strings.cancel),
              ),
              ElevatedButton(
                style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
                onPressed: () {
                  Provider.of<HarvestProvider>(
                    context,
                    listen: false,
                  ).deleteHarvest(id);
                  Navigator.pop(ctx);
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('پیداوار کامیابی سے حذف ہو گئی!'),
                    ),
                  );
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
