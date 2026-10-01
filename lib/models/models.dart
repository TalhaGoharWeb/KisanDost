class Farm {
  final int? id;
  final String name;
  final double totalArea;
  final String createdAt;

  Farm({this.id, required this.name, required this.totalArea, required this.createdAt});

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
  final double amount;
  final String date;
  final String? description;

  /// Optional links to where the money was spent. Nullable: historical
  /// expenses were recorded without links, and links are cleared
  /// (SET NULL) — never cascaded — when the farm/field/crop is deleted.
  final int? farmId;
  final int? fieldId;
  final int? cropSeasonId;

  Expense({
    this.id,
    required this.category,
    required this.amount,
    required this.date,
    this.description,
    this.farmId,
    this.fieldId,
    this.cropSeasonId,
  });

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'category': category,
      'amount': amount,
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
      amount: map['amount'],
      date: map['date'],
      description: map['description'],
      farmId: map['farm_id'],
      fieldId: map['field_id'],
      cropSeasonId: map['crop_season_id'],
    );
  }
}

class Inventory {
  final int? id;
  final String category; // e.g., Fertilizer, Seed, Spray
  final String name;
  final String unit;
  final double quantity;
  final double costPerUnit;

  Inventory({
    this.id,
    required this.category,
    required this.name,
    required this.unit,
    required this.quantity,
    required this.costPerUnit,
  });

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'category': category,
      'name': name,
      'unit': unit,
      'quantity': quantity,
      'cost_per_unit': costPerUnit,
    };
  }

  factory Inventory.fromMap(Map<String, dynamic> map) {
    return Inventory(
      id: map['id'],
      category: map['category'],
      name: map['name'],
      unit: map['unit'],
      quantity: map['quantity'],
      costPerUnit: map['cost_per_unit'],
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
      inventoryQuantity: map['inventory_quantity'] == null
          ? null
          : (map['inventory_quantity'] as num).toDouble(),
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
  final double ratePerUnit;
  final double grossAmount;
  final double transportationExpense;
  final double labourExpense;
  final double harvestingExpense;
  final double commissionExpense;
  final double otherExpense;
  final double totalExpense;
  final double netIncome;
  final String? buyerName;
  final String paymentStatus; // 'Paid', 'Pending', 'Partial'
  final String? notes;
  final int? expenseId;

  Harvest({
    this.id,
    required this.cropSeasonId,
    required this.quantity,
    required this.unit,
    required this.date,
    this.ratePerUnit = 0.0,
    this.grossAmount = 0.0,
    this.transportationExpense = 0.0,
    this.labourExpense = 0.0,
    this.harvestingExpense = 0.0,
    this.commissionExpense = 0.0,
    this.otherExpense = 0.0,
    this.totalExpense = 0.0,
    this.netIncome = 0.0,
    this.buyerName,
    this.paymentStatus = 'Pending',
    this.notes,
    this.expenseId,
  });

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'crop_season_id': cropSeasonId,
      'quantity': quantity,
      'unit': unit,
      'date': date,
      'rate_per_unit': ratePerUnit,
      'gross_amount': grossAmount,
      'transportation_expense': transportationExpense,
      'labour_expense': labourExpense,
      'harvesting_expense': harvestingExpense,
      'commission_expense': commissionExpense,
      'other_expense': otherExpense,
      'total_expense': totalExpense,
      'net_income': netIncome,
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
      ratePerUnit: (map['rate_per_unit'] ?? 0.0 as num).toDouble(),
      grossAmount: (map['gross_amount'] ?? 0.0 as num).toDouble(),
      transportationExpense: (map['transportation_expense'] ?? 0.0 as num).toDouble(),
      labourExpense: (map['labour_expense'] ?? 0.0 as num).toDouble(),
      harvestingExpense: (map['harvesting_expense'] ?? 0.0 as num).toDouble(),
      commissionExpense: (map['commission_expense'] ?? 0.0 as num).toDouble(),
      otherExpense: (map['other_expense'] ?? 0.0 as num).toDouble(),
      totalExpense: (map['total_expense'] ?? 0.0 as num).toDouble(),
      netIncome: (map['net_income'] ?? 0.0 as num).toDouble(),
      buyerName: map['buyer_name'],
      paymentStatus: map['payment_status'] ?? 'Pending',
      notes: map['notes'],
      expenseId: map['expense_id'],
    );
  }
}

class Sale {
  final int? id;
  final int harvestId;
  final String? buyerName;
  final double quantity;
  final double pricePerUnit;
  final double totalAmount;
  final String date;

