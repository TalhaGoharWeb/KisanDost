/// Party ledger (udhaar) models — "who owes whom".
///
/// Money is stored as SIGNED integer paisa from the farmer's perspective:
/// positive = the party owes the farmer (receivable), negative = the farmer
/// owes the party (payable). The provider signs amounts from the entry type,
/// so callers always pass unsigned paisa. Balances are always SUM() queries —
/// never a stored column.
library;

/// The four kinds of ledger entries, with Urdu labels and a one-line hint.
enum PartyEntryType {
  /// میں نے پارٹی کو ادھار دیا → party owes me → positive delta.
  udhaarDiya,

  /// میں نے پارٹی سے ادھار لیا → I owe party → negative delta.
  udhaarLiya,

  /// پارٹی سے وصولی → reduces what party owes me → negative delta.
  wusooli,

  /// پارٹی کو ادائیگی → reduces what I owe party → positive delta.
  adaigi,
}

/// Wire value stored in the DB.
String partyEntryTypeToString(PartyEntryType type) => switch (type) {
  PartyEntryType.udhaarDiya => 'udhaar_diya',
  PartyEntryType.udhaarLiya => 'udhaar_liya',
  PartyEntryType.wusooli => 'wusooli',
  PartyEntryType.adaigi => 'adaigi',
};

PartyEntryType partyEntryTypeFromString(String raw) => switch (raw) {
  'udhaar_diya' => PartyEntryType.udhaarDiya,
  'udhaar_liya' => PartyEntryType.udhaarLiya,
  'wusooli' => PartyEntryType.wusooli,
  'adaigi' => PartyEntryType.adaigi,
  _ => throw ArgumentError('Unknown party entry type: $raw'),
};

/// Urdu label shown in the UI.
String partyEntryTypeUrdu(PartyEntryType type) => switch (type) {
  PartyEntryType.udhaarDiya => 'ادھار دیا',
  PartyEntryType.udhaarLiya => 'ادھار لیا',
  PartyEntryType.wusooli => 'وصولی',
  PartyEntryType.adaigi => 'ادائیگی',
};

/// One-line hint for the entry form.
String partyEntryTypeHint(PartyEntryType type) => switch (type) {
  PartyEntryType.udhaarDiya =>
    'آپ نے پارٹی کو رقم دی — پارٹی کی ذمہ داری بڑھے گی',
  PartyEntryType.udhaarLiya => 'آپ نے پارٹی سے رقم لی — آپ کی ذمہ داری بڑھے گی',
  PartyEntryType.wusooli =>
    'پارٹی نے آپ کو رقم واپس کی — پارٹی کی ذمہ داری کم ہوگی',
  PartyEntryType.adaigi =>
    'آپ نے پارٹی کو رقم واپس کی — آپ کی ذمہ داری کم ہوگی',
};

/// Sign applied to the unsigned input amount, from the farmer's perspective.
/// Positive = receivable (party owes me), negative = payable (I owe party).
int partyEntryTypeSign(PartyEntryType type) => switch (type) {
  PartyEntryType.udhaarDiya => 1,
  PartyEntryType.udhaarLiya => -1,
  PartyEntryType.wusooli => -1,
  PartyEntryType.adaigi => 1,
};

/// The underlying transaction a ledger entry traces to (owner decision #3,
/// S5 / FINANCIAL_POLICY §6.4: "link ledger entries to the underlying
/// transaction, where applicable").
///
/// A link is a TRACE MARKER only — it never changes the entry's sign and
/// never creates income/expense rows. A وصولی linked to an
/// already-recognized sale only shrinks the receivable; the sale's income
/// was booked once, when the sale was recorded. So a collection on a
/// recognized sale can never double-count income.
///
/// `sale` vs `collection`: both point at the `sales` table. `sale` marks
/// the entry as the receivable's origin (e.g. an ادھار دیا mirroring a
/// credit sale); `collection` marks it as a settlement against that sale
/// (e.g. a وصولی). The distinction records intent; reconciliation sums
/// both. `payment` points at `theka_installments` (an installment paid to
/// a party); `expense` at `expenses` (a credit purchase or its payment).
enum PartyEntrySourceType {
  /// Row in `sales` — the receivable's origin.
  sale,

  /// Row in `expenses` — the payable's origin or its settlement.
  expense,

  /// Row in `theka_installments` — an installment payment to a party.
  payment,

  /// Row in `sales` — a collection settling that sale.
  collection,
}

