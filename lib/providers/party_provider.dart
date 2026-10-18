import 'package:flutter/material.dart';
import 'package:sqflite/sqflite.dart';
import '../database/db_helper.dart';
import '../models/party.dart';
import '../services/audit_service.dart';
import '../services/money.dart';

/// Thrown for party-ledger rule violations; [message] is user-facing Urdu.
class PartyException implements Exception {
  final String message;
  PartyException(this.message);

  @override
  String toString() => 'PartyException: $message';
}

class PartyProvider extends ChangeNotifier {
  /// Test hook: when set, all DB access goes through this executor instead
  /// of the app singleton, so tests never touch the real database file.
  final DatabaseExecutor? testExecutor;

  PartyProvider({this.testExecutor});

  Future<DatabaseExecutor> _db() async =>
      testExecutor ?? await DatabaseHelper.instance.database;

  /// Runs [action] inside a real transaction when the executor is a full
  /// [Database]; a bare [Transaction] (or any other executor a test hands
  /// in) already runs inside one, so the action runs directly. (Same
  /// pattern as BataiProvider.)
  Future<T> _txn<T>(Future<T> Function(DatabaseExecutor txn) action) async {
    final db = await _db();
    if (db is Database) {
      return await db.transaction(action);
    }
    return await action(db);
  }

  List<Party> _parties = [];
  final Map<int, int> _balances = {}; // partyId -> SUM(amount_paisa)

  List<Party> get parties => _parties;

  /// Last load failure, if any. Sections show it as a retryable Urdu error.
  String? _errorMessage;
  String? get errorMessage => _errorMessage;

  /// Signed balance (INTEGER paisa) for one party. Positive = party owes me.
  int balanceOf(int partyId) => _balances[partyId] ?? 0;

  /// partyId -> signed balance, for the home snapshot.
  Map<int, int> get allBalances => Map.unmodifiable(_balances);

  /// Total receivable: sum of positive balances (parties owe me).
  int get totalReceivablePaisa {
    var total = 0;
    for (final b in _balances.values) {
      if (b > 0) total += b;
    }
    return total;
  }

  /// Total payable: sum of negative balances as a positive number (I owe).
  int get totalPayablePaisa {
    var total = 0;
    for (final b in _balances.values) {
      if (b < 0) total += -b;
    }
    return total;
  }

  Future<void> fetchParties() async {
    _errorMessage = null;
    try {
      await _fetchParties();
    } catch (_) {
      _errorMessage = 'پارٹیوں کا ریکارڈ لوڈ نہیں ہو سکا۔ دوبارہ کوشش کریں۔';
      notifyListeners();
    }
  }

  Future<void> _fetchParties() async {
    final db = await _db();
    final maps = await db.query(
      'parties',
      where: 'deleted_at IS NULL',
      orderBy: 'name ASC',
    );
    _parties = maps.map(Party.fromMap).toList();
    // Balances come only from live parties; a soft-deleted party cannot
    // have entries (deletion is blocked while entries exist), but the join
    // keeps the invariant explicit.
    final balMaps = await db.rawQuery(
      'SELECT e.party_id AS party_id, SUM(e.amount_paisa) AS bal '
      'FROM party_ledger_entries e '
      'JOIN parties p ON p.id = e.party_id '
      'WHERE p.deleted_at IS NULL '
      'GROUP BY e.party_id',
    );
    _balances
      ..clear()
      ..addEntries(
        balMaps.map(
          (m) => MapEntry(
            (m['party_id'] as int),
            ((m['bal'] as num?) ?? 0).toInt(),
          ),
        ),
      );
    notifyListeners();
  }

  Future<int> addParty(Party party) async {
    final name = party.name.trim();
    if (name.isEmpty) {
      throw PartyException('پارٹی کا نام درج کریں۔');
    }
    final id = await _txn((txn) async {
      final newId = await txn.insert(
        'parties',
        Party(
          name: name,
          phone: _nullIfEmpty(party.phone),
          notes: _nullIfEmpty(party.notes),
          createdAt: party.createdAt,
        ).toMap(),
      );
      await AuditService.log(
        txn,
        table: 'parties',
        rowId: newId,
        action: AuditService.create,
        details: 'پارٹی: $name',
      );
      return newId;
    });
    await fetchParties();
    return id;
  }

