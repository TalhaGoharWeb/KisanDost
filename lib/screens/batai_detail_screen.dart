import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/batai.dart';
import '../providers/batai_provider.dart';
import '../providers/harvest_provider.dart';
import '../services/money.dart';
import '../widgets/batai_status_chip.dart';
import 'batai_screen.dart';

/// One batai agreement: its terms, its settlements, and the actions
/// (settle a harvest, change status, edit, delete).
class BataiDetailScreen extends StatefulWidget {
  final int agreementId;
  const BataiDetailScreen({super.key, required this.agreementId});

  @override
  State<BataiDetailScreen> createState() => _BataiDetailScreenState();
}

class _BataiDetailScreenState extends State<BataiDetailScreen> {
  BataiAgreementSummary? _summary;
  List<BataiSettlement> _settlements = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final provider = context.read<BataiProvider>();
    final summary = await provider.getAgreementSummary(widget.agreementId);
    final settlements =
        await provider.getSettlements(widget.agreementId);
    if (!mounted) return;
    setState(() {
      _summary = summary;
      _settlements = settlements;
      _loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final summary = _summary;
    return Scaffold(
      appBar: AppBar(title: const Text('بٹائی معاہدے کی تفصیل')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : summary == null
              ? const Center(child: Text('معاہدہ نہیں ملا۔'))
              : RefreshIndicator(
                  onRefresh: _load,
                  child: ListView(
                    padding: const EdgeInsets.all(12),
                    children: [
                      _termsCard(summary),
                      const SizedBox(height: 12),
                      _totalsCard(summary.agreement),
                      const SizedBox(height: 12),
                      _actionsRow(summary),
                      const SizedBox(height: 16),
                      const Text('چکتائیاں',
                          style: TextStyle(
                              fontSize: 18, fontWeight: FontWeight.bold)),
                      const SizedBox(height: 8),
                      if (_settlements.isEmpty)
                        const Card(
                          child: Padding(
                            padding: EdgeInsets.all(16),
                            child: Text(
                              'ابھی کوئی چکتائی درج نہیں۔ فصل بکنے پر "حساب چکتا کریں" دبائیں۔',
                              style: TextStyle(fontSize: 15),
                            ),
                          ),
                        )
                      else
                        for (final s in _settlements) _settlementCard(s),
                      const SizedBox(height: 80),
                    ],
                  ),
                ),
      floatingActionButton: summary != null &&
              summary.agreement.status != BataiStatus.cancelled
          ? FloatingActionButton.extended(
              onPressed: () => _openSettleDialog(summary.agreement),
              icon: const Icon(Icons.calculate_outlined),
              label: const Text('حساب چکتا کریں'),
            )
          : null,
    );
  }

  Widget _termsCard(BataiAgreementSummary s) {
    final a = s.agreement;
    final place = [
      if (s.cropName != null) s.cropName,
      if (s.farmName != null) s.farmName,
      if (s.fieldName != null) s.fieldName,
    ].join(' • ');
    return Card(
      elevation: 3,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    s.partyName ?? 'نامعلوم فریق',
                    style: const TextStyle(
                        fontSize: 20, fontWeight: FontWeight.bold),
                  ),
                ),
                BataiStatusChip(status: a.status),
              ],
            ),
            const Divider(height: 24),
            _row('آپ کا کردار', farmerRoleUrdu(a.farmerRole)),
            _row('حصے',
                'مالک ${a.ownerSharePercent}٪ / مزارع ${a.cultivatorSharePercent}٪'),
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 6),
              child: Text(
                'آپ کا حصہ: ${a.mySharePercent}٪',
                style: TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.bold,
                  color: Colors.green.shade800,
                ),
              ),
            ),
            if (place.isNotEmpty) _row('زمین / فصل', place),
            _row('اخراجات کی تقسیم',
                (a.expenseNote?.isNotEmpty ?? false) ? a.expenseNote! : 'درج نہیں'),
            _row('مدت',
                a.endDate == null ? '${a.startDate} سے جاری' : '${a.startDate} تا ${a.endDate}'),
            if (a.notes?.isNotEmpty ?? false) _row('نوٹ', a.notes!),
          ],
        ),
      ),
    );
  }

  Widget _row(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 130,
            child: Text(label,
                style:
                    TextStyle(fontSize: 14, color: Colors.grey.shade700)),
          ),
          Expanded(
            child: Text(value,
                style: const TextStyle(
                    fontSize: 15, fontWeight: FontWeight.w500)),
          ),
        ],
      ),
    );
  }

  Widget _totalsCard(BataiAgreement a) {
    var total = 0, mine = 0;
    for (final s in _settlements) {
      total += s.totalPaisa;
      mine += a.farmerRole == FarmerRole.landowner
          ? s.ownerPaisa
          : s.cultivatorPaisa;
    }
    return Card(
      elevation: 2,
      color: Colors.green.shade50,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('اب تک کل چکتائی',
                      style: TextStyle(fontSize: 14)),
                  Text(Money(total).format(),
                      style: const TextStyle(
                          fontSize: 18, fontWeight: FontWeight.bold)),
                ],
              ),
            ),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('آپ کا موصول شدہ حصہ',
                      style: TextStyle(fontSize: 14)),
                  Text(Money(mine).format(),
                      style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                          color: Colors.green.shade800)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _actionsRow(BataiAgreementSummary s) {
    final a = s.agreement;
    final termsLocked = _settlements.isNotEmpty;
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        PopupMenuButton<BataiStatus>(
          child: Container(
            padding:
                const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: BoxDecoration(
              border: Border.all(color: Colors.grey.shade400),
              borderRadius: BorderRadius.circular(8),
            ),
            child: const Text('حیثیت بدلیں',
                style: TextStyle(fontSize: 15)),
          ),
          onSelected: (status) => _changeStatus(a.id!, status),
          itemBuilder: (_) => [
            for (final st in BataiStatus.values)
              PopupMenuItem(
                  value: st, child: Text(bataiStatusUrdu(st))),
          ],
        ),
        OutlinedButton(
          onPressed: termsLocked
              ? () => ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                        content: Text(
                            'چکتائی ہو چکی ہے — شرائط تبدیل نہیں ہو سکتیں۔')),
                  )
              : () => _openEditForm(s),
          child: const Text('شرائط میں ترمیم'),
        ),
        TextButton(
          onPressed: () => _delete(a.id!),
          child: const Text('حذف کریں',
              style: TextStyle(color: Colors.red)),
        ),
      ],
    );
  }

  Widget _settlementCard(BataiSettlement s) {
    final link = _linkLabel(s);
    return Card(
      margin: const EdgeInsets.symmetric(vertical: 6),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    '${Money(s.totalPaisa).format()} • ${s.settleDate}',
                    style: const TextStyle(
                        fontSize: 16, fontWeight: FontWeight.bold),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text('مالک: ${Money(s.ownerPaisa).format()}',
                style: const TextStyle(fontSize: 14)),
            Text('مزارع: ${Money(s.cultivatorPaisa).format()}',
                style: const TextStyle(fontSize: 14)),
            if (link != null) ...[
              const SizedBox(height: 4),
              Text(link,
                  style:
                      TextStyle(fontSize: 13, color: Colors.grey.shade700)),
            ],
            if (s.note?.isNotEmpty ?? false) ...[
              const SizedBox(height: 4),
              Text(s.note!,
                  style:
                      TextStyle(fontSize: 13, color: Colors.grey.shade700)),
            ],
          ],
        ),
      ),
    );
  }

  /// Human label for the linked harvest/sale, resolved in-memory.
  String? _linkLabel(BataiSettlement s) {
    final hp = context.read<HarvestProvider>();
    if (s.harvestId != null) {
      for (final h in hp.harvests) {
        if (h.harvest.id == s.harvestId) {
          return 'پیداوار: ${h.cropName} — ${h.harvest.quantity} ${h.harvest.unit} (${h.harvest.date})';
        }
      }
      return 'پیداوار #${s.harvestId}';
    }
    if (s.saleId != null) {
      for (final sale in hp.sales) {
        if (sale.id == s.saleId) {
          final buyer = (sale.buyerName?.isNotEmpty ?? false)
              ? sale.buyerName!
              : 'نامعلوم خریدار';
          return 'فروخت: $buyer — ${Money(sale.totalAmountPaisa).format()} (${sale.date})';
        }
      }
      return 'فروخت #${s.saleId}';
    }
    return null;
  }

  Future<void> _openSettleDialog(BataiAgreement a) async {
    final done = await showDialog<bool>(
      context: context,
      builder: (_) => _SettleDialog(agreement: a),
    );
    if (done == true && mounted) _load();
  }

  Future<void> _changeStatus(int id, BataiStatus status) async {
    try {
      await context.read<BataiProvider>().setStatus(id, status);
      if (mounted) _load();
    } on BataiException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(e.message)));
      }
    }
  }

  Future<void> _openEditForm(BataiAgreementSummary s) async {
    final saved = await showDialog<bool>(
      context: context,
      builder: (_) => BataiAgreementDialog(
        existing: s,
        settlementCount: _settlements.length,
      ),
    );
    if (saved == true && mounted) _load();
  }

  Future<void> _delete(int id) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('معاہدہ حذف کریں؟'),
        content: const Text('یہ معاہدہ مستقل طور پر حذف ہو جائے گا۔'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('منسوخ کریں'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child:
                const Text('حذف کریں', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
    if (confirm != true || !mounted) return;
    try {
      await context.read<BataiProvider>().deleteAgreement(id);
      if (mounted) Navigator.pop(context);
    } on BataiException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(e.message)));
      }
    }
  }
}

