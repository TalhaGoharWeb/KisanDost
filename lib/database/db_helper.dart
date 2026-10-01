import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';
import 'package:flutter/foundation.dart';

class DatabaseHelper {
  static const _databaseName = "kisan_dost.db";
  static const _databaseVersion = 11;

  // Make this a singleton class
  DatabaseHelper._privateConstructor();
  static final DatabaseHelper instance = DatabaseHelper._privateConstructor();

  static Database? _database;
  Future<Database> get database async {
    if (_database != null) return _database!;
    _database = await _initDatabase();
    return _database!;
  }

  _initDatabase() async {
    String path = join(await getDatabasesPath(), _databaseName);
    return await openDatabase(
      path,
      version: _databaseVersion,
      // Enforce foreign keys: the schema declares ON DELETE CASCADE / SET NULL,
      // but sqflite leaves FK enforcement OFF by default, which silently
      // orphaned child rows on every parent delete. (Audit 2026-10-01 §7.10)
      onConfigure: (db) async {
        await db.execute('PRAGMA foreign_keys = ON');
      },
      onCreate: _onCreate,
      onUpgrade: _onUpgrade,
    );
  }

  Future _onCreate(Database db, int version) async {
    await db.execute('''
      CREATE TABLE farms (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        name TEXT NOT NULL,
        total_area REAL NOT NULL,
        created_at TEXT NOT NULL
      )
    ''');

    await db.execute('''
      CREATE TABLE fields (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        farm_id INTEGER NOT NULL,
        name TEXT NOT NULL,
        size_acres REAL NOT NULL,
        canal_water_available INTEGER NOT NULL DEFAULT 0,
        tube_well_available INTEGER NOT NULL DEFAULT 0,
        location TEXT,
        FOREIGN KEY (farm_id) REFERENCES farms (id) ON DELETE CASCADE
      )
    ''');

    await db.execute('''
      CREATE TABLE crop_seasons (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        field_id INTEGER NOT NULL,
        crop_name TEXT NOT NULL,
        variety TEXT NOT NULL,
        status TEXT NOT NULL,
        start_date TEXT NOT NULL,
        FOREIGN KEY (field_id) REFERENCES fields (id) ON DELETE CASCADE
      )
    ''');

    await db.execute('''
      CREATE TABLE crop_season_fields (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        crop_season_id INTEGER NOT NULL,
        field_id INTEGER NOT NULL,
        FOREIGN KEY (crop_season_id) REFERENCES crop_seasons (id) ON DELETE CASCADE,
        FOREIGN KEY (field_id) REFERENCES fields (id) ON DELETE CASCADE,
        UNIQUE (crop_season_id, field_id)
      )
    ''');

    await db.execute('''
      CREATE TABLE expenses (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        category TEXT NOT NULL,
        amount REAL NOT NULL,
        date TEXT NOT NULL,
        description TEXT,
        farm_id INTEGER REFERENCES farms (id) ON DELETE SET NULL,
        field_id INTEGER REFERENCES fields (id) ON DELETE SET NULL,
        crop_season_id INTEGER REFERENCES crop_seasons (id) ON DELETE SET NULL
      )
    ''');

    await db.execute('''
      CREATE TABLE inventory (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        category TEXT NOT NULL,
        name TEXT NOT NULL,
        unit TEXT NOT NULL,
        quantity REAL NOT NULL,
        cost_per_unit REAL NOT NULL,
        weight_per_unit_kg REAL
      )
    ''');

    await db.execute('''
      CREATE TABLE inventory_transactions (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        inventory_id INTEGER NOT NULL REFERENCES inventory (id) ON DELETE CASCADE,
        type TEXT NOT NULL,
        quantity REAL NOT NULL,
        unit TEXT NOT NULL,
        unit_price REAL,
        total_amount REAL,
        activity_id INTEGER REFERENCES activities (id) ON DELETE SET NULL,
        date TEXT NOT NULL,
        notes TEXT,
        created_at TEXT NOT NULL
      )
    ''');

    await db.execute('''
      CREATE INDEX IF NOT EXISTS idx_inventory_transactions_item
        ON inventory_transactions (inventory_id)
    ''');

    await db.execute('''
      CREATE TABLE activities (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        crop_season_id INTEGER NOT NULL,
        activity_type TEXT NOT NULL,
        date TEXT NOT NULL,
        details TEXT,
        expense_id INTEGER,
        expense_category TEXT,
        inventory_category TEXT,
        inventory_name TEXT,
        inventory_unit TEXT,
        inventory_quantity REAL,
        inventory_item_id INTEGER REFERENCES inventory (id) ON DELETE SET NULL,
        is_completed INTEGER NOT NULL DEFAULT 0,
        FOREIGN KEY (crop_season_id) REFERENCES crop_seasons (id) ON DELETE CASCADE,
        FOREIGN KEY (expense_id) REFERENCES expenses (id) ON DELETE SET NULL
      )
    ''');

    await db.execute('''
      CREATE TABLE harvests (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        crop_season_id INTEGER NOT NULL,
        quantity REAL NOT NULL,
        unit TEXT NOT NULL,
        date TEXT NOT NULL,
        rate_per_unit REAL DEFAULT 0.0,
        gross_amount REAL DEFAULT 0.0,
        transportation_expense REAL DEFAULT 0.0,
        labour_expense REAL DEFAULT 0.0,
        harvesting_expense REAL DEFAULT 0.0,
        commission_expense REAL DEFAULT 0.0,
        other_expense REAL DEFAULT 0.0,
        total_expense REAL DEFAULT 0.0,
        net_income REAL DEFAULT 0.0,
        buyer_name TEXT,
        payment_status TEXT DEFAULT 'Pending',
        notes TEXT,
        expense_id INTEGER,
        FOREIGN KEY (crop_season_id) REFERENCES crop_seasons (id) ON DELETE CASCADE
      )
    ''');

    await db.execute('''
      CREATE TABLE ushr_records (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        crop_season_id INTEGER NOT NULL,
        harvest_id INTEGER,
        harvest_qty REAL NOT NULL,
        market_value REAL NOT NULL,
        ushr_method TEXT NOT NULL,
        ushr_percentage REAL NOT NULL,
        ushr_amount REAL NOT NULL,
        status TEXT NOT NULL,
        date_paid TEXT,
        notes TEXT,
        expense_id INTEGER,
        pay_method TEXT DEFAULT 'Cash',
        qty_paid REAL DEFAULT 0.0,
        cash_paid REAL DEFAULT 0.0,
        remaining_balance REAL DEFAULT 0.0,
        rate_per_unit REAL DEFAULT 0.0,
        FOREIGN KEY (crop_season_id) REFERENCES crop_seasons (id) ON DELETE CASCADE,
        FOREIGN KEY (harvest_id) REFERENCES harvests (id) ON DELETE SET NULL,
        FOREIGN KEY (expense_id) REFERENCES expenses (id) ON DELETE SET NULL
      )
    ''');

    await db.execute('''
      CREATE TABLE sales (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        harvest_id INTEGER NOT NULL,
        buyer_name TEXT,
        quantity REAL NOT NULL,
        price_per_unit REAL NOT NULL,
        total_amount REAL NOT NULL,
        date TEXT NOT NULL,
        FOREIGN KEY (harvest_id) REFERENCES harvests (id) ON DELETE CASCADE
      )
    ''');

    await db.execute('''
      CREATE TABLE tasks (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        title TEXT NOT NULL,
        description TEXT,
        snoozed_until TEXT,
        date_time TEXT NOT NULL,
        is_completed INTEGER NOT NULL DEFAULT 0,
        recurrence TEXT NOT NULL DEFAULT 'none',
        reminders TEXT NOT NULL DEFAULT '0'
      )
    ''');

    await db.execute('''
      CREATE TABLE thekas (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        farm_id INTEGER NOT NULL,
        field_id INTEGER,
        total_amount REAL NOT NULL,
        duration_type TEXT NOT NULL,
        duration_details TEXT,
        payment_method TEXT NOT NULL,
        start_date TEXT,
        end_date TEXT,
        created_at TEXT NOT NULL,
        FOREIGN KEY (farm_id) REFERENCES farms (id) ON DELETE CASCADE,
        FOREIGN KEY (field_id) REFERENCES fields (id) ON DELETE CASCADE
      )
    ''');

    await db.execute('''
      CREATE TABLE theka_installments (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        theka_id INTEGER NOT NULL,
        amount REAL NOT NULL,
        due_date TEXT NOT NULL,
        status TEXT NOT NULL,
        paid_amount REAL NOT NULL DEFAULT 0.0,
        paid_date TEXT,
        expense_id INTEGER,
        FOREIGN KEY (theka_id) REFERENCES thekas (id) ON DELETE CASCADE,
        FOREIGN KEY (expense_id) REFERENCES expenses (id) ON DELETE SET NULL
      )
    ''');
  }

