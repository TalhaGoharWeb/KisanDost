import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import 'package:share_plus/share_plus.dart';

import '../services/backup_service.dart';
import '../services/restore_service.dart';
import '../providers/farm_provider.dart';
import '../providers/crop_provider.dart';
import '../providers/inventory_provider.dart';
import '../providers/activity_provider.dart';
import '../providers/harvest_provider.dart';
import '../providers/expense_provider.dart';
import '../providers/task_provider.dart';
import '../providers/theka_provider.dart';
import '../providers/ushr_provider.dart';
import '../l10n/strings.dart';
import '../utils/error_messages.dart';

/// ڈیٹا بیک اپ اور بحالی کی اسکرین: بیک اپ بنانا، فہرست، شیئر، حذف اور بحال (تبدیل/ضم)۔
class BackupScreen extends StatefulWidget {
  const BackupScreen({super.key});

  @override
  State<BackupScreen> createState() => _BackupScreenState();
}

class _BackupScreenState extends State<BackupScreen> {
  final BackupService _backupService = BackupService();
  final RestoreService _restoreService = RestoreService();

  List<BackupInfo> _backups = [];
  bool _isLoading = true;
  bool _isCreating = false;
  bool _autoBackupEnabled = false;
  bool _isRestoring = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final backups = await _backupService.listBackups();
      final autoEnabled = await _backupService.autoBackupEnabled;
      if (!mounted) return;
      setState(() {
        _backups = backups;
        _autoBackupEnabled = autoEnabled;
        _isLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _isLoading = false);
      showFriendlyError(context, e, FailureKind.database);
    }
  }

  void _showSnack(String message, Color color) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message, style: const TextStyle(fontSize: 16)),
        backgroundColor: color,
      ),
    );
  }

  /// خفیہ بیک اپ کے لیے پاس فریز مانگنے والا ڈائیلاگ۔ [hint] ہو تو یاد
  /// دہانی دکھاتا ہے۔ منسوخ کرنے پر null۔
  Future<String?> _promptPassphrase({String hint = ''}) async {
    final controller = TextEditingController();
    final result = await showDialog<String>(
      context: context,
      builder:
          (ctx) => AlertDialog(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(20),
            ),
            title: const Text(
              'پاس فریز درج کریں',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Text(
                  'یہ خفیہ بیک اپ ہے — اسے کھولنے کے لیے وہی پاس فریز درکار ہے جو بناتے وقت رکھا تھا۔',
                  style: TextStyle(fontSize: 15, height: 1.5),
                ),
                if (hint.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Text(
                    'یاد دہانی: $hint',
                    style: const TextStyle(
                      fontSize: 14,
                      color: Colors.deepPurple,
                    ),
                  ),
                ],
                const SizedBox(height: 12),
                TextField(
                  controller: controller,
                  obscureText: true,
                  autofocus: true,
                  decoration: const InputDecoration(
                    labelText: 'پاس فریز',
                    border: OutlineInputBorder(),
                  ),
                ),
              ],
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
                  backgroundColor: Colors.deepPurple.shade600,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                onPressed: () => Navigator.pop(ctx, controller.text),
                child: const Text(
                  'جاری رکھیں',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                ),
              ),
            ],
          ),
    );
    controller.dispose();
    return result;
  }

  /// تمام پرووائیڈرز کو دوبارہ لوڈ کریں (بحالی کے بعد)۔
  Future<void> _reloadAllProviders() async {
    if (!mounted) return;
    context.read<FarmProvider>().fetchFarms();
    context.read<CropProvider>().fetchCropSeasons();
    context.read<InventoryProvider>().fetchInventory();
    context.read<ActivityProvider>().fetchActivities();
    context.read<HarvestProvider>().fetchHarvests();
    context.read<ExpenseProvider>().fetchExpenses();
    context.read<TaskProvider>().fetchTasks();
    context.read<ThekaProvider>().fetchThekas();
    context.read<UshrProvider>().fetchUshrRecords();
  }

  /// نیا بیک اپ بنانے کا ڈائیلاگ: خفیہ (پاس فریز) یا سادہ بیک اپ کا واضح
  /// انتخاب، پاس فریز + یاد دہانی، اور بھولنے کی صورت میں ناقابلِ بحالی
  /// ہونے کی واضح تنبیہ۔
  Future<void> _showCreateBackupDialog() async {
    var useEncryption = true;
    final passphraseCtrl = TextEditingController();
    final confirmCtrl = TextEditingController();
    final hintCtrl = TextEditingController();
    String? error;

    final result = await showDialog<Map<String, String?>>(
      context: context,
      builder:
          (ctx) => StatefulBuilder(
            builder:
                (ctx, setDialogState) => AlertDialog(
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(20),
                  ),
                  title: const Text(
                    'نیا بیک اپ',
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                  content: SingleChildScrollView(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        RadioGroup<bool>(
                          groupValue: useEncryption,
                          onChanged:
                              (v) => setDialogState(
                                () => useEncryption = v ?? true,
                              ),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              RadioListTile<bool>(
                                value: true,
                                activeColor: Colors.deepPurple,
                                contentPadding: EdgeInsets.zero,
                                title: const Text(
                                  'خفیہ بیک اپ (تجویز کردہ)',
                                  style: TextStyle(
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                                subtitle: const Text(
                                  'پاس فریز کے بغیر کوئی بھی یہ فائل نہیں کھول سکے گا',
                                ),
                              ),
                              RadioListTile<bool>(
                                value: false,
                                activeColor: Colors.deepPurple,
                                contentPadding: EdgeInsets.zero,
                                title: const Text(
                                  'سادہ بیک اپ',
                                  style: TextStyle(
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                                subtitle: const Text(
                                  'بغیر پاس فریز — جو بھی فائل پائے گا، ڈیٹا پڑھ سکے گا',
                                ),
                              ),
                            ],
                          ),
                        ),
                        if (useEncryption) ...[
                          const SizedBox(height: 8),
                          TextField(
                            controller: passphraseCtrl,
                            obscureText: true,
                            decoration: const InputDecoration(
                              labelText: 'پاس فریز',
                              hintText: 'کم از کم 4 حروف',
                              border: OutlineInputBorder(),
                            ),
                          ),
                          const SizedBox(height: 8),
                          TextField(
                            controller: confirmCtrl,
                            obscureText: true,
                            decoration: const InputDecoration(
                              labelText: 'پاس فریز دوبارہ لکھیں',
                              border: OutlineInputBorder(),
                            ),
                          ),
                          const SizedBox(height: 8),
                          TextField(
                            controller: hintCtrl,
                            decoration: const InputDecoration(
                              labelText: 'یاد دہانی (اختیاری)',
                              hintText: 'مثلاً: میرے بیٹے کا نام',
                              border: OutlineInputBorder(),
                            ),
                          ),
                          const SizedBox(height: 4),
                          const Text(
                            'یاد دہانی سب کو نظر آئے گی — اس میں اصل پاس فریز نہ لکھیں',
                            style: TextStyle(
                              fontSize: 13,
                              color: Colors.grey,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Container(
                            padding: const EdgeInsets.all(10),
                            decoration: BoxDecoration(
                              color: Colors.red.shade50,
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(color: Colors.red.shade200),
                            ),
                            child: const Text(
                              '⚠ خبردار: اگر آپ پاس فریز بھول گئے تو یہ بیک اپ ہمیشہ کے لیے ضائع ہو جائے گا — اسے کوئی بھی بحال نہیں کر سکے گا۔',
                              style: TextStyle(
                                fontSize: 14,
                                color: Colors.red,
                                fontWeight: FontWeight.bold,
                                height: 1.5,
                              ),
                            ),
                          ),
                        ],
                        if (error != null) ...[
                          const SizedBox(height: 8),
                          Text(
                            error!,
                            style: const TextStyle(
                              color: Colors.red,
                              fontSize: 14,
                            ),
                          ),
                        ],
                      ],
                    ),
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
                        backgroundColor: Colors.deepPurple.shade600,
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      onPressed: () {
                        if (useEncryption) {
                          final pw = passphraseCtrl.text;
                          if (pw.isEmpty) {
                            setDialogState(
                              () => error = 'پاس فریز درج کریں',
                            );
                            return;
                          }
                          if (pw.length < 4) {
                            setDialogState(
                              () =>
                                  error =
                                      'پاس فریز کم از کم 4 حروف کا ہونا چاہیے',
                            );
                            return;
                          }
                          if (confirmCtrl.text != pw) {
                            setDialogState(
                              () =>
                                  error =
                                      'دونوں پاس فریز ایک جیسے نہیں ہیں',
                            );
                            return;
                          }
                        }
                        Navigator.pop(ctx, {
                          'passphrase':
                              useEncryption ? passphraseCtrl.text : null,
                          'hint': useEncryption ? hintCtrl.text : null,
                        });
                      },
                      child: const Text(
                        'بیک اپ بنائیں',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ],
                ),
          ),
    );

    passphraseCtrl.dispose();
    confirmCtrl.dispose();
    hintCtrl.dispose();
    if (result == null) return; // صارف نے منسوخ کر دیا

    setState(() => _isCreating = true);
    try {
      final info = await _backupService.createBackup(
        passphrase: result['passphrase'],
        hint: result['hint'],
      );
      await _load();
      _showSnack(
        info.isEncrypted
            ? 'خفیہ بیک اپ کامیابی سے بن گیا — پاس فریز یاد رکھیں!'
            : 'بیک اپ کامیابی سے بن گیا',
        Colors.green,
      );
    } on BackupException catch (e) {
      _showSnack(e.message, Colors.red);
    } catch (e) {
      showFriendlyError(context, e, FailureKind.storage);
    } finally {
      if (mounted) setState(() => _isCreating = false);
    }
  }

  Future<void> _toggleAutoBackup(bool value) async {
    try {
      await _backupService.setAutoBackupEnabled(value);
      if (!mounted) return;
      setState(() => _autoBackupEnabled = value);
      _showSnack(
        value
            ? 'خودکار روزانہ بیک اپ آن کر دیا گیا'
            : 'خودکار روزانہ بیک اپ بند کر دیا گیا',
        Colors.green,
      );
    } catch (e) {
      showFriendlyError(context, e, FailureKind.database);
    }
  }

  Future<void> _confirmDelete(BackupInfo info) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder:
          (ctx) => AlertDialog(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(20),
            ),
            title: const Text(
              'بیک اپ حذف کریں؟',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
            content: Text(
              'کیا آپ واقعی "${info.label}" بیک اپ حذف کرنا چاہتے ہیں؟ یہ عمل واپس نہیں لیا جا سکتا۔',
              style: const TextStyle(fontSize: 16, height: 1.5),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, false),
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
                onPressed: () => Navigator.pop(ctx, true),
                child: const Text(
                  'جی ہاں، حذف کریں',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                ),
              ),
            ],
          ),
    );
    if (confirmed != true) return;
    try {
      await _backupService.deleteBackup(info);
      await _load();
      _showSnack('بیک اپ حذف ہو گیا', Colors.green);
    } catch (e) {
      showFriendlyError(context, e, FailureKind.storage);
    }
  }

  Future<void> _shareBackup(BackupInfo info) async {
    try {
      await SharePlus.instance.share(
        ShareParams(text: 'کسان دوست بیک اپ', files: [XFile(info.path)]),
      );
    } catch (e) {
      showFriendlyError(context, e, FailureKind.sharing);
    }
  }

  Future<void> _importFromFile() async {
    try {
      final result = await FilePicker.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['db', 'enc'],
      );
      if (result == null || result.files.single.path == null) return;
      final pickedPath = result.files.single.path!;
      String? passphrase;
      if (pickedPath.endsWith('.enc')) {
        passphrase = await _promptPassphrase();
        if (passphrase == null || passphrase.isEmpty) return;
      }
      final info = await _backupService.importBackupFile(
        pickedPath,
        passphrase: passphrase,
      );
      await _load();
      _showSnack('بیک اپ فائل درآمد ہو گئی: ${info.label}', Colors.green);
    } on BackupException catch (e) {
      _showSnack(e.message, Colors.red);
    } catch (e) {
      showFriendlyError(context, e, FailureKind.import);
    }
  }

  /// بحال کرنے کا طریقہ منتخب کرنے والا ڈائیلاگ۔
  void _showRestoreDialog(BackupInfo info) {
    showDialog(
      context: context,
      builder:
          (ctx) => AlertDialog(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(20),
            ),
            title: const Text(
              'بحال کرنے کا طریقہ',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    '"${info.label}" کو کیسے بحال کیا جائے؟',
                    style: const TextStyle(fontSize: 16),
                  ),
                  const SizedBox(height: 12),
                  // Replace option
                  OutlinedButton(
                    style: OutlinedButton.styleFrom(
                      side: const BorderSide(color: Colors.red),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      padding: const EdgeInsets.all(12),
                    ),
                    onPressed: () {
                      Navigator.pop(ctx);
                      _doRestoreReplace(info);
                    },
                    child: const Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'تبدیل کریں (Replace)',
                          style: TextStyle(
                            color: Colors.red,
                            fontWeight: FontWeight.bold,
                            fontSize: 16,
                          ),
                        ),
                        SizedBox(height: 4),
                        Text(
                          'موجودہ تمام ڈیٹا ختم کر کے بیک اپ بحال ہو گا',
                          style: TextStyle(color: Colors.black87, fontSize: 14),
                        ),
                        SizedBox(height: 4),
                        Text(
                          '⚠ خبردار: موجودہ تمام ڈیٹا مستقل طور پر ضائع ہو جائے گا!',
                          style: TextStyle(
                            color: Colors.red,
                            fontSize: 14,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),
                  // Merge option
                  OutlinedButton(
                    style: OutlinedButton.styleFrom(
                      side: BorderSide(color: Colors.deepPurple.shade400),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      padding: const EdgeInsets.all(12),
                    ),
                    onPressed: () {
                      Navigator.pop(ctx);
                      _doRestoreMerge(info);
                    },
                    child: const Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'ضم کریں (Merge)',
                          style: TextStyle(
                            color: Colors.deepPurple,
                            fontWeight: FontWeight.bold,
                            fontSize: 16,
                          ),
                        ),
                        SizedBox(height: 4),
                        Text(
                          'بیک اپ کی نئی چیزیں شامل ہوں گی، موجودہ ڈیٹا محفوظ رہے گا',
                          style: TextStyle(color: Colors.black87, fontSize: 14),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text(
                  'منسوخ کریں',
                  style: TextStyle(color: Colors.grey, fontSize: 16),
                ),
              ),
            ],
          ),
    );
  }

  void _showProgressDialog(String message) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder:
          (_) => AlertDialog(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(20),
            ),
            content: Row(
              children: [
                const CircularProgressIndicator(color: Colors.deepPurple),
                const SizedBox(width: 20),
                Expanded(
                  child: Text(message, style: const TextStyle(fontSize: 16)),
                ),
              ],
            ),
          ),
    );
  }

  /// بحالی کے بعد: پرووائیڈرز دوبارہ لوڈ کریں، ہوم پر جائیں، خلاصہ دکھائیں۔
  Future<void> _finishRestore(String summary) async {
    await _reloadAllProviders();
    if (!mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    Navigator.of(context).popUntil((route) => route.isFirst);
    messenger.showSnackBar(
      SnackBar(
        content: Text(summary, style: const TextStyle(fontSize: 16)),
        backgroundColor: Colors.green,
      ),
    );
  }

  Future<void> _doRestoreReplace(BackupInfo info) async {
    // خفیہ بیک اپ ہو تو پہلے پاس فریز — بحالی سے پہلے۔
    String? passphrase;
    if (info.isEncrypted) {
      passphrase = await _promptPassphrase(hint: info.hint);
      if (passphrase == null || passphrase.isEmpty || !mounted) return;
    }

    // تبدیل (Replace) سے پہلے واضح تصدیق — موجودہ ڈیٹا ضائع ہو جائے گا۔
    final confirmed = await showDialog<bool>(
      context: context,
      builder:
          (ctx) => AlertDialog(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(20),
            ),
            title: const Text(
              'آخری تصدیق',
              style: TextStyle(fontWeight: FontWeight.bold, color: Colors.red),
            ),
            content: const Text(
              'بیک اپ کو تبدیل (Replace) کرنے سے آپ کا موجودہ تمام ڈیٹا مستقل طور پر ختم ہو جائے گا اور بیک اپ کا ڈیٹا بحال ہو گا۔ کیا آپ واقعی آگے بڑھنا چاہتے ہیں؟',
              style: TextStyle(fontSize: 16, height: 1.5),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, false),
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
                onPressed: () => Navigator.pop(ctx, true),
                child: const Text(
                  'جی ہاں، بحال کریں',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                ),
              ),
            ],
          ),
    );
    if (confirmed != true || !mounted) return;

    setState(() => _isRestoring = true);
    _showProgressDialog('بیک اپ بحال ہو رہا ہے…');
    try {
      final summary = await _restoreService.restoreReplace(
        info.path,
        passphrase: passphrase,
      );
      if (!mounted) return;
      Navigator.of(context).pop(); // بند کریں پروگریس ڈائیلاگ
      await _finishRestore(summary);
    } on BackupException catch (e) {
      if (!mounted) return;
      Navigator.of(context).pop();
      _showSnack(e.message, Colors.red);
    } catch (e) {
      if (!mounted) return;
      Navigator.of(context).pop();
      showFriendlyError(context, e, FailureKind.corruptData);
    } finally {
      if (mounted) setState(() => _isRestoring = false);
    }
  }

  Future<void> _doRestoreMerge(BackupInfo info) async {
    // خفیہ بیک اپ ہو تو پہلے پاس فریز — بحالی سے پہلے۔
    String? passphrase;
    if (info.isEncrypted) {
      passphrase = await _promptPassphrase(hint: info.hint);
      if (passphrase == null || passphrase.isEmpty || !mounted) return;
    }

    setState(() => _isRestoring = true);
    _showProgressDialog('بیک اپ ضم ہو رہا ہے…');
    try {
      final result = await _restoreService.restoreMerge(
        info.path,
        passphrase: passphrase,
      );
      if (!mounted) return;
      Navigator.of(context).pop(); // بند کریں پروگریس ڈائیلاگ
      await _finishRestore(result.summaryUrdu());
    } on BackupException catch (e) {
      if (!mounted) return;
      Navigator.of(context).pop();
      _showSnack(e.message, Colors.red);
    } catch (e) {
      if (!mounted) return;
      Navigator.of(context).pop();
      showFriendlyError(context, e, FailureKind.corruptData);
    } finally {
      if (mounted) setState(() => _isRestoring = false);
    }
  }

  String _formatSize(int bytes) {
    if (bytes < 1024) return '$bytes بائٹ';
    final kb = bytes / 1024;
    if (kb < 1024) return '${kb.toStringAsFixed(1)} KB';
    return '${(kb / 1024).toStringAsFixed(1)} MB';
  }

  /// بیک اپ کے نام/لیبل سے اندازہ: خودکار بیک اپ تھا یا دستی۔
  bool _isAutoBackup(BackupInfo info) {
    final haystack = '${info.name} ${info.label}'.toLowerCase();
    return haystack.contains('auto') || info.label.contains('خودکار');
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'بیک اپ اور ڈیٹا بحالی',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        backgroundColor: Colors.deepPurple.shade600,
        foregroundColor: Colors.white,
      ),
      body:
          _isLoading
              ? const Center(
                child: CircularProgressIndicator(color: Colors.deepPurple),
              )
              : SingleChildScrollView(
                padding: const EdgeInsets.all(20.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // نیا بیک اپ بٹن
                    ElevatedButton.icon(
                      onPressed:
                          _isCreating ? null : _showCreateBackupDialog,
                      icon:
                          _isCreating
                              ? const SizedBox(
                                width: 24,
                                height: 24,
                                child: CircularProgressIndicator(
                                  color: Colors.white,
                                  strokeWidth: 3,
                                ),
                              )
                              : const Icon(
                                Icons.backup,
                                size: 24,
                                color: Colors.white,
                              ),
                      label: Text(
                        _isCreating ? 'بیک اپ بن رہا ہے…' : 'نیا بیک اپ بنائیں',
                        style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                        ),
                      ),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.deepPurple.shade600,
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16),
                        ),
                        elevation: 4,
                      ),
                    ),
                    const SizedBox(height: 12),

                    // فائل سے بحال کریں
                    OutlinedButton.icon(
                      onPressed: _importFromFile,
                      icon: const Icon(
                        Icons.upload_file,
                        color: Colors.deepPurple,
                      ),
                      label: const Text(
                        'فائل سے بحال کریں',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          color: Colors.deepPurple,
                        ),
                      ),
                      style: OutlinedButton.styleFrom(
                        side: BorderSide(color: Colors.deepPurple.shade300),
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16),
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),

                    // خودکار بیک اپ سوئچ
                    Card(
                      elevation: 2,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: SwitchListTile(
                        title: const Text(
                          'خودکار روزانہ بیک اپ',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        subtitle: const Text(
                          'ایپ کھلنے پر دن میں ایک بار خودکار بیک اپ',
                        ),
                        value: _autoBackupEnabled,
                        activeThumbColor: Colors.deepPurple,
                        secondary: const Icon(
                          Icons.autorenew,
                          color: Colors.deepPurple,
                        ),
                        onChanged: _toggleAutoBackup,
                      ),
                    ),
                    const SizedBox(height: 16),

                    // بیک اپ فہرست
                    const Padding(
                      padding: EdgeInsets.only(right: 8, bottom: 8),
                      child: Text(
                        'محفوظ بیک اپس',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          color: Colors.deepPurple,
                        ),
                      ),
                    ),
                    if (_backups.isEmpty)
                      const Card(
                        elevation: 2,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.all(Radius.circular(16)),
                        ),
                        child: Padding(
                          padding: EdgeInsets.all(24.0),
                          child: Center(
                            child: Text(
                              'ابھی تک کوئی بیک اپ نہیں بنا',
                              style: TextStyle(
                                fontSize: 16,
                                color: Colors.grey,
                              ),
                            ),
                          ),
                        ),
                      )
                    else
                      ..._backups.map(
                        (info) => Card(
                          elevation: 2,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(16),
                          ),
                          margin: const EdgeInsets.only(bottom: 12),
                          child: Padding(
                            padding: const EdgeInsets.all(12.0),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    const Icon(
                                      Icons.save,
                                      color: Colors.deepPurple,
                                    ),
                                    const SizedBox(width: 8),
                                    Expanded(
                                      child: Text(
                                        info.label,
                                        style: const TextStyle(
                                          fontSize: 16,
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                    ),
                                    if (info.isEncrypted)
                                      Container(
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 8,
                                          vertical: 2,
                                        ),
                                        decoration: BoxDecoration(
                                          color: Colors.green.shade50,
                                          borderRadius: BorderRadius.circular(
                                            8,
                                          ),
                                        ),
                                        child: Row(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            Icon(
                                              Icons.lock,
                                              size: 12,
                                              color: Colors.green.shade700,
                                            ),
                                            const SizedBox(width: 2),
                                            Text(
                                              'خفیہ',
                                              style: TextStyle(
                                                fontSize: 12,
                                                color: Colors.green.shade700,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                    if (_isAutoBackup(info))
                                      Container(
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 8,
                                          vertical: 2,
                                        ),
                                        decoration: BoxDecoration(
                                          color: Colors.deepPurple.shade50,
                                          borderRadius: BorderRadius.circular(
                                            8,
                                          ),
                                        ),
                                        child: Text(
                                          'خودکار',
                                          style: TextStyle(
                                            fontSize: 12,
                                            color: Colors.deepPurple.shade700,
                                          ),
                                        ),
                                      ),
                                  ],
                                ),
                                const SizedBox(height: 6),
                                Text(
                                  '${DateFormat('dd-MM-yyyy، hh:mm a').format(info.createdAt)}  •  ${_formatSize(info.sizeBytes)}  •  اسکیما v${info.schemaVersion ?? '?'}',
                                  style: const TextStyle(
                                    fontSize: 13,
                                    color: Colors.grey,
                                  ),
                                ),
                                if (info.isEncrypted &&
                                    info.hint.isNotEmpty) ...[
                                  const SizedBox(height: 4),
                                  Text(
                                    'یاد دہانی: ${info.hint}',
                                    style: TextStyle(
                                      fontSize: 13,
                                      color: Colors.deepPurple.shade400,
                                    ),
                                  ),
                                ],
                                const SizedBox(height: 8),
                                Row(
                                  mainAxisAlignment:
                                      MainAxisAlignment.spaceEvenly,
                                  children: [
                                    TextButton.icon(
                                      onPressed:
                                          _isRestoring
                                              ? null
                                              : () => _showRestoreDialog(info),
                                      icon: const Icon(Icons.restore, size: 18),
                                      label: const Text('بحال کریں'),
                                      style: TextButton.styleFrom(
                                        foregroundColor: Colors.deepPurple,
                                      ),
                                    ),
                                    TextButton.icon(
                                      onPressed: () => _shareBackup(info),
                                      icon: const Icon(Icons.share, size: 18),
                                      label: const Text('شیئر کریں'),
                                      style: TextButton.styleFrom(
                                        foregroundColor: Colors.blue,
                                      ),
                                    ),
                                    TextButton.icon(
                                      onPressed: () => _confirmDelete(info),
                                      icon: const Icon(Icons.delete, size: 18),
                                      label: const Text(Strings.delete),
                                      style: TextButton.styleFrom(
                                        foregroundColor: Colors.red,
                                      ),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    const SizedBox(height: 30),
                  ],
                ),
              ),
    );
  }
}
