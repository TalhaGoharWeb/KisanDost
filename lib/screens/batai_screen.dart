import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../services/quantity.dart';
import '../models/batai.dart';
import '../models/party.dart';
import '../providers/batai_provider.dart';
import '../providers/party_provider.dart';
import '../providers/farm_provider.dart';
import '../providers/crop_provider.dart';
import '../providers/harvest_provider.dart';
import '../widgets/empty_state_widget.dart';
import '../widgets/batai_status_chip.dart';
import 'batai_detail_screen.dart';
import '../l10n/strings.dart';

/// بٹائی (sharecropping) agreements: who splits the harvest with whom.
class BataiScreen extends StatefulWidget {
  const BataiScreen({super.key});

  @override
  State<BataiScreen> createState() => _BataiScreenState();
}

class _BataiScreenState extends State<BataiScreen> {
  BataiStatus? _filter; // null = all

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _refresh());
  }

  Future<void> _refresh() async {
    final batai = context.read<BataiProvider>();
    final parties = context.read<PartyProvider>();
    final farms = context.read<FarmProvider>();
    final crops = context.read<CropProvider>();
    final harvests = context.read<HarvestProvider>();
    await batai.fetchAgreements();
    await parties.fetchParties();
    await farms.fetchFarms();
    await crops.fetchCropSeasons();
    await harvests.fetchHarvests();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('بٹائی معاہدے')),
      body: Consumer<BataiProvider>(
        builder: (context, provider, _) {
          if (provider.errorMessage != null) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(provider.errorMessage!,
                        textAlign: TextAlign.center,
                        style: const TextStyle(fontSize: 16)),
                    const SizedBox(height: 12),
                    ElevatedButton(
                      onPressed: _refresh,
                      child: const Text('دوبارہ کوشش کریں'),
                    ),
                  ],
                ),
              ),
            );
          }
          final all = provider.agreements;
          final shown = _filter == null
              ? all
              : all
                  .where((s) => s.agreement.status == _filter)
                  .toList();
          return RefreshIndicator(
            onRefresh: _refresh,
            child: ListView(
              padding: const EdgeInsets.all(12),
              children: [
                _filterRow(all),
                const SizedBox(height: 8),
                if (shown.isEmpty)
                  const EmptyStateWidget(
                    message: 'ابھی کوئی بٹائی معاہدہ درج نہیں',
                    subtitle:
                        'نیچے بٹن دبائیں اور لکھیں کہ فصل کی پیداوار کس کے ساتھ کیسے بٹے گی',
                    fallbackIcon: Icons.handshake_outlined,
                    imageAsset: 'assets/images/wheat.png',
                  )
                else
                  for (final s in shown) _agreementCard(s),
                const SizedBox(height: 80),
              ],
            ),
          );
        },
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _openForm(),
        icon: const Icon(Icons.add),
        label: const Text('نیا بٹائی معاہدہ'),
      ),
    );
  }

  Widget _filterRow(List<BataiAgreementSummary> all) {
    int count(BataiStatus? s) =>
        s == null ? all.length : all.where((x) => x.agreement.status == s).length;
    final chips = <Widget>[
      _filterChip(null, 'تمام', count(null)),
      _filterChip(BataiStatus.active, 'فعال', count(BataiStatus.active)),
      _filterChip(BataiStatus.settled, 'چکتا شدہ', count(BataiStatus.settled)),
      _filterChip(
          BataiStatus.cancelled, 'منسوخ', count(BataiStatus.cancelled)),
    ];
    return Wrap(spacing: 8, runSpacing: 4, children: chips);
  }

  Widget _filterChip(BataiStatus? status, String label, int count) {
    final selected = _filter == status;
    return FilterChip(
      label: Text('$label ($count)'),
      selected: selected,
      onSelected: (_) => setState(() => _filter = status),
    );
  }

  Widget _agreementCard(BataiAgreementSummary s) {
    final a = s.agreement;
    final place = [
      if (s.cropName != null) s.cropName,
      if (s.farmName != null) s.farmName,
      if (s.fieldName != null) s.fieldName,
    ].join(' • ');
    return Card(
      elevation: 2,
      margin: const EdgeInsets.symmetric(vertical: 6),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () => Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => BataiDetailScreen(agreementId: a.id!),
          ),
        ).then((_) => _refresh()),
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
                          fontSize: 18, fontWeight: FontWeight.bold),
                    ),
                  ),
                  BataiStatusChip(status: a.status),
                ],
              ),
              const SizedBox(height: 6),
              Text(
                farmerRoleUrdu(a.farmerRole),
                style:
                    TextStyle(fontSize: 14, color: Colors.grey.shade700),
              ),
              if (place.isNotEmpty) ...[
                const SizedBox(height: 4),
                Text(place,
                    style: TextStyle(
                        fontSize: 14, color: Colors.grey.shade700)),
              ],
              const SizedBox(height: 8),
              Text(
                'مالک ${a.ownerSharePercent}٪ / مزارع ${a.cultivatorSharePercent}٪',
                style: const TextStyle(fontSize: 15),
              ),
              Text(
                'آپ کا حصہ: ${a.mySharePercent}٪',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: Colors.green.shade800,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _openForm({BataiAgreementSummary? existing}) async {
    int settlements = 0;
    if (existing != null) {
      settlements = (await context
              .read<BataiProvider>()
              .getSettlements(existing.agreement.id!))
          .length;
    }
    if (!mounted) return;
    final saved = await showDialog<bool>(
      context: context,
      builder: (_) => BataiAgreementDialog(
        existing: existing,
        settlementCount: settlements,
      ),
    );
    if (saved == true && mounted) _refresh();
  }
}

