import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'theme/app_theme.dart';
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
import 'services/notification_service.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await NotificationService().init();
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
      ],
      child: MaterialApp(
        title: 'کسان دوست',
        navigatorKey: NotificationService.navigatorKey,
        debugShowCheckedModeBanner: false,
        theme: AppTheme.lightTheme,
        // Force RTL for Urdu
        builder: (context, child) {
          return Directionality(
            textDirection: TextDirection.rtl,
            child: child!,
          );
        },
        home: const SplashScreen(),
      ),
    );
  }
}
