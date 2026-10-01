import 'package:flutter/material.dart';
import 'package:sqflite/sqflite.dart';
import '../database/db_helper.dart';
import '../models/batai.dart';
import '../services/audit_service.dart';
import '../services/money.dart';

/// Thrown for batai rule violations; [message] is user-facing Urdu.
class BataiException implements Exception {
  final String message;
  BataiException(this.message);

  @override
  String toString() => 'BataiException: $message';
}

class BataiProvider extends ChangeNotifier {
  /// Test hook: when set, all DB access goes through this executor instead
  /// of the app singleton, so tests never touch the real database file.
  final DatabaseExecutor? testExecutor;

  BataiProvider({this.testExecutor});

  Future<DatabaseExecutor> _db() async =>
      testExecutor ?? await DatabaseHelper.instance.database;

  /// Runs [action] inside a real transaction when the executor is a full
  /// [Database]; a bare [Transaction] (or any other executor a test hands
  /// in) already runs inside one, so the action runs directly. This keeps
  /// the testExecutor hook working while production always gets ACID.
  Future<T> _txn<T>(Future<T> Function(DatabaseExecutor txn) action) async {
    final db = await _db();
    if (db is Database) {
      return await db.transaction(action);
    }
    return await action(db);
  }

  List<BataiAgreementSummary> _agreements = [];

  List<BataiAgreementSummary> get agreements => _agreements;

  /// Last load failure, if any. Sections show it as a retryable Urdu error.
  String? _errorMessage;
  String? get errorMessage => _errorMessage;

  Future<void> fetchAgreements() async {
    _errorMessage = null;
    try {
      await _fetchAgreements();
    } catch (_) {
      _errorMessage =
          'بٹائی معاہدوں کا ریکارڈ لوڈ نہیں ہو سکا۔ دوبارہ کوشش کریں۔';
      notifyListeners();
    }
  }

  Future<void> _fetchAgreements() async {
    _agreements = await getAgreementSummaries();
    notifyListeners();
  }

  /// Agreements with resolved party/crop/farm/field names (LEFT JOINs),
  /// newest first. Pass [status] to filter.
  Future<List<BataiAgreementSummary>> getAgreementSummaries({
    BataiStatus? status,
  }) async {
    final db = await _db();
    final where = status == null ? '' : 'WHERE b.status = ?';
    final args = status == null ? null : [bataiStatusToString(status)];
    final maps = await db.rawQuery('''
      SELECT b.*,
             p.name AS party_name,
             cs.crop_name AS crop_name,
             COALESCE(f1.name, f2.name) AS farm_name,
             fl.name AS field_name
      FROM batai_agreements b
      LEFT JOIN parties p ON p.id = b.other_party_id
      LEFT JOIN crop_seasons cs ON cs.id = b.crop_season_id
      LEFT JOIN fields fl ON fl.id = b.field_id
      LEFT JOIN farms f1 ON f1.id = b.farm_id
      LEFT JOIN farms f2 ON f2.id = fl.farm_id
      $where
      ORDER BY b.id DESC
    ''', args);
    return maps.map(BataiAgreementSummary.fromMap).toList();
  }

  /// One agreement with its resolved names (for the detail screen).
  Future<BataiAgreementSummary?> getAgreementSummary(int id) async {
    final all = await getAgreementSummaries();
    for (final s in all) {
      if (s.agreement.id == id) return s;
    }
    return null;
  }

  Future<int> _settlementCount(int agreementId) async {
    final db = await _db();
    final rows = await db.rawQuery(
      'SELECT COUNT(*) AS c FROM batai_settlements WHERE agreement_id = ?',
      [agreementId],
    );
    return ((rows.first['c'] as num?) ?? 0).toInt();
  }

  Future<BataiAgreement> _requireAgreement(int agreementId) async {
    final db = await _db();
    final maps = await db.query(
      'batai_agreements',
      where: 'id = ?',
      whereArgs: [agreementId],
      limit: 1,
    );
    if (maps.isEmpty) {
      throw BataiException('یہ بٹائی معاہدہ موجود نہیں۔');
    }
    return BataiAgreement.fromMap(maps.first);
  }

  void _validateTerms({
    required int ownerSharePercent,
    required int cultivatorSharePercent,
    required String startDate,
    String? endDate,
  }) {
    if (ownerSharePercent < 0 ||
        ownerSharePercent > 100 ||
        cultivatorSharePercent < 0 ||
        cultivatorSharePercent > 100) {
      throw BataiException('حصے 0 سے 100 کے درمیان ہونے چاہئیں۔');
    }
    if (ownerSharePercent + cultivatorSharePercent != 100) {
      throw BataiException('مالک اور مزارع کے حصوں کا مجموعہ 100 ہونا چاہیے۔');
    }
    if (DateTime.tryParse(startDate) == null) {
      throw BataiException('درست آغاز کی تاریخ درج کریں۔');
    }
    if (endDate != null && endDate.trim().isNotEmpty) {
      final end = DateTime.tryParse(endDate);
      if (end == null) {
        throw BataiException('درست اختتامی تاریخ درج کریں۔');
      }
      if (end.isBefore(DateTime.parse(startDate))) {
        throw BataiException(
          'اختتامی تاریخ آغاز کی تاریخ سے پہلے نہیں ہو سکتی۔',
        );
      }
    }
  }

