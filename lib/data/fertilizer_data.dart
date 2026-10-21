import '../services/fertilizer_calculator.dart';

/// Fertilizer reference data for Khaad Hisaab.
///
/// DATA HONESTY RULES (owner's Phase-6 requirement):
/// * Product compositions are manufacturer specifications (cited per
///   product) and stay EDITABLE in the app — grades vary by brand.
/// * Crop recommendations are seeded ONLY where a source was actually
///   verified during the 2026-10-21 research pass. Every entry carries
///   its source label and an [isOfficial] flag. Crops without a
///   verified dose are still listed — the farmer can enter a custom
///   nutrient target from a soil test or extension advice.
/// * Nothing here is invented. See
///   `files/khaad-hisaab/05-agricultural-data-plan.md` for the full
///   verification trail and the gaps still open.

/// Standard products sold in Pakistan. Compositions verified
/// 2026-10-21: Urea 46-0-0 (universal grade); DAP 18-46-0 (Engro
/// Fertilizers official brand page); NP/Nitrophos 23-23-0 (FFC grade —
/// Engro NP is sold as 22:20 / 20:20 / 18:18, which is why every
/// composition remains editable); SSP 18% P2O5 (standard grade);
/// SOP 50% K2O (FFC SOP, +18% sulphur); MOP 60% K2O (standard grade);
/// CAN/Gawara 26-0-0 (Sarsabz CAN, Fatima Fertilizer spec: 26% total
/// N); ammonium sulphate 21-0-0 (standard grade, +24% sulphur);
/// MAP 11-52-0 (granular basal grade; the water-soluble grade sold
/// for fertigation is 12-61-0 — compositions stay editable);
/// TSP 0-46-0 (triple superphosphate, manufacturer standard grade).
const List<FertilizerProduct> kFertilizerProducts = [
  FertilizerProduct(id: 'urea', nameUr: 'یوریا', nPct: 46),
  FertilizerProduct(id: 'dap', nameUr: 'ڈی اے پی', nPct: 18, p2o5Pct: 46),
  FertilizerProduct(id: 'np', nameUr: 'این پی (نائٹروفاس)', nPct: 23, p2o5Pct: 23),
  FertilizerProduct(id: 'ssp', nameUr: 'ایس ایس پی', p2o5Pct: 18),
  FertilizerProduct(id: 'map', nameUr: 'مونو امونیم فاسفیٹ (MAP)', nPct: 11, p2o5Pct: 52),
  FertilizerProduct(id: 'npk', nameUr: 'NPK 17-17-17', nPct: 17, p2o5Pct: 17, k2oPct: 17),
  FertilizerProduct(id: 'tsp', nameUr: 'ٹرپل سپر فاسفیٹ (TSP)', p2o5Pct: 46),
  FertilizerProduct(id: 'can', nameUr: 'گوارا (CAN)', nPct: 26),
  FertilizerProduct(id: 'amsul', nameUr: 'امونیم سلفیٹ', nPct: 21),
  FertilizerProduct(id: 'sop', nameUr: 'ایس او پی (پوٹاش)', k2oPct: 50),
  FertilizerProduct(id: 'mop', nameUr: 'ایم او پی (پوٹاش)', k2oPct: 60),
];

/// Product roles for the combination grid — every phosphorus source
/// combines with every nitrogen source and every potash source
/// (6 × 3 × 2 = 36 combinations), mirroring the SFRI کھاد حساب list
/// (their phosphorus slot also offers NPK 17-17-17).
const List<String> kPhosphorusSourceIds = ['dap', 'np', 'ssp', 'map', 'tsp', 'npk'];
const List<String> kNitrogenSourceIds = ['urea', 'can', 'amsul'];
const List<String> kPotashSourceIds = ['sop', 'mop'];

FertilizerProduct productById(String id) =>
    kFertilizerProducts.firstWhere((p) => p.id == id);

/// One application stage of a recommendation. Fractions are of the
/// plan's total for each nutrient ROLE (phosphorus product, nitrogen
/// product, potash product) — they survive product substitution.
class FertilizerStage {
  final String nameUr;
  final String timingUr;
  final double phosphorusFraction;
  final double nitrogenFraction;
  final double potashFraction;

  const FertilizerStage({
    required this.nameUr,
    required this.timingUr,
    this.phosphorusFraction = 0,
    this.nitrogenFraction = 0,
    this.potashFraction = 0,
  });
}

/// A crop nutrient recommendation (per acre) with provenance.
class CropRecommendation {
  final String cropUr;
  final String variantUr;

  /// Target nutrients per acre (kg). Null = no verified dose — the
  /// farmer enters a custom target instead.
  final Nutrients? targetPerAcre;

  final List<FertilizerStage> stages;

  /// Human-readable source, shown in the app next to the numbers.
  final String sourceUr;

  /// True only for Agriculture Department Punjab recommendations.
  final bool isOfficial;

  const CropRecommendation({
    required this.cropUr,
    required this.variantUr,
    required this.targetPerAcre,
    required this.stages,
    required this.sourceUr,
    required this.isOfficial,
  });
}

