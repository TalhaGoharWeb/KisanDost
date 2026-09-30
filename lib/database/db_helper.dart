import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';

class DatabaseHelper {
  static const _databaseName = "kisan_dost.db";
  static const _databaseVersion = 11;
  static const _backupFormat = 'kisandost_offline_backup';
  static const _backupTables = <String>[
    'farms',
    'fields',
    'crop_seasons',
    'crop_season_fields',
    'expenses',
    'inventory',
    'inventory_transactions',
    'activities',
    'harvests',
    'sales',
    'ushr_records',
    'tasks',
    'thekas',
    'theka_installments',
  ];

  // Make this a singleton class
  DatabaseHelper._privateConstructor();
  static final DatabaseHelper instance = DatabaseHelper._privateConstructor();

  static Database? _database;
  static DatabaseFactory? _databaseFactoryOverride;
  static String? _databasePathOverride;

  static Future<void> configureForTesting({
    required DatabaseFactory factory,
    String path = ':memory:',
  }) async {
    await _database?.close();
    _database = null;
    _databaseFactoryOverride = factory;
    _databasePathOverride = path;
  }

  static Future<void> resetForTesting() async {
    await _database?.close();
    _database = null;
    _databaseFactoryOverride = null;
    _databasePathOverride = null;
  }

  Future<Database> get database async {
    if (_database != null) return _database!;
    _database = await _initDatabase();
    return _database!;
  }

