/// Batai (بٹائی) / muzara'at — sharecropping models.
///
/// A batai agreement records HOW one harvest's proceeds are split between
/// the landowner (مالک) and the cultivator (مزارع): two integer percentages
/// that must sum to exactly 100. [BataiSettlement] rows are append-only
/// financial records — one per settled harvest/sale — and are NEVER edited
/// or deleted.
///
/// ROUNDING RULE (the only rounding in batai, also shown in the settlement
/// dialog before the farmer confirms): paisa cannot be split fractionally,
/// so each share truncates down (`total * percent ~/ 100`) and the leftover
/// paisa (0–99) go to the party with the LARGER share; on a tie the OWNER
/// gets them. `owner_paisa + cultivator_paisa == total_paisa` ALWAYS — also
/// enforced by a DB CHECK constraint, so the provider cannot drift.
///
/// Pure Dart: no Flutter imports, safe to use in tests and providers.
library;

/// Which side of the agreement OUR farmer is on.
enum FarmerRole {
  /// میں مالک ہوں — the farmer owns the land, the other party cultivates.
  landowner,

  /// میں مزارع ہوں — the farmer cultivates someone else's land.
  cultivator,
}

/// Wire value stored in the DB.
String farmerRoleToString(FarmerRole role) => switch (role) {
      FarmerRole.landowner => 'landowner',
      FarmerRole.cultivator => 'cultivator',
    };

FarmerRole farmerRoleFromString(String raw) => switch (raw) {
      'landowner' => FarmerRole.landowner,
      'cultivator' => FarmerRole.cultivator,
      _ => throw ArgumentError('Unknown farmer role: $raw'),
    };

/// Urdu label shown in the UI.
String farmerRoleUrdu(FarmerRole role) => switch (role) {
      FarmerRole.landowner => 'میں مالک ہوں',
      FarmerRole.cultivator => 'میں مزارع ہوں',
    };

/// Lifecycle of a batai agreement. Settled/cancelled are set MANUALLY by
/// the farmer — settling a harvest never flips the status automatically,
/// because one season is usually settled over several harvests.
enum BataiStatus {
  active,
  settled,
  cancelled,
}

/// Wire value stored in the DB.
String bataiStatusToString(BataiStatus status) => switch (status) {
      BataiStatus.active => 'active',
      BataiStatus.settled => 'settled',
      BataiStatus.cancelled => 'cancelled',
    };

BataiStatus bataiStatusFromString(String raw) => switch (raw) {
      'active' => BataiStatus.active,
      'settled' => BataiStatus.settled,
      'cancelled' => BataiStatus.cancelled,
      _ => throw ArgumentError('Unknown batai status: $raw'),
    };

/// Urdu label shown in the UI.
String bataiStatusUrdu(BataiStatus status) => switch (status) {
      BataiStatus.active => 'فعال',
      BataiStatus.settled => 'چکتا شدہ',
      BataiStatus.cancelled => 'منسوخ',
    };

/// Splits [totalPaisa] between owner and cultivator per the rounding rule.
///
/// `ownerPercent` is 0..100; the cultivator's percent is `100 - ownerPercent`.
/// Each share truncates down; the leftover (0–99 paisa) goes to the LARGER
/// share, and on a tie to the OWNER. The two results always sum to
/// [totalPaisa] exactly.
({int ownerPaisa, int cultivatorPaisa}) splitBatai(
    int totalPaisa, int ownerPercent) {
  assert(totalPaisa > 0, 'totalPaisa must be positive');
  assert(ownerPercent >= 0 && ownerPercent <= 100,
      'ownerPercent must be 0..100');
  final cultivatorPercent = 100 - ownerPercent;
  var ownerPaisa = totalPaisa * ownerPercent ~/ 100;
  var cultivatorPaisa = totalPaisa * cultivatorPercent ~/ 100;
  final remainder = totalPaisa - ownerPaisa - cultivatorPaisa;
  if (remainder > 0) {
    if (cultivatorPercent > ownerPercent) {
      cultivatorPaisa += remainder;
    } else {
      ownerPaisa += remainder;
    }
  }
  assert(ownerPaisa + cultivatorPaisa == totalPaisa);
  return (ownerPaisa: ownerPaisa, cultivatorPaisa: cultivatorPaisa);
}

/// One batai sharecropping agreement: the TERMS of the split.
class BataiAgreement {
  final int? id;
  final FarmerRole farmerRole;
  final int otherPartyId;
  final int? farmId;
  final int? fieldId;
  final int? cropSeasonId;
  final int ownerSharePercent;
  final int cultivatorSharePercent;

  /// Free text: who bears which expenses (deliberately unstructured).
  final String? expenseNote;
  final String startDate; // yyyy-MM-dd
  final String? endDate; // yyyy-MM-dd
  final BataiStatus status;
  final String? notes;
  final String createdAt;

  BataiAgreement({
    this.id,
    required this.farmerRole,
    required this.otherPartyId,
    this.farmId,
    this.fieldId,
    this.cropSeasonId,
    required this.ownerSharePercent,
    required this.cultivatorSharePercent,
    this.expenseNote,
    required this.startDate,
    this.endDate,
    this.status = BataiStatus.active,
    this.notes,
    required this.createdAt,
  });

