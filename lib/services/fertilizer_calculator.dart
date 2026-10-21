/// Khaad Hisaab — fertilizer calculation engine.
///
/// Pure Dart — no Flutter imports — so it can be unit-tested anywhere
/// and reused by any screen or report.
///
/// Core rule (the mistake this engine exists to prevent): a nutrient
/// requirement (e.g. 46 kg nitrogen) is NOT the same as a product
/// quantity (e.g. 100 kg urea). Every calculation keeps the two apart
/// and accounts for ALL nutrients a product supplies, so a combination
/// like DAP + urea never double-counts the nitrogen that DAP brings.
library;

/// Nutrient amounts in kg. N = nitrogen, P = P2O5 (phosphate),
/// K = K2O (potash) — the standard fertilizer-grade convention.
class Nutrients {
  final double n;
  final double p2o5;
  final double k2o;

  const Nutrients({this.n = 0, this.p2o5 = 0, this.k2o = 0});

  Nutrients operator +(Nutrients other) => Nutrients(
    n: n + other.n,
    p2o5: p2o5 + other.p2o5,
    k2o: k2o + other.k2o,
  );

  Nutrients operator -(Nutrients other) => Nutrients(
    n: n - other.n,
    p2o5: p2o5 - other.p2o5,
    k2o: k2o - other.k2o,
  );

  /// True when every nutrient is at or below [epsilon] kg.
  bool isNegligible([double epsilon = 0.05]) =>
      n.abs() <= epsilon && p2o5.abs() <= epsilon && k2o.abs() <= epsilon;

  @override
  String toString() => 'N $n, P2O5 $p2o5, K2O $k2o';
}

/// A fertilizer product with a CONFIGURABLE nutrient analysis.
/// Percentages are by weight (e.g. urea = 46% N). Nothing here assumes
/// a bag weight — [bagWeightKg] is data, shown to the farmer, and the
/// farmer's own products can carry their own values.
class FertilizerProduct {
  final String id;
  final String nameUr;
  final double nPct;
  final double p2o5Pct;
  final double k2oPct;

  /// Weight of one bag in kg (Pakistani standard for urea/DAP/etc. = 50).
  final double bagWeightKg;

  const FertilizerProduct({
    required this.id,
    required this.nameUr,
    this.nPct = 0,
    this.p2o5Pct = 0,
    this.k2oPct = 0,
    this.bagWeightKg = 50,
  });

  /// Nutrients supplied by [kg] of this product.
  Nutrients nutrientsIn(double kg) => Nutrients(
    n: kg * nPct / 100,
    p2o5: kg * p2o5Pct / 100,
    k2o: kg * k2oPct / 100,
  );

  /// Kg of this product needed to supply [kg] of a nutrient present at
  /// [pct]%. Throws if the product does not contain that nutrient.
  static double kgForNutrient(double kg, double pct) {
    if (pct <= 0) {
      throw ArgumentError('Product does not contain this nutrient.');
    }
    return kg * 100 / pct;
  }
}

/// One product's computed amount inside a plan.
class ProductAmount {
  final FertilizerProduct product;
  final double kgPerAcre;

  /// Nutrients this amount supplies per acre.
  final Nutrients nutrientsPerAcre;

  const ProductAmount({
    required this.product,
    required this.kgPerAcre,
    required this.nutrientsPerAcre,
  });

  double totalKg(double areaAcres) => kgPerAcre * areaAcres;

  /// Bags for the whole area, rounded UP to the nearest half bag —
  /// farmers buy whole/half bags, never 0.37 of a bag.
  double bagsFor(double areaAcres) {
    final bags = totalKg(areaAcres) / product.bagWeightKg;
    return (bags * 2).ceil() / 2;
  }

  /// Exact (unrounded) bags, for display alongside the rounded figure.
  double exactBagsFor(double areaAcres) =>
      totalKg(areaAcres) / product.bagWeightKg;
}