/// Settlement (چکتائی) dialog: the farmer enters the total, sees the exact
/// owner/cultivator split per the rounding rule BEFORE confirming, and may
/// optionally link the harvest/sale it came from.
class _SettleDialog extends StatefulWidget {
  final BataiAgreement agreement;
  const _SettleDialog({required this.agreement});

  @override
  State<_SettleDialog> createState() => _SettleDialogState();
}

class _SettleDialogState extends State<_SettleDialog> {
  late final TextEditingController _totalCtrl;
  late final TextEditingController _dateCtrl;
  late final TextEditingController _noteCtrl;
  int? _harvestId;
  int? _saleId;
  ({int ownerPaisa, int cultivatorPaisa})? _preview;

  @override
  void initState() {
    super.initState();
    _totalCtrl = TextEditingController();
    _dateCtrl = TextEditingController(text: _today());
    _noteCtrl = TextEditingController();
    _totalCtrl.addListener(_updatePreview);
  }

  String _today() {
    final n = DateTime.now();
    return '${n.year.toString().padLeft(4, '0')}-'
        '${n.month.toString().padLeft(2, '0')}-'
        '${n.day.toString().padLeft(2, '0')}';
  }

  void _updatePreview() {
    ({int ownerPaisa, int cultivatorPaisa})? next;
    try {
      final total = Money.parse(_totalCtrl.text).paisa;
      if (total > 0) {
        next = splitBatai(total, widget.agreement.ownerSharePercent);
      }
    } catch (_) {
      next = null;
    }
    if (mounted) setState(() => _preview = next);
  }

