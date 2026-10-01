class Farm {
  final int? id;
  final String name;
  final double totalArea;
  final String createdAt;

  Farm({
    this.id,
    required this.name,
    required this.totalArea,
    required this.createdAt,
  });

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'name': name,
      'total_area': totalArea,
      'created_at': createdAt,
    };
  }

  factory Farm.fromMap(Map<String, dynamic> map) {
    return Farm(
      id: map['id'],
      name: map['name'],
      totalArea: map['total_area'],
      createdAt: map['created_at'],
    );
  }
}

class Field {
  final int? id;
  final int farmId;
  final String name;
  final double sizeAcres;
  final int canalWaterAvailable;
  final int tubeWellAvailable;
  final String? location;

  Field({
    this.id,
    required this.farmId,
    required this.name,
    required this.sizeAcres,
    this.canalWaterAvailable = 0,
    this.tubeWellAvailable = 0,
    this.location,
  });

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'farm_id': farmId,
      'name': name,
      'size_acres': sizeAcres,
      'canal_water_available': canalWaterAvailable,
      'tube_well_available': tubeWellAvailable,
      'location': location,
    };
  }

  factory Field.fromMap(Map<String, dynamic> map) {
    return Field(
      id: map['id'],
      farmId: map['farm_id'],
      name: map['name'],
      sizeAcres: map['size_acres'],
      canalWaterAvailable: map['canal_water_available'],
      tubeWellAvailable: map['tube_well_available'],
      location: map['location'],
    );
  }
}

class CropSeason {
  final int? id;
  final int fieldId;
  final String cropName;
  final String variety;
  final String status; // e.g., 'Active', 'Harvested'
  final String startDate;

  CropSeason({
    this.id,
    required this.fieldId,
    required this.cropName,
    required this.variety,
    required this.status,
    required this.startDate,
  });

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'field_id': fieldId,
      'crop_name': cropName,
      'variety': variety,
      'status': status,
      'start_date': startDate,
    };
  }

  factory CropSeason.fromMap(Map<String, dynamic> map) {
    return CropSeason(
      id: map['id'],
      fieldId: map['field_id'],
      cropName: map['crop_name'],
      variety: map['variety'],
      status: map['status'],
      startDate: map['start_date'],
    );
  }
}

class Expense {
  final int? id;
  final String category;

  /// Amount in INTEGER paisa. Never a double: exact money arithmetic.
  final int amountPaisa;
  final String date;
  final String? description;

  /// Optional links to where the money was spent. Nullable: historical
  /// expenses were recorded without links, and links are cleared
  /// (SET NULL) — never cascaded — when the farm/field/crop is deleted.
  final int? farmId;
  final int? fieldId;
  final int? cropSeasonId;

  /// ISO timestamp of soft deletion; NULL = live row.
  /// Read from the DB but never written via [toMap] — updates must not
  /// accidentally resurrect a soft-deleted row.
  final String? deletedAt;

  Expense({
    this.id,
    required this.category,
    required this.amountPaisa,
    required this.date,
    this.description,
    this.farmId,
    this.fieldId,
    this.cropSeasonId,
    this.deletedAt,
  });

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'category': category,
      'amount_paisa': amountPaisa,
      'date': date,
      'description': description,
      'farm_id': farmId,
      'field_id': fieldId,
      'crop_season_id': cropSeasonId,
    };
  }

  factory Expense.fromMap(Map<String, dynamic> map) {
    return Expense(
      id: map['id'],
      category: map['category'],
      amountPaisa: map['amount_paisa'] as int,
      date: map['date'],
      description: map['description'],
      farmId: map['farm_id'],
      fieldId: map['field_id'],
      cropSeasonId: map['crop_season_id'],
      deletedAt: map['deleted_at'] as String?,
    );
  }
}

class Inventory {
  final int? id;
  final String category; // e.g., Fertilizer, Seed, Spray
  final String name;
  final String unit;
  final double quantity;

  /// Cost of one unit in INTEGER paisa. Never a double.
  final int costPerUnitPaisa;

