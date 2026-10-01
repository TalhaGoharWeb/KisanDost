import 'package:flutter/material.dart';
import 'package:sqflite/sqflite.dart';
import '../database/db_helper.dart';
import '../models/party.dart';

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
    final maps = await db.query('parties', orderBy: 'name ASC');
    _parties = maps.map(Party.fromMap).toList();
    final balMaps = await db.rawQuery(
      'SELECT party_id, SUM(amount_paisa) AS bal '
      'FROM party_ledger_entries GROUP BY party_id',
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
    final db = await _db();
    final id = await db.insert(
      'parties',
      Party(
        name: name,
        phone: _nullIfEmpty(party.phone),
        notes: _nullIfEmpty(party.notes),
        createdAt: party.createdAt,
      ).toMap(),
    );
    await fetchParties();
    return id;
  }

  Future<void> updateParty(Party party) async {
    final name = party.name.trim();
    if (name.isEmpty) {
      throw PartyException('پارٹی کا نام درج کریں۔');
    }
    final db = await _db();
    await db.update(
      'parties',
      {
        'name': name,
        'phone': _nullIfEmpty(party.phone),
        'notes': _nullIfEmpty(party.notes),
      },
      where: 'id = ?',
      whereArgs: [party.id],
    );
    await fetchParties();
  }

  /// Deletes a party only when it has NO ledger entries. A party with
  /// entries keeps its financial history — deleteParty throws an Urdu error.
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
    await db.delete('parties', where: 'id = ?', whereArgs: [partyId]);
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
    final db = await _db();
    final id = await db.insert('party_ledger_entries', {
      'party_id': partyId,
      'entry_type': partyEntryTypeToString(type),
      'amount_paisa': partyEntryTypeSign(type) * amountPaisa,
      'date': date,
      'note': _nullIfEmpty(note),
      'created_at': DateTime.now().toIso8601String(),
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
