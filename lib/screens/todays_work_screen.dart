import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import 'activity_form_screen.dart';
import '../providers/activity_provider.dart';
import '../providers/crop_provider.dart';
import '../providers/expense_provider.dart';
import '../providers/inventory_provider.dart';
import '../providers/harvest_provider.dart';
import '../providers/task_provider.dart';
import '../widgets/empty_state_widget.dart';

class TodaysWorkScreen extends StatelessWidget {
  const TodaysWorkScreen({super.key});

  final List<Map<String, dynamic>> activities = const [
    {'title': 'پانی لگایا', 'icon': Icons.water_drop, 'color': Colors.blue},
    {'title': 'کھاد ڈالی', 'icon': Icons.grass, 'color': Colors.green},
    {'title': 'سپرے کیا', 'icon': Icons.pest_control, 'color': Colors.orange},
    {'title': 'دوائی ڈالی', 'icon': Icons.medical_services, 'color': Colors.teal},
    {'title': 'زمین کی تیاری', 'icon': Icons.agriculture, 'color': Colors.brown},
    {'title': 'پنیری لگائی', 'icon': Icons.eco, 'color': Colors.lightGreen},
    {'title': 'پیداوار (کٹائی)', 'icon': Icons.content_cut, 'color': Colors.red},
    {'title': 'مزدور لگائے', 'icon': Icons.people, 'color': Colors.purple},
    {'title': 'ڈیزل استعمال', 'icon': Icons.local_gas_station, 'color': Colors.grey},
    {'title': 'مشینری کا استعمال', 'icon': Icons.settings, 'color': Colors.blueGrey},
    {'title': 'ٹرانسپورٹ', 'icon': Icons.local_shipping, 'color': Colors.indigo},
    {'title': 'دیگر کام', 'icon': Icons.more_horiz, 'color': Colors.black54},
  ];

