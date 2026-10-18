// Whole-farm P&L computation — the SINGLE source of truth for profit/loss
// numbers used by both the on-screen P&L report (profit_loss_screen.dart)
// and the exported PDF farm report (pdf_report_service.dart).
//
// Extracted verbatim from the P&L screen so the two can never disagree.
// All money is INTEGER paisa; no floating point anywhere.

import '../models/batai.dart';
import '../models/models.dart';
import '../providers/activity_provider.dart';
import '../providers/crop_provider.dart';
import '../providers/harvest_provider.dart';
import '../providers/ushr_provider.dart';

/// One crop season's P&L line plus the detail lists the UI/report needs.
class CropPnlResult {
  final CropSeasonWithDetails details;

  /// Realized income = [salesIncomePaisa] + [bataiIncomePaisa].
  final int incomePaisa;

  /// Income from genuine sales: harvest.payment_status 'Paid'/'Partial'
  /// with no batai settlement linked.
  final int salesIncomePaisa;

  /// The farmer's ACTUAL share of batai settlements (role-aware split).
  final int bataiIncomePaisa;

  /// 'Pending' (unsold/estimated) sales — NOT income; tracked as a separate
  /// visible figure so the farmer sees what produce is still awaiting sale.
  final int unsoldProducePaisa;

  final int expensesPaisa;
  int get netPaisa => incomePaisa - expensesPaisa;
  final List<HarvestWithDetails> harvests;
  final List<ActivityWithDetails> activities;

  const CropPnlResult({
    required this.details,
    required this.incomePaisa,
    this.salesIncomePaisa = 0,
    this.bataiIncomePaisa = 0,
    this.unsoldProducePaisa = 0,
    required this.expensesPaisa,
    required this.harvests,
    required this.activities,
  });
}

/// Whole-farm P&L: overall totals plus one line per crop season.
class FarmPnl {
  /// Realized income total = [salesIncomePaisa] + [bataiIncomePaisa].
  /// (Kept name: the PDF export and older callers read this field.)
  final int totalSalesPaisa;

  /// Income from genuine sales (Paid/Partial, no batai settlement linked).
  final int salesIncomePaisa;

  /// The farmer's ACTUAL share of all batai settlements.
  final int bataiIncomePaisa;

  /// 'Pending' (unsold/estimated) sales — NOT income; the visible
  /// "remaining produce" figure.
  final int unsoldProducePaisa;

  final int totalExpensesPaisa;
  int get netPaisa => totalSalesPaisa - totalExpensesPaisa;
  final List<CropPnlResult> crops;

  const FarmPnl({
    required this.totalSalesPaisa,
    this.salesIncomePaisa = 0,
    this.bataiIncomePaisa = 0,
    this.unsoldProducePaisa = 0,
    required this.totalExpensesPaisa,
    required this.crops,
  });
}

/// One harvest's realized figures. Exactly one of the three buckets holds
/// the harvest's sale value; a harvest with no live sale is all zeros.
class HarvestPnlFigures {
  final int salesIncomePaisa;
  final int bataiIncomePaisa;
  final int unsoldProducePaisa;

  const HarvestPnlFigures({
    this.salesIncomePaisa = 0,
    this.bataiIncomePaisa = 0,
    this.unsoldProducePaisa = 0,
  });

  int get incomePaisa => salesIncomePaisa + bataiIncomePaisa;
}

/// The farmer's ACTUAL share of one batai settlement, picked role-aware
/// from the stored split: landowner → owner_paisa, cultivator →
/// cultivator_paisa. The stored split was computed with splitBatai at
/// settle time (fractional-paisa remainder → larger share, owner on tie;
/// a DB CHECK enforces owner + cultivator = total) and agreement terms lock
/// on the first settlement, so the stored values ARE the agreed actuals.
///
/// A settlement whose agreement is missing from [agreements] contributes 0
/// (defensive: an agreement with settlements can never be deleted, so this
/// is a caller bug — callers must pass every agreement).
int bataiFarmerSharePaisa(
  BataiSettlement settlement,
  List<BataiAgreement> agreements,
) {
  for (final a in agreements) {
    if (a.id == settlement.agreementId) {
      return a.farmerRole == FarmerRole.landowner
          ? settlement.ownerPaisa
          : settlement.cultivatorPaisa;
    }
  }
  return 0;
}

