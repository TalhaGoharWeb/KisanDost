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
import '../providers/activity_provider.dart';
import '../providers/ushr_provider.dart';
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
    'crop_season_fields',
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
    'activities',
    'ushr_records',
  ];

  /// Tables with a soft-delete (`deleted_at`) column: rows with
  /// `deleted_at IS NULL` are the live ones.
  static const Set<String> _softDeleteTables = {
    'expenses',
    'sales',
    'harvests',
    'tasks',
    'parties',
  };

  /// Child FK relations that make deleting a demo PARENT dangerous.
  /// Each entry is (child table, child FK column, parent table).
  /// Covered relations are the ON DELETE CASCADE ones (the farmer's rows
  /// would be silently hard-deleted) and the ON DELETE RESTRICT ones (the
  /// delete would throw mid-exit). ON DELETE SET NULL relations are safe
  /// to ignore: the farmer's row survives, only unlinked.
  static const List<(String, String, String)> _childLinks = [
    // CASCADE — silent data loss without a guard.
    ('fields', 'farm_id', 'farms'),
    ('thekas', 'farm_id', 'farms'),
    ('crop_seasons', 'field_id', 'fields'),
    ('crop_season_fields', 'field_id', 'fields'),
    ('thekas', 'field_id', 'fields'),
    ('activities', 'crop_season_id', 'crop_seasons'),
    ('harvests', 'crop_season_id', 'crop_seasons'),
    ('ushr_records', 'crop_season_id', 'crop_seasons'),
    ('crop_season_fields', 'crop_season_id', 'crop_seasons'),
    ('sales', 'harvest_id', 'harvests'),
    ('theka_installments', 'theka_id', 'thekas'),
    ('inventory_transactions', 'inventory_id', 'inventory'),
    // RESTRICT — would throw mid-exit; guard up front instead.
    ('party_ledger_entries', 'party_id', 'parties'),
    ('batai_agreements', 'other_party_id', 'parties'),
    ('batai_settlements', 'agreement_id', 'batai_agreements'),
  ];

  /// Returns the demo PARENT table names whose tracked rows are referenced
  /// by at least one NON-DEMO (farmer-owned) child row. Called before any
  /// delete runs, so a blocked exit deletes nothing.
  Future<List<String>> _linkedDemoParents(
    DatabaseExecutor db,
    Map<String, dynamic> ids,
  ) async {
    final linked = <String>{};
    for (final (child, fk, parent) in _childLinks) {
      final parents =
          (ids[parent] as List?)?.map((e) => e as int).toList() ?? [];
      if (parents.isEmpty) continue;
      final childDemoIds =
          (ids[child] as List?)?.map((e) => e as int).toList() ?? [];
      final placeholders = List.filled(parents.length, '?').join(',');
      // Soft-deleted rows are already gone from the farmer's view.
      final liveOnly =
          _softDeleteTables.contains(child) ? 'AND deleted_at IS NULL' : '';
      final notDemo =
          childDemoIds.isEmpty
              ? ''
              : "AND id NOT IN (${List.filled(childDemoIds.length, '?').join(',')})";
      final rows = await db.rawQuery(
        'SELECT 1 FROM $child WHERE $fk IN ($placeholders) '
        '$liveOnly $notDemo LIMIT 1',
        [...parents, ...childDemoIds],
      );
      if (rows.isNotEmpty) linked.add(_urduTableName(parent));
    }
    return linked.toList();
  }

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
    'activities',
    'ushr_records',
    'crop_seasons',
    'fields',
    'thekas',
    'farms',
    'parties',
  ];

  bool _active = false;
  bool get isActive => _active;

  /// Re-entrancy guard: the entry button can be double-tapped while the first
  /// insert is still running; without this, two concurrent entries interleave
  /// and produce duplicate demo datasets. (Race-condition audit 2026-10-04.)
  bool _entering = false;

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
      activities: context.read<ActivityProvider>(),
      ushr: context.read<UshrProvider>(),
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
    required ActivityProvider activities,
    required UshrProvider ushr,
  }) async {
    if (_active || _entering) return;
    _entering = true;
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

      // 1. Two farms with fields — a realistic smallholder setup.
      await farms.addFarm('چک 45 فارم', 25);
      await farms.addFarm('نہر والا کھیت (ٹھیکہ)', 8);
      final farmIds = await _newIds('farms', before['farms']!);
      final homeFarm = farmIds[0];
      final thekaFarm = farmIds[1];

      await farms.addField(farmId: homeFarm, name: 'مشرقی کھیت', sizeAcres: 10);
      await farms.addField(farmId: homeFarm, name: 'مغربی کھیت', sizeAcres: 8);
      await farms.addField(farmId: homeFarm, name: 'باغ والا کھیت', sizeAcres: 7);
      await farms.addField(
        farmId: thekaFarm,
        name: 'نہر والا کھیت ۱',
        sizeAcres: 4.5,
      );
      await farms.addField(
        farmId: thekaFarm,
        name: 'نہر والا کھیت ۲',
        sizeAcres: 3.5,
      );
      final fieldIds = await _newIds('fields', before['fields']!);
      final eastField = fieldIds[0];
      final westField = fieldIds[1];
      final orchardField = fieldIds[2];
      final canalField1 = fieldIds[3];
      final canalField2 = fieldIds[4];

      // 2. Four crop seasons across both farms.
      await crops.addCropSeason(
        fieldIds: [eastField, westField],
        cropName: 'گندم',
        variety: 'فیصل آباد 2008',
        startDate: d(-120),
      );
      await crops.addCropSeason(
        fieldIds: [orchardField],
        cropName: 'کپاس',
        variety: 'FH-492',
        startDate: d(-60),
      );
      await crops.addCropSeason(
        fieldIds: [canalField1],
        cropName: 'باسمتی چاول',
        variety: 'باسمتی 515',
        startDate: d(-95),
      );
      await crops.addCropSeason(
        fieldIds: [canalField2],
        cropName: 'مکئی',
        variety: 'YH-1898',
        startDate: d(-30),
      );
      final seasonIds = await _newIds('crop_seasons', before['crop_seasons']!);
      final wheat = seasonIds[0];
      final cotton = seasonIds[1];
      final rice = seasonIds[2];
      final maize = seasonIds[3];

      // 3. Realistic expenses across categories and time (paisa).
      final expenseRows = [
        // Wheat season.
        ('Plowing', 2500000, 'ہل چلائی — مشرقی و مغربی کھیت', wheat, -118),
        ('Seeds', 1800000, 'گندم بیج 2 بوری', wheat, -115),
        ('Fertilizer', 2250000, 'ڈی اے پی 1 بوری', wheat, -110),
        ('Fertilizer', 1350000, 'یوریا 3 بوری', wheat, -85),
        ('Water', 800000, 'ٹوئیل پانی — 4 گھنٹے', wheat, -80),
        ('Labour', 1200000, 'گوڈی مزدوری', wheat, -70),
        ('Sprays', 950000, 'جڑی بوٹی سپرے', wheat, -65),
        ('Harvesting', 3000000, 'کمبائن کٹائی', wheat, -12),
        // Cotton season.
        ('Plowing', 1200000, 'ہل چلائی — باغ والا کھیت', cotton, -58),
        ('Seeds', 900000, 'کپاس بیج FH-492', cotton, -55),
        ('Fertilizer', 1500000, 'یوریا 2 بوری', cotton, -40),
        ('Sprays', 1100000, 'سفید مکھی سپرے', cotton, -25),
        ('Water', 600000, 'نہری پانی وارہ بندی', cotton, -20),
        ('Labour', 800000, 'چنائی مزدوری پیشگی', cotton, -10),
        // Rice season.
        ('Plowing', 1000000, 'ہل چلائی — نہر والا کھیت', rice, -93),
        ('Seeds', 700000, 'باسمتی پنیری', rice, -88),
        ('Labour', 1500000, 'دھان لگوائی مزدوری', rice, -80),
        ('Fertilizer', 1100000, 'یوریا 2 بوری', rice, -60),
        ('Harvesting', 1800000, 'دھان کٹائی', rice, -8),
        // Maize season.
        ('Seeds', 850000, 'مکئی بیج YH-1898', maize, -28),
        ('Fertilizer', 900000, 'ڈی اے پی آدھی بوری', maize, -25),
        ('Water', 400000, 'ٹوئیل پانی', maize, -15),
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

      // 4. Harvests and sales.
      await harvests.addHarvest(
        cropSeasonId: wheat,
        quantity: 4200,
        unit: 'kg',
        date: d(-10),
        ratePerUnitPaisa: 11500,
      );
      final wheatHarvest =
          (await _newIds('harvests', before['harvests']!)).single;
      await harvests.recordSale(
        harvestId: wheatHarvest,
        quantity: 3000,
        pricePerUnitPaisa: 11500,
        date: d(-9),
        buyerName: 'چوہدری آڑھتی',
      );
      await harvests.recordSale(
        harvestId: wheatHarvest,
        quantity: 1200,
        pricePerUnitPaisa: 11800,
        date: d(-5),
        buyerName: 'چوہدری آڑھتی',
      );
      await harvests.addHarvest(
        cropSeasonId: rice,
        quantity: 2800,
        unit: 'kg',
        date: d(-6),
        ratePerUnitPaisa: 14000,
      );
      final riceHarvest =
          (await _newIds('harvests', before['harvests']!)).last;
      await harvests.recordSale(
        harvestId: riceHarvest,
        quantity: 2000,
        pricePerUnitPaisa: 14000,
        date: d(-4),
        buyerName: 'چوہدری آڑھتی',
      );

      // 5. Ushr records (5% for irrigated crops).
      await ushr.addUshrRecord(
        cropSeasonId: wheat,
        harvestId: wheatHarvest,
        harvestQty: 4200,
        marketValuePaisa: 4200 * 11500,
        ushrMethod: 'cash',
        ushrPercentage: 5,
        ushrAmountPaisa: (4200 * 11500 * 0.05).round(),
        status: 'paid',
        datePaid: d(-7),
        notes: 'گندم عشر — نقد ادا',
        payMethod: 'cash',
        qtyPaid: 0,
        cashPaidPaisa: (4200 * 11500 * 0.05).round(),
        ratePerUnitPaisa: 11500,
      );
      await ushr.addUshrRecord(
        cropSeasonId: rice,
        harvestId: riceHarvest,
        harvestQty: 2800,
        marketValuePaisa: 2800 * 14000,
        ushrMethod: 'crop',
        ushrPercentage: 5,
        ushrAmountPaisa: (2800 * 14000 * 0.05).round(),
        status: 'pending',
        notes: 'باسمتی عشر — جنس میں دینا ہے',
        payMethod: 'crop',
        qtyPaid: 140,
        cashPaidPaisa: 0,
        ratePerUnitPaisa: 14000,
      );

      // 6. Farm activities log — the season diary.
      final activityRows = [
        (wheat, 'ہل چلائی', -118, 'مشرقی و مغربی کھیت میں دوہرا ہل'),
        (wheat, 'بوائی', -115, 'گندم بیج فیصل آباد 2008 — 2 بوری'),
        (wheat, 'کھاد', -110, 'ڈی اے پی 1 بوری فی ایکڑ'),
        (wheat, 'پانی', -80, 'ٹوئیل سے چوتھا پانی'),
        (wheat, 'سپرے', -65, 'جڑی بوٹی مار سپرے'),
        (wheat, 'کٹائی', -12, 'کمبائن سے کٹائی مکمل — 4200 کلو'),
        (cotton, 'ہل چلائی', -58, 'باغ والے کھیت میں ہل'),
        (cotton, 'بوائی', -55, 'کپاس FH-492 بوائی'),
        (cotton, 'گوڈی', -30, 'پہلی گوڈی مزدوروں سے'),
        (cotton, 'سپرے', -25, 'سفید مکھی کے خلاف سپرے'),
        (rice, 'پنیری', -88, 'باسمتی 515 پنیری تیار'),
        (rice, 'منتقلی', -80, 'دھان کی لگوائی — 8 مزدور'),
        (rice, 'کٹائی', -8, 'دھان کٹائی — 2800 کلو'),
        (maize, 'بوائی', -28, 'مکئی YH-1898 بوائی'),
      ];
      for (final a in activityRows) {
        await activities.addActivity(
          cropSeasonId: a.$1,
          activityType: a.$2,
          date: d(a.$3),
          details: a.$4,
          isCompleted: true,
        );
      }

      // 7. Tasks — upcoming, overdue, completed, recurring.
      await tasks.addTask(
        'کپاس کو پانی لگائیں',
        'باغ والے کھیت میں پانچواں پانی',
        now.add(const Duration(days: 1, hours: 6)),
        reminders: '0,60',
      );
      await tasks.addTask(
        'سپرے والی دوا خریدیں',
        'سفید مکھی کے لیے 2 بوتل',
        now.add(const Duration(days: 2)),
      );
      await tasks.addTask(
        'مکئی کی گوڈی',
        'نہر والے کھیت ۲ میں گوڈی کروانی ہے',
        now.add(const Duration(days: 3)),
        recurrence: 'weekly',
      );
      await tasks.addTask(
        'ٹوئیل کا بل ادا کریں',
        'بجلی کا بل — 8500 روپے',
        now.subtract(const Duration(days: 2)),
      );
      await tasks.addTask(
        'آڑھتی سے حساب لیں',
        'گندم کی دوسری قسط کا حساب',
        now.add(const Duration(hours: 5)),
        reminders: '0',
      );
      await tasks.addTask(
        'یوریا کھاد ڈالیں',
        'کپاس میں یوریا',
        now.subtract(const Duration(days: 5)),
      );
      final doneTaskId =
          (await _newIds('tasks', before['tasks']!)).last;
      await tasks.toggleTaskCompletion(doneTaskId);

      // 8. Inventory — purchases plus usage.
      final ureaId = await inventory.recordPurchase(
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
        name: 'سفید مکھی سپرے',
        unit: 'بوتل',
        quantity: 6,
        costPerUnitPaisa: 150000,
      );
      await inventory.recordPurchase(
        category: 'ڈیزل',
        name: 'ڈیزل',
        unit: 'لیٹر',
        quantity: 100,
        costPerUnitPaisa: 26000,
      );
      // Usage: 3 urea bags on wheat, 2 on cotton.
      await inventory.recordUsage(
        itemId: ureaId,
        quantity: 5,
        date: d(-85),
        notes: 'گندم و کپاس میں استعمال',
      );

      // 9. Three parties with realistic ledger activity.
      final arrhti = await parties.addParty(
        Party(name: 'چوہدری آڑھتی', createdAt: now.toIso8601String()),
      );
      final dealer = await parties.addParty(
        Party(name: 'کھاد ڈیلر اکرم', createdAt: now.toIso8601String()),
      );
      final contractor = await parties.addParty(
        Party(name: 'مزدور ٹھیکیدار بشیر', createdAt: now.toIso8601String()),
      );
      await parties.addEntry(
        partyId: arrhti,
        type: PartyEntryType.udhaarDiya,
        amountPaisa: 5000000,
        date: d(-40),
        note: 'کپاس بیج و کھاد ادھار',
      );
      await parties.addEntry(
        partyId: arrhti,
        type: PartyEntryType.wusooli,
        amountPaisa: 34500000,
        date: d(-9),
        note: 'گندم پہلی فروخت وصولی',
      );
      await parties.addEntry(
        partyId: dealer,
        type: PartyEntryType.udhaarLiya,
        amountPaisa: 8000000,
        date: d(-50),
        note: 'ڈی اے پی و یوریا ادھار',
      );
      await parties.addEntry(
        partyId: dealer,
        type: PartyEntryType.adaigi,
        amountPaisa: 3000000,
        date: d(-15),
        note: 'جزوی ادائیگی',
      );
      await parties.addEntry(
        partyId: contractor,
        type: PartyEntryType.udhaarDiya,
        amountPaisa: 2000000,
        date: d(-25),
        note: 'مزدوری پیشگی',
      );

      // 10. Theka on the canal farm — 3 installments, first paid.
      await thekas.addTheka(
        Theka(
          farmId: thekaFarm,
          totalAmountPaisa: 120000000,
          durationType: 'Seasonal',
          durationDetails: 'خریف 2026',
          paymentMethod: 'Installment',
          startDate: d(-100),
          createdAt: now.toIso8601String(),
        ),
        [
          ThekaInstallment(
            thekaId: 0,
            amountPaisa: 40000000,
            dueDate: d(-60),
            status: 'Paid',
          ),
          ThekaInstallment(
            thekaId: 0,
            amountPaisa: 40000000,
            dueDate: d(30),
            status: 'Pending',
          ),
          ThekaInstallment(
            thekaId: 0,
            amountPaisa: 40000000,
            dueDate: d(90),
            status: 'Pending',
          ),
        ],
      );

      // 11. Batai agreement — 50/50 on wheat with the arrhti.
      await batai.createAgreement(
        farmerRole: FarmerRole.landowner,
        otherPartyId: arrhti,
        farmId: homeFarm,
        fieldId: eastField,
        cropSeasonId: wheat,
        ownerSharePercent: 50,
        cultivatorSharePercent: 50,
        expenseNote: 'کھاد و بیج مالک کے، مزدوری مزارع کی',
        startDate: d(-120),
        notes: 'گندم بٹائی معاہدہ',
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
    } finally {
      _entering = false;
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
  /// D1 guard (2026-10-18): BEFORE deleting anything, check whether any
  /// farmer-owned (non-demo) row references a tracked demo parent. With
  /// ON DELETE CASCADE those rows would be silently hard-deleted along
  /// with the demo data, so the exit is BLOCKED with an Urdu message
  /// instead — the farmer's records are never auto-deleted.
  /// A table blocked by an FK conflict the guard did not foresee is still
  /// skipped (never a crash) and reported in the returned message.
  Future<DemoExitResult> exitDemo() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(idsKey);
    final Map<String, dynamic> ids =
        raw == null ? {} : jsonDecode(raw) as Map<String, dynamic>;

    final db = await _ex();

    // D1: the farmer added their own records on top of the demo data
    // (e.g. a real crop season on a demo field). Deleting the demo
    // parents would hard-delete those rows via FK CASCADE — abort first.
    final linked = await _linkedDemoParents(db, ids);
    if (linked.isNotEmpty) {
      notifyListeners();
      return DemoExitResult.blocked(
        'آپ کا اپنا کچھ ریکارڈ ڈیمو ڈیٹا سے جڑا ہوا ہے '
        '(${linked.join('، ')})۔ پہلے وہ ریکارڈ حذف کریں یا ڈیمو موڈ '
        'جاری رہنے دیں، پھر دوبارہ کوشش کریں۔',
      );
    }

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
