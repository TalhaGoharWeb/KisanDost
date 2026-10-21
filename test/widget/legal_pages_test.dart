import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:kisan_dost/screens/about_us_screen.dart';

/// The legal pages (privacy policy, terms, disclaimer) live on the
/// About screen. These tests pin that all three are reachable and
/// render their real content — a legal page that silently disappears
/// from navigation is a compliance bug, not a UI nit.
void main() {
  Widget app() => const MaterialApp(home: AboutUsScreen());

  Future<void> openLegalPage(
    WidgetTester tester,
    String tileTitle,
    String expectedHeading,
  ) async {
    await tester.pumpWidget(app());
    await tester.pump();

    final tile = find.text(tileTitle);
    await tester.scrollUntilVisible(tile, 300);
    await tester.pump();
    await tester.tap(tile);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    expect(find.text(expectedHeading), findsOneWidget);
  }

  testWidgets('privacy policy opens from the About screen', (tester) async {
    await openLegalPage(tester, 'رازداری کی پالیسی', 'ہمارا سادہ وعدہ');
    // The core promise must be on the page, verbatim in spirit.
    expect(find.textContaining('صرف آپ کے فون میں رہتا ہے'), findsWidgets);
  });

  testWidgets('terms of use opens from the About screen', (tester) async {
    await openLegalPage(tester, 'شرائطِ استعمال', 'قبولیت');
  });

  testWidgets('disclaimer opens from the About screen', (tester) async {
    await openLegalPage(tester, 'دستبرداری', 'کھاد حساب کی مقداریں');
    expect(find.textContaining('مٹی کا ٹیسٹ'), findsWidgets);
  });
}