  /// Farmer-entered weight of ONE package unit in kg (e.g. one bag = 50).
  /// NULL means unknown — conversions must never assume a value.
  final double? weightPerUnitKg;

  Inventory({
    this.id,
    required this.category,
    required this.name,
    required this.unit,
    required this.quantity,
    required this.costPerUnitPaisa,
    this.weightPerUnitKg,
  });

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'category': category,
      'name': name,
      'unit': unit,
      'quantity': quantity,
      'cost_per_unit_paisa': costPerUnitPaisa,
      'weight_per_unit_kg': weightPerUnitKg,
    };
  }

  factory Inventory.fromMap(Map<String, dynamic> map) {
    return Inventory(
      id: map['id'],
      category: map['category'],
      name: map['name'],
      unit: map['unit'],
      quantity: map['quantity'],
      costPerUnitPaisa: map['cost_per_unit_paisa'] as int,
      weightPerUnitKg:
          map['weight_per_unit_kg'] == null
              ? null
              : (map['weight_per_unit_kg'] as num).toDouble(),
    );
  }
}

/// One immutable row in the inventory ledger. `quantity` is signed in the
/// item's own unit: positive = stock in, negative = stock out.
class InventoryTransaction {
  final int? id;
  final int inventoryId;
  final String type; // purchase | usage | adjustment | opening_balance
  final double quantity;
  final String unit;

  /// Unit price in INTEGER paisa (nullable: adjustments may carry no price).
  final int? unitPricePaisa;

  /// Total in INTEGER paisa (signed like [quantity]).
  final int? totalAmountPaisa;
  final int? activityId;
  final String date;
  final String? notes;
  final String createdAt;

  InventoryTransaction({
    this.id,
    required this.inventoryId,
    required this.type,
    required this.quantity,
    required this.unit,
    this.unitPricePaisa,
    this.totalAmountPaisa,
    this.activityId,
    required this.date,
    this.notes,
    required this.createdAt,
  });

  /// Urdu label for the transaction type, for display.
  String get typeUrdu {
    switch (type) {
      case 'purchase':
        return 'خریداری';
      case 'usage':
        return 'استعمال';
      case 'adjustment':
        return 'تصحیح';
      case 'opening_balance':
        return 'ابتدائی بیلنس';
      default:
        return type;
    }
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'inventory_id': inventoryId,
      'type': type,
      'quantity': quantity,
      'unit': unit,
      'unit_price_paisa': unitPricePaisa,
      'total_amount_paisa': totalAmountPaisa,
      'activity_id': activityId,
      'date': date,
      'notes': notes,
      'created_at': createdAt,
    };
  }

  factory InventoryTransaction.fromMap(Map<String, dynamic> map) {
    return InventoryTransaction(
      id: map['id'],
      inventoryId: map['inventory_id'],
      type: map['type'],
      quantity: (map['quantity'] as num).toDouble(),
      unit: map['unit'],
      unitPricePaisa: map['unit_price_paisa'] as int?,
      totalAmountPaisa: map['total_amount_paisa'] as int?,
      activityId: map['activity_id'],
      date: map['date'],
      notes: map['notes'],
      createdAt: map['created_at'],
    );
  }
}

class Activity {
  final int? id;
  final int cropSeasonId;
  final String activityType; // e.g., Irrigation, Fertilizer
  final String date;
  final String? details;
  final int? expenseId;
  final String? expenseCategory;
  final String? inventoryCategory;
  final String? inventoryName;
  final String? inventoryUnit;
  final double? inventoryQuantity;

  /// Exact inventory row this activity consumed. Preferred over the
  /// category/name/unit snapshot for restores; may be null on old rows.
  final int? inventoryItemId;
  final bool? _isCompleted;

  bool get isCompleted => _isCompleted ?? false;

