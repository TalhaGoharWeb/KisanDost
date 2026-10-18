import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:kisan_dost/models/batai.dart';
import 'package:kisan_dost/models/models.dart';
import 'package:kisan_dost/models/party.dart';
import 'package:kisan_dost/providers/activity_provider.dart';
import 'package:kisan_dost/providers/batai_provider.dart';
import 'package:kisan_dost/providers/crop_provider.dart';
import 'package:kisan_dost/providers/expense_provider.dart';
import 'package:kisan_dost/providers/farm_provider.dart';
import 'package:kisan_dost/providers/harvest_provider.dart';
import 'package:kisan_dost/providers/party_provider.dart';
import 'package:kisan_dost/screens/audit_log_screen.dart';
import 'package:kisan_dost/screens/batai_detail_screen.dart';
import 'package:kisan_dost/screens/expenses_screen.dart';
import 'package:kisan_dost/screens/party_detail_screen.dart';
import 'package:kisan_dost/services/audit_service.dart';

// ---------- Fakes ----------

class FakeBataiProvider extends BataiProvider {
  FakeBataiProvider(this.summary);
  final BataiAgreementSummary summary;

  @override
  Future<BataiAgreementSummary?> getAgreementSummary(int id) async => summary;

  @override
  Future<List<BataiSettlement>> getSettlements(int agreementId) async => [];
}

class FakeHarvestProvider extends HarvestProvider {
  @override
  List<HarvestWithDetails> get harvests => [];

  @override
  List<Sale> get sales => [];

  @override
  Future<void> fetchHarvests() async {}
}

class FakePartyProvider extends PartyProvider {
  FakePartyProvider(this.fakeParty);
  final Party fakeParty;

  int addEntryCalls = 0;
  int? recordedAmountPaisa;

  @override
  List<Party> get parties => [fakeParty];

  // One seeded entry: the real screen shows a forever-repeating
  // EmptyStateWidget animation when the ledger is empty, which makes
  // pumpAndSettle() hang. The dialog under test does not depend on entries.
  @override
  Future<List<PartyLedgerEntry>> getEntries(int partyId) async => [
    PartyLedgerEntry(
      id: 1,
      partyId: partyId,
      type: PartyEntryType.udhaarDiya,
      amountPaisa: 100000,
      date: '2026-09-01',
      createdAt: '2026-09-01T00:00:00',
    ),
  ];

  @override
  Future<int> addEntry({
    required int partyId,
    required PartyEntryType type,
    required int amountPaisa,
    required String date,
    String? note,
  }) async {
    addEntryCalls++;
    recordedAmountPaisa = amountPaisa;
    return 1;
  }
}

class FakeExpenseProvider extends ExpenseProvider {
  int addExpenseCalls = 0;
  int? recordedAmountPaisa;

  // One seeded expense: the real screen shows a forever-repeating
  // EmptyStateWidget animation (and a RenderFlex overflow at small heights)
  // when the list is empty, which makes pumpAndSettle() hang. The dialog
  // under test does not depend on existing expenses.
  @override
  List<Expense> get expenses => [
    Expense(
      id: 1,
      category: 'Fertilizer',
      amountPaisa: 100000,
      date: '2026-09-01',
      description: 'کھاد',
    ),
  ];

  @override
  Future<void> fetchExpenses() async {}

  @override
  Future<int> addExpense({
    required String category,
    required int amountPaisa,
    required String date,
    String? description,
    int? farmId,
    int? fieldId,
    int? cropSeasonId,
  }) async {
    addExpenseCalls++;
    recordedAmountPaisa = amountPaisa;
    return 1;
  }
}

class FakeCropProvider extends CropProvider {
  @override
  List<CropSeasonWithDetails> get activeCropSeasons => [];

  @override
  List<CropSeasonWithDetails> get harvestedCropSeasons => [];
}

class FakeFarmProvider extends FarmProvider {
  @override
  List<Farm> get farms => [];

  @override
  List<Field> getFieldsForFarm(int farmId) => [];
}

class FakeActivityProvider extends ActivityProvider {}

// ---------- Harnesses ----------

BataiAgreementSummary fiftyFiftySummary() => BataiAgreementSummary(
  agreement: BataiAgreement(
    id: 1,
    farmerRole: FarmerRole.landowner,
    otherPartyId: 7,
    ownerSharePercent: 50,
    cultivatorSharePercent: 50,
    startDate: '2026-01-01',
    createdAt: '2026-01-01T00:00:00',
  ),
  partyName: 'ٹیسٹ فریق',
);

