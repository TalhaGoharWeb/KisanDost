import 'package:flutter/material.dart';
import '../database/db_helper.dart';
import '../models/models.dart';

class ExpenseProvider extends ChangeNotifier {
  List<Expense> _expenses = [];

  List<Expense> get expenses => _expenses;

  double get totalExpenses => _expenses.fold(0.0, (sum, item) => sum + item.amount);

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
    final db = await DatabaseHelper.instance.database;
    final List<Map<String, dynamic>> maps = await db.query('expenses', orderBy: 'id DESC');
    _expenses = List.generate(maps.length, (i) => Expense.fromMap(maps[i]));
    notifyListeners();
  }

  Future<int> addExpense({
    required String category,
    required double amount,
    required String date,
    String? description,
  }) async {
    final db = await DatabaseHelper.instance.database;
    final newExpense = Expense(
      category: category,
      amount: amount,
      date: date,
      description: description,
    );
    final id = await db.insert('expenses', newExpense.toMap());
    await fetchExpenses();
    return id;
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
