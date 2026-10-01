import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../widgets/digit_text.dart';
import '../models/party.dart';
import '../providers/party_provider.dart';
import '../services/money.dart';
import '../services/today_summary.dart';
import '../widgets/empty_state_widget.dart';
import '../l10n/strings.dart';

class PartyDetailScreen extends StatefulWidget {
  final int partyId;
  const PartyDetailScreen({super.key, required this.partyId});

  @override
  State<PartyDetailScreen> createState() => _PartyDetailScreenState();
}

class _PartyDetailScreenState extends State<PartyDetailScreen> {
  List<PartyLedgerEntry> _entries = [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final entries = await context.read<PartyProvider>().getEntries(
        widget.partyId,
      );
      if (mounted) {
        setState(() {
          _entries = entries;
          _loading = false;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _error = 'اندراجات لوڈ نہیں ہو سکے۔ دوبارہ کوشش کریں۔';
          _loading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final provider = Provider.of<PartyProvider>(context);
    Party? party;
    for (final p in provider.parties) {
      if (p.id == widget.partyId) {
        party = p;
        break;
      }
    }
    final balance = provider.balanceOf(widget.partyId);
    final Color balanceColor =
        balance > 0
            ? Colors.green.shade700
            : balance < 0
            ? Colors.red.shade700
            : Colors.grey.shade600;
    final String balanceWord =
        balance > 0
            ? 'لینا ہے'
            : balance < 0
            ? 'دینا ہے'
            : 'حساب برابر';

    return Scaffold(
      appBar: AppBar(
        title: Text(party?.name ?? 'پارٹی کھاتہ'),
        actions: [
          if (party != null)
            IconButton(
              icon: const Icon(Icons.edit),
              tooltip: 'ترمیم',
              onPressed: () => _showEditPartyDialog(context, provider, party!),
            ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: () async {
          await provider.fetchParties();
          await _load();
        },
        child: Column(
          children: [
            Container(
              width: double.infinity,
              margin: const EdgeInsets.all(12),
              padding: const EdgeInsets.symmetric(vertical: 18, horizontal: 16),
              decoration: BoxDecoration(
                color: balanceColor.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: balanceColor.withValues(alpha: 0.3)),
              ),
              child: Column(
                children: [
                  if (party?.phone != null)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 6),
                      child: Text(
                        party!.phone!,
                        style: const TextStyle(fontSize: 15),
                      ),
                    ),
                  DigitText(
                    Money(balance.abs()).format(),
                    style: TextStyle(
                      fontSize: 30,
                      fontWeight: FontWeight.bold,
                      color: balanceColor,
                    ),
                  ),
                  Text(
                    balanceWord,
                    style: TextStyle(fontSize: 16, color: balanceColor),
                  ),
                ],
              ),
            ),
            Expanded(
              child:
                  _loading
                      ? const Center(child: CircularProgressIndicator())
                      : _error != null
                      ? Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Text(_error!, style: const TextStyle(fontSize: 16)),
                            const SizedBox(height: 12),
                            ElevatedButton(
                              onPressed: _load,
                              child: const Text('دوبارہ کوشش کریں'),
                            ),
                          ],
                        ),
                      )
                      : _entries.isEmpty
                      ? const SingleChildScrollView(
                        physics: AlwaysScrollableScrollPhysics(),
                        child: EmptyStateWidget(
                          message: 'ابھی کوئی لین دین نہیں',
                          subtitle: 'پہلا اندراج کرنے کے لیے نیچے بٹن دبائیں',
                          fallbackIcon: Icons.receipt_long_outlined,
                          imageAsset: 'assets/images/wheat.png',
                        ),
                      )
                      : ListView.builder(
                        itemCount: _entries.length,
                        itemBuilder: (context, i) => _entryTile(_entries[i]),
                      ),
            ),
          ],
        ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _showEntryDialog(context),
        icon: const Icon(Icons.add),
        label: const Text('اندراج کریں'),
      ),
    );
  }

