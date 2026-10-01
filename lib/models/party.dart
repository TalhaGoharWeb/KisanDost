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

  PartyLedgerEntry({
    this.id,
    required this.partyId,
    required this.type,
    required this.amountPaisa,
    required this.date,
    this.note,
    required this.createdAt,
  });

  Map<String, dynamic> toMap() => {
    'id': id,
    'party_id': partyId,
    'entry_type': partyEntryTypeToString(type),
    'amount_paisa': amountPaisa,
    'date': date,
    'note': note,
    'created_at': createdAt,
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
      );
}
