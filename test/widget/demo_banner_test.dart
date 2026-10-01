import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:kisan_dost/services/demo_data_service.dart';
import 'package:kisan_dost/widgets/demo_banner.dart';

/// Phase 14: the dashboard demo banner shows only while demo mode is
/// active, labels the data honestly, and exits through the confirm dialog.
class _FakeDemo extends DemoDataService {
  _FakeDemo({required bool active}) : _active = active;

  bool _active;
  bool exited = false;

  @override
  bool get isActive => _active;

  @override
  Future<DemoExitResult> exitDemo() async {
    exited = true;
    _active = false;
    notifyListeners();
    return const DemoExitResult.ok();
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  Future<void> pumpBanner(WidgetTester tester, _FakeDemo demo) {
    return tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ChangeNotifierProvider<DemoDataService>.value(
            value: demo,
            child: const DemoBanner(),
          ),
        ),
      ),
    );
  }

  testWidgets('hidden when demo mode is off', (tester) async {
    await pumpBanner(tester, _FakeDemo(active: false));
    expect(find.text('ڈیمو ڈیٹا — یہ اصل ڈیٹا نہیں ہے'), findsNothing);
  });

  testWidgets('visible while demo mode is active', (tester) async {
    await pumpBanner(tester, _FakeDemo(active: true));
    expect(find.text('ڈیمو ڈیٹا — یہ اصل ڈیٹا نہیں ہے'), findsOneWidget);
    expect(find.text('ڈیمو ختم کریں'), findsOneWidget);
  });

  testWidgets('info dialog carries the honest backup note', (tester) async {
    await pumpBanner(tester, _FakeDemo(active: true));
    await tester.tap(find.byTooltip('معلومات'));
    await tester.pumpAndSettle();
    expect(
      find.textContaining(
        'ڈیمو کے دوران بنایا گیا بیک اپ ڈیمو ڈیٹا پر مشتمل ہوگا',
      ),
      findsOneWidget,
    );
  });

  testWidgets('exit button confirms, exits, and hides the banner', (
    tester,
  ) async {
    final demo = _FakeDemo(active: true);
    await pumpBanner(tester, demo);

    await tester.tap(find.text('ڈیمو ختم کریں'));
    await tester.pumpAndSettle();
    expect(find.text('ڈیمو ختم کریں؟'), findsOneWidget);

    await tester.tap(find.text('ختم کریں'));
    await tester.pumpAndSettle();

    expect(demo.exited, isTrue);
    expect(find.text('ڈیمو ڈیٹا — یہ اصل ڈیٹا نہیں ہے'), findsNothing);
    expect(find.text('ڈیمو ڈیٹا حذف کر دیا گیا'), findsOneWidget);
  });

  testWidgets('exit can be cancelled from the confirm dialog', (tester) async {
    final demo = _FakeDemo(active: true);
    await pumpBanner(tester, demo);

    await tester.tap(find.text('ڈیمو ختم کریں'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('منسوخ کریں'));
    await tester.pumpAndSettle();

    expect(demo.exited, isFalse);
    expect(find.text('ڈیمو ڈیٹا — یہ اصل ڈیٹا نہیں ہے'), findsOneWidget);
  });
}
