import 'package:flutter_test/flutter_test.dart';
import 'package:kisan_dost/data/fertilizer_data.dart';
import 'package:kisan_dost/services/area_unit.dart';
import 'package:kisan_dost/services/fertilizer_calculator.dart';

void main() {
  final urea = productById('urea');
  final dap = productById('dap');
  final ssp = productById('ssp');
  final sop = productById('sop');

  group('AreaConverter', () {
    test('1 acre = 8 kanal = 160 marla', () {
      expect(AreaConverter.convert(1, AreaUnit.acre, AreaUnit.kanal), 8);
      expect(AreaConverter.convert(1, AreaUnit.acre, AreaUnit.marla), 160);
      expect(AreaConverter.convert(20, AreaUnit.marla, AreaUnit.kanal), 1);
      expect(AreaConverter.toAcres(4, AreaUnit.kanal), 0.5);
    });

    test('roundtrip acre -> kanal -> acre', () {
      final k = AreaConverter.convert(2.5, AreaUnit.acre, AreaUnit.kanal);
      expect(AreaConverter.convert(k, AreaUnit.kanal, AreaUnit.acre), 2.5);
    });
  });

  group('FertilizerCalculator — official wheat (irrigated)', () {
    // Agriculture Dept Punjab, Pocket Book 2022 (soil-average):
    // N 57, P2O5 46, K2O 25 kg/acre.
    final target = const Nutrients(n: 57, p2o5: 46, k2o: 25);

    test('meets the official nutrient target exactly', () {
      final plan = FertilizerCalculator.buildPlan(
        targetPerAcre: target,
        areaAcres: 1,
        phosphorusSource: dap,
        nitrogenSource: urea,
        potashSource: sop,
      );
      final dapAmt = plan.products.firstWhere((a) => a.product.id == 'dap');
      final ureaAmt = plan.products.firstWhere((a) => a.product.id == 'urea');
      final sopAmt = plan.products.firstWhere((a) => a.product.id == 'sop');
      expect(dapAmt.kgPerAcre, closeTo(100, 0.01)); // 2 bags for 46 kg P2O5
      // Remaining N = 57 - 18 (from DAP) = 39 kg -> 39/0.46 kg urea.
      expect(ureaAmt.kgPerAcre, closeTo(39 / 0.46, 0.01));
      expect(sopAmt.kgPerAcre, closeTo(50, 0.01)); // 1 bag
      expect(plan.remainingPerAcre.isNegligible(), isTrue);
    });

    test('no double counting: DAP nitrogen counts toward the N target', () {
      final plan = FertilizerCalculator.buildPlan(
        targetPerAcre: target,
        areaAcres: 1,
        phosphorusSource: dap,
        nitrogenSource: urea,
      );
      // DAP 100 kg supplies 18 kg N, so urea only needs to add 39 kg N.
      final ureaAmt = plan.products.firstWhere((a) => a.product.id == 'urea');
      expect(ureaAmt.nutrientsPerAcre.n, closeTo(39, 0.01));
      expect(plan.suppliedPerAcre.n, closeTo(57, 0.01));
    });

    test('scales to a 3.5 acre field and rounds bags to halves', () {
      final plan = FertilizerCalculator.buildPlan(
        targetPerAcre: target,
        areaAcres: 3.5,
        phosphorusSource: dap,
        nitrogenSource: urea,
        potashSource: sop,
      );
      final dapAmt = plan.products.firstWhere((a) => a.product.id == 'dap');
      expect(dapAmt.totalKg(3.5), closeTo(350, 0.01));
      expect(dapAmt.bagsFor(3.5), 7.0);
    });
  });
  group('FertilizerCalculator — barani wheat (low rainfall)', () {
    test('reproduces 1 bag DAP + 1 bag urea + half bag SOP', () {
      final plan = FertilizerCalculator.buildPlan(
        targetPerAcre: const Nutrients(n: 32, p2o5: 23, k2o: 12.5),
        areaAcres: 1,
        phosphorusSource: dap,
        nitrogenSource: urea,
        potashSource: sop,
      );
      expect(
        plan.products.firstWhere((a) => a.product.id == 'dap').kgPerAcre,
        closeTo(50, 0.01),
      );
      expect(
        plan.products.firstWhere((a) => a.product.id == 'urea').kgPerAcre,
        closeTo(50, 0.01),
      );
      expect(
        plan.products.firstWhere((a) => a.product.id == 'sop').kgPerAcre,
        closeTo(25, 0.01),
      );
    });
  });

  group('FertilizerCalculator — combinations and edge cases', () {
    test('SSP combination supplies no nitrogen from the P source', () {
      final plan = FertilizerCalculator.buildPlan(
        targetPerAcre: const Nutrients(n: 64, p2o5: 46, k2o: 25),
        areaAcres: 1,
        phosphorusSource: ssp,
        nitrogenSource: urea,
        potashSource: sop,
      );
      final sspAmt = plan.products.firstWhere((a) => a.product.id == 'ssp');
      final ureaAmt = plan.products.firstWhere((a) => a.product.id == 'urea');
      expect(sspAmt.kgPerAcre, closeTo(46 / 0.18, 0.1)); // ~255.6 kg
      // All 64 kg N must come from urea when SSP is the P source.
      expect(ureaAmt.nutrientsPerAcre.n, closeTo(64, 0.01));
    });

    test('compareCombinations returns one plan per P source', () {
      final plans = FertilizerCalculator.compareCombinations(
        targetPerAcre: const Nutrients(n: 64, p2o5: 46, k2o: 25),
        areaAcres: 2,
        phosphorusSources: [dap, ssp],
        nitrogenSource: urea,
        potashSource: sop,
      );
      expect(plans.length, 2);
      for (final p in plans) {
        expect(p.remainingPerAcre.isNegligible(), isTrue);
      }
    });

    test('excess nitrogen from P source adds no urea and reports excess', () {
      // Very high P target with DAP overshoots a small N target.
      final plan = FertilizerCalculator.buildPlan(
        targetPerAcre: const Nutrients(n: 5, p2o5: 46),
        areaAcres: 1,
        phosphorusSource: dap,
        nitrogenSource: urea,
      );
      expect(plan.products.where((a) => a.product.id == 'urea'), isEmpty);
      expect(plan.remainingPerAcre.n, lessThan(0)); // excess, not hidden
    });

    test('cost uses rounded bags and skips unpriced products', () {
      final plan = FertilizerCalculator.buildPlan(
        targetPerAcre: const Nutrients(n: 64, p2o5: 46, k2o: 25),
        areaAcres: 1,
        phosphorusSource: dap,
        nitrogenSource: urea,
        potashSource: sop,
      );
      // DAP Rs 14,500/bag, urea Rs 4,500/bag, SOP unpriced.
      final cost = plan.totalCostPaisa({
        'dap': 1450000,
        'urea': 450000,
      });
      expect(cost, 2 * 1450000 + 2 * 450000);
    });

    test('zero or negative area throws', () {
      expect(
        () => FertilizerCalculator.buildPlan(
          targetPerAcre: const Nutrients(n: 10),
          areaAcres: 0,
          phosphorusSource: dap,
          nitrogenSource: urea,
        ),
        throwsArgumentError,
      );
    });

    test('per-kanal: 1 acre plan divided by 8 kanal', () {
      final plan = FertilizerCalculator.buildPlan(
        targetPerAcre: const Nutrients(n: 64, p2o5: 46, k2o: 25),
        areaAcres: 1,
        phosphorusSource: dap,
        nitrogenSource: urea,
        potashSource: sop,
      );
      final dapPerKanal =
          plan.products.firstWhere((a) => a.product.id == 'dap').kgPerAcre / 8;
      expect(dapPerKanal, closeTo(12.5, 0.01));
    });
  });

  group('Seeded recommendations are self-consistent', () {
    test('barani entries reproduce the department press-release bags', () {
      // Barani doses come from the department's Oct 2026 press release
      // in BAGS, so the calculator must hand those exact bags back.
      for (final rec in kCropRecommendations.where(
        (r) =>
            r.isOfficial &&
            r.cropUr == 'گندم' &&
            r.variantUr.contains('بارانی') &&
            r.sourceUr.contains('اعلامیہ'),
      )) {
        final plan = FertilizerCalculator.buildPlan(
          targetPerAcre: rec.targetPerAcre!,
          areaAcres: 1,
          phosphorusSource: dap,
          nitrogenSource: urea,
          potashSource: sop,
        );
        expect(
          plan.remainingPerAcre.isNegligible(),
          isTrue,
          reason: '${rec.cropUr} ${rec.variantUr} should meet its target',
        );
        for (final a in plan.products) {
          final bags = a.exactBagsFor(1);
          expect(
            (bags * 4) % 1,
            closeTo(0, 0.01),
            reason:
                '${rec.variantUr}: ${a.product.id} should be whole/quarter bags',
          );
        }
      }
    });

    test('stage fractions sum to 1 per nutrient role', () {
      for (final rec in kCropRecommendations) {
        var p = 0.0, n = 0.0, k = 0.0;
        for (final s in rec.stages) {
          p += s.phosphorusFraction;
          n += s.nitrogenFraction;
          k += s.potashFraction;
        }
        if (rec.targetPerAcre!.p2o5 > 0) expect(p, closeTo(1, 0.001));
        if (rec.targetPerAcre!.n > 0) expect(n, closeTo(1, 0.001));
        if (rec.targetPerAcre!.k2o > 0) expect(k, closeTo(1, 0.001));
      }
    });
  });

  group('FertilizerCalculator — full 36-combination grid (1.0.9)', () {
    final target = const Nutrients(n: 57, p2o5: 46, k2o: 25);
    List<FertilizerCombination> grid() =>
        FertilizerCalculator.allCombinations(
          targetPerAcre: target,
          areaAcres: 1,
          phosphorusSources: [
            for (final id in kPhosphorusSourceIds) productById(id),
          ],
          nitrogenSources: [
            for (final id in kNitrogenSourceIds) productById(id),
          ],
          potashOptions: [for (final id in kPotashSourceIds) productById(id)],
        );

    test('grid is 6 P x 3 N x 2 K = 36 combinations', () {
      expect(kPhosphorusSourceIds, ['dap', 'np', 'ssp', 'map', 'tsp', 'npk']);
      expect(kNitrogenSourceIds, ['urea', 'can', 'amsul']);
      expect(kPotashSourceIds, ['sop', 'mop']);
      expect(grid().length, 36);
    });

    test('every combination meets the nutrient target', () {
      for (final combo in grid()) {
        final r = combo.result.remainingPerAcre;
        if (combo.phosphorusSource.id == 'npk') {
          // NPK 17-17-17 brings potash with its phosphorus: N and P
          // meet exactly, potash may legitimately exceed the target
          // (the excess is reported to the farmer, never hidden).
          expect(r.n.abs(), lessThan(0.05), reason: combo.labelUr);
          expect(r.p2o5.abs(), lessThan(0.05), reason: combo.labelUr);
          expect(r.k2o, lessThan(0.05), reason: combo.labelUr);
        } else {
          expect(r.isNegligible(), isTrue, reason: combo.labelUr);
        }
      }
    });

    test('MAP credits its own nitrogen (11%) before topping up', () {
      final plan = FertilizerCalculator.buildPlan(
        targetPerAcre: target,
        areaAcres: 1,
        phosphorusSource: productById('map'),
        nitrogenSource: urea,
        potashSource: sop,
      );
      final mapAmt = plan.products.firstWhere((a) => a.product.id == 'map');
      final ureaAmt = plan.products.firstWhere((a) => a.product.id == 'urea');
      expect(mapAmt.kgPerAcre, closeTo(46 / 0.52, 0.01)); // ~88.5 kg
      // MAP supplies 46/0.52 x 11% = ~9.73 kg N; urea adds the rest.
      expect(ureaAmt.kgPerAcre, closeTo((57 - 46 / 0.52 * 0.11) / 0.46, 0.01));
    });

    test('TSP carries no nitrogen — the N source carries it all', () {
      final plan = FertilizerCalculator.buildPlan(
        targetPerAcre: target,
        areaAcres: 1,
        phosphorusSource: productById('tsp'),
        nitrogenSource: urea,
        potashSource: sop,
      );
      final tspAmt = plan.products.firstWhere((a) => a.product.id == 'tsp');
      final ureaAmt = plan.products.firstWhere((a) => a.product.id == 'urea');
      expect(tspAmt.kgPerAcre, closeTo(100, 0.01)); // 46 / 0.46
      expect(ureaAmt.kgPerAcre, closeTo(57 / 0.46, 0.01));
    });

    test('CAN (26% N) and ammonium sulphate (21% N) top up correctly', () {
      for (final (id, pct) in [('can', 0.26), ('amsul', 0.21)]) {
        final plan = FertilizerCalculator.buildPlan(
          targetPerAcre: target,
          areaAcres: 1,
          phosphorusSource: dap,
          nitrogenSource: productById(id),
          potashSource: sop,
        );
        final amt = plan.products.firstWhere((a) => a.product.id == id);
        // DAP credits 18 kg N; the remaining 39 kg comes from the source.
        expect(amt.kgPerAcre, closeTo(39 / pct, 0.01), reason: id);
        expect(plan.suppliedPerAcre.n, closeTo(57, 0.01), reason: id);
      }
    });

    test('rankByCost puts the cheapest fully-priced combo first', () {
      // Prices (paisa/bag) chosen so SSP+AMSUL+MOP is cheapest and
      // DAP+UREA+SOP is among the dearest.
      final prices = <String, int>{
        'dap': 1660000, 'np': 1050000, 'ssp': 460000, 'map': 1350000,
        'tsp': 900000, 'npk': 1140000, 'urea': 470000, 'can': 400000,
        'amsul': 460000, 'sop': 1460000, 'mop': 900000,
      };
      final ranked = FertilizerCalculator.rankByCost(grid(), prices);
      expect(ranked.length, 36);
      final costs = [
        for (final c in ranked) c.result.totalCostPaisa(prices),
      ];
      for (var i = 1; i < costs.length; i++) {
        expect(costs[i], greaterThanOrEqualTo(costs[i - 1]));
      }
    });

    test('rankByCost keeps unpriced combinations after priced ones', () {
      final ranked = FertilizerCalculator.rankByCost(grid(), {
        'dap': 1660000, 'urea': 470000, 'sop': 1460000,
      });
      // Only DAP+UREA+SOP is fully priced, so it must come first.
      expect(ranked.first.labelUr, contains('ڈی اے پی'));
      expect(ranked.first.nitrogenSource.id, 'urea');
      expect(ranked.first.potashSource!.id, 'sop');
    });
  });
  group('NPK 17-17-17 as phosphorus source — potash never double-counted', () {
    test('NPK potash credit tops up only the remaining potash', () {
      // Target K 60: NPK for P 46 supplies 46 kg K; SOP adds only 14.
      final plan = FertilizerCalculator.buildPlan(
        targetPerAcre: const Nutrients(n: 57, p2o5: 46, k2o: 60),
        areaAcres: 1,
        phosphorusSource: productById('npk'),
        nitrogenSource: productById('urea'),
        potashSource: productById('sop'),
      );
      final npkAmt = plan.products.firstWhere((a) => a.product.id == 'npk');
      final sopAmt = plan.products.firstWhere((a) => a.product.id == 'sop');
      expect(npkAmt.kgPerAcre, closeTo(46 / 0.17, 0.01));
      expect(sopAmt.kgPerAcre, closeTo(14 / 0.5, 0.01));
      expect(plan.suppliedPerAcre.k2o, closeTo(60, 0.01));
      expect(plan.remainingPerAcre.isNegligible(), isTrue);
    });

    test('NPK potash excess is reported, and no SOP is added', () {
      final plan = FertilizerCalculator.buildPlan(
        targetPerAcre: const Nutrients(n: 57, p2o5: 46, k2o: 25),
        areaAcres: 1,
        phosphorusSource: productById('npk'),
        nitrogenSource: productById('urea'),
        potashSource: productById('sop'),
      );
      expect(plan.products.where((a) => a.product.id == 'sop'), isEmpty);
      expect(plan.remainingPerAcre.k2o, lessThan(0)); // 46 supplied vs 25 target
    });
  });

  group('SFRI soil-test formulas (FRM)', () {
    test('wheat at OM 0.7, P 7 ppm, K 100 ppm', () {
      final t = sfriSoilTestTarget(
        'wheat',
        organicMatterPct: 0.7,
        phosphorusPpm: 7,
        potassiumPpm: 100,
      );
      expect(t.n, closeTo(((0.7 * -24.9) + 69.8) * 2.5 / 2.47, 0.01));
      expect(t.p2o5, closeTo(((7 * -1.18) + 46.5) * 2.5 / 2.47, 0.01));
      expect(t.k2o, closeTo((-0.23 * 100) + 41.73, 0.01));
    });

    test('wheat potash bands: rich soil needs no potash', () {
      final t = sfriSoilTestTarget(
        'wheat',
        organicMatterPct: 0.7,
        phosphorusPpm: 7,
        potassiumPpm: 200,
      );
      expect(t.k2o, 0);
      final t2 = sfriSoilTestTarget(
        'wheat',
        organicMatterPct: 0.7,
        phosphorusPpm: 7,
        potassiumPpm: 50,
      );
      expect(t2.k2o, 24);
    });

    test('negative formula results clamp to zero (very rich soil)', () {
      final t = sfriSoilTestTarget(
        'maize',
        organicMatterPct: 0.8,
        phosphorusPpm: 60,
        potassiumPpm: 100,
      );
      expect(t.p2o5, 0);
    });

    test('rice and sugarcane formulas produce sane acre doses', () {
      final rice = sfriSoilTestTarget(
        'rice',
        organicMatterPct: 0.7,
        phosphorusPpm: 7,
        potassiumPpm: 100,
      );
      expect(rice.n, closeTo(((1.5 - 0.7) * 17.52) + 35.2, 0.01));
      final cane = sfriSoilTestTarget(
        'sugarcane',
        organicMatterPct: 0.6,
        phosphorusPpm: 6,
        potassiumPpm: 120,
      );
      expect(cane.n, closeTo(((0.7 - 0.6) * 68) + 100, 0.01));
    });
  });

  group('SFRI fixed-dose seed data', () {
    test('SFRI entries exist for the previously-uncovered crops', () {
      Nutrients doseOf(String cropUr) => kCropRecommendations
          .firstWhere((r) => r.cropUr == cropUr && r.sourceUr.contains('SFRI'))
          .targetPerAcre!;
      expect(doseOf('سورج مکھی').n, 48);
      expect(doseOf('آلو').n, 100);
      expect(doseOf('آلو').k2o, 50);
      expect(doseOf('سرسوں / کینولا').p2o5, 30);
      expect(kCropsWithoutVerifiedDose, isEmpty);
    });
  });
  group('Budget fitting (SFRI cash-in-hand model)', () {
    final target = const Nutrients(n: 57, p2o5: 46, k2o: 25);
    final prices = <String, int>{
      'dap': 1660000, 'np': 1050000, 'ssp': 460000, 'map': 1350000,
      'tsp': 900000, 'npk': 1140000, 'urea': 470000, 'can': 400000,
      'amsul': 460000, 'sop': 1460000, 'mop': 900000,
    };
    List<FertilizerCombination> grid() =>
        FertilizerCalculator.allCombinations(
          targetPerAcre: target,
          areaAcres: 1,
          phosphorusSources: [
            for (final id in kPhosphorusSourceIds) productById(id),
          ],
          nitrogenSources: [
            for (final id in kNitrogenSourceIds) productById(id),
          ],
          potashOptions: [for (final id in kPotashSourceIds) productById(id)],
        );
    List<BudgetPlanOption> fit(int budgetPaisa) =>
        FertilizerCalculator.fitCombinationsToBudget(
          targetPerAcre: target,
          areaAcres: 1,
          combinations: grid(),
          pricePerBagPaisaById: prices,
          budgetPaisa: budgetPaisa,
        );

    test('generous budget: all options full-dose, cheapest first', () {
      final options = fit(100000 * 100);
      expect(options.length, 36);
      expect(options.every((o) => o.scale == 1.0), isTrue);
      for (var i = 1; i < options.length; i++) {
        expect(options[i].costPaisa, greaterThanOrEqualTo(options[i - 1].costPaisa));
      }
    });

    test('tight budget: best option is scaled, within budget, balanced', () {
      final cheapestFull = fit(100000 * 100).first.costPaisa;
      final budget = (cheapestFull * 0.6).round();
      final options = fit(budget);
      expect(options, isNotEmpty);
      final best = options.first;
      expect(best.scale, lessThan(1.0));
      expect(best.scale, greaterThan(0.4));
      expect(best.costPaisa, lessThanOrEqualTo(budget));
      // Balanced: nitrogen and phosphorus are delivered at the same
      // fraction of the full target (bag rounding aside).
      final s = best.result.suppliedPerAcre;
      expect(s.n / 57, closeTo(s.p2o5 / 46, 0.03));
      expect(s.n / 57, closeTo(best.scale, 0.03));
    });

    test('unpriced products exclude their combinations', () {
      final partial = Map<String, int>.from(prices)..remove('npk');
      final options = FertilizerCalculator.fitCombinationsToBudget(
        targetPerAcre: target,
        areaAcres: 1,
        combinations: grid(),
        pricePerBagPaisaById: partial,
        budgetPaisa: 100000 * 100,
      );
      expect(options.any((o) => o.combination.phosphorusSource.id == 'npk'), isFalse);
      expect(options.length, 30);
    });

    test('hopeless budget: no options', () {
      expect(fit(100 * 100), isEmpty);
    });
  });
}
