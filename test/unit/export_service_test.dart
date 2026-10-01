// Unit tests for the Phase 9 CSV export builders and the shared P&L
// computation. All pure-Dart: no DB, no Flutter.
import 'package:flutter_test/flutter_test.dart';
import 'package:kisan_dost/models/batai.dart';
import 'package:kisan_dost/models/models.dart';
import 'package:kisan_dost/models/party.dart';
import 'package:kisan_dost/providers/activity_provider.dart';
import 'package:kisan_dost/providers/crop_provider.dart';
import 'package:kisan_dost/providers/harvest_provider.dart';
import 'package:kisan_dost/providers/ushr_provider.dart';
import 'package:kisan_dost/services/export_service.dart';
import 'package:kisan_dost/services/pnl_summary.dart';

void main() {
  group('csvEscape', () {
    test('plain text passes through untouched', () {
      expect(csvEscape('گندم'), 'گندم');
      expect(csvEscape('abc 123'), 'abc 123');
    });

    test('null becomes empty string', () {
      expect(csvEscape(null), '');
    });

    test('comma forces quoting', () {
      expect(csvEscape('a,b'), '"a,b"');
    });

    test('quotes are doubled inside quotes', () {
      expect(csvEscape('کہا "ہاں"'), '"کہا ""ہاں"""');
    });

    test('newline forces quoting', () {
      expect(csvEscape('a\nb'), '"a\nb"');
    });
  });

  group('BOM', () {
    test('every CSV starts with the UTF-8 BOM char', () {
      expect(
        expensesCsv(
          [],
          farmNames: {},
          fieldNames: {},
          cropNames: {},
          categoryLabels: {},
        ).codeUnitAt(0),
        0xFEFF,
      );
      expect(salesCsv([]).codeUnitAt(0), 0xFEFF);
      expect(partyLedgerCsv([], {}, {}).codeUnitAt(0), 0xFEFF);
      expect(inventoryTransactionsCsv([], {}).codeUnitAt(0), 0xFEFF);
      expect(bataiSettlementsCsv([], {}).codeUnitAt(0), 0xFEFF);
    });

    test('empty inputs produce valid headers-only CSV', () {
      final csv = expensesCsv(
        [],
        farmNames: {},
        fieldNames: {},
        cropNames: {},
        categoryLabels: {},
      );
      final lines = csv.trim().split('\n');
      expect(lines.length, 1);
      expect(lines.first, contains('تاریخ'));
      expect(lines.first, contains('زمرہ'));
    });
  });

  group('expensesCsv', () {
    test('resolves names, exact paisa formatting, escapes description', () {
      final csv = expensesCsv(
        [
          Expense(
            category: 'Fertilizer',
            amountPaisa: 125050, // Rs 1,250.50 — no float involved
            date: '2026-09-15',
            description: 'یوریا، "بوری" والی',
            farmId: 1,
            fieldId: 2,
            cropSeasonId: 3,
          ),
        ],
        farmNames: {1: 'چک نمبر 5'},
        fieldNames: {2: 'مشرقی کھیت'},
        cropNames: {3: 'گندم (فیصل آباد)'},
        categoryLabels: {'Fertilizer': 'کھاد (Fertilizer)'},
      );
      expect(csv, contains('1,250.50 روپے'));
      expect(csv, contains('کھاد (Fertilizer)'));
      expect(csv, contains('چک نمبر 5'));
      expect(csv, contains('مشرقی کھیت'));
      expect(csv, contains('گندم (فیصل آباد)'));
      // Comma + quotes in description must be escaped, not break columns.
      expect(csv, contains('"یوریا، ""بوری"" والی"'));
      // Date emitted exactly as stored.
      expect(csv, contains('2026-09-15'));
    });

    test('unknown ids and null links yield empty cells, never crash', () {
      final csv = expensesCsv(
        [
          Expense(
            category: 'Other',
            amountPaisa: 100,
            date: '2026-01-01',
            farmId: 999,
          ),
        ],
        farmNames: {},
        fieldNames: {},
        cropNames: {},
        categoryLabels: {},
      );
      expect(csv, contains('1 روپے'));
      expect(csv, isNot(contains('999')));
      // Unknown category falls back to the raw key.
      expect(csv, contains('Other'));
    });
  });

  group('salesCsv', () {
    test('only sold harvests appear; quantities print without .0', () {
      final harvests = [
        HarvestWithDetails(
          harvest: Harvest(
            cropSeasonId: 1,
            quantity: 40,
            unit: 'من',
            date: '2026-05-01',
          ),
          cropName: 'گندم',
          fieldName: 'کھیت',
          fieldSize: 5,
          farmName: 'چک 5',
          sale: Sale(
            harvestId: 1,
            buyerName: 'آڑھتی، لاہور',
            quantity: 40,
            pricePerUnitPaisa: 300000,
            totalAmountPaisa: 12000000,
            date: '2026-05-10',
          ),
        ),
        HarvestWithDetails(
          harvest: Harvest(
            cropSeasonId: 1,
            quantity: 10,
            unit: 'من',
            date: '2026-05-02',
          ),
          cropName: 'گندم',
          fieldName: 'کھیت',
          fieldSize: 5,
          farmName: 'چک 5',
          // No sale — unsold harvest must not appear.
        ),
      ];
      final csv = salesCsv(harvests);
      final lines = csv.trim().split('\n');
      expect(lines.length, 2); // header + 1 row
      expect(csv, contains('120,000 روپے'));
      expect(csv, contains('3,000 روپے'));
      // Urdu comma (،) is not an ASCII comma — correctly left unquoted.
      expect(csv, contains('آڑھتی، لاہور'));
      expect(csv, isNot(contains('2026-05-02')));
    });
  });

  group('partyLedgerCsv', () {
    test('entries plus per-party balance rows', () {
      final csv = partyLedgerCsv(
        [
          PartyLedgerEntry(
            partyId: 1,
            type: PartyEntryType.udhaarDiya,
            amountPaisa: 500000,
            date: '2026-08-01',
            createdAt: '2026-08-01',
          ),
          PartyLedgerEntry(
            partyId: 1,
            type: PartyEntryType.wusooli,
            amountPaisa: 200000,
            date: '2026-09-01',
            note: 'نقد',
            createdAt: '2026-09-01',
          ),
          PartyLedgerEntry(
            partyId: 2,
            type: PartyEntryType.udhaarLiya,
            amountPaisa: -75000,
            date: '2026-07-01',
            createdAt: '2026-07-01',
          ),
        ],
        {1: 'احمد', 2: 'کریم'},
        {1: 300000, 2: -75000},
      );
      expect(csv, contains('ادھار دیا'));
      expect(csv, contains('وصولی'));
      expect(csv, contains('پارٹی کی ذمہ'));
      expect(csv, contains('میری ذمہ'));
      // Amounts shown as absolute values with the direction column.
      expect(csv, contains('5,000 روپے'));
      // Balance summary rows.
      expect(csv, contains('بیلنس'));
      expect(csv, contains('3,000 روپے'));
      expect(csv, contains('پارٹی سے لینا ہے'));
      expect(csv, contains('750 روپے'));
      expect(csv, contains('پارٹی کو دینا ہے'));
    });
  });

  group('inventoryTransactionsCsv', () {
    test('type labels in Urdu, null prices leave cells empty', () {
      final csv = inventoryTransactionsCsv(
        [
          InventoryTransaction(
            inventoryId: 7,
            type: 'purchase',
            quantity: 2.5,
            unit: 'بوری',
            unitPricePaisa: 450000,
            totalAmountPaisa: 1125000,
            date: '2026-09-01',
            createdAt: '2026-09-01',
          ),
          InventoryTransaction(
            inventoryId: 7,
            type: 'usage',
            quantity: 1,
            unit: 'بوری',
            date: '2026-09-10',
            createdAt: '2026-09-10',
          ),
        ],
        {7: 'یوریا (بوری)'},
      );
      expect(csv, contains('خریداری'));
      expect(csv, contains('استعمال'));
      expect(csv, contains('2.5'));
      expect(csv, contains('11,250 روپے'));
      expect(csv, contains('یوریا (بوری)'));
    });
  });

  group('bataiSettlementsCsv', () {
    test('shares and agreement label', () {
      final csv = bataiSettlementsCsv(
        [
          BataiSettlement(
            agreementId: 4,
            totalPaisa: 1000000,
            ownerPaisa: 600000,
            cultivatorPaisa: 400000,
            settleDate: '2026-06-01',
            createdAt: '2026-06-01',
          ),
        ],
        {4: 'احمد — 60/40'},
      );
      expect(csv, contains('احمد — 60/40'));
      expect(csv, contains('10,000 روپے'));
      expect(csv, contains('6,000 روپے'));
      expect(csv, contains('4,000 روپے'));
      expect(csv, contains('2026-06-01'));
    });
  });

  group('computeFarmPnl', () {
    CropSeasonWithDetails season(int id) => CropSeasonWithDetails(
      cropSeason: CropSeason(
        id: id,
        fieldId: 1,
        cropName: 'Wheat',
        variety: 'Faisalabad-08',
        status: 'harvested',
        startDate: '2025-11-01',
      ),
      fields: const [],
      fieldNames: const ['f'],
      farmNames: const ['farm'],
      totalArea: 5,
    );

    test('matches the P&L screen math exactly, in integer paisa', () {
      // One season: activity-linked expense 1000 + direct expense 250
      // (same expense linked both ways counted once), harvest sold for
      // 5000 with 300 harvest expenses, ushr 200.
      final expenses = [
        Expense(
          id: 1,
          category: 'Fertilizer',
          amountPaisa: 100000,
          date: '2026-01-01',
          cropSeasonId: 10,
        ),
        Expense(
          id: 2,
          category: 'Seed',
          amountPaisa: 25000,
          date: '2026-01-02',
          cropSeasonId: 10,
        ),
        Expense(
          id: 3,
          category: 'Other',
          amountPaisa: 50000,
          date: '2026-01-03',
        ), // unlinked — overall only
      ];
      final activities = [
        ActivityWithDetails(
          activity: Activity(
            cropSeasonId: 10,
            activityType: 'sowing',
            date: '2026-01-01',
            expenseId: 1,
          ),
          expenseAmountPaisa: 100000,
          cropName: 'Wheat',
          fieldNames: const ['f'],
        ),
      ];
      final harvests = [
        HarvestWithDetails(
          harvest: Harvest(
            cropSeasonId: 10,
            quantity: 40,
            unit: 'من',
            date: '2026-05-01',
            transportationExpensePaisa: 30000,
          ),
          cropName: 'Wheat',
          fieldName: 'f',
          fieldSize: 5,
          farmName: 'farm',
          sale: Sale(
            harvestId: 1,
            quantity: 40,
            pricePerUnitPaisa: 12500,
            totalAmountPaisa: 500000,
            date: '2026-05-10',
          ),
        ),
      ];
      final ushr = [
        UshrWithDetails(
          ushrRecord: UshrRecord(
            cropSeasonId: 10,
            harvestQty: 40,
            marketValuePaisa: 500000,
            ushrMethod: 'rain',
            ushrPercentage: 10,
            ushrAmountPaisa: 20000,
            status: 'paid',
          ),
          cropName: 'Wheat',
          fieldName: 'f',
          farmName: 'farm',
          fieldSize: 5,
        ),
      ];

      final pnl = computeFarmPnl(
        harvests: harvests,
        totalExpensesPaisa: 175000,
        seasons: [season(10)],
        activities: activities,
        expenses: expenses,
        ushrRecords: ushr,
      );

      expect(pnl.totalSalesPaisa, 500000);
      expect(pnl.totalExpensesPaisa, 175000);
      expect(pnl.netPaisa, 325000);

      final crop = pnl.crops.single;
      // Expense 1 counted once despite both links (1000) + expense 2 (250).
      // Crop expenses = 125000 + harvest 30000 + ushr 20000 = 175000.
      expect(crop.incomePaisa, 500000);
      expect(crop.expensesPaisa, 175000);
      expect(crop.netPaisa, 325000);
    });

    test('unsold harvest contributes zero income', () {
      final pnl = computeFarmPnl(
        harvests: [
          HarvestWithDetails(
            harvest: Harvest(
              cropSeasonId: 5,
              quantity: 10,
              unit: 'من',
              date: '2026-05-01',
            ),
            cropName: 'Wheat',
            fieldName: 'f',
            fieldSize: 5,
            farmName: 'farm',
          ),
        ],
        totalExpensesPaisa: 0,
        seasons: [season(5)],
        activities: const [],
        expenses: const [],
        ushrRecords: const [],
      );
      expect(pnl.totalSalesPaisa, 0);
      expect(pnl.crops.single.incomePaisa, 0);
      expect(pnl.netPaisa, 0);
    });
  });
}