  Future<Database> _initDatabase() async {
    final factory = _databaseFactoryOverride ?? databaseFactory;
    final path =
        _databasePathOverride ??
        join(await factory.getDatabasesPath(), _databaseName);
    return factory.openDatabase(
      path,
      options: OpenDatabaseOptions(
        version: _databaseVersion,
        onConfigure: (db) async {
          await db.execute('PRAGMA foreign_keys = ON');
        },
        onCreate: _onCreate,
        onUpgrade: _onUpgrade,
      ),
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
        description TEXT
      )
    ''');

    await db.execute('''
      CREATE TABLE inventory (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        category TEXT NOT NULL,
        name TEXT NOT NULL,
        unit TEXT NOT NULL,
        quantity REAL NOT NULL,
        cost_per_unit REAL NOT NULL
      )
    ''');
    await _createInventoryTransactionsTable(db);

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
        inventory_purchased_and_used INTEGER NOT NULL DEFAULT 0,
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
        CREATE TABLE IF NOT EXISTS tasks (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          title TEXT NOT NULL,
          date_time TEXT NOT NULL,
          is_completed INTEGER NOT NULL DEFAULT 0
        )
      ''');
    }
    if (oldVersion < 3) {
      try {
        await db.execute(
          "ALTER TABLE tasks ADD COLUMN recurrence TEXT NOT NULL DEFAULT 'none'",
        );
      } catch (e) {
        // Column might already exist
      }
      try {
        await db.execute(
          "ALTER TABLE tasks ADD COLUMN reminders TEXT NOT NULL DEFAULT '0'",
        );
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
      final columns = await db.rawQuery('PRAGMA table_info(activities)');
      final hasPurchaseFlag = columns.any(
        (column) => column['name'] == 'inventory_purchased_and_used',
      );
      if (!hasPurchaseFlag) {
        await db.execute(
          'ALTER TABLE activities ADD COLUMN inventory_purchased_and_used INTEGER NOT NULL DEFAULT 0',
        );
      }
    }
    if (oldVersion < 11) {
      await _createInventoryTransactionsTable(db);
      await db.execute('''
        INSERT INTO inventory_transactions (
          inventory_id, movement_type, category, item_name,
          quantity_delta, unit, unit_cost, transaction_date, notes
        )
        SELECT id, 'opening', category, name, quantity, unit, cost_per_unit,
          DATE('now'), 'Opening balance imported during database upgrade'
        FROM inventory
        WHERE quantity != 0
      ''');
    }
  }

  Future<void> _createInventoryTransactionsTable(
    DatabaseExecutor executor,
  ) async {
    await executor.execute('''
      CREATE TABLE IF NOT EXISTS inventory_transactions (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        inventory_id INTEGER,
        movement_type TEXT NOT NULL CHECK (
          movement_type IN ('opening', 'purchase', 'usage', 'reversal', 'adjustment')
        ),
        category TEXT NOT NULL,
        item_name TEXT NOT NULL,
        quantity_delta REAL NOT NULL CHECK (quantity_delta != 0),
        unit TEXT NOT NULL,
        unit_cost REAL NOT NULL DEFAULT 0 CHECK (unit_cost >= 0),
        activity_id INTEGER,
        transaction_date TEXT NOT NULL,
        notes TEXT,
        created_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP
      )
    ''');
    await executor.execute('''
      CREATE INDEX IF NOT EXISTS idx_inventory_transactions_item_date
      ON inventory_transactions (inventory_id, transaction_date DESC, id DESC)
    ''');
  }

  Future<Map<String, dynamic>> createBackup() async {
    final db = await database;
    final tables = <String, List<Map<String, dynamic>>>{};
    await db.transaction((txn) async {
      for (final table in _backupTables) {
        tables[table] = await txn.query(table, orderBy: 'id');
      }
    });
    return {
      'format': _backupFormat,
      'schemaVersion': _databaseVersion,
      'exportedAt': DateTime.now().toUtc().toIso8601String(),
      'tables': tables,
    };
  }

  Future<int> restoreBackup(Object? payload) async {
    if (payload is! Map) {
      throw const FormatException('Backup must be a JSON object.');
    }
    final backup = Map<String, dynamic>.from(payload);
    if (backup['format'] != _backupFormat) {
      throw const FormatException('This is not a Kisan Dost backup file.');
    }
    final schemaVersion = backup['schemaVersion'];
    if (schemaVersion is! num ||
        schemaVersion < 1 ||
        schemaVersion > _databaseVersion) {
      throw const FormatException(
        'This backup version is not supported by this app.',
      );
    }
    final rawTablesValue = backup['tables'];
    if (rawTablesValue is! Map) {
      throw const FormatException('Backup is missing its table data.');
    }
    final rawTables = Map<String, dynamic>.from(rawTablesValue);
    final importOpeningBalances =
        schemaVersion < 11 && !rawTables.containsKey('inventory_transactions');
    if (importOpeningBalances) {
      rawTables['inventory_transactions'] = <Map<String, dynamic>>[];
    }
    for (final table in _backupTables) {
      if (!rawTables.containsKey(table)) {
        throw FormatException('Backup is incomplete: missing $table.');
      }
    }

    final rowsByTable = <String, List<Map<String, dynamic>>>{};
    for (final entry in rawTables.entries) {
      final table = entry.key.toString();
      if (!_backupTables.contains(table)) {
        throw FormatException('Backup contains an unknown table: $table.');
      }
      if (entry.value is! List) {
        throw FormatException('Invalid row list for $table.');
      }
      final rows = <Map<String, dynamic>>[];
      for (final row in entry.value as List) {
        if (row is! Map) throw FormatException('Invalid row in $table.');
        final mappedRow = Map<String, dynamic>.from(row);
        if (!mappedRow.containsKey('id')) {
          throw FormatException('A row in $table is missing its record ID.');
        }
        rows.add(mappedRow);
      }
      rowsByTable[table] = rows;
    }

    final db = await database;
    var restoredCount = 0;
    await db.transaction((txn) async {
      final tableColumns = <String, Set<String>>{};
      for (final table in _backupTables) {
        final info = await txn.rawQuery('PRAGMA table_info("$table")');
        tableColumns[table] =
            info.map((column) => column['name'] as String).toSet();
      }

      for (final table in _backupTables.reversed) {
        await txn.delete(table);
      }
      for (final table in _backupTables) {
        final allowedColumns = tableColumns[table]!;
        for (final row in rowsByTable[table]!) {
          final unknownColumns = row.keys.where(
            (key) => !allowedColumns.contains(key),
          );
          if (unknownColumns.isNotEmpty) {
            throw FormatException(
              'Backup contains unsupported columns in $table.',
            );
          }
          await txn.insert(table, row);
          restoredCount++;
        }
      }
      if (importOpeningBalances) {
        restoredCount += await txn.rawInsert('''
          INSERT INTO inventory_transactions (
            inventory_id, movement_type, category, item_name,
            quantity_delta, unit, unit_cost, transaction_date, notes
          )
          SELECT id, 'opening', category, name, quantity, unit, cost_per_unit,
            DATE('now'), 'Opening balance imported from an older backup'
          FROM inventory
          WHERE quantity != 0
        ''');
      }
    });
    return restoredCount;
  }

  Future<void> clearAllTables() async {
    final db = await database;
    await db.transaction((txn) async {
      for (final table in [
        'sales',
        'ushr_records',
        'activities',
        'harvests',
        'theka_installments',
        'thekas',
        'crop_season_fields',
        'crop_seasons',
        'fields',
        'farms',
        'expenses',
        'inventory_transactions',
        'inventory',
        'tasks',
      ]) {
        await txn.delete(table);
      }
    });
  }
}
