import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../data/fertilizer_data.dart';
import '../models/fertilizer_plan.dart';
import '../providers/fertilizer_plan_provider.dart';
import '../providers/inventory_provider.dart';
import '../services/area_unit.dart';
import '../services/fertilizer_calculator.dart';
import '../services/fertilizer_price_store.dart';
import 'fertilizer_prices_screen.dart';
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

  // Soil-test (SFRI formula) mode: _recIndex == -2.
  int _soilCropIndex = 0;
  final _omController = TextEditingController();
  final _soilPController = TextEditingController();
  final _soilKController = TextEditingController();

  String _phosphorusId = 'dap';
  String _nitrogenId = 'urea';
  String _potashId = 'sop'; // 'none' allowed

  final FertilizerPriceStore _priceStore = const FertilizerPriceStore();
  Map<String, int> _savedPrices = {};

  FertilizerPlanResult? _result;
  List<FertilizerCombination>? _combinations;
  String? _error;

  final _budgetController = TextEditingController();
  List<BudgetPlanOption>? _budgetOptions;
  String? _budgetNote;

  @override
  void initState() {
    super.initState();
    _loadPrices();
  }

  Future<void> _loadPrices() async {
    final prices = await _priceStore.loadPrices();
    if (mounted) setState(() => _savedPrices = prices);
  }

  Future<void> _openPrices() async {
    final saved = await Navigator.push<bool>(
      context,
      MaterialPageRoute(builder: (_) => const FertilizerPricesScreen()),
    );
    if (saved == true) {
      await _loadPrices();
      if (_result != null) _calculate();
    }
  }

  @override
  void dispose() {
    _areaController.dispose();
    _nController.dispose();
    _pController.dispose();
    _kController.dispose();
    _budgetController.dispose();
    _omController.dispose();
    _soilPController.dispose();
    _soilKController.dispose();
    super.dispose();
  }

  CropRecommendation? get _rec =>
      _recIndex >= 0 ? kCropRecommendations[_recIndex] : null;

  String _fmt(double v) {
    final s = v.toStringAsFixed(1);
    return s.endsWith('.0') ? s.substring(0, s.length - 2) : s;
  }

  bool get _soilMode => _recIndex == -2;

  List<FertilizerStage>? _activeStages() {
    if (_rec != null) return _rec!.stages;
    if (_soilMode) return kSfriSoilTestCrops[_soilCropIndex].stages;
    return null;
  }

  Nutrients? _target() {
    if (_rec != null) return _rec!.targetPerAcre;
    if (_soilMode) {
      try {
        return sfriSoilTestTarget(
          kSfriSoilTestCrops[_soilCropIndex].id,
          organicMatterPct: Quantity.parse(_omController.text),
          phosphorusPpm: Quantity.parse(_soilPController.text),
          potassiumPpm: Quantity.parse(_soilKController.text),
        );
      } catch (_) {
        return null;
      }
    }
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
      _combinations = null;
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
        nitrogenSource: productById(_nitrogenId),
        potashSource: potash,
      );
      // The full combination grid (phosphorus × nitrogen × potash),
      // ranked cheapest first wherever prices are known.
      final combinations = FertilizerCalculator.rankByCost(
        FertilizerCalculator.allCombinations(
          targetPerAcre: target,
          areaAcres: areaAcres,
          phosphorusSources: [
            for (final id in kPhosphorusSourceIds) productById(id),
          ],
          nitrogenSources: [
            for (final id in kNitrogenSourceIds) productById(id),
          ],
          potashOptions: target.k2o > 0
              ? [for (final id in kPotashSourceIds) productById(id)]
              : [null],
        ),
        _prices(),
      );
      setState(() {
        _result = result;
        _combinations = combinations;
      });
    } on ArgumentError catch (e) {
      setState(() => _error = e.message.toString());
    }
  }

  /// The farmer's saved per-bag prices (paisa), from the prices
  /// screen. Products without a saved price stay unknown — never 0.
  Map<String, int> _prices() => _savedPrices;

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
      cropName: _soilMode
          ? kSfriSoilTestCrops[_soilCropIndex].cropUr
          : (_rec?.cropUr ?? _customCropName ?? 'اپنی فصل'),
      variantName: _soilMode ? 'مٹی ٹیسٹ (SFRI فارمولا)' : _rec?.variantUr,
      areaAcres: result.areaAcres,
      targetNKg: result.targetPerAcre.n,
      targetPKg: result.targetPerAcre.p2o5,
      targetKKg: result.targetPerAcre.k2o,
      source: _soilMode
          ? 'SFRI فارمولا — مٹی کے تجزیے (نامیاتی مادہ، فاسفورس، پوٹاش) سے حسابی مقدار'
          : (_rec?.sourceUr ?? 'کسان کی اپنی درج کردہ مقدار (مشورہ)'),
      isOfficial: _soilMode || (_rec?.isOfficial ?? false),
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
        actions: [
          IconButton(
            icon: const Icon(Icons.sell_outlined),
            tooltip: 'کھاد کی قیمتیں',
            onPressed: _openPrices,
          ),
        ],
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
          const SizedBox(height: 16),
          _buildBudgetSection(),
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
                  value: -2,
                  child: Text(
                    'مٹی کے ٹیسٹ کے مطابق (SFRI فارمولا)',
                    style: TextStyle(fontSize: 15),
                  ),
                ),
                const DropdownMenuItem(
                  value: -1,
                  child: Text(
                    'اپنی مقدار خود لکھیں (مشورے کے مطابق)',
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
              if (kMicroNoteByCrop[_rec!.cropUr] != null) ...[
                const SizedBox(height: 6),
                Text(
                  kMicroNoteByCrop[_rec!.cropUr]!,
                  style: TextStyle(fontSize: 13, color: Colors.grey.shade700),
                ),
              ],
            ] else if (_soilMode) ...[
              const SizedBox(height: 12),
              const Text('فصل:', style: TextStyle(fontSize: 16)),
              Wrap(
                spacing: 8,
                children: [
                  for (var i = 0; i < kSfriSoilTestCrops.length; i++)
                    ChoiceChip(
                      label: Text(kSfriSoilTestCrops[i].cropUr),
                      selected: _soilCropIndex == i,
                      onSelected: (_) => setState(() {
                        _soilCropIndex = i;
                        _result = null;
                      }),
                    ),
                ],
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _omController,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(
                        labelText: 'نامیاتی مادہ (فیصد)',
                        border: OutlineInputBorder(),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: TextField(
                      controller: _soilPController,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(
                        labelText: 'فاسفورس (ppm)',
                        border: OutlineInputBorder(),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: TextField(
                      controller: _soilKController,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(
                        labelText: 'پوٹاش (ppm)',
                        border: OutlineInputBorder(),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                'یہ تینوں اعداد آپ کی مٹی کے تجزیے کی رپورٹ میں ہوتے '
                'ہیں۔ مقدار SFRI (محکمہ زراعت پنجاب) کے شائع شدہ '
                'فارمولے سے بنے گی۔',
                style: TextStyle(fontSize: 13, color: Colors.grey.shade700),
              ),
              if (kMicroNoteByCrop[kSfriSoilTestCrops[_soilCropIndex].cropUr] !=
                  null) ...[
                const SizedBox(height: 6),
                Text(
                  kMicroNoteByCrop[
                      kSfriSoilTestCrops[_soilCropIndex].cropUr]!,
                  style: TextStyle(fontSize: 13, color: Colors.grey.shade700),
                ),
              ],
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
              if (kCropsWithoutVerifiedDose.isNotEmpty) ...[
                const SizedBox(height: 8),
                Text(
                  'ان فصلوں کی تصدیق شدہ سرکاری مقدار ابھی دستیاب نہیں: '
                  '${kCropsWithoutVerifiedDose.join('، ')} — ان کے لیے مٹی ٹیسٹ یا '
                  'محکمہ زراعت کے مقامی عملے کی مقدار یہاں لکھیں۔',
                  style: TextStyle(fontSize: 13, color: Colors.grey.shade700),
                ),
              ],
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
                for (final id in kPhosphorusSourceIds)
                  ChoiceChip(
                    label: Text(productById(id).nameUr),
                    selected: _phosphorusId == id,
                    onSelected: (_) => setState(() => _phosphorusId = id),
                  ),
              ],
            ),
            const SizedBox(height: 8),
            const Text('نائٹروجن کے لیے:', style: TextStyle(fontSize: 16)),
            Wrap(
              spacing: 8,
              children: [
                for (final id in kNitrogenSourceIds)
                  ChoiceChip(
                    label: Text(productById(id).nameUr),
                    selected: _nitrogenId == id,
                    onSelected: (_) => setState(() => _nitrogenId = id),
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
              'ڈی اے پی، این پی اور MAP میں موجود نائٹروجن پہلے گنی جائے '
              'گی، باقی مقدار منتخب نائٹروجن کھاد سے پوری ہو گی — دوہرا '
              'حساب نہیں ہو گا۔',
              style: TextStyle(fontSize: 13, color: Colors.grey.shade700),
            ),
          ],
        ),
      ),
    );
  }

  void _calculateBudget() {
    final target = _target();
    if (target == null || (target.n <= 0 && target.p2o5 <= 0 && target.k2o <= 0)) {
      setState(() => _budgetNote = 'پہلے فصل اور غذائی مقدار درست منتخب کریں۔');
      return;
    }
    double areaAcres;
    int budgetPaisa;
    try {
      areaAcres = AreaConverter.toAcres(
        Quantity.parsePositive(_areaController.text),
        _areaUnit,
      );
      budgetPaisa = (Quantity.parsePositive(_budgetController.text) * 100).round();
    } catch (_) {
      setState(() => _budgetNote = 'رقبہ اور بجٹ درست لکھیں۔');
      return;
    }
    if (_savedPrices.isEmpty) {
      setState(
        () => _budgetNote =
            'بجٹ حساب کے لیے پہلے کھاد کی قیمتیں درج کریں (اوپر قیمتوں والا حصہ)۔',
      );
      return;
    }
    final grid = FertilizerCalculator.allCombinations(
      targetPerAcre: target,
      areaAcres: areaAcres,
      phosphorusSources: [
        for (final id in kPhosphorusSourceIds) productById(id),
      ],
      nitrogenSources: [for (final id in kNitrogenSourceIds) productById(id)],
      potashOptions: target.k2o > 0
          ? [for (final id in kPotashSourceIds) productById(id)]
          : [null],
    );
    final options = FertilizerCalculator.fitCombinationsToBudget(
      targetPerAcre: target,
      areaAcres: areaAcres,
      combinations: grid,
      pricePerBagPaisaById: _savedPrices,
      budgetPaisa: budgetPaisa,
    );
    setState(() {
      _budgetOptions = options;
      if (options.isEmpty) {
        // Cheapest fully-priced full plan, for an honest explanation.
        var cheapest = -1;
        for (final c in grid) {
          final priced = c.result.products.every(
            (a) => _savedPrices.containsKey(a.product.id),
          );
          if (!priced) continue;
          final cost = c.result.totalCostPaisa(_savedPrices);
          if (cheapest < 0 || cost < cheapest) cheapest = cost;
        }
        _budgetNote = cheapest > 0
            ? 'اس بجٹ میں کوئی مناسب امتزاج نہیں آتا۔ سب سے سستے مکمل '
                  'منصوبے کی لاگت ${Money(cheapest).format()} ہے — بجٹ '
                  'بڑھائیں یا کم مقدار کا منصوبہ خود منتخب کریں۔'
            : 'اس بجٹ میں کوئی امتزاج نہیں آتا۔';
      } else {
        _budgetNote = null;
      }
    });
  }

  void _applyBudgetOption(BudgetPlanOption option) {
    setState(() {
      _phosphorusId = option.combination.phosphorusSource.id;
      _nitrogenId = option.combination.nitrogenSource.id;
      _potashId = option.combination.potashSource?.id ?? 'none';
      _result = option.result;
      _error = null;
    });
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('بجٹ والا منصوبہ اوپر منتخب ہو گیا — چاہیں تو محفوظ کر لیں')),
    );
  }

  Widget _buildBudgetSection() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              '5۔ بجٹ کے مطابق منصوبہ (اختیاری)',
              style: TextStyle(fontSize: 19, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            Text(
              'آپ کل کتنے پیسے خرچ کر سکتے ہیں؟ ہم اس بجٹ کے اندر '
              'بہترین متوازن کھاد کا حساب لگائیں گے — پہلے وہ امتزاج '
              'جن کی مکمل مقدار بجٹ میں آتی ہے، پھر سب سے بڑا متوازن '
              'کم منصوبہ۔',
              style: TextStyle(fontSize: 14, color: Colors.grey.shade700),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _budgetController,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(
                      labelText: 'بجٹ (روپے — کل رقبے کے لیے)',
                      border: OutlineInputBorder(),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                ElevatedButton(
                  onPressed: _calculateBudget,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppTheme.primaryColor,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 14,
                    ),
                  ),
                  child: const Text('بجٹ میں دکھائیں'),
                ),
              ],
            ),
            if (_budgetNote != null) ...[
              const SizedBox(height: 10),
              Text(
                _budgetNote!,
                style: const TextStyle(fontSize: 14, color: Colors.orange),
              ),
            ],
            if (_budgetOptions != null && _budgetOptions!.isNotEmpty) ...[
              const SizedBox(height: 12),
              Text(
                'بجٹ کے اندر بہترین امتزاج (${_budgetOptions!.length}):',
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                ),
              ),
              for (final option in _budgetOptions!) ...[
                const SizedBox(height: 6),
                InkWell(
                  onTap: () => _applyBudgetOption(option),
                  child: Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      border: Border.all(color: Colors.grey.shade300),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          option.combination.labelUr,
                          style: const TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        Text(
                          option.scale >= 0.999
                              ? 'مکمل مقدار — بجٹ کے اندر'
                              : 'متوازن کم مقدار — ضرورت کا '
                                    '${(option.scale * 100).round()} فیصد',
                          style: TextStyle(
                            fontSize: 13,
                            color: option.scale >= 0.999
                                ? Colors.green.shade800
                                : Colors.orange.shade800,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        Text(
                          option.result.products
                              .map(
                                (a) =>
                                    '${a.product.nameUr}: '
                                    '${_fmt(a.totalKg(option.result.areaAcres))} کلو '
                                    '= ${_fmt(a.bagsFor(option.result.areaAcres))} بوری',
                              )
                              .join('\n'),
                          style: const TextStyle(fontSize: 14),
                        ),
                        if (option.scale < 0.999)
                          Text(
                            'ملنے والی غذائی مقدار فی ایکڑ: نائٹروجن '
                            '${_fmt(option.result.suppliedPerAcre.n)}، فاسفورس '
                            '${_fmt(option.result.suppliedPerAcre.p2o5)}، پوٹاش '
                            '${_fmt(option.result.suppliedPerAcre.k2o)} کلو',
                            style: const TextStyle(fontSize: 13),
                          ),
                        Text(
                          'لاگت: ${Money(option.costPaisa).format()}',
                          style: const TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        Text(
                          'منتخب کرنے کے لیے ہاتھ رکھیں۔',
                          style: TextStyle(
                            fontSize: 12,
                            color: Colors.grey.shade700,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildPriceSection() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              '4۔ قیمتیں (فی بوری — آپ کے بازار کی)',
              style: TextStyle(fontSize: 19, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 10),
            for (final product in kFertilizerProducts)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 2),
                child: Text(
                  '${product.nameUr}: '
                  '${_savedPrices[product.id] != null ? Money(_savedPrices[product.id]!).format() : 'درج نہیں'}',
                  style: const TextStyle(fontSize: 15),
                ),
              ),
            const SizedBox(height: 10),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: _openPrices,
                icon: const Icon(Icons.edit),
                label: const Text('قیمتیں لکھیں / بدلیں'),
              ),
            ),
            const SizedBox(height: 6),
            Text(
              'قیمتیں فون میں محفوظ رہتی ہیں۔ جس کھاد کی قیمت درج نہ ہو، '
              'اس والے امتزاج کی لاگت نہیں لگے گی — اندازہ آپ کی لکھی '
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
            if (_combinations != null) _buildCombinations(_combinations!, prices),
            if (_activeStages() != null) _buildStages(_activeStages()!, result),
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

  bool _isSelectedCombo(FertilizerCombination combo) =>
      combo.phosphorusSource.id == _phosphorusId &&
      combo.nitrogenSource.id == _nitrogenId &&
      (combo.potashSource?.id ?? 'none') == _potashId;

  /// Plain-words check of whether a plan fulfils the crop's need,
  /// and if not, exactly what is short or extra (per acre).
  String _fulfillmentText(FertilizerPlanResult result) {
    final r = result.remainingPerAcre;
    if (r.isNegligible()) {
      return '✓ یہ امتزاج فصل کی پوری غذائی ضرورت پوری کرتا ہے '
          '(نائٹروجن ${_fmt(result.targetPerAcre.n)}، فاسفورس '
          '${_fmt(result.targetPerAcre.p2o5)}، پوٹاش '
          '${_fmt(result.targetPerAcre.k2o)} کلو فی ایکڑ)';
    }
    final parts = <String>[];
    void add(String name, double v) {
      if (v > 0.05) parts.add('$name ${_fmt(v)} کلو فی ایکڑ کم');
      if (v < -0.05) parts.add('$name ${_fmt(-v)} کلو فی ایکڑ زیادہ');
    }

    add('نائٹروجن', r.n);
    add('فاسفورس', r.p2o5);
    add('پوٹاش', r.k2o);
    return 'فرق: ${parts.join('، ')}';
  }

  String _comboCostText(
    FertilizerCombination combo,
    Map<String, int> prices,
  ) {
    final allPriced = combo.result.products.every(
      (a) => prices.containsKey(a.product.id),
    );
    if (!allPriced) return 'لاگت: قیمت درکار ہے';
    return 'لاگت: ${Money(combo.result.totalCostPaisa(prices)).format()}';
  }

  Widget _buildCombinations(
    List<FertilizerCombination> combinations,
    Map<String, int> prices,
  ) {
    final anyPriced = combinations.any(
      (c) => c.result.products.every((a) => prices.containsKey(a.product.id)),
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 12),
        Text(
          'تمام امتزاج (${combinations.length})'
          '${anyPriced ? ' — سستے سے مہنگے ترتیب میں' : ''}:',
          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 4),
        Text(
          'کسی امتزاج پر ہاتھ رکھیں تو اسی کا تفصیلی منصوبہ اوپر بن '
          'جائے گا۔',
          style: TextStyle(fontSize: 13, color: Colors.grey.shade700),
        ),
        for (final combo in combinations) ...[
          const SizedBox(height: 6),
          InkWell(
            onTap: () {
              setState(() {
                _phosphorusId = combo.phosphorusSource.id;
                _nitrogenId = combo.nitrogenSource.id;
                _potashId = combo.potashSource?.id ?? 'none';
              });
              _calculate();
            },
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                border: Border.all(
                  color: _isSelectedCombo(combo)
                      ? AppTheme.primaryColor
                      : Colors.grey.shade300,
                  width: _isSelectedCombo(combo) ? 2 : 1,
                ),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    combo.labelUr + (_isSelectedCombo(combo) ? ' ✓' : ''),
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  Text(
                    combo.result.products
                        .map(
                          (a) =>
                              '${a.product.nameUr}: '
                              '${_fmt(a.totalKg(combo.result.areaAcres))} کلو '
                              '= ${_fmt(a.bagsFor(combo.result.areaAcres))} بوری',
                        )
                        .join('\n'),
                    style: const TextStyle(fontSize: 14),
                  ),
                  Text(
                    _fulfillmentText(combo.result),
                    style: TextStyle(
                      fontSize: 13,
                      color: combo.result.remainingPerAcre.isNegligible()
                          ? Colors.green.shade800
                          : Colors.orange.shade800,
                    ),
                  ),
                  Text(
                    _comboCostText(combo, prices),
                    style: TextStyle(fontSize: 13, color: Colors.grey.shade700),
                  ),
                ],
              ),
            ),
          ),
        ],
        const SizedBox(height: 6),
        Text(
          'سب سے سستا ہمیشہ بہترین نہیں — اپنی زمین اور فصل کے لیے موزوں '
          'امتزاج چنیں۔',
          style: TextStyle(fontSize: 13, color: Colors.grey.shade700),
        ),
      ],
    );
  }

  Widget _buildStages(List<FertilizerStage> stages, FertilizerPlanResult result) {
    // Map each product to its nutrient role for stage fractions.
    ProductAmount? pAmount, nAmount, kAmount;
    for (final a in result.products) {
      if (a.product.id == _phosphorusId) pAmount = a;
      if (a.product.id == _nitrogenId) nAmount = a;
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
        for (final stage in stages) ...[
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
                    '${plan.items.map((i) => '${i.productName} ${_fmt(i.totalKg)} کلو (${_fmt(i.totalKg / 50)} بوری)').join('، ')}\n'
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
