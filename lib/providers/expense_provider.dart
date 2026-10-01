import 'package:flutter/material.dart';
import '../database/db_helper.dart';
import '../models/models.dart';
import '../services/audit_service.dart';
import '../services/money.dart';

class ExpenseProvider extends ChangeNotifier {
  List<Expense> _expenses = [];

  List<Expense> get expenses => _expenses;

  /// Last load failure, if any. Sections show it as a retryable Urdu error.
  String? _errorMessage;
  String? get errorMessage => _errorMessage;

  /// Total in INTEGER paisa.
  int get totalExpensesPaisa =>
      _expenses.fold(0, (sum, item) => sum + item.amountPaisa);

  // Urdu Category Map
  final Map<String, String> expenseCategories = {
    'Fertilizer': 'کھاد (Fertilizer)',
    'Seeds': 'بیج (Seeds)',
    'Sprays': 'سپرے (Sprays)',
    'Water': 'پانی (Water)',
    'Electricity': 'بجلی (Electricity)',
    'Diesel': 'ڈیزل (Diesel)',
    'Labour': 'مزدور (Labour)',
    'Machinery': 'مشینری (Machinery)',
    'Transportation': 'ٹرانسپورٹ (Transportation)',
    'Land Rent': 'زمین کا ٹھیکہ (Land Rent)',
    'Theka Expense': 'ٹھیکہ خرچہ (Theka Expense)',
    'Harvest Expenses': 'کٹائی کے خرچے (Harvest Expenses)',
    'Ushr Expense': 'عشر کا خرچہ (Ushr Expense)',
    'Market Expenses': 'منڈی کے خرچے (Market Expenses)',
    'Crop Medicine': 'فصل کی دوا (Crop Medicine)',
    'Miscellaneous': 'متفرق (Miscellaneous)',
  };

  Future<void> fetchExpenses() async {
    _errorMessage = null;
    try {
      await _fetchExpenses();
    } catch (_) {
      _errorMessage = 'اخراجات لوڈ نہیں ہو سکے۔ دوبارہ کوشش کریں۔';
      notifyListeners();
    }
  }

  Future<void> _fetchExpenses() async {
    final db = await DatabaseHelper.instance.database;
    final List<Map<String, dynamic>> maps = await db.query(
      'expenses',
      where: 'deleted_at IS NULL',
      orderBy: 'id DESC',
    );
    _expenses = List.generate(maps.length, (i) => Expense.fromMap(maps[i]));
    notifyListeners();
  }

  String _detail(String category, int amountPaisa) =>
      'خرچ: ${expenseCategories[category] ?? category} — ${Money(amountPaisa).format()}';

  Future<int> addExpense({
    required String category,
    required int amountPaisa,
    required String date,
    String? description,
    int? farmId,
    int? fieldId,
    int? cropSeasonId,
  }) async {
    final db = await DatabaseHelper.instance.database;
    final newExpense = Expense(
      category: category,
      amountPaisa: amountPaisa,
      date: date,
      description: description,
      farmId: farmId,
      fieldId: fieldId,
      cropSeasonId: cropSeasonId,
    );
    final id = await db.transaction((txn) async {
      final newId = await txn.insert('expenses', newExpense.toMap());
      await AuditService.log(
        txn,
        table: 'expenses',
        rowId: newId,
        action: AuditService.create,
        details: _detail(category, amountPaisa),
      );
      return newId;
    });
    await fetchExpenses();
    return id;
  }

  Future<void> updateExpense({
    required int id,
    required String category,
    required int amountPaisa,
    required String date,
    String? description,
    int? farmId,
    int? fieldId,
    int? cropSeasonId,
  }) async {
    final db = await DatabaseHelper.instance.database;
    await db.transaction((txn) async {
      await txn.update(
        'expenses',
        Expense(
          id: id,
          category: category,
          amountPaisa: amountPaisa,
          date: date,
          description: description,
          farmId: farmId,
          fieldId: fieldId,
          cropSeasonId: cropSeasonId,
        ).toMap(),
        where: 'id = ?',
        whereArgs: [id],
      );
      await AuditService.log(
        txn,
        table: 'expenses',
        rowId: id,
        action: AuditService.update,
        details: _detail(category, amountPaisa),
      );
    });
    await fetchExpenses();
  }

  /// Soft delete: the row is hidden everywhere but kept for history and the
  /// recycle bin. Callers keep calling [deleteExpense] — the name is
  /// unchanged on purpose.
  Future<void> deleteExpense(int id) async {
    final db = await DatabaseHelper.instance.database;
    await db.transaction((txn) async {
      final existing = await txn.query(
        'expenses',
        where: 'id = ?',
        whereArgs: [id],
      );
      if (existing.isEmpty) return;
      final row = existing.first;
      await txn.update(
        'expenses',
        {'deleted_at': DateTime.now().toIso8601String()},
        where: 'id = ?',
        whereArgs: [id],
      );
      await AuditService.log(
        txn,
        table: 'expenses',
        rowId: id,
        action: AuditService.softDelete,
        details: _detail(
          (row['category'] ?? '') as String,
          (row['amount_paisa'] as num).toInt(),
        ),
      );
    });
    await fetchExpenses();
  }

  /// Restores a soft-deleted expense (recycle bin only).
  Future<void> restoreExpense(int id) async {
    final db = await DatabaseHelper.instance.database;
    await db.transaction((txn) async {
      await txn.update(
        'expenses',
        {'deleted_at': null},
        where: 'id = ?',
        whereArgs: [id],
      );
      await AuditService.log(
        txn,
        table: 'expenses',
        rowId: id,
        action: AuditService.restore,
        details: 'خرچ بحال کیا گیا',
      );
    });
    await fetchExpenses();
  }

  /// Permanent delete — offered ONLY from the recycle bin, with the caller's
  /// destructive confirmation. The audit log keeps the record.
  Future<void> permanentDeleteExpense(int id) async {
    final db = await DatabaseHelper.instance.database;
    await db.transaction((txn) async {
      await txn.delete(
        'expenses',
        where: 'id = ?',
        whereArgs: [id],
      );
      await AuditService.log(
        txn,
        table: 'expenses',
        rowId: id,
        action: AuditService.permanentDelete,
        details: 'خرچ مستقل حذف کیا گیا',
      );
    });
    await fetchExpenses();
  }
}