  Future<void> _requirePartyExists(int partyId) async {
    final db = await _db();
    final maps = await db.query(
      'parties',
      where: 'id = ?',
      whereArgs: [partyId],
      limit: 1,
    );
    if (maps.isEmpty) {
      throw BataiException('منتخب کردہ فریق موجود نہیں۔ دوبارہ منتخب کریں۔');
    }
  }

  /// Creates a new batai agreement. Shares must sum to exactly 100.
  Future<int> createAgreement({
    required FarmerRole farmerRole,
    required int otherPartyId,
    int? farmId,
    int? fieldId,
    int? cropSeasonId,
    required int ownerSharePercent,
    required int cultivatorSharePercent,
    String? expenseNote,
    required String startDate,
    String? endDate,
    String? notes,
  }) async {
    _validateTerms(
      ownerSharePercent: ownerSharePercent,
      cultivatorSharePercent: cultivatorSharePercent,
      startDate: startDate,
      endDate: endDate,
    );
    await _requirePartyExists(otherPartyId);
    final id = await _txn((txn) async {
      final newId = await txn.insert(
        'batai_agreements',
        BataiAgreement(
          farmerRole: farmerRole,
          otherPartyId: otherPartyId,
          farmId: farmId,
          fieldId: fieldId,
          cropSeasonId: cropSeasonId,
          ownerSharePercent: ownerSharePercent,
          cultivatorSharePercent: cultivatorSharePercent,
          expenseNote: _nullIfEmpty(expenseNote),
          startDate: startDate,
          endDate: _nullIfEmpty(endDate),
          notes: _nullIfEmpty(notes),
          createdAt: DateTime.now().toIso8601String(),
        ).toMap(),
      );
      await AuditService.log(
        txn,
        table: 'batai_agreements',
        rowId: newId,
        action: AuditService.create,
        details:
            'بٹائی معاہدہ — مالک $ownerSharePercent٪ / مزارع $cultivatorSharePercent٪',
      );
      return newId;
    });
    await fetchAgreements();
    return id;
  }

  /// Updates the TERMS of an agreement (role, party, shares, links, dates).
  ///
  /// Terms are locked the moment the first settlement exists: changing the
  /// split afterwards would rewrite history, so [BataiException] is thrown.
  /// Free-text notes stay editable via [updateNotes]; status via [setStatus].
  Future<void> updateTerms({
    required int id,
    required FarmerRole farmerRole,
    required int otherPartyId,
    int? farmId,
    int? fieldId,
    int? cropSeasonId,
    required int ownerSharePercent,
    required int cultivatorSharePercent,
    required String startDate,
    String? endDate,
  }) async {
    final existing = await _requireAgreement(id);
    if (await _settlementCount(id) > 0) {
      throw BataiException(
        'اس معاہدے کی چکتائی ہو چکی ہے، اس لیے شرائط (حصے، کردار، فریق، تاریخیں) تبدیل نہیں ہو سکتیں۔ صرف نوٹ یا حیثیت بدلی جا سکتی ہے۔',
      );
    }
    _validateTerms(
      ownerSharePercent: ownerSharePercent,
      cultivatorSharePercent: cultivatorSharePercent,
      startDate: startDate,
      endDate: endDate,
    );
    await _requirePartyExists(otherPartyId);
    await _txn((txn) async {
      await txn.update(
        'batai_agreements',
        {
          'farmer_role': farmerRoleToString(farmerRole),
          'other_party_id': otherPartyId,
          'farm_id': farmId,
          'field_id': fieldId,
          'crop_season_id': cropSeasonId,
          'owner_share_percent': ownerSharePercent,
          'cultivator_share_percent': cultivatorSharePercent,
          'start_date': startDate,
          'end_date': _nullIfEmpty(endDate),
        },
        where: 'id = ?',
        whereArgs: [existing.id],
      );
      await AuditService.log(
        txn,
        table: 'batai_agreements',
        rowId: existing.id!,
        action: AuditService.update,
        details:
            'شرائط تبدیل — مالک $ownerSharePercent٪ / مزارع $cultivatorSharePercent٪',
      );
    });
    await fetchAgreements();
  }