/// A complete computed plan for one field area.
class FertilizerPlanResult {
  /// The nutrient target the plan aims at (per acre).
  final Nutrients targetPerAcre;

  /// Products chosen, with per-acre quantities.
  final List<ProductAmount> products;

  /// Nutrients actually supplied per acre by [products].
  final Nutrients suppliedPerAcre;

  /// target − supplied per acre. Positive = shortfall, negative = excess.
  final Nutrients remainingPerAcre;

  final double areaAcres;

  const FertilizerPlanResult({
    required this.targetPerAcre,
    required this.products,
    required this.suppliedPerAcre,
    required this.remainingPerAcre,
    required this.areaAcres,
  });

  double totalKgOf(FertilizerProduct p) =>
      products
          .where((a) => a.product.id == p.id)
          .fold(0.0, (sum, a) => sum + a.totalKg(areaAcres));

  /// Total cost in paisa, given a price per bag per product id.
  /// Products without a price are skipped (treated as unknown, not 0
  /// cost) — [pricedProductIds] reports which were included.
  int totalCostPaisa(Map<String, int> pricePerBagPaisaById) {
    var total = 0;
    for (final a in products) {
      final price = pricePerBagPaisaById[a.product.id];
      if (price != null) {
        total += (a.bagsFor(areaAcres) * price).round();
      }
    }
    return total;
  }
}

class FertilizerCalculator {
  /// Builds a plan that meets [targetPerAcre] using:
  /// * [phosphorusSource] for P2O5 (DAP, NP, or SSP) — its N counts too,
  /// * [nitrogenSource] (normally urea) for the REMAINING nitrogen,
  /// * [potashSource] (SOP or MOP) for K2O, if provided.
  ///
  /// Order matters and is deliberate: phosphorus first (basal products
  /// also carry nitrogen), then top up nitrogen — this is exactly the
  /// no-double-counting rule. If the phosphorus source alone supplies
  /// MORE nitrogen than the target, no nitrogen product is added and
  /// the excess appears in [FertilizerPlanResult.remainingPerAcre]
  /// as a negative value for the UI to explain.
  static FertilizerPlanResult buildPlan({
    required Nutrients targetPerAcre,
    required double areaAcres,
    required FertilizerProduct phosphorusSource,
    required FertilizerProduct nitrogenSource,
    FertilizerProduct? potashSource,
  }) {
    if (areaAcres <= 0) {
      throw ArgumentError('Area must be positive.');
    }
    final amounts = <ProductAmount>[];
    var supplied = const Nutrients();

    // 1. Phosphorus from the basal source.
    if (targetPerAcre.p2o5 > 0) {
      final kg = FertilizerProduct.kgForNutrient(
        targetPerAcre.p2o5,
        phosphorusSource.p2o5Pct,
      );
      final n = phosphorusSource.nutrientsIn(kg);
      amounts.add(
        ProductAmount(
          product: phosphorusSource,
          kgPerAcre: kg,
          nutrientsPerAcre: n,
        ),
      );
      supplied = supplied + n;
    }

    // 2. Remaining nitrogen from the nitrogen source.
    final remainingN = targetPerAcre.n - supplied.n;
    if (remainingN > 0.05) {
      final kg = FertilizerProduct.kgForNutrient(
        remainingN,
        nitrogenSource.nPct,
      );
      final n = nitrogenSource.nutrientsIn(kg);
      amounts.add(
        ProductAmount(
          product: nitrogenSource,
          kgPerAcre: kg,
          nutrientsPerAcre: n,
        ),
      );
      supplied = supplied + n;
    }

    // 3. Remaining potash. A compound phosphorus source (NPK
    // 17-17-17) may already supply part of the potash — only the
    // remainder is topped up, so potash is never double-counted.
    final remainingK = targetPerAcre.k2o - supplied.k2o;
    if (remainingK > 0.05 && potashSource != null) {
      final kg = FertilizerProduct.kgForNutrient(
        remainingK,
        potashSource.k2oPct,
      );
      final n = potashSource.nutrientsIn(kg);
      amounts.add(
        ProductAmount(product: potashSource, kgPerAcre: kg, nutrientsPerAcre: n),
      );
      supplied = supplied + n;
    }

    return FertilizerPlanResult(
      targetPerAcre: targetPerAcre,
      products: amounts,
      suppliedPerAcre: supplied,
      remainingPerAcre: targetPerAcre - supplied,
      areaAcres: areaAcres,
    );
  }

