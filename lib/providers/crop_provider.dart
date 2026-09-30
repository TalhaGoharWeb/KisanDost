import 'package:flutter/material.dart';
import 'package:sqflite/sqflite.dart';
import '../database/db_helper.dart';
import '../models/models.dart';

class CropSeasonWithDetails {
  final CropSeason cropSeason;
  final List<Field> fields;
  final List<String> fieldNames;
  final List<String> farmNames;
  final double totalArea;

  CropSeasonWithDetails({
    required this.cropSeason,
    required this.fields,
    required this.fieldNames,
    required this.farmNames,
    required this.totalArea,
  });

  String get fieldDisplayName {
    if (fieldNames.isEmpty) {
      return '';
    }
    if (fieldNames.length == 1) {
      return fieldNames.first;
    }
    return '${fieldNames.length} کھیت';
  }

  String get farmDisplayName {
    if (farmNames.isEmpty) {
      return '';
    }
    if (farmNames.length == 1) {
      return farmNames.first;
    }
    return farmNames.join('، ');
  }
}

class CropProvider extends ChangeNotifier {
  List<CropSeasonWithDetails> _activeCropSeasons = [];
  List<CropSeasonWithDetails> _harvestedCropSeasons = [];

  List<CropSeasonWithDetails> get activeCropSeasons => _activeCropSeasons;
  List<CropSeasonWithDetails> get harvestedCropSeasons => _harvestedCropSeasons;

  // Predefined crops and their translation to Urdu
  final Map<String, String> predefinedCrops = {
    'Wheat': 'گندم',
    'Rice': 'دھان (چاول)',
    'Cotton': 'کپاس',
    'Sugarcane': 'گنا (کماد)',
    'Maize': 'مکئی',
    'Vegetables': 'سبزیاں',
    'Fruits': 'پھل',
    'Custom': 'دیگر فصل',
  };

  // Predefined varieties
  final Map<String, List<String>> predefinedVarieties = {
    'Rice': ['IRRI-6', '1121', 'Super Basmati', 'Hybrid Rice'],
    'Maize': ['Hybrid Maize'],
    'Wheat': ['Inqalab-91', 'Faisalabad-08', 'Galaxy-13'],
    'Cotton': ['CIM-602', 'FH-142'],
    'Sugarcane': ['CPF-247', 'HSF-240'],
  };

  List<String> getDynamicTimelineForActivities(List<Activity> activities) {
    final List<Activity> sorted = List<Activity>.from(activities)
      ..sort((a, b) => a.date.compareTo(b.date));

    final List<String> timeline = [];
    for (final activity in sorted) {
      timeline.add(activity.activityType);
    }
    return timeline;
  }

  double splitAmountAcrossFields({required double amount, required int fieldCount}) {
    if (fieldCount <= 0) {
      return 0;
    }
    return amount / fieldCount;
  }

