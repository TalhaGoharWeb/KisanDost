import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:kisan_dost/database/db_helper.dart';
import 'package:kisan_dost/providers/task_provider.dart';
import 'package:kisan_dost/services/notification_service.dart';

/// Hermetic tests for TaskProvider ↔ NotificationService interactions.
///
/// The native AlarmManager and the notification plugin have no backend in
/// unit tests, and scheduling is deliberately best-effort (a reminder
/// failure must NEVER break task CRUD). These tests pin that contract:
/// * every task mutation completes without throwing, even with the
///   notification backend unavailable;
/// * the database state after each operation is exactly what the alarm
///   subsystem expects (live vs trashed vs completed rows);
/// * the scheduling decision logic (skip completed, skip past one-shots)
///   is exercised through NotificationService directly.
///
/// Plugin-call observability is covered by
/// test/db/audit_regression_test.dart (F2: restoreTask re-arms alarms).
void main() {
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  TestWidgetsFlutterBinding.ensureInitialized();
  SharedPreferences.setMockInitialValues({});
  // Notification plugin/backend calls are no-ops in tests.
  for (final name in [
    'com.talhagohar.kisandost/share',
    'dexterx.dev/flutter_local_notifications',
  ]) {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(MethodChannel(name), (call) async => null);
  }

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

  Future<TaskProvider> seedOneTask(Database db) async {
    final tasks = TaskProvider(testExecutor: db);
    await tasks.addTask(
      'Water the wheat',
      'Morning irrigation',
      DateTime.now().add(const Duration(days: 1)),
    );
    return tasks;
  }

  group('best-effort contract: mutations never throw', () {
    test('addTask completes with the backend unavailable', () async {
      final db = await openFreshDb();
      final tasks = TaskProvider(testExecutor: db);

      await tasks.addTask(
        'Evening chore',
        null,
        DateTime.now().add(const Duration(hours: 2)),
      );

      expect(tasks.tasks, hasLength(1));
      await db.close();
    });

    test('deleteTask completes and soft-deletes the row', () async {
      final db = await openFreshDb();
      final tasks = await seedOneTask(db);
      final id = tasks.tasks.first.id;

      await tasks.deleteTask(id);

      expect(tasks.tasks.where((t) => t.id == id), isEmpty);
      final rows =
          await db.query('tasks', where: 'id = ?', whereArgs: [id]);
      expect(rows.single['deleted_at'], isNotNull,
          reason: 'trash hides the row; the alarm layer filters on deleted_at');
      await db.close();
    });

    test('restoreTask brings the row back to the live list', () async {
      final db = await openFreshDb();
      final tasks = await seedOneTask(db);
      final id = tasks.tasks.first.id;

      await tasks.deleteTask(id);
      await tasks.restoreTask(id);

      expect(tasks.tasks.where((t) => t.id == id), hasLength(1));
      final rows =
          await db.query('tasks', where: 'id = ?', whereArgs: [id]);
      expect(rows.single['deleted_at'], isNull);
      await db.close();
    });

    test('toggleTaskCompletion flips state without throwing', () async {
      final db = await openFreshDb();
      final tasks = await seedOneTask(db);
      final id = tasks.tasks.first.id;

      await tasks.toggleTaskCompletion(id);
      expect(tasks.tasks.firstWhere((t) => t.id == id).isCompleted, isTrue);

      await tasks.toggleTaskCompletion(id);
      expect(tasks.tasks.firstWhere((t) => t.id == id).isCompleted, isFalse);
      await db.close();
    });
  });

  group('scheduling decision logic (NotificationService)', () {
    test('scheduling a completed task is a silent no-op', () async {
      final task = TaskItem(
        id: 42,
        title: 'Done chore',
        dateTime: DateTime.now().add(const Duration(days: 1)),
        isCompleted: true,
      );
      // Must not throw; completed tasks simply get no reminder.
      await NotificationService().scheduleTaskNotifications(task);
    });

    test('scheduling a past one-shot task is a silent no-op', () async {
      final task = TaskItem(
        id: 43,
        title: 'Missed chore',
        dateTime: DateTime.now().subtract(const Duration(days: 1)),
      );
      await NotificationService().scheduleTaskNotifications(task);
    });

    test('cancelling a never-scheduled task is a silent no-op', () async {
      await NotificationService().cancelTaskNotifications(999999);
    });
  });
}
