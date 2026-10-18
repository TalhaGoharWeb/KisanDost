import 'package:flutter_test/flutter_test.dart';

import 'package:kisan_dost/models/models.dart';
import 'package:kisan_dost/providers/ushr_provider.dart';

/// S8 / owner decision #4 (2026-10-18): ushr due, paid and remaining must be
/// three DISTINCT figures everywhere ushr appears — per crop-season, per
/// crop and overall. Paid = cash + in-kind valued at qtyPaid × rate, rounded
/// to the nearest paisa (the same rounding as the D2 guard and
/// UshrRecord.remainingBalancePaisa).
///
/// Hand-computed reference (all money in INTEGER paisa; Rs 1 = 100 paisa):
///
/// | id | crop/season | due       | cash    | in-kind        | paid      | remaining |
/// | A  | گندم / 1   | 1,400,000 | 500,000 | —              |   500,000 |   900,000 | (cash-only, partial)
/// | B  | گندم / 1   | 3,500,000 | 0       | 2.0 × 350,000  |   700,000 | 2,800,000 | (in-kind, partial)
/// | C  | چاول / 2   | 2,000,000 | 400,000 | 1.5 × 400,000  | 1,000,000 | 1,000,000 | (mixed, partial)
/// | D  | چاول / 2   |   500,000 | 500,000 | —              |   500,000 |         0 | (cash-only, fully paid)
/// | E  | گندم / 3   |   800,000 | 0       | —              |         0 |   800,000 | (nothing paid)
/// | F  | گندم / 3   |   100,000 | 0       | 1.333 × 33,333 |    44,433 |    55,567 | (rounding)
///
/// 1.333 × 33,333 = 44,432.889… → rounds to 44,433 paisa.
///
/// Season 1 (A+B):      due 4,900,000 / paid 1,200,000 / remaining 3,700,000
/// Season 2 (C+D):      due 2,500,000 / paid 1,500,000 / remaining 1,000,000
/// Season 3 (E+F):      due   900,000 / paid    44,433 / remaining   855,567
/// گندم (seasons 1,3): due 5,800,000 / paid 1,244,433 / remaining 4,555,567
/// چاول (season 2):    due 2,500,000 / paid 1,500,000 / remaining 1,000,000
/// Overall:             due 8,300,000 / paid 2,744,433 / remaining 5,555,567
/// (8,300,000 = 2,744,433 + 5,555,567 — due always equals paid + remaining.)
void main() {
  UshrRecord rec({
    required int cropSeasonId,
    required int due,
    int cash = 0,
    double qty = 0.0,
    int rate = 0,
  }) => UshrRecord(
    cropSeasonId: cropSeasonId,
    harvestQty: 100.0,
    marketValuePaisa: 1000000,
    ushrMethod: 'Natural',
    ushrPercentage: 10.0,
    ushrAmountPaisa: due,
    status: 'Pending',
    payMethod: qty > 0 ? 'Crop' : 'Cash',
    qtyPaid: qty,
    cashPaidPaisa: cash,
    ratePerUnitPaisa: rate,
  );

  UshrWithDetails item(String crop, UshrRecord r) => UshrWithDetails(
    ushrRecord: r,
    cropName: crop,
    fieldName: 'کھیت',
    farmName: 'فارم',
    fieldSize: 5.0,
  );

  List<UshrWithDetails> fixture() => [
    item('گندم', rec(cropSeasonId: 1, due: 1400000, cash: 500000)), // A
    item('گندم', rec(cropSeasonId: 1, due: 3500000, qty: 2.0, rate: 350000)), // B
    item(
      'چاول',
      rec(cropSeasonId: 2, due: 2000000, cash: 400000, qty: 1.5, rate: 400000),
    ), // C
    item('چاول', rec(cropSeasonId: 2, due: 500000, cash: 500000)), // D
    item('گندم', rec(cropSeasonId: 3, due: 800000)), // E
    item('گندم', rec(cropSeasonId: 3, due: 100000, qty: 1.333, rate: 33333)), // F
  ];

  group('paidValuePaisaOf', () {
    test('cash-only payment', () {
      expect(
        UshrProvider.paidValuePaisaOf(
          rec(cropSeasonId: 1, due: 1400000, cash: 500000),
        ),
        500000,
      );
    });

    test('in-kind payment is valued at qty x rate', () {
      // 2.0 × 350,000 = 700,000.
      expect(
        UshrProvider.paidValuePaisaOf(
          rec(cropSeasonId: 1, due: 3500000, qty: 2.0, rate: 350000),
        ),
        700000,
      );
    });

    test('mixed payment sums cash and in-kind', () {
      // 400,000 + 1.5 × 400,000 = 400,000 + 600,000 = 1,000,000.
      expect(
        UshrProvider.paidValuePaisaOf(
          rec(
            cropSeasonId: 2,
            due: 2000000,
            cash: 400000,
            qty: 1.5,
            rate: 400000,
          ),
        ),
        1000000,
      );
    });

    test('rounds the in-kind value to the nearest paisa', () {
      // 1.333 × 33,333 = 44,432.889… → 44,433.
      expect(
        UshrProvider.paidValuePaisaOf(
          rec(cropSeasonId: 3, due: 100000, qty: 1.333, rate: 33333),
        ),
        44433,
      );
    });

    test('zero payment', () {
      expect(UshrProvider.paidValuePaisaOf(rec(cropSeasonId: 3, due: 800000)), 0);
    });
  });

  group('totalsOfRecords (overall)', () {
    test('shows due, paid and remaining as three distinct figures', () {
      final t = UshrProvider.totalsOfRecords(
        fixture().map((d) => d.ushrRecord),
      );
      expect(t.totalDuePaisa, 8300000);
      expect(t.totalPaidPaisa, 2744433);
      expect(t.totalRemainingPaisa, 5555567);
    });

    test('due always equals paid + remaining', () {
      final t = UshrProvider.totalsOfRecords(
        fixture().map((d) => d.ushrRecord),
      );
      expect(t.totalDuePaisa, t.totalPaidPaisa + t.totalRemainingPaisa);
    });

    test('empty records give zero totals', () {
      final t = UshrProvider.totalsOfRecords(const []);
      expect(t.totalDuePaisa, 0);
      expect(t.totalPaidPaisa, 0);
      expect(t.totalRemainingPaisa, 0);
    });
  });

  group('seasonTotalsOf (per season)', () {
    test('rolls records up per crop-season', () {
      final seasons = UshrProvider.seasonTotalsOf(fixture());
      expect(seasons.length, 3);
      // Season 1 (A+B): due 1,400,000 + 3,500,000 = 4,900,000;
      // paid 500,000 + 700,000 = 1,200,000; remaining 3,700,000.
      expect(seasons[0].cropSeasonId, 1);
      expect(seasons[0].cropName, 'گندم');
      expect(seasons[0].totals.totalDuePaisa, 4900000);
      expect(seasons[0].totals.totalPaidPaisa, 1200000);
      expect(seasons[0].totals.totalRemainingPaisa, 3700000);
      // Season 2 (C+D): 2,500,000 / 1,500,000 / 1,000,000.
      expect(seasons[1].cropSeasonId, 2);
      expect(seasons[1].totals.totalDuePaisa, 2500000);
      expect(seasons[1].totals.totalPaidPaisa, 1500000);
      expect(seasons[1].totals.totalRemainingPaisa, 1000000);
      // Season 3 (E+F): 900,000 / 44,433 / 855,567.
      expect(seasons[2].cropSeasonId, 3);
      expect(seasons[2].totals.totalDuePaisa, 900000);
      expect(seasons[2].totals.totalPaidPaisa, 44433);
      expect(seasons[2].totals.totalRemainingPaisa, 855567);
    });

    test('fully-paid season has zero remaining', () {
      final seasons = UshrProvider.seasonTotalsOf([
        item('چاول', rec(cropSeasonId: 2, due: 500000, cash: 500000)),
      ]);
      expect(seasons.single.totals.totalPaidPaisa, 500000);
      expect(seasons.single.totals.totalRemainingPaisa, 0);
    });

    test('empty list gives no seasons', () {
      expect(UshrProvider.seasonTotalsOf(const []), isEmpty);
    });
  });

  group('cropTotalsOf (per crop)', () {
    test('rolls seasons up per crop with the season count', () {
      final crops = UshrProvider.cropTotalsOf(fixture());
      expect(crops.length, 2);
      // گندم (seasons 1 and 3): due 4,900,000 + 900,000 = 5,800,000;
      // paid 1,200,000 + 44,433 = 1,244,433;
      // remaining 3,700,000 + 855,567 = 4,555,567.
      expect(crops[0].cropName, 'گندم');
      expect(crops[0].seasonCount, 2);
      expect(crops[0].totals.totalDuePaisa, 5800000);
      expect(crops[0].totals.totalPaidPaisa, 1244433);
      expect(crops[0].totals.totalRemainingPaisa, 4555567);
      // چاول (season 2): 2,500,000 / 1,500,000 / 1,000,000.
      expect(crops[1].cropName, 'چاول');
      expect(crops[1].seasonCount, 1);
      expect(crops[1].totals.totalDuePaisa, 2500000);
      expect(crops[1].totals.totalPaidPaisa, 1500000);
      expect(crops[1].totals.totalRemainingPaisa, 1000000);
    });

    test('per-crop sums reconcile with the overall totals', () {
      final crops = UshrProvider.cropTotalsOf(fixture());
      final overall = UshrProvider.totalsOfRecords(
        fixture().map((d) => d.ushrRecord),
      );
      int due = 0;
      int paid = 0;
      int remaining = 0;
      for (final c in crops) {
        due += c.totals.totalDuePaisa;
        paid += c.totals.totalPaidPaisa;
        remaining += c.totals.totalRemainingPaisa;
      }
      expect(due, overall.totalDuePaisa);
      expect(paid, overall.totalPaidPaisa);
      expect(remaining, overall.totalRemainingPaisa);
    });

    test('empty list gives no crops', () {
      expect(UshrProvider.cropTotalsOf(const []), isEmpty);
    });
  });
}