/// Per-harvest realized figures plus the settlements that could not be
/// linked to any harvest in [harvests] (their farmer share still counts
/// toward the farm total — see [computeFarmPnl]).
///
/// The map is keyed by the [HarvestWithDetails] instance (identity), NOT by
/// harvest id: unit-test fixtures routinely build harvests without ids,
/// and the same list instances flow from the providers into this function.
({
  Map<HarvestWithDetails, HarvestPnlFigures> byHarvest,
  List<BataiSettlement> unlinkedSettlements,
})
computeHarvestPnlFigures({
  required List<HarvestWithDetails> harvests,
  List<BataiSettlement> bataiSettlements = const [],
  List<BataiAgreement> bataiAgreements = const [],
}) {
  final saleIdToHarvest = <int, HarvestWithDetails>{};
  for (final h in harvests) {
    final sid = h.sale?.id;
    if (sid != null) saleIdToHarvest[sid] = h;
  }
  final harvestById = <int, HarvestWithDetails>{
    for (final h in harvests)
      if (h.harvest.id != null) h.harvest.id!: h,
  };

  // The farmer's share per harvest, summed over every settlement linked to
  // it (by harvest_id, or by sale_id through the sale→harvest map).
  final harvestBataiPaisa = <HarvestWithDetails, int>{};
  final unlinkedSettlements = <BataiSettlement>[];
  for (final s in bataiSettlements) {
    HarvestWithDetails? target = s.harvestId == null
        ? null
        : harvestById[s.harvestId!];
    target ??= s.saleId == null ? null : saleIdToHarvest[s.saleId!];
    if (target != null) {
      harvestBataiPaisa[target] =
          (harvestBataiPaisa[target] ?? 0) +
          bataiFarmerSharePaisa(s, bataiAgreements);
    } else {
      unlinkedSettlements.add(s);
    }
  }

  final byHarvest = <HarvestWithDetails, HarvestPnlFigures>{};
  for (final h in harvests) {
    final sale = h.sale;
    final batai = harvestBataiPaisa[h] ?? 0;
    if (sale == null) {
      byHarvest[h] = const HarvestPnlFigures();
    } else if (batai > 0) {
      // Batai rule (owner decision #2): the full sale total is excluded —
      // counting it alongside the distribution would double-count. Only
      // the farmer's actual share of each linked settlement counts.
      byHarvest[h] = HarvestPnlFigures(bataiIncomePaisa: batai);
    } else if (h.harvest.paymentStatus == 'Paid' ||
        h.harvest.paymentStatus == 'Partial') {
      // A genuine sale happened — including credit sales (recordSale marks
      // them 'Paid'; the outstanding amount lives in the party ledger per
      // owner decision #3) and partial-payment sales ('Partial').
      byHarvest[h] = HarvestPnlFigures(
        salesIncomePaisa: sale.totalAmountPaisa,
      );
    } else {
      // 'Pending' (or anything unexpected): the auto-created estimate from
      // merely entering a rate on an unsold harvest. Excluded from realized
      // income (owner decision #1); tracked as remaining produce instead.
      byHarvest[h] = HarvestPnlFigures(
        unsoldProducePaisa: sale.totalAmountPaisa,
      );
    }
  }
  return (byHarvest: byHarvest, unlinkedSettlements: unlinkedSettlements);
}