/// Wire value stored in `party_ledger_entries.source_type`.
String partyEntrySourceTypeToString(PartyEntrySourceType type) => switch (type) {
  PartyEntrySourceType.sale => 'sale',
  PartyEntrySourceType.expense => 'expense',
  PartyEntrySourceType.payment => 'payment',
  PartyEntrySourceType.collection => 'collection',
};

PartyEntrySourceType partyEntrySourceTypeFromString(String raw) => switch (raw) {
  'sale' => PartyEntrySourceType.sale,
  'expense' => PartyEntrySourceType.expense,
  'payment' => PartyEntrySourceType.payment,
  'collection' => PartyEntrySourceType.collection,
  _ => throw ArgumentError('Unknown party entry source type: $raw'),
};

/// Urdu label shown in the UI.
String partyEntrySourceTypeUrdu(PartyEntrySourceType type) => switch (type) {
  PartyEntrySourceType.sale => 'فروخت',
  PartyEntrySourceType.expense => 'اخراجات',
  PartyEntrySourceType.payment => 'ٹھیکہ قسط',
  PartyEntrySourceType.collection => 'وصولی (فروخت)',
};

/// The table `source_id` refers to for each source type. Used by the
/// provider to verify the linked row exists at write time.
String partyEntrySourceTable(PartyEntrySourceType type) => switch (type) {
  PartyEntrySourceType.sale => 'sales',
  PartyEntrySourceType.expense => 'expenses',
  PartyEntrySourceType.payment => 'theka_installments',
  PartyEntrySourceType.collection => 'sales',
};

/// One-line, UI-ready summary of a linked source transaction, for the
/// trace view. `null` (from the provider) means the source row is gone —
/// the link itself survives as an audit marker.
class PartyEntrySourceSummary {
  final PartyEntrySourceType type;
  final int id;
  final String title; // e.g. 'فروخت #12'
  final int amountPaisa; // unsigned total/amount of the source row
  final String date; // yyyy-MM-dd
  final String? detail; // buyer name / category / status — may be null

  PartyEntrySourceSummary({
    required this.type,
    required this.id,
    required this.title,
    required this.amountPaisa,
    required this.date,
    this.detail,
  });
}

class Party {
  final int? id;
  final String name;
  final String? phone;
  final String? notes;
  final String createdAt;

  /// ISO timestamp of soft deletion; NULL = live row. Never in [toMap].
  final String? deletedAt;

  Party({
    this.id,
    required this.name,
    this.phone,
    this.notes,
    required this.createdAt,
    this.deletedAt,
  });

  Map<String, dynamic> toMap() => {
    'id': id,
    'name': name,
    'phone': phone,
    'notes': notes,
    'created_at': createdAt,
  };

  factory Party.fromMap(Map<String, dynamic> map) => Party(
    id: map['id'] as int?,
    name: map['name'] as String,
    phone: map['phone'] as String?,
    notes: map['notes'] as String?,
    createdAt: map['created_at'] as String,
    deletedAt: map['deleted_at'] as String?,
  );
}

class PartyLedgerEntry {
  final int? id;
  final int partyId;
  final PartyEntryType type;
  final int amountPaisa; // SIGNED, from the farmer's perspective.
  final String date; // yyyy-MM-dd
  final String? note;
  final String createdAt;

  /// Link to the underlying transaction (owner decision #3). Null =
  /// unlinked: a plain manual entry, or a legacy row predating v16.
  final PartyEntrySourceType? sourceType;
  final int? sourceId;

  PartyLedgerEntry({
    this.id,
    required this.partyId,
    required this.type,
    required this.amountPaisa,
    required this.date,
    this.note,
    required this.createdAt,
    this.sourceType,
    this.sourceId,
  });

  Map<String, dynamic> toMap() => {
    'id': id,
    'party_id': partyId,
    'entry_type': partyEntryTypeToString(type),
    'amount_paisa': amountPaisa,
    'date': date,
    'note': note,
    'created_at': createdAt,
    'source_type': sourceType == null
        ? null
        : partyEntrySourceTypeToString(sourceType!),
    'source_id': sourceId,
  };

  factory PartyLedgerEntry.fromMap(Map<String, dynamic> map) =>
      PartyLedgerEntry(
        id: map['id'] as int?,
        partyId: map['party_id'] as int,
        type: partyEntryTypeFromString(map['entry_type'] as String),
        amountPaisa: map['amount_paisa'] as int,
        date: map['date'] as String,
        note: map['note'] as String?,
        createdAt: map['created_at'] as String,
        // Pre-v16 rows (and maps built without the keys) read as unlinked.
        sourceType: map['source_type'] == null
            ? null
            : partyEntrySourceTypeFromString(map['source_type'] as String),
        sourceId: map['source_id'] as int?,
      );
}