  Future<void> updateParty(Party party) async {
    final name = party.name.trim();
    if (name.isEmpty) {
      throw PartyException('پارٹی کا نام درج کریں۔');
    }
    await _txn((txn) async {
      await txn.update(
        'parties',
        {
          'name': name,
          'phone': _nullIfEmpty(party.phone),
          'notes': _nullIfEmpty(party.notes),
        },
        where: 'id = ?',
        whereArgs: [party.id],
      );
      await AuditService.log(
        txn,
        table: 'parties',
        rowId: party.id!,
        action: AuditService.update,
        details: 'پارٹی: $name',
      );
    });
    await fetchParties();
  }

  /// Soft-deletes a party. Blocked (Urdu error) when the party has ledger
  /// entries OR is referenced by a batai agreement — financial/share history
  /// must survive. A zero-entry, unreferenced party is hidden but kept for
  /// the recycle bin.
  ///
  /// Idempotent (owner decision #5): deleting a missing or already-deleted
  /// party is a safe no-op.
  Future<void> deleteParty(int partyId) async {
    final db = await _db();
    final count = await db.rawQuery(
      'SELECT COUNT(*) AS c FROM party_ledger_entries WHERE party_id = ?',
      [partyId],
    );
    final entries = ((count.first['c'] as num?) ?? 0).toInt();
    if (entries > 0) {
      throw PartyException(
        'اس پارٹی کے کھاتے میں اندراجات موجود ہیں، اس لیے اسے حذف نہیں کیا جا سکتا۔ پہلے حساب برابر کریں۔',
      );
    }
    // A missing batai_agreements table (pre-v14 schema) means no references.
    int bataiRefs = 0;
    try {
      final bataiCount = await db.rawQuery(
        'SELECT COUNT(*) AS c FROM batai_agreements WHERE other_party_id = ?',
        [partyId],
      );
      bataiRefs = ((bataiCount.first['c'] as num?) ?? 0).toInt();
    } on DatabaseException catch (e) {
      if (!e.toString().contains('no such table')) rethrow;
    }
    if (bataiRefs > 0) {
      throw PartyException(
        'اس پارٹی کا بٹائی معاہدہ موجود ہے، اس لیے اسے حذف نہیں کیا جا سکتا۔',
      );
    }
    await _txn((txn) async {
      final existing = await txn.query(
        'parties',
        where: 'id = ?',
        whereArgs: [partyId],
      );
      if (existing.isEmpty) return;
      if (existing.first['deleted_at'] != null) return;
      await txn.update(
        'parties',
        {'deleted_at': DateTime.now().toIso8601String()},
        where: 'id = ?',
        whereArgs: [partyId],
      );
      await AuditService.log(
        txn,
        table: 'parties',
        rowId: partyId,
        action: AuditService.softDelete,
        details: 'پارٹی: ${existing.first['name']}',
      );
    });
    await fetchParties();
  }

  /// Restores a soft-deleted party (recycle bin only).
  ///
  /// Idempotent (owner decision #5): restoring a missing or already-live
  /// party is a safe no-op.
  Future<void> restoreParty(int partyId) async {
    await _txn((txn) async {
      final existing = await txn.query(
        'parties',
        columns: const ['deleted_at'],
        where: 'id = ?',
        whereArgs: [partyId],
        limit: 1,
      );
      if (existing.isEmpty) return;
      if (existing.first['deleted_at'] == null) return;
      await txn.update(
        'parties',
        {'deleted_at': null},
        where: 'id = ?',
        whereArgs: [partyId],
      );
      await AuditService.log(
        txn,
        table: 'parties',
        rowId: partyId,
        action: AuditService.restore,
        details: 'پارٹی بحال',
      );
    });
    await fetchParties();
  }

  /// Permanent delete — recycle bin only. A party with ledger entries can
  /// never reach here ([deleteParty] blocks it).
  ///
  /// Idempotent (owner decision #5): repeating a permanent delete is a
  /// safe no-op.
  Future<void> permanentDeleteParty(int partyId) async {
    await _txn((txn) async {
      final existing = await txn.query(
        'parties',
        columns: const ['id'],
        where: 'id = ?',
        whereArgs: [partyId],
        limit: 1,
      );
      if (existing.isEmpty) return;
      await txn.delete('parties', where: 'id = ?', whereArgs: [partyId]);
      await AuditService.log(
        txn,
        table: 'parties',
        rowId: partyId,
        action: AuditService.permanentDelete,
        details: 'پارٹی مستقل حذف',
      );
    });
    await fetchParties();
  }

