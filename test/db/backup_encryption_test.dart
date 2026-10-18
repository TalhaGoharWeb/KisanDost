import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite/sqflite.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:kisan_dost/database/db_helper.dart';
import 'package:kisan_dost/services/backup_service.dart';
import 'package:kisan_dost/services/restore_service.dart';

/// Hermetic encrypted-backup tests (owner decision #6).
///
/// Exercises the REAL [BackupService]/[RestoreService] against a REAL
/// file-based database via the FFI factory — same harness as
/// backup_restore_test.dart: the databases path is pointed at a fresh
/// temp dir per test, and `BackupService(backupsDir:, liveDbPath:)`
/// keeps everything inside the temp root.
///
/// Crypto under test: passphrase → PBKDF2-HMAC-SHA256 (210k) →
/// AES-256-GCM + Encrypt-then-MAC + plaintext verifier, all through
/// vetted packages (package:encrypt / pointycastle / package:crypto).
/// Nothing here hand-rolls crypto — these tests pin the observable
/// contract: round-trip, wrong-password vs tampered errors (distinct,
/// Urdu, no crash), atomic writes, and the unencrypted path untouched.
void main() {
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  const testPassphrase = 'میری خفیہ بات'; // Urdu passphrase, realistic input.
  const wrongPassphrase = 'غلط پاس فریز';

  late Directory tempRoot;
  late BackupService backups;
  late RestoreService restore;

  setUpAll(() {
    SharedPreferences.setMockInitialValues({});
  });

  setUp(() async {
    tempRoot = await Directory.systemTemp.createTemp('kisan_enc_test_');
    await databaseFactory.setDatabasesPath(join(tempRoot.path, 'databases'));
    await DatabaseHelper.instance.close();
    final liveDbPath = await DatabaseHelper.instance.databaseFilePath;
    backups = BackupService(
      backupsDir: Directory(join(tempRoot.path, 'backups')),
      liveDbPath: liveDbPath,
    );
    restore = RestoreService(backupService: backups);
  });

  tearDown(() async {
    await DatabaseHelper.instance.close();
    await tempRoot.delete(recursive: true);
  });

  Future<void> populateSampleData() async {
    final db = await DatabaseHelper.instance.database;
    final farmId = await db.insert('farms', {
      'name': 'میری زمین',
      'total_area': 10.0,
      'created_at': '2026-01-01',
    });
    await db.insert('expenses', {
      'category': 'بیج',
      'amount_paisa': 500000,
      'date': '2026-01-11',
      'farm_id': farmId,
    });
  }

  Future<int> count(Database db, String table) async =>
      Sqflite.firstIntValue(
        await db.rawQuery('SELECT COUNT(*) FROM "$table"'),
      ) ??
      0;

  /// Extracts the BackupException message, failing loudly otherwise.
  Future<String> exceptionMessage(Future<void> Function() fn) async {
    try {
      await fn();
    } on BackupException catch (e) {
      return e.message;
    }
    fail('expected a BackupException');
  }

  group('encrypted create / verify round-trip', () {
    test('encrypt -> verify -> decrypt yields a valid database', () async {
      await populateSampleData();
      final info = await backups.createBackup(
        label: 'خفیہ ٹیسٹ',
        passphrase: testPassphrase,
        hint: 'میرے بیٹے کا نام',
      );

      expect(info.isEncrypted, isTrue);
      expect(info.hint, 'میرے بیٹے کا نام');
      expect(info.name, endsWith('.db.enc'));
      expect(await File(info.path).exists(), isTrue);
      expect(await File(info.sidecarPath!).exists(), isTrue);

      // The ciphertext must not contain the plaintext farm name.
      final encBytes = await File(info.path).readAsBytes();
      expect(
        utf8.decode(encBytes, allowMalformed: true).contains('میری زمین'),
        isFalse,
      );

      // Sidecar marks encryption, stores the hint in plaintext, and the
      // sha256 covers the .enc bytes.
      final sidecar =
          jsonDecode(await File(info.sidecarPath!).readAsString())
              as Map<String, dynamic>;
      expect(sidecar['encrypted'], isTrue);
      expect(sidecar['hint'], 'میرے بیٹے کا نام');
      expect(sidecar['kdf'], 'pbkdf2-hmac-sha256');
      expect(sidecar['kdfIterations'], kBackupKdfIterations);
      expect(sidecar.containsKey('passphrase'), isFalse);
      // No key material anywhere in the sidecar.
      final sidecarText = jsonEncode(sidecar);
      expect(sidecarText.contains('salt'), isFalse);
      expect(sidecarText.contains('nonce'), isFalse);

      // verifyBackup with the right passphrase passes.
      await backups.verifyBackup(info.path, passphrase: testPassphrase);

      // Decrypting manually gives back a working database with our data.
      final tmp = await backups.decryptBackupToTemp(
        info.path,
        testPassphrase,
      );
      Database? probe;
      try {
        probe = await openDatabase(tmp, readOnly: true);
        final integrity = await probe.rawQuery('PRAGMA integrity_check');
        expect(integrity.first.values.first.toString(), 'ok');
        expect(await count(probe, 'farms'), 1);
        expect(await count(probe, 'expenses'), 1);
        final farms = await probe.query('farms');
        expect(farms.first['name'], 'میری زمین');
      } finally {
        await probe?.close();
        await File(tmp).delete();
      }

      // The app still has a usable DB afterwards.
      final db = await DatabaseHelper.instance.database;
      expect(await count(db, 'farms'), 1);
    });

    test('same passphrase still gives unique salt/nonce per backup', () async {
      await populateSampleData();
      final a = await backups.createBackup(passphrase: testPassphrase);
      final b = await backups.createBackup(passphrase: testPassphrase);
      final bytesA = await File(a.path).readAsBytes();
      final bytesB = await File(b.path).readAsBytes();
      // Different salt+nonce ⇒ different bytes (ciphertext and header).
      expect(bytesA.toString(), isNot(bytesB.toString()));
      await backups.verifyBackup(a.path, passphrase: testPassphrase);
      await backups.verifyBackup(b.path, passphrase: testPassphrase);
    });

    test('short passphrase is rejected with a clear Urdu error', () async {
      await populateSampleData();
      final msg = await exceptionMessage(
        () => backups.createBackup(passphrase: 'abc'),
      );
      expect(msg, contains('کم از کم 4 حروف'));
      // Nothing was written.
      expect(await backups.listBackups(), isEmpty);
    });

    test('unencrypted path still works and stays plaintext', () async {
      await populateSampleData();
      final info = await backups.createBackup(label: 'سادہ');
      expect(info.isEncrypted, isFalse);
      expect(info.name, endsWith('.db'));
      expect(info.name.endsWith('.db.enc'), isFalse);
      await backups.verifyBackup(info.path);
      // The plaintext bytes really are a SQLite file.
      final header = await File(
        info.path,
      ).openRead(0, 16).fold<List<int>>(<int>[], (a, b) => a..addAll(b));
      expect(utf8.decode(header), startsWith('SQLite format 3'));
    });
  });

  group('wrong passphrase vs tampered file', () {
    test('wrong passphrase gives a clear Urdu error, live DB untouched',
        () async {
      await populateSampleData();
      final info = await backups.createBackup(passphrase: testPassphrase);

      final msg = await exceptionMessage(
        () => backups.verifyBackup(info.path, passphrase: wrongPassphrase),
      );
      expect(msg, contains('پاس فریز غلط ہے'));

      // decryptBackupToTemp reports the same, without crashing.
      final msg2 = await exceptionMessage(
        () => backups.decryptBackupToTemp(info.path, wrongPassphrase),
      );
      expect(msg2, contains('پاس فریز غلط ہے'));

      // Live database is byte-identical: verification never touched it.
      final db = await DatabaseHelper.instance.database;
      expect(await count(db, 'farms'), 1);
    });

    test('verify without passphrase asks for it instead of failing '
        'cryptically', () async {
      await populateSampleData();
      final info = await backups.createBackup(passphrase: testPassphrase);

      final msg = await exceptionMessage(() => backups.verifyBackup(info.path));
      expect(msg, contains('پاس فریز درکار ہے'));
      // And crucially NOT the old cryptic wrong-magic message.
      expect(msg.contains('درست ڈیٹا بیس فائل نہیں'), isFalse);
    });

    test('tampered ciphertext is detected and distinguished from a '
        'wrong passphrase', () async {
      await populateSampleData();
      final info = await backups.createBackup(passphrase: testPassphrase);

      // Flip a byte deep in the ciphertext (past the 68-byte header).
      final bytes = await File(info.path).readAsBytes();
      bytes[100] = bytes[100] ^ 0xFF;
      await File(info.path).writeAsBytes(bytes, flush: true);

      // With the RIGHT passphrase the tamper is still caught...
      final tamperMsg = await exceptionMessage(
        () => backups.verifyBackup(info.path, passphrase: testPassphrase),
      );
      expect(tamperMsg, contains('تبدیلی پائی گئی'));

      // ...and the message differs from the wrong-passphrase message.
      final wrongPwMsg = await exceptionMessage(
        () => backups.decryptBackupToTemp(info.path, wrongPassphrase),
      );
      expect(wrongPwMsg, contains('پاس فریز غلط ہے'));
      expect(tamperMsg, isNot(wrongPwMsg));
    });

    test('truncated file is rejected as tampered, not as wrong password',
        () async {
      await populateSampleData();
      final info = await backups.createBackup(passphrase: testPassphrase);
      final bytes = await File(info.path).readAsBytes();
      await File(
        info.path,
      ).writeAsBytes(bytes.sublist(0, 40), flush: true); // header torn off

      final msg = await exceptionMessage(
        () => backups.verifyBackup(info.path, passphrase: testPassphrase),
      );
      expect(msg, contains('تبدیلی پائی گئی'));
    });
  });

  group('restore from encrypted backups', () {
    test('restoreReplace round-trips an encrypted backup', () async {
      await populateSampleData();
      final info = await backups.createBackup(passphrase: testPassphrase);

      // Mangle the live DB.
      final db = await DatabaseHelper.instance.database;
      await db.delete('farms');
      expect(await count(db, 'farms'), 0);

      final msg = await restore.restoreReplace(
        info.path,
        passphrase: testPassphrase,
      );
      expect(msg, contains('کامیابی'));

      final db2 = await DatabaseHelper.instance.database;
      expect(await count(db2, 'farms'), 1);
      final farms = await db2.query('farms');
      expect(farms.first['name'], 'میری زمین');

      // The pre-restore safety backup is encrypted too — no plaintext
      // copy of the data is left behind by the restore.
      final list = await backups.listBackups();
      final safety = list.firstWhere((b) => b.label == 'pre-restore');
      expect(safety.isEncrypted, isTrue);
      await backups.verifyBackup(safety.path, passphrase: testPassphrase);
    });

    test('restoreReplace without passphrase refuses before touching '
        'anything', () async {
      await populateSampleData();
      final info = await backups.createBackup(passphrase: testPassphrase);

      final msg = await exceptionMessage(() => restore.restoreReplace(info.path));
      expect(msg, contains('پاس فریز درکار ہے'));

      // No safety backup was taken, live DB untouched.
      expect(await backups.listBackups(), hasLength(1));
      final db = await DatabaseHelper.instance.database;
      expect(await count(db, 'farms'), 1);
    });

    test('restoreReplace with wrong passphrase fails cleanly', () async {
      await populateSampleData();
      final info = await backups.createBackup(passphrase: testPassphrase);
      final db = await DatabaseHelper.instance.database;
      await db.delete('farms');

      final msg = await exceptionMessage(
        () => restore.restoreReplace(info.path, passphrase: wrongPassphrase),
      );
      expect(msg, contains('پاس فریز غلط ہے'));

      // The mangled live DB is exactly as we left it — restore never
      // started (verify/decrypt happens before the safety backup).
      expect(await backups.listBackups(), hasLength(1));
      final db2 = await DatabaseHelper.instance.database;
      expect(await count(db2, 'farms'), 0);
    });

    test('restoreMerge works from an encrypted backup', () async {
      final db = await DatabaseHelper.instance.database;
      await db.insert('farms', {
        'name': 'A',
        'total_area': 5.0,
        'created_at': '2026-01-01',
      });
      final info = await backups.createBackup(passphrase: testPassphrase);

      final live = await DatabaseHelper.instance.database;
      await live.insert('farms', {
        'name': 'B',
        'total_area': 6.0,
        'created_at': '2026-01-02',
      });

      final result = await restore.restoreMerge(
        info.path,
        passphrase: testPassphrase,
      );
      expect(result.perTable['farms']!.imported, 0); // A already present
      expect(result.perTable['farms']!.skipped, 1);

      final live2 = await DatabaseHelper.instance.database;
      final names =
          (await live2.query('farms')).map((r) => r['name'].toString()).toSet();
      expect(names, {'A', 'B'});
    });
  });

  group('import of encrypted backups', () {
    test('imports a .db.enc file with the right passphrase', () async {
      await populateSampleData();
      final original = await backups.createBackup(
        passphrase: testPassphrase,
        hint: 'اشارہ',
      );

      // Simulate a file picked from outside the backups dir.
      final external = join(tempRoot.path, 'shared.db.enc');
      await File(original.path).copy(external);
      await File('${original.path}.json').copy('$external.json');

      final imported = await backups.importBackupFile(
        external,
        passphrase: testPassphrase,
      );
      expect(imported.isEncrypted, isTrue);
      expect(imported.hint, 'اشارہ');
      expect(imported.name, endsWith('.db.enc'));
      await backups.verifyBackup(imported.path, passphrase: testPassphrase);
    });

    test('import with wrong passphrase fails and leaves no partial copy',
        () async {
      await populateSampleData();
      final original = await backups.createBackup(passphrase: testPassphrase);
      final external = join(tempRoot.path, 'shared.db.enc');
      await File(original.path).copy(external);

      final msg = await exceptionMessage(
        () => backups.importBackupFile(external, passphrase: wrongPassphrase),
      );
      expect(msg, contains('پاس فریز غلط ہے'));

      // Only the original backup remains — no broken import copy.
      final list = await backups.listBackups();
      expect(list, hasLength(1));
      expect(list.first.path, original.path);
    });

    test('import of an encrypted pick without passphrase is refused',
        () async {
      await populateSampleData();
      final original = await backups.createBackup(passphrase: testPassphrase);
      final external = join(tempRoot.path, 'shared.db.enc');
      await File(original.path).copy(external);

      final msg = await exceptionMessage(
        () => backups.importBackupFile(external),
      );
      expect(msg, contains('پاس فریز درکار ہے'));
      expect(await backups.listBackups(), hasLength(1));
    });
  });

  group('interrupted exports leave no partial backups', () {
    test('stray .tmp files are never listed as backups', () async {
      await populateSampleData();
      final info = await backups.createBackup(passphrase: testPassphrase);

      // Simulate a process killed mid-write: temp files left behind
      // under both naming schemes, plus a stray sidecar-less .tmp.
      final backupsDir = Directory(join(tempRoot.path, 'backups'));
      await File(
        join(backupsDir.path, 'kisandost_backup_20990101_000000_v99.db.tmp'),
      ).writeAsBytes([1, 2, 3]);
      await File(
        join(
          backupsDir.path,
          'kisandost_backup_20990101_000000_v99.db.enc.tmp',
        ),
      ).writeAsBytes([4, 5, 6]);
      await File(
        '${info.path}.tmp',
      ).writeAsBytes([7, 8, 9]); // beside a real backup

      final list = await backups.listBackups();
      expect(list.map((b) => b.path), isNot(contains('${info.path}.tmp')));
      expect(
        list.where((b) => b.name.contains('20990101')),
        isEmpty,
      );
      // The real backup is still there and verifiable.
      expect(list.map((b) => b.name), contains(info.name));
      await backups.verifyBackup(info.path, passphrase: testPassphrase);
    });

    test('a completed encrypted backup has no leftover .tmp beside it',
        () async {
      await populateSampleData();
      final info = await backups.createBackup(passphrase: testPassphrase);
      expect(await File('${info.path}.tmp').exists(), isFalse);
    });
  });

  group('listing', () {
    test('lists encrypted and plaintext side by side with flags and hints',
        () async {
      await populateSampleData();
      final enc = await backups.createBackup(
        label: 'خفیہ',
        passphrase: testPassphrase,
        hint: 'یاد رکھو',
      );
      final plain = await backups.createBackup(label: 'سادہ');

      final list = await backups.listBackups();
      expect(list, hasLength(2));
      final encInfo = list.firstWhere((b) => b.name == enc.name);
      final plainInfo = list.firstWhere((b) => b.name == plain.name);
      expect(encInfo.isEncrypted, isTrue);
      expect(encInfo.hint, 'یاد رکھو');
      expect(plainInfo.isEncrypted, isFalse);
      expect(plainInfo.hint, isEmpty);

      // Deleting an encrypted backup removes the .enc and its sidecar.
      await backups.deleteBackup(encInfo);
      expect(await File(encInfo.path).exists(), isFalse);
      expect(await File(encInfo.sidecarPath!).exists(), isFalse);
      expect((await backups.listBackups()).map((b) => b.name), [plain.name]);
    });
  });
}
