import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:encrypt/encrypt.dart' as enc;
import 'package:flutter/foundation.dart';
import 'package:path/path.dart';
import 'package:path_provider/path_provider.dart';
import 'package:pointycastle/digests/sha256.dart';
import 'package:pointycastle/key_derivators/api.dart';
import 'package:pointycastle/key_derivators/pbkdf2.dart';
import 'package:pointycastle/macs/hmac.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite/sqflite.dart';

import 'package:kisan_dost/database/db_helper.dart';

/// App version stamped into backup sidecars.
///
/// TODO: wire this to the real package version (package_info_plus) when
/// that dependency is added — for now it is a manual constant kept in sync
/// with pubspec.yaml.
const String kAppVersion = '1.0.0';

/// PBKDF2-HMAC-SHA256 iterations for backup passphrase key derivation
/// (OWASP 2023 guidance). Slow enough to hurt bulk guessing, fast enough
/// (~1 s on a low-end phone) for an operation done at backup/restore time.
const int kBackupKdfIterations = 210000;

/// Minimum passphrase length enforced when CREATING an encrypted backup.
/// (A 4-char passphrase is still weak — real strength comes from the
/// farmer choosing something memorable — but below 4 is trivially
/// guessable even with the KDF.)
const int kMinPassphraseLength = 4;

// ---------------------------------------------------------------------------
// Encrypted backup file format (".db.enc").
//
// All primitives are vetted — package:encrypt (PointyCastle) for
// AES-256-GCM, PointyCastle's PBKDF2KeyDerivator for the KDF,
// package:crypto's HMAC-SHA256 for the verifier and the outer MAC.
// Nothing here is hand-rolled.
//
// Layout:
//   offset  size  field
//   0       8     magic "KDSTENC1"
//   8       16    salt (CSPRNG, per backup)
//   24      12    GCM nonce (CSPRNG, per backup)
//   36      32    verifier = HMAC-SHA256(macKey, "kisan-dost-backup-verifier"‖salt)
//   68      N     AES-256-GCM ciphertext of the .db bytes
//   68+N    32    HMAC-SHA256(macKey, salt‖nonce‖ciphertext)  (Encrypt-then-MAC)
//
// Key derivation: PBKDF2-HMAC-SHA256(passphrase_utf8, salt, 210_000)
// → 64 bytes = encKey[0..32) ‖ macKey[32..64).
//
// The verifier lets us tell "wrong passphrase" apart from "tampered
// file": verifier mismatch → wrong passphrase; verifier OK but MAC/tag
// failure → tampered file. The verifier is a deliberate, documented
// trade-off (see docs/audit/BACKUP_ENCRYPTION_DESIGN.md §3.3): an
// attacker holding the file can already test guesses offline via the
// GCM tag, so the verifier costs no practical security and buys the
// farmer a clear error message instead of a scary "file is corrupt".
// ---------------------------------------------------------------------------
const List<int> _encMagic = [0x4B, 0x44, 0x53, 0x54, 0x45, 0x4E, 0x43, 0x31];
const int _saltLength = 16;
const int _nonceLength = 12;
const int _verifierLength = 32;
const int _macLength = 32;
const int _headerLength = 8 + _saltLength + _nonceLength + _verifierLength;
const String _verifierLabel = 'kisan-dost-backup-verifier';

/// Thrown for every user-facing backup/restore failure. [message] is always
/// in Urdu so it can be shown to the farmer directly.
class BackupException implements Exception {
  final String message;
  const BackupException(this.message);

  @override
  String toString() => 'BackupException: $message';
}

/// Streams [path] through SHA-256 without loading the whole file into
/// memory (backup DBs can grow large on long-used devices).
/// (Data-layer audit 2026-10-04: replaced readAsBytes hashing.)
Future<String> _sha256OfFile(String path) async {
  final digest = await sha256.bind(File(path).openRead()).first;
  return digest.toString();
}

/// Metadata about one backup file on disk.
class BackupInfo {
  final String name;
  final String label;
  final String path;
  final String? sidecarPath;
  final DateTime createdAt;
  final int sizeBytes;
  final int? schemaVersion;
  final String? appVersion;

  /// True for `.db.enc` backups (passphrase required to open).
  final bool isEncrypted;

  /// The farmer's plaintext reminder for the passphrase ('' when none).
  /// Stored in the sidecar in PLAINTEXT by design — it is only a hint.
  final String hint;

