import 'dart:io';

import 'package:sqflite/sqflite.dart';

import 'package:kisan_dost/database/db_helper.dart';
import 'package:kisan_dost/services/backup_service.dart';

/// Per-table outcome of a merge restore.
class TableMergeCount {
  final int imported;
  final int skipped;
  const TableMergeCount({required this.imported, required this.skipped});
}

/// Urdu display names used in the merge summary.
const Map<String, String> _tableUrduNames = {
  'farms': 'زمینیں',
  'fields': 'کھیت',
  'crop_seasons': 'فصلیں',
  'crop_season_fields': 'فصل-کھیت',
  'inventory': 'اسٹاک',
  'expenses': 'اخراجات',
  'harvests': 'پیداوار',
  'sales': 'فروخت',
  'activities': 'سرگرمیاں',
  'ushr_records': 'عشر ریکارڈ',
  'thekas': 'ٹھیکے',
  'theka_installments': 'ٹھیکے کی قسطیں',
  'tasks': 'کام',
  'inventory_transactions': 'اسٹاک لین دین',
  'batai_agreements': 'بٹائی معاہدے',
  'batai_settlements': 'بٹائی چکتائیاں',
  'audit_log': 'تبدیلیوں کا ریکارڈ',
};

/// Result of [RestoreService.restoreMerge].
class MergeResult {
  final Map<String, TableMergeCount> perTable;

  const MergeResult({required this.perTable});

  int get totalImported =>
      perTable.values.fold(0, (sum, c) => sum + c.imported);

  int get totalSkipped => perTable.values.fold(0, (sum, c) => sum + c.skipped);

  /// One Urdu line per table, e.g. 'فصلیں: 3 شامل، 12 پہلے سے موجود'.
  ///
  /// "Skipped" honestly covers both rows that were already present AND
  /// rows whose parent records are missing (FK violations become skips).
  String summaryUrdu() {
    final lines = <String>[];
    for (final entry in perTable.entries) {
      final urdu = _tableUrduNames[entry.key] ?? entry.key;
      lines.add(
        '$urdu: ${entry.value.imported} شامل، '
        '${entry.value.skipped} پہلے سے موجود',
      );
    }
    lines.add('کل $totalImported ریکارڈ شامل کیے گئے۔');
    lines.add(
      'نوٹ: چھوڑی گئی قطاریں یا تو پہلے سے موجود تھیں '
      'یا ان کا متعلقہ ریکارڈ موجود نہیں تھا۔',
    );
    return lines.join('\n');
  }
}

/// Restores backups into the live database — either by replacing the whole
/// database file, or by merging missing rows table by table.
///
/// Every restore starts with [BackupService.verifyBackup]; if validation
/// fails the live database is never touched.
class RestoreService {
  final BackupService _backups;

  /// [backupService] is injectable so tests can point at temp directories
  /// (its `backupsDir`/`liveDbPath` overrides are used for the safety
  /// backup too).
  RestoreService({BackupService? backupService})
    : _backups = backupService ?? BackupService();

  /// Tables merged in PARENT-BEFORE-CHILD order so FK references resolve.
  /// FK enforcement stays ON; a bulk insert that hits an orphaned row
  /// falls back to row-by-row inserts so orphans become honest skips
  /// instead of corrupting the database.
  static const List<String> mergeTableOrder = [
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
    // Audit log last: it references every other table but has no FKs.
    'audit_log',
  ];

  /// Replaces the live database with [backupPath].
  ///
  /// 1. [BackupService.verifyBackup] — any validation failure throws here,
  ///    BEFORE the safety backup or the live DB is touched.
  /// 2. Safety backup (label 'pre-restore').
  /// 3. Checkpoint + close, delete live -wal/-shm, copy the backup over
  ///    the live path.
  /// 4. Re-open via [DatabaseHelper] so [_onUpgrade] migrates older
  ///    backups forward, then `PRAGMA integrity_check` on the live DB.
  ///
  /// Returns an Urdu success message.
  Future<String> restoreReplace(String backupPath) async {
    await _backups.verifyBackup(backupPath);
    await _backups.createBackup(label: 'pre-restore');

    final helper = DatabaseHelper.instance;
    await helper.checkpoint();
    await helper.close();
    try {
      final livePath = await helper.databaseFilePath;
      // Stale WAL frames from a different database image must not shadow
      // the restored file.
      for (final suffix in ['-wal', '-shm']) {
        final f = File('$livePath$suffix');
        if (await f.exists()) await f.delete();
      }
      await File(backupPath).copy(livePath);
    } finally {
      // Re-open: _onUpgrade migrates older backups forward.
      await helper.database;
    }

    final db = await helper.database;
    final integrity = await db.rawQuery('PRAGMA integrity_check');
    final ok =
        integrity.length == 1 &&
        integrity.first.values.first.toString() == 'ok';
    if (!ok) {
      throw const BackupException('بحالی کے بعد ڈیٹا بیس کی جانچ ناکام ہو گئی');
    }
    return 'بیک اپ کامیابی سے بحال ہو گیا';
  }

