import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter/services.dart';
import '../services/notification_service.dart';
import '../services/demo_data_service.dart';
import '../database/db_helper.dart';
import 'backup_screen.dart';
import 'recycle_bin_screen.dart';
import 'audit_log_screen.dart';
import '../providers/task_provider.dart';
import '../providers/farm_provider.dart';
import '../providers/crop_provider.dart';
import '../providers/inventory_provider.dart';
import '../providers/activity_provider.dart';
import '../providers/harvest_provider.dart';
import '../providers/expense_provider.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  bool _remindersEnabled = true;
  bool _alarmSoundEnabled = true;
  bool _vibrationEnabled = true;
  int _snoozeDuration = 10;
  bool _prefAtTime = true;
  bool _pref1h = true;
  bool _pref1d = true;
  bool _isLoading = true;
  bool _isIgnoringBattery = false;
  bool _canFullScreen = true;
  bool _canScheduleExact = true;

  static const _channel = MethodChannel('com.talhagohar.kisandost/share');

  @override
  void initState() {
    super.initState();
    _loadPreferences();
    _checkBatteryIgnoreStatus();
    _checkFullScreenStatus();
    _checkExactAlarmStatus();
  }

  Future<void> _checkBatteryIgnoreStatus() async {
    try {
      final bool ignoring = await _channel.invokeMethod(
        'isIgnoringBatteryOptimizations',
      );
      setState(() {
        _isIgnoringBattery = ignoring;
      });
    } catch (e) {
      debugPrint('Failed to query battery status: $e');
    }
  }

  Future<void> _checkAndRequestBatteryBypass() async {
    try {
      if (_isIgnoringBattery) {
        await _channel.invokeMethod('openBatterySettings');
      } else {
        await _channel.invokeMethod('requestIgnoreBatteryOptimizations');
      }
      // Recheck status after return
      Future.delayed(const Duration(seconds: 2), () {
        _checkBatteryIgnoreStatus();
      });
    } catch (e) {
      debugPrint('Failed battery bypass call: $e');
    }
  }

  Future<void> _checkFullScreenStatus() async {
    try {
      final bool canFullScreen = await _channel.invokeMethod(
        'canUseFullScreenIntent',
      );
      setState(() {
        _canFullScreen = canFullScreen;
      });
    } catch (e) {
      debugPrint('Failed to query full screen intent status: $e');
    }
  }

  Future<void> _requestFullScreenPermission() async {
    try {
      await _channel.invokeMethod('requestFullScreenIntentPermission');
      Future.delayed(const Duration(seconds: 2), () {
        _checkFullScreenStatus();
      });
    } catch (e) {
      debugPrint('Failed to request full screen intent permission: $e');
    }
  }

  Future<void> _checkExactAlarmStatus() async {
    final bool canExact = await NotificationService().canScheduleExactAlarms();
    setState(() {
      _canScheduleExact = canExact;
    });
  }

  Future<void> _requestExactAlarmPermission() async {
    await NotificationService().requestExactAlarmPermission();
    Future.delayed(const Duration(seconds: 2), () {
      _checkExactAlarmStatus();
    });
  }

  Future<void> _openAppSettings() async {
    try {
      await _channel.invokeMethod('openAppSettings');
    } catch (e) {
      debugPrint('Failed opening app details: $e');
    }
  }

  Future<void> _loadPreferences() async {
    final prefs = await SharedPreferences.getInstance();
    final canExact = await NotificationService().canScheduleExactAlarms();
    setState(() {
      _remindersEnabled = prefs.getBool('reminders_enabled') ?? true;
      _alarmSoundEnabled = prefs.getBool('alarm_sound_enabled') ?? true;
      _vibrationEnabled = prefs.getBool('vibration_enabled') ?? true;
      _snoozeDuration = prefs.getInt('snooze_duration') ?? 10;
      _prefAtTime = prefs.getBool('reminder_pref_at_time') ?? true;
      _pref1h = prefs.getBool('reminder_pref_1h') ?? true;
      _pref1d = prefs.getBool('reminder_pref_1d') ?? true;
      _canScheduleExact = canExact;
      _isLoading = false;
    });
  }

  Future<void> _setBoolPreference(String key, bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(key, value);
  }

  Future<void> _setIntPreference(String key, int value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(key, value);
  }

  Future<void> _toggleReminders(bool value) async {
    setState(() {
      _remindersEnabled = value;
    });
    final taskProvider = Provider.of<TaskProvider>(context, listen: false);
    await _setBoolPreference('reminders_enabled', value);

    // If reminders are disabled, cancel all active notifications.
    // If enabled, reschedule all pending tasks.
    for (var task in taskProvider.tasks) {
      if (!task.isCompleted) {
        if (value) {
          await NotificationService().scheduleTaskNotifications(task);
        } else {
          await NotificationService().cancelTaskNotifications(task.id);
        }
      }
    }
  }

  Future<void> _wipeAllData() async {
    final navigator = Navigator.of(context);
    final messenger = ScaffoldMessenger.of(context);

    final farmProvider = context.read<FarmProvider>();
    final cropProvider = context.read<CropProvider>();
    final inventoryProvider = context.read<InventoryProvider>();
    final activityProvider = context.read<ActivityProvider>();
    final harvestProvider = context.read<HarvestProvider>();
    final expenseProvider = context.read<ExpenseProvider>();
    final taskProvider = context.read<TaskProvider>();

    showDialog(
      context: context,
      barrierDismissible: false,
      builder:
          (ctx) => const Center(
            child: CircularProgressIndicator(color: Colors.white),
          ),
    );

    try {
      // 1. Cancel all scheduled alarms
      for (var task in taskProvider.tasks) {
        await NotificationService().cancelTaskNotifications(task.id);
      }

      // 2. Wipe SQLite database tables
      await DatabaseHelper.instance.clearAllTables();

      // 3. Reload state of all providers
      farmProvider.fetchFarms();
      cropProvider.fetchCropSeasons();
      inventoryProvider.fetchInventory();
      activityProvider.fetchActivities();
      harvestProvider.fetchHarvests();
      expenseProvider.fetchExpenses();
      await taskProvider.fetchTasks();

      // 4. Close loading indicator and show success
      navigator.pop(); // close loader dialog
      messenger.showSnackBar(
        const SnackBar(
          content: Text(
            'آپ کا تمام زرعی ریکارڈ کامیابی سے حذف ہو گیا ہے!',
            style: TextStyle(fontSize: 16),
          ),
          backgroundColor: Colors.green,
        ),
      );
      navigator.pop(); // go back to dashboard
    } catch (e) {
      navigator.pop(); // close loader dialog
      messenger.showSnackBar(
        SnackBar(
          content: Text('خرابی: $e', style: const TextStyle(fontSize: 16)),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  /// Settings demo tile: enter (with the alongside-data warning) or exit demo.
  Future<void> _onDemoTileTap(DemoDataService demo) async {
    if (demo.isActive) {
      final proceed = await showDialog<bool>(
        context: context,
        builder:
            (ctx) => AlertDialog(
              title: const Text('ڈیمو ختم کریں؟'),
              content: const Text(
                'ڈیمو کا نمونہ ڈیٹا حذف کر دیا جائے گا۔ آپ کا اپنا ڈیٹا محفوظ رہے گا۔',
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(ctx).pop(false),
                  child: const Text('منسوخ کریں'),
                ),
                FilledButton(
                  onPressed: () => Navigator.of(ctx).pop(true),
                  child: const Text('ختم کریں'),
                ),
              ],
            ),
      );
      if (proceed != true || !mounted) return;
      final result = await demo.exitDemo();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            result.ok ? 'ڈیمو ڈیٹا حذف کر دیا گیا' : result.message!,
          ),
        ),
      );
      return;
    }
    if (!mounted) return;
    final hasData = await demo.hasRealData();
    if (!mounted) return;
    if (hasData) {
      final proceed = await showDialog<bool>(
        context: context,
        builder:
            (ctx) => AlertDialog(
              title: const Text('آپ کا اپنا ڈیٹا موجود ہے'),
              content: const Text(
                'ڈیمو کا نمونہ ڈیٹا آپ کے اصل ڈیٹا کے ساتھ شامل کیا جائے گا۔\n'
                'ڈیمو ختم کرنے پر صرف ڈیمو کا ڈیٹا حذف ہوگا — آپ کا ڈیٹا محفوظ رہے گا۔',
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(ctx).pop(false),
                  child: const Text('منسوخ کریں'),
                ),
                FilledButton(
                  onPressed: () => Navigator.of(ctx).pop(true),
                  child: const Text('ڈیمو شروع کریں'),
                ),
              ],
            ),
      );
      if (proceed != true || !mounted) return;
    }
    if (!mounted) return;
    try {
      await demo.enterDemoFromContext(context);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('ڈیمو ڈیٹا شامل کر دیا گیا')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('ڈیمو شروع نہ ہو سکا: $e')));
    }
  }

  void _showWipeConfirmDialog() {
    showDialog(
      context: context,
      builder:
          (ctx) => AlertDialog(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(20),
            ),
            title: const Text(
              'تصدیق کریں',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
            content: const Text(
              'کیا آپ واقعی اپنا تمام ریکارڈ (زمینیں، فصلیں، خرچے، پیداوار، الارم) ہمیشہ کے لیے حذف کرنا چاہتے ہیں؟ یہ عمل واپس نہیں لیا جا سکتا۔',
              style: TextStyle(fontSize: 16, height: 1.5),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text(
                  'منسوخ کریں',
                  style: TextStyle(color: Colors.grey, fontSize: 16),
                ),
              ),
              ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.red,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                onPressed: () {
                  Navigator.pop(ctx);
                  _wipeAllData();
                },
                child: const Text(
                  'جی ہاں، حذف کریں',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                ),
              ),
            ],
          ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'ترتیبات (Settings)',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        backgroundColor: Colors.deepPurple.shade600,
        foregroundColor: Colors.white,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Reminders Section Header
            _buildSectionHeader('یاد دہانیاں اور الارم (Reminders & Alarm)'),

            Card(
              elevation: 2,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
              ),
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  vertical: 8.0,
                  horizontal: 4.0,
                ),
                child: Column(
                  children: [
                    // Reminders enable
                    SwitchListTile(
                      title: const Text(
                        'زرعی یاد دہانیاں آن کریں',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      subtitle: const Text('اہم سرگرمیوں کے الارم موصول کریں'),
                      value: _remindersEnabled,
                      activeColor: Colors.deepPurple,
                      onChanged: _toggleReminders,
                    ),
                    const Divider(),

                    // Sound enable
                    SwitchListTile(
                      title: const Text(
                        'الارم کی آواز',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      subtitle: const Text('یاد دہانی پر مخصوص آواز بجائیں'),
                      value: _alarmSoundEnabled,
                      activeColor: Colors.deepPurple,
                      onChanged:
                          _remindersEnabled
                              ? (value) async {
                                setState(() {
                                  _alarmSoundEnabled = value;
                                });
                                await _setBoolPreference(
                                  'alarm_sound_enabled',
                                  value,
                                );
                              }
                              : null,
                    ),
                    const Divider(),

                    // Vibration enable
                    SwitchListTile(
                      title: const Text(
                        'وائبریشن (تھرتھراہٹ)',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      subtitle: const Text('یاد دہانی پر فون وائبریٹ کریں'),
                      value: _vibrationEnabled,
                      activeColor: Colors.deepPurple,
                      onChanged:
                          _remindersEnabled
                              ? (value) async {
                                setState(() {
                                  _vibrationEnabled = value;
                                });
                                await _setBoolPreference(
                                  'vibration_enabled',
                                  value,
                                );
                              }
                              : null,
                    ),
                    const Divider(),

                    // Snooze config
                    ListTile(
                      title: const Text(
                        'الارم سوز کی مدت (Snooze Duration)',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      subtitle: const Text('کتنی دیر بعد الارم دوبارہ بجے'),
                      trailing: DropdownButton<int>(
                        value: _snoozeDuration,
                        items: const [
                          DropdownMenuItem(value: 5, child: Text('5 منٹ')),
                          DropdownMenuItem(value: 10, child: Text('10 منٹ')),
                          DropdownMenuItem(value: 15, child: Text('15 منٹ')),
                        ],
                        onChanged:
                            _remindersEnabled
                                ? (value) async {
                                  if (value != null) {
                                    setState(() {
                                      _snoozeDuration = value;
                                    });
                                    await _setIntPreference(
                                      'snooze_duration',
                                      value,
                                    );
                                  }
                                }
                                : null,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),

            // Default reminder preferences
            _buildSectionHeader('پہلے سے طے شدہ ترجیحات (Reminder Defaults)'),
            Card(
              elevation: 2,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
              ),
              child: Padding(
                padding: const EdgeInsets.all(8.0),
                child: Column(
                  children: [
                    CheckboxListTile(
                      title: const Text('کام کے وقت یاد دہانی'),
                      value: _prefAtTime,
                      activeColor: Colors.deepPurple,
                      onChanged: (val) async {
                        if (val != null) {
                          setState(() => _prefAtTime = val);
                          await _setBoolPreference(
                            'reminder_pref_at_time',
                            val,
                          );
                        }
                      },
                    ),
                    CheckboxListTile(
                      title: const Text('1 گھنٹہ پہلے یاد دہانی'),
                      value: _pref1h,
                      activeColor: Colors.deepPurple,
                      onChanged: (val) async {
                        if (val != null) {
                          setState(() => _pref1h = val);
                          await _setBoolPreference('reminder_pref_1h', val);
                        }
                      },
                    ),
                    CheckboxListTile(
                      title: const Text('1 دن پہلے یاد دہانی'),
                      value: _pref1d,
                      activeColor: Colors.deepPurple,
                      onChanged: (val) async {
                        if (val != null) {
                          setState(() => _pref1d = val);
                          await _setBoolPreference('reminder_pref_1d', val);
                        }
                      },
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),

            // Battery & System Settings Section
            _buildSectionHeader(
              'بیٹری اور دیگر ترتیبات (Battery & System Settings)',
            ),
            Card(
              elevation: 2,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
              ),
              child: Padding(
                padding: const EdgeInsets.all(8.0),
                child: Column(
                  children: [
                    ListTile(
                      leading: const Icon(
                        Icons.battery_saver,
                        color: Colors.amber,
                      ),
                      title: const Text(
                        'بیٹری بچت سے استثنیٰ (Ignore Battery Saving)',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      subtitle: Text(
                        _isIgnoringBattery
                            ? 'آن (صحیح الارم کے لیے موزوں)'
                            : 'آف (الارم تاخیر کا شکار ہو سکتا ہے)',
                      ),
                      trailing: ElevatedButton(
                        style: ElevatedButton.styleFrom(
                          backgroundColor:
                              _isIgnoringBattery
                                  ? Colors.grey
                                  : Colors.amber.shade700,
                          foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                        onPressed: _checkAndRequestBatteryBypass,
                        child: Text(
                          _isIgnoringBattery ? 'ترتیبات کھولیں' : 'اجازت دیں',
                        ),
                      ),
                    ),
                    const Divider(),
                    ListTile(
                      leading: const Icon(
                        Icons.fullscreen,
                        color: Colors.deepPurple,
                      ),
                      title: const Text(
                        'فل اسکرین الارم کی اجازت (Full Screen Alarm)',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      subtitle: Text(
                        _canFullScreen
                            ? 'آن (لاک اسکرین پر الارم بجے گا)'
                            : 'آف (لاک اسکرین پر الارم نہیں بجے گا)',
                      ),
                      trailing: ElevatedButton(
                        style: ElevatedButton.styleFrom(
                          backgroundColor:
                              _canFullScreen
                                  ? Colors.grey
                                  : Colors.deepPurple.shade600,
                          foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                        onPressed: _requestFullScreenPermission,
                        child: Text(
                          _canFullScreen ? 'ترتیبات کھولیں' : 'اجازت دیں',
                        ),
                      ),
                    ),
                    const Divider(),
                    ListTile(
                      leading: const Icon(Icons.alarm, color: Colors.blue),
                      title: const Text(
                        'صحیح وقت پر الارم کی اجازت (Exact Alarm)',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      subtitle: Text(
                        _canScheduleExact
                            ? 'آن (صحیح وقت پر یاد دہانی ملے گی)'
                            : 'آف (الارم تاخیر کا شکار ہو سکتا ہے)',
                      ),
                      trailing: ElevatedButton(
                        style: ElevatedButton.styleFrom(
                          backgroundColor:
                              _canScheduleExact
                                  ? Colors.grey
                                  : Colors.blue.shade600,
                          foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                        onPressed:
                            _canScheduleExact
                                ? _openAppSettings
                                : _requestExactAlarmPermission,
                        child: Text(
                          _canScheduleExact ? 'ترتیبات کھولیں' : 'اجازت دیں',
                        ),
                      ),
                    ),
                    const Divider(),
                    ListTile(
                      leading: const Icon(
                        Icons.settings_applications,
                        color: Colors.blueGrey,
                      ),
                      title: const Text(
                        'ایپ کی دیگر اجازتیں (Other App Permissions)',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      subtitle: const Text(
                        'لاک اسکرین پر الارم دکھانے کے لیے دیگر اجازتیں دیں',
                      ),
                      trailing: ElevatedButton(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.blueGrey.shade600,
                          foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                        onPressed: _openAppSettings,
                        child: const Text('کھولیں'),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),

            // Backup & Restore Section
            _buildSectionHeader('بیک اپ اور ڈیٹا بحالی (Backup & Restore)'),
            Card(
              elevation: 2,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  ListTile(
                    leading: const Icon(Icons.backup, color: Colors.deepPurple),
                    title: const Text(
                      'ڈیٹا بیک اپ اور بحالی',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    subtitle: const Text(
                      'بیک اپ بنائیں، بحال کریں یا شیئر کریں',
                    ),
                    trailing: const Icon(
                      Icons.arrow_forward_ios,
                      color: Colors.deepPurple,
                      size: 18,
                    ),
                    onTap: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(builder: (_) => const BackupScreen()),
                      );
                    },
                  ),
                  const Divider(height: 1),
                  ListTile(
                    leading: const Icon(
                      Icons.delete_outline,
                      color: Colors.deepPurple,
                    ),
                    title: const Text(
                      'حذف شدہ',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    subtitle: const Text(
                      'حذف شدہ ریکارڈ بحال کریں یا مستقل حذف کریں',
                    ),
                    trailing: const Icon(
                      Icons.arrow_forward_ios,
                      color: Colors.deepPurple,
                      size: 18,
                    ),
                    onTap: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => const RecycleBinScreen(),
                        ),
                      );
                    },
                  ),
                  const Divider(height: 1),
                  ListTile(
                    leading: const Icon(
                      Icons.history,
                      color: Colors.deepPurple,
                    ),
                    title: const Text(
                      'تبدیلیوں کا ریکارڈ',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    subtitle: const Text('ہر بنائی، تبدیلی اور حذف کا ریکارڈ'),
                    trailing: const Icon(
                      Icons.arrow_forward_ios,
                      color: Colors.deepPurple,
                      size: 18,
                    ),
                    onTap: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => const AuditLogScreen(),
                        ),
                      );
                    },
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),

            // Demo Mode Section
            _buildSectionHeader('ڈیمو (Demo)'),
            Card(
              elevation: 2,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
              ),
              child: Consumer<DemoDataService>(
                builder:
                    (context, demo, _) => ListTile(
                      leading: Icon(
                        Icons.science_outlined,
                        color:
                            demo.isActive ? Colors.amber.shade800 : Colors.teal,
                      ),
                      title: Text(
                        demo.isActive ? 'ڈیمو ختم کریں' : 'ڈیمو دیکھیں',
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      subtitle: Text(
                        demo.isActive
                            ? 'نمونہ ڈیٹا حذف ہوگا — بیک اپ میں ڈیمو ڈیٹا شامل ہوگا'
                            : 'نمونہ ڈیٹا کے ساتھ ایپ آزمائیں',
                      ),
                      trailing: const Icon(
                        Icons.arrow_forward_ios,
                        color: Colors.teal,
                        size: 18,
                      ),
                      onTap: () => _onDemoTileTap(demo),
                    ),
              ),
            ),
            const SizedBox(height: 24),

            // Delete Data Section
            ElevatedButton.icon(
              onPressed: _showWipeConfirmDialog,
              icon: const Icon(
                Icons.delete_forever,
                size: 24,
                color: Colors.white,
              ),
              label: const Text(
                'تمام ڈیٹا ہمیشہ کے لیے حذف کریں',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: Colors.white,
                ),
              ),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.red.shade700,
                padding: const EdgeInsets.symmetric(vertical: 16),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
                elevation: 4,
              ),
            ),
            const SizedBox(height: 30),
          ],
        ),
      ),
    );
  }

  Widget _buildSectionHeader(String title) {
    return Padding(
      padding: const EdgeInsets.only(left: 8, bottom: 8, top: 12),
      child: Text(
        title,
        style: const TextStyle(
          fontSize: 16,
          fontWeight: FontWeight.bold,
          color: Colors.deepPurple,
        ),
      ),
    );
  }
}
