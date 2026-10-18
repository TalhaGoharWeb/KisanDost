import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:kisan_dost/database/db_helper.dart';
import 'package:kisan_dost/providers/crop_provider.dart';
import 'package:kisan_dost/providers/expense_provider.dart';
import 'package:kisan_dost/providers/farm_provider.dart';
import 'package:kisan_dost/providers/harvest_provider.dart';

/// S6 regression (2026-10-18): editing a harvest whose 'Harvest Expenses'
/// mirror row was soft-deleted from the Expenses screen must NOT write the
/// new total onto the invisible deleted row. A fresh live expense row is
/// inserted and harvests.expense_id is repointed at it, so the harvest
/// card and the expense ledger can never disagree silently.
void main() {
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  TestWidgetsFlutterBinding.ensureInitialized();
  SharedPreferences.setMockInitialValues({});

  late Database db;
  late FarmProvider farms;
  late CropProvider crops;
  late ExpenseProvider expenses;
  late HarvestProvider harvests;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    db = await databaseFactoryFfi.openDatabase(inMemoryDatabasePath);
    await db.execute('PRAGMA foreign_keys = ON');
    await DatabaseHelper.instance.createFreshSchemaForTests(db);
    farms = FarmProvider(testExecutor: db);
    crops = CropProvider(testExecutor: db);
    expenses = ExpenseProvider(testExecutor: db);
    harvests = HarvestProvider(testExecutor: db);
  });

  tearDown(() async {
    await db.close();
  });

  /// Returns the crop season id of a fresh farm/field/season fixture.
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

  Future<int> addHarvestWithExpenses(int seasonId, int expensePaisa) async {
    await harvests.addHarvest(
      cropSeasonId: seasonId,
      quantity: 100,
      unit: 'kg',
      date: '2026-10-10',
      transportationExpensePaisa: expensePaisa,
    );
    final hwd = harvests.harvests.single;
    return hwd.harvest.id!;
  }

  Future<Map<String, Object?>> expenseRow(int id) async =>
      (await db.query('expenses', where: 'id = ?', whereArgs: [id])).single;

  test(
    'updateHarvest repoints to a fresh live expense row when the linked '
    'one was soft-deleted',
    () async {
      final seasonId = await seedSeason();
      final harvestId = await addHarvestWithExpenses(seasonId, 50000);
      final oldExpenseId = harvests.harvests.single.harvest.expenseId!;
      expect((await expenseRow(oldExpenseId))['deleted_at'], isNull);

      // The farmer soft-deletes the 'Harvest Expenses' mirror from the
      // Expenses screen.
      await expenses.deleteExpense(oldExpenseId);
      expect(
        (await expenseRow(oldExpenseId))['deleted_at'],
        isNotNull,
      );

      // Later the farmer edits the harvest with a new total.
      await harvests.updateHarvest(
        id: harvestId,
        cropSeasonId: seasonId,
        quantity: 100,
        unit: 'kg',
        date: '2026-10-10',
        transportationExpensePaisa: 90000,
      );

      // The soft-deleted row is untouched (still deleted).
      expect(
        (await expenseRow(oldExpenseId))['deleted_at'],
        isNotNull,
      );
      expect((await expenseRow(oldExpenseId))['amount_paisa'], 50000);

      // The harvest now points at a NEW live row with the new total.
      final newExpenseId = harvests.harvests.single.harvest.expenseId!;
      expect(newExpenseId, isNot(oldExpenseId));
      final newRow = await expenseRow(newExpenseId);
      expect(newRow['deleted_at'], isNull);
      expect(newRow['amount_paisa'], 90000);

      // The visible ledger agrees with the harvest card: exactly one live
      // row, carrying the new total.
      final live = await db.query(
        'expenses',
        where: 'deleted_at IS NULL',
      );
      expect(live, hasLength(1));
      expect(live.single['amount_paisa'], 90000);
    },
  );

  test(
    'updateHarvest still updates the live expense row in place (no churn '
    'when nothing was deleted)',
    () async {
      final seasonId = await seedSeason();
      final harvestId = await addHarvestWithExpenses(seasonId, 50000);
      final expenseId = harvests.harvests.single.harvest.expenseId!;

      await harvests.updateHarvest(
        id: harvestId,
        cropSeasonId: seasonId,
        quantity: 100,
        unit: 'kg',
        date: '2026-10-10',
        transportationExpensePaisa: 70000,
      );

      // Same row, updated in place — no fresh row inserted.
      expect(harvests.harvests.single.harvest.expenseId, expenseId);
      expect((await expenseRow(expenseId))['amount_paisa'], 70000);
      expect(await db.query('expenses'), hasLength(1));
    },
  );
}
