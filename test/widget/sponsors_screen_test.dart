import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kisan_dost/data/sponsors.dart';
import 'package:kisan_dost/screens/sponsors_screen.dart';

void main() {
  testWidgets('sponsors screen shows honest empty state while list is empty', (
    tester,
  ) async {
    await tester.pumpWidget(const MaterialApp(home: SponsorsScreen()));

    expect(find.text('ہمارے اسپانسرز'), findsOneWidget);
    expect(find.text('ابھی کوئی اسپانسر نہیں'), findsOneWidget);
    expect(find.textContaining('muhaqqiqcreates@gmail.com'), findsOneWidget);
    // The free-forever promise stays on the empty state too.
    expect(find.textContaining('ہمیشہ مفت رہے گی'), findsWidgets);
  });

  test('sponsor list starts empty (no invented sponsors)', () {
    expect(kSponsors, isEmpty);
  });
}
