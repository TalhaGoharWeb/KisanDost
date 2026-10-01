import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite/sqflite.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:kisan_dost/database/db_helper.dart';
import 'package:kisan_dost/services/backup_service.dart';
import 'package:kisan_dost/services/restore_service.dart';

/// Hermetic backup/restore tests. They exercise the REAL [BackupService]
/// and [RestoreService] against a REAL file-based v12 database opened
/// through [DatabaseHelper.instance] — the FFI factory is routed in so
/// `getDatabasesPath()` works, and the databases path is pointed at a
/// fresh temp dir per test so every test starts with a clean database.
///
/// Injection: `BackupService(backupsDir: tempDir, liveDbPath: ...)` keeps
/// everything (backups, safety backups, live db) inside the temp root;
/// production defaults (app documents dir / real databases path) are never
/// touched.
void main() {
  sqfliteFfiInit();
  // Route package:sqflite through the FFI backend for these tests.
  databaseFactory = databaseFactoryFfi;

  late Directory tempRoot;
  late BackupService backups;
  late RestoreService restore;

  setUpAll(() {
    SharedPreferences.setMockInitialValues({});
  });

  setUp(() async {
    tempRoot = await Directory.systemTemp.createTemp('kisan_backup_test_');
    // Fresh databases location per test -> fresh live DB per test.
    await databaseFactory.setDatabasesPath(join(tempRoot.path, 'databases'));
    // Drop the singleton's cached connection so it re-opens at the new path.
    await DatabaseHelper.instance.close();
    final liveDbPath = await DatabaseHelper.instance.databaseFilePath;
    backups = BackupService(
      backupsDir: Directory(join(tempRoot.path, 'backups')),
      liveDbPath: liveDbPath,
    );
    restore = RestoreService(backupService: backups);
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(BackupService.lastAutoBackupDateKey);
  });

  tearDown(() async {
    await DatabaseHelper.instance.close();
    await tempRoot.delete(recursive: true);
  });

  /// Populates a small but FK-linked dataset: farm -> field -> crop season
  /// + one linked expense + one inventory item.
  Future<Map<String, int>> populateSampleData() async {
    final db = await DatabaseHelper.instance.database;
    final farmId = await db.insert('farms', {
      'name': 'میری زمین',
      'total_area': 10.0,
      'created_at': '2026-01-01',
    });
    final fieldId = await db.insert('fields', {
      'farm_id': farmId,
      'name': 'کھیت ۱',
      'size_acres': 5.0,
      'canal_water_available': 1,
      'tube_well_available': 0,
    });
    final cropId = await db.insert('crop_seasons', {
      'field_id': fieldId,
      'crop_name': 'گندم',
      'variety': 'فیصل آباد',
      'status': 'Active',
      'start_date': '2026-01-10',
    });
    final expenseId = await db.insert('expenses', {
      'category': 'بیج',
      'amount_paisa': 500000,
      'date': '2026-01-11',
      'farm_id': farmId,
      'field_id': fieldId,
      'crop_season_id': cropId,
    });
    final itemId = await db.insert('inventory', {
      'category': 'کھاد',
      'name': 'یوریا',
      'unit': 'بوری',
      'quantity': 5.0,
      'cost_per_unit_paisa': 200000,
    });
    return {
      'farm': farmId,
      'field': fieldId,
      'crop': cropId,
      'expense': expenseId,
      'item': itemId,
    };
  }

  Future<int> count(Database db, String table) async =>
      Sqflite.firstIntValue(
        await db.rawQuery('SELECT COUNT(*) FROM "$table"'),
      ) ??
      0;

  group('createBackup / verifyBackup', () {
    test(
      'creates a verifiable backup; sidecar sha256 matches file bytes',
      () async {
        await populateSampleData();
        final info = await backups.createBackup(label: 'ٹیسٹ');

        expect(await File(info.path).exists(), isTrue);
        expect(info.sidecarPath, isNotNull);
        expect(await File(info.sidecarPath!).exists(), isTrue);
        expect(info.label, 'ٹیسٹ');
        expect(info.schemaVersion, DatabaseHelper.schemaVersion);
        expect(info.hasSidecar, isTrue);
        expect(info.sizeBytes, greaterThan(0));
        expect(info.name, startsWith('kisandost_backup_'));
        expect(info.name, endsWith('_v${DatabaseHelper.schemaVersion}.db'));

        // Throws on any problem.
        await backups.verifyBackup(info.path);

        final sidecar =
            jsonDecode(await File(info.sidecarPath!).readAsString())
                as Map<String, dynamic>;
        final actual =
            sha256.convert(await File(info.path).readAsBytes()).toString();
        expect(sidecar['sha256'], actual);
        expect(sidecar['schemaVersion'], DatabaseHelper.schemaVersion);

        // The app still has a usable DB afterwards.
        final db = await DatabaseHelper.instance.database;
        expect(await count(db, 'farms'), 1);
        expect(await count(db, 'expenses'), 1);
      },
    );

    test(
      'listBackups is newest-first and tolerates orphan .db files',
      () async {
        await populateSampleData();
        final first = await backups.createBackup(label: 'پہلا');
        final second = await backups.createBackup(label: 'دوسرا');

        // Orphan: a .db with no sidecar must still be listed.
        final orphanPath = join(
          tempRoot.path,
          'backups',
          'kisandost_backup_orphan.db',
        );
        await File(first.path).copy(orphanPath);

        final list = await backups.listBackups();
        expect(
          list.map((b) => b.name),
          containsAll([first.name, second.name, 'kisandost_backup_orphan.db']),
        );
        // Newest first by sidecar createdAt: the second real backup sorts
        // before the first. (The orphan copy gets "now" as its mtime, so
        // its position is not asserted.)
        final names = list.map((b) => b.name).toList();
        expect(names.indexOf(second.name), lessThan(names.indexOf(first.name)));
        final orphan = list.firstWhere(
          (b) => b.name == 'kisandost_backup_orphan.db',
        );
        expect(orphan.label, 'نامعلوم');
        expect(orphan.hasSidecar, isFalse);
      },
    );

    test('tampering with a backup is detected via sidecar sha256', () async {
      await populateSampleData();
      final info = await backups.createBackup();
      await backups.verifyBackup(info.path);

      // Flip one byte in the middle of the file.
      final raf = await File(info.path).open(mode: FileMode.append);
      await raf.writeByte(0xFF);
      await raf.close();

      await expectLater(
        backups.verifyBackup(info.path),
        throwsA(isA<BackupException>()),
      );
    });
  });

  group('restoreReplace', () {
    test('replaces live data with the backup; DB stays usable', () async {
      final ids = await populateSampleData();
      final info = await backups.createBackup();

      // Mangle the live DB: delete the farm (cascades), add a junk row.
      final db = await DatabaseHelper.instance.database;
      await db.delete('farms', where: 'id = ?', whereArgs: [ids['farm']]);
      await db.insert('farms', {
        'name': 'کچرا',
        'total_area': 1.0,
        'created_at': '2026-02-01',
      });
      expect(await count(db, 'farms'), 1);

      final msg = await restore.restoreReplace(info.path);
      expect(msg, contains('کامیابی'));

      final db2 = await DatabaseHelper.instance.database;
      final farms = await db2.query('farms');
      expect(farms, hasLength(1));
      expect(farms.first['name'], 'میری زمین');
      expect(await count(db2, 'fields'), 1);
      expect(await count(db2, 'crop_seasons'), 1);
      expect(await count(db2, 'expenses'), 1);
      // A safety backup was taken before replacing.
      final list = await backups.listBackups();
      expect(list.any((b) => b.label == 'pre-restore'), isTrue);
    });

    test('migrates a v11-era backup forward to v13 on restore', () async {
      await populateSampleData();

      // Hand-craft a v11-shaped backup: REAL money columns, user_version 11.
      // It carries the full v11 table set (like a real v11 backup) so the
      // v11->v12 rebuild's FK references resolve during the upgrade.
      final v11path = join(tempRoot.path, 'v11.db');
      Database? v11;
      try {
        v11 = await openDatabase(
          v11path,
          version: 11,
          onCreate: (db, version) async {
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
              CREATE TABLE expenses (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                category TEXT NOT NULL,
                amount REAL NOT NULL,
                date TEXT NOT NULL,
                description TEXT,
                farm_id INTEGER REFERENCES farms (id) ON DELETE SET NULL,
                field_id INTEGER REFERENCES fields (id) ON DELETE SET NULL,
                crop_season_id INTEGER REFERENCES crop_seasons (id) ON DELETE SET NULL
              )
            ''');
            await db.execute('''
              CREATE TABLE inventory (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                category TEXT NOT NULL,
                name TEXT NOT NULL,
                unit TEXT NOT NULL,
                quantity REAL NOT NULL,
                cost_per_unit REAL NOT NULL,
                weight_per_unit_kg REAL
              )
            ''');
            await db.execute('''
              CREATE TABLE activities (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                crop_season_id INTEGER NOT NULL,
                activity_type TEXT NOT NULL,
                date TEXT NOT NULL,
                details TEXT,
                expense_id INTEGER,
                expense_category TEXT,
                inventory_category TEXT,
                inventory_name TEXT,
                inventory_unit TEXT,
                inventory_quantity REAL,
                inventory_item_id INTEGER REFERENCES inventory (id) ON DELETE SET NULL,
                is_completed INTEGER NOT NULL DEFAULT 0,
                FOREIGN KEY (crop_season_id) REFERENCES crop_seasons (id) ON DELETE CASCADE,
                FOREIGN KEY (expense_id) REFERENCES expenses (id) ON DELETE SET NULL
              )
            ''');
            await db.execute('''
              CREATE TABLE inventory_transactions (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                inventory_id INTEGER NOT NULL REFERENCES inventory (id) ON DELETE CASCADE,
                type TEXT NOT NULL,
                quantity REAL NOT NULL,
                unit TEXT NOT NULL,
                unit_price REAL,
                total_amount REAL,
                activity_id INTEGER REFERENCES activities (id) ON DELETE SET NULL,
                date TEXT NOT NULL,
                notes TEXT,
                created_at TEXT NOT NULL
              )
            ''');
            await db.insert('expenses', {
              'category': 'بیج',
              'amount': 1234.56,
              'date': '2026-01-11',
            });
          },
        );
      } finally {
        await v11?.close();
      }

      await restore.restoreReplace(v11path);

      final db = await DatabaseHelper.instance.database;
      expect(
        Sqflite.firstIntValue(await db.rawQuery('PRAGMA user_version')),
        DatabaseHelper.schemaVersion,
      );
      // The v13 party tables were created by the forward migration too.
      final allTables =
          (await db.rawQuery(
            "SELECT name FROM sqlite_master WHERE type = 'table'",
          )).map((r) => r['name'] as String).toSet();
      expect(allTables, containsAll(['parties', 'party_ledger_entries']));
      final cols =
          (await db.rawQuery(
            'PRAGMA table_info(expenses)',
          )).map((c) => c['name'].toString()).toSet();
      expect(cols.contains('amount_paisa'), isTrue);
      expect(cols.contains('amount'), isFalse);
      final rows = await db.query('expenses');
      expect(rows, hasLength(1));
      expect(rows.first['amount_paisa'], 123456);
    });
  });

  group('restoreMerge', () {
    test(
      'restores deleted rows, keeps new rows, second merge is a no-op',
      () async {
        final db = await DatabaseHelper.instance.database;
        await db.insert('farms', {
          'name': 'A',
          'total_area': 5.0,
          'created_at': '2026-01-01',
        });
        final farmB = await db.insert('farms', {
          'name': 'B',
          'total_area': 6.0,
          'created_at': '2026-01-02',
        });
        final info = await backups.createBackup();

        // createBackup closes and re-opens the singleton connection, so
        // re-fetch: the handle above is stale.
        final live = await DatabaseHelper.instance.database;

        // Live diverges: B deleted, C added.
        await live.delete('farms', where: 'id = ?', whereArgs: [farmB]);
        await live.insert('farms', {
          'name': 'C',
          'total_area': 7.0,
          'created_at': '2026-01-03',
        });

        final result = await restore.restoreMerge(info.path);
        final farms = result.perTable['farms']!;
        expect(farms.imported, 1); // B restored
        expect(farms.skipped, 1); // A already present

        // restoreMerge takes its own safety backup, which closes and
        // re-opens the singleton — re-fetch again.
        final live2 = await DatabaseHelper.instance.database;
        final names =
            (await live2.query(
              'farms',
              orderBy: 'id ASC',
            )).map((r) => r['name'].toString()).toSet();
        expect(names, {'A', 'B', 'C'});

        // Idempotent: merging again imports nothing.
        final again = await restore.restoreMerge(info.path);
        expect(again.totalImported, 0);
        expect(again.perTable['farms']!.skipped, 2);

        // Urdu summary names the table and is honest about skips.
        final summary = result.summaryUrdu();
        expect(summary, contains('زمینیں: 1 شامل، 1 پہلے سے موجود'));
        expect(summary, contains('متعلقہ ریکارڈ'));
      },
    );

    test('skips rows whose parent records are missing (FK orphans)', () async {
      await populateSampleData();
      final info = await backups.createBackup();

      // Delete the sidecar so the edited backup still verifies, then plant
      // an orphan expense (farm_id 9999 does not exist) with FKs off.
      await File('${info.path}.json').delete();
      Database? bk;
      try {
        bk = await openDatabase(info.path);
        await bk.execute('PRAGMA foreign_keys = OFF');
        await bk.insert('expenses', {
          'category': 'کھاد',
          'amount_paisa': 100,
          'date': '2026-01-12',
          'farm_id': 9999,
        });
      } finally {
        await bk?.close();
      }

      final result = await restore.restoreMerge(info.path);
      final expenses = result.perTable['expenses']!;
      // Backup has 2 expense rows: the real one (already present) and the
      // orphan (parent missing) — both honestly skipped, none imported.
      expect(expenses.imported, 0);
      expect(expenses.skipped, 2);

      final db = await DatabaseHelper.instance.database;
      expect(await count(db, 'expenses'), 1);
    });

    test('merge follows parent-before-child table order', () {
      expect(
        RestoreService.mergeTableOrder,
        orderedEquals([
          'farms',
          'fields',
          'crop_seasons',
          'crop_season_fields',
          'inventory',
          'expenses',
          'harvests',
          'sales',
          'activities',
          'ushr_records',
          'thekas',
          'theka_installments',
          'parties',
          'party_ledger_entries',
          'batai_agreements',
          'batai_settlements',
          'tasks',
          'inventory_transactions',
          'audit_log',
        ]),
      );
    });
  });

  group('verifyBackup rejections', () {
    test('rejects missing, empty, corrupt, wrong-magic and future-version '
        'files; live DB stays byte-identical', () async {
      await populateSampleData();
      final livePath = await DatabaseHelper.instance.databaseFilePath;
      await DatabaseHelper.instance.checkpoint();
      await DatabaseHelper.instance.close();
      final beforeHash =
          sha256.convert(await File(livePath).readAsBytes()).toString();
      await DatabaseHelper.instance.database; // reopen for the app

      // Random bytes.
      final corrupt = File(join(tempRoot.path, 'corrupt.db'));
      await corrupt.writeAsBytes(
        List<int>.generate(256, (i) => (i * 37) % 256),
      );
      // Wrong magic header.
      final badMagic = File(join(tempRoot.path, 'badmagic.db'));
      await badMagic.writeAsBytes([
        ...utf8.encode('NOT A DATABASE FILE'),
        ...List.filled(100, 0),
      ]);
      // Empty file.
      final empty = File(join(tempRoot.path, 'empty.db'));
      await empty.writeAsBytes([]);
      // Valid DB but from a newer app version.
      final future = File(join(tempRoot.path, 'future.db'));
      await File(livePath).copy(future.path);
      Database? fdb;
      try {
        fdb = await openDatabase(future.path);
        await fdb.execute('PRAGMA user_version = 99');
      } finally {
        await fdb?.close();
      }

      final missing = join(tempRoot.path, 'nope.db');
      for (final p in [
        missing,
        empty.path,
        corrupt.path,
        badMagic.path,
        future.path,
      ]) {
        await expectLater(
          backups.verifyBackup(p),
          throwsA(isA<BackupException>()),
        );
        // restoreReplace validates BEFORE touching anything.
        await expectLater(
          restore.restoreReplace(p),
          throwsA(isA<BackupException>()),
        );
      }

      // The future-version message is Urdu and names the real problem.
      try {
        await backups.verifyBackup(future.path);
        fail('expected BackupException');
      } on BackupException catch (e) {
        expect(e.message, contains('نیا ورژن'));
      }

      await DatabaseHelper.instance.checkpoint();
      await DatabaseHelper.instance.close();
      final afterHash =
          sha256.convert(await File(livePath).readAsBytes()).toString();
      await DatabaseHelper.instance.database;
      expect(afterHash, beforeHash);
    });
  });

  group('pruneBackups / deleteBackup', () {
    test('pruneBackups keeps the newest N backups', () async {
      await populateSampleData();
      final created = <BackupInfo>[];
      for (var i = 0; i < 5; i++) {
        created.add(await backups.createBackup(label: 'ٹیسٹ $i'));
      }
      expect(await backups.listBackups(), hasLength(5));

      await backups.pruneBackups(keep: 3);
      final remaining = await backups.listBackups();
      expect(remaining, hasLength(3));
      final names = remaining.map((b) => b.name).toSet();
      expect(names.contains(created.last.name), isTrue); // newest kept
      expect(names.contains(created.first.name), isFalse); // oldest pruned
    });

    test('deleteBackup removes the db file and its sidecar', () async {
      await populateSampleData();
      final info = await backups.createBackup();
      final sidecarPath = info.sidecarPath!;
      await backups.deleteBackup(info);
      expect(await File(info.path).exists(), isFalse);
      expect(await File(sidecarPath).exists(), isFalse);
      expect(await backups.listBackups(), isEmpty);
    });
  });

  group('importBackupFile', () {
    test('imports an external db and rejects garbage (cleaning up)', () async {
      await populateSampleData();
      final info = await backups.createBackup();

      // Simulate a file picked from outside: the db without its sidecar.
      final external = join(tempRoot.path, 'external.db');
      await File(info.path).copy(external);
      final imported = await backups.importBackupFile(external);
      expect(imported.label, 'درآمد شدہ');
      expect(imported.hasSidecar, isTrue);
      await backups.verifyBackup(imported.path);

      final garbage = File(join(tempRoot.path, 'garbage.db'));
      await garbage.writeAsBytes([1, 2, 3, 4]);
      await expectLater(
        backups.importBackupFile(garbage.path),
        throwsA(isA<BackupException>()),
      );
      // The failed import left no broken copy behind.
      final leftovers = await backups.listBackups();
      expect(leftovers.where((b) => b.name.contains('_v0.db')), isEmpty);
    });
  });

  group('auto backup', () {
    test(
      'maybeAutoBackup backs up once per day and respects the toggle',
      () async {
        await populateSampleData();
        await backups.setAutoBackupEnabled(true);
        expect(await backups.autoBackupEnabled, isTrue);

        await backups.maybeAutoBackup();
        var list = await backups.listBackups();
        expect(list, hasLength(1));
        expect(list.first.label, 'خودکار');

        // Same day: no second backup.
        await backups.maybeAutoBackup();
        expect(await backups.listBackups(), hasLength(1));

        // Disabled: no backup even with the date cleared.
        final prefs = await SharedPreferences.getInstance();
        await prefs.remove(BackupService.lastAutoBackupDateKey);
        await backups.setAutoBackupEnabled(false);
        expect(await backups.autoBackupEnabled, isFalse);
        await backups.maybeAutoBackup();
        expect(await backups.listBackups(), hasLength(1));
      },
    );

    test('maybeAutoBackup never throws', () async {
      // No database interaction at all here would still be fine; with the
      // toggle off it must simply return.
      await backups.setAutoBackupEnabled(false);
      await backups.maybeAutoBackup();
    });
  });
}
