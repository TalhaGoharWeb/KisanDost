import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../widgets/digit_text.dart';
import '../models/party.dart';
import '../providers/party_provider.dart';
import '../services/money.dart';
import '../widgets/empty_state_widget.dart';
import 'party_detail_screen.dart';
import '../l10n/strings.dart';

class PartiesScreen extends StatefulWidget {
  const PartiesScreen({super.key});

  @override
  State<PartiesScreen> createState() => _PartiesScreenState();
}

class _PartiesScreenState extends State<PartiesScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<PartyProvider>().fetchParties();
    });
  }

  @override
  Widget build(BuildContext context) {
    final provider = Provider.of<PartyProvider>(context);
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(title: const Text('پارٹی کھاتہ (ادھار)')),
      body: RefreshIndicator(
        onRefresh: () => provider.fetchParties(),
        child: Column(
          children: [
            if (provider.parties.isNotEmpty) _buildTotalsHeader(provider),
            Expanded(
              child:
                  provider.errorMessage != null
                      ? _errorView(provider)
                      : provider.parties.isEmpty
                      ? _emptyView()
                      : ListView.builder(
                        itemCount: provider.parties.length,
                        itemBuilder: (context, i) {
                          final party = provider.parties[i];
                          return _partyTile(context, provider, party, theme);
                        },
                      ),
            ),
          ],
        ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _showPartyDialog(context),
        icon: const Icon(Icons.add),
        label: const Text('نئی پارٹی'),
      ),
    );
  }

  Widget _buildTotalsHeader(PartyProvider provider) {
    final receivable = provider.totalReceivablePaisa;
    final payable = provider.totalPayablePaisa;
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.all(12),
      padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 16),
      decoration: BoxDecoration(
        color: Theme.of(context).primaryColor.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              children: [
                const Text(
                  'لوگوں سے لینا ہے',
                  style: TextStyle(fontSize: 14, color: Colors.black54),
                ),
                const SizedBox(height: 4),
                DigitText(
                  Money(receivable).format(),
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: Colors.green.shade700,
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: Column(
              children: [
                const Text(
                  'لوگوں کو دینا ہے',
                  style: TextStyle(fontSize: 14, color: Colors.black54),
                ),
                const SizedBox(height: 4),
                DigitText(
                  Money(payable).format(),
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: Colors.red.shade700,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _errorView(PartyProvider provider) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              provider.errorMessage!,
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 16),
            ),
            const SizedBox(height: 12),
            ElevatedButton(
              onPressed: () => provider.fetchParties(),
              child: const Text('دوبارہ کوشش کریں'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _emptyView() {
    return SingleChildScrollView(
      physics: const AlwaysScrollableScrollPhysics(),
      child: SizedBox(
        height: MediaQuery.of(context).size.height * 0.7,
        child: const Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            EmptyStateWidget(
              message: 'کوئی پارٹی درج نہیں',
              subtitle: 'دکان دار، مزدور یا خریدار کا کھاتہ یہاں رکھیں',
              fallbackIcon: Icons.people_outline,
              imageAsset: 'assets/images/wheat.png',
            ),
          ],
        ),
      ),
    );
  }

  Widget _partyTile(
    BuildContext context,
    PartyProvider provider,
    Party party,
    ThemeData theme,
  ) {
    final balance = provider.balanceOf(party.id!);
    final Color balanceColor;
    final String balanceLabel;
    if (balance > 0) {
      balanceColor = Colors.green.shade700;
      balanceLabel = 'لینا ہے';
    } else if (balance < 0) {
      balanceColor = Colors.red.shade700;
      balanceLabel = 'دینا ہے';
    } else {
      balanceColor = Colors.grey.shade600;
      balanceLabel = 'حساب برابر';
    }
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: theme.primaryColor.withValues(alpha: 0.15),
          child: Text(
            party.name.isNotEmpty ? party.name.characters.first : '?',
            style: TextStyle(
              color: theme.primaryColor,
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
        title: Text(
          party.name,
          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 17),
        ),
        subtitle: party.phone != null ? Text(party.phone!) : null,
        trailing: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            DigitText(
              Money(balance.abs()).format(),
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
                color: balanceColor,
              ),
            ),
            Text(
              balanceLabel,
              style: TextStyle(fontSize: 12, color: balanceColor),
            ),
          ],
        ),
        onTap:
            () => Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => PartyDetailScreen(partyId: party.id!),
              ),
            ).then((_) => provider.fetchParties()),
      ),
    );
  }

  void _showPartyDialog(BuildContext context, [Party? existing]) {
    final provider = Provider.of<PartyProvider>(context, listen: false);
    final nameCtrl = TextEditingController(text: existing?.name ?? '');
    final phoneCtrl = TextEditingController(text: existing?.phone ?? '');
    final notesCtrl = TextEditingController(text: existing?.notes ?? '');
    showDialog(
      context: context,
      builder:
          (ctx) => AlertDialog(
            title: Text(existing == null ? 'نئی پارٹی' : 'پارٹی میں ترمیم'),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(
                    controller: nameCtrl,
                    decoration: const InputDecoration(
                      labelText: 'نام *',
                      hintText: 'مثلاً علی دکان دار',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: phoneCtrl,
                    keyboardType: TextInputType.phone,
                    decoration: const InputDecoration(
                      labelText: 'فون نمبر (اختیاری)',
                      hintText: 'مثلاً 03001234567',
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
              if (existing != null)
                TextButton(
                  onPressed: () async {
                    try {
                      await provider.deleteParty(existing.id!);
                      if (ctx.mounted) Navigator.pop(ctx);
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
                    if (existing == null) {
                      await provider.addParty(
                        Party(
                          name: nameCtrl.text,
                          phone: phoneCtrl.text,
                          notes: notesCtrl.text,
                          createdAt: DateTime.now().toIso8601String(),
                        ),
                      );
                    } else {
                      await provider.updateParty(
                        Party(
                          id: existing.id,
                          name: nameCtrl.text,
                          phone: phoneCtrl.text,
                          notes: notesCtrl.text,
                          createdAt: existing.createdAt,
                        ),
                      );
                    }
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
}
