import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:provider/provider.dart';
import 'dart:async';
import 'theme/app_theme.dart';
import 'l10n/app_locale.dart';
import 'screens/splash_screen.dart';

import 'providers/farm_provider.dart';
import 'providers/crop_provider.dart';
import 'providers/activity_provider.dart';
import 'providers/inventory_provider.dart';
import 'providers/harvest_provider.dart';
import 'providers/expense_provider.dart';
import 'providers/task_provider.dart';
import 'providers/theka_provider.dart';
import 'providers/ushr_provider.dart';
import 'providers/party_provider.dart';
import 'providers/batai_provider.dart';
import 'services/notification_service.dart';
import 'services/backup_service.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await NotificationService().init();
  // خودکار روزانہ بیک اپ: ایپ کھلنے پر دن میں ایک بار — کبھی لانچ نہیں روکتا، کبھی کریش نہیں کرتا۔
  unawaited(BackupService().maybeAutoBackup().catchError((e) {
    debugPrint('Auto-backup failed: $e');
  }));
  runApp(const KisanDostApp());
}

class KisanDostApp extends StatelessWidget {
  const KisanDostApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => FarmProvider()..fetchFarms()),
        ChangeNotifierProvider(create: (_) => CropProvider()..fetchCropSeasons()),
        ChangeNotifierProvider(create: (_) => InventoryProvider()..fetchInventory()),
        ChangeNotifierProvider(create: (_) => ActivityProvider()..fetchActivities()),
        ChangeNotifierProvider(create: (_) => HarvestProvider()..fetchHarvests()),
        ChangeNotifierProvider(create: (_) => ExpenseProvider()..fetchExpenses()),
        ChangeNotifierProvider(create: (_) => TaskProvider()..fetchTasks()),
        ChangeNotifierProvider(create: (_) => ThekaProvider()..fetchThekas()),
        ChangeNotifierProvider(create: (_) => UshrProvider()..fetchUshrRecords()),
        ChangeNotifierProvider(create: (_) => PartyProvider()..fetchParties()),
        ChangeNotifierProvider(create: (_) => BataiProvider()..fetchAgreements()),
        // App locale: text direction (RTL) comes from the locale via
        // flutter_localizations — never from a forced Directionality widget.
        ChangeNotifierProvider(create: (_) => AppLocale()..load()),
      ],
      child: Consumer<AppLocale>(
        builder: (context, appLocale, _) => MaterialApp(
          title: 'کسان دوست',
          navigatorKey: NotificationService.navigatorKey,
          debugShowCheckedModeBanner: false,
          theme: AppTheme.lightTheme,
          locale: appLocale.locale,
          supportedLocales: const [Locale('ur'), Locale('en')],
          localizationsDelegates: GlobalMaterialLocalizations.delegates,
          home: const SplashScreen(),
        ),
      ),
    );
  }
}