void main() {
  group('batai settle dialog — split preview wiring', () {
    testWidgets('typing an amount previews the Money.parse + splitBatai split; '
        'clearing restores the hint', (tester) async {
      await tester.pumpWidget(
        MultiProvider(
          providers: [
            ChangeNotifierProvider<BataiProvider>.value(
              value: FakeBataiProvider(fiftyFiftySummary()),
            ),
            ChangeNotifierProvider<HarvestProvider>.value(
              value: FakeHarvestProvider(),
            ),
          ],
          child: const MaterialApp(home: BataiDetailScreen(agreementId: 1)),
        ),
      );
      await tester.pumpAndSettle(); // post-frame _load()

      await tester.tap(find.text('حساب چکتا کریں'));
      await tester.pumpAndSettle();

      final amountField = find.widgetWithText(TextField, 'کل رقم (روپے) *');
      expect(amountField, findsOneWidget);

      // 100.01 روپے = 10001 paisa → splitBatai(10001, 50) = 5001/5000:
      // the 1-paisa leftover goes to the owner on a tie.
      // (The brief's literal '10001' is rupees = 1000100 paisa → 500.50 each;
      // '100.01' is what produces the brief's expected 50.01/50 strings.)
      await tester.enterText(amountField, '100.01');
      await tester.pump();
      expect(find.text('مالک: 50.01 روپے'), findsOneWidget);
      expect(find.text('مزارع: 50 روپے'), findsOneWidget);

      // Clearing the field drops the preview back to the hint.
      await tester.enterText(amountField, '');
      await tester.pump();
      expect(find.text('رقم لکھیں تو حصے یہاں نظر آئیں گے'), findsOneWidget);
      expect(find.text('مالک: 50.01 روپے'), findsNothing);
    });
  });

  group('party entry dialog — Money.parse validation', () {
    testWidgets(
      'garbage amount shows an Urdu snackbar and keeps the dialog open; '
      'Urdu digits save the exact paisa',
      (tester) async {
        final fake = FakePartyProvider(
          Party(id: 1, name: 'ٹیسٹ پارٹی', createdAt: '2026-01-01T00:00:00'),
        );
        await tester.pumpWidget(
          ChangeNotifierProvider<PartyProvider>.value(
            value: fake,
            child: const MaterialApp(home: PartyDetailScreen(partyId: 1)),
          ),
        );
        await tester.pumpAndSettle();

        await tester.tap(find.text('اندراج کریں'));
        await tester.pumpAndSettle();

        final amountField = find.widgetWithText(TextField, 'رقم (روپے) *');
        expect(amountField, findsOneWidget);

        await tester.enterText(amountField, 'abc');
        await tester.tap(find.text('محفوظ کریں'));
        await tester.pump();
        // MoneyParseException's Urdu message, dialog still open, nothing saved.
        expect(
          find.text('درست رقم درج کریں (مثلاً 1250 یا 1250.50)'),
          findsOneWidget,
        );
        expect(find.text('نیا اندراج'), findsOneWidget);
        expect(fake.addEntryCalls, 0);

        // Urdu digits parse: ۵۰۰۰ = 5000 rupees = 500000 paisa.
        await tester.enterText(amountField, '۵۰۰۰');
        await tester.tap(find.text('محفوظ کریں'));
        await tester.pumpAndSettle();
        expect(fake.recordedAmountPaisa, 500000);
        expect(find.text('نیا اندراج'), findsNothing); // dialog closed on save
      },
    );
  });

  group('expense form — Money.parse validation', () {
    testWidgets(
      'negative amount fails the validator with Urdu text and saves nothing; '
      'Urdu digits pass and save exact paisa',
      (tester) async {
        final expenses = FakeExpenseProvider();
        await tester.pumpWidget(
          MultiProvider(
            providers: [
              ChangeNotifierProvider<ExpenseProvider>.value(value: expenses),
              ChangeNotifierProvider<CropProvider>.value(
                value: FakeCropProvider(),
              ),
              ChangeNotifierProvider<ActivityProvider>.value(
                value: FakeActivityProvider(),
              ),
              ChangeNotifierProvider<FarmProvider>.value(
                value: FakeFarmProvider(),
              ),
            ],
            child: const MaterialApp(home: ExpensesScreen()),
          ),
        );
        await tester.pumpAndSettle();

        // The FAB label is the only 'نیا خرچہ درج کریں' Text before the
        // dialog opens (the app-bar entry is a tooltip, not rendered text).
        await tester.tap(find.text('نیا خرچہ درج کریں'));
        await tester.pumpAndSettle();

        final amountField = find.widgetWithText(
          TextFormField,
          'خرچے کی رقم (روپے)',
        );
        expect(amountField, findsOneWidget);

        await tester.enterText(amountField, '-5');
        await tester.tap(find.text('محفوظ کریں'));
        await tester.pump();
        // The validator surfaces Money.parse's Urdu rejection; no save happens
        // and the dialog stays open.
        expect(
          find.text('درست رقم درج کریں (مثلاً 1250 یا 1250.50)'),
          findsOneWidget,
        );
        expect(expenses.addExpenseCalls, 0);

        // Urdu digits pass validation: ۱۲۳ = 123 rupees = 12300 paisa.
        await tester.enterText(amountField, '۱۲۳');
        await tester.tap(find.text('محفوظ کریں'));
        await tester.pumpAndSettle();
        expect(expenses.recordedAmountPaisa, 12300);
        expect(expenses.addExpenseCalls, 1);
      },
    );
  });

  group('audit log viewer screen', () {
    // FFI + widget-test lesson: a screen that fires real FFI from initState
    // (AuditLogScreen._reload) can ONLY be pumped inside tester.runAsync()
    // (the real async zone). Awaiting FFI directly in the testWidgets body
    // (FakeAsync zone) wedges the very next pumpWidget forever, and
    // _reload's own query never resolves there either (spinner spins
    // forever, pumpAndSettle times out). Recipe: inside runAsync — seed via
    // FFI, pumpWidget, a short REAL delay to drain _reload, plain pumps to
    // rebuild, then assert. Never pumpAndSettle here (the empty state's
    // float animation repeats forever).
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    TestWidgetsFlutterBinding.ensureInitialized();
    SharedPreferences.setMockInitialValues({});

    Future<Database> openAuditDb() async {
      final db = await openDatabase(inMemoryDatabasePath);
      await db.execute('DROP TABLE IF EXISTS audit_log');
      // Real v15 audit_log schema, copied from DatabaseHelper._onCreate.
      await db.execute('''
        CREATE TABLE audit_log (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          ts TEXT NOT NULL,
          table_name TEXT NOT NULL,
          row_id INTEGER NOT NULL,
          action TEXT NOT NULL,
          details TEXT,
          created_at TEXT NOT NULL
        )
      ''');
      return db;
    }

    testWidgets('logged actions render with Urdu labels and details', (
      tester,
    ) async {
      await tester.runAsync(() async {
        final db = await openAuditDb();
        await AuditService.log(
          db,
          table: 'expenses',
          rowId: 1,
          action: AuditService.create,
          details: 'خرچ: کھاد — 5,000 روپے',
        );
        await AuditService.log(
          db,
          table: 'expenses',
          rowId: 1,
          action: AuditService.softDelete,
          details: 'خرچ حذف',
        );

        await tester.pumpWidget(
          MaterialApp(home: AuditLogScreen(executor: db)),
        );
        // Real delay: lets _reload's FFI query drain on the real event
        // loop; then plain pumps rebuild with the rows.
        await Future<void>.delayed(const Duration(milliseconds: 500));
        await tester.pump();
        await tester.pump();

        // Newest first: the soft-delete row is on top.
        expect(find.text('خرچ — حذف کیا گیا'), findsOneWidget);
        expect(find.text('خرچ — بنایا گیا'), findsOneWidget);
        expect(find.text('خرچ حذف'), findsOneWidget);
        expect(find.text('خرچ: کھاد — 5,000 روپے'), findsOneWidget);

        await db.close();
      });
    });

    testWidgets('empty log shows the Urdu empty state', (tester) async {
      await tester.runAsync(() async {
        final db = await openAuditDb();

        await tester.pumpWidget(
          MaterialApp(home: AuditLogScreen(executor: db)),
        );
        await Future<void>.delayed(const Duration(milliseconds: 500));
        await tester.pump();
        await tester.pump();

        expect(find.text('ابھی کوئی تبدیلی درج نہیں'), findsOneWidget);

        await db.close();
      });
    });
  });
}
