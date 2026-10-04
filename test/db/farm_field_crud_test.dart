import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:kisan_dost/database/db_helper.dart';
import 'package:kisan_dost/providers/farm_provider.dart';

/// Hermetic CRUD tests for farms and fields using the REAL production schema
/// ([DatabaseHelper.createFreshSchemaForTests]) against an in-memory FFI
/// database. The app singleton is never touched.
///
/// What "correct" means, from the farmer's point of view:
/// * a farm and its fields are saved and listed back exactly;
/// * a field always belongs to a real farm (FK enforced — no orphan fields);
/// * deleting a farm removes its fields too (ON DELETE CASCADE), so no
///   ghost fields linger in the UI.
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

  group('farms CRUD', () {
    test('addFarm persists and lists the farm', () async {
      final db = await openFreshDb();
      final farms = FarmProvider(testExecutor: db);

      await farms.addFarm('Chak 44 Farm', 12.5);
      expect(farms.farms, hasLength(1));
      expect(farms.farms.first.name, 'Chak 44 Farm');
      expect(farms.farms.first.totalArea, 12.5);
      await db.close();
    });

    test('updateFarm changes name and area', () async {
      final db = await openFreshDb();
      final farms = FarmProvider(testExecutor: db);

      await farms.addFarm('Old Name', 5.0);
      final id = farms.farms.first.id!;
      await farms.updateFarm(id, 'New Name', 7.25);

      expect(farms.farms, hasLength(1));
      expect(farms.farms.first.name, 'New Name');
      expect(farms.farms.first.totalArea, 7.25);
      await db.close();
    });

    test('deleteFarm removes the farm', () async {
      final db = await openFreshDb();
      final farms = FarmProvider(testExecutor: db);

      await farms.addFarm('Temp Farm', 3.0);
      final id = farms.farms.first.id!;
      await farms.deleteFarm(id);

      expect(farms.farms, isEmpty);
      await db.close();
    });
  });

  group('fields CRUD + farm relationship', () {
    test('addField links the field to its farm', () async {
      final db = await openFreshDb();
      final farms = FarmProvider(testExecutor: db);

      await farms.addFarm('Main Farm', 10.0);
      final farmId = farms.farms.first.id!;
      await farms.addField(farmId: farmId, name: 'North Plot', sizeAcres: 4.0);

      await farms.fetchFields(farmId);
      final fields = farms.getFieldsForFarm(farmId);
      expect(fields, hasLength(1));
      expect(fields.first.name, 'North Plot');
      expect(fields.first.farmId, farmId);
      await db.close();
    });

    test('field with a non-existent farm_id is rejected (no orphan fields)',
        () async {
      final db = await openFreshDb();

      // Bypass the provider to prove the DB itself enforces the relationship.
      expect(
        () => db.insert('fields', {
          'farm_id': 999999,
          'name': 'Ghost Plot',
          'size_acres': 1.0,
        }),
        throwsA(isA<DatabaseException>()),
      );
      await db.close();
    });

    test('deleteFarm cascades to its fields (no ghost fields)', () async {
      final db = await openFreshDb();
      final farms = FarmProvider(testExecutor: db);

      await farms.addFarm('Doomed Farm', 8.0);
      final farmId = farms.farms.first.id!;
      await farms.addField(farmId: farmId, name: 'Plot A', sizeAcres: 3.0);
      await farms.addField(farmId: farmId, name: 'Plot B', sizeAcres: 5.0);

      await farms.deleteFarm(farmId);

      final remaining =
          await db.query('fields', where: 'farm_id = ?', whereArgs: [farmId]);
      expect(remaining, isEmpty);
      await db.close();
    });

    test('updateField changes the plot details', () async {
      final db = await openFreshDb();
      final farms = FarmProvider(testExecutor: db);

      await farms.addFarm('Farm', 10.0);
      final farmId = farms.farms.first.id!;
      await farms.addField(farmId: farmId, name: 'Plot', sizeAcres: 2.0);
      await farms.fetchFields(farmId);
      final fieldId = farms.getFieldsForFarm(farmId).first.id!;

      await farms.updateField(
        id: fieldId,
        farmId: farmId,
        name: 'Renamed Plot',
        sizeAcres: 2.5,
      );

      final updated = farms.getFieldsForFarm(farmId).first;
      expect(updated.name, 'Renamed Plot');
      expect(updated.sizeAcres, 2.5);
      await db.close();
    });

    test('deleteField removes only that field', () async {
      final db = await openFreshDb();
      final farms = FarmProvider(testExecutor: db);

      await farms.addFarm('Farm', 10.0);
      final farmId = farms.farms.first.id!;
      await farms.addField(farmId: farmId, name: 'Keep', sizeAcres: 1.0);
      await farms.addField(farmId: farmId, name: 'Remove', sizeAcres: 1.0);
      await farms.fetchFields(farmId);
      final removeId =
          farms.getFieldsForFarm(farmId).firstWhere((f) => f.name == 'Remove').id!;

      await farms.deleteField(removeId, farmId);

      final remaining = farms.getFieldsForFarm(farmId);
      expect(remaining, hasLength(1));
      expect(remaining.first.name, 'Keep');
      await db.close();
    });
  });
}