  Future<void> fetchCropSeasons() async {
    final db = await DatabaseHelper.instance.database;

    final List<Map<String, dynamic>> seasonRows = await db.rawQuery('''
      SELECT
        cs.id as cs_id,
        cs.field_id,
        cs.crop_name,
        cs.variety,
        cs.status,
        cs.start_date
      FROM crop_seasons cs
      ORDER BY cs.id DESC
    ''');

    final List<Map<String, dynamic>> mappingRows = await db.rawQuery('''
      SELECT
        csf.crop_season_id,
        f.id as field_id,
        f.farm_id,
        f.name as field_name,
        f.size_acres,
        f.canal_water_available,
        f.tube_well_available,
        f.location,
        farm.name as farm_name
      FROM crop_season_fields csf
      JOIN fields f ON csf.field_id = f.id
      JOIN farms farm ON f.farm_id = farm.id
    ''');

    final Map<int, List<Map<String, dynamic>>> seasonFieldMap = {};
    for (final row in mappingRows) {
      final int seasonId = row['crop_season_id'] as int;
      seasonFieldMap.putIfAbsent(seasonId, () => []).add(row);
    }

    _activeCropSeasons = [];
    _harvestedCropSeasons = [];

    for (final row in seasonRows) {
      final int seasonId = row['cs_id'] as int;
      List<Map<String, dynamic>> linkedFields = seasonFieldMap[seasonId] ?? [];

      // Backward compatibility fallback for old rows that may not have mapping.
      if (linkedFields.isEmpty && row['field_id'] != null) {
        final fallbackRows = await db.rawQuery('''
          SELECT
            f.id as field_id,
            f.farm_id,
            f.name as field_name,
            f.size_acres,
            f.canal_water_available,
            f.tube_well_available,
            f.location,
            farm.name as farm_name
          FROM fields f
          JOIN farms farm ON f.farm_id = farm.id
          WHERE f.id = ?
        ''', [row['field_id']]);

        if (fallbackRows.isNotEmpty) {
          linkedFields = fallbackRows;
          await db.insert(
            'crop_season_fields',
            {
              'crop_season_id': seasonId,
              'field_id': row['field_id'],
            },
            conflictAlgorithm: ConflictAlgorithm.ignore,
          );
        }
      }

      final List<Field> fields = linkedFields
          .map(
            (f) => Field(
              id: f['field_id'],
              farmId: f['farm_id'],
              name: f['field_name'],
              sizeAcres: (f['size_acres'] as num).toDouble(),
              canalWaterAvailable: f['canal_water_available'] ?? 0,
              tubeWellAvailable: f['tube_well_available'] ?? 0,
              location: f['location'],
            ),
          )
          .toList();

      final cropSeason = CropSeason(
        id: seasonId,
        fieldId: linkedFields.isNotEmpty
            ? linkedFields.first['field_id'] as int
            : row['field_id'] as int,
        cropName: row['crop_name'],
        variety: row['variety'],
        status: row['status'],
        startDate: row['start_date'],
      );

      final details = CropSeasonWithDetails(
        cropSeason: cropSeason,
        fields: fields,
        fieldNames: linkedFields.map((f) => f['field_name'] as String).toList(),
        farmNames: linkedFields
            .map((f) => f['farm_name'] as String)
            .toSet()
            .toList(),
        totalArea: fields.fold(0.0, (sum, f) => sum + f.sizeAcres),
      );

      if (cropSeason.status == 'Active') {
        _activeCropSeasons.add(details);
      } else {
        _harvestedCropSeasons.add(details);
      }
    }
    notifyListeners();
  }

  Future<void> addCropSeason({
    required List<int> fieldIds,
    required String cropName,
    required String variety,
    required String startDate,
  }) async {
    final db = await DatabaseHelper.instance.database;
    if (fieldIds.isEmpty) {
      throw ArgumentError('At least one field must be selected.');
    }

    await db.transaction((txn) async {
      final newSeason = CropSeason(
        fieldId: fieldIds.first,
        cropName: cropName,
        variety: variety,
        status: 'Active',
        startDate: startDate,
      );
      final int seasonId = await txn.insert('crop_seasons', newSeason.toMap());

      for (final fieldId in fieldIds) {
        await txn.insert(
          'crop_season_fields',
          {
            'crop_season_id': seasonId,
            'field_id': fieldId,
          },
          conflictAlgorithm: ConflictAlgorithm.ignore,
        );
      }
    });

    await fetchCropSeasons();
  }

  Future<void> updateCropSeasonStatus(int id, String status) async {
    final db = await DatabaseHelper.instance.database;
    await db.update(
      'crop_seasons',
      {'status': status},
      where: 'id = ?',
      whereArgs: [id],
    );
    await fetchCropSeasons();
  }

  Future<void> updateCropSeason({
    required int id,
    required List<int> fieldIds,
    required String cropName,
    required String variety,
    required String status,
    required String startDate,
  }) async {
    final db = await DatabaseHelper.instance.database;
    if (fieldIds.isEmpty) {
      throw ArgumentError('At least one field must be selected.');
    }

    await db.transaction((txn) async {
      await txn.update(
        'crop_seasons',
        {
          'field_id': fieldIds.first,
          'crop_name': cropName,
          'variety': variety,
          'status': status,
          'start_date': startDate,
        },
        where: 'id = ?',
        whereArgs: [id],
      );

      await txn.delete(
        'crop_season_fields',
        where: 'crop_season_id = ?',
        whereArgs: [id],
      );

      for (final fieldId in fieldIds) {
        await txn.insert(
          'crop_season_fields',
          {
            'crop_season_id': id,
            'field_id': fieldId,
          },
          conflictAlgorithm: ConflictAlgorithm.ignore,
        );
      }
    });

    await fetchCropSeasons();
  }

  Future<void> deleteCropSeason(int id) async {
    final db = await DatabaseHelper.instance.database;
    await db.delete(
      'crop_seasons',
      where: 'id = ?',
      whereArgs: [id],
    );
    await fetchCropSeasons();
  }
}