/// Create/edit dialog for a batai agreement.
///
/// Terms (role, party, shares, links, dates) are editable only while the
/// agreement has no settlements — afterwards the fields are disabled and
/// only the free-text notes can change.
class BataiAgreementDialog extends StatefulWidget {
  final BataiAgreementSummary? existing;
  final int settlementCount;
  const BataiAgreementDialog(
      {super.key, this.existing, required this.settlementCount});

  @override
  State<BataiAgreementDialog> createState() => BataiAgreementDialogState();
}

class BataiAgreementDialogState extends State<BataiAgreementDialog> {
  late FarmerRole _role;
  int? _partyId;
  int? _farmId;
  int? _fieldId;
  int? _cropId;
  late final TextEditingController _ownerCtrl;
  late final TextEditingController _cultCtrl;
  late final TextEditingController _expenseCtrl;
  late final TextEditingController _startCtrl;
  late final TextEditingController _endCtrl;
  late final TextEditingController _notesCtrl;
  bool _balancing = false;

  bool get _termsLocked =>
      widget.existing != null && widget.settlementCount > 0;

  @override
  void initState() {
    super.initState();
    final e = widget.existing?.agreement;
    _role = e?.farmerRole ?? FarmerRole.cultivator;
    _partyId = e?.otherPartyId;
    _farmId = e?.farmId;
    _fieldId = e?.fieldId;
    _cropId = e?.cropSeasonId;
    _ownerCtrl =
        TextEditingController(text: (e?.ownerSharePercent ?? 50).toString());
    _cultCtrl = TextEditingController(
        text: (e?.cultivatorSharePercent ?? 50).toString());
    _expenseCtrl = TextEditingController(text: e?.expenseNote ?? '');
    _startCtrl = TextEditingController(text: e?.startDate ?? _today());
    _endCtrl = TextEditingController(text: e?.endDate ?? '');
    _notesCtrl = TextEditingController(text: e?.notes ?? '');
    _ownerCtrl.addListener(() => _rebalance(_ownerCtrl, _cultCtrl));
    _cultCtrl.addListener(() => _rebalance(_cultCtrl, _ownerCtrl));
  }

  /// Whole percentages only: Quantity accepts Urdu digits; a fractional
  /// share is rejected (not rounded) so the farmer's terms stay exact.
  static int? _wholePercent(String text) {
    final v = Quantity.tryParse(text.trim());
    if (v == null || v != v.roundToDouble()) return null;
    return v.toInt();
  }

  void _rebalance(
      TextEditingController from, TextEditingController to) {
    if (_balancing) return;
    final v = _wholePercent(from.text);
    if (v == null) return;
    _balancing = true;
    to.text = (100 - v).toString();
    _balancing = false;
  }

  String _today() {
    final n = DateTime.now();
    return '${n.year.toString().padLeft(4, '0')}-'
        '${n.month.toString().padLeft(2, '0')}-'
        '${n.day.toString().padLeft(2, '0')}';
  }

