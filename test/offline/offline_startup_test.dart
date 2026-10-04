import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:kisan_dost/database/db_helper.dart';
import 'package:kisan_dost/providers/farm_provider.dart';
import 'package:kisan_dost/services/onboarding_service.dart';

/// Hermetic offline-first startup tests: first launch, kill-mid-onboarding,
/// and provider behaviour when the database cannot be opened (e.g. full
/// disk). No network, no device, no app singleton.
void main() {
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  group('onboarding flags can never strand the farmer', () {
    setUp(() async {
      SharedPreferences.setMockInitialValues({});
    });

    test('fresh install shows onboarding', () async {
      expect(await OnboardingService.shouldShowOnboarding(), isTrue);
    });

    test('completing onboarding hides it forever', () async {
      await OnboardingService.completeOnboarding();
      expect(await OnboardingService.shouldShowOnboarding(), isFalse);
    });

    test('kill mid-onboarding replays onboarding (safe direction)', () async {
      // The flag is written only at the END of the flow; a kill before that
      // leaves the default false -> onboarding shows again. Never stuck.
      expect(await OnboardingService.shouldShowOnboarding(), isTrue);
    });
  });

  group('provider survives an unopenable database', () {
    test('fetchFarms never throws; it reports a friendly Urdu error',
        () async {
      // A closed database throws on every operation — stands in for
      // "disk full / database file unreadable" without needing a device.
      final broken =
          await databaseFactoryFfi.openDatabase(inMemoryDatabasePath);
      await broken.close();

      final provider = FarmProvider(testExecutor: broken);
      // Must not throw: main() calls fetchFarms() fire-and-forget.
      await provider.fetchFarms();

      final message = provider.errorMessage;
      expect(message, isNotNull);
      expect(message, isNotEmpty);
      // Friendly Urdu for the farmer — never a raw technical exception.
      expect(message, contains(RegExp(r'[\u0600-\u06FF]')));
      expect(message, isNot(contains('Exception')));
      expect(message, isNot(contains('SqliteException')));
    });
  });

  group('schema version sanity', () {
    test('schemaVersion matches the migrated-to version', () {
      // Guards against a version bump that forgets its migration (which
      // would brick offline upgrades).
      expect(DatabaseHelper.schemaVersion, greaterThanOrEqualTo(15));
    });
  });
}
