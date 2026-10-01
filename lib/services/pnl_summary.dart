// Whole-farm P&L computation — the SINGLE source of truth for profit/loss
// numbers used by both the on-screen P&L report (profit_loss_screen.dart)
// and the exported PDF farm report (pdf_report_service.dart).
//
// Extracted verbatim from the P&L screen so the two can never disagree.
// All money is INTEGER paisa; no floating point anywhere.

import '../models/models.dart';
import '../providers/activity_provider.dart';
import '../providers/crop_provider.dart';
import '../providers/harvest_provider.dart';
import '../providers/ushr_provider.dart';

/// One crop season's P&L line plus the detail lists the UI/report needs.
class CropPnlResult {
  final CropSeasonWithDetails details;
  final int incomePaisa;
  final int expensesPaisa;
  int get netPaisa => incomePaisa - expensesPaisa;
  final List<HarvestWithDetails> harvests;
  final List<ActivityWithDetails> activities;

  const CropPnlResult({
    required this.details,
    required this.incomePaisa,
    required this.expensesPaisa,
    required this.harvests,
    required this.activities,
  });
}

/// Whole-farm P&L: overall totals plus one line per crop season.
class FarmPnl {
  final int totalSalesPaisa;
  final int totalExpensesPaisa;
  int get netPaisa => totalSalesPaisa - totalExpensesPaisa;
  final List<CropPnlResult> crops;

  const FarmPnl({
    required this.totalSalesPaisa,
    required this.totalExpensesPaisa,
    required this.crops,
  });
}

/// Computes the farm P&L from provider data.
///
/// [totalExpensesPaisa] is the provider's already-summed expense total
/// (ExpenseProvider.totalExpensesPaisa).
FarmPnl computeFarmPnl({
  required List<HarvestWithDetails> harvests,
  required int totalExpensesPaisa,
  required List<CropSeasonWithDetails> seasons,
  required List<ActivityWithDetails> activities,
  required List<Expense> expenses,
  required List<UshrWithDetails> ushrRecords,
}) {
  // 1. Overall: revenue = sum of all sales (INTEGER paisa).
  final totalSales = harvests
      .where((h) => h.sale != null)
      .fold<int>(0, (sum, h) => sum + h.sale!.totalAmountPaisa);

  // 2. Crop-wise.
  final cropPnlList = seasons.map((details) {
    final seasonId = details.cropSeason.id;

    // Expenses for this season:
    //  (a) expenses linked via activities (legacy path — incl. the auto-created
    //      activity the Expenses screen adds for a crop-linked expense), and
    //  (b) expenses linked directly via expenses.crop_season_id (new path).
    // Dedupe by expense id so an expense linked both ways is counted once.
    final cropActivities = activities
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

    // Income for this season: cash received from sales of this season's
    // harvests. Uses sale.totalAmount — the SAME definition as the overall
    // header above — so the two can never disagree. Unsold harvests
    // contribute 0 (no phantom income from unsold stock).
    final cropHarvests =
        harvests.where((h) => h.harvest.cropSeasonId == seasonId).toList();
    final cropIncome = cropHarvests
        .where((h) => h.sale != null)
        .fold<int>(0, (sum, h) => sum + h.sale!.totalAmountPaisa);

    final cropHarvestExpenses = cropHarvests.fold<int>(
        0, (sum, h) => sum + h.harvest.totalExpensePaisa);

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
      expensesPaisa: totalCropExpenses,
      harvests: cropHarvests,
      activities: cropActivities,
    );
  }).toList();

  return FarmPnl(
    totalSalesPaisa: totalSales,
    totalExpensesPaisa: totalExpensesPaisa,
    crops: cropPnlList,
  );
}
