import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import '../providers/crop_provider.dart';
import '../providers/harvest_provider.dart';
import '../providers/expense_provider.dart';
import '../providers/activity_provider.dart';
import '../providers/theka_provider.dart';
import '../providers/farm_provider.dart';
import '../providers/ushr_provider.dart';
import '../models/models.dart';
import '../services/money.dart';
import '../services/pnl_summary.dart';

class ProfitLossScreen extends StatefulWidget {
  const ProfitLossScreen({super.key});

  @override
  State<ProfitLossScreen> createState() => _ProfitLossScreenState();
}

class _ProfitLossScreenState extends State<ProfitLossScreen> {
  String _selectedStatus = 'All'; // 'All', 'Active', 'Harvested'

  @override
  Widget build(BuildContext context) {
    final cropProvider = Provider.of<CropProvider>(context);
    final harvestProvider = Provider.of<HarvestProvider>(context);
    final expenseProvider = Provider.of<ExpenseProvider>(context);
    final activityProvider = Provider.of<ActivityProvider>(context);
    final thekaProvider = Provider.of<ThekaProvider>(context);
    final farmProvider = Provider.of<FarmProvider>(context);
    final ushrProvider = Provider.of<UshrProvider>(context);

    // 1+2. Overall + crop-wise P&L — computed by the shared service so the
    // on-screen report and the exported PDF can never disagree.
    final pnl = computeFarmPnl(
      harvests: harvestProvider.harvests,
      totalExpensesPaisa: expenseProvider.totalExpensesPaisa,
      seasons: [
        ...cropProvider.activeCropSeasons,
        ...cropProvider.harvestedCropSeasons
      ],
      activities: activityProvider.activities,
      expenses: expenseProvider.expenses,
      ushrRecords: ushrProvider.ushrRecords,
    );
    final totalSales = pnl.totalSalesPaisa;
    final totalExpenses = pnl.totalExpensesPaisa;
    final netProfit = pnl.netPaisa;

    final List<CropPL> cropPLList = pnl.crops
        .map((r) => CropPL(
              details: r.details,
              income: r.incomePaisa,
              expenses: r.expensesPaisa,
              net: r.netPaisa,
              harvests: r.harvests,
              activities: r.activities,
            ))
        .toList();

    // 3. Filtered Crops list
    final filteredCropPLList = cropPLList.where((pl) {
      if (_selectedStatus == 'Active') {
        return pl.details.cropSeason.status == 'Active';
      } else if (_selectedStatus == 'Harvested') {
        return pl.details.cropSeason.status == 'Harvested';
      }
      return true;
    }).toList();

    // 4. Key Insights
    CropPL? mostProfitable;
    for (var pl in cropPLList) {
      if (pl.net > 0) {
        if (mostProfitable == null || pl.net > mostProfitable.net) {
          mostProfitable = pl;
        }
      }
    }

    CropPL? highestYielding;
    double maxYield = 0.0;
    String highestYieldText = '';
    for (var pl in cropPLList) {
      if (pl.harvests.isNotEmpty) {
        final Map<String, double> unitQuantities = {};
        for (var hwd in pl.harvests) {
          unitQuantities[hwd.harvest.unit] =
              (unitQuantities[hwd.harvest.unit] ?? 0.0) + hwd.harvest.quantity;
        }
        final yieldSum = pl.harvests.fold(0.0, (sum, h) => sum + h.harvest.quantity);
        if (yieldSum > maxYield) {
          maxYield = yieldSum;
          highestYielding = pl;
          highestYieldText = unitQuantities.entries
              .map((e) => '${e.value.toStringAsFixed(0)} ${e.key}')
              .join('، ');
        }
      }
    }

    // 5. Category-wise Expenses Breakdown
    final Map<String, int> categorySums = {};
    for (var exp in expenseProvider.expenses) {
      categorySums[exp.category] = (categorySums[exp.category] ?? 0) + exp.amountPaisa;
    }
    final sortedCategories = categorySums.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));

    // Indirect Expenses: expenses not linked to any crop — neither via
    // activities nor via the direct expenses.crop_season_id link.
    final linkedExpenseIds = <int>{};
    for (final act in activityProvider.activities) {
      final expId = act.activity.expenseId;
      if (expId != null) linkedExpenseIds.add(expId);
    }
    for (final exp in expenseProvider.expenses) {
      final expId = exp.id;
      if (exp.cropSeasonId != null && expId != null) {
        linkedExpenseIds.add(expId);
      }
    }
    final linkedExpenseSum = expenseProvider.expenses
        .where((e) => e.id != null && linkedExpenseIds.contains(e.id))
        .fold<int>(0, (sum, e) => sum + e.amountPaisa);
    final indirectExpenses = totalExpenses - linkedExpenseSum;

    return DefaultTabController(
      length: 4,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('منافع اور نقصان کا حساب'),
          bottom: const TabBar(
            labelColor: Colors.white,
            unselectedLabelColor: Colors.white70,
            indicatorColor: Colors.white,
            labelStyle: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.bold,
              fontFamily: 'Jameel Noori Nastaleeq',
            ),
            unselectedLabelStyle: TextStyle(
              fontSize: 18,
              fontFamily: 'Jameel Noori Nastaleeq',
            ),
            tabs: [
              Tab(text: 'فصل وار حساب'),
              Tab(text: 'خرچے کا تجزیہ'),
              Tab(text: 'ٹھیکہ کی رپورٹ'),
              Tab(text: 'عشر کی رپورٹ'),
            ],
          ),
        ),
        body: TabBarView(
          children: [
            // Tab 1: Crop-wise accounts
            _buildCropWiseTab(
              context,
              netProfit,
              totalSales,
              totalExpenses,
              filteredCropPLList,
              mostProfitable,
              highestYielding,
              highestYieldText,
              cropProvider,
            ),
            // Tab 2: Expense Analysis
            _buildExpenseAnalysisTab(
              context,
              netProfit,
              totalSales,
              totalExpenses,
              sortedCategories,
              indirectExpenses,
              expenseProvider,
            ),
            // Tab 3: Theka Report
            _buildThekaReportTab(
              context,
              thekaProvider,
              farmProvider,
            ),
            // Tab 4: Ushr Report
            _buildUshrReportTab(
              context,
              ushrProvider,
              farmProvider,
              cropProvider,
            ),
          ],
        ),
      ),
    );
  }

  // overall summary card
  Widget _buildSummaryCard(
    BuildContext context,
    int netProfit,
    int totalSales,
    int totalExpenses,
  ) {
    final isProfit = netProfit >= 0;
    final primaryGrad = isProfit ? const Color(0xFF1B5E20) : const Color(0xFFB71C1C);
    final secondaryGrad = isProfit ? const Color(0xFF4CAF50) : const Color(0xFFE53935);
    final statusText = isProfit
        ? 'ماشاءاللہ، آپ کا کاروبار منافع میں ہے!'
        : 'احتیاط! آپ کا کاروبار نقصان میں ہے۔';

    return Container(
      width: double.infinity,
      margin: const EdgeInsets.all(16),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [primaryGrad, secondaryGrad],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(
            color: (isProfit ? Colors.green : Colors.red).withValues(alpha: 0.3),
            blurRadius: 12,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    isProfit ? 'خالص بچت / منافع' : 'خالص نقصان',
                    style: const TextStyle(
                      color: Colors.white70,
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      fontFamily: 'Jameel Noori Nastaleeq',
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    Money(netProfit.abs()).format(),
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 32,
                      fontWeight: FontWeight.bold,
                      fontFamily: 'Jameel Noori Nastaleeq',
                    ),
                  ),
                ],
              ),
              CircleAvatar(
                radius: 28,
                backgroundColor: Colors.white.withValues(alpha: 0.2),
                child: Icon(
                  isProfit ? Icons.trending_up : Icons.trending_down,
                  color: Colors.white,
                  size: 32,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Align(
            alignment: Alignment.centerRight,
            child: Text(
              statusText,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 15,
                fontStyle: FontStyle.italic,
                fontFamily: 'Jameel Noori Nastaleeq',
              ),
            ),
          ),
          const Divider(color: Colors.white24, height: 24),
          Row(
            children: [
              Expanded(
                child: Column(
                  children: [
                    const Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.arrow_upward, color: Colors.greenAccent, size: 16),
                        SizedBox(width: 4),
                        Text(
                          'کل فروخت (آمدنی)',
                          style: TextStyle(
                            color: Colors.white70,
                            fontSize: 13,
                            fontFamily: 'Jameel Noori Nastaleeq',
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      Money(totalSales).format(),
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        fontFamily: 'Jameel Noori Nastaleeq',
                      ),
                    ),
                  ],
                ),
              ),
              Container(width: 1, height: 40, color: Colors.white24),
              Expanded(
                child: Column(
                  children: [
                    const Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.arrow_downward, color: Colors.redAccent, size: 16),
                        SizedBox(width: 4),
                        Text(
                          'کل اخراجات',
                          style: TextStyle(
                            color: Colors.white70,
                            fontSize: 13,
                            fontFamily: 'Jameel Noori Nastaleeq',
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      Money(totalExpenses).format(),
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        fontFamily: 'Jameel Noori Nastaleeq',
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildCropWiseTab(
    BuildContext context,
    int netProfit,
    int totalSales,
    int totalExpenses,
    List<CropPL> filteredList,
    CropPL? mostProfitable,
    CropPL? highestYielding,
    String highestYieldText,
    CropProvider cropProvider,
  ) {
    return ListView(
      physics: const BouncingScrollPhysics(),
      children: [
        _buildSummaryCard(context, netProfit, totalSales, totalExpenses),
        
        // Insights
        _buildInsightsPanel(mostProfitable, highestYielding, highestYieldText, cropProvider),
        
        // Filters title
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                'فصل وار منافع و نقصان کا ریکارڈ:',
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 18,
                  fontFamily: 'Jameel Noori Nastaleeq',
                ),
              ),
              Text(
                'تعداد: ${filteredList.length}',
                style: const TextStyle(
                  color: Colors.grey,
                  fontSize: 14,
                  fontFamily: 'Jameel Noori Nastaleeq',
                ),
              ),
            ],
          ),
        ),

        // Filter chips
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 4.0),
          child: Row(
            children: [
              _buildFilterChip('All', 'تمام فصلیں'),
              const SizedBox(width: 8),
              _buildFilterChip('Active', 'کاشت شدہ (فعال)'),
              const SizedBox(width: 8),
              _buildFilterChip('Harvested', 'کٹائی شدہ (سابقہ)'),
            ],
          ),
        ),

        const SizedBox(height: 8),

        // List
        if (filteredList.isEmpty)
          const Center(
            child: Padding(
              padding: EdgeInsets.symmetric(vertical: 40.0),
              child: Text(
                'کوئی ریکارڈ موجود نہیں ہے',
                style: TextStyle(
                  fontSize: 18,
                  color: Colors.grey,
                  fontFamily: 'Jameel Noori Nastaleeq',
                ),
              ),
            ),
          )
        else
          ...filteredList.map((pl) => _buildCropPLCard(context, pl, cropProvider)),

        const SizedBox(height: 40),
      ],
    );
  }

  Widget _buildFilterChip(String status, String label) {
    final isSelected = _selectedStatus == status;
    return ChoiceChip(
      label: Text(label),
      selected: isSelected,
      onSelected: (val) {
        if (val) {
          setState(() {
            _selectedStatus = status;
          });
        }
      },
      selectedColor: Theme.of(context).primaryColor,
      backgroundColor: Colors.white,
      labelStyle: TextStyle(
        fontFamily: 'Jameel Noori Nastaleeq',
        fontSize: 16,
        fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
        color: isSelected ? Colors.white : Colors.black87,
      ),
    );
  }

  Widget _buildInsightsPanel(
    CropPL? mostProfitable,
    CropPL? highestYielding,
    String highestYieldText,
    CropProvider cropProvider,
  ) {
    if (mostProfitable == null && highestYielding == null) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'اہم معلومات (بڑی کامیابیاں):',
            style: TextStyle(
              fontWeight: FontWeight.bold,
              fontSize: 18,
              color: Colors.green,
              fontFamily: 'Jameel Noori Nastaleeq',
            ),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              if (mostProfitable != null)
                Expanded(
                  child: Card(
                    color: Colors.green.shade50,
                    child: Padding(
                      padding: const EdgeInsets.all(12.0),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Row(
                            children: [
                              Icon(Icons.star, color: Colors.amber, size: 18),
                              SizedBox(width: 4),
                              Text(
                                'کامیاب ترین فصل',
                                style: TextStyle(
                                  fontWeight: FontWeight.bold,
                                  fontSize: 13,
                                  color: Colors.black87,
                                  fontFamily: 'Jameel Noori Nastaleeq',
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 6),
                          Text(
                            '${cropProvider.predefinedCrops[mostProfitable.details.cropSeason.cropName] ?? mostProfitable.details.cropSeason.cropName} (${mostProfitable.details.cropSeason.variety})',
                            style: const TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 16,
                              color: Colors.green,
                              fontFamily: 'Jameel Noori Nastaleeq',
                            ),
                          ),
                          Text(
                            'بچت: ${Money(mostProfitable.net).format()}',
                            style: const TextStyle(
                              fontSize: 13,
                              color: Colors.black54,
                              fontFamily: 'Jameel Noori Nastaleeq',
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              if (highestYielding != null && highestYieldText.isNotEmpty)
                Expanded(
                  child: Card(
                    color: Colors.blue.shade50,
                    child: Padding(
                      padding: const EdgeInsets.all(12.0),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Row(
                            children: [
                              Icon(Icons.workspace_premium, color: Colors.orange, size: 18),
                              SizedBox(width: 4),
                              Text(
                                'زیادہ پیداوار',
                                style: TextStyle(
                                  fontWeight: FontWeight.bold,
                                  fontSize: 13,
                                  color: Colors.black87,
                                  fontFamily: 'Jameel Noori Nastaleeq',
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 6),
                          Text(
                            '${cropProvider.predefinedCrops[highestYielding.details.cropSeason.cropName] ?? highestYielding.details.cropSeason.cropName} - ${highestYielding.details.fieldDisplayName}',
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 16,
                              color: Colors.blue.shade800,
                              fontFamily: 'Jameel Noori Nastaleeq',
                            ),
                          ),
                          Text(
                            'مقدار: $highestYieldText',
                            style: const TextStyle(
                              fontSize: 13,
                              color: Colors.black54,
                              fontFamily: 'Jameel Noori Nastaleeq',
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildCropPLCard(BuildContext context, CropPL pl, CropProvider cropProvider) {
    final season = pl.details.cropSeason;
    final cropNameUrdu = cropProvider.predefinedCrops[season.cropName] ?? season.cropName;
    final cropNet = pl.net;

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: ExpansionTile(
        leading: CircleAvatar(
          backgroundColor: cropNet >= 0 ? Colors.green.shade50 : Colors.red.shade50,
          child: Icon(
            cropNet >= 0 ? Icons.trending_up : Icons.trending_down,
            color: cropNet >= 0 ? Colors.green : Colors.red,
          ),
        ),
        title: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Expanded(
              child: Text(
                '$cropNameUrdu (${season.variety})',
                style: const TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 18,
                  fontFamily: 'Jameel Noori Nastaleeq',
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),
            const SizedBox(width: 8),
            _buildStatusBadge(season.status),
          ],
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'زمین: ${pl.details.farmDisplayName} - ${pl.details.fieldDisplayName}',
              style: const TextStyle(
                fontFamily: 'Jameel Noori Nastaleeq',
                fontSize: 14,
              ),
            ),
            const SizedBox(height: 8),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                _buildMiniStat('آمدنی', pl.income, Colors.green),
                _buildMiniStat('اخراجات', pl.expenses, Colors.red),
                _buildMiniStat(
                  cropNet >= 0 ? 'بچت' : 'نقصان',
                  cropNet.abs(),
                  cropNet >= 0 ? Colors.green.shade800 : Colors.red.shade800,
                  isBold: true,
                ),
              ],
            ),
          ],
        ),
        children: [
          const Divider(),
          _buildCropDetails(context, pl),
        ],
      ),
    );
  }

  Widget _buildStatusBadge(String status) {
    final isActive = status == 'Active';
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: isActive ? Colors.blue.shade50 : Colors.grey.shade100,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: isActive ? Colors.blue.shade200 : Colors.grey.shade300),
      ),
      child: Text(
        isActive ? 'کاشت شدہ' : 'کٹائی شدہ',
        style: TextStyle(
          fontSize: 12,
          color: isActive ? Colors.blue.shade800 : Colors.grey.shade700,
          fontWeight: FontWeight.bold,
          fontFamily: 'Jameel Noori Nastaleeq',
        ),
      ),
    );
  }

  Widget _buildMiniStat(String label, int amount, Color color, {bool isBold = false}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(
            fontSize: 12,
            color: Colors.grey,
            fontFamily: 'Jameel Noori Nastaleeq',
          ),
        ),
        Text(
          Money(amount).format(),
          style: TextStyle(
            fontSize: 14,
            fontWeight: isBold ? FontWeight.bold : FontWeight.normal,
            color: color,
            fontFamily: 'Jameel Noori Nastaleeq',
          ),
        ),
      ],
    );
  }

  Widget _buildCropDetails(BuildContext context, CropPL pl) {
    final hasHarvests = pl.harvests.isNotEmpty;
    final hasActivities = pl.activities.isNotEmpty;

    return Padding(
      padding: const EdgeInsets.all(16.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Harvest & Sales Details
          const Row(
            children: [
              Icon(Icons.agriculture, size: 18, color: Colors.green),
              SizedBox(width: 8),
              Text(
                'پیداوار اور فروخت کی تفصیل:',
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 16,
                  fontFamily: 'Jameel Noori Nastaleeq',
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          if (!hasHarvests)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 8.0),
              child: Text(
                'اس فصل کی کوئی پیداوار درج نہیں کی گئی۔',
                style: TextStyle(
                  color: Colors.grey,
                  fontSize: 14,
                  fontFamily: 'Jameel Noori Nastaleeq',
                ),
              ),
            )
          else
            ...pl.harvests.map((hwd) {
              final h = hwd.harvest;
              final s = hwd.sale;
              return Card(
                color: Colors.green.shade50.withValues(alpha: 0.5),
                margin: const EdgeInsets.only(bottom: 8),
                child: Padding(
                  padding: const EdgeInsets.all(12.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            'پیداوار: ${h.quantity.toStringAsFixed(0)} ${h.unit}',
                            style: const TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 15,
                              fontFamily: 'Jameel Noori Nastaleeq',
                            ),
                          ),
                          Text(
                            DateFormat('yyyy-MM-dd').format(DateTime.parse(h.date)),
                            style: const TextStyle(
                              color: Colors.grey,
                              fontSize: 12,
                              fontFamily: 'Jameel Noori Nastaleeq',
                            ),
                          ),
                        ],
                      ),
                      if (s != null) ...[
                        const Divider(height: 12),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(
                              'شرح: ${Money(s.pricePerUnitPaisa).format()} فی ${h.unit}',
                              style: const TextStyle(
                                fontFamily: 'Jameel Noori Nastaleeq',
                                fontSize: 13,
                              ),
                            ),
                            Text(
                              'آمدنی: ${Money(s.totalAmountPaisa).format()}',
                              style: const TextStyle(
                                color: Colors.green,
                                fontWeight: FontWeight.bold,
                                fontFamily: 'Jameel Noori Nastaleeq',
                              ),
                            ),
                          ],
                        ),
                        if (s.buyerName != null && s.buyerName!.isNotEmpty)
                          Padding(
                            padding: const EdgeInsets.only(top: 4.0),
                            child: Text(
                              'خریدار: ${s.buyerName}',
                              style: const TextStyle(
                                fontSize: 13,
                                color: Colors.black87,
                                fontFamily: 'Jameel Noori Nastaleeq',
                              ),
                            ),
                          ),
                      ] else
                        const Padding(
                          padding: EdgeInsets.only(top: 6.0),
                          child: Text(
                            'ابھی تک فروخت نہیں ہوئی',
                            style: TextStyle(
                              color: Colors.orange,
                              fontSize: 13,
                              fontWeight: FontWeight.bold,
                              fontFamily: 'Jameel Noori Nastaleeq',
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              );
            }),

          const SizedBox(height: 16),
          // Activities Expenses details
          const Row(
            children: [
              Icon(Icons.money_off, size: 18, color: Colors.red),
              SizedBox(width: 8),
              Text(
                'اخراجات کی تفصیل (سرگرمیاں):',
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 16,
                  fontFamily: 'Jameel Noori Nastaleeq',
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          if (!hasActivities)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 8.0),
              child: Text(
                'اس فصل کا کوئی خرچہ درج نہیں کیا گیا۔',
                style: TextStyle(
                  color: Colors.grey,
                  fontSize: 14,
                  fontFamily: 'Jameel Noori Nastaleeq',
                ),
              ),
            )
          else
            ...pl.activities.map((actwd) {
              final act = actwd.activity;
              return Card(
                color: Colors.red.shade50.withValues(alpha: 0.3),
                margin: const EdgeInsets.only(bottom: 8),
                child: ListTile(
                  dense: true,
                  title: Text(
                    act.activityType,
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 14,
                      fontFamily: 'Jameel Noori Nastaleeq',
                    ),
                  ),
                  subtitle: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (act.details != null && act.details!.isNotEmpty)
                        Text(
                          act.details!,
                          style: const TextStyle(
                            fontSize: 12,
                            fontFamily: 'Jameel Noori Nastaleeq',
                          ),
                        ),
                      Text(
                        DateFormat('yyyy-MM-dd').format(DateTime.parse(act.date)),
                        style: const TextStyle(
                          color: Colors.grey,
                          fontSize: 11,
                          fontFamily: 'Jameel Noori Nastaleeq',
                        ),
                      ),
                    ],
                  ),
                  trailing: Text(
                    Money(actwd.expenseAmountPaisa ?? 0).format(),
                    style: const TextStyle(
                      color: Colors.red,
                      fontWeight: FontWeight.bold,
                      fontSize: 14,
                      fontFamily: 'Jameel Noori Nastaleeq',
                    ),
                  ),
                ),
              );
            }),
        ],
      ),
    );
  }

  Widget _buildExpenseAnalysisTab(
    BuildContext context,
    int netProfit,
    int totalSales,
    int totalExpenses,
    List<MapEntry<String, int>> sortedCategories,
    int indirectExpenses,
    ExpenseProvider expenseProvider,
  ) {
    final theme = Theme.of(context);

    return ListView(
      physics: const BouncingScrollPhysics(),
      children: [
        _buildSummaryCard(context, netProfit, totalSales, totalExpenses),

        Padding(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'اخراجات کی تفصیل بلحاظ زمرہ (Category):',
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 18,
                  fontFamily: 'Jameel Noori Nastaleeq',
                ),
              ),
              const SizedBox(height: 12),
              if (sortedCategories.isEmpty && indirectExpenses <= 0)
                const Center(
                  child: Padding(
                    padding: EdgeInsets.symmetric(vertical: 40.0),
                    child: Text(
                      'کوئی اخراجات ریکارڈ نہیں ہیں',
                      style: TextStyle(
                        fontSize: 18,
                        color: Colors.grey,
                        fontFamily: 'Jameel Noori Nastaleeq',
                      ),
                    ),
                  ),
                )
              else ...[
                // List of categories progress bars
                ...sortedCategories.map((entry) {
                  final catUrdu = expenseProvider.expenseCategories[entry.key] ?? entry.key;
                  final percentage = totalExpenses > 0 ? (entry.value / totalExpenses) : 0.0;
                  return _buildCategoryProgressRow(catUrdu, entry.value, percentage, theme.primaryColor);
                }),
                
                // Show Indirect/General expenses if they exist
                if (indirectExpenses > 0) ...[
                  const Divider(height: 24),
                  _buildCategoryProgressRow(
                    'غیر فصلاتی / متفرق اخراجات (Indirect)',
                    indirectExpenses,
                    totalExpenses > 0 ? (indirectExpenses / totalExpenses) : 0.0,
                    Colors.grey.shade600,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'یہ وہ اخراجات ہیں جو کسی مخصوص فصل کی سرگرمی سے منسلک نہیں کیے گئے، بلکہ براہ راست خرچے کے ریکارڈ میں درج کیے گئے ہیں (جیسے زمین کا ٹھیکہ، بجلی کا بل وغیرہ)۔',
                    style: TextStyle(
                      color: Colors.grey.shade600,
                      fontSize: 13,
                      height: 1.4,
                      fontFamily: 'Jameel Noori Nastaleeq',
                    ),
                  ),
                ],
              ],
            ],
          ),
        ),
        const SizedBox(height: 40),
      ],
    );
  }

  Widget _buildCategoryProgressRow(
    String categoryUrdu,
    int amount,
    double percentage,
    Color color,
  ) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                categoryUrdu,
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  fontFamily: 'Jameel Noori Nastaleeq',
                ),
              ),
              Text(
                '${Money(amount).format()} (${(percentage * 100).toStringAsFixed(0)}%)',
                style: TextStyle(
                  fontSize: 14,
                  color: Colors.grey.shade700,
                  fontWeight: FontWeight.bold,
                  fontFamily: 'Jameel Noori Nastaleeq',
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Container(
            width: double.infinity,
            height: 12,
            decoration: BoxDecoration(
              color: Colors.grey.shade200,
              borderRadius: BorderRadius.circular(6),
            ),
            child: Align(
              alignment: Alignment.centerRight, // RTL alignment support
              child: FractionallySizedBox(
                widthFactor: percentage,
                child: Container(
                  decoration: BoxDecoration(
                    color: color,
                    borderRadius: BorderRadius.circular(6),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildThekaReportTab(
    BuildContext context,
    ThekaProvider thekaProvider,
    FarmProvider farmProvider,
  ) {
    final thekas = thekaProvider.thekas;

    if (thekas.isEmpty) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(24.0),
          child: Text(
            'کوئی ٹھیکہ معاہدہ موجود نہیں ہے۔\nٹھیکہ کی معلومات دیکھنے کے لیے پہلے ٹھیکہ شامل کریں۔',
            style: TextStyle(
              fontSize: 20,
              fontFamily: 'Jameel Noori Nastaleeq',
              color: Colors.grey,
            ),
            textAlign: TextAlign.center,
          ),
        ),
      );
    }

    // Calculations
    int totalThekaAmount = 0;
    int totalPaid = 0;
    int totalInstallments = 0;
    int paidInstallments = 0;
    int pendingInstallments = 0;
    int partialInstallments = 0;

    final Map<int, int> farmPaid = {};
    final Map<int, int> farmTotal = {};

    final Map<String, int> seasonalPaid = {};
    final Map<String, int> seasonalTotal = {};

    final Map<String, int> yearlyPaid = {};
    final Map<String, int> yearlyTotal = {};

    for (var theka in thekas) {
      totalThekaAmount += theka.totalAmountPaisa;
      farmTotal[theka.farmId] = (farmTotal[theka.farmId] ?? 0) + theka.totalAmountPaisa;

      final seasonName = theka.durationDetails?.isNotEmpty == true 
          ? theka.durationDetails! 
          : (theka.durationType == 'Yearly' ? 'سالانہ ٹھیکہ' : 'دیگر ٹھیکہ');
      seasonalTotal[seasonName] = (seasonalTotal[seasonName] ?? 0) + theka.totalAmountPaisa;

      final insts = thekaProvider.getInstallmentsForTheka(theka.id!);
      totalInstallments += insts.length;

      for (var inst in insts) {
        if (inst.status == 'Paid') {
          paidInstallments++;
        } else if (inst.status == 'Partially Paid') {
          partialInstallments++;
        } else {
          pendingInstallments++;
        }

        totalPaid += inst.paidAmountPaisa;
        farmPaid[theka.farmId] = (farmPaid[theka.farmId] ?? 0) + inst.paidAmountPaisa;
        seasonalPaid[seasonName] = (seasonalPaid[seasonName] ?? 0) + inst.paidAmountPaisa;

        // Group by year of payment (if paid) or due date (if pending)
        final String yearStr = inst.paidDate != null 
            ? inst.paidDate!.split('-').first
            : inst.dueDate.split('-').first;
        
        yearlyTotal[yearStr] = (yearlyTotal[yearStr] ?? 0) + inst.amountPaisa;
        yearlyPaid[yearStr] = (yearlyPaid[yearStr] ?? 0) + inst.paidAmountPaisa;
      }
    }

    final int totalPending = totalThekaAmount - totalPaid;

    return ListView(
      padding: const EdgeInsets.all(16.0),
      children: [
        // 1. Overview Summary Card
        Card(
          elevation: 4,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          color: Colors.brown.shade800,
          child: Padding(
            padding: const EdgeInsets.all(20.0),
            child: Column(
              children: [
                const Text(
                  'ٹھیکہ (لیز) خلاصہ رپورٹ',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                    fontFamily: 'Jameel Noori Nastaleeq',
                  ),
                ),
                const SizedBox(height: 16),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    _buildPLSummaryCol('کل ٹھیکہ رقم', totalThekaAmount, Colors.white),
                    _buildPLSummaryCol('کل ادا شدہ', totalPaid, Colors.greenAccent),
                    _buildPLSummaryCol('کل واجب الادا', totalPending, Colors.orangeAccent),
                  ],
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 16),

        // 2. Installments Status Card
        Card(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          child: Padding(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'اقساط کا تجزیہ (Installment Status)',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: Colors.brown,
                    fontFamily: 'Jameel Noori Nastaleeq',
                  ),
                ),
                const Divider(),
                const SizedBox(height: 8),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceAround,
                  children: [
                    _buildStatCol('کل اقساط', totalInstallments, Colors.black87),
                    _buildStatCol('مکمل ادا شدہ', paidInstallments, Colors.green),
                    _buildStatCol('جزوی ادا شدہ', partialInstallments, Colors.orange),
                    _buildStatCol('غیر ادا شدہ', pendingInstallments, Colors.red),
                  ],
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 16),

        // 3. Farm-wise Theka Table
        Card(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          child: Padding(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'زمین وار ٹھیکہ خرچہ (Farm-wise Expenses)',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: Colors.brown,
                    fontFamily: 'Jameel Noori Nastaleeq',
                  ),
                ),
                const Divider(),
                Table(
                  columnWidths: const {
                    0: FlexColumnWidth(2),
                    1: FlexColumnWidth(1.2),
                    2: FlexColumnWidth(1.2),
                    3: FlexColumnWidth(1.2),
                  },
                  children: [
                    const TableRow(
                      children: [
                        TableCell(child: Padding(padding: EdgeInsets.symmetric(vertical: 8.0), child: Text('زمین کا نام', style: TextStyle(fontWeight: FontWeight.bold)))),
                        TableCell(child: Padding(padding: EdgeInsets.symmetric(vertical: 8.0), child: Text('کل ٹھیکہ', style: TextStyle(fontWeight: FontWeight.bold)))),
                        TableCell(child: Padding(padding: EdgeInsets.symmetric(vertical: 8.0), child: Text('اندازہ ادا شدہ', style: TextStyle(fontWeight: FontWeight.bold)))),
                        TableCell(child: Padding(padding: EdgeInsets.symmetric(vertical: 8.0), child: Text('باقی رقم', style: TextStyle(fontWeight: FontWeight.bold)))),
                      ],
                    ),
                    ...farmTotal.entries.map((entry) {
                      final farm = farmProvider.farms.firstWhere(
                        (f) => f.id == entry.key,
                        orElse: () => Farm(name: 'نامعلوم فارم', totalArea: 0.0, createdAt: ''),
                      );
                      final fTotal = entry.value;
                      final fPaid = farmPaid[entry.key] ?? 0;
                      final fPending = fTotal - fPaid;

                      return TableRow(
                        children: [
                          TableCell(child: Padding(padding: const EdgeInsets.symmetric(vertical: 8.0), child: Text(farm.name))),
                          TableCell(child: Padding(padding: const EdgeInsets.symmetric(vertical: 8.0), child: Text(Money(fTotal).format()))),
                          TableCell(child: Padding(padding: const EdgeInsets.symmetric(vertical: 8.0), child: Text(Money(fPaid).format(), style: const TextStyle(color: Colors.green)))),
                          TableCell(child: Padding(padding: const EdgeInsets.symmetric(vertical: 8.0), child: Text(Money(fPending).format(), style: const TextStyle(color: Colors.red)))),
                        ],
                      );
                    }),
                  ],
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 16),

        // 4. Seasonal Theka Table
        Card(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          child: Padding(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'موسمی ٹھیکہ خرچہ (Seasonal Expenses)',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: Colors.brown,
                    fontFamily: 'Jameel Noori Nastaleeq',
                  ),
                ),
                const Divider(),
                Table(
                  columnWidths: const {
                    0: FlexColumnWidth(2),
                    1: FlexColumnWidth(1.2),
                    2: FlexColumnWidth(1.2),
                    3: FlexColumnWidth(1.2),
                  },
                  children: [
                    const TableRow(
                      children: [
                        TableCell(child: Padding(padding: EdgeInsets.symmetric(vertical: 8.0), child: Text('سلسلہ/فصل', style: TextStyle(fontWeight: FontWeight.bold)))),
                        TableCell(child: Padding(padding: EdgeInsets.symmetric(vertical: 8.0), child: Text('کل ٹھیکہ', style: TextStyle(fontWeight: FontWeight.bold)))),
                        TableCell(child: Padding(padding: EdgeInsets.symmetric(vertical: 8.0), child: Text('ادا شدہ', style: TextStyle(fontWeight: FontWeight.bold)))),
                        TableCell(child: Padding(padding: EdgeInsets.symmetric(vertical: 8.0), child: Text('باقی رقم', style: TextStyle(fontWeight: FontWeight.bold)))),
                      ],
                    ),
                    ...seasonalTotal.entries.map((entry) {
                      final sTotal = entry.value;
                      final sPaid = seasonalPaid[entry.key] ?? 0;
                      final sPending = sTotal - sPaid;

                      return TableRow(
                        children: [
                          TableCell(child: Padding(padding: const EdgeInsets.symmetric(vertical: 8.0), child: Text(entry.key))),
                          TableCell(child: Padding(padding: const EdgeInsets.symmetric(vertical: 8.0), child: Text(Money(sTotal).format()))),
                          TableCell(child: Padding(padding: const EdgeInsets.symmetric(vertical: 8.0), child: Text(Money(sPaid).format(), style: const TextStyle(color: Colors.green)))),
                          TableCell(child: Padding(padding: const EdgeInsets.symmetric(vertical: 8.0), child: Text(Money(sPending).format(), style: const TextStyle(color: Colors.red)))),
                        ],
                      );
                    }),
                  ],
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 16),

        // 5. Yearly Theka Table
        Card(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          child: Padding(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'سالانہ ٹھیکہ خرچہ (Yearly Expenses)',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: Colors.brown,
                    fontFamily: 'Jameel Noori Nastaleeq',
                  ),
                ),
                const Divider(),
                Table(
                  columnWidths: const {
                    0: FlexColumnWidth(2),
                    1: FlexColumnWidth(1.2),
                    2: FlexColumnWidth(1.2),
                    3: FlexColumnWidth(1.2),
                  },
                  children: [
                    const TableRow(
                      children: [
                        TableCell(child: Padding(padding: EdgeInsets.symmetric(vertical: 8.0), child: Text('سال', style: TextStyle(fontWeight: FontWeight.bold)))),
                        TableCell(child: Padding(padding: EdgeInsets.symmetric(vertical: 8.0), child: Text('کل ٹھیکہ', style: TextStyle(fontWeight: FontWeight.bold)))),
                        TableCell(child: Padding(padding: EdgeInsets.symmetric(vertical: 8.0), child: Text('ادا شدہ', style: TextStyle(fontWeight: FontWeight.bold)))),
                        TableCell(child: Padding(padding: EdgeInsets.symmetric(vertical: 8.0), child: Text('باقی رقم', style: TextStyle(fontWeight: FontWeight.bold)))),
                      ],
                    ),
                    ...yearlyTotal.entries.map((entry) {
                      final yTotal = entry.value;
                      final yPaid = yearlyPaid[entry.key] ?? 0;
                      final yPending = yTotal - yPaid;

                      return TableRow(
                        children: [
                          TableCell(child: Padding(padding: const EdgeInsets.symmetric(vertical: 8.0), child: Text('${entry.key}ء'))),
                          TableCell(child: Padding(padding: const EdgeInsets.symmetric(vertical: 8.0), child: Text(Money(yTotal).format()))),
                          TableCell(child: Padding(padding: const EdgeInsets.symmetric(vertical: 8.0), child: Text(Money(yPaid).format(), style: const TextStyle(color: Colors.green)))),
                          TableCell(child: Padding(padding: const EdgeInsets.symmetric(vertical: 8.0), child: Text(Money(yPending).format(), style: const TextStyle(color: Colors.red)))),
                        ],
                      );
                    }),
                  ],
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildPLSummaryCol(String label, int amount, Color textCol) {
    return Column(
      children: [
        Text(label, style: const TextStyle(color: Colors.white70, fontSize: 13)),
        const SizedBox(height: 6),
        Text(
          Money(amount).format(),
          style: TextStyle(
            color: textCol,
            fontSize: 16,
            fontWeight: FontWeight.bold,
          ),
        ),
      ],
    );
  }

  /// Paisa amount as a grouped number ("1,250") without the روپے suffix —
  /// for labels that already carry their own unit marker ("Rs.").
  String _formatPaisaNumber(int paisa) =>
      Money(paisa).format().replaceFirst(' روپے', '');

  Widget _buildUshrReportTab(
    BuildContext context,
    UshrProvider ushrProvider,
    FarmProvider farmProvider,
    CropProvider cropProvider,
  ) {
    final ushrRecords = ushrProvider.ushrRecords;

    if (ushrRecords.isEmpty) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(24.0),
          child: Text(
            'کوئی عشر ریکارڈ موجود نہیں ہے۔\nعشر کی معلومات دیکھنے کے لیے پہلے عشر درج کریں۔',
            style: TextStyle(
              fontSize: 20,
              fontFamily: 'Jameel Noori Nastaleeq',
              color: Colors.grey,
            ),
            textAlign: TextAlign.center,
          ),
        ),
      );
    }

    int totalUshrAmount = 0;
    int totalPaidUshr = 0;
    int totalPendingUshr = 0;
    int ushrPaidInCropPaisa = 0;
    int ushrPaidInCashPaisa = 0;

    final Map<String, int> farmUshr = {};
    final Map<String, int> seasonalUshr = {};
    final Map<String, int> yearlyUshr = {};

    for (var item in ushrRecords) {
      final u = item.ushrRecord;
      totalUshrAmount += u.ushrAmountPaisa;
      
      // Same formula as UshrRecord.remainingBalancePaisa: crop-paid value is
      // qty x rate, rounded to the paisa. Types only — inclusion logic unchanged.
      final paidCropPaisa = (u.qtyPaid * u.ratePerUnitPaisa).round();
      totalPaidUshr += u.cashPaidPaisa + paidCropPaisa;
      ushrPaidInCropPaisa += paidCropPaisa;
      ushrPaidInCashPaisa += u.cashPaidPaisa;
      
      totalPendingUshr += u.remainingBalancePaisa;

      farmUshr[item.farmName] = (farmUshr[item.farmName] ?? 0) + u.ushrAmountPaisa;

      final cropNameUrdu = cropProvider.predefinedCrops[item.cropName] ?? item.cropName;
      seasonalUshr[cropNameUrdu] = (seasonalUshr[cropNameUrdu] ?? 0) + u.ushrAmountPaisa;

      final String yearStr = u.datePaid != null
          ? u.datePaid!.split('-').first
          : DateTime.now().year.toString();
      yearlyUshr[yearStr] = (yearlyUshr[yearStr] ?? 0) + u.ushrAmountPaisa;
    }

    return ListView(
      padding: const EdgeInsets.all(16.0),
      children: [
        Card(
          elevation: 4,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          color: Colors.green.shade800,
          child: Padding(
            padding: const EdgeInsets.all(20.0),
            child: Column(
              children: [
                const Text(
                  'عشر (رپورٹ و خلاصہ)',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                    fontFamily: 'Jameel Noori Nastaleeq',
                  ),
                ),
                const SizedBox(height: 16),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    _buildPLSummaryCol('کل عشر رقم', totalUshrAmount, Colors.white),
                    _buildPLSummaryCol('کل ادا شدہ عشر', totalPaidUshr, Colors.greenAccent),
                    _buildPLSummaryCol('کل واجب الادا عشر', totalPendingUshr, Colors.orangeAccent),
                  ],
                ),
                const Divider(color: Colors.white24, height: 24),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text('ادا شدہ بجنس (Crop): Rs. ${_formatPaisaNumber(ushrPaidInCropPaisa)}', style: const TextStyle(color: Colors.white70, fontSize: 13)),
                    Text('ادا شدہ بنقد (Cash): Rs. ${_formatPaisaNumber(ushrPaidInCashPaisa)}', style: const TextStyle(color: Colors.white70, fontSize: 13)),
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
                  'زمین وار عشر خلاصہ (Farm-wise Ushr)',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: Colors.green,
                    fontFamily: 'Jameel Noori Nastaleeq',
                  ),
                ),
                const Divider(),
                Table(
                  columnWidths: const {
                    0: FlexColumnWidth(2),
                    1: FlexColumnWidth(1.5),
                  },
                  children: [
                    const TableRow(
                      children: [
                        TableCell(
                          child: Padding(
                            padding: EdgeInsets.symmetric(vertical: 8.0),
                            child: Text('فارم کا نام', style: TextStyle(fontWeight: FontWeight.bold)),
                          ),
                        ),
                        TableCell(
                          child: Padding(
                            padding: EdgeInsets.symmetric(vertical: 8.0),
                            child: Text('عشر رقم (روپے)', style: TextStyle(fontWeight: FontWeight.bold), textAlign: TextAlign.left),
                          ),
                        ),
                      ],
                    ),
                    ...farmUshr.entries.map((entry) {
                      return TableRow(
                        children: [
                          TableCell(
                            child: Padding(
                              padding: const EdgeInsets.symmetric(vertical: 8.0),
                              child: Text(entry.key),
                            ),
                          ),
                          TableCell(
                            child: Padding(
                              padding: const EdgeInsets.symmetric(vertical: 8.0),
                              child: Text('Rs. ${_formatPaisaNumber(entry.value)}', textAlign: TextAlign.left),
                            ),
                          ),
                        ],
                      );
                    }),
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
                  'فصل وار عشر خلاصہ (Seasonal Ushr)',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: Colors.green,
                    fontFamily: 'Jameel Noori Nastaleeq',
                  ),
                ),
                const Divider(),
                Table(
                  columnWidths: const {
                    0: FlexColumnWidth(2),
                    1: FlexColumnWidth(1.5),
                  },
                  children: [
                    const TableRow(
                      children: [
                        TableCell(
                          child: Padding(
                            padding: EdgeInsets.symmetric(vertical: 8.0),
                            child: Text('فصل کا نام', style: TextStyle(fontWeight: FontWeight.bold)),
                          ),
                        ),
                        TableCell(
                          child: Padding(
                            padding: EdgeInsets.symmetric(vertical: 8.0),
                            child: Text('عشر رقم (روپے)', style: TextStyle(fontWeight: FontWeight.bold), textAlign: TextAlign.left),
                          ),
                        ),
                      ],
                    ),
                    ...seasonalUshr.entries.map((entry) {
                      return TableRow(
                        children: [
                          TableCell(
                            child: Padding(
                              padding: const EdgeInsets.symmetric(vertical: 8.0),
                              child: Text(entry.key),
                            ),
                          ),
                          TableCell(
                            child: Padding(
                              padding: const EdgeInsets.symmetric(vertical: 8.0),
                              child: Text('Rs. ${_formatPaisaNumber(entry.value)}', textAlign: TextAlign.left),
                            ),
                          ),
                        ],
                      );
                    }),
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
                  'سالانہ عشر خلاصہ (Yearly Ushr)',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: Colors.green,
                    fontFamily: 'Jameel Noori Nastaleeq',
                  ),
                ),
                const Divider(),
                Table(
                  columnWidths: const {
                    0: FlexColumnWidth(2),
                    1: FlexColumnWidth(1.5),
                  },
                  children: [
                    const TableRow(
                      children: [
                        TableCell(
                          child: Padding(
                            padding: EdgeInsets.symmetric(vertical: 8.0),
                            child: Text('سال', style: TextStyle(fontWeight: FontWeight.bold)),
                          ),
                        ),
                        TableCell(
                          child: Padding(
                            padding: EdgeInsets.symmetric(vertical: 8.0),
                            child: Text('عشر رقم (روپے)', style: TextStyle(fontWeight: FontWeight.bold), textAlign: TextAlign.left),
                          ),
                        ),
                      ],
                    ),
                    ...yearlyUshr.entries.map((entry) {
                      return TableRow(
                        children: [
                          TableCell(
                            child: Padding(
                              padding: const EdgeInsets.symmetric(vertical: 8.0),
                              child: Text(entry.key),
                            ),
                          ),
                          TableCell(
                            child: Padding(
                              padding: const EdgeInsets.symmetric(vertical: 8.0),
                              child: Text('Rs. ${_formatPaisaNumber(entry.value)}', textAlign: TextAlign.left),
                            ),
                          ),
                        ],
                      );
                    }),
                  ],
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 40),
      ],
    );
  }

  Widget _buildStatCol(String label, int val, Color valColor) {
    return Column(
      children: [
        Text(
          val.toString(),
          style: TextStyle(color: valColor, fontWeight: FontWeight.bold, fontSize: 18),
        ),
        const SizedBox(height: 4),
        Text(
          label,
          style: const TextStyle(color: Colors.grey, fontSize: 12),
        ),
      ],
    );
  }
}

// Simple Helper class to hold crop P&L details
class CropPL {
  final CropSeasonWithDetails details;
  final int income;
  final int expenses;
  final int net;
  final List<HarvestWithDetails> harvests;
  final List<ActivityWithDetails> activities;

  CropPL({
    required this.details,
    required this.income,
    required this.expenses,
    required this.net,
    required this.harvests,
    required this.activities,
  });
}
