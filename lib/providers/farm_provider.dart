import 'package:flutter/material.dart';
import 'package:sqflite/sqflite.dart';
import '../database/db_helper.dart';
import '../models/models.dart';
import '../services/audit_service.dart';
import '../services/quantity.dart';

class FarmProvider extends ChangeNotifier {
  /// Test hook: when set, all DB access goes through this executor instead
  /// of the app singleton, so tests never touch the real database file.
  final DatabaseExecutor? testExecutor;

  FarmProvider({this.testExecutor});

  Future<DatabaseExecutor> _db() async =>
      testExecutor ?? await DatabaseHelper.instance.database;

  /// Runs [action] inside a real transaction when the executor is a full
  /// [Database]; a bare [Transaction] (or any other executor a test hands
  /// in) already runs inside one, so the action runs directly.
  /// (Owner decision #5: delete + its audit row must be atomic.)
  Future<T> _txn<T>(Future<T> Function(DatabaseExecutor txn) action) async {
    final db = await _db();
    if (db is Database) {
      return await db.transaction(action);
    }
    return await action(db);
  }

  List<Farm> _farms = [];
  final Map<int, List<Field>> _farmFields = {}; // farmId -> fields

  List<Farm> get farms => _farms;

  /// Last load failure, if any. Sections show it as a retryable Urdu error.
  String? _errorMessage;
  String? get errorMessage => _errorMessage;

  List<Field> getFieldsForFarm(int farmId) {
    return _farmFields[farmId] ?? [];
  }

  Future<void> fetchFarms() async {
    _errorMessage = null;
    try {
      await _fetchFarms();
    } catch (_) {
      _errorMessage = 'زمینوں کی فہرست لوڈ نہیں ہو سکی۔ دوبارہ کوشش کریں۔';
      notifyListeners();
    }
  }

  Future<void> _fetchFarms() async {
    final db = await _db();
    final List<Map<String, dynamic>> maps = await db.query(
      'farms',
      orderBy: 'id DESC',
    );
    _farms = List.generate(maps.length, (i) => Farm.fromMap(maps[i]));

    // Fetch fields for all fetched farms
    for (var farm in _farms) {
      if (farm.id != null) {
        await fetchFields(farm.id!);
      }
    }
    notifyListeners();
  }

  Future<void> addFarm(String name, double totalArea) async {
    final db = await _db();
    final newFarm = Farm(
      name: name,
      totalArea: totalArea,
      createdAt: DateTime.now().toIso8601String(),
    );
    await db.insert('farms', newFarm.toMap());
    await fetchFarms();
  }

  Future<void> fetchFields(int farmId) async {
    // Keep the last good list on DB failure; the failure is reported,
    // never thrown (callers may fire this unawaited at launch).
    try {
      final db = await _db();
      final List<Map<String, dynamic>> maps = await db.query(
        'fields',
        where: 'farm_id = ?',
        whereArgs: [farmId],
        orderBy: 'id DESC',
      );
      _farmFields[farmId] = List.generate(
        maps.length,
        (i) => Field.fromMap(maps[i]),
      );
    } catch (e) {
      debugPrint('fetchFields failed: $e');
    }
    notifyListeners();
  }

  Future<void> addField({
    required int farmId,
    required String name,
    required double sizeAcres,
    int canalWaterAvailable = 0,
    int tubeWellAvailable = 0,
    String? location,
  }) async {
    Quantity.requireFinite(sizeAcres);
    final db = await _db();
    final newField = Field(
      farmId: farmId,
      name: name,
      sizeAcres: sizeAcres,
      canalWaterAvailable: canalWaterAvailable,
      tubeWellAvailable: tubeWellAvailable,
      location: location,
    );
    await db.insert('fields', newField.toMap());
    await fetchFields(farmId);
  }

  Future<void> updateFarm(int id, String name, double totalArea) async {
    final db = await _db();
    await db.update(
      'farms',
      {'name': name, 'total_area': totalArea},
      where: 'id = ?',
      whereArgs: [id],
    );
    await fetchFarms();
  }

  /// Hard-deletes a farm. Its fields cascade via FK (disclosed in the UI
  /// confirmation); the audit log keeps the record so the delete is never
  /// silent. Atomic (owner decision #5): delete + audit row are one
  /// transaction. Idempotent: deleting a missing farm is a safe no-op.
  Future<void> deleteFarm(int id) async {
    await _txn((txn) async {
      final existing = await txn.query(
        'farms',
        columns: const ['name'],
        where: 'id = ?',
        whereArgs: [id],
        limit: 1,
      );
      if (existing.isEmpty) return;
      final fieldCount =
          Sqflite.firstIntValue(
            await txn.rawQuery(
              'SELECT COUNT(*) FROM fields WHERE farm_id = ?',
              [id],
            ),
          ) ??
          0;
      await AuditService.log(
        txn,
        table: 'farms',
        rowId: id,
        action: AuditService.delete,
        details:
            'زمین حذف — ${existing.first['name']}'
            '${fieldCount == 0 ? '' : ' ($fieldCount کھیت سمیت)'}',
      );
      await txn.delete('farms', where: 'id = ?', whereArgs: [id]);
    });
    await fetchFarms();
  }

  Future<void> updateField({
    required int id,
    required int farmId,
    required String name,
    required double sizeAcres,
    int canalWaterAvailable = 0,
    int tubeWellAvailable = 0,
    String? location,
  }) async {
    Quantity.requireFinite(sizeAcres);
    final db = await _db();
    await db.update(
      'fields',
      {
        'name': name,
        'size_acres': sizeAcres,
        'canal_water_available': canalWaterAvailable,
        'tube_well_available': tubeWellAvailable,
        'location': location,
      },
      where: 'id = ?',
      whereArgs: [id],
    );
    await fetchFields(farmId);
  }

  /// Hard-deletes one field. Atomic (owner decision #5): delete + audit
  /// row are one transaction. Idempotent: deleting a missing field is a
  /// safe no-op.
  Future<void> deleteField(int id, int farmId) async {
    await _txn((txn) async {
      final existing = await txn.query(
        'fields',
        columns: const ['name'],
        where: 'id = ?',
        whereArgs: [id],
        limit: 1,
      );
      if (existing.isEmpty) return;
      await AuditService.log(
        txn,
        table: 'fields',
        rowId: id,
        action: AuditService.delete,
        details: 'کھیت حذف — ${existing.first['name']}',
      );
      await txn.delete('fields', where: 'id = ?', whereArgs: [id]);
    });
    await fetchFields(farmId);
  }
}
