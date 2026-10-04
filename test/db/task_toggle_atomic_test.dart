import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:kisan_dost/database/db_helper.dart';
import 'package:kisan_dost/providers/task_provider.dart';

/// Atomicity tests for [TaskProvider.toggleTaskCompletion].
///
/// The farmer-visible contract: each tap on a task's checkbox flips its
/// state exactly once. Rapid double-taps used to race a read-modify-write
/// on a stale UI snapshot — both taps could read "incomplete" and both
/// write "complete", leaving a non-deterministic final state plus
/// duplicate audit rows. The toggle is now a single atomic SQL statement.
void main() {
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  late Database db;
  late TaskProvider tasks;

  Future<Database> openFreshDb() {
    return openDatabase(
      inMemoryDatabasePath,
      onConfigure: (db) async {
        await db.execute('PRAGMA foreign_keys = ON');
      },
    );
  }

  Future<bool> isCompleted(int id) async {
    final rows = await db.query(
      'tasks',
      columns: ['is_completed'],
      where: 'id = ?',
      whereArgs: [id],
    );
    return rows.single['is_completed'] == 1;
  }

  Future<int> auditCount(int id) async {
    final rows = await db.query(
      'audit_log',
      where: 'table_name = ? AND row_id = ?',
      whereArgs: ['tasks', id],
    );
    return rows.length;
  }

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    db = await openFreshDb();
    await DatabaseHelper.instance.createFreshSchemaForTests(db);
    tasks = TaskProvider(testExecutor: db);
  });

  tearDown(() async {
    await db.close();
  });

  test('a single toggle flips the state exactly once', () async {
    // Past date: the notification scheduler skips it, so the test never
    // touches real plugin scheduling.
    await tasks.addTask('پانی لگانا', null, DateTime(2020, 1, 1));
    await tasks.fetchTasks();
    final id = tasks.tasks.single.id;
    expect(await isCompleted(id), isFalse);

    await tasks.toggleTaskCompletion(id);
    expect(await isCompleted(id), isTrue);

    await tasks.toggleTaskCompletion(id);
    expect(await isCompleted(id), isFalse);
  });

  test('rapid double toggle is deterministic: two flips, net zero change',
      () async {
    await tasks.addTask('پانی لگانا', null, DateTime(2020, 1, 1));
    await tasks.fetchTasks();
    final id = tasks.tasks.single.id;
    expect(await isCompleted(id), isFalse);

    // Two taps fired without awaiting in between — the way rapid taps
    // arrive from the UI (callers fire this unawaited).
    await Future.wait([
      tasks.toggleTaskCompletion(id),
      tasks.toggleTaskCompletion(id),
    ]);

    // Each tap flipped exactly once: false -> true -> false.
    // (The old read-modify-write could leave this stuck at true.)
    expect(await isCompleted(id), isFalse);
    expect(tasks.tasks.single.isCompleted, isFalse);
    // One audit row per tap — no duplicates, no lost rows.
    expect(await auditCount(id), 3); // create + 2 toggles
  });

  test('toggling a missing or trashed task is a silent no-op', () async {
    await tasks.toggleTaskCompletion(9999);
    expect(await auditCount(9999), 0);

    await tasks.addTask('پانی لگانا', null, DateTime(2020, 1, 1));
    await tasks.fetchTasks();
    final id = tasks.tasks.single.id;
    await tasks.deleteTask(id); // soft-delete
    final auditsBefore = await auditCount(id);

    await tasks.toggleTaskCompletion(id);

    // A trashed task is never resurrected by a toggle.
    expect(await isCompleted(id), isFalse);
    expect(await auditCount(id), auditsBefore);
  });
}
