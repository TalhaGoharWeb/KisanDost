import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:kisan_dost/database/db_helper.dart';
import 'package:kisan_dost/providers/crop_provider.dart';
import 'package:kisan_dost/providers/farm_provider.dart';
import 'package:kisan_dost/providers/harvest_provider.dart';
import 'package:kisan_dost/providers/ushr_provider.dart';

/// S7 regression (2026-10-18): an in-kind ushr payment must reduce the
/// linked harvest's remaining quantity — exactly once. Edits, deletes and
/// harvest-link changes re-adjust consistently; a no-op edit nets to zero
/// (never double-reduces).
///
/// The deduction is proportional: harvest.quantity × (qtyPaid / harvestQty).
/// The ushr record is self-consistent (market value = harvestQty × rate),
/// so the ratio is unit-agnostic: for the screen flow (من) it equals a
/// من→unit conversion, and it stays correct for harvest units a converter
/// cannot bridge.
///
/// D2 is covered at the provider boundary here too: an overpaying
/// addUshrRecord throws before any row is written.
///
/// Hand-computed reference: harvest 100 من, ushr basis 100 من @ Rs 3,500/من
/// → market value Rs 3,500,000 paisa 35,000,000; ushr 10% = 3,500,000 paisa.
/// In-kind 2 من → ratio 0.02 → deduct 2.0 من → 98.0 من.
void main() {
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  TestWidgetsFlutterBinding.ensureInitialized();
  SharedPreferences.setMockInitialValues({});

  late Database db;
  late FarmProvider farms;
  late CropProvider crops;
  late HarvestProvider harvests;
  late UshrProvider ushr;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    db = await databaseFactoryFfi.openDatabase(inMemoryDatabasePath);
    await db.execute('PRAGMA foreign_keys = ON');
    await DatabaseHelper.instance.createFreshSchemaForTests(db);
    farms = FarmProvider(testExecutor: db);
    crops = CropProvider(testExecutor: db);
    harvests = HarvestProvider(testExecutor: db);
    ushr = UshrProvider(testExecutor: db);
  });

  tearDown(() async {
    await db.close();
  });

  Future<int> seedSeason() async {
    await farms.addFarm('ٹیسٹ فارم', 5);
    final farmId =
        (await db.query('farms', columns: ['id'])).single['id'] as int;
    await farms.addField(farmId: farmId, name: 'ٹیسٹ کھیت', sizeAcres: 5);
    final fieldId =
        (await db.query('fields', columns: ['id'])).single['id'] as int;
    await crops.addCropSeason(
      fieldIds: [fieldId],
      cropName: 'گندم',
      variety: 'دیسی',
      startDate: '2026-10-01',
    );
    return (await db.query('crop_seasons', columns: ['id'])).single['id']
        as int;
  }

  Future<int> addHarvest(int seasonId, double qty, String unit) async {
    await harvests.addHarvest(
      cropSeasonId: seasonId,
      quantity: qty,
      unit: unit,
      date: '2026-10-10',
    );
    return (await db.query('harvests', orderBy: 'id DESC')).first['id'] as int;
  }

  Future<double> harvestQty(int harvestId) async =>
      ((await db.query(
                'harvests',
                columns: ['quantity'],
                where: 'id = ?',
                whereArgs: [harvestId],
              )).single['quantity'] as num)
          .toDouble();

  Future<int> addInKindUshr(
    int seasonId,
    int harvestId, {
    double qtyPaid = 2.0,
    double harvestQty = 100.0,
  }) async {
    await ushr.addUshrRecord(
      cropSeasonId: seasonId,
      harvestId: harvestId,
      harvestQty: harvestQty,
      marketValuePaisa: 35000000,
      ushrMethod: 'Natural',
      ushrPercentage: 10.0,
      ushrAmountPaisa: 3500000,
      status: 'Pending',
      payMethod: 'Crop',
      qtyPaid: qtyPaid,
      cashPaidPaisa: 0,
      ratePerUnitPaisa: 350000,
    );
    return (await db.query(
      'ushr_records',
      orderBy: 'id DESC',
    )).first['id'] as int;
  }

  Future<void> updateInKindUshr(
    int ushrId,
    int seasonId, {
    double qtyPaid = 2.0,
    double harvestQty = 100.0,
    int? harvestId,
  }) async {
    await ushr.updateUshrRecord(
      id: ushrId,
      cropSeasonId: seasonId,
      harvestId: harvestId,
      harvestQty: harvestQty,
      marketValuePaisa: 35000000,
      ushrMethod: 'Natural',
      ushrPercentage: 10.0,
      ushrAmountPaisa: 3500000,
      status: 'Pending',
      payMethod: 'Crop',
      qtyPaid: qtyPaid,
      cashPaidPaisa: 0,
      ratePerUnitPaisa: 350000,
    );
  }

  Future<bool> hasInKindMarker(int ushrId) async {
    final rows = await db.query(
      'audit_log',
      columns: ['id'],
      where: 'table_name = ? AND details LIKE ?',
      whereArgs: [
        'harvests',
        '%عشر جنس ایڈجسٹمنٹ — ریکارڈ #$ushrId —%',
      ],
    );
    return rows.isNotEmpty;
  }

  test('addUshrRecord deducts the in-kind share once (100 من → 98.0)', () async {
    final seasonId = await seedSeason();
    final harvestId = await addHarvest(seasonId, 100, 'من');

    final ushrId = await addInKindUshr(seasonId, harvestId);

    // 100 × (2/100) = 2.0 deducted, exactly once.
    expect(await harvestQty(harvestId), closeTo(98.0, 1e-9));
    // The paid mirror carries the in-kind value: 2 × 350,000 = 700,000.
    final expenses = await db.query('expenses');
    expect(expenses, hasLength(1));
    expect(expenses.single['amount_paisa'], 700000);
    // The audit marker records the S7-managed deduction.
    expect(await hasInKindMarker(ushrId), isTrue);
  });

  test('deduction is proportional for non-من harvest units (kg)', () async {
    final seasonId = await seedSeason();
    // 4000 kg = 100 من; the ushr record stays من-based (screen contract).
    final harvestId = await addHarvest(seasonId, 4000, 'کلوگرام');

    await addInKindUshr(seasonId, harvestId);

    // 4000 × (2/100) = 80 kg deducted → 3920 kg.
    expect(await harvestQty(harvestId), closeTo(3920.0, 1e-9));
  });

  test('updateUshrRecord adjusts by delta — a no-op edit never double-'
      'reduces', () async {
    final seasonId = await seedSeason();
    final harvestId = await addHarvest(seasonId, 100, 'من');
    final ushrId = await addInKindUshr(seasonId, harvestId);
    expect(await harvestQty(harvestId), closeTo(98.0, 1e-9));

    // 2 → 5 من: undo 2.0, deduct 5.0 → 95.0.
    await updateInKindUshr(ushrId, seasonId, qtyPaid: 5.0, harvestId: harvestId);
    expect(await harvestQty(harvestId), closeTo(95.0, 1e-9));

    // Same values again: undo 5.0, deduct 5.0 → still 95.0 (no drift).
    await updateInKindUshr(ushrId, seasonId, qtyPaid: 5.0, harvestId: harvestId);
    expect(await harvestQty(harvestId), closeTo(95.0, 1e-9));

    // 5 → 1 من: undo 5.0, deduct 1.0 → 99.0.
    await updateInKindUshr(ushrId, seasonId, qtyPaid: 1.0, harvestId: harvestId);
    expect(await harvestQty(harvestId), closeTo(99.0, 1e-9));
  });

  test('unlinking the harvest restores the deducted quantity', () async {
    final seasonId = await seedSeason();
    final harvestId = await addHarvest(seasonId, 100, 'من');
    final ushrId = await addInKindUshr(seasonId, harvestId);
    expect(await harvestQty(harvestId), closeTo(98.0, 1e-9));

    await updateInKindUshr(ushrId, seasonId, harvestId: null);

    expect(await harvestQty(harvestId), closeTo(100.0, 1e-9));
  });

  test('moving the link restores the old harvest and deducts the new one',
      () async {
    final seasonId = await seedSeason();
    final harvestA = await addHarvest(seasonId, 100, 'من');
    final harvestB = await addHarvest(seasonId, 50, 'من');
    final ushrId = await addInKindUshr(seasonId, harvestA);
    expect(await harvestQty(harvestA), closeTo(98.0, 1e-9));

    await updateInKindUshr(ushrId, seasonId, harvestId: harvestB);

    // A is whole again; B loses 50 × 0.02 = 1.0 → 49.0.
    expect(await harvestQty(harvestA), closeTo(100.0, 1e-9));
    expect(await harvestQty(harvestB), closeTo(49.0, 1e-9));
  });

  test('deleteUshrRecord restores the deducted quantity', () async {
    final seasonId = await seedSeason();
    final harvestId = await addHarvest(seasonId, 100, 'من');
    final ushrId = await addInKindUshr(seasonId, harvestId);
    expect(await harvestQty(harvestId), closeTo(98.0, 1e-9));

    await ushr.deleteUshrRecord(ushrId);

    expect(await harvestQty(harvestId), closeTo(100.0, 1e-9));
    expect(await db.query('ushr_records'), isEmpty);
  });

  test('legacy in-kind record: delete invents no grain; first managed edit '
      'deducts in full', () async {
    final seasonId = await seedSeason();
    final harvestId = await addHarvest(seasonId, 100, 'من');

    // A record created before the S7 deduction existed: no audit marker.
    final legacyId = await db.insert('ushr_records', {
      'crop_season_id': seasonId,
      'harvest_id': harvestId,
      'harvest_qty': 100.0,
      'market_value_paisa': 35000000,
      'ushr_method': 'Natural',
      'ushr_percentage': 10.0,
      'ushr_amount_paisa': 3500000,
      'status': 'Pending',
      'pay_method': 'Crop',
      'qty_paid': 2.0,
      'cash_paid_paisa': 0,
      'rate_per_unit_paisa': 350000,
    });
    expect(await hasInKindMarker(legacyId), isFalse);

    // Deleting restores nothing — the harvest was never reduced.
    await ushr.deleteUshrRecord(legacyId);
    expect(await harvestQty(harvestId), closeTo(100.0, 1e-9));

    // A second legacy record, now edited: the first S7-managed edit deducts
    // the FULL new share (3.0), not a delta off the never-deducted 2.0.
    final legacyId2 = await db.insert('ushr_records', {
      'crop_season_id': seasonId,
      'harvest_id': harvestId,
      'harvest_qty': 100.0,
      'market_value_paisa': 35000000,
      'ushr_method': 'Natural',
      'ushr_percentage': 10.0,
      'ushr_amount_paisa': 3500000,
      'status': 'Pending',
      'pay_method': 'Crop',
      'qty_paid': 2.0,
      'cash_paid_paisa': 0,
      'rate_per_unit_paisa': 350000,
    });
    await updateInKindUshr(
      legacyId2,
      seasonId,
      qtyPaid: 3.0,
      harvestId: harvestId,
    );
    expect(await harvestQty(harvestId), closeTo(97.0, 1e-9));
    expect(await hasInKindMarker(legacyId2), isTrue);

    // …and its delete restores exactly what was deducted.
    await ushr.deleteUshrRecord(legacyId2);
    expect(await harvestQty(harvestId), closeTo(100.0, 1e-9));
  });

  test('D2: overpaying addUshrRecord throws and writes nothing', () async {
    final seasonId = await seedSeason();
    final harvestId = await addHarvest(seasonId, 100, 'من');

    // 3,000,000 cash + 2 × 350,000 in-kind = 3,700,000 > 3,500,000 due.
    await expectLater(
      () => ushr.addUshrRecord(
        cropSeasonId: seasonId,
        harvestId: harvestId,
        harvestQty: 100.0,
        marketValuePaisa: 35000000,
        ushrMethod: 'Natural',
        ushrPercentage: 10.0,
        ushrAmountPaisa: 3500000,
        status: 'Pending',
        payMethod: 'Mixed',
        qtyPaid: 2.0,
        cashPaidPaisa: 3000000,
        ratePerUnitPaisa: 350000,
      ),
      throwsA(isA<Exception>()),
    );

    // Atomic: no ushr row, no expense mirror, harvest untouched.
    expect(await db.query('ushr_records'), isEmpty);
    expect(await db.query('expenses'), isEmpty);
    expect(await harvestQty(harvestId), closeTo(100.0, 1e-9));
  });

  test('in-kind share larger than the harvest basis is rejected', () async {
    final seasonId = await seedSeason();
    final harvestId = await addHarvest(seasonId, 100, 'من');

    // qtyPaid 120 > harvestQty 100 → ratio 1.2 → would overdraw.
    await expectLater(
      () => ushr.addUshrRecord(
        cropSeasonId: seasonId,
        harvestId: harvestId,
        harvestQty: 100.0,
        marketValuePaisa: 35000000,
        ushrMethod: 'Natural',
        ushrPercentage: 10.0,
        ushrAmountPaisa: 3500000,
        status: 'Pending',
        payMethod: 'Crop',
        qtyPaid: 120.0,
        cashPaidPaisa: 0,
        ratePerUnitPaisa: 29000, // keeps D2 quiet: 120 × 29,000 < 3,500,000
      ),
      throwsA(
        isA<Exception>().having(
          (e) => e.toString(),
          'message',
          contains('زیادہ ہے'),
        ),
      ),
    );

    expect(await db.query('ushr_records'), isEmpty);
    expect(await harvestQty(harvestId), closeTo(100.0, 1e-9));
  });
}
