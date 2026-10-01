import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';
import 'package:flutter/foundation.dart';

class DatabaseHelper {
  static const _databaseName = "kisan_dost.db";
  static const _databaseVersion = 13;

  // Make this a singleton class
  DatabaseHelper._privateConstructor();
  static final DatabaseHelper instance = DatabaseHelper._privateConstructor();

  static Database? _database;
  Future<Database> get database async {
    if (_database != null) return _database!;
    _database = await _initDatabase();
    return _database!;
  }

  /// Closes the open database (if any) and forgets it, so the next
  /// [database] access re-opens the file fresh. Backup/restore close the
  /// DB before copying files; reopening via [database] then re-runs
  /// [_onUpgrade], which migrates older backups forward.
  Future<void> close() async {
    final db = _database;
    _database = null;
    if (db != null) {
      await db.close();
    }
  }

  /// Absolute path of the live database file.
  Future<String> get databaseFilePath async =>
      join(await getDatabasesPath(), _databaseName);

  /// Current schema version of the app (the version new installs get and
  /// older databases are migrated up to).
  static int get schemaVersion => _databaseVersion;

  /// Merges any WAL frames back into the main database file and truncates
  /// the WAL. No-op when the database is not open. Call before copying the
  /// .db file so the copy is self-contained.
  Future<void> checkpoint() async {
    final db = _database;
    if (db == null) return;
    await db.execute('PRAGMA wal_checkpoint(TRUNCATE)');
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
        amount_paisa INTEGER NOT NULL,
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
        cost_per_unit_paisa INTEGER NOT NULL,
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
        unit_price_paisa INTEGER,
        total_amount_paisa INTEGER,
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
        rate_per_unit_paisa INTEGER DEFAULT 0,
        transportation_expense_paisa INTEGER DEFAULT 0,
        labour_expense_paisa INTEGER DEFAULT 0,
        harvesting_expense_paisa INTEGER DEFAULT 0,
        commission_expense_paisa INTEGER DEFAULT 0,
        other_expense_paisa INTEGER DEFAULT 0,
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
        market_value_paisa INTEGER NOT NULL,
        ushr_method TEXT NOT NULL,
        ushr_percentage REAL NOT NULL,
        ushr_amount_paisa INTEGER NOT NULL,
        status TEXT NOT NULL,
        date_paid TEXT,
        notes TEXT,
        expense_id INTEGER,
        pay_method TEXT DEFAULT 'Cash',
        qty_paid REAL DEFAULT 0.0,
        cash_paid_paisa INTEGER DEFAULT 0,
        rate_per_unit_paisa INTEGER DEFAULT 0,
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
        price_per_unit_paisa INTEGER NOT NULL,
        total_amount_paisa INTEGER NOT NULL,
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
        total_amount_paisa INTEGER NOT NULL,
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
        amount_paisa INTEGER NOT NULL,
        due_date TEXT NOT NULL,
        status TEXT NOT NULL,
        paid_amount_paisa INTEGER NOT NULL DEFAULT 0,
        paid_date TEXT,
        expense_id INTEGER,
        FOREIGN KEY (theka_id) REFERENCES thekas (id) ON DELETE CASCADE,
        FOREIGN KEY (expense_id) REFERENCES expenses (id) ON DELETE SET NULL
      )
    ''');

    await db.execute('''
      CREATE TABLE parties (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        name TEXT NOT NULL,
        phone TEXT,
        notes TEXT,
        created_at TEXT NOT NULL
      )
    ''');

    await db.execute('''
      CREATE TABLE party_ledger_entries (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        party_id INTEGER NOT NULL,
        entry_type TEXT NOT NULL,
        amount_paisa INTEGER NOT NULL,
        date TEXT NOT NULL,
        note TEXT,
        created_at TEXT NOT NULL,
        FOREIGN KEY (party_id) REFERENCES parties (id) ON DELETE RESTRICT
      )
    ''');

    await db.execute('''
      CREATE INDEX IF NOT EXISTS idx_party_ledger_entries_party
        ON party_ledger_entries (party_id)
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
    if (oldVersion < 12) {
      await migrateV11ToV12(db);
    }
    if (oldVersion < 13) {
      await migrateV12ToV13(db);
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

  /// v11 -> v12 migration: money moves from REAL rupees to INTEGER paisa.
  ///
  /// Every money table is REBUILT: the old table is renamed to
  /// `<table>_v11_backup`, a new table with `<name>_paisa INTEGER` columns is
  /// created (the exact fresh-install schema from [_onCreate]), rows are
  /// copied with `CAST(ROUND(<name> * 100) AS INTEGER)`, and the backup is
  /// dropped.
  ///
  /// A rebuild (rather than deprecate-in-place) is REQUIRED: the old REAL
  /// columns are `NOT NULL` on several tables, so keeping them would make
  /// every future insert fail its constraint. After the rebuild, upgraded
  /// devices have byte-for-byte the same schema as fresh installs — there
  /// are no deprecated money columns left.
  ///
  /// ROUNDING RULE (the only rounding in the whole migration): SQLite's
  /// ROUND() rounds half AWAY from zero, so 10.999 -> 1100, 0.005 -> 1.
  /// This matches Dart's `double.round()` used by `Money.fromRupees`.
  ///
  /// Redundant COMPUTED columns are DROPPED, not converted — they are
  /// derived in Dart now (see [Harvest] / [UshrRecord] computed getters) and
  /// storing them caused real drift bugs:
  ///   harvests.gross_amount (= qty x rate), harvests.total_expense
  ///   (= sum of the 5 expense buckets), harvests.net_income (= gross - expenses),
  ///   ushr_records.remaining_balance (= ushr - cash - qty*rate).
  ///
  /// Non-money REAL columns (quantities, weights, percentages) are untouched.
  @visibleForTesting
  static Future<void> migrateV11ToV12(Database db) async {
    final tables = (await db
            .rawQuery("SELECT name FROM sqlite_master WHERE type = 'table'"))
        .map((r) => r['name'] as String)
        .toSet();

    // Rebuilds one money table. Skips silently when the table is absent
    // (minimal test schemas) or when it already carries paisa columns
    // (a repeated run — the migration is idempotent). FKs are toggled off
    // for the rebuild so table order never matters; the backup table is
    // dropped afterwards. Note: _onUpgrade runs inside a transaction, so a
    // failed run rolls back to v11 and the next launch retries cleanly.
    Future<void> rebuildMoneyTable(
      String table,
      String createSql,
      List<String> newColumns,
      List<String> selectExprs,
    ) async {
      if (!tables.contains(table)) return;
      assert(newColumns.length == selectExprs.length);
      final cols = (await db.rawQuery('PRAGMA table_info($table)'))
          .map((c) => c['name'] as String)
          .toSet();
      if (cols.any((c) => c.endsWith('_paisa'))) return; // Already v12.
      // legacy_alter_table=ON: RENAME must NOT rewrite FK references in
      // other tables to the backup name (the rebuilt table keeps the
      // original name, so references stay valid). foreign_keys=OFF so the
      // intermediate states never trip enforcement.
      await db.execute('PRAGMA legacy_alter_table = ON');
      await db.execute('PRAGMA foreign_keys = OFF');
      try {
        await db.execute('ALTER TABLE $table RENAME TO ${table}_v11_backup');
        await db.execute(createSql);
        await db.execute(
          'INSERT INTO $table (${newColumns.join(', ')}) '
          'SELECT ${selectExprs.join(', ')} FROM ${table}_v11_backup',
        );
        await db.execute('DROP TABLE ${table}_v11_backup');
      } finally {
        await db.execute('PRAGMA legacy_alter_table = OFF');
        await db.execute('PRAGMA foreign_keys = ON');
      }
    }

    String paisa(String oldCol) =>
        'CAST(ROUND($oldCol * 100) AS INTEGER)';

    await rebuildMoneyTable(
      'expenses',
      '''CREATE TABLE expenses (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        category TEXT NOT NULL,
        amount_paisa INTEGER NOT NULL,
        date TEXT NOT NULL,
        description TEXT,
        farm_id INTEGER REFERENCES farms (id) ON DELETE SET NULL,
        field_id INTEGER REFERENCES fields (id) ON DELETE SET NULL,
        crop_season_id INTEGER REFERENCES crop_seasons (id) ON DELETE SET NULL
      )''',
      ['id', 'category', 'amount_paisa', 'date', 'description', 'farm_id', 'field_id', 'crop_season_id'],
      ['id', 'category', paisa('amount'), 'date', 'description', 'farm_id', 'field_id', 'crop_season_id'],
    );

    await rebuildMoneyTable(
      'inventory',
      '''CREATE TABLE inventory (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        category TEXT NOT NULL,
        name TEXT NOT NULL,
        unit TEXT NOT NULL,
        quantity REAL NOT NULL,
        cost_per_unit_paisa INTEGER NOT NULL,
        weight_per_unit_kg REAL
      )''',
      ['id', 'category', 'name', 'unit', 'quantity', 'cost_per_unit_paisa', 'weight_per_unit_kg'],
      ['id', 'category', 'name', 'unit', 'quantity', paisa('cost_per_unit'), 'weight_per_unit_kg'],
    );

    await rebuildMoneyTable(
      'inventory_transactions',
      '''CREATE TABLE inventory_transactions (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        inventory_id INTEGER NOT NULL REFERENCES inventory (id) ON DELETE CASCADE,
        type TEXT NOT NULL,
        quantity REAL NOT NULL,
        unit TEXT NOT NULL,
        unit_price_paisa INTEGER,
        total_amount_paisa INTEGER,
        activity_id INTEGER REFERENCES activities (id) ON DELETE SET NULL,
        date TEXT NOT NULL,
        notes TEXT,
        created_at TEXT NOT NULL
      )''',
      ['id', 'inventory_id', 'type', 'quantity', 'unit', 'unit_price_paisa', 'total_amount_paisa', 'activity_id', 'date', 'notes', 'created_at'],
      ['id', 'inventory_id', 'type', 'quantity', 'unit', paisa('unit_price'), paisa('total_amount'), 'activity_id', 'date', 'notes', 'created_at'],
    );
    if (tables.contains('inventory_transactions')) {
      // The rebuild drops indexes; recreate the v11 one.
      await db.execute('''
        CREATE INDEX IF NOT EXISTS idx_inventory_transactions_item
          ON inventory_transactions (inventory_id)
      ''');
    }

    await rebuildMoneyTable(
      'harvests',
      '''CREATE TABLE harvests (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        crop_season_id INTEGER NOT NULL,
        quantity REAL NOT NULL,
        unit TEXT NOT NULL,
        date TEXT NOT NULL,
        rate_per_unit_paisa INTEGER DEFAULT 0,
        transportation_expense_paisa INTEGER DEFAULT 0,
        labour_expense_paisa INTEGER DEFAULT 0,
        harvesting_expense_paisa INTEGER DEFAULT 0,
        commission_expense_paisa INTEGER DEFAULT 0,
        other_expense_paisa INTEGER DEFAULT 0,
        buyer_name TEXT,
        payment_status TEXT DEFAULT 'Pending',
        notes TEXT,
        expense_id INTEGER,
        FOREIGN KEY (crop_season_id) REFERENCES crop_seasons (id) ON DELETE CASCADE
      )''',
      ['id', 'crop_season_id', 'quantity', 'unit', 'date', 'rate_per_unit_paisa', 'transportation_expense_paisa', 'labour_expense_paisa', 'harvesting_expense_paisa', 'commission_expense_paisa', 'other_expense_paisa', 'buyer_name', 'payment_status', 'notes', 'expense_id'],
      ['id', 'crop_season_id', 'quantity', 'unit', 'date', paisa('rate_per_unit'), paisa('transportation_expense'), paisa('labour_expense'), paisa('harvesting_expense'), paisa('commission_expense'), paisa('other_expense'), 'buyer_name', 'payment_status', 'notes', 'expense_id'],
    );

    await rebuildMoneyTable(
      'ushr_records',
      '''CREATE TABLE ushr_records (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        crop_season_id INTEGER NOT NULL,
        harvest_id INTEGER,
        harvest_qty REAL NOT NULL,
        market_value_paisa INTEGER NOT NULL,
        ushr_method TEXT NOT NULL,
        ushr_percentage REAL NOT NULL,
        ushr_amount_paisa INTEGER NOT NULL,
        status TEXT NOT NULL,
        date_paid TEXT,
        notes TEXT,
        expense_id INTEGER,
        pay_method TEXT DEFAULT 'Cash',
        qty_paid REAL DEFAULT 0.0,
        cash_paid_paisa INTEGER DEFAULT 0,
        rate_per_unit_paisa INTEGER DEFAULT 0,
        FOREIGN KEY (crop_season_id) REFERENCES crop_seasons (id) ON DELETE CASCADE,
        FOREIGN KEY (harvest_id) REFERENCES harvests (id) ON DELETE SET NULL,
        FOREIGN KEY (expense_id) REFERENCES expenses (id) ON DELETE SET NULL
      )''',
      ['id', 'crop_season_id', 'harvest_id', 'harvest_qty', 'market_value_paisa', 'ushr_method', 'ushr_percentage', 'ushr_amount_paisa', 'status', 'date_paid', 'notes', 'expense_id', 'pay_method', 'qty_paid', 'cash_paid_paisa', 'rate_per_unit_paisa'],
      ['id', 'crop_season_id', 'harvest_id', 'harvest_qty', paisa('market_value'), 'ushr_method', 'ushr_percentage', paisa('ushr_amount'), 'status', 'date_paid', 'notes', 'expense_id', 'pay_method', 'qty_paid', paisa('cash_paid'), paisa('rate_per_unit')],
    );

    await rebuildMoneyTable(
      'sales',
      '''CREATE TABLE sales (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        harvest_id INTEGER NOT NULL,
        buyer_name TEXT,
        quantity REAL NOT NULL,
        price_per_unit_paisa INTEGER NOT NULL,
        total_amount_paisa INTEGER NOT NULL,
        date TEXT NOT NULL,
        FOREIGN KEY (harvest_id) REFERENCES harvests (id) ON DELETE CASCADE
      )''',
      ['id', 'harvest_id', 'buyer_name', 'quantity', 'price_per_unit_paisa', 'total_amount_paisa', 'date'],
      ['id', 'harvest_id', 'buyer_name', 'quantity', paisa('price_per_unit'), paisa('total_amount'), 'date'],
    );

    await rebuildMoneyTable(
      'thekas',
      '''CREATE TABLE thekas (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        farm_id INTEGER NOT NULL,
        field_id INTEGER,
        total_amount_paisa INTEGER NOT NULL,
        duration_type TEXT NOT NULL,
        duration_details TEXT,
        payment_method TEXT NOT NULL,
        start_date TEXT,
        end_date TEXT,
        created_at TEXT NOT NULL,
        FOREIGN KEY (farm_id) REFERENCES farms (id) ON DELETE CASCADE,
        FOREIGN KEY (field_id) REFERENCES fields (id) ON DELETE CASCADE
      )''',
      ['id', 'farm_id', 'field_id', 'total_amount_paisa', 'duration_type', 'duration_details', 'payment_method', 'start_date', 'end_date', 'created_at'],
      ['id', 'farm_id', 'field_id', paisa('total_amount'), 'duration_type', 'duration_details', 'payment_method', 'start_date', 'end_date', 'created_at'],
    );

    await rebuildMoneyTable(
      'theka_installments',
      '''CREATE TABLE theka_installments (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        theka_id INTEGER NOT NULL,
        amount_paisa INTEGER NOT NULL,
        due_date TEXT NOT NULL,
        status TEXT NOT NULL,
        paid_amount_paisa INTEGER NOT NULL DEFAULT 0,
        paid_date TEXT,
        expense_id INTEGER,
        FOREIGN KEY (theka_id) REFERENCES thekas (id) ON DELETE CASCADE,
        FOREIGN KEY (expense_id) REFERENCES expenses (id) ON DELETE SET NULL
      )''',
      ['id', 'theka_id', 'amount_paisa', 'due_date', 'status', 'paid_amount_paisa', 'paid_date', 'expense_id'],
      ['id', 'theka_id', paisa('amount'), 'due_date', 'status', paisa('paid_amount'), 'paid_date', 'expense_id'],
    );
  }

  /// v12 -> v13 migration, exposed for tests: party ledger (udhaar).
  ///
  /// Creates `parties` and `party_ledger_entries` plus an index on
  /// `party_ledger_entries.party_id`. Idempotent (`IF NOT EXISTS`) — a
  /// repeated run is a no-op. No data moves; nothing is dropped.
  /// Balances are always computed with SUM(), never stored.
  @visibleForTesting
  static Future<void> migrateV12ToV13(Database db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS parties (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        name TEXT NOT NULL,
        phone TEXT,
        notes TEXT,
        created_at TEXT NOT NULL
      )
    ''');
    await db.execute('''
      CREATE TABLE IF NOT EXISTS party_ledger_entries (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        party_id INTEGER NOT NULL,
        entry_type TEXT NOT NULL,
        amount_paisa INTEGER NOT NULL,
        date TEXT NOT NULL,
        note TEXT,
        created_at TEXT NOT NULL,
        FOREIGN KEY (party_id) REFERENCES parties (id) ON DELETE RESTRICT
      )
    ''');
    await db.execute('''
      CREATE INDEX IF NOT EXISTS idx_party_ledger_entries_party
        ON party_ledger_entries (party_id)
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
