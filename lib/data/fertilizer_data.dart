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
/// SOP 50% K2O (FFC SOP, +18% sulphur); MOP 60% K2O (standard grade).
const List<FertilizerProduct> kFertilizerProducts = [
  FertilizerProduct(id: 'urea', nameUr: 'یوریا', nPct: 46),
  FertilizerProduct(id: 'dap', nameUr: 'ڈی اے پی', nPct: 18, p2o5Pct: 46),
  FertilizerProduct(id: 'np', nameUr: 'این پی (نائٹروفاس)', nPct: 23, p2o5Pct: 23),
  FertilizerProduct(id: 'ssp', nameUr: 'ایس ایس پی', p2o5Pct: 18),
  FertilizerProduct(id: 'sop', nameUr: 'ایس او پی (پوٹاش)', k2oPct: 50),
  FertilizerProduct(id: 'mop', nameUr: 'ایم او پی (پوٹاش)', k2oPct: 60),
];

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
];

/// Major crops with NO verified dose yet. The calculator still works
/// for them in custom-target mode (soil test / extension advice).
const List<String> kCropsWithoutVerifiedDose = [
  'سورج مکھی',
  'آلو',
  'سرسوں / کینولا',
];
