// CSV export builders for Kisan Dost — pure functions, no DB, no Flutter.
//
// Every builder takes plain model lists and returns a UTF-8 string WITH a
// BOM prefix so Microsoft Excel renders Urdu headers correctly.
// Money is formatted via [Money.format] (exact paisa → rupees); dates are
// emitted exactly as stored (yyyy-MM-dd). Empty inputs produce a valid
// headers-only CSV, never an error.
import '../models/batai.dart';
import '../models/models.dart';
import '../models/party.dart';
import '../providers/harvest_provider.dart';
import 'money.dart';
import 'pnl_summary.dart';
import '../l10n/strings.dart';

/// UTF-8 BOM — required for Excel to detect UTF-8 and render Urdu.
const String csvBom = '\uFEFF';

/// Escapes one CSV field per RFC 4180.
String csvEscape(String? value) {
  final v = value ?? '';
  if (v.contains(',') ||
      v.contains('"') ||
      v.contains('\n') ||
      v.contains('\r')) {
    return '"${v.replaceAll('"', '""')}"';
  }
  return v;
}

String _csv(List<String> headers, List<List<String?>> rows) {
  final sb = StringBuffer(csvBom);
  sb.writeln(headers.map(csvEscape).join(','));
  for (final row in rows) {
    sb.writeln(row.map(csvEscape).join(','));
  }
  return sb.toString();
}

String _money(int paisa) => Money(paisa).format();

/// Expenses CSV. Name maps resolve farm/field/crop IDs to display names;
/// unknown IDs fall back to an empty cell (never a crash).
String expensesCsv(
  List<Expense> expenses, {
  required Map<int, String> farmNames,
  required Map<int, String> fieldNames,
  required Map<int, String> cropNames,
  required Map<String, String> categoryLabels,
}) {
  return _csv(
    const [Strings.date, 'زمرہ', 'رقم', 'زمین', 'کھیت', 'فصل', 'تفصیل'],
    [
      for (final e in expenses)
        [
          e.date,
          categoryLabels[e.category] ?? e.category,
          _money(e.amountPaisa),
          e.farmId == null ? '' : (farmNames[e.farmId] ?? ''),
          e.fieldId == null ? '' : (fieldNames[e.fieldId] ?? ''),
          e.cropSeasonId == null ? '' : (cropNames[e.cropSeasonId] ?? ''),
          e.description,
        ],
    ],
  );
}

/// Sales CSV — one row per sold harvest.
String salesCsv(List<HarvestWithDetails> harvests) {
  return _csv(
    const [
      Strings.date,
      'فصل',
      'زمین',
      'مقدار',
      'اکائی',
      'فی اکائی قیمت',
      'کل رقم',
      'خریدار',
    ],
    [
      for (final h in harvests)
        if (h.sale != null)
          [
            h.sale!.date,
            h.cropName,
            h.farmName,
            _qty(h.harvest.quantity),
            h.harvest.unit,
            _money(h.sale!.pricePerUnitPaisa),
            _money(h.sale!.totalAmountPaisa),
            h.sale!.buyerName,
          ],
    ],
  );
}

/// Party ledger CSV: every entry, then one balance row per party.
/// [balances] maps partyId → signed paisa balance.
String partyLedgerCsv(
  List<PartyLedgerEntry> entries,
  Map<int, String> partyNames,
  Map<int, int> balances,
) {
  final rows = <List<String?>>[
    for (final e in entries)
      [
        e.date,
        partyNames[e.partyId] ?? '',
        partyEntryTypeUrdu(e.type),
        _money(e.amountPaisa.abs()),
        e.amountPaisa >= 0 ? 'پارٹی کی ذمہ' : 'میری ذمہ',
        e.note,
      ],
    // Balance summary rows.
    for (final id in balances.keys)
      [
        '',
        partyNames[id] ?? '',
        'بیلنس',
        _money(balances[id]!.abs()),
        balances[id]! > 0
            ? 'پارٹی سے لینا ہے'
            : balances[id]! < 0
            ? 'پارٹی کو دینا ہے'
            : 'حساب برابر',
        '',
      ],
  ];
  return _csv(const [Strings.date, 'پارٹی', 'قسم', 'رقم', 'سمت', 'نوٹ'], rows);
}

/// Inventory transactions CSV.
String inventoryTransactionsCsv(
  List<InventoryTransaction> txns,
  Map<int, String> itemNames,
) {
  return _csv(
    const [
      Strings.date,
      'آئٹم',
      'قسم',
      'مقدار',
      'اکائی',
      'فی اکائی قیمت',
      'کل رقم',
      'نوٹ',
    ],
    [
      for (final t in txns)
        [
          t.date,
          itemNames[t.inventoryId] ?? '',
          t.typeUrdu,
          _qty(t.quantity),
          t.unit,
          t.unitPricePaisa == null ? '' : _money(t.unitPricePaisa!),
          t.totalAmountPaisa == null ? '' : _money(t.totalAmountPaisa!),
          t.notes,
        ],
    ],
  );
}

/// Batai settlements CSV. [agreementLabels] maps agreementId → display label
/// such as "احمد — 50/50".
String bataiSettlementsCsv(
  List<BataiSettlement> settlements,
  Map<int, String> agreementLabels,
) {
  return _csv(
    const [
      Strings.date,
      'معاہدہ',
      'کل رقم',
      'مالک کا حصہ',
      'کاشتکار کا حصہ',
      'نوٹ',
    ],
    [
      for (final s in settlements)
        [
          s.settleDate,
          agreementLabels[s.agreementId] ?? '',
          _money(s.totalPaisa),
          _money(s.ownerPaisa),
          _money(s.cultivatorPaisa),
          s.note,
        ],
    ],
  );
}

/// Quantity formatting: quantities are physical measures (doubles are fine),
/// shown without trailing zeros.
String _qty(double q) {
  if (q == q.roundToDouble()) return q.toInt().toString();
  return q.toString();
}

/// Data needed by the PDF farm report, assembled by the reports screen from
/// providers. Uses [FarmPnl] so the PDF math is literally the same code as
/// the on-screen P&L.
class PnlReportData {
  final FarmPnl pnl;
  final Map<String, String> cropNameUrdu;
  final String generatedOn; // yyyy-MM-dd

  const PnlReportData({
    required this.pnl,
    required this.cropNameUrdu,
    required this.generatedOn,
  });
}

/// Data for one party receipt (رسید).
class ReceiptData {
  final String partyName;
  final PartyLedgerEntry entry;
  final int balanceAfterPaisa; // running balance AFTER this entry
  final String generatedOn;

  const ReceiptData({
    required this.partyName,
    required this.entry,
    required this.balanceAfterPaisa,
    required this.generatedOn,
  });
}
