import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../services/notification_service.dart';
import '../providers/task_provider.dart';
import 'alarm_screen.dart';
import 'about_us_screen.dart';
import 'settings_screen.dart';
import 'my_farms_screen.dart';
import 'my_crops_screen.dart';
import 'todays_work_screen.dart';
import 'expenses_screen.dart';
import 'harvest_screen.dart';
import 'profit_loss_screen.dart';
import 'inventory_screen.dart';
import 'tasks_screen.dart';
import 'theka_list_screen.dart';
import 'ushr_screen.dart';

class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key});

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  static const _shareChannel = MethodChannel('com.example.kisan_dost/share');

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _checkNotificationLaunch();
      context.read<TaskProvider>().fetchTasks();
    });
  }

  void _checkNotificationLaunch() {
    if (NotificationService.launchPayload != null) {
      final payload = NotificationService.launchPayload;
      NotificationService.launchPayload = null; // Clear so it only runs once
      if (payload != null) {
        final taskId = int.tryParse(payload);
        if (taskId != null) {
          Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => AlarmScreen(taskId: taskId)),
          );
        }
      }
    }
  }

  Future<void> _shareApk() async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      messenger.showSnackBar(
        const SnackBar(
          content: Text('ایپ فائل (APK) شیئر کرنے کی تیاری ہو رہی ہے...', style: TextStyle(fontSize: 16)),
          duration: Duration(seconds: 2),
        ),
      );
      await _shareChannel.invokeMethod('shareApk');
    } on PlatformException catch (e) {
      messenger.showSnackBar(
        SnackBar(
          content: Text('ایپ شیئرنگ میں خرابی پیش آئی: ${e.message}', style: const TextStyle(fontSize: 16)),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('کسان دوست', style: TextStyle(fontWeight: FontWeight.bold)),
        actions: [
          PopupMenuButton<String>(
            icon: const Icon(Icons.more_vert),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            onSelected: (value) {
              if (value == 'about') {
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const AboutUsScreen()),
                );
              } else if (value == 'settings') {
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const SettingsScreen()),
                );
              } else if (value == 'share') {
                _shareApk();
              }
            },
            itemBuilder: (BuildContext context) {
              return [
                const PopupMenuItem<String>(
                  value: 'about',
                  child: Row(
                    children: [
                      Icon(Icons.info_outline, color: Colors.black87),
                      SizedBox(width: 12),
                      Text('ایپ کے بارے میں', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                    ],
                  ),
                ),
                const PopupMenuItem<String>(
                  value: 'settings',
                  child: Row(
                    children: [
                      Icon(Icons.settings_outlined, color: Colors.black87),
                      SizedBox(width: 12),
                      Text('ترتیبات (Settings)', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                    ],
                  ),
                ),
                const PopupMenuItem<String>(
                  value: 'share',
                  child: Row(
                    children: [
                      Icon(Icons.share_outlined, color: Colors.black87),
                      SizedBox(width: 12),
                      Text('ایپ شیئر کریں (APK)', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                    ],
                  ),
                ),
              ];
            },
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _buildTaskSummaryCard(),
            const SizedBox(height: 20),
            GridView.count(
              crossAxisCount: 2,
              crossAxisSpacing: 16,
              mainAxisSpacing: 16,
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              children: [
                _buildDashboardButton(
                  context,
                  icon: Icons.landscape,
                  label: 'میری زمینیں',
                  color: Colors.brown.shade600,
                  onTap: () {
                    Navigator.push(context, MaterialPageRoute(builder: (_) => const MyFarmsScreen()));
                  },
                ),
                _buildDashboardButton(
                  context,
                  icon: Icons.grass,
                  label: 'میری فصلیں',
                  color: Colors.green.shade600,
                  onTap: () {
                    Navigator.push(context, MaterialPageRoute(builder: (_) => const MyCropsScreen()));
                  },
                ),
                _buildDashboardButton(
                  context,
                  icon: Icons.add_circle,
                  label: 'آج کا کام',
                  color: Colors.blue.shade600,
                  onTap: () {
                    Navigator.push(context, MaterialPageRoute(builder: (_) => const TodaysWorkScreen()));
                  },
                ),
                _buildDashboardButton(
                  context,
                  icon: Icons.money_off,
                  label: 'خرچے',
                  color: Colors.red.shade500,
                  onTap: () {
                    Navigator.push(context, MaterialPageRoute(builder: (_) => const ExpensesScreen()));
                  },
                ),
                _buildDashboardButton(
                  context,
                  icon: Icons.agriculture,
                  label: 'پیداوار',
                  color: Colors.orange.shade600,
                  onTap: () {
                    Navigator.push(context, MaterialPageRoute(builder: (_) => const HarvestScreen()));
                  },
                ),
                _buildDashboardButton(
                  context,
                  icon: Icons.inventory,
                  label: 'گودام (اسٹاک)',
                  color: Colors.blueGrey.shade600,
                  onTap: () {
                    Navigator.push(context, MaterialPageRoute(builder: (_) => const InventoryScreen()));
                  },
                ),
                _buildDashboardButton(
                  context,
                  icon: Icons.account_balance_wallet,
                  label: 'منافع و نقصان',
                  color: Colors.teal.shade600,
                  onTap: () {
                    Navigator.push(context, MaterialPageRoute(builder: (_) => const ProfitLossScreen()));
                  },
                ),
                _buildDashboardButton(
                  context,
                  icon: Icons.checklist_rtl,
                  label: 'کام کی منصوبہ بندی',
                  color: Colors.deepPurple.shade600,
                  onTap: () {
                    Navigator.push(context, MaterialPageRoute(builder: (_) => const TasksScreen()));
                  },
                ),
                _buildDashboardButton(
                  context,
                  icon: Icons.description_outlined,
                  label: 'ٹھیکہ مینجمنٹ',
                  color: Colors.brown.shade800,
                  onTap: () {
                    Navigator.push(context, MaterialPageRoute(builder: (_) => const ThekaListScreen()));
                  },
                ),
                _buildDashboardButton(
                  context,
                  icon: Icons.volunteer_activism,
                  label: 'عشر مینجمنٹ',
                  color: Colors.green.shade800,
                  onTap: () {
                    Navigator.push(context, MaterialPageRoute(builder: (_) => const UshrScreen()));
                  },
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDashboardButton(
    BuildContext context, {
    required IconData icon,
    required String label,
    required Color color,
    required VoidCallback onTap,
  }) {
    return Card(
      elevation: 4,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      shadowColor: color.withValues(alpha: 0.2),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(20),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.1),
                shape: BoxShape.circle,
              ),
              child: Icon(icon, size: 36, color: color),
            ),
            const SizedBox(height: 12),
            Text(
              label,
              style: const TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                fontFamily: 'Jameel Noori Nastaleeq',
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTaskSummaryCard() {
    return Consumer<TaskProvider>(
      builder: (context, taskProvider, child) {
        final tasks = taskProvider.tasks;
        final total = tasks.length;
        final completed = tasks.where((t) => t.isCompleted).length;
        final now = DateTime.now();
        
        bool isSameDay(DateTime a, DateTime b) {
          return a.year == b.year && a.month == b.month && a.day == b.day;
        }

        final overdue = tasks.where((t) => !t.isCompleted && t.dateTime.isBefore(now) && (t.snoozedUntil == null || t.snoozedUntil!.isBefore(now))).length;
        final today = tasks.where((t) => !t.isCompleted && isSameDay(t.dateTime, now) && t.dateTime.isAfter(now)).length;
        final upcoming = tasks.where((t) => !t.isCompleted && !isSameDay(t.dateTime, now) && t.dateTime.isAfter(now)).length;

        // Build list of message sentences
        final List<String> messages = [];
        if (today > 0) {
          messages.add('آج آپ کے لیے $today زرعی کام شیڈول ہیں۔');
        }
        if (upcoming > 0) {
          messages.add('مستقبل کے لیے $upcoming کام شیڈول ہیں۔');
        }
        if (overdue > 0) {
          messages.add('$overdue کام التوا (اوورڈیو) کا شکار ہیں!');
        }

        final summaryMessage = messages.isEmpty 
            ? 'آج کوئی کام باقی نہیں ہے۔ آپ کی فارمنگ ڈائری اپ ٹو ڈیٹ ہے!' 
            : messages.join(' ');

        return Card(
          elevation: 4,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
          shadowColor: Colors.deepPurple.withValues(alpha: 0.15),
          child: Container(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [Colors.deepPurple.shade600, Colors.indigo.shade700],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(24),
            ),
            padding: const EdgeInsets.all(20.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Icon(Icons.checklist_rtl_rounded, color: Colors.yellowAccent, size: 28),
                    const SizedBox(width: 10),
                    const Text(
                      'زرعی سرگرمیاں اور یاد دہانیاں',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        fontFamily: 'Jameel Noori Nastaleeq',
                      ),
                    ),
                    const Spacer(),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                        color: Colors.white24,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Text(
                        'کل: $total',
                        style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                Text(
                  summaryMessage,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 16,
                    height: 1.6,
                    fontFamily: 'Jameel Noori Nastaleeq',
                  ),
                ),
                const Divider(color: Colors.white24, height: 24, thickness: 1),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    _buildMiniBadge(label: 'آج', count: today, color: Colors.amberAccent),
                    _buildMiniBadge(label: 'آنے والے', count: upcoming, color: Colors.greenAccent),
                    _buildMiniBadge(label: 'تاخیر', count: overdue, color: Colors.redAccent),
                    _buildMiniBadge(label: 'مکمل', count: completed, color: Colors.cyanAccent),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildMiniBadge({required String label, required int count, required Color color}) {
    return Column(
      children: [
        Text(
          count.toString(),
          style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: color),
        ),
        const SizedBox(height: 4),
        Text(
          label,
          style: const TextStyle(color: Colors.white70, fontSize: 12),
        ),
      ],
    );
  }
}