  const BackupInfo({
    required this.name,
    required this.label,
    required this.path,
    this.sidecarPath,
    required this.createdAt,
    required this.sizeBytes,
    this.schemaVersion,
    this.appVersion,
    this.isEncrypted = false,
    this.hint = '',
  });

  bool get hasSidecar => sidecarPath != null;
}

/// The two keys derived from the farmer's passphrase.
class _DerivedKeys {
  final Uint8List encKey; // AES-256 key, 32 bytes.
  final Uint8List macKey; // HMAC-SHA256 key, 32 bytes.
  const _DerivedKeys(this.encKey, this.macKey);
}

_DerivedKeys _deriveKeys(String passphrase, Uint8List salt) {
  final derivator = PBKDF2KeyDerivator(HMac(SHA256Digest(), 64));
  derivator.init(Pbkdf2Parameters(salt, kBackupKdfIterations, 64));
  final out = derivator.process(Uint8List.fromList(utf8.encode(passphrase)));
  return _DerivedKeys(
    Uint8List.fromList(out.sublist(0, 32)),
    Uint8List.fromList(out.sublist(32, 64)),
  );
}

Uint8List _randomBytes(int n) {
  final random = Random.secure();
  return Uint8List.fromList(
    List<int>.generate(n, (_) => random.nextInt(256)),
  );
}

bool _constantTimeEquals(List<int> a, List<int> b) {
  if (a.length != b.length) return false;
  var diff = 0;
  for (var i = 0; i < a.length; i++) {
    diff |= a[i] ^ b[i];
  }
  return diff == 0;
}

/// Encrypts raw database bytes into the ".db.enc" file format.
List<int> _encryptBackupBytes(List<int> plain, String passphrase) {
  final salt = _randomBytes(_saltLength);
  final nonce = _randomBytes(_nonceLength);
  final keys = _deriveKeys(passphrase, salt);

  final encrypter = enc.Encrypter(enc.AES(enc.Key(keys.encKey), mode: enc.AESMode.gcm));
  final ciphertext = encrypter.encryptBytes(plain, iv: enc.IV(nonce)).bytes;

  final verifier =
      Hmac(
        sha256,
        keys.macKey,
      ).convert([...utf8.encode(_verifierLabel), ...salt]).bytes;
  final mac =
      Hmac(
        sha256,
        keys.macKey,
      ).convert([...salt, ...nonce, ...ciphertext]).bytes;

  return [..._encMagic, ...salt, ...nonce, ...verifier, ...ciphertext, ...mac];
}

/// Decrypts ".db.enc" file bytes back to raw database bytes.
///
/// Throws [BackupException] with a wrong-passphrase message when the
/// verifier does not match, and with a tampered-file message when the
/// header, MAC or GCM tag is invalid.
List<int> _decryptBackupBytes(List<int> fileBytes, String passphrase) {
  BackupException tampered() => const BackupException(
    'بیک اپ فائل میں تبدیلی پائی گئی ہے — یہ محفوظ نہیں ہے',
  );
  // Header + MAC + at least one ciphertext byte.
  if (fileBytes.length < _headerLength + _macLength + 1) throw tampered();
  for (var i = 0; i < _encMagic.length; i++) {
    if (fileBytes[i] != _encMagic[i]) throw tampered();
  }

  final salt = Uint8List.fromList(fileBytes.sublist(8, 8 + _saltLength));
  final nonce = Uint8List.fromList(
    fileBytes.sublist(8 + _saltLength, 8 + _saltLength + _nonceLength),
  );
  final verifier = fileBytes.sublist(
    8 + _saltLength + _nonceLength,
    _headerLength,
  );
  final mac = fileBytes.sublist(fileBytes.length - _macLength);
  final ciphertext = fileBytes.sublist(
    _headerLength,
    fileBytes.length - _macLength,
  );

  final keys = _deriveKeys(passphrase, salt);

  // Verifier FIRST: wrong passphrase vs tampered file (see §3.3 of the
  // design doc).
  final expectedVerifier =
      Hmac(
        sha256,
        keys.macKey,
      ).convert([...utf8.encode(_verifierLabel), ...salt]).bytes;
  if (!_constantTimeEquals(verifier, expectedVerifier)) {
    throw const BackupException('پاس فریز غلط ہے — دوبارہ کوشش کریں');
  }

  final expectedMac =
      Hmac(
        sha256,
        keys.macKey,
      ).convert([...salt, ...nonce, ...ciphertext]).bytes;
  if (!_constantTimeEquals(mac, expectedMac)) throw tampered();

  try {
    final encrypter = enc.Encrypter(enc.AES(enc.Key(keys.encKey), mode: enc.AESMode.gcm));
    return encrypter.decryptBytes(
      enc.Encrypted(Uint8List.fromList(ciphertext)),
      iv: enc.IV(nonce),
    );
  } catch (_) {
    // GCM tag failure after a valid outer MAC: treat as tampering.
    throw tampered();
  }
}