  Future<void> _pickDate() async {
    final initial = DateTime.tryParse(_dateCtrl.text.trim()) ?? DateTime.now();
    final date = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
    );
    if (date != null) {
      _dateCtrl.text = '${date.year.toString().padLeft(4, '0')}-'
          '${date.month.toString().padLeft(2, '0')}-'
          '${date.day.toString().padLeft(2, '0')}';
    }
  }

  Future<void> _save() async {
    try {
      final total = Money.parse(_totalCtrl.text).paisa;
      await context.read<BataiProvider>().settleAgreement(
            agreementId: widget.agreement.id!,
            totalPaisa: total,
            harvestId: _harvestId,
            saleId: _saleId,
            settleDate: _dateCtrl.text.trim(),
            note: _noteCtrl.text,
          );
      if (mounted) Navigator.pop(context, true);
    } on BataiException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(e.message)));
      }
    } on Object catch (e) {
      // Money.parse throws MoneyParseException with an Urdu message.
      if (mounted) {
        final msg = e.toString().replaceFirst('MoneyParseException: ', '');
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final hp = context.watch<HarvestProvider>();
    return AlertDialog(
      title: const Text('حساب چکتا کریں'),
      content: SingleChildScrollView(
        child: SizedBox(
          width: 420,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              TextField(
                controller: _totalCtrl,
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true),
                decoration: const InputDecoration(
                  labelText: 'کل رقم (روپے) *',
                  hintText: 'مثلاً 125000',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.green.shade50,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.green.shade200),
                ),
                child: _preview == null
                    ? const Text('رقم لکھیں تو حصے یہاں نظر آئیں گے',
                        style: TextStyle(fontSize: 14))
                    : Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                              'مالک: ${Money(_preview!.ownerPaisa).format()}',
                              style: const TextStyle(
                                  fontSize: 15,
                                  fontWeight: FontWeight.bold)),
                          Text(
                              'مزارع: ${Money(_preview!.cultivatorPaisa).format()}',
                              style: const TextStyle(
                                  fontSize: 15,
                                  fontWeight: FontWeight.bold)),
                          const SizedBox(height: 4),
                          Text(
                            'باقی ماندہ پیسے (0–99) بڑے حصے میں شامل ہیں — برابری پر مالک کو ملتے ہیں۔',
                            style: TextStyle(
                                fontSize: 12,
                                color: Colors.grey.shade700),
                          ),
                        ],
                      ),
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<int?>(
                initialValue: _harvestId,
                decoration: const InputDecoration(
                  labelText: 'پیداوار (اختیاری)',
                  border: OutlineInputBorder(),
                ),
                items: [
                  const DropdownMenuItem<int?>(
                      value: null, child: Text('— کوئی نہیں —')),
                  for (final h in hp.harvests)
                    DropdownMenuItem<int?>(
                      value: h.harvest.id,
                      child: Text(
                          '${h.cropName} — ${h.harvest.quantity} ${h.harvest.unit} (${h.harvest.date})'),
                    ),
                ],
                onChanged: (v) => setState(() => _harvestId = v),
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<int?>(
                initialValue: _saleId,
                decoration: const InputDecoration(
                  labelText: 'فروخت (اختیاری)',
                  border: OutlineInputBorder(),
                ),
                items: [
                  const DropdownMenuItem<int?>(
                      value: null, child: Text('— کوئی نہیں —')),
                  for (final s in hp.sales)
                    DropdownMenuItem<int?>(
                      value: s.id,
                      child: Text(
                          '${(s.buyerName?.isNotEmpty ?? false) ? s.buyerName! : 'نامعلوم خریدار'} — ${Money(s.totalAmountPaisa).format()} (${s.date})'),
                    ),
                ],
                onChanged: (v) => setState(() => _saleId = v),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _dateCtrl,
                readOnly: true,
                decoration: const InputDecoration(
                  labelText: 'تاریخ *',
                  border: OutlineInputBorder(),
                ),
                onTap: _pickDate,
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _noteCtrl,
                maxLines: 2,
                decoration: const InputDecoration(
                  labelText: 'نوٹ (اختیاری)',
                  border: OutlineInputBorder(),
                ),
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('منسوخ کریں'),
        ),
        ElevatedButton(
          onPressed: _save,
          child: const Text('چکتائی محفوظ کریں'),
        ),
      ],
    );
  }

  @override
  void dispose() {
    _totalCtrl.dispose();
    _dateCtrl.dispose();
    _noteCtrl.dispose();
    super.dispose();
  }
}