  /// Appends one ledger entry. [amountPaisa] is UNSIGNED; the sign comes
  /// from [type]. Amount must be > 0 — zero/negative input is rejected.
  /// Entries are append-only: there is deliberately no delete/update API.
  Future<int> addEntry({
    required int partyId,
    required PartyEntryType type,
    required int amountPaisa,
    required String date,
    String? note,
  }) async {
    _validateEntryInput(amountPaisa, date);
    final id = await _txn(
      (txn) => _insertEntry(
        txn,
        partyId: partyId,
        type: type,
        amountPaisa: amountPaisa,
        date: date,
        note: note,
      ),
    );
    await fetchParties();
    return id;
  }

  /// Appends one ledger entry LINKED to its underlying transaction (owner
  /// decision #3, S5/§6.4).
  ///
  /// Sign convention (same as [addEntry]): the sign ALWAYS comes from
  /// [type] — positive = the party owes me, negative = I owe the party. A
  /// linked entry never books income or expense: e.g. a وصولی linked to an
  /// already-recognized sale only shrinks the receivable; the sale's income
  /// was booked once, when the sale was recorded. Party balance = SUM of
  /// signed entry amounts; outstanding for one source = SUM of its linked
  /// entries (see [outstandingForSale]). The referenced row must exist —
  /// links are never dangling.
  Future<int> addLinkedEntry({
    required int partyId,
    required PartyEntryType type,
    required int amountPaisa,
    required String date,
    String? note,
    required PartyEntrySourceType sourceType,
    required int sourceId,
  }) async {
    _validateEntryInput(amountPaisa, date);
    final id = await _txn((txn) async {
      await _requireSourceExists(txn, sourceType, sourceId);
      return _insertEntry(
        txn,
        partyId: partyId,
        type: type,
        amountPaisa: amountPaisa,
        date: date,
        note: note,
        sourceType: sourceType,
        sourceId: sourceId,
      );
    });
    await fetchParties();
    return id;
  }

  void _validateEntryInput(int amountPaisa, String date) {
    if (amountPaisa <= 0) {
      throw PartyException('رقم صفر سے زیادہ ہونی چاہیے۔');
    }
    if (DateTime.tryParse(date) == null) {
      throw PartyException('درست تاریخ درج کریں۔');
    }
  }

  /// The referenced source row must exist — a link is a trace marker, and
  /// a dangling one proves nothing. Runs inside the caller's transaction.
  Future<void> _requireSourceExists(
    DatabaseExecutor txn,
    PartyEntrySourceType sourceType,
    int sourceId,
  ) async {
    final table = partyEntrySourceTable(sourceType);
    List<Map<String, Object?>> rows;
    try {
      rows = await txn.query(
        table,
        columns: const ['id'],
        where: 'id = ?',
        whereArgs: [sourceId],
        limit: 1,
      );
    } on DatabaseException catch (e) {
      // A missing source table (older partial schema) means the link
      // cannot be verified — fail loudly rather than store a dangling one.
      if (e.toString().contains('no such table')) {
        throw PartyException('منسلک لین دین کا ریکارڈ موجود نہیں ہے۔');
      }
      rethrow;
    }
    if (rows.isEmpty) {
      throw PartyException('منسلک لین دین موجود نہیں ہے (نمبر $sourceId)۔');
    }
  }

  Future<int> _insertEntry(
    DatabaseExecutor txn, {
    required int partyId,
    required PartyEntryType type,
    required int amountPaisa,
    required String date,
    String? note,
    PartyEntrySourceType? sourceType,
    int? sourceId,
  }) async {
    // Never post to a missing or soft-deleted party.
    final party = await txn.query(
      'parties',
      where: 'id = ? AND deleted_at IS NULL',
      whereArgs: [partyId],
    );
    if (party.isEmpty) {
      throw PartyException('یہ پارٹی موجود نہیں ہے۔');
    }
    final newId = await txn.insert('party_ledger_entries', {
      'party_id': partyId,
      'entry_type': partyEntryTypeToString(type),
      'amount_paisa': partyEntryTypeSign(type) * amountPaisa,
      'date': date,
      'note': _nullIfEmpty(note),
      'created_at': DateTime.now().toIso8601String(),
      'source_type': sourceType == null
          ? null
          : partyEntrySourceTypeToString(sourceType),
      'source_id': sourceId,
    });
    final linkSuffix = sourceType == null
        ? ''
        : ' — منسلک: ${partyEntrySourceTypeUrdu(sourceType)} #$sourceId';
    await AuditService.log(
      txn,
      table: 'party_ledger_entries',
      rowId: newId,
      action: AuditService.create,
      details:
          '${partyEntryTypeUrdu(type)} — ${Money(amountPaisa).format()}$linkSuffix',
    );
    return newId;
  }