/// Creates, lists, verifies and prunes database backups.
///
/// A backup is a straight copy of the live `kisan_dost.db` file plus a
/// JSON sidecar (`<name>.json`) carrying {appVersion, schemaVersion,
/// createdAt, sha256, label}.
///
/// An ENCRYPTED backup (passphrase given) is instead a `.db.enc` file in
/// the format documented above, with a sidecar that additionally carries
/// {encrypted: true, hint, kdf, kdfIterations}. The passphrase is never
/// stored anywhere.
///
/// WAL handling: [createBackup] runs a `wal_checkpoint(TRUNCATE)` and then
/// closes the database before copying, so the main .db file is
/// self-contained — only it is copied, never -wal/-shm. On restore the
/// live -wal/-shm files are deleted first so no stale WAL frames from a
/// different database image can shadow the restored file.
class BackupService {
  static const String autoBackupEnabledKey = 'auto_backup_enabled';
  static const String lastAutoBackupDateKey = 'last_auto_backup_date';

  final Directory? _backupsDirOverride;
  final String? _liveDbPathOverride;

  /// [backupsDir] / [liveDbPath] are injectable so tests can point at temp
  /// directories. Production defaults: `<appDocuments>/backups` and the
  /// live path from [DatabaseHelper].
  BackupService({Directory? backupsDir, String? liveDbPath})
    : _backupsDirOverride = backupsDir,
      _liveDbPathOverride = liveDbPath;

  Future<Directory> _backupsDir() async {
    final override = _backupsDirOverride;
    if (override != null) return override;
    final docs = await getApplicationDocumentsDirectory();
    return Directory(join(docs.path, 'backups'));
  }

  Future<String> _liveDbPath() async {
    final override = _liveDbPathOverride;
    if (override != null) return override;
    return DatabaseHelper.instance.databaseFilePath;
  }

  String _stamp(DateTime t) {
    String two(int n) => n.toString().padLeft(2, '0');
    return '${t.year}${two(t.month)}${two(t.day)}_'
        '${two(t.hour)}${two(t.minute)}${two(t.second)}';
  }

  /// Generates a unique backup filename in the spec format
  /// `kisandost_backup_<yyyyMMdd_HHmmss>_v<userVersion>.db` (plaintext) or
  /// `..._v<userVersion>.db.enc` (encrypted), appending a numeric suffix
  /// on same-second collisions.
  Future<String> _uniqueBackupPath(
    Directory dir,
    DateTime now,
    int userVersion, {
    bool encrypted = false,
  }) async {
    final ext = encrypted ? '.db.enc' : '.db';
    var name = 'kisandost_backup_${_stamp(now)}_v$userVersion$ext';
    var destPath = join(dir.path, name);
    var suffix = 2;
    while (await File(destPath).exists()) {
      name = 'kisandost_backup_${_stamp(now)}_v${userVersion}_$suffix$ext';
      destPath = join(dir.path, name);
      suffix++;
    }
    return destPath;
  }

  /// Copies [src] to [dest] atomically: the bytes land in a `.tmp` file
  /// first and are renamed into place, so an interrupted export can never
  /// leave a partial file behind under the final name.
  Future<void> _copyAtomically(String src, String dest) async {
    final tmp = '$dest.tmp';
    try {
      await File(src).copy(tmp);
      await File(tmp).rename(dest);
    } catch (_) {
      final t = File(tmp);
      if (await t.exists()) await t.delete();
      rethrow;
    }
  }

