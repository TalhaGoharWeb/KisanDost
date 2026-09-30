import 'package:flutter/material.dart';
import '../database/db_helper.dart';
import '../models/models.dart';

class FarmProvider extends ChangeNotifier {
  List<Farm> _farms = [];
  final Map<int, List<Field>> _farmFields = {}; // farmId -> fields

  List<Farm> get farms => _farms;
  
  List<Field> getFieldsForFarm(int farmId) {
    return _farmFields[farmId] ?? [];
  }

  Future<void> fetchFarms() async {
    final db = await DatabaseHelper.instance.database;
    final List<Map<String, dynamic>> maps = await db.query('farms', orderBy: 'id DESC');
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
    final db = await DatabaseHelper.instance.database;
    final newFarm = Farm(
      name: name,
      totalArea: totalArea,
      createdAt: DateTime.now().toIso8601String(),
    );
    await db.insert('farms', newFarm.toMap());
    await fetchFarms();
  }

  Future<void> fetchFields(int farmId) async {
    final db = await DatabaseHelper.instance.database;
    final List<Map<String, dynamic>> maps = await db.query(
      'fields',
      where: 'farm_id = ?',
      whereArgs: [farmId],
      orderBy: 'id DESC',
    );
    _farmFields[farmId] = List.generate(maps.length, (i) => Field.fromMap(maps[i]));
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
    final db = await DatabaseHelper.instance.database;
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
    final db = await DatabaseHelper.instance.database;
    await db.update(
      'farms',
      {
        'name': name,
        'total_area': totalArea,
      },
      where: 'id = ?',
      whereArgs: [id],
    );
    await fetchFarms();
  }

  Future<void> deleteFarm(int id) async {
    final db = await DatabaseHelper.instance.database;
    await db.delete(
      'farms',
      where: 'id = ?',
      whereArgs: [id],
    );
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
    final db = await DatabaseHelper.instance.database;
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

  Future<void> deleteField(int id, int farmId) async {
    final db = await DatabaseHelper.instance.database;
    await db.delete(
      'fields',
      where: 'id = ?',
      whereArgs: [id],
    );
    await fetchFields(farmId);
  }
}
