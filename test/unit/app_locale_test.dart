import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:kisan_dost/l10n/app_locale.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('AppLocale', () {
    test('defaults to Urdu', () {
      SharedPreferences.setMockInitialValues({});
      final locale = AppLocale();
      expect(locale.code, 'ur');
      expect(locale.locale, const Locale('ur'));
    });

    test('loads a saved supported locale', () async {
      SharedPreferences.setMockInitialValues({'app_locale': 'ur'});
      final locale = AppLocale();
      await locale.load();
      expect(locale.code, 'ur');
    });

    test('ignores unsupported saved codes', () async {
      SharedPreferences.setMockInitialValues({'app_locale': 'xx'});
      final locale = AppLocale();
      await locale.load();
      expect(locale.code, 'ur');
    });

    test('setLocale ignores unsupported codes and persists supported ones',
        () async {
      SharedPreferences.setMockInitialValues({});
      final locale = AppLocale();
      await locale.load();
      await locale.setLocale('xx');
      expect(locale.code, 'ur');
      // 'ur' is the only supported locale today; setting it is a no-op
      // that must not throw.
      await locale.setLocale('ur');
      expect(locale.code, 'ur');
    });

    testWidgets('MaterialApp gets RTL directionality from the ur locale',
        (tester) async {
      // The whole point of the locale-driven architecture: direction
      // comes from the locale via flutter_localizations, not from a
      // forced Directionality widget.
      await tester.pumpWidget(
        MaterialApp(
          locale: const Locale('ur'),
          supportedLocales: const [Locale('ur'), Locale('en')],
          localizationsDelegates:
              GlobalMaterialLocalizations.delegates,
          home: Builder(
            builder: (context) =>
                Text('${Directionality.of(context)}'),
          ),
        ),
      );
      expect(find.text('TextDirection.rtl'), findsOneWidget);
    });
  });
}
