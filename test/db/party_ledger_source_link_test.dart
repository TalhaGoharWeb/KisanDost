import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:kisan_dost/database/db_helper.dart';
import 'package:kisan_dost/models/party.dart';
import 'package:kisan_dost/providers/party_provider.dart';

/// Hermetic tests for the v16 party-ledger source links (owner decision #3,
/// S5 / FINANCIAL_POLICY §6.4). They exercise the REAL migration SQL
/// ([DatabaseHelper.migrateV15ToV16]) and the REAL provider against an
/// in-memory FFI database — the app singleton is never touched.
///
/// What "correct" means, from the farmer's point of view:
/// * a ledger entry can reference its underlying transaction
///   (sale / expense / theka-installment payment / collection against a
///   sale) via nullable `source_type`/`source_id` — legacy entries stay
///   valid and unlinked;
/// * the link is a TRACE MARKER: it never changes the entry's sign and
///   never books income/expense — a وصولی on an already-recognized sale
///   only shrinks the receivable, so income cannot be double-counted;
/// * signs stay exactly as before (positive = party owes me);
/// * balance = SUM of signed entries; outstanding for one sale = SUM of
///   its linked entries ('sale' origin + 'collection' settlements);
/// * a link can never dangle: the source row must exist at write time,
///   but the link survives the source row's later deletion (audit trail).
///
/// All money below is hand-computed in INTEGER paisa (Rs = paisa / 100).
void main() {
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  /// Opens a fresh in-memory DB at the v16 schema with minimal source
  /// tables (the real ones live in the full app schema; the provider only
  /// needs the columns it reads). Every test starts from empty tables.
  Future<({Database db, PartyProvider provider})> openLinkedDb() async {
    final db = await openDatabase(
      inMemoryDatabasePath,
      onConfigure: (db) async {
        await db.execute('PRAGMA foreign_keys = ON');
      },
    );
    await DatabaseHelper.migrateV12ToV13(db);
    await DatabaseHelper.migrateV14ToV15(db);
    await DatabaseHelper.migrateV15ToV16(db);
    await db.execute('''
      CREATE TABLE IF NOT EXISTS sales (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        total_amount_paisa INTEGER NOT NULL,
        date TEXT NOT NULL,
        buyer_name TEXT
      )
    ''');
    await db.execute('''
      CREATE TABLE IF NOT EXISTS expenses (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        amount_paisa INTEGER NOT NULL,
        date TEXT NOT NULL,
        category TEXT NOT NULL
      )
    ''');
    await db.execute('''
      CREATE TABLE IF NOT EXISTS theka_installments (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        amount_paisa INTEGER NOT NULL,
        due_date TEXT NOT NULL,
        status TEXT NOT NULL
      )
    ''');
    for (final t in [
      'party_ledger_entries',
      'parties',
      'sales',
      'expenses',
      'theka_installments',
    ]) {
      await db.delete(t);
    }
    return (db: db, provider: PartyProvider(testExecutor: db));
  }

  Future<int> addParty(PartyProvider p, String name) => p.addParty(
    Party(name: name, createdAt: DateTime.now().toIso8601String()),
  );

  Future<int> insertSale(
    Database db, {
    required int totalPaisa,
    String buyer = 'علی',
  }) => db.insert('sales', {
    'total_amount_paisa': totalPaisa,
    'date': '2026-10-01',
    'buyer_name': buyer,
  });

  /// "Income" the way P&L sees it: booked once per sale row.
  Future<int> incomePaisa(Database db) async {
    final r = await db.rawQuery(
      'SELECT SUM(total_amount_paisa) AS s FROM sales',
    );
    return ((r.first['s'] as num?) ?? 0).toInt();
  }

  Future<int> expenseTotalPaisa(Database db) async {
    final r = await db.rawQuery('SELECT SUM(amount_paisa) AS s FROM expenses');
    return ((r.first['s'] as num?) ?? 0).toInt();
  }

  group('v16 migration', () {
    test(
      'adds nullable source_type/source_id and the source index, idempotently',
      () async {
        final env = await openLinkedDb();
        final db = env.db;
        // Second run must be a no-op, not an error.
        await DatabaseHelper.migrateV15ToV16(db);

        final cols =
            (await db.rawQuery('PRAGMA table_info(party_ledger_entries)'))
                .map((c) => c['name'] as String)
                .toSet();
        expect(cols, containsAll(['source_type', 'source_id']));

        final indexes =
            (await db.rawQuery(
              "SELECT name FROM sqlite_master WHERE type = 'index'",
            )).map((r) => r['name'] as String).toSet();
        expect(indexes, contains('idx_party_ledger_entries_source'));
      },
    );
  });

  group('source-type vocabulary', () {
    test('wire values round-trip; labels and tables are fixed', () {
      for (final t in PartyEntrySourceType.values) {
        expect(
          partyEntrySourceTypeFromString(partyEntrySourceTypeToString(t)),
          t,
        );
      }
      expect(partyEntrySourceTable(PartyEntrySourceType.sale), 'sales');
      expect(
        partyEntrySourceTable(PartyEntrySourceType.collection),
        'sales',
      );
      expect(partyEntrySourceTable(PartyEntrySourceType.expense), 'expenses');
      expect(
        partyEntrySourceTable(PartyEntrySourceType.payment),
        'theka_installments',
      );
      expect(partyEntrySourceTypeUrdu(PartyEntrySourceType.sale), 'فروخت');
      expect(
        partyEntrySourceTypeUrdu(PartyEntrySourceType.expense),
        'اخراجات',
      );
      expect(
        partyEntrySourceTypeUrdu(PartyEntrySourceType.payment),
        'ٹھیکہ قسط',
      );
      expect(
        partyEntrySourceTypeUrdu(PartyEntrySourceType.collection),
        'وصولی (فروخت)',
      );
      expect(
        () => partyEntrySourceTypeFromString('bogus'),
        throwsArgumentError,
      );
    });
  });

  group('credit sale lifecycle — no double-count, reconciles', () {
    test(
      'sale → partial collection → reversal → full settlement',
      () async {
        final env = await openLinkedDb();
        final db = env.db;
        final p = env.provider;
        final partyId = await addParty(p, 'کریم');

        // A Rs 60,000 credit sale, already booked as income (accrual).
        final saleId = await insertSale(db, totalPaisa: 6000000);
        expect(await incomePaisa(db), 6000000);

        // E1: the receivable's origin, linked to the sale.
        await p.addLinkedEntry(
          partyId: partyId,
          type: PartyEntryType.udhaarDiya,
          amountPaisa: 6000000,
          date: '2026-10-02',
          sourceType: PartyEntrySourceType.sale,
          sourceId: saleId,
        );
        expect(p.balanceOf(partyId), 6000000);

        // E2: partial collection of Rs 25,000 — settles the sale.
        await p.addLinkedEntry(
          partyId: partyId,
          type: PartyEntryType.wusooli,
          amountPaisa: 2500000,
          date: '2026-10-05',
          sourceType: PartyEntrySourceType.collection,
          sourceId: saleId,
        );
        expect(p.balanceOf(partyId), 3500000); // 6,000,000 − 2,500,000
        // The collection must NOT book new income: income is still the one
        // sale row, unchanged.
        expect(await incomePaisa(db), 6000000);
        // Outstanding = sale.total − collected.
        expect(await p.outstandingForSale(saleId), 3500000);

        // E3: E2 was recorded by mistake — reversal entry, same sale link.
        await p.addLinkedEntry(
          partyId: partyId,
          type: PartyEntryType.udhaarDiya,
          amountPaisa: 2500000,
          date: '2026-10-06',
          note: 'غلط وصولی کی درستگی',
          sourceType: PartyEntrySourceType.sale,
          sourceId: saleId,
        );
        expect(p.balanceOf(partyId), 6000000);
        expect(await p.outstandingForSale(saleId), 6000000);
        expect(await incomePaisa(db), 6000000);

        // E4: the full, correct collection.
        await p.addLinkedEntry(
          partyId: partyId,
          type: PartyEntryType.wusooli,
          amountPaisa: 6000000,
          date: '2026-10-07',
          sourceType: PartyEntrySourceType.collection,
          sourceId: saleId,
        );
        expect(p.balanceOf(partyId), 0);
        expect(await p.outstandingForSale(saleId), 0);
        expect(await incomePaisa(db), 6000000);

        // Balance is exactly f(underlying entries):
        // +6,000,000 − 2,500,000 + 2,500,000 − 6,000,000 = 0.
        final entries = await p.getEntries(partyId);
        expect(entries.length, 4);
        expect(
          entries.fold<int>(0, (sum, e) => sum + e.amountPaisa),
          p.balanceOf(partyId),
        );

        // Trace views split origin from settlement.
        expect(
          (await p.entriesForSource(PartyEntrySourceType.sale, saleId)).length,
          2,
        );
        expect(
          (await p.entriesForSource(
            PartyEntrySourceType.collection,
            saleId,
          )).length,
          2,
        );

        // The link round-trips through the model (newest first: E4..E1).
        expect(entries.first.sourceType, PartyEntrySourceType.collection);
        expect(entries.first.sourceId, saleId);
        expect(entries.last.sourceType, PartyEntrySourceType.sale);
        expect(entries.last.sourceId, saleId);
      },
    );

    test('payable side: expense origin + settlement, expense total untouched',
        () async {
      final env = await openLinkedDb();
      final db = env.db;
      final p = env.provider;
      final partyId = await addParty(p, 'بشیر');

      // A Rs 12,000 credit purchase, already booked as an expense.
      final expenseId = await db.insert('expenses', {
        'amount_paisa': 1200000,
        'date': '2026-10-01',
        'category': 'کھاد',
      });
      expect(await expenseTotalPaisa(db), 1200000);

      await p.addLinkedEntry(
        partyId: partyId,
        type: PartyEntryType.udhaarLiya,
        amountPaisa: 1200000,
        date: '2026-10-02',
        sourceType: PartyEntrySourceType.expense,
        sourceId: expenseId,
      );
      expect(p.balanceOf(partyId), -1200000);

      await p.addLinkedEntry(
        partyId: partyId,
        type: PartyEntryType.adaigi,
        amountPaisa: 1200000,
        date: '2026-10-03',
        sourceType: PartyEntrySourceType.expense,
        sourceId: expenseId,
      );
      expect(p.balanceOf(partyId), 0);
      // Settling the payable must not book a second expense.
      expect(await expenseTotalPaisa(db), 1200000);
    });

    test('outstanding is 0 when nothing is linked', () async {
      final env = await openLinkedDb();
      expect(await env.provider.outstandingForSale(12345), 0);
    });
  });

  group('trace view', () {
    test('sourceSummary describes the row; survives its deletion', () async {
      final env = await openLinkedDb();
      final db = env.db;
      final p = env.provider;
      final partyId = await addParty(p, 'دانش');

      final saleId = await insertSale(db, totalPaisa: 6000000, buyer: 'علی');
      final instId = await db.insert('theka_installments', {
        'amount_paisa': 500000,
        'due_date': '2026-11-01',
        'status': 'pending',
      });
      await p.addLinkedEntry(
        partyId: partyId,
        type: PartyEntryType.udhaarDiya,
        amountPaisa: 6000000,
        date: '2026-10-02',
        sourceType: PartyEntrySourceType.sale,
        sourceId: saleId,
      );
      await p.addLinkedEntry(
        partyId: partyId,
        type: PartyEntryType.adaigi,
        amountPaisa: 500000,
        date: '2026-10-03',
        sourceType: PartyEntrySourceType.payment,
        sourceId: instId,
      );

      final saleSummary = await p.sourceSummary(
        PartyEntrySourceType.sale,
        saleId,
      );
      expect(saleSummary, isNotNull);
      expect(saleSummary!.title, 'فروخت #$saleId');
      expect(saleSummary.amountPaisa, 6000000);
      expect(saleSummary.date, '2026-10-01');
      expect(saleSummary.detail, 'خریدار: علی');

      final paySummary = await p.sourceSummary(
        PartyEntrySourceType.payment,
        instId,
      );
      expect(paySummary, isNotNull);
      expect(paySummary!.title, 'ٹھیکہ قسط #$instId');
      expect(paySummary.amountPaisa, 500000);

      // The source row is deleted later: the trace shows "removed", but the
      // link — and the entries — survive as an audit marker.
      await db.delete('sales', where: 'id = ?', whereArgs: [saleId]);
      expect(
        await p.sourceSummary(PartyEntrySourceType.sale, saleId),
        isNull,
      );
      expect(
        (await p.entriesForSource(PartyEntrySourceType.sale, saleId)).length,
        1,
      );
      // +6,000,000 (udhaar_diya) + 500,000 (adaigi) = 6,500,000.
      expect(p.balanceOf(partyId), 6500000);
    });
  });

  group('link validation', () {
    test('dangling links are rejected; nothing is written', () async {
      final env = await openLinkedDb();
      final p = env.provider;
      final partyId = await addParty(p, 'ناصر');

      expect(
        () => p.addLinkedEntry(
          partyId: partyId,
          type: PartyEntryType.wusooli,
          amountPaisa: 100000,
          date: '2026-10-01',
          sourceType: PartyEntrySourceType.sale,
          sourceId: 999,
        ),
        throwsA(isA<PartyException>()),
      );
      expect(p.balanceOf(partyId), 0);
      expect(await p.getEntries(partyId), isEmpty);
    });

    test('linked entries keep the amount/date validation', () async {
      final env = await openLinkedDb();
      final db = env.db;
      final p = env.provider;
      final partyId = await addParty(p, 'فہد');
      final saleId = await insertSale(db, totalPaisa: 100000);

      expect(
        () => p.addLinkedEntry(
          partyId: partyId,
          type: PartyEntryType.udhaarDiya,
          amountPaisa: 0,
          date: '2026-10-01',
          sourceType: PartyEntrySourceType.sale,
          sourceId: saleId,
        ),
        throwsA(isA<PartyException>()),
      );
      expect(
        () => p.addLinkedEntry(
          partyId: partyId,
          type: PartyEntryType.udhaarDiya,
          amountPaisa: 100000,
          date: 'not-a-date',
          sourceType: PartyEntrySourceType.sale,
          sourceId: saleId,
        ),
        throwsA(isA<PartyException>()),
      );
      expect(await p.getEntries(partyId), isEmpty);
    });

    test('legacy rows and plain entries read as unlinked', () async {
      final env = await openLinkedDb();
      final db = env.db;
      final p = env.provider;
      final partyId = await addParty(p, 'کریم');

      // A pre-v16 row: inserted without the new columns.
      await db.insert('party_ledger_entries', {
        'party_id': partyId,
        'entry_type': 'udhaar_diya',
        'amount_paisa': 100000,
        'date': '2026-10-01',
        'created_at': '2026-10-01T00:00:00',
      });
      // A plain manual entry stays unlinked too.
      await p.addEntry(
        partyId: partyId,
        type: PartyEntryType.wusooli,
        amountPaisa: 40000,
        date: '2026-10-02',
      );

      final entries = await p.getEntries(partyId);
      expect(entries.length, 2);
      for (final e in entries) {
        expect(e.sourceType, isNull);
        expect(e.sourceId, isNull);
      }
      expect(p.balanceOf(partyId), 60000); // 100,000 − 40,000
    });
  });
}
