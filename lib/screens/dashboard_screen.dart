import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../services/notification_service.dart';
import '../services/today_summary.dart';
import '../services/money.dart';
import '../models/models.dart';
import '../providers/task_provider.dart';
import '../providers/expense_provider.dart';
import '../providers/harvest_provider.dart';
import '../providers/theka_provider.dart';
import '../providers/crop_provider.dart';
import '../providers/farm_provider.dart';
import '../providers/party_provider.dart';
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
import 'task_form_screen.dart';
import 'theka_list_screen.dart';
import 'ushr_screen.dart';
import 'parties_screen.dart';
import 'batai_screen.dart';

/// Farmer home: answers within seconds —
/// (1) what needs doing today, (2) the money situation, (3) crop activity —
/// then quick actions and the full feature menu. All navigation destinations
/// from the old grid are preserved below in "تمام سہولتیں".
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
                      Text('ترتیبات', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                    ],
                  ),
                ),
                const PopupMenuItem<String>(
                  value: 'share',
                  child: Row(
                    children: [
                      Icon(Icons.share_outlined, color: Colors.black87),
                      SizedBox(width: 12),
                      Text('ایپ شیئر کریں', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
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
            _buildHeader(),
            const SizedBox(height: 16),
            _buildTodaySection(),
            const SizedBox(height: 16),
            _buildMoneySection(),
            const SizedBox(height: 16),
            _buildCropSection(),
            const SizedBox(height: 16),
            _buildQuickActions(),
            const SizedBox(height: 20),
            const Text(
              'تمام سہولتیں',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 12),
            _buildAllFeatures(),
          ],
        ),
      ),
    );
  }

  // ---------- 1. TODAY header: greeting + Urdu date + farm ----------

  Widget _buildHeader() {
    final now = DateTime.now();
    return Consumer<FarmProvider>(
      builder: (context, farmProvider, _) {
        if (farmProvider.errorMessage != null) {
          return _sectionErrorCard(
            farmProvider.errorMessage!,
            () => farmProvider.fetchFarms(),
          );
        }
        final farms = farmProvider.farms;
        final String farmLine;
        if (farms.isEmpty) {
          farmLine = 'آج سے اپنی ڈیجیٹل ڈائری شروع کریں';
        } else if (farms.length == 1) {
          farmLine = 'زمین: ${farms.first.name}';
        } else {
          farmLine = '${farms.length} زمینیں';
        }
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              greetingFor(now),
              style: const TextStyle(fontSize: 26, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 4),
            Text(
              urduDateLine(now),
              style: TextStyle(fontSize: 16, color: Colors.grey.shade700),
            ),
            const SizedBox(height: 2),
            Text(
              farmLine,
              style: TextStyle(
                fontSize: 15,
                color: Theme.of(context).primaryColor,
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        );
      },
    );
  }

  // ---------- 2. Today's work ----------

  Widget _buildTodaySection() {
    return Consumer<TaskProvider>(
      builder: (context, taskProvider, _) {
        if (taskProvider.errorMessage != null) {
          return _sectionErrorCard(
            taskProvider.errorMessage!,
            () => taskProvider.fetchTasks(),
          );
        }
        final now = DateTime.now();
        final items = todaysTasks(taskProvider.tasks, now).take(5).toList();
        return _sectionCard(
          title: 'آج کے کام',
          icon: Icons.checklist_rtl,
          seeAllLabel: 'تمام کام',
          onSeeAll: () => Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => const TasksScreen()),
          ),
          child: items.isEmpty
              ? _emptyLine('آج کے لیے کوئی کام شیڈول نہیں ہے — آپ کی ڈائری اپ ٹو ڈیٹ ہے!')
              : Column(
                  children: [
                    for (final t in items) _taskRow(context, taskProvider, t, now),
                    if (todaysTasks(taskProvider.tasks, now).length > 5)
                      const Padding(
                        padding: EdgeInsets.only(top: 4),
                        child: Text('…اور مزید', style: TextStyle(color: Colors.grey)),
                      ),
                  ],
                ),
        );
      },
    );
  }

  Widget _taskRow(BuildContext context, TaskProvider taskProvider, TaskItem task, DateTime now) {
    final overdue = isTaskOverdue(task, now);
    return InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: () => Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => TaskFormScreen(task: task)),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 4),
        child: Row(
          children: [
            InkWell(
              onTap: () => taskProvider.toggleTaskCompletion(task.id, task.isCompleted),
              borderRadius: BorderRadius.circular(24),
              child: Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: task.isCompleted ? Colors.green : Colors.grey,
                    width: 2,
                  ),
                  color: task.isCompleted ? Colors.green : Colors.transparent,
                ),
                child: task.isCompleted
                    ? const Icon(Icons.check, size: 24, color: Colors.white)
                    : null,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    task.title,
                    style: TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.bold,
                      decoration: task.isCompleted ? TextDecoration.lineThrough : null,
                    ),
                  ),
                  const SizedBox(height: 4),
                  if (overdue)
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
                      decoration: BoxDecoration(
                        color: Colors.red.shade50,
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: Colors.red.shade300),
                      ),
                      child: Text(
                        'زائد المیعاد',
                        style: TextStyle(
                          color: Colors.red.shade700,
                          fontSize: 13,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    )
                  else
                    Text(
                      urduTimeOfDay(task.dateTime),
                      style: TextStyle(fontSize: 14, color: Colors.grey.shade600),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ---------- 3. Money snapshot ----------

  Widget _buildMoneySection() {
    return Consumer4<ExpenseProvider, HarvestProvider, ThekaProvider,
        PartyProvider>(
      builder:
          (context, expenseProvider, harvestProvider, thekaProvider, partyProvider, _) {
        final error = expenseProvider.errorMessage ??
            harvestProvider.errorMessage ??
            thekaProvider.errorMessage ??
            partyProvider.errorMessage;
        if (error != null) {
          return _sectionErrorCard(error, () {
            expenseProvider.fetchExpenses();
            harvestProvider.fetchHarvests();
            thekaProvider.fetchThekas();
            partyProvider.fetchParties();
          });
        }
        final now = DateTime.now();
        final todayPaisa = expensesOnDayPaisa(expenseProvider.expenses, now);
        final monthExpensePaisa = expensesInMonthPaisa(expenseProvider.expenses, now);
        final monthIncomePaisa = salesInMonthPaisa(harvestProvider.sales, now);
        final dueSoon = dueSoonInstallments(thekaProvider.allInstallments, now);
        final receivablePaisa = partyProvider.totalReceivablePaisa;
        final payablePaisa = partyProvider.totalPayablePaisa;
        final hasAnyData = expenseProvider.expenses.isNotEmpty ||
            harvestProvider.sales.isNotEmpty ||
            thekaProvider.allInstallments.isNotEmpty ||
            receivablePaisa > 0 ||
            payablePaisa > 0;

        return _sectionCard(
          title: 'رقم کی صورتحال',
          icon: Icons.account_balance_wallet_outlined,
          child: !hasAnyData
              ? _emptyLine('ابھی کوئی لین دین ریکارڈ نہیں — پہلا خرچ لکھ کر شروع کریں۔')
              : Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        _moneyStat('آج کے خرچے', todayPaisa, Colors.red.shade600),
                        const SizedBox(width: 10),
                        _moneyStat('اس ماہ خرچے', monthExpensePaisa, Colors.orange.shade700),
                        const SizedBox(width: 10),
                        _moneyStat('اس ماہ آمدنی', monthIncomePaisa, Colors.green.shade700),
                      ],
                    ),
                    if (dueSoon.isNotEmpty) ...[
                      const SizedBox(height: 14),
                      const Divider(height: 1),
                      const SizedBox(height: 10),
                      const Text(
                        'جلد واجب الادا ٹھیکہ قسطیں',
                        style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 6),
                      for (final inst in dueSoon.take(3))
                        _installmentRow(context, thekaProvider, inst, now),
                    ],
                    if (receivablePaisa > 0 || payablePaisa > 0) ...[
                      const SizedBox(height: 14),
                      const Divider(height: 1),
                      const SizedBox(height: 10),
                      if (receivablePaisa > 0)
                        _partyBalanceLine('لوگوں سے لینا ہے', receivablePaisa,
                            Colors.green.shade700),
                      if (payablePaisa > 0)
                        _partyBalanceLine('لوگوں کو دینا ہے', payablePaisa,
                            Colors.red.shade700),
                    ],
                  ],
                ),
        );
      },
    );
  }

  Widget _partyBalanceLine(String label, int paisa, Color color) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Icon(Icons.people_outline, size: 18, color: color),
          const SizedBox(width: 8),
          Text(label, style: const TextStyle(fontSize: 15)),
          const Spacer(),
          Text(
            Money(paisa).format(),
            style: TextStyle(
                fontSize: 16, fontWeight: FontWeight.bold, color: color),
          ),
        ],
      ),
    );
  }

  Widget _moneyStat(String label, int paisa, Color color) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 6),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: color.withValues(alpha: 0.25)),
        ),
        child: Column(
          children: [
            Text(label, style: TextStyle(fontSize: 13, color: Colors.grey.shade700)),
            const SizedBox(height: 6),
            Text(
              Money(paisa).format(),
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: color),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }

  Widget _installmentRow(
    BuildContext context,
    ThekaProvider thekaProvider,
    ThekaInstallment inst,
    DateTime now,
  ) {
    final due = tryParseStoredDate(inst.dueDate);
    final dueDay = due == null ? null : DateTime(due.year, due.month, due.day);
    final today = DateTime(now.year, now.month, now.day);
    final overdue = dueDay != null && dueDay.isBefore(today);
    final theka = thekaProvider.getThekaById(inst.thekaId);
    String? farmName;
    if (theka != null) {
      final farms = Provider.of<FarmProvider>(context, listen: false).farms;
      for (final f in farms) {
        if (f.id == theka.farmId) {
          farmName = f.name;
          break;
        }
      }
    }
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          Icon(Icons.event_note, color: overdue ? Colors.red : Colors.orange.shade700),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'ٹھیکہ قسط${farmName != null ? ' — $farmName' : ''}',
                  style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
                ),
                Text(
                  dueDay == null
                      ? 'آخری تاریخ نامعلوم'
                      : 'آخری تاریخ: ${urduShortDate(dueDay)}${overdue ? ' (زائد المیعاد)' : ''}',
                  style: TextStyle(
                    fontSize: 13,
                    color: overdue ? Colors.red.shade700 : Colors.grey.shade600,
                    fontWeight: overdue ? FontWeight.bold : FontWeight.normal,
                  ),
                ),
              ],
            ),
          ),
          Text(
            Money(remainingPaisa(inst)).format(),
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.bold,
              color: overdue ? Colors.red.shade700 : Colors.orange.shade800,
            ),
          ),
        ],
      ),
    );
  }

  // ---------- 4. Crop activity ----------

  Widget _buildCropSection() {
    return Consumer2<CropProvider, HarvestProvider>(
      builder: (context, cropProvider, harvestProvider, _) {
        final error = cropProvider.errorMessage ?? harvestProvider.errorMessage;
        if (error != null) {
          return _sectionErrorCard(error, () {
            cropProvider.fetchCropSeasons();
            harvestProvider.fetchHarvests();
          });
        }
        final active = cropProvider.activeCropSeasons.take(4).toList();

        // Most recent sale by date (parsed defensively).
        Sale? latestSale;
        DateTime? latestDate;
        for (final s in harvestProvider.sales) {
          final d = tryParseStoredDate(s.date);
          if (d == null) continue;
          if (latestDate == null || d.isAfter(latestDate)) {
            latestDate = d;
            latestSale = s;
          }
        }
        String? latestCropName;
        if (latestSale != null) {
          for (final h in harvestProvider.harvests) {
            if (h.harvest.id == latestSale.harvestId) {
              latestCropName = h.cropName;
              break;
            }
          }
        }

        final hasContent = active.isNotEmpty || latestSale != null;
        return _sectionCard(
          title: 'فصلوں کی صورتحال',
          icon: Icons.grass,
          seeAllLabel: 'تمام فصلیں',
          onSeeAll: () => Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => const MyCropsScreen()),
          ),
          child: !hasContent
              ? _emptyLine('ابھی کوئی فصل درج نہیں — نئے سیزن کی فصل لکھ کر شروع کریں۔')
              : Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    for (final s in active)
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 6),
                        child: Row(
                          children: [
                            Icon(Icons.spa, color: Colors.green.shade700),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Text(
                                s.cropSeason.cropName,
                                style: const TextStyle(
                                    fontSize: 16, fontWeight: FontWeight.bold),
                              ),
                            ),
                            Text(
                              s.farmDisplayName.isNotEmpty
                                  ? s.farmDisplayName
                                  : s.fieldDisplayName,
                              style: TextStyle(
                                  fontSize: 13, color: Colors.grey.shade600),
                            ),
                          ],
                        ),
                      ),
                    if (latestSale != null) ...[
                      const Divider(height: 20),
                      Row(
                        children: [
                          Icon(Icons.sell_outlined,
                              color: Colors.teal.shade700),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              'آخری فروخت${latestCropName != null ? ': $latestCropName' : ''}',
                              style: const TextStyle(fontSize: 15),
                            ),
                          ),
                          Text(
                            Money(latestSale.totalAmountPaisa).format(),
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                              color: Colors.teal.shade800,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ],
                ),
        );
      },
    );
  }

  // ---------- 5. Quick actions ----------

  Widget _buildQuickActions() {
    return Row(
      children: [
        _quickAction(
          icon: Icons.add_card,
          label: 'خرچ لکھیں',
          color: Colors.red.shade600,
          onTap: () => Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => const ExpensesScreen()),
          ),
        ),
        const SizedBox(width: 12),
        _quickAction(
          icon: Icons.add_task,
          label: 'کام لکھیں',
          color: Colors.deepPurple.shade600,
          onTap: () => Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => const TaskFormScreen()),
          ),
        ),
        const SizedBox(width: 12),
        _quickAction(
          icon: Icons.grass,
          label: 'فصل دیکھیں',
          color: Colors.green.shade700,
          onTap: () => Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => const MyCropsScreen()),
          ),
        ),
      ],
    );
  }

  Widget _quickAction({
    required IconData icon,
    required String label,
    required Color color,
    required VoidCallback onTap,
  }) {
    return Expanded(
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(20),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 22),
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.10),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: color.withValues(alpha: 0.30), width: 1.5),
          ),
          child: Column(
            children: [
              Icon(icon, size: 34, color: color),
              const SizedBox(height: 10),
              Text(
                label,
                style: TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.bold,
                  color: color,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ---------- 6. Full feature menu (all destinations preserved) ----------

  Widget _buildAllFeatures() {
    final tiles = [
      _FeatureTile(Icons.landscape, 'میری زمینیں', Colors.brown.shade600,
          () => _push(const MyFarmsScreen())),
      _FeatureTile(Icons.grass, 'میری فصلیں', Colors.green.shade600,
          () => _push(const MyCropsScreen())),
      _FeatureTile(Icons.add_circle, 'آج کا کام', Colors.blue.shade600,
          () => _push(const TodaysWorkScreen())),
      _FeatureTile(Icons.money_off, 'خرچے', Colors.red.shade500,
          () => _push(const ExpensesScreen())),
      _FeatureTile(Icons.agriculture, 'پیداوار', Colors.orange.shade600,
          () => _push(const HarvestScreen())),
      _FeatureTile(Icons.inventory, 'گودام (اسٹاک)', Colors.blueGrey.shade600,
          () => _push(const InventoryScreen())),
      _FeatureTile(Icons.account_balance_wallet, 'منافع و نقصان',
          Colors.teal.shade600, () => _push(const ProfitLossScreen())),
      _FeatureTile(Icons.checklist_rtl, 'کام کی منصوبہ بندی',
          Colors.deepPurple.shade600, () => _push(const TasksScreen())),
      _FeatureTile(Icons.description_outlined, 'ٹھیکہ مینجمنٹ',
          Colors.brown.shade800, () => _push(const ThekaListScreen())),
      _FeatureTile(Icons.volunteer_activism, 'عشر مینجمنٹ',
          Colors.green.shade800, () => _push(const UshrScreen())),
      _FeatureTile(Icons.people_outline, 'پارٹی کھاتہ',
          Colors.indigo.shade600, () => _push(const PartiesScreen())),
      _FeatureTile(Icons.handshake_outlined, 'بٹائی',
          Colors.amber.shade800, () => _push(const BataiScreen())),
    ];
    return GridView.count(
      crossAxisCount: 3,
      crossAxisSpacing: 12,
      mainAxisSpacing: 12,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      children: [for (final t in tiles) _compactTile(t)],
    );
  }

  void _push(Widget screen) {
    Navigator.push(context, MaterialPageRoute(builder: (_) => screen));
  }

  Widget _compactTile(_FeatureTile tile) {
    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: InkWell(
        onTap: tile.onTap,
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 4),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(tile.icon, size: 30, color: tile.color),
              const SizedBox(height: 8),
              Text(
                tile.label,
                style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ---------- Shared section widgets ----------

  Widget _sectionCard({
    required String title,
    required IconData icon,
    required Widget child,
    String? seeAllLabel,
    VoidCallback? onSeeAll,
  }) {
    return Card(
      elevation: 3,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, color: Theme.of(context).primaryColor),
                const SizedBox(width: 8),
                Text(
                  title,
                  style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                ),
                const Spacer(),
                if (onSeeAll != null)
                  TextButton(
                    onPressed: onSeeAll,
                    child: Text(seeAllLabel ?? 'سب دیکھیں'),
                  ),
              ],
            ),
            const SizedBox(height: 8),
            child,
          ],
        ),
      ),
    );
  }

  Widget _sectionErrorCard(String message, VoidCallback onRetry) {
    return Card(
      elevation: 3,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            const Icon(Icons.error_outline, color: Colors.red, size: 32),
            const SizedBox(width: 12),
            Expanded(
              child: Text(message, style: const TextStyle(fontSize: 15)),
            ),
            TextButton(
              onPressed: onRetry,
              child: const Text('دوبارہ کوشش کریں'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _emptyLine(String message) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Row(
        children: [
          Icon(Icons.eco_outlined, color: Colors.green.shade600, size: 28),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              message,
              style: TextStyle(fontSize: 15, color: Colors.grey.shade700, height: 1.6),
            ),
          ),
        ],
      ),
    );
  }
}

class _FeatureTile {
  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback onTap;

  _FeatureTile(this.icon, this.label, this.color, this.onTap);
}
