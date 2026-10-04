import 'package:flutter/material.dart';
import 'package:sqflite/sqflite.dart';
import '../database/db_helper.dart';
import '../services/audit_service.dart';
import '../services/notification_service.dart';

class TaskItem {
  final int id;
  final String title;
  final String? description;
  final DateTime? snoozedUntil;
  final DateTime dateTime;
  bool isCompleted;
  final String recurrence;
  final String reminders; // comma separated minutes before, e.g. "0,60,1440"

  /// ISO timestamp of soft deletion; NULL = live row. Never in [toMap].
  final String? deletedAt;

  TaskItem({
    required this.id,
    required this.title,
    this.description,
    this.snoozedUntil,
    required this.dateTime,
    this.isCompleted = false,
    this.recurrence = 'none',
    this.reminders = '0',
    this.deletedAt,
  });

  factory TaskItem.fromMap(Map<String, dynamic> map) {
    return TaskItem(
      id: map['id'],
      title: map['title'],
      description: map['description'],
      snoozedUntil:
          map['snoozed_until'] != null
              // tryParse: a corrupt timestamp must not nuke the whole list.
              ? DateTime.tryParse(map['snoozed_until'] as String)
              : null,
      dateTime: DateTime.parse(map['date_time']),
      isCompleted: map['is_completed'] == 1,
      recurrence: map['recurrence'] ?? 'none',
      reminders: map['reminders'] ?? '0',
      deletedAt: map['deleted_at'] as String?,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'title': title,
      'description': description,
      'snoozed_until': snoozedUntil?.toIso8601String(),
      'date_time': dateTime.toIso8601String(),
      'is_completed': isCompleted ? 1 : 0,
      'recurrence': recurrence,
      'reminders': reminders,
    };
  }
}

class TaskProvider with ChangeNotifier {
  /// Test hook: when set, all DB access goes through this executor instead
  /// of the app singleton, so tests never touch the real database file.
  final DatabaseExecutor? testExecutor;

  TaskProvider({this.testExecutor});

  Future<DatabaseExecutor> _db() async =>
      testExecutor ?? await DatabaseHelper.instance.database;

  List<TaskItem> _tasks = [];
  bool _isLoading = false;

  /// Last load failure, if any. Sections show it as a retryable Urdu error.
  String? _errorMessage;
  String? get errorMessage => _errorMessage;

  List<TaskItem> get tasks => _tasks;
  bool get isLoading => _isLoading;

  Future<void> fetchTasks() async {
    _errorMessage = null;
    try {
      await _fetchTasks();
    } catch (_) {
      _errorMessage = 'کاموں کی فہرست لوڈ نہیں ہو سکی۔ دوبارہ کوشش کریں۔';
      notifyListeners();
    }
  }

  Future<void> _fetchTasks() async {
    _isLoading = true;
    notifyListeners();

    final db = await _db();
    final List<Map<String, dynamic>> maps = await db.query(
      'tasks',
      where: 'deleted_at IS NULL',
      orderBy: 'date_time ASC',
    );

    _tasks = maps.map((e) => TaskItem.fromMap(e)).toList();
    _isLoading = false;
    notifyListeners();
  }

  Future<void> addTask(
    String title,
    String? description,
    DateTime dateTime, {
    String recurrence = 'none',
    String reminders = '0',
  }) async {
    final db = await _db();
    int id = 0;

    try {
      id = await db.insert('tasks', {
        'title': title,
        'description': description,
        'snoozed_until': null,
        'date_time': dateTime.toIso8601String(),
        'is_completed': 0,
        'recurrence': recurrence,
        'reminders': reminders,
      });
    } catch (e) {
      debugPrint(
        'Error inserting task: $e. Attempting self-healing database fix.',
      );
      try {
        await db.execute("ALTER TABLE tasks ADD COLUMN description TEXT");
      } catch (_) {}
      try {
        await db.execute("ALTER TABLE tasks ADD COLUMN snoozed_until TEXT");
      } catch (_) {}
      try {
        id = await db.insert('tasks', {
          'title': title,
          'description': description,
          'snoozed_until': null,
          'date_time': dateTime.toIso8601String(),
          'is_completed': 0,
          'recurrence': recurrence,
          'reminders': reminders,
        });
      } catch (retryError) {
        debugPrint('Self-healing database fix failed on insert: $retryError');
      }
    }

    // Refresh local list and notify UI
    await fetchTasks();

    if (id != 0) {
      await AuditService.log(
        db,
        table: 'tasks',
        rowId: id,
        action: AuditService.create,
        details: 'کام: $title',
      );
      TaskItem? newTask;
      for (var t in _tasks) {
        if (t.id == id) {
          newTask = t;
          break;
        }
      }
      if (newTask != null) {
        await NotificationService().scheduleTaskNotifications(newTask);
      }
    }
  }

