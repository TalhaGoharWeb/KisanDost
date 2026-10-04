import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:kisan_dost/database/db_helper.dart';
import 'package:kisan_dost/providers/crop_provider.dart';
import 'package:kisan_dost/providers/farm_provider.dart';

/// Hermetic tests for crop-season ↔ field relationships using the REAL
/// production schema. The app singleton is never touched.
///
/// What "correct" means, from the farmer's point of view:
/// * a crop season links to exactly the fields the farmer picked;
/// * a season cannot be created with no fields (rejected loudly);
/// * linking the same field twice does not duplicate it;
/// * deleting a season removes its links but keeps the fields themselves.
void main() {
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  Future<Database> openFreshDb() async {
    final db = await openDatabase(
      inMemoryDatabasePath,
      onConfigure: (db) async {
        await db.execute('PRAGMA foreign_keys = ON');
      },
    );
    await DatabaseHelper.instance.createFreshSchemaForTests(db);
    return db;
  }

  /// Creates a farm with two fields; returns (farmId, [fieldId1, fieldId2]).
  Future<(int, List<int>)> seedFarmWithFields(Database db) async {
    final farms = FarmProvider(testExecutor: db);
    await farms.addFarm('Test Farm', 10.0);
    final farmId = farms.farms.first.id!;
    await farms.addField(farmId: farmId, name: 'Plot A', sizeAcres: 4.0);
    await farms.addField(farmId: farmId, name: 'Plot B', sizeAcres: 6.0);
    await farms.fetchFields(farmId);
    final ids = farms.getFieldsForFarm(farmId).map((f) => f.id!).toList();
    return (farmId, ids);
  }

  group('crop season ↔ field relationships', () {
    test('season links to exactly the chosen fields', () async {
      final db = await openFreshDb();
      final (_, fieldIds) = await seedFarmWithFields(db);
      final crops = CropProvider(testExecutor: db);

      await crops.addCropSeason(
        fieldIds: fieldIds,
        cropName: 'Wheat',
        variety: 'Galaxy-13',
        startDate: '2026-11-01',
      );

      expect(crops.activeCropSeasons, hasLength(1));
      final seasonId = crops.activeCropSeasons.first.cropSeason.id!;
      final links = await db.query(
        'crop_season_fields',
        where: 'crop_season_id = ?',
        whereArgs: [seasonId],
      );
      expect(links, hasLength(2));
      final linkedFieldIds = links.map((l) => l['field_id']).toSet();
      expect(linkedFieldIds, fieldIds.toSet());
      await db.close();
    });

    test('season with no fields is rejected loudly', () async {
      final db = await openFreshDb();
      final crops = CropProvider(testExecutor: db);

      expect(
        () => crops.addCropSeason(
          fieldIds: [],
          cropName: 'Wheat',
          variety: 'Galaxy-13',
          startDate: '2026-11-01',
        ),
        throwsArgumentError,
      );

      expect(crops.activeCropSeasons, isEmpty);
      await db.close();
    });

    test('linking the same field twice does not duplicate it', () async {
      final db = await openFreshDb();
      final (_, fieldIds) = await seedFarmWithFields(db);
      final crops = CropProvider(testExecutor: db);

      await crops.addCropSeason(
        fieldIds: [fieldIds.first, fieldIds.first],
        cropName: 'Cotton',
        variety: 'FH-142',
        startDate: '2026-05-01',
      );

      final seasonId = crops.activeCropSeasons.first.cropSeason.id!;
      final links = await db.query(
        'crop_season_fields',
        where: 'crop_season_id = ?',
        whereArgs: [seasonId],
      );
      // UNIQUE(crop_season_id, field_id) + ConflictAlgorithm.ignore.
      expect(links, hasLength(1));
      await db.close();
    });

    test('linking a non-existent field is rejected (FK)', () async {
      final db = await openFreshDb();
      final crops = CropProvider(testExecutor: db);

      expect(
        () => crops.addCropSeason(
          fieldIds: [999999],
          cropName: 'Wheat',
          variety: 'Galaxy-13',
          startDate: '2026-11-01',
        ),
        throwsA(anyOf([isA<DatabaseException>(), isA<Exception>()])),
      );
      await db.close();
    });

    test('deleting a season removes its links but keeps the fields', () async {
      final db = await openFreshDb();
      final (_, fieldIds) = await seedFarmWithFields(db);
      final crops = CropProvider(testExecutor: db);

      await crops.addCropSeason(
        fieldIds: fieldIds,
        cropName: 'Wheat',
        variety: 'Galaxy-13',
        startDate: '2026-11-01',
      );
      final seasonId = crops.activeCropSeasons.first.cropSeason.id!;
      await crops.deleteCropSeason(seasonId);

      final links = await db.query('crop_season_fields');
      expect(links, isEmpty);
      final fields = await db.query('fields');
      expect(fields, hasLength(2));
      await db.close();
    });
  });
}