  /// Updates only the free-text fields — always allowed, even after
  /// settlements.
  Future<void> updateNotes(int id, {String? expenseNote, String? notes}) async {
    final existing = await _requireAgreement(id);
    final db = await _db();
    await db.update(
      'batai_agreements',
      {'expense_note': _nullIfEmpty(expenseNote), 'notes': _nullIfEmpty(notes)},
      where: 'id = ?',
      whereArgs: [existing.id],
    );
    await fetchAgreements();
  }

  /// Changes the lifecycle status — always allowed. A season is marked
  /// 'settled' (چکتا شدہ) by the farmer's own hand, never automatically:
  /// one season is usually settled over several harvests.
  Future<void> setStatus(int id, BataiStatus status) async {
    final existing = await _requireAgreement(id);
    await _txn((txn) async {
      await txn.update(
        'batai_agreements',
        {'status': bataiStatusToString(status)},
        where: 'id = ?',
        whereArgs: [existing.id],
      );
      await AuditService.log(
        txn,
        table: 'batai_agreements',
        rowId: existing.id!,
        action: AuditService.update,
        details: 'حیثیت: ${bataiStatusUrdu(status)}',
      );
    });
    await fetchAgreements();
  }

  /// Records one settlement (چکتائی) of a harvest/sale: the split is
  /// computed with [splitBatai] and the row is inserted in ONE transaction.
  ///
  /// Settlements are append-only: there is deliberately no delete/update API.
  ///
  /// DELIBERATE: this does NOT flip the agreement's status to 'settled'.
  /// A sharecropping season is normally settled harvest by harvest, so the
  /// status stays 'active' until the farmer marks the whole season settled
  /// himself via [setStatus]. Auto-flipping would lie about partial seasons.
  Future<int> settleAgreement({
    required int agreementId,
    required int totalPaisa,
    int? harvestId,
    int? saleId,
    required String settleDate,
    String? note,
  }) async {
    final agreement = await _requireAgreement(agreementId);
    if (agreement.status == BataiStatus.cancelled) {
      throw BataiException('منسوخ شدہ معاہدے کی چکتائی نہیں ہو سکتی۔');
    }
    if (agreement.status == BataiStatus.settled) {
      throw BataiException(
        'یہ معاہدہ پہلے سے چکتا شدہ ہے۔ مزید چکتائی کے لیے پہلے حیثیت "فعال" کریں۔',
      );
    }
    if (totalPaisa <= 0) {
      throw BataiException('چکتائی کی رقم صفر سے زیادہ ہونی چاہیے۔');
    }
    if (DateTime.tryParse(settleDate) == null) {
      throw BataiException('درست تاریخ درج کریں۔');
    }
    final split = splitBatai(totalPaisa, agreement.ownerSharePercent);
    final id = await _txn((txn) async {
      final newId = await txn.insert(
        'batai_settlements',
        BataiSettlement(
          agreementId: agreementId,
          harvestId: harvestId,
          saleId: saleId,
          totalPaisa: totalPaisa,
          ownerPaisa: split.ownerPaisa,
          cultivatorPaisa: split.cultivatorPaisa,
          settleDate: settleDate,
          note: _nullIfEmpty(note),
          createdAt: DateTime.now().toIso8601String(),
        ).toMap(),
      );
      await AuditService.log(
        txn,
        table: 'batai_settlements',
        rowId: newId,
        action: AuditService.create,
        details: 'چکتائی — ${Money(totalPaisa).format()}',
      );
      return newId;
    });
    await fetchAgreements();
    return id;
  }

  /// Deletes an agreement only when it has NO settlements. An agreement
  /// with settlements keeps its financial history — deleteAgreement throws
  /// an Urdu error (mirrors [PartyProvider.deleteParty]).
  Future<void> deleteAgreement(int agreementId) async {
    final existing = await _requireAgreement(agreementId);
    if (await _settlementCount(agreementId) > 0) {
      throw BataiException(
        'اس معاہدے کی چکتائیاں موجود ہیں، اس لیے اسے حذف نہیں کیا جا سکتا۔',
      );
    }
    await _txn((txn) async {
      await txn.delete(
        'batai_agreements',
        where: 'id = ?',
        whereArgs: [existing.id],
      );
      await AuditService.log(
        txn,
        table: 'batai_agreements',
        rowId: existing.id!,
        action: AuditService.delete,
        details: 'بٹائی معاہدہ حذف (بغیر چکتائی)',
      );
    });
    await fetchAgreements();
  }

  /// Settlements for one agreement, newest first.
  Future<List<BataiSettlement>> getSettlements(int agreementId) async {
    final db = await _db();
    final maps = await db.query(
      'batai_settlements',
      where: 'agreement_id = ?',
      whereArgs: [agreementId],
      orderBy: 'settle_date DESC, id DESC',
    );
    return maps.map(BataiSettlement.fromMap).toList();
  }

  String? _nullIfEmpty(String? v) {
    final t = v?.trim();
    return (t == null || t.isEmpty) ? null : t;
  }
}