  /// Merges rows missing from the live database out of [backupPath].
  ///
  /// The backup is ATTACHed as `bk`; for each table in [mergeTableOrder]
  /// the column intersection of `main.t` and `bk.t` is computed and
  /// `INSERT OR IGNORE ... SELECT` runs inside ONE transaction. Per-table
  /// `imported` = `changes()`, `skipped` = (backup rows − imported).
  ///
  /// FK enforcement stays ON. SQLite's `OR IGNORE` does NOT cover FOREIGN
  /// KEY violations, so a bulk insert containing an orphan aborts with
  /// error 787 — in that case the table falls back to row-by-row inserts,
  /// and orphans become honest skips instead of aborting the whole merge.
  /// DETACH runs in `finally`.
  Future<MergeResult> restoreMerge(String backupPath) async {
    await _backups.verifyBackup(backupPath);
    await _backups.createBackup(label: 'pre-merge');

    final db = await DatabaseHelper.instance.database;
    await db.execute('ATTACH DATABASE ? AS bk', [backupPath]);
    try {
      final perTable = <String, TableMergeCount>{};
      await db.transaction((txn) async {
        for (final table in mergeTableOrder) {
          perTable[table] = await _mergeTable(txn, table);
        }
      });
      return MergeResult(perTable: perTable);
    } finally {
      await db.execute('DETACH DATABASE bk');
    }
  }

  /// Merges one table from `bk` into `main`, returning its counts.
  Future<TableMergeCount> _mergeTable(Transaction txn, String table) async {
    final bkTables =
        (await txn.rawQuery(
          "SELECT name FROM bk.sqlite_master WHERE type = 'table' AND name = ?",
          [table],
        )).map((r) => r['name'].toString()).toSet();
    if (!bkTables.contains(table)) {
      return const TableMergeCount(imported: 0, skipped: 0);
    }
    final mainCols =
        (await txn.rawQuery(
          'PRAGMA main.table_info("$table")',
        )).map((c) => c['name'].toString()).toSet();
    final bkCols =
        (await txn.rawQuery(
          'PRAGMA bk.table_info("$table")',
        )).map((c) => c['name'].toString()).toSet();
    final common = mainCols.intersection(bkCols).toList(growable: false);
    if (common.isEmpty) {
      return const TableMergeCount(imported: 0, skipped: 0);
    }

    final cols = common.map((c) => '"$c"').join(', ');
    final bkCount =
        Sqflite.firstIntValue(
          await txn.rawQuery('SELECT COUNT(*) FROM bk."$table"'),
        ) ??
        0;

    int imported;
    try {
      await txn.rawInsert(
        'INSERT OR IGNORE INTO main."$table" ($cols) '
        'SELECT $cols FROM bk."$table"',
      );
      imported = await _changes(txn);
    } on DatabaseException catch (e) {
      if (!_isForeignKeyError(e)) rethrow;
      // Bulk insert hit an orphan: redo row-by-row so valid rows still
      // merge and only orphans are skipped.
      imported = 0;
      final placeholders = List.filled(common.length, '?').join(', ');
      final rows = await txn.rawQuery('SELECT $cols FROM bk."$table"');
      for (final row in rows) {
        try {
          await txn.rawInsert(
            'INSERT OR IGNORE INTO main."$table" ($cols) '
            'VALUES ($placeholders)',
            [for (final c in common) row[c]],
          );
          imported += await _changes(txn);
        } on DatabaseException {
          // Orphan (or duplicate): an honest skip, counted below.
        }
      }
    }
    return TableMergeCount(imported: imported, skipped: bkCount - imported);
  }

  Future<int> _changes(Transaction txn) async =>
      Sqflite.firstIntValue(await txn.rawQuery('SELECT changes()')) ?? 0;

  bool _isForeignKeyError(DatabaseException e) {
    final msg = e.toString();
    return msg.contains('FOREIGN KEY constraint failed') || msg.contains('787');
  }
}