  Future<void> _pickDate(TextEditingController ctrl) async {
    final initial = DateTime.tryParse(ctrl.text.trim()) ?? DateTime.now();
    final date = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
    );
    if (date != null) {
      ctrl.text = '${date.year.toString().padLeft(4, '0')}-'
          '${date.month.toString().padLeft(2, '0')}-'
          '${date.day.toString().padLeft(2, '0')}';
    }
  }

  Future<void> _addPartyFlow() async {
    final nameCtrl = TextEditingController();
    final phoneCtrl = TextEditingController();
    final data = await showDialog<Map<String, String>>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('نیا فریق'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: nameCtrl,
              decoration: const InputDecoration(
                labelText: 'نام *',
                hintText: 'مثلاً چوہدری صاحب',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: phoneCtrl,
              keyboardType: TextInputType.phone,
              decoration: const InputDecoration(
                labelText: 'فون نمبر (اختیاری)',
                border: OutlineInputBorder(),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('منسوخ کریں'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(
                ctx, {'name': nameCtrl.text, 'phone': phoneCtrl.text}),
            child: const Text('شامل کریں'),
          ),
        ],
      ),
    );
    if (data == null || !mounted) return;
    try {
      final id = await context.read<PartyProvider>().addParty(Party(
            name: data['name'] ?? '',
            phone: (data['phone'] ?? '').trim().isEmpty
                ? null
                : data['phone'],
            createdAt: DateTime.now().toIso8601String(),
          ));
      setState(() => _partyId = id);
    } on PartyException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(e.message)));
      }
    }
  }

  Future<void> _save() async {
    final provider = context.read<BataiProvider>();
    final owner = _wholePercent(_ownerCtrl.text);
    final cult = _wholePercent(_cultCtrl.text);
    if (_partyId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('دوسرا فریق منتخب کریں۔')));
      return;
    }
    if (owner == null || cult == null) {
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('حصے درست اعداد میں درج کریں۔')));
      return;
    }
    try {
      final existing = widget.existing;
      if (existing == null) {
        await provider.createAgreement(
          farmerRole: _role,
          otherPartyId: _partyId!,
          farmId: _farmId,
          fieldId: _fieldId,
          cropSeasonId: _cropId,
          ownerSharePercent: owner,
          cultivatorSharePercent: cult,
          expenseNote: _expenseCtrl.text,
          startDate: _startCtrl.text.trim(),
          endDate: _endCtrl.text.trim().isEmpty ? null : _endCtrl.text.trim(),
          notes: _notesCtrl.text,
        );
      } else {
        if (!_termsLocked) {
          await provider.updateTerms(
            id: existing.agreement.id!,
            farmerRole: _role,
            otherPartyId: _partyId!,
            farmId: _farmId,
            fieldId: _fieldId,
            cropSeasonId: _cropId,
            ownerSharePercent: owner,
            cultivatorSharePercent: cult,
            startDate: _startCtrl.text.trim(),
            endDate:
                _endCtrl.text.trim().isEmpty ? null : _endCtrl.text.trim(),
          );
        }
        await provider.updateNotes(
          existing.agreement.id!,
          expenseNote: _expenseCtrl.text,
          notes: _notesCtrl.text,
        );
      }
      if (mounted) Navigator.pop(context, true);
    } on BataiException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(e.message)));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final partyProvider = context.watch<PartyProvider>();
    final farmProvider = context.watch<FarmProvider>();
    final cropProvider = context.watch<CropProvider>();
    final locked = _termsLocked;

    final fields =
        _farmId == null ? const [] : farmProvider.getFieldsForFarm(_farmId!);
    final crops = [
      ...cropProvider.activeCropSeasons,
      ...cropProvider.harvestedCropSeasons,
    ];

    return AlertDialog(
      title: Text(widget.existing == null
          ? 'نیا بٹائی معاہدہ'
          : 'بٹائی معاہدے میں ترمیم'),
      content: SingleChildScrollView(
        child: SizedBox(
          width: 420,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (locked)
                Container(
                  padding: const EdgeInsets.all(10),
                  margin: const EdgeInsets.only(bottom: 12),
                  decoration: BoxDecoration(
                    color: Colors.amber.shade100,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Text(
                    'اس معاہدے کی چکتائی ہو چکی ہے — شرائط تبدیل نہیں ہو سکتیں۔ صرف نوٹ بدلے جا سکتے ہیں۔',
                    style: TextStyle(fontSize: 13),
                  ),
                ),
              const Text('آپ کا کردار',
                  style: TextStyle(fontWeight: FontWeight.bold)),
              if (locked)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  child: Text(farmerRoleUrdu(_role),
                      style: const TextStyle(fontSize: 16)),
                )
              else
                RadioGroup<FarmerRole>(
                  groupValue: _role,
                  onChanged: (v) => setState(() => _role = v!),
                  child: const Column(
                    children: [
                      RadioListTile<FarmerRole>(
                        title: Text('میں مالک ہوں'),
                        value: FarmerRole.landowner,
                        dense: true,
                      ),
                      RadioListTile<FarmerRole>(
                        title: Text('میں مزارع ہوں'),
                        value: FarmerRole.cultivator,
                        dense: true,
                      ),
                    ],
                  ),
                ),
              const SizedBox(height: 8),
              DropdownButtonFormField<int>(
                initialValue: _partyId,
                decoration: const InputDecoration(
                  labelText: 'دوسرا فریق *',
                  border: OutlineInputBorder(),
                ),
                items: [
                  for (final p in partyProvider.parties)
                    DropdownMenuItem(value: p.id, child: Text(p.name)),
                  const DropdownMenuItem(
                      value: -1, child: Text('+ نیا فریق شامل کریں')),
                ],
                onChanged: locked
                    ? null
                    : (v) {
                        if (v == -1) {
                          _addPartyFlow();
                        } else {
                          setState(() => _partyId = v);
                        }
                      },
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<int?>(
                initialValue: _farmId,
                decoration: const InputDecoration(
                  labelText: 'زمین (اختیاری)',
                  border: OutlineInputBorder(),
                ),
                items: [
                  const DropdownMenuItem<int?>(
                      value: null, child: Text('— کوئی نہیں —')),
                  for (final f in farmProvider.farms)
                    DropdownMenuItem<int?>(value: f.id, child: Text(f.name)),
                ],
                onChanged: locked
                    ? null
                    : (v) => setState(() {
                          _farmId = v;
                          _fieldId = null;
                        }),
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<int?>(
                initialValue: _fieldId,
                decoration: const InputDecoration(
                  labelText: 'کھیت (اختیاری)',
                  border: OutlineInputBorder(),
                ),
                items: [
                  const DropdownMenuItem<int?>(
                      value: null, child: Text('— کوئی نہیں —')),
                  for (final f in fields)
                    DropdownMenuItem<int?>(value: f.id, child: Text(f.name)),
                ],
                onChanged: locked || _farmId == null
                    ? null
                    : (v) => setState(() => _fieldId = v),
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<int?>(
                initialValue: _cropId,
                decoration: const InputDecoration(
                  labelText: 'فصل (اختیاری)',
                  border: OutlineInputBorder(),
                ),
                items: [
                  const DropdownMenuItem<int?>(
                      value: null, child: Text('— کوئی نہیں —')),
                  for (final c in crops)
                    DropdownMenuItem<int?>(
                      value: c.cropSeason.id,
                      child: Text(
                          '${c.cropSeason.cropName} (${c.cropSeason.variety})'),
                    ),
                ],
                onChanged:
                    locked ? null : (v) => setState(() => _cropId = v),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _ownerCtrl,
                      enabled: !locked,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(
                        labelText: 'مالک کا حصہ ٪ *',
                        border: OutlineInputBorder(),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: TextField(
                      controller: _cultCtrl,
                      enabled: !locked,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(
                        labelText: 'مزارع کا حصہ ٪ *',
                        border: OutlineInputBorder(),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              Text(
                'ایک حصہ بدلیں تو دوسرا خود بخود متوازن ہو جائے گا (مجموعہ 100)',
                style:
                    TextStyle(fontSize: 12, color: Colors.grey.shade600),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _expenseCtrl,
                maxLines: 2,
                decoration: const InputDecoration(
                  labelText: 'اخراجات کی تقسیم',
                  hintText: 'مثلاً: کھاد مزارع کی، بیج آدھا آدھا',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _startCtrl,
                      readOnly: true,
                      enabled: !locked,
                      decoration: const InputDecoration(
                        labelText: 'آغاز کی تاریخ *',
                        border: OutlineInputBorder(),
                      ),
                      onTap: locked ? null : () => _pickDate(_startCtrl),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: TextField(
                      controller: _endCtrl,
                      readOnly: true,
                      enabled: !locked,
                      decoration: const InputDecoration(
                        labelText: 'اختتام (اختیاری)',
                        border: OutlineInputBorder(),
                      ),
                      onTap: locked ? null : () => _pickDate(_endCtrl),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _notesCtrl,
                maxLines: 2,
                decoration: const InputDecoration(
                  labelText: Strings.noteOptional,
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
          child: const Text(Strings.save),
        ),
      ],
    );
  }

  @override
  void dispose() {
    _ownerCtrl.dispose();
    _cultCtrl.dispose();
    _expenseCtrl.dispose();
    _startCtrl.dispose();
    _endCtrl.dispose();
    _notesCtrl.dispose();
    super.dispose();
  }
}
