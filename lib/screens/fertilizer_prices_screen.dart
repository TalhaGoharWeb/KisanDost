import 'package:flutter/material.dart';

import '../data/fertilizer_data.dart';
import '../services/fertilizer_price_store.dart';
import '../services/quantity.dart';
import '../theme/app_theme.dart';

/// کھاد کی قیمتیں — the farmer's own per-bag prices for every
/// fertilizer, saved on the phone (SFRI-style price sheet). Khaad
/// Hisaab reads these for cost estimates and for ranking the
/// combinations cheapest first. Prices are the farmer's market
/// rates — the app ships none of its own and never claims a bazaar
/// price.
class FertilizerPricesScreen extends StatefulWidget {
  final FertilizerPriceStore store;

  const FertilizerPricesScreen({
    super.key,
    this.store = const FertilizerPriceStore(),
  });

  @override
  State<FertilizerPricesScreen> createState() => _FertilizerPricesScreenState();
}

class _FertilizerPricesScreenState extends State<FertilizerPricesScreen> {
  final Map<String, TextEditingController> _controllers = {};
  bool _loaded = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final prices = await widget.store.loadPrices();
    if (!mounted) return;
    setState(() {
      for (final product in kFertilizerProducts) {
        final paisa = prices[product.id];
        _controllers[product.id] = TextEditingController(
          text: paisa == null ? '' : (paisa / 100).round().toString(),
        );
      }
      _loaded = true;
    });
  }

  @override
  void dispose() {
    for (final c in _controllers.values) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _save() async {
    final prices = <String, int>{};
    for (final entry in _controllers.entries) {
      final text = entry.value.text.trim();
      if (text.isEmpty) continue;
      try {
        final rupees = Quantity.parsePositive(text);
        prices[entry.key] = (rupees * 100).round();
      } catch (_) {
        // Unparseable price: not saved — the field is simply skipped,
        // never stored as zero.
      }
    }
    await widget.store.savePrices(prices);
    if (mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('قیمتیں محفوظ ہو گئیں')));
      Navigator.pop(context, true);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'کھاد کی قیمتیں',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        backgroundColor: AppTheme.primaryColor,
        foregroundColor: Colors.white,
      ),
      body: !_loaded
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                Text(
                  'اپنے بازار کی فی بوری قیمت لکھیں۔ یہ قیمتیں آپ کے فون '
                  'میں محفوظ رہیں گی اور کھاد حساب کی لاگت و امتزاج کی '
                  'ترتیب انہی سے بنے گی۔ جب دام بدلیں، یہاں آ کر نئی '
                  'قیمت لکھ دیں۔',
                  style: TextStyle(fontSize: 14, color: Colors.grey.shade700),
                ),
                const SizedBox(height: 16),
                GridView.builder(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 2,
                    crossAxisSpacing: 12,
                    mainAxisSpacing: 12,
                    childAspectRatio: 1.9,
                  ),
                  itemCount: kFertilizerProducts.length,
                  itemBuilder: (context, i) {
                    final product = kFertilizerProducts[i];
                    return TextField(
                      controller: _controllers[product.id],
                      keyboardType: TextInputType.number,
                      decoration: InputDecoration(
                        labelText: '${product.nameUr} (روپے/بوری)',
                        border: const OutlineInputBorder(),
                      ),
                    );
                  },
                ),
                const SizedBox(height: 20),
                ElevatedButton.icon(
                  onPressed: _save,
                  icon: const Icon(Icons.save),
                  label: const Text(
                    'قیمتیں محفوظ کریں',
                    style: TextStyle(fontSize: 18),
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppTheme.primaryColor,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                  ),
                ),
              ],
            ),
    );
  }
}