  Future _onUpgrade(Database db, int oldVersion, int newVersion) async {
    if (oldVersion < 2) {
      await db.execute('''
        CREATE TABLE tasks (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          title TEXT NOT NULL,
          date_time TEXT NOT NULL,
          is_completed INTEGER NOT NULL DEFAULT 0
        )
      ''');
    }
    if (oldVersion < 3) {
      try {
        await db.execute("ALTER TABLE tasks ADD COLUMN recurrence TEXT NOT NULL DEFAULT 'none'");
      } catch (e) {
        // Column might already exist
      }
      try {
        await db.execute("ALTER TABLE tasks ADD COLUMN reminders TEXT NOT NULL DEFAULT '0'");
      } catch (e) {
        // Column might already exist
      }
    }
    if (oldVersion < 4) {
      try {
        await db.execute("ALTER TABLE tasks ADD COLUMN description TEXT");
      } catch (e) {
        // Column might already exist
      }
      try {
        await db.execute("ALTER TABLE tasks ADD COLUMN snoozed_until TEXT");
      } catch (e) {
        // Column might already exist
      }
    }
    if (oldVersion < 5) {
      await db.execute('''
        CREATE TABLE IF NOT EXISTS crop_season_fields (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          crop_season_id INTEGER NOT NULL,
          field_id INTEGER NOT NULL,
          FOREIGN KEY (crop_season_id) REFERENCES crop_seasons (id) ON DELETE CASCADE,
          FOREIGN KEY (field_id) REFERENCES fields (id) ON DELETE CASCADE,
          UNIQUE (crop_season_id, field_id)
        )
      ''');

      await db.execute('''
        INSERT OR IGNORE INTO crop_season_fields (crop_season_id, field_id)
        SELECT id, field_id FROM crop_seasons
      ''');
    }
    if (oldVersion < 6) {
      final List<String> statements = [
        "ALTER TABLE activities ADD COLUMN expense_category TEXT",
        "ALTER TABLE activities ADD COLUMN inventory_category TEXT",
        "ALTER TABLE activities ADD COLUMN inventory_name TEXT",
        "ALTER TABLE activities ADD COLUMN inventory_unit TEXT",
        "ALTER TABLE activities ADD COLUMN inventory_quantity REAL",
        "ALTER TABLE activities ADD COLUMN is_completed INTEGER NOT NULL DEFAULT 0",
      ];
      for (final statement in statements) {
        try {
          await db.execute(statement);
        } catch (_) {
          // Column might already exist on partially migrated devices.
        }
      }
    }
    if (oldVersion < 7) {
      await db.execute('''
        CREATE TABLE IF NOT EXISTS thekas (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          farm_id INTEGER NOT NULL,
          field_id INTEGER,
          total_amount REAL NOT NULL,
          duration_type TEXT NOT NULL,
          duration_details TEXT,
          payment_method TEXT NOT NULL,
          start_date TEXT,
          end_date TEXT,
          created_at TEXT NOT NULL,
          FOREIGN KEY (farm_id) REFERENCES farms (id) ON DELETE CASCADE,
          FOREIGN KEY (field_id) REFERENCES fields (id) ON DELETE CASCADE
        )
      ''');

      await db.execute('''
        CREATE TABLE IF NOT EXISTS theka_installments (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          theka_id INTEGER NOT NULL,
          amount REAL NOT NULL,
          due_date TEXT NOT NULL,
          status TEXT NOT NULL,
          paid_amount REAL NOT NULL DEFAULT 0.0,
          paid_date TEXT,
          expense_id INTEGER,
          FOREIGN KEY (theka_id) REFERENCES thekas (id) ON DELETE CASCADE,
          FOREIGN KEY (expense_id) REFERENCES expenses (id) ON DELETE SET NULL
        )
      ''');
    }
    if (oldVersion < 8) {
      final List<String> statements = [
        "ALTER TABLE harvests ADD COLUMN rate_per_unit REAL DEFAULT 0.0",
        "ALTER TABLE harvests ADD COLUMN gross_amount REAL DEFAULT 0.0",
        "ALTER TABLE harvests ADD COLUMN transportation_expense REAL DEFAULT 0.0",
        "ALTER TABLE harvests ADD COLUMN labour_expense REAL DEFAULT 0.0",
        "ALTER TABLE harvests ADD COLUMN harvesting_expense REAL DEFAULT 0.0",
        "ALTER TABLE harvests ADD COLUMN commission_expense REAL DEFAULT 0.0",
        "ALTER TABLE harvests ADD COLUMN other_expense REAL DEFAULT 0.0",
        "ALTER TABLE harvests ADD COLUMN total_expense REAL DEFAULT 0.0",
        "ALTER TABLE harvests ADD COLUMN net_income REAL DEFAULT 0.0",
        "ALTER TABLE harvests ADD COLUMN buyer_name TEXT",
        "ALTER TABLE harvests ADD COLUMN payment_status TEXT DEFAULT 'Pending'",
        "ALTER TABLE harvests ADD COLUMN notes TEXT",
        "ALTER TABLE harvests ADD COLUMN expense_id INTEGER",
      ];
      for (final statement in statements) {
        try {
          await db.execute(statement);
        } catch (_) {}
      }

      await db.execute('''
        CREATE TABLE IF NOT EXISTS ushr_records (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          crop_season_id INTEGER NOT NULL,
          harvest_id INTEGER,
          harvest_qty REAL NOT NULL,
          market_value REAL NOT NULL,
          ushr_method TEXT NOT NULL,
          ushr_percentage REAL NOT NULL,
          ushr_amount REAL NOT NULL,
          status TEXT NOT NULL,
          date_paid TEXT,
          notes TEXT,
          expense_id INTEGER,
          FOREIGN KEY (crop_season_id) REFERENCES crop_seasons (id) ON DELETE CASCADE,
          FOREIGN KEY (harvest_id) REFERENCES harvests (id) ON DELETE SET NULL,
          FOREIGN KEY (expense_id) REFERENCES expenses (id) ON DELETE SET NULL
        )
      ''');
    }
    if (oldVersion < 9) {
      final List<String> statements = [
        "ALTER TABLE ushr_records ADD COLUMN pay_method TEXT DEFAULT 'Cash'",
        "ALTER TABLE ushr_records ADD COLUMN qty_paid REAL DEFAULT 0.0",
        "ALTER TABLE ushr_records ADD COLUMN cash_paid REAL DEFAULT 0.0",
        "ALTER TABLE ushr_records ADD COLUMN remaining_balance REAL DEFAULT 0.0",
        "ALTER TABLE ushr_records ADD COLUMN rate_per_unit REAL DEFAULT 0.0",
      ];
      for (final statement in statements) {
        try {
          await db.execute(statement);
        } catch (_) {}
      }
    }
    if (oldVersion < 10) {
      await migrateV9ToV10(db);
    }
    if (oldVersion < 11) {
      await migrateV10ToV11(db);
    }
  }