  /// Atomically flips a task's completion flag with a single SQL statement —
  /// no read-modify-write on a possibly stale UI snapshot. Rapid double-taps
  /// (the callers fire this unawaited) serialize in SQLite: each tap flips
  /// exactly once, so the final state is deterministic and only one audit
  /// row is written per tap.
  Future<void> toggleTaskCompletion(int id) async {
    final db = await _db();

    final changed = await db.rawUpdate(
      'UPDATE tasks SET is_completed = 1 - is_completed, snoozed_until = NULL '
      'WHERE id = ? AND deleted_at IS NULL',
      [id],
    );
    if (changed == 0) {
      return;
    }

    // Refresh list and notify
    await fetchTasks();

    // Handle notifications from the post-toggle state (read back, never
    // from a stale argument).
    TaskItem? toggledTask;
    for (var t in _tasks) {
      if (t.id == id) {
        toggledTask = t;
        break;
      }
    }

    if (toggledTask != null) {
      await AuditService.log(
        db,
        table: 'tasks',
        rowId: id,
        action: AuditService.update,
        details: toggledTask.isCompleted ? 'کام مکمل' : 'کام دوبارہ کھولا گیا',
      );
      if (toggledTask.isCompleted) {
        await NotificationService().cancelTaskNotifications(id);
      } else {
        await NotificationService().scheduleTaskNotifications(toggledTask);
      }
    }
  }

  Future<void> updateTask(
    int id,
    String title,
    String? description,
    DateTime dateTime, {
    String recurrence = 'none',
    String reminders = '0',
  }) async {
    final db = await _db();

    final values = {
      'title': title,
      'description': description,
      'snoozed_until': null, // Clear snooze on edits
      'date_time': dateTime.toIso8601String(),
      'recurrence': recurrence,
      'reminders': reminders,
    };
    try {
      await db.update('tasks', values, where: 'id = ?', whereArgs: [id]);
    } catch (e) {
      debugPrint(
        'Error updating task: $e. Attempting self-healing database fix.',
      );
      try {
        await db.execute("ALTER TABLE tasks ADD COLUMN description TEXT");
      } catch (_) {}
      try {
        await db.execute("ALTER TABLE tasks ADD COLUMN snoozed_until TEXT");
      } catch (_) {}
      try {
        await db.update('tasks', values, where: 'id = ?', whereArgs: [id]);
      } catch (retryError) {
        debugPrint('Self-healing database fix failed on update: $retryError');
      }
    }
    await AuditService.log(
      db,
      table: 'tasks',
      rowId: id,
      action: AuditService.update,
      details: 'کام: $title',
    );

    // Refresh local list and notify UI
    await fetchTasks();

    TaskItem? updatedTask;
    for (var t in _tasks) {
      if (t.id == id) {
        updatedTask = t;
        break;
      }
    }
    if (updatedTask != null) {
      await NotificationService().scheduleTaskNotifications(updatedTask);
    }
  }

  /// Soft delete: the task is hidden everywhere but kept for history and
  /// the recycle bin. Callers keep calling [deleteTask] — the name is
  /// unchanged on purpose.
  Future<void> deleteTask(int id) async {
    final db = await _db();
    final existing = await db.query('tasks', where: 'id = ?', whereArgs: [id]);
    await db.update(
      'tasks',
      {'deleted_at': DateTime.now().toIso8601String()},
      where: 'id = ?',
      whereArgs: [id],
    );
    await AuditService.log(
      db,
      table: 'tasks',
      rowId: id,
      action: AuditService.softDelete,
      details: existing.isEmpty ? 'کام حذف' : 'کام: ${existing.first['title']}',
    );

    _tasks.removeWhere((t) => t.id == id);

    // Cancel notification
    await NotificationService().cancelTaskNotifications(id);

    notifyListeners();
  }

  /// Restores a soft-deleted task (recycle bin only).
  Future<void> restoreTask(int id) async {
    final db = await _db();
    await db.update(
      'tasks',
      {'deleted_at': null},
      where: 'id = ?',
      whereArgs: [id],
    );
    await AuditService.log(
      db,
      table: 'tasks',
      rowId: id,
      action: AuditService.restore,
      details: 'کام بحال کیا گیا',
    );
    await fetchTasks();

    // The task's alarms were cancelled when it was trashed; re-arm them now
    // that it is restored. scheduleTaskNotifications is a no-op for
    // completed tasks or past one-shot reminders, and it cancels before
    // re-scheduling, so this can never create duplicates.
    // (Alarm audit 2026-10-04)
    try {
      TaskItem? restored;
      for (final t in _tasks) {
        if (t.id == id) restored = t;
      }
      if (restored != null) {
        await NotificationService().scheduleTaskNotifications(restored);
      }
    } catch (e) {
      debugPrint('Failed to reschedule alarms for restored task: $e');
    }
  }

  /// Permanent delete — offered ONLY from the recycle bin, with the caller's
  /// destructive confirmation. The audit log keeps the record.
  Future<void> permanentDeleteTask(int id) async {
    final db = await _db();
    await db.delete('tasks', where: 'id = ?', whereArgs: [id]);
    await AuditService.log(
      db,
      table: 'tasks',
      rowId: id,
      action: AuditService.permanentDelete,
      details: 'کام مستقل حذف کیا گیا',
    );
    await NotificationService().cancelTaskNotifications(id);
    await fetchTasks();
  }
}
