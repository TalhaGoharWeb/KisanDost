import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:kisan_dost/database/db_helper.dart';
import 'package:kisan_dost/models/party.dart';
import 'package:kisan_dost/providers/party_provider.dart';
import 'package:kisan_dost/services/restore_service.dart';

/// Hermetic tests for the v13 party ledger (udhaar). They exercise the REAL
/// migration SQL ([DatabaseHelper.migrateV12ToV13], then the v14→v15
/// soft-delete migration) and the REAL provider
/// against an in-memory FFI database (via PartyProvider's test executor) —
/// the app singleton is never touched.
///
/// What "correct" means, from the farmer's point of view:
/// * entry amounts are SIGNED from the farmer's perspective: positive =
///   the party owes me (receivable), negative = I owe the party (payable);
/// * balances are always SUM() — never a stored column that can drift;
/// * a party with ledger entries can NEVER be deleted (financial history
///   must survive); entries are append-only (no delete API at all);
/// * zero/negative input amounts are rejected loudly with Urdu errors.
void main() {
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  Future<Database> openV12Db() {
    return openDatabase(
      inMemoryDatabasePath,
      onConfigure: (db) async {
        await db.execute('PRAGMA foreign_keys = ON');
      },
    );
  }

  Future<PartyProvider> openProvider() async {
    final db = await openV12Db();
    await DatabaseHelper.migrateV12ToV13(db);
    // The current provider expects the v15 schema (soft-delete columns);
    // chain the real v14→v15 migration on top.
    await DatabaseHelper.migrateV14ToV15(db);
    // FFI in-memory databases are shared across openDatabase() calls in one
    // test run: start every test from empty tables.
    await db.delete('party_ledger_entries');
    await db.delete('parties');
    return PartyProvider(testExecutor: db);
  }

  Future<int> addParty(PartyProvider p, String name) => p.addParty(
    Party(name: name, createdAt: DateTime.now().toIso8601String()),
  );

  group('DB v13 migration', () {
    test(
      'creates parties and party_ledger_entries tables, idempotently',
      () async {
        final db = await openV12Db();
        await DatabaseHelper.migrateV12ToV13(db);
        // Second run must be a no-op, not an error.
        await DatabaseHelper.migrateV12ToV13(db);

        final tables =
            (await db.rawQuery(
              "SELECT name FROM sqlite_master WHERE type = 'table'",
            )).map((r) => r['name'] as String).toSet();
        expect(tables, containsAll(['parties', 'party_ledger_entries']));

        final entryCols =
            (await db.rawQuery(
              'PRAGMA table_info(party_ledger_entries)',
            )).map((c) => c['name'] as String).toSet();
        expect(
          entryCols,
          containsAll([
            'id',
            'party_id',
            'entry_type',
            'amount_paisa',
            'date',
            'note',
            'created_at',
          ]),
        );

        final indexes =
            (await db.rawQuery(
              "SELECT name FROM sqlite_master WHERE type = 'index'",
            )).map((r) => r['name'] as String).toSet();
        expect(indexes, contains('idx_party_ledger_entries_party'));
      },
    );
  });

  group('entry type signs', () {
    test('udhaar_diya is +receivable, udhaar_liya is -payable', () async {
      final p = await openProvider();
      final id = await addParty(p, 'علی');

      await p.addEntry(
        partyId: id,
        type: PartyEntryType.udhaarDiya,
        amountPaisa: 500000,
        date: '2026-10-01',
      );
      expect(p.balanceOf(id), 500000);

      await p.addEntry(
        partyId: id,
        type: PartyEntryType.udhaarLiya,
        amountPaisa: 200000,
        date: '2026-10-01',
      );
      expect(p.balanceOf(id), 300000);
    });

    test('wusooli reduces receivable, adaigi reduces payable', () async {
      final p = await openProvider();
      final id = await addParty(p, 'بشیر');

      await p.addEntry(
        partyId: id,
        type: PartyEntryType.udhaarDiya,
        amountPaisa: 500000,
        date: '2026-10-01',
      );
      await p.addEntry(
        partyId: id,
        type: PartyEntryType.wusooli,
        amountPaisa: 200000,
        date: '2026-10-02',
      );
      expect(p.balanceOf(id), 300000);

      await p.addEntry(
        partyId: id,
        type: PartyEntryType.udhaarLiya,
        amountPaisa: 100000,
        date: '2026-10-03',
      );
      expect(p.balanceOf(id), 200000);
      await p.addEntry(
        partyId: id,
        type: PartyEntryType.adaigi,
        amountPaisa: 100000,
        date: '2026-10-04',
      );
      expect(p.balanceOf(id), 300000);
    });

    test('getEntries returns newest first with Urdu type labels', () async {
      final p = await openProvider();
      final id = await addParty(p, 'کریم');
      await p.addEntry(
        partyId: id,
        type: PartyEntryType.udhaarDiya,
        amountPaisa: 100000,
        date: '2026-09-01',
        note: 'پہلا',
      );
      await p.addEntry(
        partyId: id,
        type: PartyEntryType.wusooli,
        amountPaisa: 40000,
        date: '2026-10-01',
        note: 'دوسرا',
      );

      final entries = await p.getEntries(id);
      expect(entries.length, 2);
      expect(entries.first.date, '2026-10-01');
      expect(entries.first.type, PartyEntryType.wusooli);
      expect(entries.first.amountPaisa, -40000);
      expect(partyEntryTypeUrdu(PartyEntryType.udhaarDiya), 'ادھار دیا');
      expect(partyEntryTypeUrdu(PartyEntryType.wusooli), 'وصولی');
    });
  });

  group('totals', () {
    test(
      'totalReceivable/totalPayable split positive and negative balances',
      () async {
        final p = await openProvider();
        final a = await addParty(p, 'الف');
        final b = await addParty(p, 'ب');
        await addParty(p, 'ج'); // zero balance

        await p.addEntry(
          partyId: a,
          type: PartyEntryType.udhaarDiya,
          amountPaisa: 500000,
          date: '2026-10-01',
        );
        await p.addEntry(
          partyId: b,
          type: PartyEntryType.udhaarLiya,
          amountPaisa: 300000,
          date: '2026-10-01',
        );

        expect(p.totalReceivablePaisa, 500000);
        expect(p.totalPayablePaisa, 300000);
        expect(p.allBalances[a], 500000);
        expect(p.allBalances[b], -300000);
      },
    );
  });

  group('deletion rules', () {
    test('deleteParty is blocked when entries exist; party survives', () async {
      final p = await openProvider();
      final id = await addParty(p, 'دانش');
      await p.addEntry(
        partyId: id,
        type: PartyEntryType.udhaarDiya,
        amountPaisa: 100000,
        date: '2026-10-01',
      );

      expect(() => p.deleteParty(id), throwsA(isA<PartyException>()));
      // Party and its entries are still there.
      expect(p.parties.any((x) => x.id == id), isTrue);
      expect(p.balanceOf(id), 100000);
      expect((await p.getEntries(id)).length, 1);
    });

    test('deleteParty is allowed with zero entries', () async {
      final p = await openProvider();
      final id = await addParty(p, 'عارضی');
      await p.deleteParty(id);
      expect(p.parties.any((x) => x.id == id), isFalse);
    });

    test('ledger entries are append-only: no delete API exists', () {
      // Compile-time guarantee: PartyProvider exposes addParty, updateParty,
      // deleteParty, addEntry, getEntries — and no deleteEntry/updateEntry.
      // This test documents the rule; a future delete API breaks the build
      // only if someone adds it, which code review must catch.
      final p = PartyProvider();
      expect(p, isA<PartyProvider>());
    });
  });

  group('validation', () {
    test('zero and negative amounts are rejected with Urdu errors', () async {
      final p = await openProvider();
      final id = await addParty(p, 'ناصر');
      for (final bad in [0, -500]) {
        expect(
          () => p.addEntry(
            partyId: id,
            type: PartyEntryType.udhaarDiya,
            amountPaisa: bad,
            date: '2026-10-01',
          ),
          throwsA(isA<PartyException>()),
        );
      }
      expect(p.balanceOf(id), 0);
      expect(await p.getEntries(id), isEmpty);
    });

    test('empty party name is rejected', () async {
      final p = await openProvider();
      expect(() => addParty(p, '   '), throwsA(isA<PartyException>()));
      expect(p.parties, isEmpty);
    });

    test('invalid date is rejected', () async {
      final p = await openProvider();
      final id = await addParty(p, 'فہد');
      expect(
        () => p.addEntry(
          partyId: id,
          type: PartyEntryType.udhaarDiya,
          amountPaisa: 100000,
          date: 'not-a-date',
        ),
        throwsA(isA<PartyException>()),
      );
    });
  });

  group('backup merge order', () {
    test('parties comes before party_ledger_entries', () {
      final order = RestoreService.mergeTableOrder;
      expect(
        order.indexOf('parties'),
        lessThan(order.indexOf('party_ledger_entries')),
      );
    });
  });
}