  Activity({
    this.id,
    required this.cropSeasonId,
    required this.activityType,
    required this.date,
    this.details,
    this.expenseId,
    this.expenseCategory,
    this.inventoryCategory,
    this.inventoryName,
    this.inventoryUnit,
    this.inventoryQuantity,
    this.inventoryItemId,
    bool? isCompleted,
  }) : _isCompleted = isCompleted ?? false;

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'crop_season_id': cropSeasonId,
      'activity_type': activityType,
      'date': date,
      'details': details,
      'expense_id': expenseId,
      'expense_category': expenseCategory,
      'inventory_category': inventoryCategory,
      'inventory_name': inventoryName,
      'inventory_unit': inventoryUnit,
      'inventory_quantity': inventoryQuantity,
      'inventory_item_id': inventoryItemId,
      'is_completed': isCompleted ? 1 : 0,
    };
  }

  factory Activity.fromMap(Map<String, dynamic> map) {
    return Activity(
      id: map['id'],
      cropSeasonId: map['crop_season_id'],
      activityType: map['activity_type'],
      date: map['date'],
      details: map['details'],
      expenseId: map['expense_id'],
      expenseCategory: map['expense_category'],
      inventoryCategory: map['inventory_category'],
      inventoryName: map['inventory_name'],
      inventoryUnit: map['inventory_unit'],
      inventoryQuantity:
          map['inventory_quantity'] == null
              ? null
              : (map['inventory_quantity'] as num).toDouble(),
      inventoryItemId: map['inventory_item_id'],
      isCompleted: (map['is_completed'] ?? 0) == 1,
    );
  }
}

class Harvest {
  final int? id;
  final int cropSeasonId;
  final double quantity;
  final String unit;
  final String date;

  /// Rate per unit in INTEGER paisa.
  final int ratePerUnitPaisa;

  /// The five expense buckets in INTEGER paisa.
  final int transportationExpensePaisa;
  final int labourExpensePaisa;
  final int harvestingExpensePaisa;
  final int commissionExpensePaisa;
  final int otherExpensePaisa;
  final String? buyerName;
  final String paymentStatus; // 'Paid', 'Pending', 'Partial'
  final String? notes;
  final int? expenseId;

  /// ISO timestamp of soft deletion; NULL = live row. Never in [toMap].
  final String? deletedAt;

  Harvest({
    this.id,
    required this.cropSeasonId,
    required this.quantity,
    required this.unit,
    required this.date,
    this.ratePerUnitPaisa = 0,
    this.transportationExpensePaisa = 0,
    this.labourExpensePaisa = 0,
    this.harvestingExpensePaisa = 0,
    this.commissionExpensePaisa = 0,
    this.otherExpensePaisa = 0,
    this.buyerName,
    this.paymentStatus = 'Pending',
    this.notes,
    this.expenseId,
    this.deletedAt,
  });

  /// Computed — NEVER stored (storing them caused drift bugs when sales
  /// were edited). All in INTEGER paisa; per-unit x quantity rounds to the
  /// nearest paisa (half away from zero), exactly like the DB backfill.
  int get grossPaisa => (quantity * ratePerUnitPaisa).round();
  int get totalExpensePaisa =>
      transportationExpensePaisa +
      labourExpensePaisa +
      harvestingExpensePaisa +
      commissionExpensePaisa +
      otherExpensePaisa;
  int get netIncomePaisa => grossPaisa - totalExpensePaisa;

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'crop_season_id': cropSeasonId,
      'quantity': quantity,
      'unit': unit,
      'date': date,
      'rate_per_unit_paisa': ratePerUnitPaisa,
      'transportation_expense_paisa': transportationExpensePaisa,
      'labour_expense_paisa': labourExpensePaisa,
      'harvesting_expense_paisa': harvestingExpensePaisa,
      'commission_expense_paisa': commissionExpensePaisa,
      'other_expense_paisa': otherExpensePaisa,
      'buyer_name': buyerName,
      'payment_status': paymentStatus,
      'notes': notes,
      'expense_id': expenseId,
    };
  }

  factory Harvest.fromMap(Map<String, dynamic> map) {
    return Harvest(
      id: map['id'],
      cropSeasonId: map['crop_season_id'],
      quantity: (map['quantity'] as num).toDouble(),
      unit: map['unit'],
      date: map['date'],
      ratePerUnitPaisa: (map['rate_per_unit_paisa'] ?? 0) as int,
      transportationExpensePaisa:
          (map['transportation_expense_paisa'] ?? 0) as int,
      labourExpensePaisa: (map['labour_expense_paisa'] ?? 0) as int,
      harvestingExpensePaisa: (map['harvesting_expense_paisa'] ?? 0) as int,
      commissionExpensePaisa: (map['commission_expense_paisa'] ?? 0) as int,
      otherExpensePaisa: (map['other_expense_paisa'] ?? 0) as int,
      buyerName: map['buyer_name'],
      paymentStatus: map['payment_status'] ?? 'Pending',
      notes: map['notes'],
      expenseId: map['expense_id'],
      deletedAt: map['deleted_at'] as String?,
    );
  }
}

