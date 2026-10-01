import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite/sqflite.dart';

import '../database/db_helper.dart';
import '../models/batai.dart';
import '../models/models.dart';
import '../models/party.dart';
import '../providers/batai_provider.dart';
import '../providers/crop_provider.dart';
import '../providers/expense_provider.dart';
import '../providers/farm_provider.dart';
import '../providers/harvest_provider.dart';
import '../providers/inventory_provider.dart';
import '../providers/party_provider.dart';
import '../providers/task_provider.dart';
import '../providers/theka_provider.dart';
import 'audit_service.dart';

/// Demo mode: inserts a coherent sample dataset through the REAL providers
/// (so demo rows exercise the same validation, ledger and audit paths as
/// farmer-entered data), clearly labeled as demo, and removes exactly those
/// rows on exit.
///
/// Every inserted row id is tracked per table in SharedPreferences
/// ([idsKey]); no schema change was needed. Cleanup deletes children before
/// parents and never crashes on FK conflicts — a blocked table is skipped
/// and reported in Urdu.
class DemoDataService extends ChangeNotifier {
  /// Test hook: when set, all DB access goes through this executor instead
  /// of the app singleton, so tests never touch the real database file.
  final DatabaseExecutor? testExecutor;

  DemoDataService({this.testExecutor});

  static const String activeKey = 'demo_active';
  static const String idsKey = 'demo_row_ids';

  /// Tables whose demo row ids are tracked, in insert order.
  static const List<String> trackedTables = [
    'farms',
    'fields',
    'crop_seasons',
    'expenses',
    'harvests',
    'sales',
    'tasks',
    'inventory',
    'inventory_transactions',
    'parties',
    'party_ledger_entries',
    'thekas',
    'theka_installments',
    'batai_agreements',
    'batai_settlements',
  ];

  /// Cleanup order: children before parents. (crop_season_fields,
  /// sales→harvests and theka_installments→thekas are ON DELETE CASCADE,
  /// but explicit child-first deletes keep the order safe regardless.)
  static const List<String> deleteOrder = [
    'inventory_transactions',
    'party_ledger_entries',
    'batai_settlements',
    'sales',
    'theka_installments',
    'expenses',
    'harvests',
    'tasks',
    'inventory',
    'batai_agreements',
    'crop_seasons',
    'fields',
    'thekas',
    'farms',
    'parties',
  ];

  bool _active = false;
  bool get isActive => _active;