  Widget _entryTile(PartyLedgerEntry entry) {
    final positive = entry.amountPaisa >= 0;
    final color = positive ? Colors.green.shade700 : Colors.red.shade700;
    final date = tryParseStoredDate(entry.date);
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: color.withValues(alpha: 0.12),
          child: Icon(
            positive ? Icons.arrow_downward : Icons.arrow_upward,
            color: color,
          ),
        ),
        title: Text(
          partyEntryTypeUrdu(entry.type),
          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (entry.note != null && entry.note!.isNotEmpty) Text(entry.note!),
            if (date != null)
              Text(
                urduShortDate(date),
                style: const TextStyle(fontSize: 12, color: Colors.black54),
              ),
          ],
        ),
        trailing: Text(
          '${positive ? '+' : '−'}${Money(entry.amountPaisa.abs()).format()}',
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.bold,
            color: color,
          ),
        ),
      ),
    );
  }

  void _showEditPartyDialog(
    BuildContext context,
    PartyProvider provider,
    Party party,
  ) {
    final nameCtrl = TextEditingController(text: party.name);
    final phoneCtrl = TextEditingController(text: party.phone ?? '');
    final notesCtrl = TextEditingController(text: party.notes ?? '');
    showDialog(
      context: context,
      builder:
          (ctx) => AlertDialog(
            title: const Text('پارٹی میں ترمیم'),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(
                    controller: nameCtrl,
                    decoration: const InputDecoration(
                      labelText: 'نام *',
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
                  const SizedBox(height: 12),
                  TextField(
                    controller: notesCtrl,
                    maxLines: 2,
                    decoration: const InputDecoration(
                      labelText: Strings.noteOptional,
                      border: OutlineInputBorder(),
                    ),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () async {
                  try {
                    await provider.deleteParty(party.id!);
                    if (ctx.mounted) Navigator.pop(ctx);
                    if (context.mounted) Navigator.pop(context);
                  } on PartyException catch (e) {
                    if (ctx.mounted) {
                      ScaffoldMessenger.of(
                        ctx,
                      ).showSnackBar(SnackBar(content: Text(e.message)));
                    }
                  }
                },
                child: const Text(
                  Strings.delete,
                  style: TextStyle(color: Colors.red),
                ),
              ),
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('منسوخ کریں'),
              ),
              ElevatedButton(
                onPressed: () async {
                  try {
                    await provider.updateParty(
                      Party(
                        id: party.id,
                        name: nameCtrl.text,
                        phone: phoneCtrl.text,
                        notes: notesCtrl.text,
                        createdAt: party.createdAt,
                      ),
                    );
                    if (ctx.mounted) Navigator.pop(ctx);
                  } on PartyException catch (e) {
                    if (ctx.mounted) {
                      ScaffoldMessenger.of(
                        ctx,
                      ).showSnackBar(SnackBar(content: Text(e.message)));
                    }
                  }
                },
                child: const Text(Strings.save),
              ),
            ],
          ),
    );
  }

  void _showEntryDialog(BuildContext context) {
    final provider = Provider.of<PartyProvider>(context, listen: false);
    var type = PartyEntryType.udhaarDiya;
    final amountCtrl = TextEditingController();
    final noteCtrl = TextEditingController();
    var date = DateTime.now();

    String fmtDate(DateTime d) =>
        '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

    showDialog(
      context: context,
      builder:
          (ctx) => StatefulBuilder(
            builder:
                (ctx, setDialogState) => AlertDialog(
                  title: const Text('نیا اندراج'),
                  content: SingleChildScrollView(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        RadioGroup<PartyEntryType>(
                          groupValue: type,
                          onChanged:
                              (v) => setDialogState(() => type = v ?? type),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              for (final t in PartyEntryType.values)
                                RadioListTile<PartyEntryType>(
                                  value: t,
                                  title: Text(
                                    partyEntryTypeUrdu(t),
                                    style: const TextStyle(
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                  subtitle: Text(
                                    partyEntryTypeHint(t),
                                    style: const TextStyle(fontSize: 12),
                                  ),
                                  dense: true,
                                  contentPadding: EdgeInsets.zero,
                                ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 8),
                        TextField(
                          controller: amountCtrl,
                          keyboardType: const TextInputType.numberWithOptions(
                            decimal: true,
                          ),
                          decoration: const InputDecoration(
                            labelText: 'رقم (روپے) *',
                            hintText: 'مثلاً 5000',
                            border: OutlineInputBorder(),
                          ),
                        ),
                        const SizedBox(height: 12),
                        InkWell(
                          onTap: () async {
                            final picked = await showDatePicker(
                              context: ctx,
                              initialDate: date,
                              firstDate: DateTime(2000),
                              lastDate: DateTime.now().add(
                                const Duration(days: 365),
                              ),
                            );
                            if (picked != null) {
                              setDialogState(() => date = picked);
                            }
                          },
                          child: InputDecorator(
                            decoration: const InputDecoration(
                              labelText: Strings.date,
                              border: OutlineInputBorder(),
                            ),
                            child: Text(urduDateLine(date)),
                          ),
                        ),
                        const SizedBox(height: 12),
                        TextField(
                          controller: noteCtrl,
                          maxLines: 2,
                          decoration: const InputDecoration(
                            labelText: Strings.noteOptional,
                            border: OutlineInputBorder(),
                          ),
                        ),
                      ],
                    ),
                  ),
                  actions: [
                    TextButton(
                      onPressed: () => Navigator.pop(ctx),
                      child: const Text('منسوخ کریں'),
                    ),
                    ElevatedButton(
                      onPressed: () async {
                        try {
                          final money = Money.parse(amountCtrl.text);
                          if (money.paisa <= 0) {
                            throw PartyException(
                              'رقم صفر سے زیادہ ہونی چاہیے۔',
                            );
                          }
                          await provider.addEntry(
                            partyId: widget.partyId,
                            type: type,
                            amountPaisa: money.paisa,
                            date: fmtDate(date),
                            note: noteCtrl.text,
                          );
                          if (ctx.mounted) Navigator.pop(ctx);
                          await _load();
                        } on MoneyParseException catch (e) {
                          if (ctx.mounted) {
                            ScaffoldMessenger.of(
                              ctx,
                            ).showSnackBar(SnackBar(content: Text(e.message)));
                          }
                        } on PartyException catch (e) {
                          if (ctx.mounted) {
                            ScaffoldMessenger.of(
                              ctx,
                            ).showSnackBar(SnackBar(content: Text(e.message)));
                          }
                        }
                      },
                      child: const Text(Strings.save),
                    ),
                  ],
                ),
          ),
    );
  }
}
