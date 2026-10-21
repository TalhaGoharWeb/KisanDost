import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:kisan_dost/database/db_helper.dart';
import 'package:kisan_dost/providers/fertilizer_plan_provider.dart';
import 'package:kisan_dost/providers/inventory_provider.dart';
import 'package:kisan_dost/screens/khaad_hisaab_screen.dart';

/// Widget tests for کھاد حساب. FFI (sqflite) wedges inside testWidgets'
/// FakeAsync zone (AGENTS.md lesson), so all DB setup and the
/// save-flow run inside tester.runAsync(). The screen is one long
/// ListView that builds lazily, so buttons are revealed by dragging.
void main() {
  SharedPreferences.setMockInitialValues({});
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  Future<(Database, FertilizerPlanProvider, InventoryProvider)>
  setupProviders() async {
    final db = await openDatabase(
      inMemoryDatabasePath,
      onConfigure: (db) async {
        await db.execute('PRAGMA foreign_keys = ON');
      },
    );
    await DatabaseHelper.instance.createFreshSchemaForTests(db);
    final plans = FertilizerPlanProvider(testExecutor: db);
    await plans.fetchPlans();
    final inventory = InventoryProvider(testExecutor: db);
    await inventory.fetchInventory();
    return (db, plans, inventory);
  }

  Widget app(FertilizerPlanProvider plans, InventoryProvider inventory) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider.value(value: plans),
        ChangeNotifierProvider.value(value: inventory),
      ],
      child: const MaterialApp(home: KhaadHisaabScreen()),
    );
  }

  Future<void> revealAndTap(WidgetTester tester, Finder finder) async {
    for (var i = 0; i < 12 && finder.evaluate().isEmpty; i++) {
      await tester.drag(find.byType(ListView), const Offset(0, -400));
      await tester.pump();
    }
    expect(finder, findsOneWidget);
    await tester.ensureVisible(finder);
    await tester.pump();
    await tester.tap(finder);
    await tester.pump();
  }

  testWidgets('calculate shows a plan for the default wheat recommendation', (
    tester,
  ) async {
    late Database db;
    await tester.runAsync(() async {
      final (d, plans, inventory) = await setupProviders();
      db = d;
      await tester.pumpWidget(app(plans, inventory));
    });
    await tester.pump();

    expect(find.text('کھاد حساب'), findsOneWidget);
    // Official source label is visible before calculating.
    expect(find.textContaining('پاکٹ بک 2022'), findsWidgets);

    await revealAndTap(
      tester,
      find.widgetWithText(ElevatedButton, 'حساب لگائیں'),
    );

    // Result with products and the stage schedule.
    expect(find.textContaining('نتیجہ'), findsOneWidget);
    expect(find.textContaining('ڈی اے پی'), findsWidgets);
    expect(find.textContaining('اقساط'), findsOneWidget);
    // Plan-only note: a plan must never deduct stock by itself.
    expect(find.textContaining('اسٹاک سے کھاد تب ہی کٹے گی'), findsOneWidget);

    // The full combination grid (36) is offered below the result.
    final combos = find.textContaining('تمام امتزاج (36)');
    for (var i = 0; i < 14 && combos.evaluate().isEmpty; i++) {
      await tester.drag(find.byType(ListView), const Offset(0, -400));
      await tester.pump();
    }
    expect(combos, findsOneWidget);
    // Each combination states the exact kilos/bags per fertilizer and
    // whether it fulfils the crop's full nutrient need.
    final fulfil = find.textContaining('پوری غذائی ضرورت پوری کرتا ہے');
    for (var i = 0; i < 10 && fulfil.evaluate().isEmpty; i++) {
      await tester.drag(find.byType(ListView), const Offset(0, -400));
      await tester.pump();
    }
    expect(fulfil, findsWidgets);
    expect(find.textContaining('کلو ='), findsWidgets);

    await tester.runAsync(() => db.close());
  });

  testWidgets('saving a plan lists it under saved plans', (tester) async {
    late Database db;
    late FertilizerPlanProvider plans;
    await tester.runAsync(() async {
      final (d, p, inventory) = await setupProviders();
      db = d;
      plans = p;
      await tester.pumpWidget(app(p, inventory));
    });
    await tester.pump();

    await revealAndTap(
      tester,
      find.widgetWithText(ElevatedButton, 'حساب لگائیں'),
    );
    await revealAndTap(
      tester,
      find.widgetWithText(ElevatedButton, 'منصوبہ محفوظ کریں'),
    );
    // The save hits FFI — its isolate round-trips each need a real
    // event-loop turn, so flush repeatedly (AGENTS.md FFI recipe).
    for (var i = 0; i < 6; i++) {
      await tester.runAsync(() async {
        await Future<void>.delayed(const Duration(milliseconds: 250));
      });
      await tester.pump();
    }
    // Evidence the save callback actually ran: its snackbar.
    expect(find.text('منصوبہ محفوظ ہو گیا'), findsOneWidget);

    expect(plans.plans, hasLength(1));
    expect(find.text('محفوظ شدہ منصوبے'), findsOneWidget);

    await tester.runAsync(() => db.close());
  });
}
