import 'package:flutter/material.dart';
import '../database/db_helper.dart';
import '../models/models.dart';

class ThekaProvider extends ChangeNotifier {
  List<Theka> _thekas = [];
  final Map<int, List<ThekaInstallment>> _thekaInstallments = {}; // thekaId -> installments

  List<Theka> get thekas => _thekas;

  List<ThekaInstallment> getInstallmentsForTheka(int thekaId) {
    return _thekaInstallments[thekaId] ?? [];
  }

  Future<void> fetchThekas() async {
    final db = await DatabaseHelper.instance.database;
    final List<Map<String, dynamic>> maps = await db.query('thekas', orderBy: 'id DESC');
    _thekas = List.generate(maps.length, (i) => Theka.fromMap(maps[i]));

    for (var theka in _thekas) {
      if (theka.id != null) {
        final List<Map<String, dynamic>> instMaps = await db.query(
          'theka_installments',
          where: 'theka_id = ?',
          whereArgs: [theka.id],
          orderBy: 'due_date ASC, id ASC',
        );
        _thekaInstallments[theka.id!] = List.generate(
          instMaps.length,
          (i) => ThekaInstallment.fromMap(instMaps[i]),
        );
      }
    }
    notifyListeners();
  }

  Future<void> addTheka(Theka theka, List<ThekaInstallment> installments) async {
    final db = await DatabaseHelper.instance.database;
    await db.transaction((txn) async {
      final thekaId = await txn.insert('thekas', theka.toMap());
      for (var inst in installments) {
        final newInst = ThekaInstallment(
          thekaId: thekaId,
          amount: inst.amount,
          dueDate: inst.dueDate,
          status: inst.status,
          paidAmount: inst.paidAmount,
          paidDate: inst.paidDate,
          expenseId: inst.expenseId,
        );
        await txn.insert('theka_installments', newInst.toMap());
      }
    });
    await fetchThekas();
  }

  Future<void> deleteTheka(int thekaId) async {
    final db = await DatabaseHelper.instance.database;
    await db.transaction((txn) async {
      // 1. Delete associated expenses
      final List<Map<String, dynamic>> instMaps = await txn.query(
        'theka_installments',
        where: 'theka_id = ?',
        whereArgs: [thekaId],
      );
      for (var inst in instMaps) {
        final expenseId = inst['expense_id'] as int?;
        if (expenseId != null) {
          await txn.delete('expenses', where: 'id = ?', whereArgs: [expenseId]);
        }
      }
      // 2. Delete theka (cascading deletes installments due to db ON DELETE CASCADE)
      await txn.delete('thekas', where: 'id = ?', whereArgs: [thekaId]);
    });
    await fetchThekas();
  }

  Future<void> payInstallment({
    required int installmentId,
    required double paidAmount,
    required String paidDate,
    required String farmName,
    required int installmentIndex,
  }) async {
    final db = await DatabaseHelper.instance.database;
    await db.transaction((txn) async {
      // 1. Fetch current installment
      final List<Map<String, dynamic>> maps = await txn.query(
        'theka_installments',
        where: 'id = ?',
        whereArgs: [installmentId],
      );
      if (maps.isEmpty) return;

      final currentInst = ThekaInstallment.fromMap(maps.first);
      final isFullPayment = paidAmount >= currentInst.amount;
      final newStatus = isFullPayment ? 'Paid' : 'Partially Paid';

      int? expenseId = currentInst.expenseId;
      final String desc = isFullPayment
          ? 'ٹھیکہ ادائیگی: $farmName (قسط نمبر $installmentIndex)'
          : 'ٹھیکہ جزوی ادائیگی: $farmName (قسط نمبر $installmentIndex)';

      if (expenseId == null) {
        // Insert new expense entry
        expenseId = await txn.insert('expenses', {
          'category': 'Land Rent', // standard category
          'amount': paidAmount,
          'date': paidDate,
          'description': desc,
        });
      } else {
        // Update existing expense entry
        await txn.update(
          'expenses',
          {
            'amount': paidAmount,
            'date': paidDate,
            'description': desc,
          },
          where: 'id = ?',
          whereArgs: [expenseId],
        );
      }

      // Update installment
      await txn.update(
        'theka_installments',
        {
          'status': newStatus,
          'paid_amount': paidAmount,
          'paid_date': paidDate,
          'expense_id': expenseId,
        },
        where: 'id = ?',
        whereArgs: [installmentId],
      );
    });
    await fetchThekas();
  }

  Future<void> markInstallmentPending(int installmentId) async {
    final db = await DatabaseHelper.instance.database;
    await db.transaction((txn) async {
      final List<Map<String, dynamic>> maps = await txn.query(
        'theka_installments',
        where: 'id = ?',
        whereArgs: [installmentId],
      );
      if (maps.isEmpty) return;

      final currentInst = ThekaInstallment.fromMap(maps.first);
      final expenseId = currentInst.expenseId;

      if (expenseId != null) {
        await txn.delete('expenses', where: 'id = ?', whereArgs: [expenseId]);
      }

      await txn.update(
        'theka_installments',
        {
          'status': 'Pending',
          'paid_amount': 0.0,
          'paid_date': null,
          'expense_id': null,
        },
        where: 'id = ?',
        whereArgs: [installmentId],
      );
    });
    await fetchThekas();
  }

  Future<void> updateInstallmentSchedule(int thekaId, List<ThekaInstallment> newSchedule) async {
    final db = await DatabaseHelper.instance.database;
    await db.transaction((txn) async {
      // Verify no payments are recorded yet
      final List<Map<String, dynamic>> maps = await txn.query(
        'theka_installments',
        where: 'theka_id = ? AND status != ?',
        whereArgs: [thekaId, 'Pending'],
      );
      if (maps.isNotEmpty) {
        throw Exception('ادائیگیاں ریکارڈ ہونے کی وجہ سے شیڈول تبدیل نہیں کیا جا سکتا۔');
      }

      // Delete old installments
      await txn.delete('theka_installments', where: 'theka_id = ?', whereArgs: [thekaId]);

      // Insert new installments
      for (var inst in newSchedule) {
        final newInst = ThekaInstallment(
          thekaId: thekaId,
          amount: inst.amount,
          dueDate: inst.dueDate,
          status: 'Pending',
          paidAmount: 0.0,
          paidDate: null,
          expenseId: null,
        );
        await txn.insert('theka_installments', newInst.toMap());
      }
    });
    await fetchThekas();
  }
}
