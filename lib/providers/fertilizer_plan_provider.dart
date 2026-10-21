import 'package:flutter/foundation.dart';
import 'package:sqflite/sqflite.dart';

import '../database/db_helper.dart';
import '../models/fertilizer_plan.dart';
import '../services/audit_service.dart';

/// Saved Khaad Hisaab plans (DB v18). Soft-delete + audit, matching the
/// app's owner-policy #5: deletion is reversible (deleted_at), never a
/// silent hard delete, and the state change + audit row are atomic.
class FertilizerPlanProvider extends ChangeNotifier {
  /// Test hook: when set, all DB access goes through this executor
  /// instead of the app singleton (same pattern as FarmProvider).
  final DatabaseExecutor? testExecutor;

  FertilizerPlanProvider({this.testExecutor});

  Future<DatabaseExecutor> _db() async =>
      testExecutor ?? await DatabaseHelper.instance.database;

  Future<T> _txn<T>(Future<T> Function(DatabaseExecutor txn) action) async {
    final db = await _db();
    if (db is Database) {
      return await db.transaction(action);
    }
    return await action(db);
  }

  List<FertilizerPlan> _plans = [];
  String? _errorMessage;

  List<FertilizerPlan> get plans => _plans;
  String? get errorMessage => _errorMessage;

  Future<void> fetchPlans() async {
    _errorMessage = null;
    try {
      final db = await _db();
      final rows = await db.query(
        'fertilizer_plans',
        where: 'deleted_at IS NULL',
        orderBy: 'id DESC',
      );
      final loaded = <FertilizerPlan>[];
      for (final row in rows) {
        final itemRows = await db.query(
          'fertilizer_plan_items',
          where: 'plan_id = ?',
          whereArgs: [row['id']],
          orderBy: 'id ASC',
        );
        loaded.add(
          FertilizerPlan.fromMap(
            row,
            items: itemRows.map(FertilizerPlanItem.fromMap).toList(),
          ),
        );
      }
      _plans = loaded;
    } catch (_) {
      _errorMessage = 'کھاد کے منصوبے لوڈ نہیں ہو سکے۔ دوبارہ کوشش کریں۔';
    }
    notifyListeners();
  }

  /// Saves a plan + its items atomically. Returns the new plan id.
  Future<int> savePlan(FertilizerPlan plan) async {
    final id = await _txn((txn) async {
      final planId = await txn.insert('fertilizer_plans', plan.toMap());
      for (final item in plan.items) {
        await txn.insert('fertilizer_plan_items', {
          ...item.toMap(),
          'plan_id': planId,
        });
      }
      await AuditService.log(
        txn,
        table: 'fertilizer_plans',
        rowId: planId,
        action: AuditService.create,
        details: 'کھاد منصوبہ — ${plan.cropName} (${plan.areaAcres} ایکڑ)',
      );
      return planId;
    });
    await fetchPlans();
    return id;
  }

  /// Soft delete (recycle-bin pattern). Idempotent.
  Future<void> deletePlan(int id) async {
    final deleted = await _txn((txn) async {
      final existing = await txn.query(
        'fertilizer_plans',
        columns: const ['crop_name', 'deleted_at'],
        where: 'id = ?',
        whereArgs: [id],
        limit: 1,
      );
      if (existing.isEmpty) return false;
      if (existing.first['deleted_at'] != null) return false;
      await txn.update(
        'fertilizer_plans',
        {'deleted_at': DateTime.now().toIso8601String()},
        where: 'id = ?',
        whereArgs: [id],
      );
      await AuditService.log(
        txn,
        table: 'fertilizer_plans',
        rowId: id,
        action: AuditService.softDelete,
        details: 'کھاد منصوبہ حذف — ${existing.first['crop_name']}',
      );
      return true;
    });
    if (!deleted) return;
    _plans.removeWhere((p) => p.id == id);
    notifyListeners();
  }
}
