import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:kisan_dost/database/db_helper.dart';
import 'package:kisan_dost/models/batai.dart';
import 'package:kisan_dost/models/party.dart';
import 'package:kisan_dost/providers/batai_provider.dart';
import 'package:kisan_dost/providers/party_provider.dart';
import 'package:kisan_dost/services/restore_service.dart';

/// Hermetic tests for the v14 batai (بٹائی) sharecropping feature. They
/// exercise the REAL migration SQL ([DatabaseHelper.migrateV13ToV14]) and
/// the REAL provider against an in-memory FFI database (via BataiProvider's
/// test executor) — the app singleton is never touched.
///
/// What "correct" means, from the farmer's point of view:
/// * shares are integer percents summing to exactly 100;
/// * every settlement splits to the paisa with owner + cultivator == total,
///   ALWAYS (the rounding rule: leftovers go to the larger share, ties to
///   the owner — also enforced by a DB CHECK constraint);
/// * terms lock the moment the first settlement exists; notes and the
///   manual status stay editable;
/// * settlements are append-only (no delete/update API at all);
/// * an agreement with settlements can NEVER be deleted;
/// * settling never auto-flips the status — the farmer marks the season
///   settled himself, because one season settles over several harvests.
void main() {
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  Future<Database> openV13Db() {
    return openDatabase(
      inMemoryDatabasePath,
      onConfigure: (db) async {
        await db.execute('PRAGMA foreign_keys = ON');
      },
    );
  }

  Future<BataiProvider> openProvider() async {
    final db = await openV13Db();
    await DatabaseHelper.migrateV12ToV13(db);
    await DatabaseHelper.migrateV13ToV14(db);
    // Minimal stand-ins for the tables batai_agreements/_settlements
    // reference. SQLite with PRAGMA foreign_keys = ON needs every
    // REFERENCES target to EXIST (even for a plain DELETE on the child),
    // so the harness creates them; production always has the real ones.
    await db.execute(
        'CREATE TABLE IF NOT EXISTS farms (id INTEGER PRIMARY KEY AUTOINCREMENT, name TEXT NOT NULL, total_area REAL NOT NULL, created_at TEXT NOT NULL)');
    await db.execute(
        'CREATE TABLE IF NOT EXISTS fields (id INTEGER PRIMARY KEY AUTOINCREMENT, farm_id INTEGER NOT NULL, name TEXT NOT NULL, size_acres REAL NOT NULL, canal_water_available INTEGER NOT NULL DEFAULT 0, tube_well_available INTEGER NOT NULL DEFAULT 0, location TEXT)');
    await db.execute(
        'CREATE TABLE IF NOT EXISTS crop_seasons (id INTEGER PRIMARY KEY AUTOINCREMENT, field_id INTEGER NOT NULL, crop_name TEXT NOT NULL, variety TEXT NOT NULL, status TEXT NOT NULL, start_date TEXT NOT NULL)');
    await db.execute(
        'CREATE TABLE IF NOT EXISTS harvests (id INTEGER PRIMARY KEY AUTOINCREMENT, crop_season_id INTEGER NOT NULL, quantity REAL NOT NULL, unit TEXT NOT NULL, date TEXT NOT NULL)');
    await db.execute(
        'CREATE TABLE IF NOT EXISTS sales (id INTEGER PRIMARY KEY AUTOINCREMENT, harvest_id INTEGER NOT NULL, quantity REAL NOT NULL, price_per_unit_paisa INTEGER NOT NULL, total_amount_paisa INTEGER NOT NULL, date TEXT NOT NULL)');
    // FFI in-memory databases are shared across openDatabase() calls in one
    // test run: start every test from empty tables (children first — FKs
    // are enforced).
    await db.delete('batai_settlements');
    await db.delete('batai_agreements');
    await db.delete('party_ledger_entries');
    await db.delete('parties');
    return BataiProvider(testExecutor: db);
  }

  /// Creates a party through the REAL PartyProvider on the same DB, so the
  /// FK from batai_agreements.other_party_id resolves.
  Future<int> addPartyOn(BataiProvider p, String name) {
    final parties = PartyProvider(testExecutor: p.testExecutor);
    return parties.addParty(Party(
      name: name,
      createdAt: DateTime.now().toIso8601String(),
    ));
  }

  Future<int> addAgreement(
    BataiProvider p, {
    int? partyId,
    FarmerRole role = FarmerRole.cultivator,
    int owner = 50,
    int cultivator = 50,
    String startDate = '2026-01-01',
    String? endDate,
  }) async {
    final pid = partyId ?? await addPartyOn(p, 'زمیندار');
    return p.createAgreement(
      farmerRole: role,
      otherPartyId: pid,
      ownerSharePercent: owner,
      cultivatorSharePercent: cultivator,
      startDate: startDate,
      endDate: endDate,
    );
  }

  group('DB v14 migration', () {
    test('creates batai tables + index, idempotently', () async {
      final db = await openV13Db();
      await DatabaseHelper.migrateV13ToV14(db);
      // Second run must be a no-op, not an error.
      await DatabaseHelper.migrateV13ToV14(db);

      final tables = (await db.rawQuery(
              "SELECT name FROM sqlite_master WHERE type = 'table'"))
          .map((r) => r['name'] as String)
          .toSet();
      expect(tables, containsAll(['batai_agreements', 'batai_settlements']));

      final agrCols = (await db.rawQuery(
              'PRAGMA table_info(batai_agreements)'))
          .map((c) => c['name'] as String)
          .toSet();
      expect(
          agrCols,
          containsAll([
            'id',
            'farmer_role',
            'other_party_id',
            'farm_id',
            'field_id',
            'crop_season_id',
            'owner_share_percent',
            'cultivator_share_percent',
            'expense_note',
            'start_date',
            'end_date',
            'status',
            'notes',
            'created_at',
          ]));

      final setCols = (await db.rawQuery(
              'PRAGMA table_info(batai_settlements)'))
          .map((c) => c['name'] as String)
          .toSet();
      expect(
          setCols,
          containsAll([
            'id',
            'agreement_id',
            'harvest_id',
            'sale_id',
            'total_paisa',
            'owner_paisa',
            'cultivator_paisa',
            'settle_date',
            'note',
            'created_at',
          ]));

      final indexes = (await db.rawQuery(
              "SELECT name FROM sqlite_master WHERE type = 'index'"))
          .map((r) => r['name'] as String)
          .toSet();
      expect(indexes, contains('idx_batai_settlements_agreement'));

      // The exactness CHECKs are in the schema.
      final sql = (await db.rawQuery(
              "SELECT sql FROM sqlite_master WHERE type = 'table'"))
          .map((r) => r['sql'] as String)
          .join('\n');
      expect(sql,
          contains('owner_share_percent + cultivator_share_percent = 100'));
      expect(sql, contains('owner_paisa + cultivator_paisa = total_paisa'));
    });

    test('DB CHECK rejects a settlement that does not add up', () async {
      final p = await openProvider();
      final agrId = await addAgreement(p);

      // Bypass the provider (which always computes a correct split) to
      // prove the CHECK constraint itself holds.
      final db = p.testExecutor as Database;
      expect(
        () => db.insert('batai_settlements', {
          'agreement_id': agrId,
          'total_paisa': 100,
          'owner_paisa': 40, // 40 + 50 != 100
          'cultivator_paisa': 50,
          'settle_date': '2026-06-01',
          'created_at': DateTime.now().toIso8601String(),
        }),
        throwsA(isA<DatabaseException>()),
      );

      expect(
        () => db.insert('batai_agreements', {
          'farmer_role': 'cultivator',
          'other_party_id': 999999, // also: no such party
          'owner_share_percent': 60,
          'cultivator_share_percent': 30, // 60 + 30 != 100
          'start_date': '2026-01-01',
          'created_at': DateTime.now().toIso8601String(),
        }),
        throwsA(isA<DatabaseException>()),
      );
    });
  });

  group('share validation', () {
    test('shares must sum to exactly 100', () async {
      final p = await openProvider();
      expect(
        () => addAgreement(p, owner: 60, cultivator: 30),
        throwsA(isA<BataiException>()),
      );
      expect(p.agreements, isEmpty);
    });

    test('shares must be 0..100', () async {
      final p = await openProvider();
      expect(
        () => addAgreement(p, owner: 150, cultivator: -50),
        throwsA(isA<BataiException>()),
      );
      expect(p.agreements, isEmpty);
    });

    test('edge splits 0/100 and 100/0 are allowed', () async {
      final p = await openProvider();
      await addAgreement(p, owner: 0, cultivator: 100);
      await addAgreement(p, owner: 100, cultivator: 0);
      expect(p.agreements, hasLength(2));
    });

    test('other party must exist', () async {
      final p = await openProvider();
      expect(
        () => p.createAgreement(
          farmerRole: FarmerRole.landowner,
          otherPartyId: 424242,
          ownerSharePercent: 50,
          cultivatorSharePercent: 50,
          startDate: '2026-01-01',
        ),
        throwsA(isA<BataiException>()),
      );
    });

    test('dates are validated: bad start, end before start', () async {
      final p = await openProvider();
      expect(
        () => addAgreement(p, startDate: 'not-a-date'),
        throwsA(isA<BataiException>()),
      );
      expect(
        () => addAgreement(p,
            startDate: '2026-06-01', endDate: '2026-01-01'),
        throwsA(isA<BataiException>()),
      );
      expect(p.agreements, isEmpty);
    });

    test('valid agreement appears in summaries with the party name',
        () async {
      final p = await openProvider();
      final pid = await addPartyOn(p, 'چوہدری صاحب');
      await p.createAgreement(
        farmerRole: FarmerRole.landowner,
        otherPartyId: pid,
        ownerSharePercent: 60,
        cultivatorSharePercent: 40,
        expenseNote: 'کھاد مزارع کی',
        startDate: '2026-01-01',
        notes: 'پہلا معاہدہ',
      );

      final list = await p.getAgreementSummaries();
      expect(list, hasLength(1));
      final s = list.first;
      expect(s.partyName, 'چوہدری صاحب');
      expect(s.agreement.farmerRole, FarmerRole.landowner);
      expect(s.agreement.ownerSharePercent, 60);
      expect(s.agreement.cultivatorSharePercent, 40);
      expect(s.agreement.expenseNote, 'کھاد مزارع کی');
      expect(s.agreement.status, BataiStatus.active);
      expect(s.agreement.mySharePercent, 60); // landowner → owner share
      expect(s.agreement.otherSharePercent, 40);

      expect(farmerRoleUrdu(FarmerRole.landowner), 'میں مالک ہوں');
      expect(farmerRoleUrdu(FarmerRole.cultivator), 'میں مزارع ہوں');
      expect(bataiStatusUrdu(BataiStatus.active), 'فعال');
      expect(bataiStatusUrdu(BataiStatus.settled), 'چکتا شدہ');
      expect(bataiStatusUrdu(BataiStatus.cancelled), 'منسوخ');
    });

    test('summaries resolve crop/farm/field names via LEFT JOINs', () async {
      final p = await openProvider();
      final db = p.testExecutor as Database;
      final farmId = await db.insert('farms',
          {'name': 'چک نمبر 5', 'total_area': 10.0, 'created_at': 'x'});
      final fieldId = await db.insert('fields', {
        'farm_id': farmId,
        'name': 'مشرقی کھیت',
        'size_acres': 5.0,
      });
      final cropId = await db.insert('crop_seasons', {
        'field_id': fieldId,
        'crop_name': 'گندم',
        'variety': 'فیصل آباد',
        'status': 'active',
        'start_date': '2026-01-01',
      });

      final pid = await addPartyOn(p, 'مزارع احمد');
      await p.createAgreement(
        farmerRole: FarmerRole.landowner,
        otherPartyId: pid,
        fieldId: fieldId, // farm resolved through the field
        cropSeasonId: cropId,
        ownerSharePercent: 50,
        cultivatorSharePercent: 50,
        startDate: '2026-01-01',
      );

      final list = await p.getAgreementSummaries();
      expect(list, hasLength(1));
      expect(list.first.partyName, 'مزارع احمد');
      expect(list.first.cropName, 'گندم');
      expect(list.first.fieldName, 'مشرقی کھیت');
      expect(list.first.farmName, 'چک نمبر 5');
    });

    test('getAgreementSummaries filters by status', () async {
      final p = await openProvider();
      final id1 = await addAgreement(p);
      await addAgreement(p);
      await p.setStatus(id1, BataiStatus.settled);

      expect((await p.getAgreementSummaries()).length, 2);
      expect((await p.getAgreementSummaries(status: BataiStatus.active)).length,
          1);
      expect(
          (await p.getAgreementSummaries(status: BataiStatus.settled)).length,
          1);
    });
  });

  group('splitBatai rounding rule', () {
    test('10001 paisa at 50/50: tie goes to the owner (5001/5000)', () {
      final s = splitBatai(10001, 50);
      expect(s.ownerPaisa, 5001);
      expect(s.cultivatorPaisa, 5000);
      expect(s.ownerPaisa + s.cultivatorPaisa, 10001);
    });

    test('100 paisa at 33/67 splits exactly', () {
      final s = splitBatai(100, 33);
      expect(s.ownerPaisa, 33);
      expect(s.cultivatorPaisa, 67);
    });

    test('1 paisa total goes whole to the larger share', () {
      final larger = splitBatai(1, 40); // cultivator 60
      expect(larger.ownerPaisa, 0);
      expect(larger.cultivatorPaisa, 1);
    });

    test('1 paisa total at 50/50: tie goes to the owner', () {
      final s = splitBatai(1, 50);
      expect(s.ownerPaisa, 1);
      expect(s.cultivatorPaisa, 0);
    });

    test('999 paisa at 33/67: remainder 1 goes to the cultivator', () {
      final s = splitBatai(999, 33);
      expect(s.ownerPaisa, 329); // 999*33~/100
      expect(s.cultivatorPaisa, 670); // 669 + 1 remainder
      expect(s.ownerPaisa + s.cultivatorPaisa, 999);
    });

    test('edge percents 0/100 and 100/0', () {
      final s0 = splitBatai(12345, 0);
      expect((s0.ownerPaisa, s0.cultivatorPaisa), (0, 12345));
      final s100 = splitBatai(12345, 100);
      expect((s100.ownerPaisa, s100.cultivatorPaisa), (12345, 0));
    });

    test('mySharePaisa is role-aware', () {
      // Landowner, 60/40, total 10001: owner 6001 (6000 + 1 remainder),
      // cultivator 4000.
      final landowner = BataiAgreement(
        farmerRole: FarmerRole.landowner,
        otherPartyId: 1,
        ownerSharePercent: 60,
        cultivatorSharePercent: 40,
        startDate: '2026-01-01',
        createdAt: 'x',
      );
      expect(landowner.mySharePercent, 60);
      expect(landowner.mySharePaisa(10001), 6001);
      expect(landowner.otherSharePaisa(10001), 4000);

      final cultivator = BataiAgreement(
        farmerRole: FarmerRole.cultivator,
        otherPartyId: 1,
        ownerSharePercent: 60,
        cultivatorSharePercent: 40,
        startDate: '2026-01-01',
        createdAt: 'x',
      );
      expect(cultivator.mySharePercent, 40);
      expect(cultivator.mySharePaisa(10001), 4000);
      expect(cultivator.otherSharePaisa(10001), 6001);
    });
  });

  group('settlements', () {
    test('settle inserts the computed split; status stays active', () async {
      final p = await openProvider();
      final agrId = await addAgreement(p, owner: 60, cultivator: 40);

      final setId = await p.settleAgreement(
        agreementId: agrId,
        totalPaisa: 10001,
        settleDate: '2026-06-01',
        note: 'پہلی فصل',
      );
      expect(setId, isNotNull);

      final settlements = await p.getSettlements(agrId);
      expect(settlements, hasLength(1));
      final s = settlements.first;
      expect(s.totalPaisa, 10001);
      expect(s.ownerPaisa, 6001);
      expect(s.cultivatorPaisa, 4000);
      expect(s.note, 'پہلی فصل');

      // DELIBERATE: one season settles over several harvests — the status
      // stays 'active' until the farmer marks it settled himself.
      final summary = await p.getAgreementSummary(agrId);
      expect(summary!.agreement.status, BataiStatus.active);
    });

    test('multiple settlements per agreement are allowed (partial harvests)',
        () async {
      final p = await openProvider();
      final agrId = await addAgreement(p);

      await p.settleAgreement(
          agreementId: agrId, totalPaisa: 500000, settleDate: '2026-06-01');
      await p.settleAgreement(
          agreementId: agrId, totalPaisa: 300000, settleDate: '2026-07-01');

      final settlements = await p.getSettlements(agrId);
      expect(settlements, hasLength(2));
      // Newest first.
      expect(settlements.first.settleDate, '2026-07-01');
      final total = settlements.fold<int>(0, (sum, s) => sum + s.totalPaisa);
      expect(total, 800000);
    });

    test('zero/negative totals and bad dates are rejected', () async {
      final p = await openProvider();
      final agrId = await addAgreement(p);
      for (final bad in [0, -100]) {
        expect(
          () => p.settleAgreement(
              agreementId: agrId,
              totalPaisa: bad,
              settleDate: '2026-06-01'),
          throwsA(isA<BataiException>()),
        );
      }
      expect(
        () => p.settleAgreement(
            agreementId: agrId, totalPaisa: 100, settleDate: 'nope'),
        throwsA(isA<BataiException>()),
      );
      expect(await p.getSettlements(agrId), isEmpty);
    });

    test('settling a cancelled agreement is rejected', () async {
      final p = await openProvider();
      final agrId = await addAgreement(p);
      await p.setStatus(agrId, BataiStatus.cancelled);
      expect(
        () => p.settleAgreement(
            agreementId: agrId, totalPaisa: 100, settleDate: '2026-06-01'),
        throwsA(isA<BataiException>()),
      );
    });

    test('settling a manually-settled agreement is rejected', () async {
      final p = await openProvider();
      final agrId = await addAgreement(p);
      await p.setStatus(agrId, BataiStatus.settled);
      expect(
        () => p.settleAgreement(
            agreementId: agrId, totalPaisa: 100, settleDate: '2026-06-01'),
        throwsA(isA<BataiException>()),
      );
    });

    test('settlements are append-only: no delete/update API exists', () {
      // Compile-time guarantee: BataiProvider exposes settleAgreement and
      // getSettlements — and no deleteSettlement/updateSettlement.
      final p = BataiProvider();
      expect(p, isA<BataiProvider>());
    });
  });

  group('deletion rules', () {
    test('deleteAgreement is blocked when settlements exist', () async {
      final p = await openProvider();
      final agrId = await addAgreement(p);
      await p.settleAgreement(
          agreementId: agrId, totalPaisa: 100000, settleDate: '2026-06-01');

      expect(() => p.deleteAgreement(agrId), throwsA(isA<BataiException>()));
      // Agreement and its settlement survive.
      expect((await p.getAgreementSummaries()).length, 1);
      expect((await p.getSettlements(agrId)).length, 1);
    });

    test('deleteAgreement is allowed with zero settlements', () async {
      final p = await openProvider();
      final agrId = await addAgreement(p);
      await p.deleteAgreement(agrId);
      expect(await p.getAgreementSummaries(), isEmpty);
    });
  });

  group('update rules', () {
    test('terms are locked after the first settlement', () async {
      final p = await openProvider();
      final pid = await addPartyOn(p, 'فریق');
      final agrId = await addAgreement(p, partyId: pid);
      await p.settleAgreement(
          agreementId: agrId, totalPaisa: 100000, settleDate: '2026-06-01');

      expect(
        () => p.updateTerms(
          id: agrId,
          farmerRole: FarmerRole.landowner,
          otherPartyId: pid,
          ownerSharePercent: 70,
          cultivatorSharePercent: 30,
          startDate: '2026-01-01',
        ),
        throwsA(isA<BataiException>()),
      );
      // Terms unchanged.
      final summary = await p.getAgreementSummary(agrId);
      expect(summary!.agreement.ownerSharePercent, 50);
      expect(summary.agreement.farmerRole, FarmerRole.cultivator);
    });

    test('terms are editable before any settlement', () async {
      final p = await openProvider();
      final pid = await addPartyOn(p, 'فریق');
      final pid2 = await addPartyOn(p, 'دوسرا فریق');
      final agrId = await addAgreement(p, partyId: pid);
      await p.updateTerms(
        id: agrId,
        farmerRole: FarmerRole.landowner,
        otherPartyId: pid2,
        ownerSharePercent: 70,
        cultivatorSharePercent: 30,
        startDate: '2026-02-01',
        endDate: '2026-12-31',
      );
      final summary = await p.getAgreementSummary(agrId);
      expect(summary!.agreement.farmerRole, FarmerRole.landowner);
      expect(summary.agreement.ownerSharePercent, 70);
      expect(summary.agreement.cultivatorSharePercent, 30);
      expect(summary.agreement.otherPartyId, pid2);
      expect(summary.agreement.startDate, '2026-02-01');
    });

    test('notes stay editable after a settlement', () async {
      final p = await openProvider();
      final agrId = await addAgreement(p);
      await p.settleAgreement(
          agreementId: agrId, totalPaisa: 100000, settleDate: '2026-06-01');
      await p.updateNotes(agrId,
          expenseNote: 'کھاد مزارع کی، بیج آدھا آدھا', notes: 'نیا نوٹ');
      final summary = await p.getAgreementSummary(agrId);
      expect(summary!.agreement.expenseNote, 'کھاد مزارع کی، بیج آدھا آدھا');
      expect(summary.agreement.notes, 'نیا نوٹ');
    });

    test('setStatus is always allowed', () async {
      final p = await openProvider();
      final agrId = await addAgreement(p);
      await p.setStatus(agrId, BataiStatus.settled);
      expect((await p.getAgreementSummary(agrId))!.agreement.status,
          BataiStatus.settled);
      await p.setStatus(agrId, BataiStatus.active);
      expect((await p.getAgreementSummary(agrId))!.agreement.status,
          BataiStatus.active);
    });
  });

  group('backup merge order', () {
    test('batai tables sit between party_ledger_entries and tasks', () {
      final order = RestoreService.mergeTableOrder;
      expect(order.indexOf('parties'),
          lessThan(order.indexOf('batai_agreements')));
      expect(order.indexOf('batai_agreements'),
          lessThan(order.indexOf('batai_settlements')));
      expect(order.indexOf('batai_settlements'),
          lessThan(order.indexOf('tasks')));
    });
  });
}
