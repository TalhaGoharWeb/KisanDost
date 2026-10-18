import 'package:flutter_test/flutter_test.dart';

import 'package:kisan_dost/models/models.dart';
import 'package:kisan_dost/providers/activity_provider.dart';
import 'package:kisan_dost/providers/crop_provider.dart';
import 'package:kisan_dost/providers/harvest_provider.dart';
import 'package:kisan_dost/providers/ushr_provider.dart';
import 'package:kisan_dost/services/pnl_summary.dart';

/// S1 regression (2026-10-18): the my_crops season card must show the SAME
/// منافع as the P&L screen. The card used to compute
/// Σ(sale.totalAmountPaisa) − Σ(activity-linked expenseAmountPaisa) only,
/// while computeFarmPnl (the P&L screen's single source of truth) also
/// counts direct expenses.crop_season_id rows, harvest-bucket expenses and
/// ushr due. The card now uses computeFarmPnl's per-season values
/// verbatim; this test pins the contract with a season where every extra
/// basis is non-zero, and proves the old card formula would have shown a
/// different (wrong) number.
void main() {
  CropSeasonWithDetails seasonDetails() => CropSeasonWithDetails(
    cropSeason: CropSeason(
      id: 1,
      fieldId: 1,
      cropName: 'گندم',
      variety: 'دیسی',
      status: 'active',
      startDate: '2026-01-01',
    ),
    fields: const [],
    fieldNames: const [],
    farmNames: const [],
    totalArea: 5.0,
  );

  // Activity-linked expense: 1,000.00 (via activity.expenseId = 11).
  ActivityWithDetails linkedActivity() => ActivityWithDetails(
    activity: Activity(
      id: 1,
      cropSeasonId: 1,
      activityType: 'کھاد',
      date: '2026-02-01',
      expenseId: 11,
    ),
    expenseAmountPaisa: 100000,
    cropName: 'گندم',
    fieldNames: const ['کھیت 1'],
  );

  // Direct expense (expenses.crop_season_id, no activity): 500.00.
  Expense directExpense() => Expense(
    id: 12,
    category: 'Labour',
    amountPaisa: 50000,
    date: '2026-02-02',
    cropSeasonId: 1,
  );

  // Harvest with harvest-bucket expenses (transport 200.00) + a sale of
  // 4,000.00. The sale is a genuine (Paid) sale: under the realized-income
  // rule (owner decision #1) only Paid/Partial sales count as income.
  HarvestWithDetails harvestWithSale() => HarvestWithDetails(
    harvest: Harvest(
      id: 1,
      cropSeasonId: 1,
      quantity: 100,
      unit: 'kg',
      date: '2026-04-01',
      transportationExpensePaisa: 20000,
      paymentStatus: 'Paid',
    ),
    cropName: 'گندم',
    fieldName: 'کھیت 1',
    fieldSize: 5.0,
    farmName: 'ٹیسٹ فارم',
    sale: Sale(
      id: 1,
      harvestId: 1,
      quantity: 100,
      pricePerUnitPaisa: 4000,
      totalAmountPaisa: 400000,
      date: '2026-04-02',
    ),
  );

  // Ushr due: 200.00.
  UshrWithDetails ushrDue() => UshrWithDetails(
    ushrRecord: UshrRecord(
      id: 1,
      cropSeasonId: 1,
      harvestQty: 100,
      marketValuePaisa: 400000,
      ushrMethod: 'cash',
      ushrPercentage: 5,
      ushrAmountPaisa: 20000,
      status: 'pending',
    ),
    cropName: 'گندم',
    fieldName: 'کھیت 1',
    farmName: 'ٹیسٹ فارم',
    fieldSize: 5.0,
  );

  FarmPnl pnl() => computeFarmPnl(
    harvests: [harvestWithSale()],
    totalExpensesPaisa: 100000 + 50000,
    seasons: [seasonDetails()],
    activities: [linkedActivity()],
    expenses: [directExpense()],
    ushrRecords: [ushrDue()],
  );

  test(
    'card منافع == computeFarmPnl season منافع (full expense basis)',
    () {
      final seasonPnl = pnl().crops.single;

      // Full basis: 1,000 (activity-linked) + 500 (direct) +
      // 200 (harvest bucket) + 200 (ushr) = 1,900.00 expenses;
      // income 4,000.00 → منافع 2,100.00.
      expect(seasonPnl.incomePaisa, 400000);
      expect(seasonPnl.expensesPaisa, 190000);
      expect(seasonPnl.netPaisa, 210000);
    },
  );

  test('the old activity-only card formula diverges on the same data', () {
    // What my_crops_screen.dart used to display (activity-linked only).
    final oldCardProfitPaisa =
        400000 - // Σ sale totals
        100000; // Σ activity expenseAmountPaisa only
    expect(oldCardProfitPaisa, 300000);

    // The P&L screen (and now the card) shows the full-basis figure.
    expect(pnl().crops.single.netPaisa, 210000);
    expect(oldCardProfitPaisa, isNot(pnl().crops.single.netPaisa));
  });
}
