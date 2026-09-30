import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter/services.dart';
import 'dart:convert';
import 'package:file_picker/file_picker.dart';
import '../services/notification_service.dart';
import '../database/db_helper.dart';
import '../providers/task_provider.dart';
import '../providers/farm_provider.dart';
import '../providers/crop_provider.dart';
import '../providers/inventory_provider.dart';
import '../providers/activity_provider.dart';
import '../providers/harvest_provider.dart';
import '../providers/expense_provider.dart';
import '../providers/theka_provider.dart';
import '../providers/ushr_provider.dart';

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
  bool _isProcessingBackup = false;
  bool _canScheduleExact = true;

  static const _channel = MethodChannel('com.example.kisan_dost/share');

  @override
  void initState() {
    super.initState();
    _loadPreferences();
    _checkExactAlarmStatus();
  }

  Future<void> _checkExactAlarmStatus() async {
    final bool canExact = await NotificationService().canScheduleExactAlarms();
    if (!mounted) return;
    setState(() {
      _canScheduleExact = canExact;
    });
  }

  Future<void> _requestExactAlarmPermission() async {
    await NotificationService().requestExactAlarmPermission();
    await Future<void>.delayed(const Duration(seconds: 2));
    final canExact = await NotificationService().canScheduleExactAlarms();
    if (!mounted) return;
    setState(() => _canScheduleExact = canExact);
    if (canExact) await NotificationService().rescheduleAllPendingAlarms();
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
    if (!mounted) return;
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
    final thekaProvider = context.read<ThekaProvider>();
    final ushrProvider = context.read<UshrProvider>();

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
      await farmProvider.fetchFarms();
      await cropProvider.fetchCropSeasons();
      await inventoryProvider.fetchInventory();
      await activityProvider.fetchActivities();
      await harvestProvider.fetchHarvests();
      await expenseProvider.fetchExpenses();
      await thekaProvider.fetchThekas();
      await ushrProvider.fetchUshrRecords();
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

  Future<void> _saveOfflineBackup() async {
    if (_isProcessingBackup) return;
    setState(() => _isProcessingBackup = true);
    try {
      final backup = await DatabaseHelper.instance.createBackup();
      final contents = const JsonEncoder.withIndent('  ').convert(backup);
      final stamp = DateTime.now()
          .toIso8601String()
          .replaceAll(':', '-')
          .replaceAll('.', '-');
      final savedFile = await FilePicker.saveFile(
        dialogTitle: 'آف لائن بیک اپ محفوظ کریں',
        fileName: 'kisan_dost_backup_$stamp.json',
        type: FileType.custom,
        allowedExtensions: const ['json'],
        bytes: Uint8List.fromList(utf8.encode(contents)),
      );
      if (!mounted || savedFile == null) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('آپ کا آف لائن بیک اپ محفوظ ہو گیا ہے۔')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('بیک اپ محفوظ نہیں ہو سکا: $e'),
          backgroundColor: Colors.red,
        ),
      );
    } finally {
      if (mounted) setState(() => _isProcessingBackup = false);
    }
  }

  Future<void> _restoreOfflineBackup() async {
    if (_isProcessingBackup) return;
    try {
      final files = await FilePicker.pickFiles(
        type: FileType.custom,
        allowedExtensions: const ['json'],
      );
      if (!mounted || files.isEmpty) return;

      setState(() => _isProcessingBackup = true);
      final bytes = await files.single.readAsBytes();
      final payload = jsonDecode(utf8.decode(bytes));
      if (!mounted) return;
      final shouldRestore = await showDialog<bool>(
        context: context,
        builder:
            (dialogContext) => AlertDialog(
              title: const Text('موجودہ ریکارڈ بدلیں؟'),
              content: const Text(
                'اس بیک اپ سے بحالی آپ کے فون کا موجودہ زرعی ریکارڈ بدل دے گی۔ '
                'اگر موجودہ ڈیٹا درکار ہو تو پہلے اس کا بیک اپ محفوظ کریں۔',
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(dialogContext, false),
                  child: const Text('منسوخ کریں'),
                ),
                ElevatedButton(
                  onPressed: () => Navigator.pop(dialogContext, true),
                  child: const Text('بحال کریں'),
                ),
              ],
            ),
      );
      if (shouldRestore != true || !mounted) return;

      final restoredCount = await DatabaseHelper.instance.restoreBackup(
        payload,
      );
      await _refreshRestoredData();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('$restoredCount ریکارڈ بیک اپ سے بحال ہو گئے۔')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('بیک اپ بحال نہیں ہو سکا: $e'),
          backgroundColor: Colors.red,
        ),
      );
    } finally {
      if (mounted) setState(() => _isProcessingBackup = false);
    }
  }

  Future<void> _refreshRestoredData() async {
    final farmProvider = context.read<FarmProvider>();
    final cropProvider = context.read<CropProvider>();
    final inventoryProvider = context.read<InventoryProvider>();
    final activityProvider = context.read<ActivityProvider>();
    final harvestProvider = context.read<HarvestProvider>();
    final expenseProvider = context.read<ExpenseProvider>();
    final thekaProvider = context.read<ThekaProvider>();
    final ushrProvider = context.read<UshrProvider>();
    final taskProvider = context.read<TaskProvider>();

    await farmProvider.fetchFarms();
    await cropProvider.fetchCropSeasons();
    await inventoryProvider.fetchInventory();
    await activityProvider.fetchActivities();
    await harvestProvider.fetchHarvests();
    await expenseProvider.fetchExpenses();
    await thekaProvider.fetchThekas();
    await ushrProvider.fetchUshrRecords();
    await taskProvider.fetchTasks();
    final preferences = await SharedPreferences.getInstance();
    if (preferences.getBool('reminders_enabled') ?? true) {
      for (final task in taskProvider.tasks.where(
        (task) => !task.isCompleted,
      )) {
        try {
          await NotificationService().scheduleTaskNotifications(task);
        } catch (e) {
          debugPrint('A restored task reminder could not be scheduled: $e');
        }
      }
    }
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
                      activeThumbColor: Colors.deepPurple,
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
                      activeThumbColor: Colors.deepPurple,
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
                      activeThumbColor: Colors.deepPurple,
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

            // Reminder permissions
            _buildSectionHeader('اجازتیں اور یاد دہانیاں (Permissions)'),
            Card(
              elevation: 2,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
              ),
              child: Column(
                children: [
                  ListTile(
                    leading: const Icon(Icons.alarm, color: Colors.blue),
                    title: const Text(
                      'صحیح وقت پر یاد دہانی (Exact Alarm)',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    subtitle: Text(
                      _canScheduleExact
                          ? 'آن — یاد دہانی مقررہ وقت پر آئے گی'
                          : 'آف — فون کی ترتیبات میں اجازت دیں',
                    ),
                    trailing: ElevatedButton(
                      onPressed:
                          _canScheduleExact
                              ? _openAppSettings
                              : _requestExactAlarmPermission,
                      child: Text(_canScheduleExact ? 'ترتیبات' : 'اجازت دیں'),
                    ),
                  ),
                  const Divider(height: 1),
                  ListTile(
                    leading: const Icon(
                      Icons.notifications_active_outlined,
                      color: Colors.blueGrey,
                    ),
                    title: const Text(
                      'اطلاعات کی اجازت',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    subtitle: const Text(
                      'یاد دہانیاں نہ آئیں تو ایپ کی اطلاعات کی اجازت دیکھیں',
                    ),
                    trailing: OutlinedButton(
                      onPressed: _openAppSettings,
                      child: const Text('کھولیں'),
                    ),
                  ),
                ],
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
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    ElevatedButton.icon(
                      onPressed:
                          _isProcessingBackup ? null : _saveOfflineBackup,
                      icon: const Icon(Icons.save_alt),
                      label: const Text('آف لائن بیک اپ محفوظ کریں'),
                    ),
                    const SizedBox(height: 8),
                    OutlinedButton.icon(
                      onPressed:
                          _isProcessingBackup ? null : _restoreOfflineBackup,
                      icon: const Icon(Icons.settings_backup_restore),
                      label: const Text('بیک اپ سے ریکارڈ بحال کریں'),
                    ),
                    if (_isProcessingBackup) ...[
                      const SizedBox(height: 8),
                      const LinearProgressIndicator(),
                    ],
                    const SizedBox(height: 8),
                    const Text(
                      'بیک اپ میں آپ کے کھیت، فصل اور مالی ریکارڈ شامل ہیں۔ '
                      'فائل رمز شدہ نہیں؛ اسے محفوظ جگہ پر رکھیں۔ بحالی موجودہ ریکارڈ بدل دے گی۔',
                      textAlign: TextAlign.right,
                      style: TextStyle(color: Colors.black54, fontSize: 13),
                    ),
                  ],
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
