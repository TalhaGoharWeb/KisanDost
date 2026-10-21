/// Saved Khaad Hisaab plan (DB v18: `fertilizer_plans` +
/// `fertilizer_plan_items`). A plan is a snapshot — quantities and
/// prices frozen at save time.
library;

class FertilizerPlanItem {
  final int? id;
  final int? planId;
  final String productId;
  final String productName;
  final double kgPerAcre;
  final double totalKg;
  final int? pricePerBagPaisa;
  final double appliedKg;

  const FertilizerPlanItem({
    this.id,
    this.planId,
    required this.productId,
    required this.productName,
    required this.kgPerAcre,
    required this.totalKg,
    this.pricePerBagPaisa,
    this.appliedKg = 0,
  });

  Map<String, dynamic> toMap() => {
    if (id != null) 'id': id,
    if (planId != null) 'plan_id': planId,
    'product_id': productId,
    'product_name': productName,
    'kg_per_acre': kgPerAcre,
    'total_kg': totalKg,
    'price_per_bag_paisa': pricePerBagPaisa,
    'applied_kg': appliedKg,
  };

  factory FertilizerPlanItem.fromMap(Map<String, dynamic> m) =>
      FertilizerPlanItem(
        id: m['id'] as int?,
        planId: m['plan_id'] as int?,
        productId: m['product_id'] as String,
        productName: m['product_name'] as String,
        kgPerAcre: (m['kg_per_acre'] as num).toDouble(),
        totalKg: (m['total_kg'] as num).toDouble(),
        pricePerBagPaisa: m['price_per_bag_paisa'] as int?,
        appliedKg: (m['applied_kg'] as num?)?.toDouble() ?? 0,
      );
}

class FertilizerPlan {
  final int? id;
  final int? cropSeasonId;
  final int? fieldId;
  final String cropName;
  final String? variantName;
  final double areaAcres;
  final double targetNKg;
  final double targetPKg;
  final double targetKKg;
  final String? source;
  final bool isOfficial;
  final String createdAt;
  final List<FertilizerPlanItem> items;

  const FertilizerPlan({
    this.id,
    this.cropSeasonId,
    this.fieldId,
    required this.cropName,
    this.variantName,
    required this.areaAcres,
    required this.targetNKg,
    required this.targetPKg,
    required this.targetKKg,
    this.source,
    this.isOfficial = false,
    required this.createdAt,
    this.items = const [],
  });

  Map<String, dynamic> toMap() => {
    if (id != null) 'id': id,
    'crop_season_id': cropSeasonId,
    'field_id': fieldId,
    'crop_name': cropName,
    'variant_name': variantName,
    'area_acres': areaAcres,
    'target_n_kg': targetNKg,
    'target_p_kg': targetPKg,
    'target_k_kg': targetKKg,
    'source': source,
    'is_official': isOfficial ? 1 : 0,
    'created_at': createdAt,
  };

  factory FertilizerPlan.fromMap(
    Map<String, dynamic> m, {
    List<FertilizerPlanItem> items = const [],
  }) => FertilizerPlan(
    id: m['id'] as int?,
    cropSeasonId: m['crop_season_id'] as int?,
    fieldId: m['field_id'] as int?,
    cropName: m['crop_name'] as String,
    variantName: m['variant_name'] as String?,
    areaAcres: (m['area_acres'] as num).toDouble(),
    targetNKg: (m['target_n_kg'] as num).toDouble(),
    targetPKg: (m['target_p_kg'] as num).toDouble(),
    targetKKg: (m['target_k_kg'] as num).toDouble(),
    source: m['source'] as String?,
    isOfficial: (m['is_official'] as int? ?? 0) == 1,
    createdAt: m['created_at'] as String,
    items: items,
  );

  /// Total estimated cost in paisa from item snapshots (50 kg bags).
  int get estimatedCostPaisa {
    var total = 0;
    for (final item in items) {
      final price = item.pricePerBagPaisa;
      if (price != null) {
        final bags = item.totalKg / 50;
        total += ((bags * 2).ceil() / 2 * price).round();
      }
    }
    return total;
  }
}