/// Computes the farm P&L from provider data.
///
/// [totalExpensesPaisa] is the provider's already-summed expense total
/// (ExpenseProvider.totalExpensesPaisa).
///
/// REALIZED-INCOME RULE (owner decision #1, S2 / FINANCIAL_POLICY §6.1):
/// a harvest's linked live sale counts as realized income ONLY when
/// harvest.payment_status is 'Paid' or 'Partial' — a genuine sale happened.
/// 'Pending' sales are ESTIMATES auto-created when the farmer merely enters
/// a rate on an unsold harvest (see HarvestProvider.addHarvest /
/// updateHarvest: any rate > 0 inserts a sales row while payment_status
/// stays 'Pending'; only recordSale flips it to 'Paid'): they are EXCLUDED
/// from realized income and reported separately as
/// [FarmPnl.unsoldProducePaisa] — the visible "remaining produce" figure.
/// Entering an estimated rate stays fully supported; it just no longer
/// books phantom income. Preserved: estimated rate entry, partial sales
/// ('Partial' counts as income), credit sales (recorded 'Paid').
///
/// BATAI RULE (owner decision #2, S3 / FINANCIAL_POLICY §6.3): when a
/// harvest's proceeds were split via batai (≥1 settlement linked by
/// harvest_id or sale_id — see [computeHarvestPnlFigures]), the full sale
/// total is excluded from income and the farmer's ACTUAL share of each
/// linked settlement is added instead (role-aware via
/// [bataiFarmerSharePaisa]), so harvest sale + distribution can never
/// double-count. Settlements linked to no harvest in [harvests] still count
/// toward the farm total, attributed to the agreement's crop season when
/// one is set.
FarmPnl computeFarmPnl({
  required List<HarvestWithDetails> harvests,
  required int totalExpensesPaisa,
  required List<CropSeasonWithDetails> seasons,
  required List<ActivityWithDetails> activities,
  required List<Expense> expenses,
  required List<UshrWithDetails> ushrRecords,
  List<BataiSettlement> bataiSettlements = const [],
  List<BataiAgreement> bataiAgreements = const [],
}) {
  final breakdown = computeHarvestPnlFigures(
    harvests: harvests,
    bataiSettlements: bataiSettlements,
    bataiAgreements: bataiAgreements,
  );
  final figures = breakdown.byHarvest;

  HarvestPnlFigures figOf(HarvestWithDetails h) =>
      figures[h] ?? const HarvestPnlFigures();

  // Agreement id → its crop season, for attributing unlinked settlements.
  final seasonByAgreementId = <int, int?>{};
  for (final a in bataiAgreements) {
    final id = a.id;
    if (id != null) seasonByAgreementId[id] = a.cropSeasonId;
  }
  int unlinkedShareOf(BataiSettlement s) =>
      bataiFarmerSharePaisa(s, bataiAgreements);

  // 1. Overall: realized income = sales + the farmer's batai share.
  //    Unsold (Pending) produce is tracked separately — never income.
  int totalSalesIncome = 0;
  int totalBataiIncome = 0;
  int totalUnsold = 0;
  for (final h in harvests) {
    final f = figOf(h);
    totalSalesIncome += f.salesIncomePaisa;
    totalBataiIncome += f.bataiIncomePaisa;
    totalUnsold += f.unsoldProducePaisa;
  }
  for (final s in breakdown.unlinkedSettlements) {
    totalBataiIncome += unlinkedShareOf(s);
  }
  final totalIncome = totalSalesIncome + totalBataiIncome;

  // 2. Crop-wise.
  final cropPnlList =
      seasons.map((details) {
        final seasonId = details.cropSeason.id;

        // Expenses for this season:
        //  (a) expenses linked via activities (legacy path — incl. the auto-created
        //      activity the Expenses screen adds for a crop-linked expense), and
        //  (b) expenses linked directly via expenses.crop_season_id (new path).
        // Dedupe by expense id so an expense linked both ways is counted once.
        final cropActivities =
            activities
                .where((act) => act.activity.cropSeasonId == seasonId)
                .toList();
        final linkedExpenseIds = <int>{};
        int activityLinkedExpenses = 0;
        for (final act in cropActivities) {
          final expId = act.activity.expenseId;
          if (expId != null && linkedExpenseIds.add(expId)) {
            activityLinkedExpenses += act.expenseAmountPaisa ?? 0;
          }
        }
        int directExpenses = 0;
        for (final exp in expenses) {
          final expId = exp.id;
          if (exp.cropSeasonId == seasonId &&
              expId != null &&
              !linkedExpenseIds.contains(expId)) {
            directExpenses += exp.amountPaisa;
          }
        }
        final cropExpenses = activityLinkedExpenses + directExpenses;

        // Income for this season: realized income (Paid/Partial sales + the
        // farmer's batai share) of this season's harvests — the SAME
        // definition as the overall header above — so the two can never
        // disagree. Pending (unsold/estimated) sales contribute 0 income
        // and are reported as unsold produce instead.
        final cropHarvests =
            harvests.where((h) => h.harvest.cropSeasonId == seasonId).toList();
        int cropSalesIncome = 0;
        int cropBataiIncome = 0;
        int cropUnsold = 0;
        for (final h in cropHarvests) {
          final f = figOf(h);
          cropSalesIncome += f.salesIncomePaisa;
          cropBataiIncome += f.bataiIncomePaisa;
          cropUnsold += f.unsoldProducePaisa;
        }
        // Unlinked settlements attributed via the agreement's crop season.
        for (final s in breakdown.unlinkedSettlements) {
          if (seasonByAgreementId[s.agreementId] == seasonId) {
            cropBataiIncome += unlinkedShareOf(s);
          }
        }
        final cropIncome = cropSalesIncome + cropBataiIncome;

        final cropHarvestExpenses = cropHarvests.fold<int>(
          0,
          (sum, h) => sum + h.harvest.totalExpensePaisa,
        );

        // Ushr stays counted as a crop expense exactly as before — only the
        // field types moved to paisa. (Ushr policy itself is deliberately
        // deferred; this computation fixes types only.)
        final cropUshrExpenses = ushrRecords
            .where((u) => u.ushrRecord.cropSeasonId == seasonId)
            .fold<int>(0, (sum, u) => sum + u.ushrRecord.ushrAmountPaisa);

        final totalCropExpenses =
            cropExpenses + cropHarvestExpenses + cropUshrExpenses;

        return CropPnlResult(
          details: details,
          incomePaisa: cropIncome,
          salesIncomePaisa: cropSalesIncome,
          bataiIncomePaisa: cropBataiIncome,
          unsoldProducePaisa: cropUnsold,
          expensesPaisa: totalCropExpenses,
          harvests: cropHarvests,
          activities: cropActivities,
        );
      }).toList();

  return FarmPnl(
    totalSalesPaisa: totalIncome,
    salesIncomePaisa: totalSalesIncome,
    bataiIncomePaisa: totalBataiIncome,
    unsoldProducePaisa: totalUnsold,
    totalExpensesPaisa: totalExpensesPaisa,
    crops: cropPnlList,
  );
}
