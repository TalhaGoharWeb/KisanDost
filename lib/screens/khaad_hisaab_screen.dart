import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../data/fertilizer_data.dart';
import '../models/fertilizer_plan.dart';
import '../providers/fertilizer_plan_provider.dart';
import '../providers/inventory_provider.dart';
import '../services/area_unit.dart';
import '../services/fertilizer_calculator.dart';
import '../services/money.dart';
import '../services/quantity.dart';
import '../services/unit_converter.dart';
import '../theme/app_theme.dart';

/// کھاد حساب — fertilizer calculator (Khaad Hisaab).
///
/// Workflow (Phase-3E): crop → area → recommendation or custom target →
/// choose products → prices → plan → stages → save. Works fully
/// offline; a plan is only a calculation — stock is deducted ONLY when
/// the farmer records an actual «کھاد ڈالی» activity (existing flow).
class KhaadHisaabScreen extends StatefulWidget {
  const KhaadHisaabScreen({super.key});

  @override
  State<KhaadHisaabScreen> createState() => _KhaadHisaabScreenState();
}

class _KhaadHisaabScreenState extends State<KhaadHisaabScreen> {
  // Selection: index into kCropRecommendations, or -1 for custom.
  int _recIndex = 0;
  String? _customCropName;

  final _areaController = TextEditingController(text: '1');
  AreaUnit _areaUnit = AreaUnit.acre;

  final _nController = TextEditingController();
  final _pController = TextEditingController();
  final _kController = TextEditingController();

  String _phosphorusId = 'dap';
  String _potashId = 'sop'; // 'none' allowed

  final Map<String, TextEditingController> _priceControllers = {};

  FertilizerPlanResult? _result;
  List<FertilizerPlanResult>? _comparison;
  String? _error;

  @override
  void dispose() {
    _areaController.dispose();
    _nController.dispose();
    _pController.dispose();
    _kController.dispose();
    for (final c in _priceControllers.values) {
      c.dispose();
    }
    super.dispose();
  }

  CropRecommendation? get _rec =>
      _recIndex >= 0 ? kCropRecommendations[_recIndex] : null;

  TextEditingController _priceFor(String productId) =>
      _priceControllers.putIfAbsent(productId, () => TextEditingController());

  String _fmt(double v) {
    final s = v.toStringAsFixed(1);
    return s.endsWith('.0') ? s.substring(0, s.length - 2) : s;
  }

  Nutrients? _target() {
    if (_rec != null) return _rec!.targetPerAcre;
    try {
      return Nutrients(
        n: Quantity.parse(_nController.text),
        p2o5: Quantity.parse(_pController.text),
        k2o: Quantity.parse(_kController.text),
      );
    } catch (_) {
      return null;
    }
  }

  void _calculate() {
    setState(() {
      _error = null;
      _result = null;
      _comparison = null;
    });
    final target = _target();
    if (target == null || (target.n <= 0 && target.p2o5 <= 0 && target.k2o <= 0)) {
      setState(() => _error = 'غذائی مقدار (نائٹروجن، فاسفورس، پوٹاش) درست لکھیں۔');
      return;
    }
    double areaAcres;
    try {
      areaAcres = AreaConverter.toAcres(
        Quantity.parsePositive(_areaController.text),
        _areaUnit,
      );
    } catch (_) {
      setState(() => _error = 'رقبہ درست لکھیں۔');
      return;
    }
    final potash =
        _potashId == 'none' ? null : productById(_potashId);
    try {
      final result = FertilizerCalculator.buildPlan(
        targetPerAcre: target,
        areaAcres: areaAcres,
        phosphorusSource: productById(_phosphorusId),
        nitrogenSource: productById('urea'),
        potashSource: potash,
      );
      // Compare all three phosphorus sources for the same target.
      final comparison = FertilizerCalculator.compareCombinations(
        targetPerAcre: target,
        areaAcres: areaAcres,
        phosphorusSources: [
          productById('dap'),
          productById('np'),
          productById('ssp'),
        ],
        nitrogenSource: productById('urea'),
        potashSource: potash,
      );
      setState(() {
        _result = result;
        _comparison = comparison;
      });
    } on ArgumentError catch (e) {
      setState(() => _error = e.message.toString());
    }
  }

  Map<String, int> _prices() {
    final prices = <String, int>{};
    for (final entry in _priceControllers.entries) {
      final text = entry.value.text.trim();
      if (text.isEmpty) continue;
      try {
        final rupees = Quantity.parsePositive(text);
        prices[entry.key] = (rupees * 100).round();
      } catch (_) {
        // Unparseable price: treated as unknown, never as zero.
      }
    }
    return prices;
  }

