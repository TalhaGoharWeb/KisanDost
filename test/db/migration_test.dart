import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:kisan_dost/database/db_helper.dart';

/// Hermetic migration tests. They exercise the REAL migration SQL in
/// [DatabaseHelper.migrateV9ToV10] against an in-memory FFI database —
/// no app singleton, no filesystem, no plugins.
void main() {
  sqfliteFfiInit();
  // Route package:sqflite through the FFI backend for these tests.
  databaseFactory = databaseFactoryFfi;

  /// Builds the v9-shaped schema (the tables touched by the v10 migration).
  Future<void> createV9Schema(Database db) async {
    await db.execute('''
      CREATE TABLE farms (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        name TEXT NOT NULL,
        total_area REAL NOT NULL,
        created_at TEXT NOT NULL
      )
    ''');
    await db.execute('''
      CREATE TABLE fields (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        farm_id INTEGER NOT NULL,
        name TEXT NOT NULL,
        size_acres REAL NOT NULL,
        canal_water_available INTEGER NOT NULL DEFAULT 0,
        tube_well_available INTEGER NOT NULL DEFAULT 0,
        location TEXT,
        FOREIGN KEY (farm_id) REFERENCES farms (id) ON DELETE CASCADE
      )
    ''');
    await db.execute('''
      CREATE TABLE crop_seasons (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        field_id INTEGER NOT NULL,
        crop_name TEXT NOT NULL,
        variety TEXT NOT NULL,
        status TEXT NOT NULL,
        start_date TEXT NOT NULL,
        FOREIGN KEY (field_id) REFERENCES fields (id) ON DELETE CASCADE
      )
    ''');
    await db.execute('''
      CREATE TABLE crop_season_fields (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        crop_season_id INTEGER NOT NULL,
        field_id INTEGER NOT NULL,
        FOREIGN KEY (crop_season_id) REFERENCES crop_seasons (id) ON DELETE CASCADE,
        FOREIGN KEY (field_id) REFERENCES fields (id) ON DELETE CASCADE,
        UNIQUE (crop_season_id, field_id)
      )
    ''');
    await db.execute('''
      CREATE TABLE expenses (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        category TEXT NOT NULL,
        amount REAL NOT NULL,
        date TEXT NOT NULL,
        description TEXT
      )
    ''');

    // Stub tables: the v10 migration's orphan-repair DELETEs read these,
    // but this test only exercises the farm/field/season/expense paths.
    // They stay empty, so the DELETEs are no-ops here.
    await db.execute(
        'CREATE TABLE thekas (id INTEGER PRIMARY KEY AUTOINCREMENT, farm_id INTEGER, field_id INTEGER)');
    await db.execute(
        'CREATE TABLE theka_installments (id INTEGER PRIMARY KEY AUTOINCREMENT, theka_id INTEGER)');
    await db.execute(
        'CREATE TABLE ushr_records (id INTEGER PRIMARY KEY AUTOINCREMENT, crop_season_id INTEGER, harvest_id INTEGER)');
    await db.execute(
        'CREATE TABLE harvests (id INTEGER PRIMARY KEY AUTOINCREMENT, crop_season_id INTEGER)');
    await db.execute(
        'CREATE TABLE sales (id INTEGER PRIMARY KEY AUTOINCREMENT, harvest_id INTEGER)');
    await db.execute(
        'CREATE TABLE activities (id INTEGER PRIMARY KEY AUTOINCREMENT, crop_season_id INTEGER)');
  }

  Future<Database> openV9Db() {
    return openDatabase(
      inMemoryDatabasePath,
      onConfigure: (db) async {
        // Same as DatabaseHelper._initDatabase: FKs must be enforced for
        // cascades and SET NULL to work.
        await db.execute('PRAGMA foreign_keys = ON');
      },
    );
  }

  /// Opens a v9-shaped DB with FK enforcement OFF, simulating production
  /// devices before the FK-enforcement fix (9b5f7f0): that is the only way
  /// orphan rows could have accumulated.
  Future<Database> openV9DbWithoutFk() {
    return openDatabase(inMemoryDatabasePath);
  }

  group('DB v10 migration', () {
    test('FK enforcement: deleting a farm cascades to its fields', () async {
      final db = await openV9Db();
      await createV9Schema(db);

      final farmId = await db.insert('farms', {
        'name': 'Test Farm',
        'total_area': 10.0,
        'created_at': '2026-01-01',
      });
      await db.insert('fields', {
        'farm_id': farmId,
        'name': 'Field 1',
        'size_acres': 5.0,
      });

      await db.delete('farms', where: 'id = ?', whereArgs: [farmId]);

      expect(await db.query('fields'), isEmpty);
      await db.close();
    });

    test('v10 migration cleans orphans and links expenses to farm/field/crop',
        () async {
      // FK off: orphans could only accumulate on devices where FK
      // enforcement was disabled (pre-9b5f7f0 production).
      final db = await openV9DbWithoutFk();
      await createV9Schema(db);

      // Valid parent chain.
      final farmId = await db.insert('farms', {
        'name': 'Good Farm',
        'total_area': 10.0,
        'created_at': '2026-01-01',
      });
      final fieldId = await db.insert('fields', {
        'farm_id': farmId,
        'name': 'Good Field',
        'size_acres': 5.0,
      });
      final seasonId = await db.insert('crop_seasons', {
        'field_id': fieldId,
        'crop_name': 'Wheat',
        'variety': 'Local',
        'status': 'Active',
        'start_date': '2026-01-01',
      });

      // Orphans accumulated before FK enforcement existed.
      await db.insert('fields', {
        'farm_id': 9999,
        'name': 'Orphan Field',
        'size_acres': 1.0,
      });
      await db.insert('crop_seasons', {
        'field_id': 9999,
        'crop_name': 'Rice',
        'variety': 'X',
        'status': 'Active',
        'start_date': '2026-01-01',
      });
      await db.insert('crop_season_fields', {
        'crop_season_id': 9999,
        'field_id': fieldId,
      });

      // A pre-migration expense (no link columns yet).
      await db.insert('expenses', {
        'category': 'Seeds',
        'amount': 100.0,
        'date': '2026-01-01',
        'description': 'old expense',
      });

      // Run the real v10 migration.
      await DatabaseHelper.migrateV9ToV10(db);

      // Orphans are gone; valid rows survive.
      final fields = await db.query('fields');
      expect(fields.map((f) => f['name']), ['Good Field']);
      expect(await db.query('crop_seasons'), hasLength(1));
      expect(await db.query('crop_season_fields'), isEmpty);

      // Enable FK enforcement like the app's _initDatabase does, so the
      // new REFERENCES clauses added by the migration are actually
      // enforced for the assertions below.
      await db.execute('PRAGMA foreign_keys = ON');

      // New link columns exist on expenses.
      final columns = await db.rawQuery("PRAGMA table_info('expenses')");
      final columnNames = columns.map((c) => c['name'] as String).toSet();
      expect(
          columnNames, containsAll(['farm_id', 'field_id', 'crop_season_id']));

      // Old expense survived with NULL links.
      final oldExpense = (await db.query('expenses',
              where: 'description = ?', whereArgs: ['old expense']))
          .single;
      expect(oldExpense['farm_id'], isNull);
      expect(oldExpense['crop_season_id'], isNull);

      // A new expense can be linked to farm/field/crop.
      final linkedId = await db.insert('expenses', {
        'category': 'Fertilizer',
        'amount': 250.0,
        'date': '2026-02-01',
        'farm_id': farmId,
        'field_id': fieldId,
        'crop_season_id': seasonId,
      });
      expect(linkedId, isNotNull);

      // A link to a non-existent parent is rejected (FK enforced on the
      // columns added via ALTER TABLE).
      await expectLater(
        db.insert('expenses', {
          'category': 'Fertilizer',
          'amount': 1.0,
          'date': '2026-02-01',
          'farm_id': 9999,
        }),
        throwsException,
      );

      // Deleting the farm SET NULLs the expense links instead of deleting
      // the financial record.
      await db.delete('farms', where: 'id = ?', whereArgs: [farmId]);
      final kept = (await db
              .query('expenses', where: 'id = ?', whereArgs: [linkedId]))
          .single;
      expect(kept['farm_id'], isNull);
      expect(kept['field_id'], isNull);
      expect(kept['crop_season_id'], isNull);
      expect(kept['amount'], 250.0);

      await db.close();
    });
  });
}