  /// "My" share percent, from OUR farmer's perspective.
  int get mySharePercent => farmerRole == FarmerRole.landowner
      ? ownerSharePercent
      : cultivatorSharePercent;

  /// The other party's share percent.
  int get otherSharePercent => farmerRole == FarmerRole.landowner
      ? cultivatorSharePercent
      : ownerSharePercent;

  /// Splits [totalPaisa] per the rounding rule.
  ({int ownerPaisa, int cultivatorPaisa}) split(int totalPaisa) =>
      splitBatai(totalPaisa, ownerSharePercent);

  /// My paisa out of a [totalPaisa] settlement, role-aware.
  int mySharePaisa(int totalPaisa) {
    final s = split(totalPaisa);
    return farmerRole == FarmerRole.landowner ? s.ownerPaisa : s.cultivatorPaisa;
  }

  /// The other party's paisa out of a [totalPaisa] settlement, role-aware.
  int otherSharePaisa(int totalPaisa) {
    final s = split(totalPaisa);
    return farmerRole == FarmerRole.landowner
        ? s.cultivatorPaisa
        : s.ownerPaisa;
  }

  Map<String, dynamic> toMap() => {
        'id': id,
        'farmer_role': farmerRoleToString(farmerRole),
        'other_party_id': otherPartyId,
        'farm_id': farmId,
        'field_id': fieldId,
        'crop_season_id': cropSeasonId,
        'owner_share_percent': ownerSharePercent,
        'cultivator_share_percent': cultivatorSharePercent,
        'expense_note': expenseNote,
        'start_date': startDate,
        'end_date': endDate,
        'status': bataiStatusToString(status),
        'notes': notes,
        'created_at': createdAt,
      };

  factory BataiAgreement.fromMap(Map<String, dynamic> map) => BataiAgreement(
        id: map['id'] as int?,
        farmerRole: farmerRoleFromString(map['farmer_role'] as String),
        otherPartyId: map['other_party_id'] as int,
        farmId: map['farm_id'] as int?,
        fieldId: map['field_id'] as int?,
        cropSeasonId: map['crop_season_id'] as int?,
        ownerSharePercent: map['owner_share_percent'] as int,
        cultivatorSharePercent: map['cultivator_share_percent'] as int,
        expenseNote: map['expense_note'] as String?,
        startDate: map['start_date'] as String,
        endDate: map['end_date'] as String?,
        status: bataiStatusFromString(map['status'] as String),
        notes: map['notes'] as String?,
        createdAt: map['created_at'] as String,
      );
}

/// One settlement (چکتائی): an append-only record of a split harvest/sale.
///
/// [ownerPaisa] + [cultivatorPaisa] == [totalPaisa] is guaranteed by the
/// provider's [splitBatai] and by the DB CHECK constraint.
class BataiSettlement {
  final int? id;
  final int agreementId;
  final int? harvestId;
  final int? saleId;
  final int totalPaisa;
  final int ownerPaisa;
  final int cultivatorPaisa;
  final String settleDate; // yyyy-MM-dd
  final String? note;
  final String createdAt;

  BataiSettlement({
    this.id,
    required this.agreementId,
    this.harvestId,
    this.saleId,
    required this.totalPaisa,
    required this.ownerPaisa,
    required this.cultivatorPaisa,
    required this.settleDate,
    this.note,
    required this.createdAt,
  });

  Map<String, dynamic> toMap() => {
        'id': id,
        'agreement_id': agreementId,
        'harvest_id': harvestId,
        'sale_id': saleId,
        'total_paisa': totalPaisa,
        'owner_paisa': ownerPaisa,
        'cultivator_paisa': cultivatorPaisa,
        'settle_date': settleDate,
        'note': note,
        'created_at': createdAt,
      };

  factory BataiSettlement.fromMap(Map<String, dynamic> map) => BataiSettlement(
        id: map['id'] as int?,
        agreementId: map['agreement_id'] as int,
        harvestId: map['harvest_id'] as int?,
        saleId: map['sale_id'] as int?,
        totalPaisa: map['total_paisa'] as int,
        ownerPaisa: map['owner_paisa'] as int,
        cultivatorPaisa: map['cultivator_paisa'] as int,
        settleDate: map['settle_date'] as String,
        note: map['note'] as String?,
        createdAt: map['created_at'] as String,
      );
}

/// An agreement plus the resolved display names for the list screen
/// (LEFT JOINs — any of these may be null when the link was not set).
class BataiAgreementSummary {
  final BataiAgreement agreement;
  final String? partyName;
  final String? cropName;
  final String? farmName;
  final String? fieldName;

  BataiAgreementSummary({
    required this.agreement,
    this.partyName,
    this.cropName,
    this.farmName,
    this.fieldName,
  });

  factory BataiAgreementSummary.fromMap(Map<String, dynamic> map) =>
      BataiAgreementSummary(
        agreement: BataiAgreement.fromMap(map),
        partyName: map['party_name'] as String?,
        cropName: map['crop_name'] as String?,
        farmName: map['farm_name'] as String?,
        fieldName: map['field_name'] as String?,
      );
}
