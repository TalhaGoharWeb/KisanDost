import 'package:sqflite/sqflite.dart';
import '../database/db_helper.dart';
import 'money.dart';
import 'unit_display.dart';

/// One soft-deleted row, as listed in the recycle bin.
class DeletedItem {
  /// 'expenses' | 'sales' | 'harvests' | 'tasks' | 'parties'
  final String table;
  final int id;

  /// Urdu display line, e.g. 'کھاد' or 'پیداوار — گندم'.
  final String title;

  /// Detail line, e.g. an amount + date.
  final String subtitle;
  final String deletedAt;

  const DeletedItem({
    required this.table,
    required this.id,
    required this.title,
    required this.subtitle,
    required this.deletedAt,
  });
}

/// Reads soft-deleted rows for the recycle bin screen.
///
/// Only the five soft-deletable tables are covered: expenses, sales,
/// harvests, tasks, parties. Everything else in the schema is either
/// append-only (ledgers, settlements) or intentionally hard-deleted
/// (thekas, batai agreements without settlements), so it never appears here.
class RecycleBinService {
  static const Map<String, String> tableUrdu = {
    'expenses': 'اخراجات',
    'sales': 'فروخت',
    'harvests': 'پیداوار',
    'tasks': 'کام',
    'parties': 'پارٹیاں',
  };

  static String urduFor(String table) => tableUrdu[table] ?? table;

  static Future<List<DeletedItem>> listDeleted({
    DatabaseExecutor? executor,
  }) async {
    final db = executor ?? await DatabaseHelper.instance.database;
    final items = <DeletedItem>[];

    // --- Expenses ---
    for (final m in await db.query(
      'expenses',
      where: 'deleted_at IS NOT NULL',
      orderBy: 'deleted_at DESC',
    )) {
      final category = m['category'] as String;
      final desc = m['description'] as String?;
      items.add(
        DeletedItem(
          table: 'expenses',
          id: m['id'] as int,
          title:
              (desc == null || desc.isEmpty) ? category : '$category — $desc',
          subtitle:
              '${Money((m['amount_paisa'] as num).toInt()).format()} — ${m['date']}',
          deletedAt: m['deleted_at'] as String,
        ),
      );
    }

    // --- Harvests (with crop name from the season) ---
    for (final m in await db.rawQuery(
      'SELECT h.*, cs.crop_name AS crop_name, cs.variety AS variety '
      'FROM harvests h '
      'LEFT JOIN crop_seasons cs ON cs.id = h.crop_season_id '
      'WHERE h.deleted_at IS NOT NULL '
      'ORDER BY h.deleted_at DESC',
    )) {
      final crop = m['crop_name'] as String?;
      final variety = m['variety'] as String?;
      final name = [
        crop,
        variety,
      ].where((s) => s != null && s.isNotEmpty).join(' — ');
      items.add(
        DeletedItem(
          table: 'harvests',
          id: m['id'] as int,
          title: name.isEmpty ? 'پیداوار' : 'پیداوار — $name',
          subtitle:
              '${UnitDisplay.format((m['quantity'] as num).toDouble(), m['unit'] as String)} — ${m['date']}',
          deletedAt: m['deleted_at'] as String,
        ),
      );
    }

    // --- Sales (with crop name through the parent harvest) ---
    for (final m in await db.rawQuery(
      'SELECT s.*, cs.crop_name AS crop_name '
      'FROM sales s '
      'LEFT JOIN harvests h ON h.id = s.harvest_id '
      'LEFT JOIN crop_seasons cs ON cs.id = h.crop_season_id '
      'WHERE s.deleted_at IS NOT NULL '
      'ORDER BY s.deleted_at DESC',
    )) {
      final crop = m['crop_name'] as String?;
      final buyer = m['buyer_name'] as String?;
      final label = [
        crop,
        buyer,
      ].where((s) => s != null && s.isNotEmpty).join(' — ');
      items.add(
        DeletedItem(
          table: 'sales',
          id: m['id'] as int,
          title: label.isEmpty ? 'فروخت' : 'فروخت — $label',
          subtitle:
              '${Money((m['total_amount_paisa'] as num).toInt()).format()} — ${m['date']}',
          deletedAt: m['deleted_at'] as String,
        ),
      );
    }

    // --- Tasks ---
    for (final m in await db.query(
      'tasks',
      where: 'deleted_at IS NOT NULL',
      orderBy: 'deleted_at DESC',
    )) {
      items.add(
        DeletedItem(
          table: 'tasks',
          id: m['id'] as int,
          title: m['title'] as String,
          subtitle: 'کام',
          deletedAt: m['deleted_at'] as String,
        ),
      );
    }

    // --- Parties ---
    for (final m in await db.query(
      'parties',
      where: 'deleted_at IS NOT NULL',
      orderBy: 'deleted_at DESC',
    )) {
      final phone = m['phone'] as String?;
      items.add(
        DeletedItem(
          table: 'parties',
          id: m['id'] as int,
          title: m['name'] as String,
          subtitle:
              (phone == null || phone.isEmpty) ? 'پارٹی' : 'پارٹی — $phone',
          deletedAt: m['deleted_at'] as String,
        ),
      );
    }

    return items;
  }
}