  @override
  Widget build(BuildContext context) {
    final activityProvider = Provider.of<ActivityProvider>(context);
    final cropProvider = Provider.of<CropProvider>(context);
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(title: const Text('آج آپ نے کھیت میں کیا کیا؟')),
      body: RefreshIndicator(
        onRefresh: () async {
          await activityProvider.fetchActivities();
        },
        child: CustomScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          slivers: [
          // 1. Grid of Activities
          SliverPadding(
            padding: const EdgeInsets.all(12.0),
            sliver: SliverGrid(
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 2,
                crossAxisSpacing: 12,
                mainAxisSpacing: 12,
                childAspectRatio: 1.3,
              ),
              delegate: SliverChildBuilderDelegate(
                (context, index) {
                  final activity = activities[index];
                  return _buildActivityCard(
                    context,
                    title: activity['title'],
                    icon: activity['icon'],
                    color: activity['color'],
                    onTap: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => ActivityFormScreen(activityTitle: activity['title']),
                        ),
                      );
                    },
                  );
                },
                childCount: activities.length,
              ),
            ),
          ),

          // 2. Section Title: Recent Diary Entries
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.only(left: 16.0, right: 16.0, top: 24.0, bottom: 8.0),
              child: Text(
                'حالیہ سرگرمیاں (ڈیجیٹل ڈائری)',
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.bold,
                  color: theme.colorScheme.primary,
                ),
              ),
            ),
          ),

          // 3. List of Activities (Diary entries)
          activityProvider.activities.isEmpty
              ? const SliverToBoxAdapter(
                  child: Padding(
                    padding: EdgeInsets.symmetric(vertical: 20.0),
                    child: EmptyStateWidget(
                      imageAsset: 'assets/images/tractor.png',
                      message: 'آج کے لیے کوئی کام نہیں ہے',
                      subtitle: 'آپ کی آنے والی زرعی سرگرمیاں یہاں نظر آئیں گی۔',
                      fallbackIcon: Icons.agriculture,
                    ),
                  ),
                )
              : SliverList(
                  delegate: SliverChildBuilderDelegate(
                    (context, index) {
                      final item = activityProvider.activities[index];
                      final act = item.activity;
                      final cropNameUrdu = cropProvider.predefinedCrops[item.cropName] ?? item.cropName;
                      
                      // Match activity to get its color & icon
                      final match = activities.firstWhere(
                        (a) => a['title'] == act.activityType,
                        orElse: () => {'icon': Icons.task_alt, 'color': theme.colorScheme.primary},
                      );

                      return Card(
                        margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                        child: ListTile(
                          tileColor: act.isCompleted ? Colors.green.shade50 : null,
                          leading: Stack(
                            alignment: Alignment.bottomRight,
                            children: [
                              CircleAvatar(
                                backgroundColor: (match['color'] as Color).withValues(alpha: 0.1),
                                child: Icon(match['icon'] as IconData, color: match['color'] as Color),
                              ),
                              if (act.isCompleted)
                                const Icon(Icons.check_circle, color: Colors.green, size: 18),
                            ],
                          ),
                          title: Text(
                            act.activityType,
                            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
                          ),
                          subtitle: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                               Text('${item.fieldDisplayName} ($cropNameUrdu)'),
                              if (item.expenseAmount != null && item.expenseAmount! > 0)
                                Text(
                                  '${item.expenseAmount!.toStringAsFixed(0)} روپے',
                                  style: const TextStyle(
                                    color: Colors.red,
                                    fontWeight: FontWeight.bold,
                                    fontSize: 14,
                                  ),
                                ),
                              if (act.details != null && act.details!.isNotEmpty)
                                Text(
                                  act.details!,
                                  style: TextStyle(color: Colors.grey.shade600, fontSize: 14),
                                ),
                              Text(
                                DateFormat('yyyy-MM-dd HH:mm').format(DateTime.parse(act.date)),
                                style: const TextStyle(fontSize: 12, color: Colors.grey),
                              ),
                            ],
                          ),
                           trailing: PopupMenuButton<String>(
                            onSelected: (value) {
                              if (value == 'edit') {
                                Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                    builder: (_) => ActivityFormScreen(
                                      activityTitle: act.activityType,
                                      existingActivity: item,
                                    ),
                                  ),
                                );
                              } else if (value == 'duplicate') {
                                Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                    builder: (_) => ActivityFormScreen(
                                      activityTitle: act.activityType,
                                      existingActivity: item,
                                      duplicateMode: true,
                                    ),
                                  ),
                                );
                              } else if (value == 'toggle_complete') {
                                activityProvider.toggleCompleted(act.id!, !act.isCompleted);
                              } else if (value == 'delete') {
                                _confirmDeleteActivity(
                                  context,
                                  activityProvider,
                                  Provider.of<InventoryProvider>(context, listen: false),
                                  act.id!,
                                );
                              }
                            },
                            itemBuilder: (ctx) => [
                              const PopupMenuItem(value: 'edit', child: Text('ترمیم کریں')),
                              const PopupMenuItem(value: 'duplicate', child: Text('ڈپلیکیٹ بنائیں')),
                              PopupMenuItem(
                                value: 'toggle_complete',
                                child: Text(act.isCompleted ? 'نامکمل نشان کریں' : 'مکمل نشان کریں'),
                              ),
                              const PopupMenuItem(value: 'delete', child: Text('حذف کریں')),
                            ],
                          ),
                        ),
                      );
                    },
                    childCount: activityProvider.activities.length,
                  ),
                ),
          const SliverPadding(padding: EdgeInsets.only(bottom: 50)),
        ],
      ),
    ),
  );
}

  Widget _buildActivityCard(
    BuildContext context, {
    required String title,
    required IconData icon,
    required Color color,
    required VoidCallback onTap,
  }) {
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(16),
      elevation: 2,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: color.withValues(alpha: 0.2), width: 2),
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, size: 40, color: color),
              const SizedBox(height: 8),
              Text(
                title,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: Colors.black87,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _confirmDeleteActivity(
    BuildContext context,
    ActivityProvider provider,
    InventoryProvider inventoryProvider,
    int id,
  ) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text('سرگرمی حذف کریں؟', style: TextStyle(fontWeight: FontWeight.bold)),
        content: const Text('کیا آپ واقعی اس سرگرمی کو ڈائری سے حذف کرنا چاہتے ہیں؟ اس سے منسلک خرچہ بھی حذف ہو جائے گا۔'),
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
              provider.deleteActivity(id, inventoryProvider: inventoryProvider);
              Provider.of<InventoryProvider>(context, listen: false).fetchInventory();
              Provider.of<ExpenseProvider>(context, listen: false).fetchExpenses();
              Provider.of<CropProvider>(context, listen: false).fetchCropSeasons();
              Provider.of<HarvestProvider>(context, listen: false).fetchHarvests();
              Provider.of<TaskProvider>(context, listen: false).fetchTasks();
              Navigator.pop(ctx);
            },
            child: const Text('حذف کریں', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }
}
