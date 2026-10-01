import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:kisan_dost/database/db_helper.dart';
import 'package:kisan_dost/services/restore_service.dart';

/// Hermetic Phase 12 merge/migration tests.
///
/// 4a — merge semantics: [RestoreService.restoreMerge] itself is bound to
/// the app singleton ([DatabaseHelper.instance]) and its per-table worker
/// `_mergeTable` is private, so the real code path cannot run hermetically.
/// What IS pinned here:
/// * the real public contract [RestoreService.mergeTableOrder] (audit_log
///   merges last, after every table it describes);
/// * the documented merge algorithm — column-intersection
///   `INSERT OR IGNORE ... SELECT` — executed verbatim against two
///   file-backed FFI databases, proving a soft-deleted row arrives with
///   `deleted_at` intact (merge never resurrects) and audit_log rows merge.
///
/// 4b — v15 migration idempotency: [DatabaseHelper.migrateV14ToV15] runs
/// twice on the same database without error and leaves every `deleted_at`
/// column plus `audit_log` behind.
void main() {
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  TestWidgetsFlutterBinding.ensureInitialized();
  SharedPreferences.setMockInitialValues({});

  const expensesDdl = '''
    CREATE TABLE expenses (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      category TEXT NOT NULL,
      amount_paisa INTEGER NOT NULL,
      date TEXT NOT NULL,
      description TEXT,
      deleted_at TEXT
    )
  ''';

  const auditLogDdl = '''
    CREATE TABLE audit_log (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      ts TEXT NOT NULL,
      table_name TEXT NOT NULL,
      row_id INTEGER NOT NULL,
      action TEXT NOT NULL,
      details TEXT,
      created_at TEXT NOT NULL
    )
  ''';

  /// Verbatim copy of the documented merge algorithm in
  /// restore_service.dart `_mergeTable` (bulk path): column intersection of
  /// main/bk, then INSERT OR IGNORE ... SELECT. No FK clauses in these
  /// fixtures, so the orphan fallback path is not exercised.
  Future<void> mergeTableLikeRestoreService(
      Database db, String table) async {
    final mainCols = (await db
            .rawQuery('PRAGMA main.table_info("$table")'))
        .map((c) => c['name'].toString())
        .toSet();
    final bkCols = (await db
            .rawQuery('PRAGMA bk.table_info("$table")'))
        .map((c) => c['name'].toString())
        .toSet();
    final common = mainCols.intersection(bkCols).toList(growable: false);
    if (common.isEmpty) return;
    final cols = common.map((c) => '"$c"').join(', ');
    await db.rawInsert(
      'INSERT OR IGNORE INTO main."$table" ($cols) '
      'SELECT $cols FROM bk."$table"',
    );
  }

  group('merge keeps soft-delete state and audit rows', () {
    test('mergeTableOrder puts audit_log last', () {
      // The real contract: the log references every other table, so it
      // merges after all of them.
      expect(RestoreService.mergeTableOrder, contains('expenses'));
      expect(RestoreService.mergeTableOrder, contains('audit_log'));
      expect(RestoreService.mergeTableOrder.last, 'audit_log');
    });

    test(
        'soft-deleted expense arrives with deleted_at intact; '
        'audit_log rows merge', () async {
      final tmp =
          await Directory.systemTemp.createTemp('phase12_merge_test');
      try {
        // --- "Backup" database: one soft-deleted expense, one live expense,
        // --- and two audit rows.
        final backupPath = '${tmp.path}/backup.db';
        final backup = await openDatabase(backupPath);
        await backup.execute(expensesDdl);
        await backup.execute(auditLogDdl);
        final deadId = await backup.insert('expenses', {
          'category': 'Seeds',
          'amount_paisa': 250000,
          'date': '2026-09-10',
          'description': 'حذف شدہ خرچہ',
          'deleted_at': '2026-09-20T10:00:00',
        });
        final liveId = await backup.insert('expenses', {
          'category': 'Fertilizer',
          'amount_paisa': 500000,
          'date': '2026-09-11',
          'description': 'زندہ خرچہ',
          'deleted_at': null,
        });
        await backup.insert('audit_log', {
          'ts': '2026-09-20T10:00:00',
          'table_name': 'expenses',
          'row_id': deadId,
          'action': 'soft_delete',
          'details': 'خرچ حذف',
          'created_at': '2026-09-20T10:00:00',
        });
        await backup.insert('audit_log', {
          'ts': '2026-09-11T09:00:00',
          'table_name': 'expenses',
          'row_id': liveId,
          'action': 'create',
          'details': 'خرچ: کھاد — 5,000 روپے',
          'created_at': '2026-09-11T09:00:00',
        });
        await backup.close();

        // --- "Current" database: same v15 shape, empty.
        final currentPath = '${tmp.path}/current.db';
        final current = await openDatabase(currentPath);
        await current.execute(expensesDdl);
        await current.execute(auditLogDdl);

        await current.execute('ATTACH DATABASE ? AS bk', [backupPath]);
        try {
          // RestoreService merges in mergeTableOrder; expenses before
          // audit_log.
          await mergeTableLikeRestoreService(current, 'expenses');
          await mergeTableLikeRestoreService(current, 'audit_log');
        } finally {
          await current.execute('DETACH DATABASE bk');
        }

        // Both expenses arrived; the soft-deleted one is STILL soft-deleted
        // (deleted_at copied verbatim — merge does not resurrect).
        final mergedExpenses =
            await current.query('expenses', orderBy: 'id ASC');
        expect(mergedExpenses, hasLength(2));
        final mergedDead = mergedExpenses.firstWhere(
            (r) => r['id'] == deadId);
        expect(mergedDead['deleted_at'], '2026-09-20T10:00:00');
        final mergedLive = mergedExpenses.firstWhere(
            (r) => r['id'] == liveId);
        expect(mergedLive['deleted_at'], isNull);

        // Audit rows merged with their actions and details intact.
        final mergedAudit =
            await current.query('audit_log', orderBy: 'id ASC');
        expect(mergedAudit, hasLength(2));
        expect(
            mergedAudit.map((r) => r['action']),
            containsAll(['create', 'soft_delete']));
        expect(
            mergedAudit
                .map((r) => r['details'])
                .whereType<String>()
                .toList(),
            containsAll(['خرچ حذف', 'خرچ: کھاد — 5,000 روپے']));

        await current.close();
      } finally {
        await tmp.delete(recursive: true);
      }
    });
  });

  group('v15 migration idempotency', () {
    /// Minimal v14-shaped schema for the five tables the migration touches:
    /// real column lists MINUS `deleted_at`, no audit_log, no FKs.
    Future<void> createV14Schema(Database db) async {
      await db.execute('''
        CREATE TABLE expenses (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          category TEXT NOT NULL,
          amount_paisa INTEGER NOT NULL,
          date TEXT NOT NULL,
          description TEXT
        )
      ''');
      await db.execute('''
        CREATE TABLE sales (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          harvest_id INTEGER,
          quantity REAL NOT NULL,
          price_per_unit_paisa INTEGER NOT NULL,
          date TEXT NOT NULL
        )
      ''');
      await db.execute('''
        CREATE TABLE harvests (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          crop_season_id INTEGER NOT NULL,
          quantity REAL NOT NULL,
          unit TEXT NOT NULL,
          date TEXT NOT NULL
        )
      ''');
      await db.execute('''
        CREATE TABLE tasks (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          title TEXT NOT NULL,
          due_date TEXT,
          is_completed INTEGER DEFAULT 0
        )
      ''');
      await db.execute('''
        CREATE TABLE parties (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          name TEXT NOT NULL,
          phone TEXT,
          notes TEXT,
          created_at TEXT NOT NULL
        )
      ''');
    }

    Future<bool> hasColumn(Database db, String table, String column) async {
      final info = await db.rawQuery('PRAGMA table_info("$table")');
      return info.any((c) => c['name'] == column);
    }

    test('migrateV14ToV15 is safe to run twice', () async {
      final db = await openDatabase(inMemoryDatabasePath);
      for (final t in [
        'expenses',
        'sales',
        'harvests',
        'tasks',
        'parties',
        'audit_log',
      ]) {
        await db.execute('DROP TABLE IF EXISTS $t');
      }
      await createV14Schema(db);

      // Seed a row so we can prove data survives the double migration.
      await db.insert('expenses', {
        'category': 'Fertilizer',
        'amount_paisa': 500000,
        'date': '2026-09-11',
        'description': 'پرانا خرچہ',
      });

      await DatabaseHelper.migrateV14ToV15(db);
      // Second run on the already-migrated db must not throw.
      await DatabaseHelper.migrateV14ToV15(db);

      for (final t in [
        'expenses',
        'sales',
        'harvests',
        'tasks',
        'parties',
      ]) {
        expect(await hasColumn(db, t, 'deleted_at'), isTrue,
            reason: '$t should have deleted_at after the migration');
      }
      final auditTables = await db.rawQuery(
          "SELECT name FROM sqlite_master WHERE type = 'table' AND name = 'audit_log'");
      expect(auditTables, hasLength(1));

      // The pre-existing row survived with NULL deleted_at (still live).
      final rows = await db.query('expenses');
      expect(rows, hasLength(1));
      expect(rows.first['deleted_at'], isNull);
      expect(rows.first['amount_paisa'], 500000);

      await db.close();
    });
  });
}