  /// Ledger entries linked to one source transaction, newest first.
  /// Exact-type match: [PartyEntrySourceType.sale] for origin entries,
  /// [PartyEntrySourceType.collection] for settlements against a sale.
  Future<List<PartyLedgerEntry>> entriesForSource(
    PartyEntrySourceType sourceType,
    int sourceId,
  ) async {
    final db = await _db();
    final maps = await db.query(
      'party_ledger_entries',
      where: 'source_type = ? AND source_id = ?',
      whereArgs: [partyEntrySourceTypeToString(sourceType), sourceId],
      orderBy: 'date DESC, id DESC',
    );
    return maps.map(PartyLedgerEntry.fromMap).toList();
  }

  /// Live outstanding on one sale: SUM of the signed amounts of every
  /// entry linked to it — BOTH 'sale' (origin) and 'collection'
  /// (settlement) links. Positive = the party still owes the farmer.
  /// Must equal sale.total − collected; 0 means fully settled.
  Future<int> outstandingForSale(int saleId) async {
    final db = await _db();
    final rows = await db.rawQuery(
      'SELECT SUM(amount_paisa) AS s FROM party_ledger_entries '
      "WHERE source_id = ? AND source_type IN ('sale', 'collection')",
      [saleId],
    );
    return ((rows.first['s'] as num?) ?? 0).toInt();
  }

  /// UI-ready summary of a linked source row for the trace view, or null
  /// when the row is gone (soft/hard deleted) — the link itself survives
  /// as an audit marker.
  Future<PartyEntrySourceSummary?> sourceSummary(
    PartyEntrySourceType sourceType,
    int sourceId,
  ) async {
    final db = await _db();
    try {
      switch (sourceType) {
        case PartyEntrySourceType.sale:
        case PartyEntrySourceType.collection:
          final rows = await db.query(
            'sales',
            where: 'id = ?',
            whereArgs: [sourceId],
            limit: 1,
          );
          if (rows.isEmpty) return null;
          final r = rows.first;
          final buyer = r['buyer_name'] as String?;
          return PartyEntrySourceSummary(
            type: sourceType,
            id: sourceId,
            title: 'فروخت #$sourceId',
            amountPaisa: (r['total_amount_paisa'] as num).toInt(),
            date: r['date'] as String,
            detail: buyer != null && buyer.isNotEmpty
                ? 'خریدار: $buyer'
                : null,
          );
        case PartyEntrySourceType.expense:
          final rows = await db.query(
            'expenses',
            where: 'id = ?',
            whereArgs: [sourceId],
            limit: 1,
          );
          if (rows.isEmpty) return null;
          final r = rows.first;
          return PartyEntrySourceSummary(
            type: sourceType,
            id: sourceId,
            title: 'اخراجات #$sourceId',
            amountPaisa: (r['amount_paisa'] as num).toInt(),
            date: r['date'] as String,
            detail: 'قسم: ${r['category']}',
          );
        case PartyEntrySourceType.payment:
          final rows = await db.query(
            'theka_installments',
            where: 'id = ?',
            whereArgs: [sourceId],
            limit: 1,
          );
          if (rows.isEmpty) return null;
          final r = rows.first;
          return PartyEntrySourceSummary(
            type: sourceType,
            id: sourceId,
            title: 'ٹھیکہ قسط #$sourceId',
            amountPaisa: (r['amount_paisa'] as num).toInt(),
            date: r['due_date'] as String,
            detail: 'حالت: ${r['status']}',
          );
      }
    } on DatabaseException catch (e) {
      if (e.toString().contains('no such table')) return null;
      rethrow;
    }
  }

  /// Ledger entries for one party, newest first.
  Future<List<PartyLedgerEntry>> getEntries(int partyId) async {
    final db = await _db();
    final maps = await db.query(
      'party_ledger_entries',
      where: 'party_id = ?',
      whereArgs: [partyId],
      orderBy: 'date DESC, id DESC',
    );
    return maps.map(PartyLedgerEntry.fromMap).toList();
  }

  String? _nullIfEmpty(String? v) {
    final t = v?.trim();
    return (t == null || t.isEmpty) ? null : t;
  }
}
