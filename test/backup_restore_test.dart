import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:kisan_dost/database/db_helper.dart';

void main() {
  setUpAll(sqfliteFfiInit);

  setUp(() async {
    await DatabaseHelper.configureForTesting(factory: databaseFactoryFfi);
  });

  tearDown(() async {
    await DatabaseHelper.resetForTesting();
  });

  Future<void> seedLinkedRecords() async {
    final db = await DatabaseHelper.instance.database;
    final farmId = await db.insert('farms', {
      'name': 'Original Farm',
      'total_area': 5.0,
      'created_at': '2026-09-30',
    });
    final fieldId = await db.insert('fields', {
      'farm_id': farmId,
      'name': 'North Field',
      'size_acres': 2.0,
      'canal_water_available': 1,
      'tube_well_available': 0,
    });
    final cropSeasonId = await db.insert('crop_seasons', {
      'field_id': fieldId,
      'crop_name': 'Wheat',
      'variety': 'Test',
      'status': 'Active',
      'start_date': '2026-09-01',
    });
    await db.insert('crop_season_fields', {
      'crop_season_id': cropSeasonId,
      'field_id': fieldId,
    });
    final expenseId = await db.insert('expenses', {
      'category': 'Fertilizer',
      'amount': 1000.0,
      'date': '2026-09-15',
      'description': 'Urea',
    });
    await db.insert('inventory', {
      'category': 'Fertilizer',
      'name': 'Urea',
      'unit': 'kg',
      'quantity': 10.0,
      'cost_per_unit': 100.0,
    });
    await db.insert('activities', {
      'crop_season_id': cropSeasonId,
      'activity_type': 'Fertilizer applied',
      'date': '2026-09-15',
      'expense_id': expenseId,
      'inventory_category': 'Fertilizer',
      'inventory_name': 'Urea',
      'inventory_unit': 'kg',
      'inventory_quantity': 2.0,
    });
    final harvestId = await db.insert('harvests', {
      'crop_season_id': cropSeasonId,
      'quantity': 10.0,
      'unit': 'من',
      'date': '2026-09-30',
      'gross_amount': 5000.0,
      'total_expense': 1000.0,
      'net_income': 4000.0,
    });
    await db.insert('sales', {
      'harvest_id': harvestId,
      'buyer_name': 'Buyer',
      'quantity': 10.0,
      'price_per_unit': 500.0,
      'total_amount': 5000.0,
      'date': '2026-09-30',
    });
    await db.insert('ushr_records', {
      'crop_season_id': cropSeasonId,
      'harvest_id': harvestId,
      'harvest_qty': 10.0,
      'market_value': 5000.0,
      'ushr_method': 'Canal',
      'ushr_percentage': 5.0,
      'ushr_amount': 250.0,
      'status': 'Pending',
    });
    await db.insert('tasks', {
      'title': 'Irrigate field',
      'date_time': '2026-10-01T06:00:00.000',
    });
    final thekaId = await db.insert('thekas', {
      'farm_id': farmId,
      'field_id': fieldId,
      'total_amount': 12000.0,
      'duration_type': 'Yearly',
      'payment_method': 'Installment',
      'created_at': '2026-09-01',
    });
    await db.insert('theka_installments', {
      'theka_id': thekaId,
      'amount': 1000.0,
      'due_date': '2026-10-01',
      'status': 'Pending',
    });
  }

  test(
    'backup restores all related records and preserves primary keys',
    () async {
      await seedLinkedRecords();
      final db = await DatabaseHelper.instance.database;
      final backup = await DatabaseHelper.instance.createBackup();
      await db.update(
        'farms',
        {'name': 'Changed Locally'},
        where: 'id = ?',
        whereArgs: [1],
      );

      final restoredCount = await DatabaseHelper.instance.restoreBackup(backup);

      expect(restoredCount, 13);
      expect((await db.query('farms')).single['name'], 'Original Farm');
      expect((await db.query('fields')).single['farm_id'], 1);
      expect((await db.query('crop_seasons')).single['field_id'], 1);
      expect((await db.query('activities')).single['expense_id'], 1);
      expect((await db.query('sales')).single['harvest_id'], 1);
      expect((await db.query('ushr_records')).single['harvest_id'], 1);
      expect((await db.query('theka_installments')).single['theka_id'], 1);
    },
  );

  test('v10 backups restore stock as an opening movement', () async {
    await seedLinkedRecords();
    final db = await DatabaseHelper.instance.database;
    final backup = await DatabaseHelper.instance.createBackup();
    final tables = Map<String, dynamic>.from(backup['tables'] as Map);
    tables.remove('inventory_transactions');
    backup['tables'] = tables;
    backup['schemaVersion'] = 10;

    final restoredCount = await DatabaseHelper.instance.restoreBackup(backup);
    final movements = await db.query('inventory_transactions');

    expect(restoredCount, 14);
    expect(movements, hasLength(1));
    expect(movements.single['movement_type'], 'opening');
    expect(movements.single['quantity_delta'], 10.0);
    expect(movements.single['item_name'], 'Urea');
  });

  test('v10 database migration preserves current warehouse balances', () async {
    final legacyPath =
        '${Directory.systemTemp.path}/kisandost-v10-${DateTime.now().microsecondsSinceEpoch}.db';
    addTearDown(() async {
      await DatabaseHelper.resetForTesting();
      final file = File(legacyPath);
      if (await file.exists()) await file.delete();
    });
    final legacyDb = await databaseFactoryFfi.openDatabase(
      legacyPath,
      options: OpenDatabaseOptions(
        version: 10,
        onCreate: (db, _) async {
          await db.execute('''
            CREATE TABLE inventory (
              id INTEGER PRIMARY KEY AUTOINCREMENT,
              category TEXT NOT NULL,
              name TEXT NOT NULL,
              unit TEXT NOT NULL,
              quantity REAL NOT NULL,
              cost_per_unit REAL NOT NULL
            )
          ''');
          await db.insert('inventory', {
            'category': 'Fertilizer',
            'name': 'Urea',
            'unit': 'کلوگرام',
            'quantity': 25.0,
            'cost_per_unit': 100.0,
          });
        },
      ),
    );
    await legacyDb.close();

    await DatabaseHelper.configureForTesting(
      factory: databaseFactoryFfi,
      path: legacyPath,
    );
    final upgradedDb = await DatabaseHelper.instance.database;
    final movements = await upgradedDb.query('inventory_transactions');

    expect((await upgradedDb.query('inventory')).single['quantity'], 25.0);
    expect(movements, hasLength(1));
    expect(movements.single['movement_type'], 'opening');
    expect(movements.single['quantity_delta'], 25.0);
  });

  test(
    'invalid foreign-key references roll back without erasing current records',
    () async {
      await seedLinkedRecords();
      final db = await DatabaseHelper.instance.database;
      final backup = await DatabaseHelper.instance.createBackup();
      await db.update(
        'farms',
        {'name': 'Current Local Farm'},
        where: 'id = ?',
        whereArgs: [1],
      );

      final invalidBackup = Map<String, dynamic>.from(backup);
      final tables = Map<String, dynamic>.from(backup['tables'] as Map);
      final fields = List<Map<String, dynamic>>.from(tables['fields'] as List);
      fields[0] = Map<String, dynamic>.from(fields[0])..['farm_id'] = 9999;
      tables['fields'] = fields;
      invalidBackup['tables'] = tables;

      await expectLater(
        DatabaseHelper.instance.restoreBackup(invalidBackup),
        throwsA(anything),
      );
      expect((await db.query('farms')).single['name'], 'Current Local Farm');
      expect((await db.query('fields')).single['farm_id'], 1);
    },
  );

  test(
    'rejects unsupported schema versions before replacing any data',
    () async {
      await seedLinkedRecords();
      final db = await DatabaseHelper.instance.database;
      final backup = await DatabaseHelper.instance.createBackup();
      await db.update(
        'farms',
        {'name': 'Current Local Farm'},
        where: 'id = ?',
        whereArgs: [1],
      );
      backup['schemaVersion'] = 999;

      await expectLater(
        DatabaseHelper.instance.restoreBackup(backup),
        throwsA(isA<FormatException>()),
      );
      expect((await db.query('farms')).single['name'], 'Current Local Farm');
    },
  );
}
