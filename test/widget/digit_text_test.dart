import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kisan_dost/widgets/digit_text.dart';

void main() {
  testWidgets('DigitText renders with the Noto Sans numeric font',
      (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: DigitText('1,250 روپے'),
        ),
      ),
    );

    expect(find.text('1,250 روپے'), findsOneWidget);
    final text = tester.widget<Text>(find.byType(Text));
    expect(text.style?.fontFamily, 'Noto Sans');
    expect(
      text.style?.fontFeatures,
      contains(const FontFeature.tabularFigures()),
    );
  });

  testWidgets('DigitText merges a caller-provided style', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: DigitText(
            '500',
            style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
          ),
        ),
      ),
    );

    final text = tester.widget<Text>(find.byType(Text));
    expect(text.style?.fontSize, 20);
    expect(text.style?.fontWeight, FontWeight.bold);
    // Numeric font wins over the ambient (Nastaleeq) theme font.
    expect(text.style?.fontFamily, 'Noto Sans');
  });
}