  /// Every combination of the given sources for the same target —
  /// the full grid a farmer may choose from (5 phosphorus ×
  /// 3 nitrogen × 2 potash = 30). [potashOptions] may contain null
  /// for "no potash" (used when the target carries no potash).
  static List<FertilizerCombination> allCombinations({
    required Nutrients targetPerAcre,
    required double areaAcres,
    required List<FertilizerProduct> phosphorusSources,
    required List<FertilizerProduct> nitrogenSources,
    required List<FertilizerProduct?> potashOptions,
  }) {
    return [
      for (final p in phosphorusSources)
        for (final n in nitrogenSources)
          for (final k in potashOptions)
            FertilizerCombination(
              phosphorusSource: p,
              nitrogenSource: n,
              potashSource: k,
              result: buildPlan(
                targetPerAcre: targetPerAcre,
                areaAcres: areaAcres,
                phosphorusSource: p,
                nitrogenSource: n,
                potashSource: k,
              ),
            ),
    ];
  }

  /// Ranks combinations cheapest first — but ONLY combinations whose
  /// every product has a known price can be ranked; the rest keep
  /// their grid order after them. Mirrors the SFRI app's
  /// lowest-to-highest presentation without inventing any prices.
  static List<FertilizerCombination> rankByCost(
    List<FertilizerCombination> combinations,
    Map<String, int> pricePerBagPaisaById,
  ) {
    bool priced(FertilizerCombination c) => c.result.products.every(
      (a) => pricePerBagPaisaById.containsKey(a.product.id),
    );
    final ranked = combinations.where(priced).toList()
      ..sort(
        (a, b) => a.result
            .totalCostPaisa(pricePerBagPaisaById)
            .compareTo(b.result.totalCostPaisa(pricePerBagPaisaById)),
      );
    return [...ranked, ...combinations.where((c) => !priced(c))];
  }

  /// Compares the standard combinations for the same target so the
  /// farmer can choose by cost and suitability — cheapest is NOT
  /// auto-picked; the UI presents all three with their assumptions.
  static List<FertilizerPlanResult> compareCombinations({
    required Nutrients targetPerAcre,
    required double areaAcres,
    required List<FertilizerProduct> phosphorusSources,
    required FertilizerProduct nitrogenSource,
    FertilizerProduct? potashSource,
  }) {
    return [
      for (final p in phosphorusSources)
        buildPlan(
          targetPerAcre: targetPerAcre,
          areaAcres: areaAcres,
          phosphorusSource: p,
          nitrogenSource: nitrogenSource,
          potashSource: potashSource,
        ),
    ];
  }
}

/// One named combination (phosphorus × nitrogen × potash) with its
/// computed plan, so the UI can list, rank and select combinations.
class FertilizerCombination {
  final FertilizerProduct phosphorusSource;
  final FertilizerProduct nitrogenSource;
  final FertilizerProduct? potashSource;
  final FertilizerPlanResult result;

  const FertilizerCombination({
    required this.phosphorusSource,
    required this.nitrogenSource,
    required this.potashSource,
    required this.result,
  });

  /// Display label, e.g. «ڈی اے پی + یوریا + ایس او پی (پوٹاش)».
  String get labelUr => [
    phosphorusSource.nameUr,
    nitrogenSource.nameUr,
    if (potashSource != null) potashSource!.nameUr,
  ].join(' + ');
}