const _wheatIrrigatedStages = [
  FertilizerStage(
    nameUr: 'کاشت کے وقت',
    timingUr: 'تمام فاسفورس اور پوٹاش + نائٹروجن کا ایک تہائی، ڈرل کے ساتھ',
    phosphorusFraction: 1,
    nitrogenFraction: 1 / 3,
    potashFraction: 1,
  ),
  FertilizerStage(
    nameUr: 'پہلا پانی',
    timingUr: 'کاشت کے تقریباً 25 سے 30 دن بعد — نائٹروجن کی دوسری قسط',
    nitrogenFraction: 1 / 3,
  ),
  FertilizerStage(
    nameUr: 'دوسرا پانی',
    timingUr: 'نائٹروجن کی آخری قسط',
    nitrogenFraction: 1 / 3,
  ),
];

const _allAtSowing = [
  FertilizerStage(
    nameUr: 'زمین کی تیاری / کاشت کے وقت',
    timingUr: 'ساری کھاد کاشت سے پہلے یا ڈرل کے ساتھ ایک ہی بار',
    phosphorusFraction: 1,
    nitrogenFraction: 1,
    potashFraction: 1,
  ),
];

/// Generic split pattern (own wording, department-style): all
/// phosphorus and potash at sowing, nitrogen in three splits.
const _genericSplits = [
  FertilizerStage(
    nameUr: 'کاشت کے وقت',
    timingUr: 'تمام فاسفورس اور پوٹاش + نائٹروجن کا ایک تہائی',
    phosphorusFraction: 1,
    nitrogenFraction: 1 / 3,
    potashFraction: 1,
  ),
  FertilizerStage(
    nameUr: '30 دن بعد',
    timingUr: 'نائٹروجن کی دوسری قسط',
    nitrogenFraction: 1 / 3,
  ),
  FertilizerStage(
    nameUr: 'پھول آنے پر',
    timingUr: 'نائٹروجن کی آخری قسط',
    nitrogenFraction: 1 / 3,
  ),
];

const _riceStagesGeneric = [
  FertilizerStage(
    nameUr: 'پنیری لگاتے وقت',
    timingUr: 'تمام فاسفورس اور پوٹاش + نائٹروجن کا 10 فیصد',
    phosphorusFraction: 1,
    nitrogenFraction: 0.1,
    potashFraction: 1,
  ),
  FertilizerStage(
    nameUr: '30 دن بعد',
    timingUr: 'نائٹروجن کی دوسری قسط',
    nitrogenFraction: 0.45,
  ),
  FertilizerStage(
    nameUr: '50 سے 60 دن بعد',
    timingUr: 'نائٹروجن کی آخری قسط',
    nitrogenFraction: 0.45,
  ),
];

const _sugarcaneStagesGeneric = [
  FertilizerStage(
    nameUr: 'کاشت کے وقت',
    timingUr: 'تمام فاسفورس + آدھی پوٹاش + نائٹروجن کا ایک تہائی',
    phosphorusFraction: 1,
    nitrogenFraction: 1 / 3,
    potashFraction: 0.5,
  ),
  FertilizerStage(
    nameUr: '60 دن بعد',
    timingUr: 'نائٹروجن کی دوسری قسط',
    nitrogenFraction: 1 / 3,
  ),
  FertilizerStage(
    nameUr: '90 سے 120 دن بعد',
    timingUr: 'نائٹروجن کی آخری قسط + باقی آدھی پوٹاش',
    nitrogenFraction: 1 / 3,
    potashFraction: 0.5,
  ),
];

/// Source label for every SFRI-derived recommendation below.
const _sfriSource =
    'SFRI (ادارہ تحقیق زرخیزیِ زمین، محکمہ زراعت پنجاب) — کھاد حساب '
    'ماڈل، درمیانی زرخیز زمین کے لیے۔ مٹی کے ٹیسٹ سے اصل ضرورت کم '
    'یا زیادہ ہو سکتی ہے';

const _microZnB =
    'خورد غذائی اجزا (SFRI رہنمائی): مٹی میں کمی ہو تو زنک سلفیٹ '
    '(33 فیصد) 6 کلو فی ایکڑ اور بوریکس تقریباً 4.5 کلو فی ایکڑ';

/// Micronutrient guidance by crop (SFRI-derived): zinc sulphate
/// 33% at 3x the element dose, borax at 9x (their published
/// conversion factors). Shown as a note only — never costed.
const Map<String, String> kMicroNoteByCrop = {
  'گندم': _microZnB,
  'چاول (دھان)': _microZnB,
  'مکئی': _microZnB,
  'کپاس': _microZnB,
  'ٹماٹر': _microZnB,
  'آلو':
      'خورد غذائی اجزا (SFRI رہنمائی): مٹی میں کمی ہو تو زنک سلفیٹ '
      '(33 فیصد) 12 کلو فی ایکڑ اور بوریکس تقریباً 4.5 کلو فی ایکڑ',
  'کھیرا':
      'خورد غذائی اجزا (SFRI رہنمائی): مٹی میں کمی ہو تو زنک سلفیٹ '
      '(33 فیصد) 6 کلو فی ایکڑ',
};