class Sale {
  final int? id;
  final int harvestId;
  final String? buyerName;
  final double quantity;

  /// Price per unit in INTEGER paisa.
  final int pricePerUnitPaisa;

  /// Total in INTEGER paisa.
  final int totalAmountPaisa;
  final String date;

  /// ISO timestamp of soft deletion; NULL = live row. Never in [toMap].
  final String? deletedAt;

  Sale({
    this.id,
    required this.harvestId,
    this.buyerName,
    required this.quantity,
    required this.pricePerUnitPaisa,
    required this.totalAmountPaisa,
    required this.date,
    this.deletedAt,
  });

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'harvest_id': harvestId,
      'buyer_name': buyerName,
      'quantity': quantity,
      'price_per_unit_paisa': pricePerUnitPaisa,
      'total_amount_paisa': totalAmountPaisa,
      'date': date,
    };
  }

  factory Sale.fromMap(Map<String, dynamic> map) {
    return Sale(
      id: map['id'],
      harvestId: map['harvest_id'],
      buyerName: map['buyer_name'],
      quantity: map['quantity'],
      pricePerUnitPaisa: map['price_per_unit_paisa'] as int,
      totalAmountPaisa: map['total_amount_paisa'] as int,
      date: map['date'],
      deletedAt: map['deleted_at'] as String?,
    );
  }
}

class Theka {
  final int? id;
  final int farmId;
  final int? fieldId;

  /// Total in INTEGER paisa.
  final int totalAmountPaisa;
  final String durationType; // 'Seasonal', 'Yearly', 'Custom'
  final String? durationDetails; // e.g. 'Rabi 2026'
  final String paymentMethod; // 'Full', 'Installment'
  final String? startDate;
  final String? endDate;
  final String createdAt;

  Theka({
    this.id,
    required this.farmId,
    this.fieldId,
    required this.totalAmountPaisa,
    required this.durationType,
    this.durationDetails,
    required this.paymentMethod,
    this.startDate,
    this.endDate,
    required this.createdAt,
  });

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'farm_id': farmId,
      'field_id': fieldId,
      'total_amount_paisa': totalAmountPaisa,
      'duration_type': durationType,
      'duration_details': durationDetails,
      'payment_method': paymentMethod,
      'start_date': startDate,
      'end_date': endDate,
      'created_at': createdAt,
    };
  }

  factory Theka.fromMap(Map<String, dynamic> map) {
    return Theka(
      id: map['id'],
      farmId: map['farm_id'],
      fieldId: map['field_id'],
      totalAmountPaisa: map['total_amount_paisa'] as int,
      durationType: map['duration_type'],
      durationDetails: map['duration_details'],
      paymentMethod: map['payment_method'],
      startDate: map['start_date'],
      endDate: map['end_date'],
      createdAt: map['created_at'],
    );
  }
}

class ThekaInstallment {
  final int? id;
  final int thekaId;

  /// Installment amount in INTEGER paisa.
  final int amountPaisa;
  final String dueDate;
  final String status; // 'Pending', 'Paid', 'Partially Paid'
  /// Paid so far in INTEGER paisa (accumulates; never exceeds [amountPaisa]).
  final int paidAmountPaisa;
  final String? paidDate;
  final int? expenseId;