  /// True when [path] is an encrypted backup: by `.db.enc` extension, or
  /// by an `encrypted: true` flag in its sidecar.
  Future<bool> isEncryptedBackup(String path) async {
    if (path.endsWith('.db.enc')) return true;
    final sidecar = File('$path.json');
    if (await sidecar.exists()) {
      try {
        final data =
            jsonDecode(await sidecar.readAsString()) as Map<String, dynamic>;
        if (data['encrypted'] == true) return true;
      } catch (_) {
        // Unreadable sidecar: not our call to make.
      }
    }
    return false;
  }

  /// Decrypts an encrypted backup into a temp `.db` file in the system
  /// temp directory and returns its path. The CALLER must delete the file
  /// when done (it holds plaintext database bytes).
  ///
  /// Throws [BackupException]: wrong-passphrase message when the
  /// passphrase does not match, tampered-file message when the file was
  /// modified. Never returns keys — only a temp file path.
  Future<String> decryptBackupToTemp(String path, String passphrase) async {
    final bytes = await File(path).readAsBytes();
    final plain = _decryptBackupBytes(bytes, passphrase);
    final tmpPath = join(
      Directory.systemTemp.path,
      'kisan_dost_decrypt_${DateTime.now().microsecondsSinceEpoch}_'
          '${Random().nextInt(1 << 32)}.db',
    );
    await File(tmpPath).writeAsBytes(plain, flush: true);
    return tmpPath;
  }

  /// Creates a backup of the live database and returns its [BackupInfo].
  ///
  /// Pass [passphrase] for an encrypted backup (`.db.enc`); omit it for
  /// the classic plaintext copy. [hint] is stored in PLAINTEXT in the
  /// sidecar and is only meaningful for encrypted backups.
  ///
  /// The database is checkpointed, closed, copied, and then re-opened —
  /// the `finally` guarantees the app is never left without a usable DB,
  /// even if the copy fails halfway. The backup file itself is written
  /// via temp + atomic rename, so an interrupted export leaves no partial
  /// file behind.
  Future<BackupInfo> createBackup({
    String? label,
    String? passphrase,
    String? hint,
  }) async {
    final encrypted = passphrase != null && passphrase.isNotEmpty;
    if (encrypted && passphrase.length < kMinPassphraseLength) {
      throw const BackupException(
        'پاس فریز کم از کم $kMinPassphraseLength حروف کا ہونا چاہیے',
      );
    }

    final helper = DatabaseHelper.instance;

    // Read user_version while the DB is still open.
    final db = await helper.database;
    final int schemaVersion =
        Sqflite.firstIntValue(await db.rawQuery('PRAGMA user_version')) ?? 0;
    await helper.checkpoint();

    final livePath = await _liveDbPath();
    final dir = await _backupsDir();
    await dir.create(recursive: true);

    final now = DateTime.now();
    final destPath = await _uniqueBackupPath(
      dir,
      now,
      schemaVersion,
      encrypted: encrypted,
    );

    await helper.close();
    try {
      if (encrypted) {
        // The live DB is closed here, so reading it directly is
        // equivalent to copying it first; DB files are small (a few MB).
        final plain = await File(livePath).readAsBytes();
        final encBytes = _encryptBackupBytes(plain, passphrase);
        final tmpPath = '$destPath.tmp';
        try {
          await File(tmpPath).writeAsBytes(encBytes, flush: true);
          await File(tmpPath).rename(destPath);
        } catch (_) {
          final t = File(tmpPath);
          if (await t.exists()) await t.delete();
          rethrow;
        }
      } else {
        await _copyAtomically(livePath, destPath);
      }

      final sha = await _sha256OfFile(destPath);
      final sidecarPath = '$destPath.json';
      final sidecar = <String, dynamic>{
        'appVersion': kAppVersion,
        'schemaVersion': schemaVersion,
        'createdAt': now.toIso8601String(),
        'sha256': sha,
        'label': label ?? '',
      };
      if (encrypted) {
        sidecar['encrypted'] = true;
        // Plaintext BY DESIGN — it is only a hint, never the passphrase.
        sidecar['hint'] = hint ?? '';
        sidecar['kdf'] = 'pbkdf2-hmac-sha256';
        sidecar['kdfIterations'] = kBackupKdfIterations;
      }
      await File(sidecarPath).writeAsString(jsonEncode(sidecar));

      final size = await File(destPath).length();
      return BackupInfo(
        name: basename(destPath),
        label: (label == null || label.isEmpty) ? 'نامعلوم' : label,
        path: destPath,
        sidecarPath: sidecarPath,
        createdAt: now,
        sizeBytes: size,
        schemaVersion: schemaVersion,
        appVersion: kAppVersion,
        isEncrypted: encrypted,
        hint: encrypted ? (hint ?? '') : '',
      );
    } finally {
      // Never leave the app without a database.
      await helper.database;
    }
  }

