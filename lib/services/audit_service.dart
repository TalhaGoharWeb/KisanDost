import 'package:sqflite/sqflite.dart';

import '../database/db_helper.dart';

/// Append-only audit trail: every create/update/delete on the app's tables
/// writes one row here describing what changed. There is deliberately NO
/// delete or update API for audit rows, and the UI never offers per-row
/// deletion — the log is the farmer's proof of what happened to their data.
///
/// `details` is a SHORT human summary (Urdu OK), e.g.
/// "خرچ 5,000 روپے — کھاد". Never full rows, never PII dumps.
///
/// The log call takes a [DatabaseExecutor] so providers can write the audit
/// row inside the SAME transaction as the change it describes.
class AuditService {
  AuditService._();

  static const String create = 'create';
  static const String update = 'update';

  /// Hard delete (theka/ushr paths that still hard-delete; everything else
  /// soft-deletes).
  static const String delete = 'delete';
  static const String softDelete = 'soft_delete';
  static const String restore = 'restore';
  static const String permanentDelete = 'permanent_delete';

  /// Writes one audit row. Best-effort when the `audit_log` table is
  /// absent: hermetic unit tests run providers against minimal stand-in
  /// tables, and logging must not break them. In production the v15
  /// migration always creates the table, so any OTHER database error is
  /// rethrown loudly.
  static Future<void> log(
    DatabaseExecutor db, {
    required String table,
    required int rowId,
    required String action,
    String? details,
  }) async {
    final now = DateTime.now().toIso8601String();
    try {
      await db.insert('audit_log', {
        'ts': now,
        'table_name': table,
        'row_id': rowId,
        'action': action,
        'details': details,
        'created_at': now,
      });
    } on DatabaseException catch (e) {
      if (!e.toString().contains('no such table')) rethrow;
    }
  }

  /// Audit rows for one record, newest first. Used by tests and any future
  /// history view. Returns an empty list when the table is absent.
  static Future<List<Map<String, dynamic>>> historyFor(
    DatabaseExecutor db,
    String table,
    int rowId,
  ) async {
    try {
      return await db.query(
        'audit_log',
        where: 'table_name = ? AND row_id = ?',
        whereArgs: [table, rowId],
        orderBy: 'id DESC',
      );
    } on DatabaseException catch (e) {
      if (!e.toString().contains('no such table')) rethrow;
      return [];
    }
  }

  /// Every audit row, newest first. Powers the audit-log viewer screen.
  /// Pass an [executor] in tests; production callers omit it and read the
  /// app database. Returns an empty list when the table is absent.
  static Future<List<Map<String, dynamic>>> listAll({
    DatabaseExecutor? executor,
    int limit = 500,
  }) async {
    try {
      final db = executor ?? await DatabaseHelper.instance.database;
      return await db.query('audit_log', orderBy: 'id DESC', limit: limit);
    } on DatabaseException catch (e) {
      if (!e.toString().contains('no such table')) rethrow;
      return [];
    }
  }
}