/// Seeded recommendations with verified sources (2026-10-21 pass):
/// * Wheat (irrigated + 3 barani zones) and rice, maize, cotton,
///   sugarcane nutrient doses — Agriculture Department Punjab,
///   Pocket Book 2022 (soil-average basis: "اوسط زرخیزی والی زمین"),
///   cross-checked against the department's Oct 2026 barani press
///   release (bag doses convert exactly to the barani entries below)
///   and SFRI's Fertilizer Recommendation Model ranges.
/// * Stage splits follow the department's published pattern (all P/K
///   basal, nitrogen in splits) — general guidance, labelled as such.
/// Doses vary with soil-test values (SFRI FRM: wheat N ranges
/// 46–69 kg/acre by soil N) — the app says so and offers custom
/// targets. Nothing here is invented; gaps are listed in the data plan.
const List<CropRecommendation> kCropRecommendations = [
  CropRecommendation(
    cropUr: 'گندم',
    variantUr: 'آبپاشی علاقہ — اوسط زرخیز زمین',
    targetPerAcre: Nutrients(n: 57, p2o5: 46, k2o: 25),
    stages: _wheatIrrigatedStages,
    sourceUr:
        'محکمہ زراعت پنجاب (پاکٹ بک 2022) — اوسط زرخیزی والی زمین کے لیے غذائی سفارش۔ مٹی کے ٹیسٹ سے مقدار کم یا زیادہ ہو سکتی ہے',
    isOfficial: true,
  ),
  CropRecommendation(
    cropUr: 'گندم',
    variantUr: 'بارانی — کم بارش والا علاقہ',
    targetPerAcre: Nutrients(n: 32, p2o5: 23, k2o: 12.5),
    stages: _allAtSowing,
    sourceUr:
        'محکمہ زراعت پنجاب، اعلامیہ 14 اکتوبر 2026 (1 بوری ڈی اے پی + 1 بوری یوریا + آدھی بوری پوٹاش فی ایکڑ)',
    isOfficial: true,
  ),
  CropRecommendation(
    cropUr: 'گندم',
    variantUr: 'بارانی — درمیانی بارش (چکوال، تلہ گنگ، پنڈ دادن خان)',
    targetPerAcre: Nutrients(n: 40, p2o5: 28.75, k2o: 12.5),
    stages: _allAtSowing,
    sourceUr:
        'محکمہ زراعت پنجاب، اعلامیہ 14 اکتوبر 2026 (سوا بوری ڈی اے پی + سوا بوری یوریا + آدھی بوری پوٹاش فی ایکڑ)',
    isOfficial: true,
  ),
  CropRecommendation(
    cropUr: 'گندم',
    variantUr: 'بارانی — زیادہ بارش والا علاقہ',
    targetPerAcre: Nutrients(n: 48, p2o5: 34.5, k2o: 12.5),
    stages: _allAtSowing,
    sourceUr:
        'محکمہ زراعت پنجاب، اعلامیہ 14 اکتوبر 2026 (ڈیڑھ بوری ڈی اے پی + ڈیڑھ بوری یوریا + آدھی بوری پوٹاش فی ایکڑ)',
    isOfficial: true,
  ),
  CropRecommendation(
    cropUr: 'چاول (دھان)',
    variantUr: 'موٹا چاول — آبپاشی، اوسط زرخیز زمین',
    targetPerAcre: Nutrients(n: 55, p2o5: 35, k2o: 25),
    stages: [
      FertilizerStage(
        nameUr: 'پنیری لگاتے وقت',
        timingUr: 'تمام فاسفورس اور پوٹاش + نائٹروجن کا 10 فیصد',
        phosphorusFraction: 1,
        nitrogenFraction: 0.1,
        potashFraction: 1,
      ),
      FertilizerStage(
        nameUr: '30 دن بعد',
        timingUr: 'نائٹروجن کی دوسری قسط',
        nitrogenFraction: 0.45,
      ),
      FertilizerStage(
        nameUr: '50 سے 60 دن بعد',
        timingUr: 'خوشہ نکلنے پر نائٹروجن کی آخری قسط',
        nitrogenFraction: 0.45,
      ),
    ],
    sourceUr:
        'محکمہ زراعت پنجاب (پاکٹ بک 2022) — اوسط زرخیزی والی زمین کے لیے غذائی سفارش۔ اقساط کی تقسیم عمومی رہنمائی ہے',
    isOfficial: true,
  ),
  CropRecommendation(
    cropUr: 'مکئی',
    variantUr: 'ہائبرڈ — بہار کی کاشت، اوسط زرخیز زمین',
    targetPerAcre: Nutrients(n: 92, p2o5: 58, k2o: 25),
    stages: [
      FertilizerStage(
        nameUr: 'کاشت کے وقت',
        timingUr: 'تمام فاسفورس اور پوٹاش + نائٹروجن کا ایک تہائی',
        phosphorusFraction: 1,
        nitrogenFraction: 1 / 3,
        potashFraction: 1,
      ),
      FertilizerStage(
        nameUr: '25 سے 30 دن بعد',
        timingUr: 'گھٹنے تک اونچائی پر نائٹروجن کی دوسری قسط',
        nitrogenFraction: 1 / 3,
      ),
      FertilizerStage(
        nameUr: '45 سے 50 دن بعد',
        timingUr: 'نائٹروجن کی آخری قسط',
        nitrogenFraction: 1 / 3,
      ),
    ],
    sourceUr:
        'محکمہ زراعت پنجاب (پاکٹ بک 2022) — اوسط زرخیزی والی زمین کے لیے غذائی سفارش۔ اقساط کی تقسیم عمومی رہنمائی ہے',
    isOfficial: true,
  ),
  CropRecommendation(
    cropUr: 'کپاس',
    variantUr: 'بی ٹی کپاس — آبپاشی، اوسط زرخیز زمین',
    targetPerAcre: Nutrients(n: 63, p2o5: 31, k2o: 25),
    stages: [
      FertilizerStage(
        nameUr: 'کاشت کے وقت',
        timingUr: 'تمام فاسفورس اور پوٹاش + نائٹروجن کا ایک تہائی',
        phosphorusFraction: 1,
        nitrogenFraction: 1 / 3,
        potashFraction: 1,
      ),
      FertilizerStage(
        nameUr: 'پہلا پھول آنے پر',
        timingUr: 'کاشت کے تقریباً 45 دن بعد نائٹروجن کی دوسری قسط',
        nitrogenFraction: 1 / 3,
      ),
      FertilizerStage(
        nameUr: 'پھول عروج پر',
        timingUr: 'نائٹروجن کی آخری قسط',
        nitrogenFraction: 1 / 3,
      ),
    ],
    sourceUr:
        'محکمہ زراعت پنجاب (پاکٹ بک 2022) — اوسط زرخیزی والی زمین کے لیے غذائی سفارش۔ اقساط کی تقسیم عمومی رہنمائی ہے',
    isOfficial: true,
  ),
  CropRecommendation(
    cropUr: 'گنا',
    variantUr: 'فروری کی کاشت، اوسط زرخیز زمین',
    targetPerAcre: Nutrients(n: 92, p2o5: 46, k2o: 50),
    stages: [
      FertilizerStage(
        nameUr: 'کاشت کے وقت',
        timingUr: 'تمام فاسفورس + آدھی پوٹاش + نائٹروجن کا ایک تہائی',
        phosphorusFraction: 1,
        nitrogenFraction: 1 / 3,
        potashFraction: 0.5,
      ),
      FertilizerStage(
        nameUr: '60 دن بعد',
        timingUr: 'جھاڑ بننے پر نائٹروجن کی دوسری قسط',
        nitrogenFraction: 1 / 3,
      ),
      FertilizerStage(
        nameUr: '90 سے 120 دن بعد',
        timingUr: 'نائٹروجن کی آخری قسط + باقی آدھی پوٹاش',
        nitrogenFraction: 1 / 3,
        potashFraction: 0.5,
      ),
    ],
    sourceUr:
        'اوسط زرخیز زمین کے لیے عام پیداواری رہنمائی (زمین کی زرخیزی کے درجوں والی جدول: کمزور زمین 120-69-50، اوسط 92-46-50، زرخیز 69-23-25 کلو فی ایکڑ) — پاکٹ بک کی سرکاری جدول سے براہِ راست تصدیق باقی ہے',
    isOfficial: false,
  ),
  // ---- SFRI fixed doses (medium-fertility soil), extracted and
  // cross-checked 2026-10-21 from the official SFRI کھاد حساب model
  // (see 05-agricultural-data-plan.md). Values are kg/acre. ----
  CropRecommendation(
    cropUr: 'چاول (دھان)',
    variantUr: 'باسمتی — SFRI، درمیانی زرخیز زمین',
    targetPerAcre: Nutrients(n: 55, p2o5: 36, k2o: 25),
    stages: _riceStagesGeneric,
    sourceUr: _sfriSource,
    isOfficial: true,
  ),
  CropRecommendation(
    cropUr: 'چاول (دھان)',
    variantUr: 'موٹا چاول — SFRI، درمیانی زرخیز زمین',
    targetPerAcre: Nutrients(n: 69, p2o5: 41, k2o: 32),
    stages: _riceStagesGeneric,
    sourceUr: _sfriSource,
    isOfficial: true,
  ),
  CropRecommendation(
    cropUr: 'مکئی',
    variantUr: 'بارانی — SFRI',
    targetPerAcre: Nutrients(n: 46, p2o5: 34, k2o: 25),
    stages: _genericSplits,
    sourceUr: _sfriSource,
    isOfficial: true,
  ),
  CropRecommendation(
    cropUr: 'مکئی',
    variantUr: 'چارہ — SFRI',
    targetPerAcre: Nutrients(n: 43, p2o5: 23, k2o: 12.5),
    stages: _genericSplits,
    sourceUr: _sfriSource,
    isOfficial: true,
  ),
  CropRecommendation(
    cropUr: 'مکئی',
    variantUr: 'غیر ہائبرڈ — SFRI',
    targetPerAcre: Nutrients(n: 80, p2o5: 46, k2o: 37),
    stages: _genericSplits,
    sourceUr: _sfriSource,
    isOfficial: true,
  ),
  CropRecommendation(
    cropUr: 'کپاس',
    variantUr: 'بی ٹی، مرکزی علاقہ — SFRI',
    targetPerAcre: Nutrients(n: 90, p2o5: 35, k2o: 38),
    stages: _genericSplits,
    sourceUr: _sfriSource,
    isOfficial: true,
  ),
  CropRecommendation(
    cropUr: 'کپاس',
    variantUr: 'بی ٹی، ثانوی علاقہ — SFRI',
    targetPerAcre: Nutrients(n: 80, p2o5: 35, k2o: 30),
    stages: _genericSplits,
    sourceUr: _sfriSource,
    isOfficial: true,
  ),
  CropRecommendation(
    cropUr: 'کپاس',
    variantUr: 'دیسی، مرکزی علاقہ — SFRI',
    targetPerAcre: Nutrients(n: 69, p2o5: 35, k2o: 25),
    stages: _genericSplits,
    sourceUr: _sfriSource,
    isOfficial: true,
  ),
  CropRecommendation(
    cropUr: 'کپاس',
    variantUr: 'دیسی، ثانوی علاقہ — SFRI',
    targetPerAcre: Nutrients(n: 58, p2o5: 35, k2o: 25),
    stages: _genericSplits,
    sourceUr: _sfriSource,
    isOfficial: true,
  ),
  CropRecommendation(
    cropUr: 'گنا',
    variantUr: 'بہار کی فصل — SFRI',
    targetPerAcre: Nutrients(n: 103, p2o5: 57, k2o: 50),
    stages: _sugarcaneStagesGeneric,
    sourceUr: _sfriSource,
    isOfficial: true,
  ),
  CropRecommendation(
    cropUr: 'گنا',
    variantUr: 'مونڈھی فصل — SFRI',
    targetPerAcre: Nutrients(n: 134, p2o5: 57, k2o: 50),
    stages: _sugarcaneStagesGeneric,
    sourceUr: _sfriSource,
    isOfficial: true,
  ),
  CropRecommendation(
    cropUr: 'آلو',
    variantUr: 'SFRI، درمیانی زرخیز زمین',
    targetPerAcre: Nutrients(n: 100, p2o5: 50, k2o: 50),
    stages: _genericSplits,
    sourceUr: _sfriSource,
    isOfficial: true,
  ),
  CropRecommendation(
    cropUr: 'سورج مکھی',
    variantUr: 'SFRI، درمیانی زرخیز زمین',
    targetPerAcre: Nutrients(n: 48, p2o5: 34, k2o: 25),
    stages: _genericSplits,
    sourceUr: _sfriSource,
    isOfficial: true,
  ),
  CropRecommendation(
    cropUr: 'تل',
    variantUr: 'SFRI، درمیانی زرخیز زمین',
    targetPerAcre: Nutrients(n: 34, p2o5: 24, k2o: 12),
    stages: _genericSplits,
    sourceUr: _sfriSource,
    isOfficial: true,
  ),
  CropRecommendation(
    cropUr: 'دال ماش',
    variantUr: 'SFRI، درمیانی زرخیز زمین',
    targetPerAcre: Nutrients(n: 9, p2o5: 23, k2o: 12),
    stages: _allAtSowing,
    sourceUr: _sfriSource,
    isOfficial: true,
  ),
  CropRecommendation(
    cropUr: 'دال مونگ',
    variantUr: 'SFRI، درمیانی زرخیز زمین',
    targetPerAcre: Nutrients(n: 9, p2o5: 23, k2o: 12),
    stages: _allAtSowing,
    sourceUr: _sfriSource,
    isOfficial: true,
  ),
  CropRecommendation(
    cropUr: 'دال مسور',
    variantUr: 'SFRI، درمیانی زرخیز زمین',
    targetPerAcre: Nutrients(n: 13, p2o5: 23, k2o: 12),
    stages: _allAtSowing,
    sourceUr: _sfriSource,
    isOfficial: true,
  ),
  CropRecommendation(
    cropUr: 'مونگ پھلی',
    variantUr: 'SFRI، درمیانی زرخیز زمین',
    targetPerAcre: Nutrients(n: 8, p2o5: 24, k2o: 8),
    stages: _allAtSowing,
    sourceUr: _sfriSource,
    isOfficial: true,
  ),
  CropRecommendation(
    cropUr: 'چنا',
    variantUr: 'SFRI، درمیانی زرخیز زمین',
    targetPerAcre: Nutrients(n: 13, p2o5: 34, k2o: 12),
    stages: _allAtSowing,
    sourceUr: _sfriSource,
    isOfficial: true,
  ),
  CropRecommendation(
    cropUr: 'لہسن',
    variantUr: 'SFRI، درمیانی زرخیز زمین',
    targetPerAcre: Nutrients(n: 64, p2o5: 46, k2o: 25),
    stages: _genericSplits,
    sourceUr: _sfriSource,
    isOfficial: true,
  ),
  CropRecommendation(
    cropUr: 'پیاز',
    variantUr: 'SFRI، درمیانی زرخیز زمین',
    targetPerAcre: Nutrients(n: 50, p2o5: 35, k2o: 35),
    stages: _genericSplits,
    sourceUr: _sfriSource,
    isOfficial: true,
  ),
  CropRecommendation(
    cropUr: 'ٹماٹر',
    variantUr: 'غیر ہائبرڈ — SFRI',
    targetPerAcre: Nutrients(n: 58, p2o5: 23, k2o: 32),
    stages: _genericSplits,
    sourceUr: _sfriSource,
    isOfficial: true,
  ),
  CropRecommendation(
    cropUr: 'ٹماٹر',
    variantUr: 'ہائبرڈ — SFRI',
    targetPerAcre: Nutrients(n: 90, p2o5: 46, k2o: 100),
    stages: _genericSplits,
    sourceUr: _sfriSource,
    isOfficial: true,
  ),
  CropRecommendation(
    cropUr: 'مرچ',
    variantUr: 'SFRI، درمیانی زرخیز زمین',
    targetPerAcre: Nutrients(n: 58, p2o5: 23, k2o: 25),
    stages: _genericSplits,
    sourceUr: _sfriSource,
    isOfficial: true,
  ),
  CropRecommendation(
    cropUr: 'برسیم',
    variantUr: 'SFRI، درمیانی زرخیز زمین',
    targetPerAcre: Nutrients(n: 13, p2o5: 35, k2o: 0),
    stages: _allAtSowing,
    sourceUr: _sfriSource,
    isOfficial: true,
  ),
  CropRecommendation(
    cropUr: 'لوسن',
    variantUr: 'SFRI، درمیانی زرخیز زمین',
    targetPerAcre: Nutrients(n: 23, p2o5: 35, k2o: 0),
    stages: _allAtSowing,
    sourceUr: _sfriSource,
    isOfficial: true,
  ),
  CropRecommendation(
    cropUr: 'جوار (چارہ)',
    variantUr: 'SFRI، درمیانی زرخیز زمین',
    targetPerAcre: Nutrients(n: 32, p2o5: 23, k2o: 12),
    stages: _genericSplits,
    sourceUr: _sfriSource,
    isOfficial: true,
  ),
  CropRecommendation(
    cropUr: 'سدا بہار چارہ',
    variantUr: 'SFRI، درمیانی زرخیز زمین',
    targetPerAcre: Nutrients(n: 20, p2o5: 23, k2o: 12),
    stages: _allAtSowing,
    sourceUr: _sfriSource,
    isOfficial: true,
  ),
  CropRecommendation(
    cropUr: 'باجرا',
    variantUr: 'ایک کٹ والا چارہ — SFRI',
    targetPerAcre: Nutrients(n: 32, p2o5: 23, k2o: 12),
    stages: _genericSplits,
    sourceUr: _sfriSource,
    isOfficial: true,
  ),
  CropRecommendation(
    cropUr: 'باجرا',
    variantUr: 'زیادہ کٹ والا چارہ — SFRI',
    targetPerAcre: Nutrients(n: 20, p2o5: 23, k2o: 12),
    stages: _allAtSowing,
    sourceUr: _sfriSource,
    isOfficial: true,
  ),
  CropRecommendation(
    cropUr: 'گوار (پھلی)',
    variantUr: 'SFRI، درمیانی زرخیز زمین',
    targetPerAcre: Nutrients(n: 32, p2o5: 23, k2o: 0),
    stages: _genericSplits,
    sourceUr: _sfriSource,
    isOfficial: true,
  ),
  CropRecommendation(
    cropUr: 'جئی',
    variantUr: 'SFRI، درمیانی زرخیز زمین',
    targetPerAcre: Nutrients(n: 60, p2o5: 36, k2o: 25),
    stages: _genericSplits,
    sourceUr: _sfriSource,
    isOfficial: true,
  ),
  CropRecommendation(
    cropUr: 'لوبیا',
    variantUr: 'SFRI، درمیانی زرخیز زمین',
    targetPerAcre: Nutrients(n: 9, p2o5: 23, k2o: 0),
    stages: _allAtSowing,
    sourceUr: _sfriSource,
    isOfficial: true,
  ),
  CropRecommendation(
    cropUr: 'موڈ گھاس',
    variantUr: 'SFRI، درمیانی زرخیز زمین',
    targetPerAcre: Nutrients(n: 20, p2o5: 23, k2o: 25),
    stages: _allAtSowing,
    sourceUr: _sfriSource,
    isOfficial: true,
  ),
  CropRecommendation(
    cropUr: 'روڈس گھاس',
    variantUr: 'SFRI، درمیانی زرخیز زمین',
    targetPerAcre: Nutrients(n: 20, p2o5: 23, k2o: 25),
    stages: _allAtSowing,
    sourceUr: _sfriSource,
    isOfficial: true,
  ),
  CropRecommendation(
    cropUr: 'جنتر',
    variantUr: 'SFRI، درمیانی زرخیز زمین',
    targetPerAcre: Nutrients(n: 20, p2o5: 23, k2o: 0),
    stages: _allAtSowing,
    sourceUr: _sfriSource,
    isOfficial: true,
  ),
  CropRecommendation(
    cropUr: 'کلر گھاس',
    variantUr: 'SFRI، درمیانی زرخیز زمین',
    targetPerAcre: Nutrients(n: 20, p2o5: 23, k2o: 12),
    stages: _allAtSowing,
    sourceUr: _sfriSource,
    isOfficial: true,
  ),
  CropRecommendation(
    cropUr: 'روان (لوبیا)',
    variantUr: 'SFRI، درمیانی زرخیز زمین',
    targetPerAcre: Nutrients(n: 9, p2o5: 23, k2o: 0),
    stages: _allAtSowing,
    sourceUr: _sfriSource,
    isOfficial: true,
  ),
  CropRecommendation(
    cropUr: 'کریلا',
    variantUr: 'SFRI، درمیانی زرخیز زمین',
    targetPerAcre: Nutrients(n: 45, p2o5: 40, k2o: 25),
    stages: _genericSplits,
    sourceUr: _sfriSource,
    isOfficial: true,
  ),
  CropRecommendation(
    cropUr: 'گیا کدو',
    variantUr: 'SFRI، درمیانی زرخیز زمین',
    targetPerAcre: Nutrients(n: 53, p2o5: 35, k2o: 25),
    stages: _genericSplits,
    sourceUr: _sfriSource,
    isOfficial: true,
  ),
  CropRecommendation(
    cropUr: 'کھیرا',
    variantUr: 'SFRI، درمیانی زرخیز زمین',
    targetPerAcre: Nutrients(n: 36, p2o5: 35, k2o: 25),
    stages: _genericSplits,
    sourceUr: _sfriSource,
    isOfficial: true,
  ),
  CropRecommendation(
    cropUr: 'خربوزہ',
    variantUr: 'SFRI، درمیانی زرخیز زمین',
    targetPerAcre: Nutrients(n: 55, p2o5: 23, k2o: 25),
    stages: _genericSplits,
    sourceUr: _sfriSource,
    isOfficial: true,
  ),
  CropRecommendation(
    cropUr: 'تربوز',
    variantUr: 'SFRI، درمیانی زرخیز زمین',
    targetPerAcre: Nutrients(n: 64, p2o5: 46, k2o: 50),
    stages: _genericSplits,
    sourceUr: _sfriSource,
    isOfficial: true,
  ),
  CropRecommendation(
    cropUr: 'ٹنڈا',
    variantUr: 'SFRI، درمیانی زرخیز زمین',
    targetPerAcre: Nutrients(n: 60, p2o5: 35, k2o: 25),
    stages: _genericSplits,
    sourceUr: _sfriSource,
    isOfficial: true,
  ),
  CropRecommendation(
    cropUr: 'بینگن',
    variantUr: 'SFRI، درمیانی زرخیز زمین',
    targetPerAcre: Nutrients(n: 59, p2o5: 36, k2o: 0),
    stages: _genericSplits,
    sourceUr: _sfriSource,
    isOfficial: true,
  ),
  CropRecommendation(
    cropUr: 'بھنڈی',
    variantUr: 'SFRI، درمیانی زرخیز زمین',
    targetPerAcre: Nutrients(n: 26, p2o5: 35, k2o: 25),
    stages: _genericSplits,
    sourceUr: _sfriSource,
    isOfficial: true,
  ),
  CropRecommendation(
    cropUr: 'ہلدی',
    variantUr: 'SFRI، درمیانی زرخیز زمین',
    targetPerAcre: Nutrients(n: 120, p2o5: 50, k2o: 80),
    stages: _genericSplits,
    sourceUr: _sfriSource,
    isOfficial: true,
  ),
  CropRecommendation(
    cropUr: 'ٹوریا',
    variantUr: 'SFRI، درمیانی زرخیز زمین',
    targetPerAcre: Nutrients(n: 23, p2o5: 23, k2o: 12),
    stages: _genericSplits,
    sourceUr: _sfriSource,
    isOfficial: true,
  ),
  CropRecommendation(
    cropUr: 'تارامیرا',
    variantUr: 'SFRI، درمیانی زرخیز زمین',
    targetPerAcre: Nutrients(n: 12, p2o5: 12, k2o: 12),
    stages: _allAtSowing,
    sourceUr: _sfriSource,
    isOfficial: true,
  ),
  CropRecommendation(
    cropUr: 'سرسوں / کینولا',
    variantUr: 'AARI اقسام — SFRI',
    targetPerAcre: Nutrients(n: 35, p2o5: 30, k2o: 12),
    stages: _genericSplits,
    sourceUr: _sfriSource,
    isOfficial: true,
  ),
  CropRecommendation(
    cropUr: 'کینولا',
    variantUr: 'ہائبرڈ — SFRI',
    targetPerAcre: Nutrients(n: 35, p2o5: 35, k2o: 25),
    stages: _genericSplits,
    sourceUr: _sfriSource,
    isOfficial: true,
  ),
  CropRecommendation(
    cropUr: 'السی',
    variantUr: 'SFRI، درمیانی زرخیز زمین',
    targetPerAcre: Nutrients(n: 23, p2o5: 23, k2o: 12),
    stages: _allAtSowing,
    sourceUr: _sfriSource,
    isOfficial: true,
  ),
  CropRecommendation(
    cropUr: 'چکوال رایا / سرسوں',
    variantUr: 'SFRI، درمیانی زرخیز زمین',
    targetPerAcre: Nutrients(n: 34, p2o5: 23, k2o: 12),
    stages: _genericSplits,
    sourceUr: _sfriSource,
    isOfficial: true,
  ),
];


