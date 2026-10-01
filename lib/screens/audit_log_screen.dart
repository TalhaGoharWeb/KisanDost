import 'package:flutter/material.dart';
import 'package:sqflite/sqflite.dart';
import '../services/audit_service.dart';
import '../services/today_summary.dart' show urduDateLine;
import '../widgets/empty_state_widget.dart';

/// Read-only audit trail viewer: every create/update/delete the app logged,
/// newest first.
///
/// The log is the farmer's proof of what happened to their data — this
/// screen only READS it. There is no delete, edit, or clear action here
/// (the table is append-only by design).
class AuditLogScreen extends StatefulWidget {
  /// Test seam: pass an in-memory [DatabaseExecutor] in widget tests.
  /// Production callers omit it and read the app database.
  final DatabaseExecutor? executor;

  const AuditLogScreen({super.key, this.executor});

  @override
  State<AuditLogScreen> createState() => _AuditLogScreenState();
}

class _AuditLogScreenState extends State<AuditLogScreen> {
  List<Map<String, dynamic>> _rows = [];
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
      final rows = await AuditService.listAll(executor: widget.executor);
      if (!mounted) return;
      setState(() {
        _rows = rows;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = 'ریکارڈ لوڈ کرنے میں مسئلہ ہوا۔ دوبارہ کوشش کریں۔';
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('تبدیلیوں کا ریکارڈ'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: 'تازہ کریں',
            onPressed: _reload,
          ),
        ],
      ),
      body:
          _loading
              ? const Center(child: CircularProgressIndicator())
              : _error != null
              ? Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(_error!, style: const TextStyle(fontSize: 16)),
                    const SizedBox(height: 12),
                    ElevatedButton(
                      onPressed: _reload,
                      child: const Text('دوبارہ کوشش کریں'),
                    ),
                  ],
                ),
              )
              : _rows.isEmpty
              ? const EmptyStateWidget(
                message: 'ابھی کوئی تبدیلی درج نہیں',
                subtitle:
                    'جب آپ خرچ، فروخت، فریق یا کوئی اور ریکارڈ بنائیں یا بدلیں گے تو وہ یہاں نظر آئے گا۔',
                fallbackIcon: Icons.history,
                imageAsset: '',
              )
              : RefreshIndicator(
                onRefresh: _reload,
                child: ListView.separated(
                  padding: const EdgeInsets.all(12),
                  itemCount: _rows.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 8),
                  itemBuilder: (context, i) => _auditTile(_rows[i]),
                ),
              ),
    );
  }

  Widget _auditTile(Map<String, dynamic> row) {
    final action = row['action'] as String? ?? '';
    final table = row['table_name'] as String? ?? '';
    final details = row['details'] as String? ?? '';
    final ts = row['ts'] as String? ?? '';
    return Card(
      elevation: 1,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: _actionColor(action).withValues(alpha: 0.12),
          child: Icon(
            _actionIcon(action),
            color: _actionColor(action),
            size: 20,
          ),
        ),
        title: Text(
          '${_tableUrdu(table)} — ${_actionUrdu(action)}',
          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (details.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(details, style: const TextStyle(fontSize: 14)),
              ),
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(
                _formatTs(ts),
                style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _formatTs(String ts) {
    final dt = DateTime.tryParse(ts);
    if (dt == null) return ts;
    return urduDateLine(dt);
  }
}

/// Urdu label for an audit action. Unknown actions fall back to the raw
/// value — never blank, never invented.
String _actionUrdu(String action) => switch (action) {
  'create' => 'بنایا گیا',
  'update' => 'تبدیل کیا گیا',
  'delete' => 'حذف کیا گیا',
  'soft_delete' => 'حذف کیا گیا',
  'restore' => 'بحال کیا گیا',
  'permanent_delete' => 'مستقل حذف کیا گیا',
  _ => action,
};

/// Urdu label for a table name. Unknown tables fall back to the raw name.
String _tableUrdu(String table) => switch (table) {
  'expenses' => 'خرچ',
  'sales' => 'فروخت',
  'harvests' => 'پیداوار',
  'tasks' => 'کام',
  'parties' => 'فریق',
  'party_ledger_entries' => 'کھاتہ اندراج',
  'batai_agreements' => 'بٹائی معاہدہ',
  'batai_settlements' => 'بٹائی چکتائی',
  'inventory_transactions' => 'اسٹاک لین دین',
  'inventory_items' => 'اسٹاک چیز',
  'thekas' => 'ٹھیکہ',
  'theka_installments' => 'ٹھیکہ قسط',
  'ushr_records' => 'عشر',
  'farms' => 'فارم',
  'fields' => 'کھیت',
  'crop_seasons' => 'فصل',
  _ => table,
};

Color _actionColor(String action) => switch (action) {
  'create' => Colors.green.shade700,
  'restore' => Colors.teal.shade700,
  'delete' || 'soft_delete' || 'permanent_delete' => Colors.red.shade700,
  _ => Colors.blueGrey.shade700,
};

IconData _actionIcon(String action) => switch (action) {
  'create' => Icons.add_circle_outline,
  'restore' => Icons.restore,
  'delete' || 'soft_delete' || 'permanent_delete' => Icons.delete_outline,
  _ => Icons.edit_outlined,
};