  /// Lists backups newest-first. A .db/.db.enc file without its sidecar
  /// is still listed (label 'نامعلوم') rather than hidden. Temp files
  /// (`*.tmp`) from interrupted exports are never listed.
  Future<List<BackupInfo>> listBackups() async {
    final dir = await _backupsDir();
    if (!await dir.exists()) return [];
    final files =
        await dir
            .list()
            .where(
              (e) =>
                  e is File &&
                  (e.path.endsWith('.db') || e.path.endsWith('.db.enc')),
            )
            .cast<File>()
            .toList();

    final infos = <BackupInfo>[];
    for (final file in files) {
      final stat = await file.stat();
      String label = 'نامعلوم';
      DateTime createdAt = stat.modified;
      int? schemaVersion;
      String? appVersion;
      String? sidecarPath;
      var isEncrypted = file.path.endsWith('.db.enc');
      var hint = '';
      final sidecar = File('${file.path}.json');
      if (await sidecar.exists()) {
        sidecarPath = sidecar.path;
        try {
          final data =
              jsonDecode(await sidecar.readAsString()) as Map<String, dynamic>;
          final rawLabel = data['label'] as String?;
          if (rawLabel != null && rawLabel.isNotEmpty) label = rawLabel;
          final rawCreated = data['createdAt'] as String?;
          if (rawCreated != null) {
            createdAt = DateTime.tryParse(rawCreated) ?? createdAt;
          }
          schemaVersion = data['schemaVersion'] as int?;
          appVersion = data['appVersion'] as String?;
          if (data['encrypted'] == true) isEncrypted = true;
          final rawHint = data['hint'] as String?;
          if (rawHint != null) hint = rawHint;
        } catch (_) {
          // Corrupt sidecar: still list the backup from file stats.
        }
      }
      infos.add(
        BackupInfo(
          name: basename(file.path),
          label: label,
          path: file.path,
          sidecarPath: sidecarPath,
          createdAt: createdAt,
          sizeBytes: stat.size,
          schemaVersion: schemaVersion,
          appVersion: appVersion,
          isEncrypted: isEncrypted,
          hint: hint,
        ),
      );
    }
    infos.sort((a, b) => b.createdAt.compareTo(a.createdAt));
    return infos;
  }

  /// Structural checks for a PLAINTEXT database file: SQLite magic,
  /// integrity_check, required tables, and schema version ceiling.
  Future<void> _verifyPlainDb(String path) async {
    // SQLite header magic: "SQLite format 3\0" (16 bytes).
    final header = await File(path)
        .openRead(0, 16)
        .fold<List<int>>(<int>[], (a, b) => a..addAll(b));
    final magicBytes = utf8.encode('SQLite format 3\x00');
    var magicOk = header.length == magicBytes.length;
    if (magicOk) {
      for (var i = 0; i < magicBytes.length; i++) {
        if (header[i] != magicBytes[i]) {
          magicOk = false;
          break;
        }
      }
    }
    if (!magicOk) {
      throw const BackupException('یہ درست ڈیٹا بیس فائل نہیں ہے');
    }

    Database? bk;
    try {
      bk = await openDatabase(path, readOnly: true);

      final integrity = await bk.rawQuery('PRAGMA integrity_check');
      final integrityOk =
          integrity.length == 1 &&
          integrity.first.values.first.toString() == 'ok';
      if (!integrityOk) {
        throw const BackupException(
          'بیک اپ فائل خراب ہے — اس کی جانچ ناکام ہو گئی',
        );
      }

      final tables =
          (await bk.rawQuery(
            "SELECT name FROM sqlite_master WHERE type = 'table'",
          )).map((r) => r['name'].toString()).toSet();
      for (final t in [
        'farms',
        'expenses',
        'inventory',
        'inventory_transactions',
      ]) {
        if (!tables.contains(t)) {
          throw BackupException('بیک اپ میں ضروری جدول "$t" موجود نہیں ہے');
        }
      }

      final userVersion =
          Sqflite.firstIntValue(await bk.rawQuery('PRAGMA user_version')) ?? 0;
      if (userVersion > DatabaseHelper.schemaVersion) {
        throw const BackupException(
          'اس بیک اپ کو ایپ کا نیا ورژن درکار ہے — پہلے ایپ اپ ڈیٹ کریں',
        );
      }
    } finally {
      await bk?.close();
    }
  }