  Sale({
    this.id,
    required this.harvestId,
    this.buyerName,
    required this.quantity,
    required this.pricePerUnit,
    required this.totalAmount,
    required this.date,
  });

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'harvest_id': harvestId,
      'buyer_name': buyerName,
      'quantity': quantity,
      'price_per_unit': pricePerUnit,
      'total_amount': totalAmount,
      'date': date,
    };
  }

  factory Sale.fromMap(Map<String, dynamic> map) {
    return Sale(
      id: map['id'],
      harvestId: map['harvest_id'],
      buyerName: map['buyer_name'],
      quantity: map['quantity'],
      pricePerUnit: map['price_per_unit'],
      totalAmount: map['total_amount'],
      date: map['date'],
    );
  }
}

class Theka {
  final int? id;
  final int farmId;
  final int? fieldId;
  final double totalAmount;
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
    required this.totalAmount,
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
      'total_amount': totalAmount,
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
      totalAmount: (map['total_amount'] as num).toDouble(),
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
  final double amount;
  final String dueDate;
  final String status; // 'Pending', 'Paid', 'Partially Paid'
  final double paidAmount;
  final String? paidDate;
  final int? expenseId;

  ThekaInstallment({
    this.id,
    required this.thekaId,
    required this.amount,
    required this.dueDate,
    required this.status,
    this.paidAmount = 0.0,
    this.paidDate,
    this.expenseId,
  });

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'theka_id': thekaId,
      'amount': amount,
      'due_date': dueDate,
      'status': status,
      'paid_amount': paidAmount,
      'paid_date': paidDate,
      'expense_id': expenseId,
    };
  }

  factory ThekaInstallment.fromMap(Map<String, dynamic> map) {
    return ThekaInstallment(
      id: map['id'],
      thekaId: map['theka_id'],
      amount: (map['amount'] as num).toDouble(),
      dueDate: map['due_date'],
      status: map['status'],
      paidAmount: map['paid_amount'] == null ? 0.0 : (map['paid_amount'] as num).toDouble(),
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
  final double marketValue;
  final String ushrMethod; // 'Natural', 'Artificial', 'Custom'
  final double ushrPercentage;
  final double ushrAmount;
  final String status; // 'Paid', 'Pending'
  final String? datePaid;
  final String? notes;
  final int? expenseId;
  final String payMethod; // 'Cash', 'Crop', 'Mixed'
  final double qtyPaid;
  final double cashPaid;
  final double remainingBalance;
  final double ratePerUnit;

  UshrRecord({
    this.id,
    required this.cropSeasonId,
    this.harvestId,
    required this.harvestQty,
    required this.marketValue,
    required this.ushrMethod,
    required this.ushrPercentage,
    required this.ushrAmount,
    required this.status,
    this.datePaid,
    this.notes,
    this.expenseId,
    this.payMethod = 'Cash',
    this.qtyPaid = 0.0,
    this.cashPaid = 0.0,
    this.remainingBalance = 0.0,
    this.ratePerUnit = 0.0,
  });

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'crop_season_id': cropSeasonId,
      'harvest_id': harvestId,
      'harvest_qty': harvestQty,
      'market_value': marketValue,
      'ushr_method': ushrMethod,
      'ushr_percentage': ushrPercentage,
      'ushr_amount': ushrAmount,
      'status': status,
      'date_paid': datePaid,
      'notes': notes,
      'expense_id': expenseId,
      'pay_method': payMethod,
      'qty_paid': qtyPaid,
      'cash_paid': cashPaid,
      'remaining_balance': remainingBalance,
      'rate_per_unit': ratePerUnit,
    };
  }

  factory UshrRecord.fromMap(Map<String, dynamic> map) {
    return UshrRecord(
      id: map['id'],
      cropSeasonId: map['crop_season_id'],
      harvestId: map['harvest_id'],
      harvestQty: (map['harvest_qty'] as num).toDouble(),
      marketValue: (map['market_value'] as num).toDouble(),
      ushrMethod: map['ushr_method'],
      ushrPercentage: (map['ushr_percentage'] as num).toDouble(),
      ushrAmount: (map['ushr_amount'] as num).toDouble(),
      status: map['status'] ?? 'Pending',
      datePaid: map['date_paid'],
      notes: map['notes'],
      expenseId: map['expense_id'],
      payMethod: map['pay_method'] ?? 'Cash',
      qtyPaid: (map['qty_paid'] ?? 0.0 as num).toDouble(),
      cashPaid: (map['cash_paid'] ?? 0.0 as num).toDouble(),
      remainingBalance: (map['remaining_balance'] ?? 0.0 as num).toDouble(),
      ratePerUnit: (map['rate_per_unit'] ?? 0.0 as num).toDouble(),
    );
  }
}