  ThekaInstallment({
    this.id,
    required this.thekaId,
    required this.amountPaisa,
    required this.dueDate,
    required this.status,
    this.paidAmountPaisa = 0,
    this.paidDate,
    this.expenseId,
  });

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'theka_id': thekaId,
      'amount_paisa': amountPaisa,
      'due_date': dueDate,
      'status': status,
      'paid_amount_paisa': paidAmountPaisa,
      'paid_date': paidDate,
      'expense_id': expenseId,
    };
  }

  factory ThekaInstallment.fromMap(Map<String, dynamic> map) {
    return ThekaInstallment(
      id: map['id'],
      thekaId: map['theka_id'],
      amountPaisa: map['amount_paisa'] as int,
      dueDate: map['due_date'],
      status: map['status'],
      paidAmountPaisa:
          map['paid_amount_paisa'] == null
              ? 0
              : map['paid_amount_paisa'] as int,
      paidDate: map['paid_date'],
      expenseId: map['expense_id'],
    );
  }
}

class UshrRecord {
  final int? id;
  final int cropSeasonId;
  final int? harvestId;
  final double harvestQty;

  /// Market value in INTEGER paisa.
  final int marketValuePaisa;
  final String ushrMethod; // 'Natural', 'Artificial', 'Custom'
  final double ushrPercentage;

  /// Ushr due in INTEGER paisa.
  final int ushrAmountPaisa;
  final String status; // 'Paid', 'Pending'
  final String? datePaid;
  final String? notes;
  final int? expenseId;
  final String payMethod; // 'Cash', 'Crop', 'Mixed'
  final double qtyPaid;

  /// Cash paid in INTEGER paisa.
  final int cashPaidPaisa;

  /// Rate per unit for crop-paid ushr, in INTEGER paisa.
  final int ratePerUnitPaisa;

  UshrRecord({
    this.id,
    required this.cropSeasonId,
    this.harvestId,
    required this.harvestQty,
    required this.marketValuePaisa,
    required this.ushrMethod,
    required this.ushrPercentage,
    required this.ushrAmountPaisa,
    required this.status,
    this.datePaid,
    this.notes,
    this.expenseId,
    this.payMethod = 'Cash',
    this.qtyPaid = 0.0,
    this.cashPaidPaisa = 0,
    this.ratePerUnitPaisa = 0,
  });

  /// Computed — NEVER stored (storing it caused drift when payments were
  /// edited). In INTEGER paisa: ushr due minus cash paid minus crop paid
  /// (qty x rate, rounded to the nearest paisa).
  int get remainingBalancePaisa =>
      ushrAmountPaisa - cashPaidPaisa - (qtyPaid * ratePerUnitPaisa).round();

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'crop_season_id': cropSeasonId,
      'harvest_id': harvestId,
      'harvest_qty': harvestQty,
      'market_value_paisa': marketValuePaisa,
      'ushr_method': ushrMethod,
      'ushr_percentage': ushrPercentage,
      'ushr_amount_paisa': ushrAmountPaisa,
      'status': status,
      'date_paid': datePaid,
      'notes': notes,
      'expense_id': expenseId,
      'pay_method': payMethod,
      'qty_paid': qtyPaid,
      'cash_paid_paisa': cashPaidPaisa,
      'rate_per_unit_paisa': ratePerUnitPaisa,
    };
  }

  factory UshrRecord.fromMap(Map<String, dynamic> map) {
    return UshrRecord(
      id: map['id'],
      cropSeasonId: map['crop_season_id'],
      harvestId: map['harvest_id'],
      harvestQty: (map['harvest_qty'] as num).toDouble(),
      marketValuePaisa: map['market_value_paisa'] as int,
      ushrMethod: map['ushr_method'],
      ushrPercentage: (map['ushr_percentage'] as num).toDouble(),
      ushrAmountPaisa: map['ushr_amount_paisa'] as int,
      status: map['status'] ?? 'Pending',
      datePaid: map['date_paid'],
      notes: map['notes'],
      expenseId: map['expense_id'],
      payMethod: map['pay_method'] ?? 'Cash',
      qtyPaid: (map['qty_paid'] ?? 0.0 as num).toDouble(),
      cashPaidPaisa: (map['cash_paid_paisa'] ?? 0) as int,
      ratePerUnitPaisa: (map['rate_per_unit_paisa'] ?? 0) as int,
    );
  }
}
