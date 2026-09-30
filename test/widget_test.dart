import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:kisan_dost/providers/farm_provider.dart';
import 'package:kisan_dost/providers/theka_provider.dart';
import 'package:kisan_dost/screens/my_farms_screen.dart';

void main() {
  testWidgets('farm screen shows Urdu empty state and opens area-unit entry', (
    tester,
  ) async {
    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider(create: (_) => FarmProvider()),
          ChangeNotifierProvider(create: (_) => ThekaProvider()),
        ],
        child: const MaterialApp(home: MyFarmsScreen()),
      ),
    );
    await tester.pump(const Duration(milliseconds: 16));

    expect(find.text('میری زمینیں'), findsOneWidget);
    expect(find.text('کوئی زمین موجود نہیں ہے'), findsOneWidget);

    await tester.tap(find.text('نئی زمین شامل کریں').last);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.text('رقبے کی اکائی'), findsOneWidget);
    expect(find.text('ایکڑ'), findsWidgets);
    await tester.tap(find.byType(DropdownButtonFormField<String>));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('کنال'), findsOneWidget);
    expect(find.text('مرلہ'), findsOneWidget);
  });
}
