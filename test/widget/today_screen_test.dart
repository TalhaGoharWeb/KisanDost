import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:kisan_dost/models/models.dart';
import 'package:kisan_dost/providers/task_provider.dart';
import 'package:kisan_dost/providers/expense_provider.dart';
import 'package:kisan_dost/providers/harvest_provider.dart';
import 'package:kisan_dost/providers/theka_provider.dart';
import 'package:kisan_dost/providers/crop_provider.dart';
import 'package:kisan_dost/providers/farm_provider.dart';
import 'package:kisan_dost/providers/party_provider.dart';
import 'package:kisan_dost/screens/dashboard_screen.dart';
import 'package:kisan_dost/screens/task_form_screen.dart';
import 'package:kisan_dost/services/money.dart';
import 'package:kisan_dost/services/today_summary.dart';

// ---------- Fake providers (override getters; never touch the DB) ----------

class FakeTaskProvider extends TaskProvider {
  FakeTaskProvider(this.fakeTasks, {this.fakeError});
  final List<TaskItem> fakeTasks;
  final String? fakeError;

  @override
  List<TaskItem> get tasks => fakeTasks;

  @override
  String? get errorMessage => fakeError;

  @override
  Future<void> fetchTasks() async {}

  @override
  Future<void> toggleTaskCompletion(int id, bool currentStatus) async {
    for (final t in fakeTasks) {
      if (t.id == id) t.isCompleted = !currentStatus;
    }
    notifyListeners();
  }
}

class FakeExpenseProvider extends ExpenseProvider {
  FakeExpenseProvider(this.fakeExpenses);
  final List<Expense> fakeExpenses;

  @override
  List<Expense> get expenses => fakeExpenses;

  @override
  Future<void> fetchExpenses() async {}
}

class FakeHarvestProvider extends HarvestProvider {
  FakeHarvestProvider(this.fakeHarvests, this.fakeSales);
  final List<HarvestWithDetails> fakeHarvests;
  final List<Sale> fakeSales;

  @override
  List<HarvestWithDetails> get harvests => fakeHarvests;

  @override
  List<Sale> get sales => fakeSales;

  @override
  Future<void> fetchHarvests() async {}
}

class FakeThekaProvider extends ThekaProvider {
  FakeThekaProvider(this.fakeInstallments);
  final List<ThekaInstallment> fakeInstallments;

  @override
  List<ThekaInstallment> get allInstallments => fakeInstallments;

  @override
  Future<void> fetchThekas() async {}
}

class FakeCropProvider extends CropProvider {
  FakeCropProvider(this.fakeActive);
  final List<CropSeasonWithDetails> fakeActive;

  @override
  List<CropSeasonWithDetails> get activeCropSeasons => fakeActive;

  @override
  Future<void> fetchCropSeasons() async {}
}

class FakeFarmProvider extends FarmProvider {
  FakeFarmProvider(this.fakeFarms);
  final List<Farm> fakeFarms;

  @override
  List<Farm> get farms => fakeFarms;

  @override
  Future<void> fetchFarms() async {}
}

class FakePartyProvider extends PartyProvider {
  FakePartyProvider({this.receivable = 0, this.payable = 0});
  final int receivable;
  final int payable;

  @override
  int get totalReceivablePaisa => receivable;

  @override
  int get totalPayablePaisa => payable;

  @override
  Future<void> fetchParties() async {}
}

// ---------- Harness ----------

Widget makeHome({
  List<TaskItem> tasks = const [],
  String? taskError,
  List<Expense> expenses = const [],
  List<HarvestWithDetails> harvests = const [],
  List<Sale> sales = const [],
  List<ThekaInstallment> installments = const [],
  List<CropSeasonWithDetails> crops = const [],
  List<Farm> farms = const [],
  int partyReceivable = 0,
  int partyPayable = 0,
}) {
  return MultiProvider(
    providers: [
      ChangeNotifierProvider<TaskProvider>.value(
        value: FakeTaskProvider(List.of(tasks), fakeError: taskError),
      ),
      ChangeNotifierProvider<ExpenseProvider>.value(
        value: FakeExpenseProvider(List.of(expenses)),
      ),
      ChangeNotifierProvider<HarvestProvider>.value(
        value: FakeHarvestProvider(List.of(harvests), List.of(sales)),
      ),
      ChangeNotifierProvider<ThekaProvider>.value(
        value: FakeThekaProvider(List.of(installments)),
      ),
      ChangeNotifierProvider<CropProvider>.value(
        value: FakeCropProvider(List.of(crops)),
      ),
      ChangeNotifierProvider<FarmProvider>.value(
        value: FakeFarmProvider(List.of(farms)),
      ),
      ChangeNotifierProvider<PartyProvider>.value(
        value: FakePartyProvider(
          receivable: partyReceivable,
          payable: partyPayable,
        ),
      ),
    ],
    child: const MaterialApp(home: DashboardScreen()),
  );
}

