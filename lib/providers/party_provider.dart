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
      ..addEntries(balMaps.map((m) => MapEntry(
            (m['party_id'] as int),
            ((m['bal'] as num?) ?? 0).toInt(),
          )));
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
        details: existing.isEmpty
            ? 'پارٹی حذف'
            : 'پارٹی: ${existing.first['name']}',
      );
    });
    await fetchParties();
  }

  /// Restores a soft-deleted party (recycle bin only).
  Future<void> restoreParty(int partyId) async {
    await _txn((txn) async {
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
  Future<void> permanentDeleteParty(int partyId) async {
    await _txn((txn) async {
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
    if (amountPaisa <= 0) {
      throw PartyException('رقم صفر سے زیادہ ہونی چاہیے۔');
    }
    if (DateTime.tryParse(date) == null) {
      throw PartyException('درست تاریخ درج کریں۔');
    }
    final id = await _txn((txn) async {
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
      });
      await AuditService.log(
        txn,
        table: 'party_ledger_entries',
        rowId: newId,
        action: AuditService.create,
        details:
            '${partyEntryTypeUrdu(type)} — ${Money(amountPaisa).format()}',
      );
      return newId;
    });
    await fetchParties();
    return id;
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
