import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import '../providers/crop_provider.dart';
import '../providers/farm_provider.dart';
import '../providers/activity_provider.dart';
import '../providers/harvest_provider.dart';
import '../widgets/empty_state_widget.dart';

class MyCropsScreen extends StatefulWidget {
  const MyCropsScreen({super.key});

  @override
  State<MyCropsScreen> createState() => _MyCropsScreenState();
}

class _MyCropsScreenState extends State<MyCropsScreen> with SingleTickerProviderStateMixin {
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
    final cropProvider = Provider.of<CropProvider>(context);
    final farmProvider = Provider.of<FarmProvider>(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('میری فصلیں', style: TextStyle(fontWeight: FontWeight.bold)),
        backgroundColor: Colors.green.shade700,
        foregroundColor: Colors.white,
        bottom: TabBar(
          controller: _tabController,
          labelColor: Colors.white,
          unselectedLabelColor: Colors.white70,
          indicatorColor: Colors.white,
          indicatorWeight: 3,
          tabs: const [
            Tab(text: 'فعال فصلیں'),
            Tab(text: 'سابقہ فصلیں'),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.add_circle_outline),
            tooltip: 'نئی فصل کاشت کریں',
            onPressed: () => _showAddCropSeasonDialog(context, farmProvider),
          ),
        ],
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          _buildCropList(context, cropProvider.activeCropSeasons, isActive: true),
          _buildCropList(context, cropProvider.harvestedCropSeasons, isActive: false),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _showAddCropSeasonDialog(context, farmProvider),
        icon: const Icon(Icons.add, color: Colors.white),
        label: const Text('نئی فصل کاشت کریں', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
        backgroundColor: Colors.green.shade700,
      ),
    );
  }

  Widget _buildCropList(BuildContext context, List<CropSeasonWithDetails> seasons, {required bool isActive}) {
    final cropProvider = Provider.of<CropProvider>(context, listen: false);
    final farmProvider = Provider.of<FarmProvider>(context, listen: false);
    final activityProvider = Provider.of<ActivityProvider>(context);
    final harvestProvider = Provider.of<HarvestProvider>(context);

    return RefreshIndicator(
      onRefresh: () async {
        await cropProvider.fetchCropSeasons();
      },
      child: seasons.isEmpty
          ? SingleChildScrollView(
              physics: const AlwaysScrollableScrollPhysics(),
              child: SizedBox(
                height: MediaQuery.of(context).size.height - kToolbarHeight - kTextTabBarHeight - MediaQuery.of(context).padding.top,
                child: EmptyStateWidget(
                  message: isActive ? 'کوئی فعال فصل موجود نہیں ہے' : 'کوئی سابقہ فصل موجود نہیں ہے',
                  subtitle: isActive ? 'کاشت شروع کرنے کے لیے نیچے بٹن دبائیں' : null,
                  fallbackIcon: Icons.grass,
                  imageAsset: 'assets/images/wheat.png',
                ),
              ),
            )
          : ListView.builder(
              padding: const EdgeInsets.only(left: 16, right: 16, top: 16, bottom: 88),
              itemCount: seasons.length,
              itemBuilder: (context, index) {
                final details = seasons[index];
                final season = details.cropSeason;
                final cropNameUrdu = cropProvider.predefinedCrops[season.cropName] ?? season.cropName;
                final cropActivities = activityProvider.activities
                    .where((act) => act.activity.cropSeasonId == season.id)
                    .toList();
                final cropHarvests = harvestProvider.harvests
                    .where((h) => h.harvest.cropSeasonId == season.id)
                    .toList();
                final timelineSteps = cropProvider.getDynamicTimelineForActivities(
                  cropActivities.map((e) => e.activity).toList(),
                );

                final totalExpense = cropActivities.fold<double>(
                  0.0,
                  (sum, act) => sum + (act.expenseAmount ?? 0.0),
                );
                final totalIncome = cropHarvests
                    .where((h) => h.sale != null)
                    .fold<double>(0.0, (sum, h) => sum + h.sale!.totalAmount);
                final totalYield = cropHarvests.fold<double>(
                  0.0,
                  (sum, h) => sum + h.harvest.quantity,
                );
                final fieldCount = details.fields.isEmpty ? 1 : details.fields.length;
                final expensePerField = cropProvider.splitAmountAcrossFields(
                  amount: totalExpense,
                  fieldCount: fieldCount,
                );
                final incomePerField = cropProvider.splitAmountAcrossFields(
                  amount: totalIncome,
                  fieldCount: fieldCount,
                );
                final yieldPerField = cropProvider.splitAmountAcrossFields(
                  amount: totalYield,
                  fieldCount: fieldCount,
                );
                final profitPerField = incomePerField - expensePerField;

                // Status border coloring matching premium layout
                final sideColor = isActive ? Colors.green.shade600 : Colors.brown.shade500;

                return Card(
                  elevation: 3,
                  margin: const EdgeInsets.only(bottom: 16),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(20),
                  ),
                  clipBehavior: Clip.antiAlias,
                  child: Container(
                    decoration: BoxDecoration(
                      border: BorderDirectional(
                        start: BorderSide(color: sideColor, width: 6),
                      ),
                    ),
                    child: ExpansionTile(
                      shape: const Border(), // remove defaults
                      collapsedShape: const Border(),
                      title: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Expanded(
                            child: Text(
                              '$cropNameUrdu (${season.variety})',
                              style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Colors.black87),
                            ),
                          ),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                            decoration: BoxDecoration(
                              color: isActive ? Colors.green.shade50 : Colors.brown.shade50,
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Text(
                              isActive ? 'کاشت شدہ' : 'کٹائی مکمل',
                              style: TextStyle(
                                color: isActive ? Colors.green.shade800 : Colors.brown.shade800,
                                fontSize: 13,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                        ],
                      ),
                      subtitle: Padding(
                        padding: const EdgeInsets.only(top: 8.0),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Icon(Icons.location_on, size: 16, color: Colors.grey.shade600),
                                const SizedBox(width: 6),
                                Text(
                                  'زمین / کھیت: ${details.farmDisplayName} - ${details.fieldDisplayName}',
                                  style: TextStyle(color: Colors.grey.shade700, fontSize: 14),
                                ),
                              ],
                            ),
                            const SizedBox(height: 4),
                            Row(
                              children: [
                                Icon(Icons.straighten, size: 15, color: Colors.grey.shade600),
                                const SizedBox(width: 6),
                                Text(
                                  'کل زیر کاشت رقبہ: ${details.totalArea.toStringAsFixed(2)} ایکڑ',
                                  style: TextStyle(color: Colors.grey.shade700, fontSize: 14),
                                ),
                              ],
                            ),
                            const SizedBox(height: 4),
                            Row(
                              children: [
                                Icon(Icons.calendar_today, size: 15, color: Colors.grey.shade600),
                                const SizedBox(width: 6),
                                Text(
                                  'کاشت کی تاریخ: ${DateFormat('dd MMM yyyy').format(DateTime.parse(season.startDate))}',
                                  style: TextStyle(color: Colors.grey.shade700, fontSize: 14),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                      leading: CircleAvatar(
                        backgroundColor: sideColor.withValues(alpha: 0.1),
                        child: Icon(Icons.grass, color: sideColor),
                      ),
                      children: [
                        const Divider(height: 1),
                        const SizedBox(height: 16),
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 16.0),
                          child: Container(
                            width: double.infinity,
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: Colors.grey.shade100,
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'مجموعی سیزن رپورٹ',
                                  style: TextStyle(
                                    fontSize: 15,
                                    fontWeight: FontWeight.bold,
                                    color: Colors.grey.shade800,
                                  ),
                                ),
                                const SizedBox(height: 8),
                                Text('کل خرچہ: ${totalExpense.toStringAsFixed(0)} روپے'),
                                Text('کل پیداوار: ${totalYield.toStringAsFixed(1)}'),
                                Text('کل آمدن: ${totalIncome.toStringAsFixed(0)} روپے'),
                                Text('کل منافع: ${(totalIncome - totalExpense).toStringAsFixed(0)} روپے'),
                              ],
                            ),
                          ),
                        ),
                        const SizedBox(height: 12),
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 16.0),
                          child: Container(
                            width: double.infinity,
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: Colors.green.shade50,
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(color: Colors.green.shade100),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text(
                                  'کھیت وار رپورٹ (اوسط تقسیم)',
                                  style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
                                ),
                                const SizedBox(height: 8),
                                ...details.fields.map((field) {
                                  return Padding(
                                    padding: const EdgeInsets.only(bottom: 6),
                                    child: Text(
                                      '${field.name}: خرچہ ${expensePerField.toStringAsFixed(0)} روپے، پیداوار ${yieldPerField.toStringAsFixed(1)}، منافع ${profitPerField.toStringAsFixed(0)} روپے',
                                      style: const TextStyle(fontSize: 13),
                                    ),
                                  );
                                }),
                              ],
                            ),
                          ),
                        ),
                        const SizedBox(height: 8),
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 16.0),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              const Text(
                                'فصل کی حقیقی ٹائم لائن:',
                                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: Colors.black87),
                              ),
                              if (isActive)
                                ElevatedButton.icon(
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: Colors.orange.shade700,
                                    foregroundColor: Colors.white,
                                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                                  ),
                                  onPressed: () => _confirmHarvestCrop(context, season.id!),
                                  icon: const Icon(Icons.check_circle_outline, size: 20),
                                  label: const Text('کٹائی مکمل کریں', style: TextStyle(fontWeight: FontWeight.bold)),
                                ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 16),
                        
                        // Optimized Timeline vertical steps (No Overlapping)
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 20.0),
                          child: ListView.builder(
                            shrinkWrap: true,
                            physics: const NeverScrollableScrollPhysics(),
                            itemCount: timelineSteps.isEmpty ? 1 : timelineSteps.length,
                            itemBuilder: (context, tIndex) {
                              if (timelineSteps.isEmpty) {
                                return Padding(
                                  padding: const EdgeInsets.only(bottom: 12),
                                  child: Text(
                                    'ابھی کوئی سرگرمی شامل نہیں ہوئی۔ جیسے ہی کام شامل ہوگا، ٹائم لائن خود بن جائے گی۔',
                                    style: TextStyle(color: Colors.grey.shade700),
                                  ),
                                );
                              }
                              final step = timelineSteps[tIndex];
                              bool isCompleted = _isTimelineStepCompleted(
                                step,
                                cropActivities,
                                cropHarvests,
                                !isActive,
                              );
                              final completionDate = _getTimelineStepCompletionDate(
                                step,
                                cropActivities,
                                cropHarvests,
                              );
                              
                              return IntrinsicHeight(
                                child: Row(
                                  crossAxisAlignment: CrossAxisAlignment.stretch,
                                  children: [
                                    Column(
                                      children: [
                                        Container(
                                          width: 22,
                                          height: 22,
                                          decoration: BoxDecoration(
                                            color: isCompleted ? Colors.green : Colors.grey.shade300,
                                            shape: BoxShape.circle,
                                            border: Border.all(
                                              color: isCompleted ? Colors.green.shade700 : Colors.grey.shade400,
                                              width: 1.5,
                                            ),
                                          ),
                                          child: isCompleted
                                              ? const Icon(Icons.check, size: 14, color: Colors.white)
                                              : null,
                                        ),
                                        if (tIndex < timelineSteps.length - 1)
                                          Expanded(
                                            child: Container(
                                              width: 2.5,
                                              color: isCompleted ? Colors.green : Colors.grey.shade300,
                                            ),
                                          ),
                                      ],
                                    ),
                                    const SizedBox(width: 14),
                                    Expanded(
                                      child: Padding(
                                        padding: const EdgeInsets.only(bottom: 20.0),
                                        child: Column(
                                          crossAxisAlignment: CrossAxisAlignment.start,
                                          children: [
                                            Text(
                                              step,
                                              style: TextStyle(
                                                fontSize: 16,
                                                color: isCompleted ? Colors.black87 : Colors.grey.shade600,
                                                fontWeight: isCompleted ? FontWeight.bold : FontWeight.normal,
                                              ),
                                            ),
                                            if (isCompleted) ...[
                                              const SizedBox(height: 4),
                                              Text(
                                                completionDate != null
                                                    ? 'تاریخِ تکمیل: $completionDate'
                                                    : 'مکمل ہو گیا',
                                                style: TextStyle(
                                                  fontSize: 13,
                                                  color: Colors.green.shade700,
                                                  fontWeight: FontWeight.w500,
                                                ),
                                              ),
                                            ],
                                          ],
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              );
                            },
                          ),
                        ),
                        
                        // Action row (Edit / Delete)
                        Container(
                          color: Colors.grey.shade50,
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.end,
                            children: [
                              TextButton.icon(
                                style: TextButton.styleFrom(foregroundColor: Colors.blueGrey),
                                onPressed: () => _showEditCropSeasonDialog(context, details, farmProvider),
                                icon: const Icon(Icons.edit_outlined),
                                label: const Text('تبدیلی کریں', style: TextStyle(fontWeight: FontWeight.bold)),
                              ),
                              const SizedBox(width: 12),
                              TextButton.icon(
                                style: TextButton.styleFrom(foregroundColor: Colors.redAccent),
                                onPressed: () => _confirmDeleteCrop(context, season.id!),
                                icon: const Icon(Icons.delete_outline),
                                label: const Text('حذف کریں', style: TextStyle(fontWeight: FontWeight.bold)),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
    );
  }

  void _showAddCropSeasonDialog(BuildContext context, FarmProvider farmProvider) {
    final cropProvider = Provider.of<CropProvider>(context, listen: false);
    final formKey = GlobalKey<FormState>();
    
    // Flatten fields for selection
    List<Map<String, dynamic>> fieldsList = [];
    for (var farm in farmProvider.farms) {
      final fields = farmProvider.getFieldsForFarm(farm.id!);
      for (var f in fields) {
        fieldsList.add({
          'id': f.id,
          'name': '${farm.name} - ${f.name} (${f.sizeAcres} ایکڑ)',
        });
      }
    }

    if (fieldsList.isEmpty) {
      showDialog(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('کھیت موجود نہیں ہے'),
          content: const Text('فصل کاشت کرنے کے لیے پہلے "میری زمینیں" والے سیکشن میں جا کر کھیت شامل کریں۔'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('اوکے'),
            ),
          ],
        ),
      );
      return;
    }

    final Set<int> selectedFieldIds = {fieldsList.first['id'] as int};
    String selectedCropKey = 'Rice';
    String? selectedVariety;
    final varietyTextController = TextEditingController();
    DateTime selectedDate = DateTime.now();

    showDialog(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (context, setState) {
            List<String> varieties = cropProvider.predefinedVarieties[selectedCropKey] ?? [];
            if (varieties.isNotEmpty && selectedVariety == null) {
              selectedVariety = varieties.first;
            }

            return AlertDialog(
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
              title: const Text('نئی فصل کاشت کریں', style: TextStyle(fontWeight: FontWeight.bold)),
              content: Form(
                key: formKey,
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Align(
                        alignment: Alignment.centerRight,
                        child: Text(
                          'کھیت منتخب کریں (ایک یا زیادہ)',
                          style: TextStyle(
                            color: Colors.grey.shade800,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                      const SizedBox(height: 8),
                      Container(
                        decoration: BoxDecoration(
                          border: Border.all(color: Colors.grey.shade300),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: fieldsList.map((f) {
                            final int id = f['id'] as int;
                            return CheckboxListTile(
                              value: selectedFieldIds.contains(id),
                              title: Text(f['name']),
                              onChanged: (val) {
                                setState(() {
                                  if (val == true) {
                                    selectedFieldIds.add(id);
                                  } else {
                                    selectedFieldIds.remove(id);
                                  }
                                  if (selectedFieldIds.isEmpty) {
                                    selectedFieldIds.add(id);
                                  }
                                });
                              },
                            );
                          }).toList(),
                        ),
                      ),
                      const SizedBox(height: 16),
                      DropdownButtonFormField<String>(
                        value: selectedCropKey,
                        decoration: const InputDecoration(
                          labelText: 'فصل کا نام',
                          border: OutlineInputBorder(borderRadius: BorderRadius.all(Radius.circular(12))),
                        ),
                        items: cropProvider.predefinedCrops.entries.map((e) {
                          return DropdownMenuItem<String>(
                            value: e.key,
                            child: Text(e.value),
                          );
                        }).toList(),
                        onChanged: (val) {
                          setState(() {
                            selectedCropKey = val!;
                            selectedVariety = null;
                            varietyTextController.clear();
                          });
                        },
                      ),
                      const SizedBox(height: 16),
                      if (varieties.isNotEmpty) ...[
                        DropdownButtonFormField<String>(
                          value: selectedVariety,
                          decoration: const InputDecoration(
                            labelText: 'قسم (Variety)',
                            border: OutlineInputBorder(borderRadius: BorderRadius.all(Radius.circular(12))),
                          ),
                          items: [
                            ...varieties.map((v) => DropdownMenuItem<String>(value: v, child: Text(v))),
                            const DropdownMenuItem<String>(value: 'Custom', child: Text('دیگر (ٹائپ کریں)')),
                          ],
                          onChanged: (val) {
                            setState(() {
                              selectedVariety = val;
                            });
                          },
                        ),
                        const SizedBox(height: 16),
                      ],
                      if (varieties.isEmpty || selectedVariety == 'Custom') ...[
                        TextFormField(
                          controller: varietyTextController,
                          decoration: const InputDecoration(
                            labelText: 'قسم کا نام لکھیں (Variety Name)',
                            border: OutlineInputBorder(borderRadius: BorderRadius.all(Radius.circular(12))),
                          ),
                          validator: (value) => value!.isEmpty ? 'براہ کرم قسم کا نام درج کریں' : null,
                        ),
                        const SizedBox(height: 16),
                      ],
                      ListTile(
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                          side: BorderSide(color: Colors.grey.shade400),
                        ),
                        title: Text('کاشت کی تاریخ: ${DateFormat('dd MMM yyyy').format(selectedDate)}'),
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
                  child: const Text('کینسل', style: TextStyle(color: Colors.grey, fontSize: 16)),
                ),
                ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.green.shade700,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                  onPressed: () {
                    if (formKey.currentState!.validate()) {
                      String variety = selectedVariety == 'Custom' || varieties.isEmpty
                          ? varietyTextController.text
                          : selectedVariety!;
                          
                      cropProvider.addCropSeason(
                        fieldIds: selectedFieldIds.toList(),
                        cropName: selectedCropKey,
                        variety: variety,
                        startDate: selectedDate.toIso8601String(),
                      );
                      Navigator.pop(ctx);
                    }
                  },
                  child: const Text('محفوظ کریں', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                ),
              ],
            );
          },
        );
      },
    );
  }

  void _confirmHarvestCrop(BuildContext context, int id) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text('کٹائی مکمل کریں؟', style: TextStyle(fontWeight: FontWeight.bold)),
        content: const Text('کیا اس فصل کی کٹائی مکمل ہو چکی ہے؟ کٹائی کے بعد یہ "سابقہ فصلیں" والے حصے میں چلی جائے گی۔'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('کینسل', style: TextStyle(color: Colors.grey, fontSize: 16)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.orange.shade700,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
            onPressed: () {
              Provider.of<CropProvider>(context, listen: false).updateCropSeasonStatus(id, 'Harvested');
              Navigator.pop(ctx);
            },
            child: const Text('ہاں، کٹائی مکمل', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }

  void _confirmDeleteCrop(BuildContext context, int id) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text('حذف کریں؟', style: TextStyle(fontWeight: FontWeight.bold)),
        content: const Text('کیا آپ واقعی اس فصل کا پورا ریکارڈ حذف کرنا چاہتے ہیں؟'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('کینسل', style: TextStyle(color: Colors.grey, fontSize: 16)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
            onPressed: () {
              Provider.of<CropProvider>(context, listen: false).deleteCropSeason(id);
              Navigator.pop(ctx);
            },
            child: const Text('حذف کریں', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }

  void _showEditCropSeasonDialog(
    BuildContext context,
    CropSeasonWithDetails details,
    FarmProvider farmProvider,
  ) {
    final cropProvider = Provider.of<CropProvider>(context, listen: false);
    final formKey = GlobalKey<FormState>();
    final season = details.cropSeason;

    // Flatten fields for selection
    List<Map<String, dynamic>> fieldsList = [];
    for (var farm in farmProvider.farms) {
      final fields = farmProvider.getFieldsForFarm(farm.id!);
      for (var f in fields) {
        fieldsList.add({
          'id': f.id,
          'name': '${farm.name} - ${f.name} (${f.sizeAcres} ایکڑ)',
        });
      }
    }

    final Set<int> selectedFieldIds = details.fields.map((f) => f.id!).toSet();
    String selectedCropKey = season.cropName;
    
    // Check if current variety is in predefined ones
    List<String> varieties = cropProvider.predefinedVarieties[selectedCropKey] ?? [];
    String? selectedVariety;
    final varietyTextController = TextEditingController();

    if (varieties.contains(season.variety)) {
      selectedVariety = season.variety;
    } else {
      if (varieties.isNotEmpty) {
        selectedVariety = 'Custom';
      }
      varietyTextController.text = season.variety;
    }

    DateTime selectedDate = DateTime.parse(season.startDate);

    showDialog(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (context, setState) {
            List<String> currentVarieties = cropProvider.predefinedVarieties[selectedCropKey] ?? [];
            if (currentVarieties.isNotEmpty && selectedVariety == null) {
              selectedVariety = currentVarieties.first;
            }

            return AlertDialog(
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
              title: const Text('فصل کے ریکارڈ میں ترمیم', style: TextStyle(fontWeight: FontWeight.bold)),
              content: Form(
                key: formKey,
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Align(
                        alignment: Alignment.centerRight,
                        child: Text(
                          'کھیت منتخب کریں (ایک یا زیادہ)',
                          style: TextStyle(
                            color: Colors.grey.shade800,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                      const SizedBox(height: 8),
                      Container(
                        decoration: BoxDecoration(
                          border: Border.all(color: Colors.grey.shade300),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: fieldsList.map((f) {
                            final int id = f['id'] as int;
                            return CheckboxListTile(
                              value: selectedFieldIds.contains(id),
                              title: Text(f['name']),
                              onChanged: (val) {
                                setState(() {
                                  if (val == true) {
                                    selectedFieldIds.add(id);
                                  } else {
                                    selectedFieldIds.remove(id);
                                  }
                                  if (selectedFieldIds.isEmpty) {
                                    selectedFieldIds.add(id);
                                  }
                                });
                              },
                            );
                          }).toList(),
                        ),
                      ),
                      const SizedBox(height: 16),
                      DropdownButtonFormField<String>(
                        value: selectedCropKey,
                        decoration: const InputDecoration(
                          labelText: 'فصل کا نام',
                          border: OutlineInputBorder(borderRadius: BorderRadius.all(Radius.circular(12))),
                        ),
                        items: cropProvider.predefinedCrops.entries.map((e) {
                          return DropdownMenuItem<String>(
                            value: e.key,
                            child: Text(e.value),
                          );
                        }).toList(),
                        onChanged: (val) {
                          setState(() {
                            selectedCropKey = val!;
                            selectedVariety = null;
                            varietyTextController.clear();
                          });
                        },
                      ),
                      const SizedBox(height: 16),
                      if (currentVarieties.isNotEmpty) ...[
                        DropdownButtonFormField<String>(
                          value: selectedVariety,
                          decoration: const InputDecoration(
                            labelText: 'قسم (Variety)',
                            border: OutlineInputBorder(borderRadius: BorderRadius.all(Radius.circular(12))),
                          ),
                          items: [
                            ...currentVarieties.map((v) => DropdownMenuItem<String>(value: v, child: Text(v))),
                            const DropdownMenuItem<String>(value: 'Custom', child: Text('دیگر (ٹائپ کریں)')),
                          ],
                          onChanged: (val) {
                            setState(() {
                              selectedVariety = val;
                            });
                          },
                        ),
                        const SizedBox(height: 16),
                      ],
                      if (currentVarieties.isEmpty || selectedVariety == 'Custom') ...[
                        TextFormField(
                          controller: varietyTextController,
                          decoration: const InputDecoration(
                            labelText: 'قسم کا نام لکھیں (Variety Name)',
                            border: OutlineInputBorder(borderRadius: BorderRadius.all(Radius.circular(12))),
                          ),
                          validator: (value) => value!.isEmpty ? 'براہ کرم قسم کا نام درج کریں' : null,
                        ),
                        const SizedBox(height: 16),
                      ],
                      ListTile(
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                          side: BorderSide(color: Colors.grey.shade400),
                        ),
                        title: Text('کاشت کی تاریخ: ${DateFormat('dd MMM yyyy').format(selectedDate)}'),
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
                  child: const Text('کینسل', style: TextStyle(color: Colors.grey, fontSize: 16)),
                ),
                ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.green.shade700,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                  onPressed: () {
                    if (formKey.currentState!.validate()) {
                      String variety = selectedVariety == 'Custom' || currentVarieties.isEmpty
                          ? varietyTextController.text
                          : selectedVariety!;
                          
                      cropProvider.updateCropSeason(
                        id: season.id!,
                        fieldIds: selectedFieldIds.toList(),
                        cropName: selectedCropKey,
                        variety: variety,
                        status: season.status,
                        startDate: selectedDate.toIso8601String(),
                      );
                      Navigator.pop(ctx);
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('فصل کی تفصیلات کامیابی سے تبدیل ہو گئیں!')),
                      );
                    }
                  },
                  child: const Text('محفوظ کریں', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                ),
              ],
            );
          },
        );
      },
    );
  }

  bool _isTimelineStepCompleted(
    String step,
    List<ActivityWithDetails> cropActivities,
    List<HarvestWithDetails> cropHarvests,
    bool isCompletedCrop,
  ) {
    if (isCompletedCrop) {
      return true;
    }

    if (cropActivities.any((act) => act.activity.activityType == step)) {
      return true;
    }

    if (step.toLowerCase().contains('harvest') || step.contains('کٹائی')) {
      return cropHarvests.isNotEmpty;
    }

    return false;
  }

  String? _getTimelineStepCompletionDate(
    String step,
    List<ActivityWithDetails> cropActivities,
    List<HarvestWithDetails> cropHarvests,
  ) {
    final sortedActs = List<ActivityWithDetails>.from(cropActivities)
      ..sort((a, b) => a.activity.date.compareTo(b.activity.date));
    final sortedHarvests = List<HarvestWithDetails>.from(cropHarvests)
      ..sort((a, b) => a.harvest.date.compareTo(b.harvest.date));

    String formatDate(String isoString) {
      try {
        return DateFormat('dd MMM yyyy').format(DateTime.parse(isoString));
      } catch (_) {
        return '';
      }
    }

    for (final act in sortedActs) {
      if (act.activity.activityType == step) {
        return formatDate(act.activity.date);
      }
    }

    if (step.toLowerCase().contains('harvest') || step.contains('کٹائی')) {
      if (sortedHarvests.isNotEmpty) {
        return formatDate(sortedHarvests.first.harvest.date);
      }
    }

    return null;
  }
}
