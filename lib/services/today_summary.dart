/// Pure, testable helpers behind the home/TODAY screen.
///
/// All aggregation over provider lists lives here (not in the widget) so the
/// "what needs doing today / money situation / crop situation" logic is unit
/// tested. Money stays in INTEGER paisa throughout — never doubles.
library;

import '../models/models.dart';
import '../providers/task_provider.dart';

/// Urdu weekday names, Monday-first to match [DateTime.weekday].
const List<String> _urduWeekdays = [
  'پیر',
  'منگل',
  'بدھ',
  'جمعرات',
  'جمعہ',
  'ہفتہ',
  'اتوار',
];

/// Urdu month names.
const List<String> _urduMonths = [
  'جنوری',
  'فروری',
  'مارچ',
  'اپریل',
  'مئی',
  'جون',
  'جولائی',
  'اگست',
  'ستمبر',
  'اکتوبر',
  'نومبر',
  'دسمبر',
];

/// Urdu month name for [month] (1-12).
String urduMonthName(int month) => _urduMonths[month - 1];

/// e.g. "جمعرات، 1 اکتوبر 2026". Western digits on purpose: Nastaleeq
/// numerals are hard to scan at a glance.
String urduDateLine(DateTime date) {
  final weekday = _urduWeekdays[date.weekday - 1];
  return '$weekday، ${date.day} ${urduMonthName(date.month)} ${date.year}';
}

/// Short Urdu date, e.g. "1 اکتوبر".
String urduShortDate(DateTime date) =>
    '${date.day} ${urduMonthName(date.month)}';

/// Time of day in words, e.g. "صبح 9:30" / "دوپہر 2:05" / "شام 6:45".
String urduTimeOfDay(DateTime dt) {
  final h = dt.hour;
  final m = dt.minute.toString().padLeft(2, '0');
  final h12 = h % 12 == 0 ? 12 : h % 12;
  final part = h < 5
      ? 'رات'
      : h < 12
          ? 'صبح'
          : h < 17
              ? 'دوپہر'
              : 'شام';
  return '$part $h12:$m';
}

/// Time-of-day greeting in Urdu.
String greetingFor(DateTime now) {
  final h = now.hour;
  if (h >= 5 && h < 12) return 'صبح بخیر';
  if (h >= 17 && h < 22) return 'شام بخیر';
  return 'السلام علیکم';
}

bool isSameDay(DateTime a, DateTime b) =>
    a.year == b.year && a.month == b.month && a.day == b.day;

/// Lenient date parse for stored date strings (ISO or yyyy-MM-dd).
DateTime? tryParseStoredDate(String raw) => DateTime.tryParse(raw);

/// A task is overdue when its time has passed, it is not completed, and it is
/// not currently snoozed into the future. Mirrors the tasks screen semantics.
bool isTaskOverdue(TaskItem task, DateTime now) {
  if (task.isCompleted) return false;
  if (!task.dateTime.isBefore(now)) return false;
  final snoozed = task.snoozedUntil;
  return snoozed == null || snoozed.isBefore(now);
}

/// Due today = scheduled for today's calendar date and not overdue/completed.
bool isTaskDueToday(TaskItem task, DateTime now) {
  if (task.isCompleted || isTaskOverdue(task, now)) return false;
  return isSameDay(task.dateTime, now);
}

/// Today's actionable tasks: overdue first, then due-today, each group by time.
List<TaskItem> todaysTasks(List<TaskItem> tasks, DateTime now) {
  final overdue = tasks.where((t) => isTaskOverdue(t, now)).toList()
    ..sort((a, b) => a.dateTime.compareTo(b.dateTime));
  final dueToday = tasks.where((t) => isTaskDueToday(t, now)).toList()
    ..sort((a, b) => a.dateTime.compareTo(b.dateTime));
  return [...overdue, ...dueToday];
}

/// Total expenses (INTEGER paisa) recorded on [day]'s calendar date.
int expensesOnDayPaisa(List<Expense> expenses, DateTime day) {
  var total = 0;
  for (final e in expenses) {
    final d = tryParseStoredDate(e.date);
    if (d != null && isSameDay(d, day)) total += e.amountPaisa;
  }
  return total;
}

/// Total expenses (INTEGER paisa) recorded in [month]'s calendar month.
int expensesInMonthPaisa(List<Expense> expenses, DateTime month) {
  var total = 0;
  for (final e in expenses) {
    final d = tryParseStoredDate(e.date);
    if (d != null && d.year == month.year && d.month == month.month) {
      total += e.amountPaisa;
    }
  }
  return total;
}

/// Sales cash (INTEGER paisa) recorded in [month]'s calendar month.
int salesInMonthPaisa(List<Sale> sales, DateTime month) {
  var total = 0;
  for (final s in sales) {
    final d = tryParseStoredDate(s.date);
    if (d != null && d.year == month.year && d.month == month.month) {
      total += s.totalAmountPaisa;
    }
  }
  return total;
}

/// Installments with money still owed whose due date is within [withinDays]
/// days from today — overdue unpaid installments included, earliest first.
List<ThekaInstallment> dueSoonInstallments(
  List<ThekaInstallment> installments,
  DateTime now, {
  int withinDays = 7,
}) {
  final today = DateTime(now.year, now.month, now.day);
  final cutoff = today.add(Duration(days: withinDays));
  final due = installments.where((i) {
    if (i.amountPaisa - i.paidAmountPaisa <= 0) return false;
    final d = tryParseStoredDate(i.dueDate);
    if (d == null) return false;
    final dueDay = DateTime(d.year, d.month, d.day);
    return !dueDay.isAfter(cutoff);
  }).toList();
  due.sort((a, b) => a.dueDate.compareTo(b.dueDate));
  return due;
}

/// Remaining payable on an installment, in INTEGER paisa.
int remainingPaisa(ThekaInstallment i) => i.amountPaisa - i.paidAmountPaisa;

/// Total receivable (INTEGER paisa) across party balances: the sum of
/// positive balances — what people owe the farmer.
int totalReceivablePaisa(Map<int, int> balances) {
  var total = 0;
  for (final b in balances.values) {
    if (b > 0) total += b;
  }
  return total;
}

/// Total payable (INTEGER paisa, as a positive number) across party
/// balances: the sum of negative balances — what the farmer owes people.
int totalPayablePaisa(Map<int, int> balances) {
  var total = 0;
  for (final b in balances.values) {
    if (b < 0) total += -b;
  }
  return total;
}
