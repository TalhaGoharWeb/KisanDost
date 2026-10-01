import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite/sqflite.dart';

import 'package:kisan_dost/database/db_helper.dart';

/// App version stamped into backup sidecars.
///
/// TODO: wire this to the real package version (package_info_plus) when
/// that dependency is added — for now it is a manual constant kept in sync
/// with pubspec.yaml.
const String kAppVersion = '1.0.0';

/// Thrown for every user-facing backup/restore failure. [message] is always
/// in Urdu so it can be shown to the farmer directly.
class BackupException implements Exception {
  final String message;
  const BackupException(this.message);

  @override
  String toString() => 'BackupException: $message';
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

  const BackupInfo({
    required this.name,
    required this.label,
    required this.path,
    this.sidecarPath,
    required this.createdAt,
    required this.sizeBytes,
    this.schemaVersion,
    this.appVersion,
  });

  bool get hasSidecar => sidecarPath != null;
}

/// Creates, lists, verifies and prunes database backups.
///
/// A backup is a straight copy of the live `kisan_dost.db` file plus a
/// JSON sidecar (`<name>.json`) carrying {appVersion, schemaVersion,
/// createdAt, sha256, label}.
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
  /// `kisandost_backup_<yyyyMMdd_HHmmss>_v<userVersion>.db`, appending a
  /// numeric suffix on same-second collisions.
  Future<String> _uniqueBackupPath(
    Directory dir,
    DateTime now,
    int userVersion,
  ) async {
    var name = 'kisandost_backup_${_stamp(now)}_v$userVersion.db';
    var destPath = join(dir.path, name);
    var suffix = 2;
    while (await File(destPath).exists()) {
      name = 'kisandost_backup_${_stamp(now)}_v${userVersion}_$suffix.db';
      destPath = join(dir.path, name);
      suffix++;
    }
    return destPath;
  }

  /// Creates a backup of the live database and returns its [BackupInfo].
  ///
  /// The database is checkpointed, closed, copied, and then re-opened —
  /// the `finally` guarantees the app is never left without a usable DB,
  /// even if the copy fails halfway.
  Future<BackupInfo> createBackup({String? label}) async {
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
    final destPath = await _uniqueBackupPath(dir, now, schemaVersion);

    await helper.close();
    try {
      await File(livePath).copy(destPath);

      final bytes = await File(destPath).readAsBytes();
      final sha = sha256.convert(bytes).toString();
      final sidecarPath = '$destPath.json';
      await File(sidecarPath).writeAsString(
        jsonEncode({
          'appVersion': kAppVersion,
          'schemaVersion': schemaVersion,
          'createdAt': now.toIso8601String(),
          'sha256': sha,
          'label': label ?? '',
        }),
      );

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
      );
    } finally {
      // Never leave the app without a database.
      await helper.database;
    }
  }

  /// Lists backups newest-first. A .db file without its sidecar is still
  /// listed (label 'نامعلوم') rather than hidden.
  Future<List<BackupInfo>> listBackups() async {
    final dir = await _backupsDir();
    if (!await dir.exists()) return [];
    final files =
        await dir
            .list()
            .where((e) => e is File && e.path.endsWith('.db'))
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
        ),
      );
    }
    infos.sort((a, b) => b.createdAt.compareTo(a.createdAt));
    return infos;
  }

  /// Validates a backup file. Throws [BackupException] (Urdu) on any
  /// problem. Never touches the live database — the file is opened
  /// read-only at its own path.
  Future<void> verifyBackup(String path) async {
    final file = File(path);
    if (!await file.exists()) {
      throw const BackupException('بیک اپ فائل نہیں ملی');
    }
    if (await file.length() == 0) {
      throw const BackupException('بیک اپ فائل خالی ہے');
    }

    // SQLite header magic: "SQLite format 3\0" (16 bytes).
    final header = await file
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

      final sidecar = File('$path.json');
      if (await sidecar.exists()) {
        try {
          final data =
              jsonDecode(await sidecar.readAsString()) as Map<String, dynamic>;
          final expected = data['sha256'] as String?;
          if (expected != null && expected.isNotEmpty) {
            final actual = sha256.convert(await file.readAsBytes()).toString();
            if (actual != expected) {
              throw const BackupException(
                'بیک اپ فائل میں تبدیلی پائی گئی ہے — یہ محفوظ نہیں ہے',
              );
            }
          }
        } on BackupException {
          rethrow;
        } catch (_) {
          // Unreadable sidecar: the structural checks above already passed,
          // so treat it like a missing sidecar rather than failing.
        }
      }
    } finally {
      await bk?.close();
    }
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
  /// Never throws — failures are only logged.
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

  /// Copies a user-picked .db file into the backups folder with a proper
  /// backup filename and sidecar, then verifies it. Throws [BackupException]
  /// (Urdu) when the picked file is not a usable backup. A failed import
  /// cleans up its partial copy so garbage never accumulates.
  Future<BackupInfo> importBackupFile(String pickedPath) async {
    // Read the schema version for the filename; a garbage file fails here
    // and again (with a proper Urdu error) in verifyBackup below.
    var userVersion = 0;
    Database? probe;
    try {
      probe = await openDatabase(pickedPath, readOnly: true);
      userVersion =
          Sqflite.firstIntValue(await probe.rawQuery('PRAGMA user_version')) ??
          0;
    } catch (_) {
      userVersion = 0;
    } finally {
      await probe?.close();
    }

    final dir = await _backupsDir();
    await dir.create(recursive: true);
    final now = DateTime.now();
    final destPath = await _uniqueBackupPath(dir, now, userVersion);
    await File(pickedPath).copy(destPath);

    // Keep the picked file's sidecar when it ships one; otherwise write a
    // fresh sidecar (schema version read from the file itself).
    final pickedSidecar = File('$pickedPath.json');
    final sidecarPath = '$destPath.json';
    if (await pickedSidecar.exists()) {
      await pickedSidecar.copy(sidecarPath);
    } else {
      final sha = sha256.convert(await File(destPath).readAsBytes()).toString();
      await File(sidecarPath).writeAsString(
        jsonEncode({
          'appVersion': kAppVersion,
          'schemaVersion': userVersion,
          'createdAt': now.toIso8601String(),
          'sha256': sha,
          'label': 'درآمد شدہ',
        }),
      );
    }

    try {
      await verifyBackup(destPath);
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
    );
  }
}
