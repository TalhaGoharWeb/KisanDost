import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Regression tests for Android manifest hardening (audits 2026-10-04).
/// These read the REAL android/app/src/main/AndroidManifest.xml so the
/// security attributes can never silently regress. Parsing is done with
/// plain string matching (no extra dependencies) — the manifest is
/// machine-generated XML with stable formatting.
///
/// Covered fixes:
/// * allowBackup=false — the farmer's plaintext financial DB must never be
///   auto-uploaded to Google Drive (DB_ANDROID_HARDENING F1);
/// * usesCleartextTraffic=false + network_security_config — the app is fully
///   offline; no cleartext downgrade ever (DB_ANDROID_HARDENING);
/// * MainActivity must NOT show over the lock screen — tapping the
///   status-bar alarm icon on a locked phone must not open the full
///   financial app (native Android audit F1, HIGH).
void main() {
  late String manifest;
  late String applicationTag;
  late String mainActivityTag;

  String tagBlock(String xml, String openTag) {
    final start = xml.indexOf(openTag);
    expect(start, isNot(-1), reason: '$openTag not found in manifest');
    final end = xml.indexOf('>', start);
    return xml.substring(start, end);
  }

  setUpAll(() {
    final file = File('android/app/src/main/AndroidManifest.xml');
    expect(file.existsSync(), isTrue,
        reason: 'run from the kisan-dost repo root');
    manifest = file.readAsStringSync();
    applicationTag = tagBlock(manifest, '<application');
    mainActivityTag = tagBlock(manifest, '<activity\n            android:name=".MainActivity"');
  });

  group('backup + network hardening', () {
    test('allowBackup is false (no cloud upload of the financial DB)', () {
      expect(
        applicationTag.contains('android:allowBackup="false"'),
        isTrue,
        reason:
            'Android Auto Backup would silently upload the plaintext SQLite DB',
      );
    });

    test('cleartext traffic is disabled', () {
      expect(
        applicationTag.contains('android:usesCleartextTraffic="false"'),
        isTrue,
      );
    });

    test('a network security config is wired up and denies cleartext', () {
      expect(
        applicationTag.contains(
            'android:networkSecurityConfig="@xml/network_security_config"'),
        isTrue,
      );
      final configFile = File(
        'android/app/src/main/res/xml/network_security_config.xml',
      );
      expect(configFile.existsSync(), isTrue);
      final config = configFile.readAsStringSync();
      expect(config.contains('cleartextTrafficPermitted="false"'), isTrue);
    });
  });

  group('lock-screen bypass (native audit F1)', () {
    test('MainActivity does not show over the lock screen', () {
      expect(
        mainActivityTag.contains('android:showWhenLocked="true"'),
        isFalse,
        reason:
            'showWhenLocked on MainActivity let a locked phone open the full app',
      );
      expect(
        mainActivityTag.contains('android:turnScreenOn="true"'),
        isFalse,
        reason:
            'turnScreenOn on MainActivity is part of the lock-screen bypass',
      );
    });

    test('alarm UI components are not exported', () {
      for (final name in ['.AlarmActivity', '.AlarmService', '.AlarmReceiver']) {
        final idx = manifest.indexOf('android:name="$name"');
        expect(idx, isNot(-1), reason: '$name declaration not found');
        // The exported attribute sits within the same component tag.
        final snippet = manifest.substring(idx, idx + 300);
        expect(
          snippet.contains('android:exported="false"'),
          isTrue,
          reason: '$name must not be reachable by other apps',
        );
      }
    });
  });

  group('release safety', () {
    test('application is not debuggable', () {
      expect(
        applicationTag.contains('android:debuggable="true"'),
        isFalse,
      );
    });

    test('no INTERNET permission in the release manifest', () {
      expect(
        manifest.contains('android.permission.INTERNET'),
        isFalse,
        reason: 'the app is fully offline; INTERNET belongs only in debug',
      );
    });
  });
}