/// (All major crops now carry a verified dose — Pocket Book or
/// SFRI — so this list is empty. The custom-target mode remains for
/// any other crop and for a farmer's own soil-test figures.)
const List<String> kCropsWithoutVerifiedDose = [];

/// One crop of the SFRI soil-test model (FRM).
class SfriSoilTestCrop {
  final String id;
  final String cropUr;
  final List<FertilizerStage> stages;

  const SfriSoilTestCrop({
    required this.id,
    required this.cropUr,
    required this.stages,
  });
}

/// The five crops for which SFRI publishes soil-test formulas.
/// Inputs: organic matter (%), available phosphorus (ppm) and
/// available potassium (ppm) from the farmer's soil-test report.
const List<SfriSoilTestCrop> kSfriSoilTestCrops = [
  SfriSoilTestCrop(id: 'wheat', cropUr: 'گندم', stages: _wheatIrrigatedStages),
  SfriSoilTestCrop(id: 'rice', cropUr: 'چاول (دھان)', stages: _riceStagesGeneric),
  SfriSoilTestCrop(id: 'maize', cropUr: 'مکئی', stages: _genericSplits),
  SfriSoilTestCrop(id: 'cotton', cropUr: 'کپاس', stages: _genericSplits),
  SfriSoilTestCrop(id: 'sugarcane', cropUr: 'گنا', stages: _sugarcaneStagesGeneric),
];

