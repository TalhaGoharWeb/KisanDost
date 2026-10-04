import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// Hermetic offline-reliability tests: a kill (exception) in the middle of a
/// multi-step write must never leave torn state. These exercise the exact
/// transaction mechanism every provider relies on (`db.transaction`), plus
/// the all-or-nothing property of the delete-all-data wipe pattern.
///
/// No app singleton, no filesystem paths, no plugins, no network.
void main() {
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  group('interrupted writes roll back', () {
    late Database db;

    setUp(() async {
      db = await databaseFactoryFfi.openDatabase(inMemoryDatabasePath);
      await db.execute(
        'CREATE TABLE ledger (id INTEGER PRIMARY KEY AUTOINCREMENT, label TEXT NOT NULL)',
      );
      // One pre-existing row: the "farmer's data" that must survive a crash.
      await db.insert('ledger', {'label': 'existing'});
    });

    tearDown(() async {
      await db.close();
    });

    test('throw mid-transaction undoes earlier writes in the same transaction',
        () async {
      await expectLater(
        db.transaction((txn) async {
          await txn.insert('ledger', {'label': 'new-1'});
          await txn.insert('ledger', {'label': 'new-2'});
          // Simulate the process being killed here.
          throw Exception('simulated kill');
        }),
        throwsException,
      );

      final rows = await db.query('ledger', orderBy: 'id');
      // Only the pre-existing row survives: the torn write is fully undone.
      expect(rows.map((r) => r['label']), ['existing']);
    });

    test('a completed transaction commits every write', () async {
      await db.transaction((txn) async {
        await txn.insert('ledger', {'label': 'new-1'});
        await txn.insert('ledger', {'label': 'new-2'});
      });

      final rows = await db.query('ledger', orderBy: 'id');
      expect(rows.map((r) => r['label']), ['existing', 'new-1', 'new-2']);
    });

    test('multi-table wipe that fails midway keeps every table intact',
        () async {
      await db.execute(
        'CREATE TABLE child (id INTEGER PRIMARY KEY AUTOINCREMENT, v TEXT)',
      );
      await db.insert('child', {'v': 'c1'});
      await db.insert('ledger', {'label': 'keep-me'});

      // Mimics DatabaseHelper.clearTables: N sequential deletes inside one
      // transaction, with a failure injected halfway (here: a typo'd table).
      Future<void> wipe(Database db) => db.transaction((txn) async {
            await txn.delete('child');
            await txn.delete('ledger');
            await txn.delete('no_such_table_boom');
          });

      await expectLater(wipe(db), throwsException);

      // Atomicity: because the wipe failed, NOTHING was deleted.
      expect(await db.query('child'), hasLength(1));
      expect(await db.query('ledger'), hasLength(2));
    });
  });
}
