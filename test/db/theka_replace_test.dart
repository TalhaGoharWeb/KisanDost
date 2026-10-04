import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:kisan_dost/database/db_helper.dart';
import 'package:kisan_dost/models/models.dart';
import 'package:kisan_dost/providers/theka_provider.dart';

/// Atomicity tests for [ThekaProvider.replaceTheka].
///
/// The farmer-visible contract: editing a theka replaces the old contract
/// with the new one all-or-nothing. The edit form used to call
/// `deleteTheka` then `addTheka` as two separate provider calls — if the
/// insert failed after the delete succeeded, the contract and its
/// installments were unrecoverable. `replaceTheka` wraps both in a single
/// transaction.
void main() {
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  late Database db;
  late ThekaProvider thekas;
  late int farmId;

  Future<Database> openFreshDb() {
    return openDatabase(
      inMemoryDatabasePath,
      onConfigure: (db) async {
        await db.execute('PRAGMA foreign_keys = ON');
      },
    );
  }

  Theka thekaFor(int farm, int totalPaisa) => Theka(
    farmId: farm,
    totalAmountPaisa: totalPaisa,
    durationType: 'Seasonal',
    paymentMethod: 'Installment',
    createdAt: DateTime.now().toIso8601String(),
  );

  List<ThekaInstallment> twoInstallments(int totalPaisa) => [
    ThekaInstallment(
      thekaId: 0,
      amountPaisa: totalPaisa ~/ 2,
      dueDate: '2026-06-01',
      status: 'Pending',
    ),
    ThekaInstallment(
      thekaId: 0,
      amountPaisa: totalPaisa ~/ 2,
      dueDate: '2026-12-01',
      status: 'Pending',
    ),
  ];

  setUp(() async {
    db = await openFreshDb();
    await DatabaseHelper.instance.createFreshSchemaForTests(db);
    farmId = await db.insert('farms', {
      'name': 'ٹیسٹ فارم',
      'total_area': 5.0,
      'created_at': DateTime.now().toIso8601String(),
    });
    thekas = ThekaProvider(testExecutor: db);
  });

  tearDown(() async {
    await db.close();
  });

  test('replaceTheka swaps the contract and its installments atomically',
      () async {
    await thekas.addTheka(thekaFor(farmId, 200000), twoInstallments(200000));
    await thekas.fetchThekas();
    final oldId = thekas.thekas.single.id!;

    await thekas.replaceTheka(
      oldId,
      thekaFor(farmId, 300000),
      twoInstallments(300000),
    );
    await thekas.fetchThekas();

    // Exactly one theka: the new one. The old row and its installments
    // are gone, the new installments are linked to the new row.
    expect(thekas.thekas, hasLength(1));
    final kept = thekas.thekas.single;
    expect(kept.id, isNot(oldId));
    expect(kept.totalAmountPaisa, 300000);
    final insts = thekas.getInstallmentsForTheka(kept.id!);
    expect(insts, hasLength(2));
    expect(insts.map((i) => i.amountPaisa), [150000, 150000]);

    // No orphan installments point at the deleted theka.
    final orphans = await db.query(
      'theka_installments',
      where: 'theka_id = ?',
      whereArgs: [oldId],
    );
    expect(orphans, isEmpty);
  });

  test('replaceTheka rolls back when the insert fails: old contract kept',
      () async {
    await thekas.addTheka(thekaFor(farmId, 200000), twoInstallments(200000));
    await thekas.fetchThekas();
    final oldId = thekas.thekas.single.id!;

    // farmId 99999 violates the thekas.farm_id FK: the insert must throw,
    // and the single transaction must roll everything back.
    await expectLater(
      thekas.replaceTheka(
        oldId,
        thekaFor(99999, 300000),
        twoInstallments(300000),
      ),
      throwsA(isA<Exception>()),
    );
    await thekas.fetchThekas();

    // The old contract and both installments survive untouched.
    expect(thekas.thekas, hasLength(1));
    expect(thekas.thekas.single.id, oldId);
    expect(thekas.thekas.single.totalAmountPaisa, 200000);
    expect(thekas.getInstallmentsForTheka(oldId), hasLength(2));
  });

  test('replaceTheka on a theka with only pending installments', () async {
    // Mirrors the form's hasPayments guard: all pending, so no expenses
    // are linked and none are destroyed.
    await thekas.addTheka(thekaFor(farmId, 200000), twoInstallments(200000));
    await thekas.fetchThekas();
    final oldId = thekas.thekas.single.id!;

    await thekas.replaceTheka(
      oldId,
      thekaFor(farmId, 250000),
      twoInstallments(250000),
    );

    expect(await db.query('expenses'), isEmpty);
    await thekas.fetchThekas();
    expect(thekas.thekas.single.totalAmountPaisa, 250000);
  });
}
