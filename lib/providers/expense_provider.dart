import 'package:flutter/material.dart';
import '../database/db_helper.dart';
import '../models/models.dart';

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
    final List<Map<String, dynamic>> maps = await db.query('expenses', orderBy: 'id DESC');
    _expenses = List.generate(maps.length, (i) => Expense.fromMap(maps[i]));
    notifyListeners();
  }

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
    final id = await db.insert('expenses', newExpense.toMap());
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
    await db.update(
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
    await fetchExpenses();
  }

  Future<void> deleteExpense(int id) async {
    final db = await DatabaseHelper.instance.database;
    await db.delete(
      'expenses',
      where: 'id = ?',
      whereArgs: [id],
    );
    await fetchExpenses();
  }
}