TaskItem task(int id, String title, DateTime when, {bool done = false}) =>
    TaskItem(id: id, title: title, dateTime: when, isCompleted: done);

/// A time later today that can never cross midnight: 2h ahead, but clamped
/// to 23:59 when the suite runs after 22:00 (a +2h offset would otherwise
/// land tomorrow and the task would correctly vanish from "due today").
DateTime laterToday(DateTime now) {
  final candidate = now.add(const Duration(hours: 2));
  if (candidate.day != now.day) {
    return DateTime(now.year, now.month, now.day, 23, 59);
  }
  return candidate;
}

String ymd(DateTime d) =>
    '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

void main() {
  group('TODAY home — empty database', () {
    testWidgets('welcoming empty states, not zeros-as-data', (tester) async {
      await tester.pumpWidget(makeHome());
      await tester.pumpAndSettle();

      expect(find.text('آج کے کام'), findsOneWidget);
      expect(find.text('رقم کی صورتحال'), findsOneWidget);
      expect(find.text('فصلوں کی صورتحال'), findsOneWidget);
      expect(
        find.text(
          'آج کے لیے کوئی کام شیڈول نہیں ہے — آپ کی ڈائری اپ ٹو ڈیٹ ہے!',
        ),
        findsOneWidget,
      );
      expect(
        find.text('ابھی کوئی لین دین ریکارڈ نہیں — پہلا خرچ لکھ کر شروع کریں۔'),
        findsOneWidget,
      );
      expect(
        find.text('ابھی کوئی فصل درج نہیں — نئے سیزن کی فصل لکھ کر شروع کریں۔'),
        findsOneWidget,
      );
      // No zero-amount stats shown on a fresh install.
      expect(find.text(Money(0).format()), findsNothing);
    });

    testWidgets('quick actions and full feature menu are present', (
      tester,
    ) async {
      await tester.pumpWidget(makeHome());
      await tester.pumpAndSettle();

      expect(find.text('خرچ لکھیں'), findsOneWidget);
      expect(find.text('کام لکھیں'), findsOneWidget);
      expect(find.text('فصل دیکھیں'), findsOneWidget);
      expect(find.text('تمام سہولتیں'), findsOneWidget);
      // All 10 destinations preserved.
      for (final label in [
        'میری زمینیں',
        'میری فصلیں',
        'آج کا کام',
        'خرچے',
        'پیداوار',
        'گودام (اسٹاک)',
        'منافع و نقصان',
        'کام کی منصوبہ بندی',
        'ٹھیکہ مینجمنٹ',
        'عشر مینجمنٹ',
      ]) {
        expect(find.text(label), findsOneWidget, reason: label);
      }
    });

    testWidgets('header shows greeting, Urdu date, onboarding line', (
      tester,
    ) async {
      await tester.pumpWidget(makeHome());
      await tester.pumpAndSettle();

      final now = DateTime.now();
      expect(find.text(greetingFor(now)), findsOneWidget);
      expect(find.text(urduDateLine(now)), findsOneWidget);
      expect(find.text('آج سے اپنی ڈیجیٹل ڈائری شروع کریں'), findsOneWidget);
    });

    testWidgets('header shows farm name when farms exist', (tester) async {
      await tester.pumpWidget(
        makeHome(farms: [Farm(name: 'چک 12', totalArea: 5, createdAt: 'x')]),
      );
      await tester.pumpAndSettle();

      expect(find.text('زمین: چک 12'), findsOneWidget);
    });
  });

  group('TODAY home — tasks', () {
    testWidgets('overdue badge on overdue, today tasks listed, future hidden', (
      tester,
    ) async {
      final now = DateTime.now();
      await tester.pumpWidget(
        makeHome(
          tasks: [
            task(1, 'پانی لگائیں', laterToday(now)),
            task(2, 'سپرے کریں', now.subtract(const Duration(days: 1))),
            task(3, 'کھاد ڈالیں', now.add(const Duration(days: 5))),
            task(4, 'مکمل کام', now.add(const Duration(hours: 1)), done: true),
          ],
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('پانی لگائیں'), findsOneWidget);
      expect(find.text('سپرے کریں'), findsOneWidget);
      expect(find.text('زائد المیعاد'), findsOneWidget);
      // Future and completed tasks stay out of the TODAY section.
      expect(find.text('کھاد ڈالیں'), findsNothing);
      expect(find.text('مکمل کام'), findsNothing);
    });

    testWidgets('tapping a task opens the task form', (tester) async {
      final now = DateTime.now();
      await tester.pumpWidget(
        makeHome(
          tasks: [task(1, 'پانی لگائیں', laterToday(now))],
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('پانی لگائیں'));
      await tester.pumpAndSettle();
      expect(find.byType(TaskFormScreen), findsOneWidget);
    });

    testWidgets('provider error shows retryable Urdu error', (tester) async {
      await tester.pumpWidget(makeHome(taskError: 'نقلی خرابی'));
      await tester.pumpAndSettle();

      expect(find.text('نقلی خرابی'), findsOneWidget);
      expect(find.text('دوبارہ کوشش کریں'), findsOneWidget);
    });
  });

  group('TODAY home — money snapshot in paisa', () {
    testWidgets('today/month expense and month income totals', (tester) async {
      final now = DateTime.now();
      final firstOfMonth = DateTime(now.year, now.month, 1, 12);
      await tester.pumpWidget(
        makeHome(
          expenses: [
            Expense(
              category: 'Labour',
              amountPaisa: 125000,
              date: now.toIso8601String(),
            ),
            Expense(
              category: 'Seeds',
              amountPaisa: 250000,
              date: firstOfMonth.toIso8601String(),
            ),
          ],
          sales: [
            Sale(
              harvestId: 1,
              quantity: 40,
              pricePerUnitPaisa: 125000,
              totalAmountPaisa: 500000,
              date: now.toIso8601String(),
            ),
          ],
        ),
      );
      await tester.pumpAndSettle();

      final todayExpected = isSameDay(now, firstOfMonth) ? 375000 : 125000;
      // On the 1st of the month, "today" and "this month" show the same total.
      expect(
        find.text(Money(375000).format()),
        isSameDay(now, firstOfMonth) ? findsNWidgets(2) : findsOneWidget,
      );
      if (!isSameDay(now, firstOfMonth)) {
        expect(find.text(Money(todayExpected).format()), findsOneWidget);
      }
      // The 500000 sale shows twice: month income + latest-sale row.
      expect(find.text(Money(500000).format()), findsNWidgets(2));
    });

    testWidgets(
      'theka installments due within 7 days surface; paid/far ones do not',
      (tester) async {
        final now = DateTime.now();
        ThekaInstallment inst(int id, int amount, int paid, DateTime due) =>
            ThekaInstallment(
              id: id,
              thekaId: 1,
              amountPaisa: amount,
              paidAmountPaisa: paid,
              dueDate: ymd(due),
              status: 'Pending',
            );
        await tester.pumpWidget(
          makeHome(
            installments: [
              inst(1, 1000000, 400000, now.add(const Duration(days: 3))),
              inst(
                2,
                500000,
                500000,
                now.add(const Duration(days: 2)),
              ), // fully paid
              inst(3, 200000, 0, now.add(const Duration(days: 30))), // too far
              inst(
                4,
                300000,
                0,
                now.subtract(const Duration(days: 2)),
              ), // overdue
            ],
          ),
        );
        await tester.pumpAndSettle();

        expect(find.text('جلد واجب الادا ٹھیکہ قسطیں'), findsOneWidget);
        // Remaining on the due-soon one: 600000 paisa.
        expect(find.text(Money(600000).format()), findsOneWidget);
        // Overdue unpaid one: 300000 paisa, marked زائد المیعاد in its date line.
        expect(find.text(Money(300000).format()), findsOneWidget);
        expect(find.textContaining('زائد المیعاد'), findsOneWidget);
        // Fully-paid and far-future installments stay hidden.
        expect(find.text(Money(500000).format()), findsNothing);
        expect(find.text(Money(200000).format()), findsNothing);
      },
    );

    testWidgets('party receivable/payable lines show when non-zero', (
      tester,
    ) async {
      await tester.pumpWidget(
        makeHome(partyReceivable: 250000, partyPayable: 100000),
      );
      await tester.pumpAndSettle();

      expect(find.text('لوگوں سے لینا ہے'), findsOneWidget);
      expect(find.text('لوگوں کو دینا ہے'), findsOneWidget);
      expect(find.text(Money(250000).format()), findsOneWidget);
      expect(find.text(Money(100000).format()), findsOneWidget);
    });

    testWidgets('party lines hidden when both are zero', (tester) async {
      await tester.pumpWidget(makeHome());
      await tester.pumpAndSettle();

      expect(find.text('لوگوں سے لینا ہے'), findsNothing);
      expect(find.text('لوگوں کو دینا ہے'), findsNothing);
    });
  });

  group('TODAY home — crops', () {
    testWidgets('active seasons and latest sale shown', (tester) async {
      final now = DateTime.now();
      final season = CropSeasonWithDetails(
        cropSeason: CropSeason(
          id: 1,
          fieldId: 1,
          cropName: 'گندم',
          variety: 'فیصل آباد',
          status: 'Active',
          startDate: ymd(now),
        ),
        fields: const [],
        fieldNames: const ['کھیت 1'],
        farmNames: const ['چک 12'],
        totalArea: 5,
      );
      final harvest = HarvestWithDetails(
        harvest: Harvest(
          id: 7,
          cropSeasonId: 1,
          quantity: 40,
          unit: 'kg',
          date: now.toIso8601String(),
        ),
        cropName: 'گندم',
        fieldName: 'کھیت 1',
        fieldSize: 5,
        farmName: 'چک 12',
      );
      await tester.pumpWidget(
        makeHome(
          crops: [season],
          harvests: [harvest],
          sales: [
            Sale(
              harvestId: 7,
              quantity: 40,
              pricePerUnitPaisa: 125000,
              totalAmountPaisa: 500000,
              date: now.toIso8601String(),
            ),
          ],
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('گندم'), findsWidgets);
      expect(find.text('چک 12'), findsWidgets);
      expect(find.textContaining('آخری فروخت'), findsOneWidget);
      // Shown twice: once in the money snapshot (month income), once here.
      expect(find.text(Money(500000).format()), findsNWidgets(2));
    });
  });

  group('today_summary pure logic', () {
    test('greeting follows time of day', () {
      expect(greetingFor(DateTime(2026, 1, 1, 8)), 'صبح بخیر');
      expect(greetingFor(DateTime(2026, 1, 1, 20)), 'شام بخیر');
      expect(greetingFor(DateTime(2026, 1, 1, 14)), 'السلام علیکم');
      expect(greetingFor(DateTime(2026, 1, 1, 2)), 'السلام علیکم');
    });

    test('urduDateLine renders weekday and month', () {
      // 2026-10-01 is a Thursday.
      expect(urduDateLine(DateTime(2026, 10, 1)), 'جمعرات، 1 اکتوبر 2026');
    });

    test('overdue respects snooze', () {
      final now = DateTime(2026, 10, 1, 12);
      final past = DateTime(2026, 10, 1, 9);
      final plain = TaskItem(id: 1, title: 'a', dateTime: past);
      expect(isTaskOverdue(plain, now), isTrue);
      expect(isTaskDueToday(plain, now), isFalse);

      final snoozed = TaskItem(
        id: 2,
        title: 'b',
        dateTime: past,
        snoozedUntil: now.add(const Duration(hours: 5)),
      );
      expect(isTaskOverdue(snoozed, now), isFalse);

      final later = TaskItem(
        id: 3,
        title: 'c',
        dateTime: now.add(const Duration(hours: 2)),
      );
      expect(isTaskDueToday(later, now), isTrue);
      expect(isTaskOverdue(later, now), isFalse);
    });

    test('dueSoonInstallments includes overdue, excludes paid and far', () {
      final now = DateTime(2026, 10, 1, 12);
      ThekaInstallment inst(String due, int amount, int paid) =>
          ThekaInstallment(
            thekaId: 1,
            amountPaisa: amount,
            paidAmountPaisa: paid,
            dueDate: due,
            status: 'Pending',
          );
      final list = dueSoonInstallments([
        inst('2026-10-03', 100000, 0), // in 2 days
        inst('2026-09-28', 50000, 0), // overdue
        inst('2026-10-02', 70000, 70000), // paid
        inst('2026-11-01', 90000, 0), // too far
      ], now);
      expect(list.map((i) => i.amountPaisa).toList(), [50000, 100000]);
      expect(remainingPaisa(list.first), 50000);
    });

    test('party totals split receivable and payable', () {
      expect(totalReceivablePaisa({1: 50000, 2: -30000, 3: 0}), 50000);
      expect(totalPayablePaisa({1: 50000, 2: -30000, 3: 0}), 30000);
      expect(totalReceivablePaisa({}), 0);
      expect(totalPayablePaisa({}), 0);
    });
  });
}