  /// Compares the file's SHA-256 against the sidecar record when one
  /// exists. A mismatch means the file changed after the backup was made.
  Future<void> _verifySidecarSha256(String path) async {
    final sidecar = File('$path.json');
    if (await sidecar.exists()) {
      try {
        final data =
            jsonDecode(await sidecar.readAsString()) as Map<String, dynamic>;
        final expected = data['sha256'] as String?;
        if (expected != null && expected.isNotEmpty) {
          final actual = await _sha256OfFile(path);
          if (actual != expected) {
            throw const BackupException(
              'بیک اپ فائل میں تبدیلی پائی گئی ہے — یہ محفوظ نہیں ہے',
            );
          }
        }
      } on BackupException {
        rethrow;
      } catch (_) {
        // Unreadable sidecar: the structural checks already passed, so
        // treat it like a missing sidecar rather than failing.
      }
    }
  }

  /// Validates a backup file. Throws [BackupException] (Urdu) on any
  /// problem. Never touches the live database — the file is opened
  /// read-only at its own path.
  ///
  /// For encrypted backups the [passphrase] is required: without it this
  /// throws a "passphrase required" error instead of failing cryptically
  /// on the ciphertext header. A wrong passphrase and a tampered file
  /// produce different, clear Urdu errors.
  Future<void> verifyBackup(String path, {String? passphrase}) async {
    final file = File(path);
    if (!await file.exists()) {
      throw const BackupException('بیک اپ فائل نہیں ملی');
    }
    if (await file.length() == 0) {
      throw const BackupException('بیک اپ فائل خالی ہے');
    }

    if (await isEncryptedBackup(path)) {
      if (passphrase == null || passphrase.isEmpty) {
        throw const BackupException(
          'یہ خفیہ بیک اپ ہے — اسے کھولنے کے لیے پاس فریز درکار ہے',
        );
      }
      String? tmp;
      try {
        // Throws the wrong-passphrase / tampered-file errors.
        tmp = await decryptBackupToTemp(path, passphrase);
        await _verifyPlainDb(tmp);
        await _verifySidecarSha256(path);
      } finally {
        if (tmp != null) {
          final t = File(tmp);
          if (await t.exists()) await t.delete();
        }
      }
      return;
    }

    await _verifyPlainDb(path);
    await _verifySidecarSha256(path);
  }

  /// Deletes a backup and its sidecar.
  Future<void> deleteBackup(BackupInfo info) async {
    final dbFile = File(info.path);
    if (await dbFile.exists()) await dbFile.delete();
    final sidecarPath = info.sidecarPath;
    if (sidecarPath != null) {
      final sidecar = File(sidecarPath);
      if (await sidecar.exists()) await sidecar.delete();
    }
  }

  /// Keeps the [keep] newest backups, deletes the rest (oldest first).
  Future<void> pruneBackups({int keep = 10}) async {
    final backups = await listBackups();
    if (backups.length <= keep) return;
    for (final old in backups.sublist(keep)) {
      await deleteBackup(old);
    }
  }