  /// Stock of a product in kg, matched tolerantly against the farmer's
  /// own inventory names (e.g. «یوریا», 'Urea', 'DAP'). Null = not stocked.
  double? _stockKg(BuildContext context, FertilizerProduct product) {
    final inventory = Provider.of<InventoryProvider>(
      context,
      listen: false,
    ).inventoryList;
    var totalKg = 0.0;
    var found = false;
    for (final item in inventory) {
      if (item.category != 'Fertilizer') continue;
      final name = item.name.toLowerCase();
      final matches =
          name.contains(product.nameUr) ||
          name.contains(product.id) ||
          (product.id == 'dap' && name.contains('ڈی اے پی')) ||
          (product.id == 'np' && name.contains('نائٹروفاس'));
      if (!matches) continue;
      try {
        totalKg += UnitConverter.convert(
          item.quantity,
          item.unit,
          'kg',
          weightPerUnitKg: item.weightPerUnitKg,
        );
        found = true;
      } catch (_) {
        // Unit cannot be converted safely (e.g. bags of unknown
        // weight) — skip rather than guess.
      }
    }
    return found ? totalKg : null;
  }

  Future<void> _savePlan() async {
    final result = _result;
    if (result == null) return;
    final prices = _prices();
    final plan = FertilizerPlan(
      cropName: _rec?.cropUr ?? _customCropName ?? 'اپنی فصل',
      variantName: _rec?.variantUr,
      areaAcres: result.areaAcres,
      targetNKg: result.targetPerAcre.n,
      targetPKg: result.targetPerAcre.p2o5,
      targetKKg: result.targetPerAcre.k2o,
      source: _rec?.sourceUr ?? 'کسان کی اپنی درج کردہ مقدار (مٹی ٹیسٹ / مشورہ)',
      isOfficial: _rec?.isOfficial ?? false,
      createdAt: DateTime.now().toIso8601String(),
      items: [
        for (final a in result.products)
          FertilizerPlanItem(
            productId: a.product.id,
            productName: a.product.nameUr,
            kgPerAcre: a.kgPerAcre,
            totalKg: a.totalKg(result.areaAcres),
            pricePerBagPaisa: prices[a.product.id],
          ),
      ],
    );
    await Provider.of<FertilizerPlanProvider>(
      context,
      listen: false,
    ).savePlan(plan);
    if (mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('منصوبہ محفوظ ہو گیا')));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'کھاد حساب',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        backgroundColor: AppTheme.primaryColor,
        foregroundColor: Colors.white,
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _buildCropSection(),
          const SizedBox(height: 16),
          _buildAreaSection(),
          const SizedBox(height: 16),
          _buildProductSection(),
          const SizedBox(height: 16),
          _buildPriceSection(),
          const SizedBox(height: 20),
          ElevatedButton.icon(
            onPressed: _calculate,
            icon: const Icon(Icons.calculate),
            label: const Text('حساب لگائیں', style: TextStyle(fontSize: 18)),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppTheme.primaryColor,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(vertical: 14),
            ),
          ),
          if (_error != null) ...[
            const SizedBox(height: 12),
            Text(
              _error!,
              style: const TextStyle(color: Colors.red, fontSize: 16),
              textAlign: TextAlign.center,
            ),
          ],
          if (_result != null) ...[
            const SizedBox(height: 20),
            _buildResultSection(_result!),
          ],
          const SizedBox(height: 24),
          _buildSavedPlans(),
        ],
      ),
    );
  }

  Widget _buildCropSection() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              '1۔ فصل منتخب کریں',
              style: TextStyle(fontSize: 19, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<int>(
              initialValue: _recIndex,
              isExpanded: true,
              decoration: const InputDecoration(
                labelText: 'فصل اور سفارش',
                border: OutlineInputBorder(),
              ),
              items: [
                for (var i = 0; i < kCropRecommendations.length; i++)
                  DropdownMenuItem(
                    value: i,
                    child: Text(
                      '${kCropRecommendations[i].cropUr} — ${kCropRecommendations[i].variantUr}',
                      style: const TextStyle(fontSize: 15),
                    ),
                  ),
                const DropdownMenuItem(
                  value: -1,
                  child: Text(
                    'اپنی مقدار خود لکھیں (مٹی ٹیسٹ / مشورے کے مطابق)',
                    style: TextStyle(fontSize: 15),
                  ),
                ),
              ],
              onChanged: (v) => setState(() {
                _recIndex = v ?? 0;
                _result = null;
              }),
            ),
            if (_rec != null) ...[
              const SizedBox(height: 10),
              Text(
                'مقدار فی ایکڑ: نائٹروجن ${_fmt(_rec!.targetPerAcre!.n)} کلو، '
                'فاسفورس ${_fmt(_rec!.targetPerAcre!.p2o5)} کلو، '
                'پوٹاش ${_fmt(_rec!.targetPerAcre!.k2o)} کلو',
                style: const TextStyle(fontSize: 15),
              ),
              const SizedBox(height: 6),
              Text(
                'ماخذ: ${_rec!.sourceUr}',
                style: TextStyle(fontSize: 13, color: Colors.grey.shade700),
              ),
            ] else ...[
              const SizedBox(height: 12),
              TextField(
                decoration: const InputDecoration(
                  labelText: 'فصل کا نام',
                  border: OutlineInputBorder(),
                ),
                onChanged: (v) => _customCropName = v,
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _nController,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(
                        labelText: 'نائٹروجن (کلو فی ایکڑ)',
                        border: OutlineInputBorder(),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: TextField(
                      controller: _pController,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(
                        labelText: 'فاسفورس (کلو فی ایکڑ)',
                        border: OutlineInputBorder(),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: TextField(
                      controller: _kController,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(
                        labelText: 'پوٹاش (کلو فی ایکڑ)',
                        border: OutlineInputBorder(),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                'ان فصلوں کی تصدیق شدہ سرکاری مقدار ابھی دستیاب نہیں: '
                '${kCropsWithoutVerifiedDose.join('، ')} — ان کے لیے مٹی ٹیسٹ یا '
                'محکمہ زراعت کے مقامی عملے کی مقدار یہاں لکھیں۔',
                style: TextStyle(fontSize: 13, color: Colors.grey.shade700),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildAreaSection() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              '2۔ رقبہ لکھیں',
              style: TextStyle(fontSize: 19, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  flex: 2,
                  child: TextField(
                    controller: _areaController,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(
                      labelText: 'رقبہ',
                      border: OutlineInputBorder(),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: DropdownButtonFormField<AreaUnit>(
                    initialValue: _areaUnit,
                    decoration: const InputDecoration(
                      labelText: 'اکائی',
                      border: OutlineInputBorder(),
                    ),
                    items: [
                      for (final u in AreaUnit.values)
                        DropdownMenuItem(value: u, child: Text(u.urduLabel)),
                    ],
                    onChanged: (v) => setState(() => _areaUnit = v ?? AreaUnit.acre),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildProductSection() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              '3۔ کھاد منتخب کریں',
              style: TextStyle(fontSize: 19, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            const Text('فاسفورس کے لیے:', style: TextStyle(fontSize: 16)),
            Wrap(
              spacing: 8,
              children: [
                for (final id in ['dap', 'np', 'ssp'])
                  ChoiceChip(
                    label: Text(productById(id).nameUr),
                    selected: _phosphorusId == id,
                    onSelected: (_) => setState(() => _phosphorusId = id),
                  ),
              ],
            ),
            const SizedBox(height: 8),
            const Text('پوٹاش کے لیے:', style: TextStyle(fontSize: 16)),
            Wrap(
              spacing: 8,
              children: [
                for (final id in ['sop', 'mop', 'none'])
                  ChoiceChip(
                    label: Text(id == 'none' ? 'پوٹاش نہیں' : productById(id).nameUr),
                    selected: _potashId == id,
                    onSelected: (_) => setState(() => _potashId = id),
                  ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              'نائٹروجن کی باقی مقدار یوریا سے پوری ہو گی۔ ڈی اے پی اور این پی '
              'میں موجود نائٹروجن پہلے گنی جائے گی — دوہرا حساب نہیں ہو گا۔',
              style: TextStyle(fontSize: 13, color: Colors.grey.shade700),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPriceSection() {
    final ids = <String>{_phosphorusId, 'urea', if (_potashId != 'none') _potashId};
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              '4۔ قیمتیں (اختیاری — فی بوری روپے)',
              style: TextStyle(fontSize: 19, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 12),
            for (final id in ids) ...[
              TextField(
                controller: _priceFor(id),
                keyboardType: TextInputType.number,
                decoration: InputDecoration(
                  labelText: '${productById(id).nameUr} — فی بوری قیمت (روپے)',
                  border: const OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 10),
            ],
            Text(
              'قیمت نہ لکھیں تو لاگت کا اندازہ نہیں لگے گا — اندازہ آپ کی لکھی '
              'قیمت پر ہے، بازار کا دعویٰ نہیں۔',
              style: TextStyle(fontSize: 13, color: Colors.grey.shade700),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildResultSection(FertilizerPlanResult result) {
    final prices = _prices();
    final cost = result.totalCostPaisa(prices);
    final areaAcres = result.areaAcres;
    return Card(
      color: Colors.green.shade50,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'نتیجہ — ${_fmt(areaAcres)} ایکڑ کے لیے',
              style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 4),
            Text(
              'فی کنال مقدار بھی ساتھ دی ہے (1 ایکڑ = 8 کنال)۔',
              style: TextStyle(fontSize: 13, color: Colors.grey.shade700),
            ),
            const Divider(),
            for (final a in result.products) ...[
              _productRow(context, a, areaAcres),
              const SizedBox(height: 6),
            ],
            const Divider(),
            Text(
              'ملنے والی غذائی مقدار فی ایکڑ: نائٹروجن '
              '${_fmt(result.suppliedPerAcre.n)} کلو، فاسفورس '
              '${_fmt(result.suppliedPerAcre.p2o5)} کلو، پوٹاش '
              '${_fmt(result.suppliedPerAcre.k2o)} کلو',
              style: const TextStyle(fontSize: 15),
            ),
            if (!result.remainingPerAcre.isNegligible()) ...[
              const SizedBox(height: 6),
              Text(
                'فرق: نائٹروجن ${_fmt(result.remainingPerAcre.n)}، فاسفورس '
                '${_fmt(result.remainingPerAcre.p2o5)}، پوٹاش '
                '${_fmt(result.remainingPerAcre.k2o)} کلو '
                '(منفی کا مطلب ہے ضرورت سے زیادہ)',
                style: const TextStyle(fontSize: 14, color: Colors.orange),
              ),
            ],
            if (cost > 0) ...[
              const SizedBox(height: 8),
              Text(
                'اندازاً کل لاگت: ${Money(cost).format()} '
                '(آپ کی لکھی قیمتوں پر، پوری/آدھی بوریوں کے حساب سے)',
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
            if (_comparison != null) _buildComparison(_comparison!, prices),
            if (_rec != null) _buildStages(_rec!, result),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: _savePlan,
                icon: const Icon(Icons.save),
                label: const Text('منصوبہ محفوظ کریں'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppTheme.primaryColor,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 12),
                ),
              ),
            ),
            const SizedBox(height: 6),
            Text(
              'نوٹ: منصوبہ صرف حساب ہے۔ اسٹاک سے کھاد تب ہی کٹے گی جب آپ '
              'اصل میں کھاد ڈال کر «کھاد ڈالی» کام درج کریں گے۔',
              style: TextStyle(fontSize: 13, color: Colors.grey.shade700),
            ),
          ],
        ),
      ),
    );
  }

  Widget _productRow(
    BuildContext context,
    ProductAmount a,
    double areaAcres,
  ) {
    final totalKg = a.totalKg(areaAcres);
    final bags = a.bagsFor(areaAcres);
    final stock = _stockKg(context, a.product);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '${a.product.nameUr}: ${_fmt(a.kgPerAcre)} کلو فی ایکڑ '
          '(${_fmt(a.kgPerAcre / 8)} کلو فی کنال)',
          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
        ),
        Text(
          'کل ضرورت: ${_fmt(totalKg)} کلو = ${_fmt(bags)} بوری '
          '(فی بوری ${_fmt(a.product.bagWeightKg)} کلو)',
          style: const TextStyle(fontSize: 15),
        ),
        if (stock != null)
          Text(
            stock >= totalKg
                ? 'گودام میں موجود: ${_fmt(stock)} کلو — کافی ہے'
                : 'گودام میں موجود: ${_fmt(stock)} کلو — '
                    '${_fmt(totalKg - stock)} کلو کم ہے',
            style: TextStyle(
              fontSize: 14,
              color: stock >= totalKg ? Colors.green.shade800 : Colors.red,
              fontWeight: FontWeight.bold,
            ),
          ),
      ],
    );
  }

  Widget _buildComparison(
    List<FertilizerPlanResult> comparison,
    Map<String, int> prices,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 12),
        const Text(
          'متبادل امتزاج کا موازنہ (ایک ہی مقصد کے لیے):',
          style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
        ),
        for (final plan in comparison) ...[
          const SizedBox(height: 6),
          Text(
            plan.products
                .map(
                  (a) =>
                      '${a.product.nameUr} ${_fmt(a.bagsFor(plan.areaAcres))} بوری',
                )
                .join(' + '),
            style: const TextStyle(fontSize: 14),
          ),
          Text(
            plan.totalCostPaisa(prices) > 0
                ? 'لاگت: ${Money(plan.totalCostPaisa(prices)).format()}'
                : 'لاگت: قیمت درکار ہے',
            style: TextStyle(fontSize: 13, color: Colors.grey.shade700),
          ),
        ],
        Text(
          'سب سے سستا ہمیشہ بہترین نہیں — اپنی زمین اور فصل کے لیے موزوں '
          'امتزاج چنیں۔',
          style: TextStyle(fontSize: 13, color: Colors.grey.shade700),
        ),
      ],
    );
  }

  Widget _buildStages(CropRecommendation rec, FertilizerPlanResult result) {
    // Map each product to its nutrient role for stage fractions.
    ProductAmount? pAmount, nAmount, kAmount;
    for (final a in result.products) {
      if (a.product.id == _phosphorusId) pAmount = a;
      if (a.product.id == 'urea') nAmount = a;
      if (a.product.id == _potashId) kAmount = a;
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 12),
        const Text(
          'کھاد کب ڈالیں (اقساط):',
          style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
        ),
        for (final stage in rec.stages) ...[
          const SizedBox(height: 8),
          Text(
            stage.nameUr,
            style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
          ),
          Text(stage.timingUr, style: const TextStyle(fontSize: 14)),
          if (pAmount != null && stage.phosphorusFraction > 0)
            Text(
              '• ${pAmount.product.nameUr}: '
              '${_fmt(pAmount.totalKg(result.areaAcres) * stage.phosphorusFraction)} کلو',
              style: const TextStyle(fontSize: 14),
            ),
          if (nAmount != null && stage.nitrogenFraction > 0)
            Text(
              '• ${nAmount.product.nameUr}: '
              '${_fmt(nAmount.totalKg(result.areaAcres) * stage.nitrogenFraction)} کلو',
              style: const TextStyle(fontSize: 14),
            ),
          if (kAmount != null && stage.potashFraction > 0)
            Text(
              '• ${kAmount.product.nameUr}: '
              '${_fmt(kAmount.totalKg(result.areaAcres) * stage.potashFraction)} کلو',
              style: const TextStyle(fontSize: 14),
            ),
        ],
      ],
    );
  }

  Widget _buildSavedPlans() {
    return Consumer<FertilizerPlanProvider>(
      builder: (context, provider, _) {
        if (provider.plans.isEmpty) return const SizedBox.shrink();
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'محفوظ شدہ منصوبے',
              style: TextStyle(fontSize: 19, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            for (final plan in provider.plans)
              Card(
                child: ListTile(
                  title: Text(
                    '${plan.cropName}'
                    '${plan.variantName != null ? ' — ${plan.variantName}' : ''}',
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                  subtitle: Text(
                    '${_fmt(plan.areaAcres)} ایکڑ • '
                    '${plan.items.map((i) => '${i.productName} ${_fmt(i.totalKg / 50)} بوری').join('، ')}\n'
                    'غذائی مقصد: نائٹروجن ${_fmt(plan.targetNKg)}، فاسفورس '
                    '${_fmt(plan.targetPKg)}، پوٹاش ${_fmt(plan.targetKKg)} کلو فی ایکڑ'
                    '${plan.estimatedCostPaisa > 0 ? '\nاندازاً لاگت: ${Money(plan.estimatedCostPaisa).format()}' : ''}',
                  ),
                  trailing: IconButton(
                    icon: const Icon(Icons.delete_outline, color: Colors.red),
                    onPressed: () async {
                      final ok = await showDialog<bool>(
                        context: context,
                        builder:
                            (ctx) => AlertDialog(
                              title: const Text('منصوبہ حذف کریں؟'),
                              content: const Text(
                                'یہ منصوبہ فہرست سے ہٹ جائے گا۔ (حذف شدہ '
                                'منصوبے تاریخ میں محفوظ رہتے ہیں۔)',
                              ),
                              actions: [
                                TextButton(
                                  onPressed: () => Navigator.pop(ctx, false),
                                  child: const Text('منسوخ کریں'),
                                ),
                                ElevatedButton(
                                  onPressed: () => Navigator.pop(ctx, true),
                                  child: const Text('حذف کریں'),
                                ),
                              ],
                            ),
                      );
                      if (ok == true && plan.id != null) {
                        await provider.deletePlan(plan.id!);
                      }
                    },
                  ),
                ),
              ),
          ],
        );
      },
    );
  }
}