  Future<DatabaseExecutor> _ex() async =>
      testExecutor ?? await DatabaseHelper.instance.database;

  Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    _active = prefs.getBool(activeKey) ?? false;
    notifyListeners();
  }

  /// True when any of the main tables already hold rows (used to warn before
  /// adding demo rows alongside the farmer's own data).
  Future<bool> hasRealData() async {
    final db = await _ex();
    for (final t in ['farms', 'expenses', 'tasks', 'parties', 'harvests']) {
      final rows = await db.rawQuery('SELECT COUNT(*) AS c FROM $t');
      if ((rows.first['c'] as int? ?? 0) > 0) return true;
    }
    return false;
  }

  Future<int> _maxId(String table) async {
    final db = await _ex();
    final rows = await db.rawQuery('SELECT MAX(id) AS m FROM $table');
    return (rows.first['m'] as int?) ?? 0;
  }

  Future<List<int>> _newIds(String table, int beforeMax) async {
    final db = await _ex();
    final rows = await db.query(
      table,
      columns: ['id'],
      where: 'id > ?',
      whereArgs: [beforeMax],
    );
    return [for (final r in rows) r['id'] as int];
  }

  /// Convenience for screens: reads all providers from [context].
  Future<void> enterDemoFromContext(BuildContext context) {
    return enterDemo(
      farms: context.read<FarmProvider>(),
      crops: context.read<CropProvider>(),
      expenses: context.read<ExpenseProvider>(),
      harvests: context.read<HarvestProvider>(),
      tasks: context.read<TaskProvider>(),
      parties: context.read<PartyProvider>(),
      inventory: context.read<InventoryProvider>(),
      thekas: context.read<ThekaProvider>(),
      batai: context.read<BataiProvider>(),
    );
  }

  Future<void> enterDemo({
    required FarmProvider farms,
    required CropProvider crops,
    required ExpenseProvider expenses,
    required HarvestProvider harvests,
    required TaskProvider tasks,
    required PartyProvider parties,
    required InventoryProvider inventory,
    required ThekaProvider thekas,
    required BataiProvider batai,
  }) async {
    if (_active) return;
    final before = <String, int>{};
    for (final t in trackedTables) {
      before[t] = await _maxId(t);
    }
    try {
      final now = DateTime.now();
      String d(int offsetDays) {
        final day = DateTime(
          now.year,
          now.month,
          now.day,
        ).add(Duration(days: offsetDays));
        return '${day.year}-${day.month.toString().padLeft(2, '0')}-${day.day.toString().padLeft(2, '0')}';
      }

      // 1. Farm + fields.
      await farms.addFarm('ڈیمو فارم', 12.5);
      final farmId = (await _newIds('farms', before['farms']!)).single;
      await farms.addField(farmId: farmId, name: 'ڈیمو کھیت ۱', sizeAcres: 6);
      await farms.addField(farmId: farmId, name: 'ڈیمو کھیت ۲', sizeAcres: 6.5);
      final fieldIds = await _newIds('fields', before['fields']!);

      // 2. Crop seasons.
      await crops.addCropSeason(
        fieldIds: fieldIds,
        cropName: 'گندم',
        variety: 'فیصل آباد 2008',
        startDate: d(-120),
      );
      await crops.addCropSeason(
        fieldIds: [fieldIds.last],
        cropName: 'کپاس',
        variety: 'FH-492',
        startDate: d(-60),
      );
      final seasonIds = await _newIds('crop_seasons', before['crop_seasons']!);
      final wheat = seasonIds.first;
      final cotton = seasonIds.last;

      // 3. Expenses (amounts in paisa).
      final expenseRows = [
        ('Fertilizer', 1500000, 'کھاد — ڈیمو', wheat, -100),
        ('Seeds', 800000, 'بیج — ڈیمو', wheat, -115),
        ('Water', 300000, 'ٹوئیل کا پانی — ڈیمو', wheat, -90),
        ('Labour', 500000, 'مزدوری — ڈیمو', wheat, -80),
        ('Sprays', 450000, 'سپرے — ڈیمو', cotton, -40),
        ('Diesel', 600000, 'ڈیزل — ڈیمو', cotton, -35),
        ('Fertilizer', 1200000, 'کھاد — ڈیمو', cotton, -30),
        ('Labour', 400000, 'مزدوری — ڈیمو', cotton, -20),
      ];
      for (final e in expenseRows) {
        await expenses.addExpense(
          category: e.$1,
          amountPaisa: e.$2,
          date: d(e.$5),
          description: e.$3,
          cropSeasonId: e.$4,
        );
      }

      // 4. Harvests + one sale.
      await harvests.addHarvest(
        cropSeasonId: wheat,
        quantity: 1600,
        unit: 'kg',
        date: d(-10),
        ratePerUnitPaisa: 11000,
      );
      final harvestId = (await _newIds('harvests', before['harvests']!)).single;
      await harvests.recordSale(
        harvestId: harvestId,
        quantity: 1600,
        pricePerUnitPaisa: 11000,
        date: d(-9),
        buyerName: 'ڈیمو آڑھتی',
      );
      await harvests.addHarvest(
        cropSeasonId: cotton,
        quantity: 1000,
        unit: 'kg',
        date: d(-5),
      );

      // 5. Tasks.
      await tasks.addTask(
        'پانی لگائیں',
        'ڈیمو کام',
        now.add(const Duration(days: 1)),
      );
      await tasks.addTask(
        'کھاد ڈالیں',
        'ڈیمو کام',
        now.add(const Duration(days: 3)),
      );
      await tasks.addTask(
        'سپرے کریں',
        'ڈیمو کام',
        now.subtract(const Duration(days: 1)),
      );

      // 6. Inventory purchases (cost in paisa per unit).
      await inventory.recordPurchase(
        category: 'کھاد',
        name: 'یوریا',
        unit: 'بوری',
        quantity: 10,
        costPerUnitPaisa: 450000,
        weightPerUnitKg: 50,
      );
      await inventory.recordPurchase(
        category: 'کھاد',
        name: 'ڈی اے پی',
        unit: 'بوری',
        quantity: 5,
        costPerUnitPaisa: 1200000,
        weightPerUnitKg: 50,
      );
      await inventory.recordPurchase(
        category: 'بیج',
        name: 'گندم بیج',
        unit: 'بوری',
        quantity: 4,
        costPerUnitPaisa: 600000,
        weightPerUnitKg: 50,
      );
      await inventory.recordPurchase(
        category: 'سپرے',
        name: 'سپرے دوا',
        unit: 'بوتل',
        quantity: 6,
        costPerUnitPaisa: 150000,
      );

      // 7. Party + ledger entries.
      final partyId = await parties.addParty(
        Party(name: 'ڈیمو آڑھتی', createdAt: now.toIso8601String()),
      );
      await parties.addEntry(
        partyId: partyId,
        type: PartyEntryType.udhaarDiya,
        amountPaisa: 2000000,
        date: d(-20),
        note: 'ڈیمو',
      );
      await parties.addEntry(
        partyId: partyId,
        type: PartyEntryType.wusooli,
        amountPaisa: 500000,
        date: d(-5),
        note: 'ڈیمو',
      );

      // 8. Theka with two installments.
      await thekas.addTheka(
        Theka(
          farmId: farmId,
          totalAmountPaisa: 20000000,
          durationType: 'Seasonal',
          durationDetails: 'ربیع 2026',
          paymentMethod: 'Installment',
          startDate: d(-100),
          createdAt: now.toIso8601String(),
        ),
        [
          ThekaInstallment(
            thekaId: 0,
            amountPaisa: 10000000,
            dueDate: d(30),
            status: 'Pending',
          ),
          ThekaInstallment(
            thekaId: 0,
            amountPaisa: 10000000,
            dueDate: d(90),
            status: 'Pending',
          ),
        ],
      );

      // 9. Batai agreement with the demo party.
      await batai.createAgreement(
        farmerRole: FarmerRole.landowner,
        otherPartyId: partyId,
        farmId: farmId,
        fieldId: fieldIds.first,
        cropSeasonId: wheat,
        ownerSharePercent: 50,
        cultivatorSharePercent: 50,
        expenseNote: 'ڈیمو: کھاد مالک کی، مزدوری مزارع کی',
        startDate: d(-120),
        notes: 'ڈیمو معاہدہ',
      );

      // Collect every tracked id.
      final ids = <String, List<int>>{};
      for (final t in trackedTables) {
        ids[t] = await _newIds(t, before[t]!);
      }

      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(idsKey, jsonEncode(ids));
      await prefs.setBool(activeKey, true);
      _active = true;

      final db = await _ex();
      await AuditService.log(
        db,
        table: 'demo',
        rowId: 0,
        action: 'demo_enter',
        details: 'ڈیمو ڈیٹا شامل کیا گیا',
      );
      notifyListeners();
    } catch (e) {
      // Never leave half-inserted demo rows behind: remove anything new.
      await _cleanupPartial(before);
      rethrow;
    }
  }

  Future<void> _cleanupPartial(Map<String, int> before) async {
    final db = await _ex();
    for (final t in deleteOrder) {
      try {
        await db.delete(t, where: 'id > ?', whereArgs: [before[t] ?? 0]);
      } catch (_) {}
    }
  }

  /// Removes exactly the tracked demo rows, children before parents.
  /// A table blocked by the farmer's own rows referencing demo rows is
  /// skipped (never a crash) and reported in the returned message.
  Future<DemoExitResult> exitDemo() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(idsKey);
    final Map<String, dynamic> ids =
        raw == null ? {} : jsonDecode(raw) as Map<String, dynamic>;

    final db = await _ex();
    final blocked = <String>[];
    for (final t in deleteOrder) {
      final list = (ids[t] as List?)?.map((e) => e as int).toList() ?? [];
      if (list.isEmpty) continue;
      try {
        await db.delete(
          t,
          where: 'id IN (${List.filled(list.length, '?').join(',')})',
          whereArgs: list,
        );
      } catch (_) {
        blocked.add(_urduTableName(t));
      }
    }

    if (blocked.isEmpty) {
      await prefs.remove(idsKey);
      await prefs.setBool(activeKey, false);
      _active = false;
      await AuditService.log(
        db,
        table: 'demo',
        rowId: 0,
        action: 'demo_exit',
        details: 'ڈیمو ڈیٹا ختم کیا گیا',
      );
      notifyListeners();
      return const DemoExitResult.ok();
    }
    // Some demo rows survive (the farmer linked their own records to them):
    // stay in demo mode so the banner persists and they can retry.
    notifyListeners();
    return DemoExitResult.blocked(
      'کچھ ڈیمو ڈیٹا حذف نہ ہو سکا کیونکہ آپ کا اپنا ریکارڈ اس سے جڑا ہے '
      '(${blocked.join('، ')})۔ پہلے وہ ریکارڈ ہٹائیں، پھر دوبارہ کوشش کریں۔',
    );
  }

  static String _urduTableName(String table) {
    return switch (table) {
      'parties' => 'پارٹیاں',
      'crop_seasons' => 'فصلیں',
      'farms' => 'زمینیں',
      'fields' => 'کھیت',
      'harvests' => 'پیداوار',
      'expenses' => 'خرچے',
      _ => table,
    };
  }
}

/// Result of [DemoDataService.exitDemo]: either fully cleaned, or blocked
/// with an Urdu explanation of what survived and why.
class DemoExitResult {
  final bool ok;
  final String? message;

  const DemoExitResult.ok() : ok = true, message = null;
  const DemoExitResult.blocked(this.message) : ok = false;
}
