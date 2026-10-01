import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../l10n/strings.dart';
import '../providers/expense_provider.dart';
import '../providers/harvest_provider.dart';
import '../providers/party_provider.dart';
import '../providers/task_provider.dart';
import '../services/recycle_bin_service.dart';
import '../widgets/digit_text.dart';
import '../widgets/empty_state_widget.dart';

/// The recycle bin: every soft-deleted row in one place, grouped by type.
///
/// Restoring is forgiving (a single tap). Permanent deletion is the ONLY
/// destructive path for soft-deleted rows and always asks for explicit
/// confirmation — the audit log keeps a record of it either way.
class RecycleBinScreen extends StatefulWidget {
  const RecycleBinScreen({super.key});

  @override
  State<RecycleBinScreen> createState() => _RecycleBinScreenState();
}

class _RecycleBinScreenState extends State<RecycleBinScreen> {
  List<DeletedItem> _items = [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _reload();
  }

  Future<void> _reload() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final items = await RecycleBinService.listDeleted();
      if (!mounted) return;
      setState(() {
        _items = items;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = 'ڈیٹا لوڈ کرنے میں مسئلہ ہوا۔ دوبارہ کوشش کریں۔';
        _loading = false;
      });
    }
  }

  Future<void> _restore(DeletedItem item) async {
    try {
      switch (item.table) {
        case 'expenses':
          await Provider.of<ExpenseProvider>(context, listen: false)
              .restoreExpense(item.id);
        case 'sales':
          await Provider.of<HarvestProvider>(context, listen: false)
              .restoreSale(item.id);
        case 'harvests':
          await Provider.of<HarvestProvider>(context, listen: false)
              .restoreHarvest(item.id);
        case 'tasks':
          await Provider.of<TaskProvider>(context, listen: false)
              .restoreTask(item.id);
        case 'parties':
          await Provider.of<PartyProvider>(context, listen: false)
              .restoreParty(item.id);
      }
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('بحال ہو گیا')),
      );
      await _reload();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('بحالی میں مسئلہ ہوا')),
      );
    }
  }

  Future<void> _confirmPermanentDelete(DeletedItem item) async {
    // Capture everything context-bound before the async gap.
    final messenger = ScaffoldMessenger.of(context);
    final expenses = Provider.of<ExpenseProvider>(context, listen: false);
    final harvests = Provider.of<HarvestProvider>(context, listen: false);
    final tasks = Provider.of<TaskProvider>(context, listen: false);
    final parties = Provider.of<PartyProvider>(context, listen: false);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('مستقل حذف کریں؟'),
        content: Text(
          '"${item.title}" ہمیشہ کے لیے حذف ہو جائے گا۔ یہ عمل واپس نہیں ہو سکتا۔',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text(Strings.cancel),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('مستقل حذف کریں',
                style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      switch (item.table) {
        case 'expenses':
          await expenses.permanentDeleteExpense(item.id);
        case 'sales':
          await harvests.permanentDeleteSale(item.id);
        case 'harvests':
          await harvests.permanentDeleteHarvest(item.id);
        case 'tasks':
          await tasks.permanentDeleteTask(item.id);
        case 'parties':
          await parties.permanentDeleteParty(item.id);
      }
      if (!mounted) return;
      messenger.showSnackBar(
        const SnackBar(content: Text('مستقل حذف ہو گیا')),
      );
      await _reload();
    } catch (e) {
      if (!mounted) return;
      messenger.showSnackBar(
        const SnackBar(content: Text('مستقل حذف میں مسئلہ ہوا')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('حذف شدہ'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _reload,
            tooltip: 'تازہ کریں',
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(_error!),
                      const SizedBox(height: 12),
                      ElevatedButton(
                        onPressed: _reload,
                        child: const Text('دوبارہ کوشش کریں'),
                      ),
                    ],
                  ),
                )
              : _items.isEmpty
                  ? const EmptyStateWidget(
                      message: 'ری سائیکل بن خالی ہے',
                      subtitle: 'حذف شدہ اخراجات، فروخت، پیداوار، کام اور پارٹیاں یہاں نظر آئیں گی',
                      fallbackIcon: Icons.delete_outline,
                      imageAsset: 'assets/images/wheat.png',
                    )
                  : RefreshIndicator(
                      onRefresh: _reload,
                      child: ListView.builder(
                        itemCount: _items.length,
                        itemBuilder: (ctx, index) {
                          final item = _items[index];
                          final showHeader = index == 0 ||
                              _items[index - 1].table != item.table;
                          return Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              if (showHeader)
                                Padding(
                                  padding: const EdgeInsets.fromLTRB(
                                      16, 16, 16, 4),
                                  child: Text(
                                    RecycleBinService.urduFor(item.table),
                                    style: const TextStyle(
                                      fontSize: 16,
                                      fontWeight: FontWeight.bold,
                                      color: Colors.deepOrange,
                                    ),
                                  ),
                                ),
                              Card(
                                margin: const EdgeInsets.symmetric(
                                    horizontal: 12, vertical: 4),
                                child: ListTile(
                                  title: Text(item.title),
                                  subtitle: DigitText(
                                    item.subtitle,
                                    style:
                                        TextStyle(color: Colors.grey.shade700),
                                  ),
                                  trailing: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      IconButton(
                                        icon: const Icon(Icons.restore,
                                            color: Colors.green),
                                        tooltip: 'بحال کریں',
                                        onPressed: () => _restore(item),
                                      ),
                                      IconButton(
                                        icon: const Icon(
                                            Icons.delete_forever,
                                            color: Colors.red),
                                        tooltip: 'مستقل حذف کریں',
                                        onPressed: () =>
                                            _confirmPermanentDelete(item),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ],
                          );
                        },
                      ),
                    ),
    );
  }
}
