import 'package:shared_preferences/shared_preferences.dart';

/// First-run onboarding state. The flag is set once the farmer finishes
/// onboarding through EITHER path ("شروع کریں" or "ڈیمو دیکھیں"), so the
/// flow never shows again.
class OnboardingService {
  static const String onboardingDoneKey = 'onboarding_done';

  /// True when onboarding has never been completed (fresh install).
  /// Fails OPEN to true: if the flag can't be read, replaying onboarding
  /// is always the safe direction (never lock a farmer out of first-run).
  static Future<bool> shouldShowOnboarding() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return !(prefs.getBool(onboardingDoneKey) ?? false);
    } catch (_) {
      return true;
    }
  }

  /// Marks onboarding complete. Called by both the fresh-start and the
  /// demo path.
  static Future<void> completeOnboarding() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(onboardingDoneKey, true);
  }
}