  /// v10 -> v11 migration, exposed for tests.
  ///
  /// 1. Creates the immutable `inventory_transactions` ledger table.
  /// 2. Adds `inventory.weight_per_unit_kg` (farmer-entered weight of one
  ///    package unit, e.g. one bag = 50 kg; NULL = unknown, never assumed).
  /// 3. Adds `activities.inventory_item_id` so activity stock moves link to
  ///    the exact item row instead of fuzzy name matching.
  /// 4. Backfills one 'opening_balance' ledger row per existing inventory
  ///    item (idempotent: skipped if any opening_balance rows exist), and
  ///    best-effort links old activities to items by (category, name, unit).
  @visibleForTesting
  static Future<void> migrateV10ToV11(Database db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS inventory_transactions (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        inventory_id INTEGER NOT NULL REFERENCES inventory (id) ON DELETE CASCADE,
        type TEXT NOT NULL,
        quantity REAL NOT NULL,
        unit TEXT NOT NULL,
        unit_price REAL,
        total_amount REAL,
        activity_id INTEGER REFERENCES activities (id) ON DELETE SET NULL,
        date TEXT NOT NULL,
        notes TEXT,
        created_at TEXT NOT NULL
      )
    ''');

    await db.execute('''
      CREATE INDEX IF NOT EXISTS idx_inventory_transactions_item
        ON inventory_transactions (inventory_id)
    ''');

    for (final statement in [
      'ALTER TABLE inventory ADD COLUMN weight_per_unit_kg REAL',
      'ALTER TABLE activities ADD COLUMN inventory_item_id INTEGER REFERENCES inventory (id) ON DELETE SET NULL',
    ]) {
      try {
        await db.execute(statement);
      } catch (_) {
        // Column might already exist on partially migrated devices.
      }
    }

    // Backfill opening balances (idempotent).
    final int existing = Sqflite.firstIntValue(await db.rawQuery(
          "SELECT COUNT(*) FROM inventory_transactions WHERE type = 'opening_balance'",
        )) ??
        0;
    if (existing == 0) {
      final String now = DateTime.now().toIso8601String();
      final List<Map<String, dynamic>> items = await db.query('inventory');
      for (final item in items) {
        await db.insert('inventory_transactions', {
          'inventory_id': item['id'],
          'type': 'opening_balance',
          'quantity': item['quantity'],
          'unit': item['unit'],
          'date': now,
          'notes': 'پرانے ریکارڈ کا ابتدائی بیلنس',
          'created_at': now,
        });
      }
    }

    // Best-effort link of pre-v11 activities to their item rows.
    await db.execute('''
      UPDATE activities
      SET inventory_item_id = (
        SELECT id FROM inventory
        WHERE inventory.category = activities.inventory_category
          AND inventory.name = activities.inventory_name
          AND inventory.unit = activities.inventory_unit
        LIMIT 1
      )
      WHERE inventory_category IS NOT NULL
        AND inventory_item_id IS NULL
    ''');
  }

  /// v9 -> v10 migration, exposed for tests.
  ///
  /// 1. Orphan repair: deletes child rows whose parent no longer exists.
  ///    These orphans predate FK enforcement (`PRAGMA foreign_keys = ON`
  ///    was only enabled after v9), so `ON DELETE CASCADE` never fired for
  ///    them. Children are deleted before parents; each statement only
  ///    removes rows whose parent is already gone.
  /// 2. Links expenses to farm/field/crop via new nullable columns.
  ///    Nullable + `ON DELETE SET NULL` (never CASCADE): deleting a farm,
  ///    field or crop must never delete financial records.
  @visibleForTesting
  static Future<void> migrateV9ToV10(Database db) async {
    await db.execute(
        'DELETE FROM theka_installments WHERE theka_id NOT IN (SELECT id FROM thekas)');
    await db.execute(
        'DELETE FROM ushr_records WHERE crop_season_id NOT IN (SELECT id FROM crop_seasons)');
    await db.execute(
        'DELETE FROM ushr_records WHERE harvest_id IS NOT NULL AND harvest_id NOT IN (SELECT id FROM harvests)');
    await db.execute(
        'DELETE FROM sales WHERE harvest_id NOT IN (SELECT id FROM harvests)');
    await db.execute(
        'DELETE FROM activities WHERE crop_season_id NOT IN (SELECT id FROM crop_seasons)');
    await db.execute(
        'DELETE FROM harvests WHERE crop_season_id NOT IN (SELECT id FROM crop_seasons)');
    await db.execute(
        'DELETE FROM crop_season_fields WHERE crop_season_id NOT IN (SELECT id FROM crop_seasons) OR field_id NOT IN (SELECT id FROM fields)');
    await db.execute(
        'DELETE FROM crop_seasons WHERE field_id NOT IN (SELECT id FROM fields)');
    await db.execute(
        'DELETE FROM thekas WHERE farm_id NOT IN (SELECT id FROM farms)');
    await db.execute(
        'DELETE FROM thekas WHERE field_id IS NOT NULL AND field_id NOT IN (SELECT id FROM fields)');
    await db.execute(
        'DELETE FROM fields WHERE farm_id NOT IN (SELECT id FROM farms)');

    final List<String> statements = [
      'ALTER TABLE expenses ADD COLUMN farm_id INTEGER REFERENCES farms (id) ON DELETE SET NULL',
      'ALTER TABLE expenses ADD COLUMN field_id INTEGER REFERENCES fields (id) ON DELETE SET NULL',
      'ALTER TABLE expenses ADD COLUMN crop_season_id INTEGER REFERENCES crop_seasons (id) ON DELETE SET NULL',
    ];
    for (final statement in statements) {
      try {
        await db.execute(statement);
      } catch (_) {
        // Column might already exist on partially migrated devices.
      }
    }
  }

  Future<void> clearAllTables() async {
    final db = await database;
    await db.delete('ushr_records');
    await db.delete('theka_installments');
    await db.delete('thekas');
    await db.delete('farms');
    await db.delete('fields');
    await db.delete('crop_seasons');
    await db.delete('crop_season_fields');
    await db.delete('expenses');
    await db.delete('inventory_transactions');
    await db.delete('inventory');
    await db.delete('activities');
    await db.delete('harvests');
    await db.delete('sales');
    await db.delete('tasks');
  }
}
