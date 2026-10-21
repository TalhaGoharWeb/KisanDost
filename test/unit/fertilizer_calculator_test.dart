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
        (r) => r.isOfficial && r.variantUr.contains('بارانی'),
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
}