double _frmClamp(double v) => v < 0 ? 0 : v;

/// SFRI Fertilizer Recommendation Model: nutrient dose (kg/acre)
/// from soil-test values. Formulas transcribed from the published
/// SFRI model (کھاد حساب app, extracted 2026-10-21) — see the data
/// plan for the full transcription and cross-checks. Outputs are
/// clamped at zero: a very rich soil needs none of a nutrient.
Nutrients sfriSoilTestTarget(
  String cropId, {
  required double organicMatterPct,
  required double phosphorusPpm,
  required double potassiumPpm,
}) {
  final om = organicMatterPct;
  final p = phosphorusPpm;
  final k = potassiumPpm;
  switch (cropId) {
    case 'wheat':
      final kDose = k < 75
          ? 24.0
          : (k < 180 ? (-0.23 * k) + 41.73 : 0.0);
      return Nutrients(
        n: _frmClamp(((om * -24.9) + 69.8) * 2.5 / 2.47),
        p2o5: _frmClamp(((p * -1.18) + 46.5) * 2.5 / 2.47),
        k2o: _frmClamp(kDose),
      );
    case 'cotton':
      final pCapped = p > 18 ? 18.0 : p;
      return Nutrients(
        n: _frmClamp(((0.5 - om) * 40) + 104),
        p2o5: _frmClamp(((8 - pCapped) * 2.2) + 34.56),
        k2o: _frmClamp((k * -0.16) + 60.8),
      );
    case 'maize':
      return Nutrients(
        n: _frmClamp(((0.44 - om) * 50) + 123.6),
        p2o5: _frmClamp(((5 - p) * 2) + 83.2),
        k2o: _frmClamp(((136 - k) * 0.14) + 46.8),
      );
    case 'rice':
      return Nutrients(
        n: _frmClamp(((1.5 - om) * 17.52) + 35.2),
        p2o5: _frmClamp(((13 - p) * 1.32) + 29.2),
        k2o: _frmClamp((k * -0.12) + 33.6),
      );
    case 'sugarcane':
      return Nutrients(
        n: _frmClamp(((0.7 - om) * 68) + 100),
        p2o5: _frmClamp(((9 - p) * 2.8) + 48.8),
        k2o: _frmClamp((k * -0.096) + 56.4),
      );
    default:
      throw ArgumentError('No SFRI soil-test formula for $cropId');
  }
}