  Future<bool> get autoBackupEnabled async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(autoBackupEnabledKey) ?? true;
  }

  Future<void> setAutoBackupEnabled(bool enabled) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(autoBackupEnabledKey, enabled);
  }

  /// Creates one automatic backup per day (label 'خودکار') when enabled.
  /// Automatic backups are always PLAINTEXT: they run unattended with no
  /// farmer present to type a passphrase. Farmers who want encryption
  /// make manual encrypted backups. Never throws — failures are only
  /// logged.
  Future<void> maybeAutoBackup() async {
    try {
      if (!await autoBackupEnabled) return;
      final prefs = await SharedPreferences.getInstance();
      final now = DateTime.now();
      final today =
          '${now.year.toString().padLeft(4, '0')}-'
          '${now.month.toString().padLeft(2, '0')}-'
          '${now.day.toString().padLeft(2, '0')}';
      if (prefs.getString(lastAutoBackupDateKey) == today) return;
      await createBackup(label: 'خودکار');
      await pruneBackups();
      await prefs.setString(lastAutoBackupDateKey, today);
    } catch (e) {
      debugPrint('خودکار بیک اپ ناکام: $e');
    }
  }

  /// Copies a user-picked .db / .db.enc file into the backups folder with
  /// a proper backup filename and sidecar, then verifies it. Throws
  /// [BackupException] (Urdu) when the picked file is not a usable
  /// backup. A failed import cleans up its partial copy so garbage never
  /// accumulates. Encrypted picks require [passphrase] up front.
  Future<BackupInfo> importBackupFile(
    String pickedPath, {
    String? passphrase,
  }) async {
    final pickedEncrypted = await isEncryptedBackup(pickedPath);
    // The picked file itself is encrypted (or claims to be in its
    // sidecar) — a bare ".enc" suffix on a renamed file also counts.
    final encrypted = pickedEncrypted || pickedPath.endsWith('.enc');
    if (encrypted && (passphrase == null || passphrase.isEmpty)) {
      throw const BackupException(
        'یہ خفیہ بیک اپ ہے — اسے درآمد کرنے کے لیے پاس فریز درکار ہے',
      );
    }

    // For encrypted picks the passphrase is validated (and the crypto
    // layer checked) BEFORE anything is copied: a wrong passphrase or a
    // tampered file throws here, so no partial import ever starts.
    String? probeTmp;
    if (encrypted) {
      probeTmp = await decryptBackupToTemp(pickedPath, passphrase!);
    }

    // Read the schema version for the filename; a garbage file fails here
    // and again (with a proper Urdu error) in verifyBackup below.
    var userVersion = 0;
    Database? probe;
    try {
      probe = await openDatabase(
        encrypted ? probeTmp! : pickedPath,
        readOnly: true,
      );
      userVersion =
          Sqflite.firstIntValue(await probe.rawQuery('PRAGMA user_version')) ??
          0;
    } catch (_) {
      userVersion = 0;
    } finally {
      await probe?.close();
      if (probeTmp != null) {
        final t = File(probeTmp);
        if (await t.exists()) await t.delete();
      }
    }

    final dir = await _backupsDir();
    await dir.create(recursive: true);
    final now = DateTime.now();
    final destPath = await _uniqueBackupPath(
      dir,
      now,
      userVersion,
      encrypted: encrypted,
    );
    await File(pickedPath).copy(destPath);

    // Keep the picked file's sidecar when it ships one; otherwise write a
    // fresh sidecar (schema version read from the file itself).
    final pickedSidecar = File('$pickedPath.json');
    final sidecarPath = '$destPath.json';
    String hint = '';
    if (await pickedSidecar.exists()) {
      await pickedSidecar.copy(sidecarPath);
      try {
        final data =
            jsonDecode(await File(sidecarPath).readAsString())
                as Map<String, dynamic>;
        hint = (data['hint'] as String?) ?? '';
      } catch (_) {}
    } else {
      final sha = await _sha256OfFile(destPath);
      final sidecar = <String, dynamic>{
        'appVersion': kAppVersion,
        'schemaVersion': userVersion,
        'createdAt': now.toIso8601String(),
        'sha256': sha,
        'label': 'درآمد شدہ',
      };
      if (encrypted) {
        sidecar['encrypted'] = true;
        sidecar['hint'] = '';
        sidecar['kdf'] = 'pbkdf2-hmac-sha256';
        sidecar['kdfIterations'] = kBackupKdfIterations;
      }
      await File(sidecarPath).writeAsString(jsonEncode(sidecar));
    }

    try {
      await verifyBackup(destPath, passphrase: encrypted ? passphrase : null);
    } catch (_) {
      // Don't leave a broken copy behind.
      final junk = File(destPath);
      if (await junk.exists()) await junk.delete();
      final junkSidecar = File(sidecarPath);
      if (await junkSidecar.exists()) await junkSidecar.delete();
      rethrow;
    }

    final size = await File(destPath).length();
    return BackupInfo(
      name: basename(destPath),
      label: 'درآمد شدہ',
      path: destPath,
      sidecarPath: sidecarPath,
      createdAt: now,
      sizeBytes: size,
      schemaVersion: userVersion,
      appVersion: kAppVersion,
      isEncrypted: encrypted,
      hint: hint,
    );
  }
}
