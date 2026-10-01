import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:kisan_dost/screens/onboarding_screen.dart';
import 'package:kisan_dost/services/demo_data_service.dart';
import 'package:kisan_dost/services/onboarding_service.dart';

/// Phase 14: first-run onboarding through the [OnboardingScreen] widget.
/// The screen never touches the real database here — demo insertion is
/// behind a fake [DemoDataService].
class _FakeDemo extends DemoDataService {
  _FakeDemo({this.dataExists = false});

  final bool dataExists;
  bool entered = false;

  @override
  Future<bool> hasRealData() async => dataExists;

  @override
  Future<void> enterDemoFromContext(BuildContext context) async {
    entered = true;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  Future<void> pumpScreen(
    WidgetTester tester,
    _FakeDemo demo,
    VoidCallback onDone,
  ) {
    return tester.pumpWidget(
      MaterialApp(
        home: ChangeNotifierProvider<DemoDataService>.value(
          value: demo,
          child: OnboardingScreen(onCompleted: () async => onDone()),
        ),
      ),
    );
  }

  /// Pumps a few frames without requiring all animations to settle: page 3
  /// shows an indeterminate CircularProgressIndicator while _finish runs,
  /// which pumpAndSettle would wait on forever.
  Future<void> pumpBusy(WidgetTester tester) async {
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));
    await tester.pump();
  }

  /// Taps "آگے بڑھیں" twice to reach the choice page.
  Future<void> goToChoicePage(WidgetTester tester) async {
    await tester.tap(find.text('آگے بڑھیں'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('آگے بڑھیں'));
    await tester.pumpAndSettle();
    expect(find.text('شروع کریں'), findsOneWidget);
    expect(find.text('ڈیمو دیکھیں'), findsOneWidget);
  }

  group('OnboardingService flag', () {
    test(
      'shows onboarding on first run, never again after completion',
      () async {
        expect(await OnboardingService.shouldShowOnboarding(), isTrue);
        await OnboardingService.completeOnboarding();
        expect(await OnboardingService.shouldShowOnboarding(), isFalse);
      },
    );
  });

  group('OnboardingScreen', () {
    testWidgets('skip button completes onboarding without demo', (
      tester,
    ) async {
      final demo = _FakeDemo();
      var done = false;
      await pumpScreen(tester, demo, () => done = true);

      await tester.tap(find.text('چھوڑیں'));
      await tester.pumpAndSettle();

      expect(done, isTrue);
      expect(demo.entered, isFalse);
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getBool(OnboardingService.onboardingDoneKey), isTrue);
    });

    testWidgets('fresh start completes onboarding without demo', (
      tester,
    ) async {
      final demo = _FakeDemo();
      var done = false;
      await pumpScreen(tester, demo, () => done = true);
      await goToChoicePage(tester);

      await tester.tap(find.text('شروع کریں'));
      await pumpBusy(tester);

      expect(done, isTrue);
      expect(demo.entered, isFalse);
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getBool(OnboardingService.onboardingDoneKey), isTrue);
    });

    testWidgets('demo with no existing data inserts demo rows directly', (
      tester,
    ) async {
      final demo = _FakeDemo(dataExists: false);
      var done = false;
      await pumpScreen(tester, demo, () => done = true);
      await goToChoicePage(tester);

      await tester.tap(find.text('ڈیمو دیکھیں'));
      await pumpBusy(tester);

      expect(find.text('آپ کا اپنا ڈیٹا موجود ہے'), findsNothing);
      expect(demo.entered, isTrue);
      expect(done, isTrue);
    });

    testWidgets('demo with existing data warns first, then proceeds', (
      tester,
    ) async {
      final demo = _FakeDemo(dataExists: true);
      var done = false;
      await pumpScreen(tester, demo, () => done = true);
      await goToChoicePage(tester);

      await tester.tap(find.text('ڈیمو دیکھیں'));
      await pumpBusy(tester);

      // Warning dialog appears; demo not yet inserted.
      expect(find.text('آپ کا اپنا ڈیٹا موجود ہے'), findsOneWidget);
      expect(demo.entered, isFalse);
      expect(done, isFalse);

      await tester.tap(find.text('ڈیمو شروع کریں'));
      await pumpBusy(tester);

      expect(demo.entered, isTrue);
      expect(done, isTrue);
    });

    testWidgets('demo warning dialog can be cancelled', (tester) async {
      final demo = _FakeDemo(dataExists: true);
      var done = false;
      await pumpScreen(tester, demo, () => done = true);
      await goToChoicePage(tester);

      await tester.tap(find.text('ڈیمو دیکھیں'));
      await pumpBusy(tester);
      await tester.tap(find.text('منسوخ کریں'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));

      expect(demo.entered, isFalse);
      expect(done, isFalse);
      // Still on the choice page.
      expect(find.text('ڈیمو دیکھیں'), findsOneWidget);
    });
  });
}
