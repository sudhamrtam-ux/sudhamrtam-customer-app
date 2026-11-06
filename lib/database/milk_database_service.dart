import 'package:path/path.dart' as path;
import 'package:sqflite/sqflite.dart';

/// Local SQLite database service for Sudhamrtam.
///
/// Version 1: Milk subscriptions and shift schedules.
/// Version 2: Shopping cart.
/// Version 3: Customer orders and order items.
/// Version 4: Customer profiles and saved addresses.
/// Version 5: Optional GPS coordinates for delivery addresses.
/// Version 6: Durable pending order submissions.
/// Version 7: Checkout reconciliation tracking.
/// Version 8: Delivery recipient name and phone on orders.
/// Version 9: Server catalog cache and app settings.
class MilkDatabaseService {
  MilkDatabaseService._();
  static const String checkoutReconciliationsTable = 'checkout_reconciliations';
  static final MilkDatabaseService instance = MilkDatabaseService._();
  static const String databaseName = 'sudhamrtam_milk.db';
  static const int databaseVersion = 9;
  static const String catalogCacheTable = 'catalog_cache';
  static const String appSettingsTable = 'app_settings';
  static const String subscriptionsTable = 'milk_subscriptions';
  static const String schedulesTable = 'milk_shift_schedules';
  static const String cartItemsTable = 'cart_items';
  static const String ordersTable = 'customer_orders';
  static const String orderItemsTable = 'customer_order_items';
  static const String customerProfilesTable = 'customer_profiles';
  static const String customerAddressesTable = 'customer_addresses';
  static const String pendingOrderSubmissionsTable =
      'pending_order_submissions';

  Database? _database;

  // IMPORTANT:
  // Do not initialize this with `databaseFactory` here.
  // On Windows, sqflite_common_ffi initializes its factory separately.
  DatabaseFactory? _databaseFactory;

  String? _databasePathOverride;

  /// Configure an isolated SQLite database for automated testing.
  ///
  /// The existing connection must be closed before calling this method.
  void configureForTesting({
    required DatabaseFactory factory,
    required String databasePath,
  }) {
    if (_database != null && _database!.isOpen) {
      throw StateError('Close the existing database before configuring tests.');
    }

    if (databasePath.trim().isEmpty) {
      throw ArgumentError('Test database path cannot be empty.');
    }

    _databaseFactory = factory;
    _databasePathOverride = databasePath;
  }

  /// Restore the default platform SQLite configuration.
  ///
  /// Call this after closing the test database.
  void resetTestingConfiguration() {
    if (_database != null && _database!.isOpen) {
      throw StateError('Close the database before resetting configuration.');
    }

    _databaseFactory = null;
    _databasePathOverride = null;
  }

  /// Open the database or reuse an existing open connection.
  Future<Database> get database async {
    if (_database != null && _database!.isOpen) {
      return _database!;
    }

    // Resolve the factory only when opening the database.
    // Tests can provide databaseFactoryFfi before this point.
    final factory = _databaseFactory ?? databaseFactory;

    final databasePath =
        _databasePathOverride ??
        path.join(await factory.getDatabasesPath(), databaseName);

    _database = await factory.openDatabase(
      databasePath,
      options: OpenDatabaseOptions(
        version: databaseVersion,
        onConfigure: (db) async {
          await db.execute('PRAGMA foreign_keys = ON');
        },
        onCreate: _createTables,
        onUpgrade: _upgradeDatabase,
      ),
    );

    return _database!;
  }

  /// Create all tables for a new installation.
  Future<void> _createTables(Database db, int version) async {
    await db.execute('''
      CREATE TABLE $subscriptionsTable (
        id TEXT PRIMARY KEY,
        product_id TEXT NOT NULL
          CHECK (
            product_id IN (
              'buffalo_milk',
              'cow_milk'
            )
          ),
        status TEXT NOT NULL DEFAULT 'active'
          CHECK (
            status IN (
              'active',
              'paused',
              'cancelled'
            )
          ),
        created_at TEXT NOT NULL
      )
    ''');

    await db.execute('''
      CREATE TABLE $schedulesTable (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        subscription_id TEXT NOT NULL,
        shift TEXT NOT NULL
          CHECK (
            shift IN (
              'morning',
              'evening'
            )
          ),
        quantity_ml INTEGER NOT NULL
          CHECK (
            quantity_ml >= 500
            AND quantity_ml <= 10000
            AND quantity_ml % 500 = 0
          ),
        frequency TEXT NOT NULL
          CHECK (
            frequency IN (
              'daily',
              'alternateDays',
              'selectedDays',
              'randomDays'
            )
          ),
        selected_weekdays TEXT NOT NULL DEFAULT '[]',
        selected_random_dates TEXT NOT NULL DEFAULT '[]',
        start_date TEXT NOT NULL,
        end_date TEXT,
        FOREIGN KEY (subscription_id)
          REFERENCES $subscriptionsTable(id)
          ON DELETE CASCADE,
        UNIQUE (
          subscription_id,
          shift
        )
      )
    ''');

    await db.execute('''
      CREATE INDEX idx_milk_shift_subscription
      ON $schedulesTable(subscription_id)
    ''');

    await _createCartTable(db);
    await _createOrderTables(db);
    await _addOrderRecipientColumns(db);
    await _createCustomerAccountTables(db);
    await _createPendingOrderSubmissionsTable(db);
    await _createCheckoutReconciliationsTable(db);
    await _createCatalogCacheTables(db);
  }

  /// Upgrade older database versions without deleting
  /// existing customer records.
  Future<void> _upgradeDatabase(
    Database db,
    int oldVersion,
    int newVersion,
  ) async {
    // Version 2: Shopping cart.
    if (oldVersion < 2) {
      await _createCartTable(db);
    }

    // Version 3: Customer orders.
    if (oldVersion < 3) {
      await _createOrderTables(db);
    }

    // Version 4: Customer profiles and addresses.
    if (oldVersion < 4) {
      await _createCustomerAccountTables(db);
    }

    // Version 5: Google Maps delivery coordinates.
    //
    // Existing addresses remain intact.
    // Both new columns are nullable.
    if (oldVersion < 5) {
      await db.execute('''
        ALTER TABLE $customerAddressesTable
        ADD COLUMN latitude REAL
      ''');
      await db.execute('''
        ALTER TABLE $customerAddressesTable
        ADD COLUMN longitude REAL
      ''');
    }

    // Version 6: Durable pending order submission recovery.
    if (oldVersion < 6) {
      await _createPendingOrderSubmissionsTable(db);
    }

    // Version 7: Checkout reconciliation tracking.
    if (oldVersion < 7) {
      await _createCheckoutReconciliationsTable(db);
    }

    // Version 8: Delivery recipient on orders.
    //
    // Existing orders remain intact with NULL recipients.
    if (oldVersion < 8) {
      await _addOrderRecipientColumns(db);
    }

    // Version 9: Server catalog cache and app settings.
    if (oldVersion < 9) {
      await _createCatalogCacheTables(db);
    }
  }

  /// Version 9: Server catalog cache and app settings.
  ///
  /// `catalog_cache` keeps the last catalog received so the app
  /// works offline. `app_settings` is a small key/value store
  /// for app preferences.
  Future<void> _createCatalogCacheTables(Database db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS $catalogCacheTable (
        area_id TEXT PRIMARY KEY,
        area_name TEXT NOT NULL,
        payload TEXT NOT NULL,
        fetched_at TEXT NOT NULL
      )
    ''');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS $appSettingsTable (
        key TEXT PRIMARY KEY,
        value TEXT NOT NULL
      )
    ''');
  }

  /// Version 8: Delivery recipient name and phone.
  ///
  /// Shared by fresh installs and upgrades, and always
  /// applied after the v3 order table exists.
  Future<void> _addOrderRecipientColumns(Database db) async {
    await db.execute('''
      ALTER TABLE $ordersTable
      ADD COLUMN recipient_name TEXT
    ''');
    await db.execute('''
      ALTER TABLE $ordersTable
      ADD COLUMN recipient_phone TEXT
    ''');
  }

  /// Version 2: Shopping cart.
  Future<void> _createCartTable(Database db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS $cartItemsTable (
        product_id TEXT PRIMARY KEY,
        quantity INTEGER NOT NULL
          CHECK (
            quantity >= 1
            AND quantity <= 100
          )
      )
    ''');
  }

  /// Version 3: Customer orders and order items.
  Future<void> _createOrderTables(Database db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS $ordersTable (
        id TEXT PRIMARY KEY,
        created_at TEXT NOT NULL,
        fulfillment_method TEXT NOT NULL
          CHECK (
            fulfillment_method IN (
              'delivery',
              'pickup'
            )
          ),
        payment_method TEXT NOT NULL
          CHECK (
            payment_method IN (
              'online',
              'cashOnDelivery'
            )
          ),
        status TEXT NOT NULL DEFAULT 'pending'
          CHECK (
            status IN (
              'pending',
              'confirmed',
              'preparing',
              'outForDelivery',
              'readyForPickup',
              'delivered',
              'pickedUp',
              'cancelled'
            )
          ),
        delivery_address TEXT,
        notes TEXT,
        subtotal REAL NOT NULL
          CHECK (
            subtotal >= 0
          ),
        CHECK (
          fulfillment_method != 'delivery'
          OR (
            delivery_address IS NOT NULL
            AND length(
              trim(delivery_address)
            ) > 0
          )
        )
      )
    ''');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS $orderItemsTable (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        order_id TEXT NOT NULL,
        product_id TEXT NOT NULL,
        product_name TEXT NOT NULL,
        unit TEXT NOT NULL,
        quantity INTEGER NOT NULL
          CHECK (
            quantity >= 1
            AND quantity <= 100
          ),
        unit_price REAL NOT NULL
          CHECK (
            unit_price >= 0
          ),
        FOREIGN KEY (order_id)
          REFERENCES $ordersTable(id)
          ON DELETE CASCADE
      )
    ''');

    await db.execute('''
      CREATE INDEX IF NOT EXISTS idx_customer_orders_created
      ON $ordersTable(created_at)
    ''');

    await db.execute('''
      CREATE INDEX IF NOT EXISTS idx_customer_order_items_order
      ON $orderItemsTable(order_id)
    ''');
  }

  /// Version 4: Customer profiles and delivery addresses.
  ///
  /// Version 5: New installations include optional
  /// latitude and longitude columns.
  Future<void> _createCustomerAccountTables(Database db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS $customerProfilesTable (
        id TEXT PRIMARY KEY,
        full_name TEXT NOT NULL,
        phone_number TEXT,
        email TEXT,
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL
      )
    ''');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS $customerAddressesTable (
        id TEXT PRIMARY KEY,
        customer_id TEXT NOT NULL,
        label TEXT NOT NULL,
        recipient_name TEXT NOT NULL,
        phone_number TEXT NOT NULL,
        address_line_1 TEXT NOT NULL,
        address_line_2 TEXT,
        landmark TEXT NOT NULL DEFAULT '',
        city TEXT NOT NULL,
        state TEXT NOT NULL,
        postal_code TEXT NOT NULL,

        latitude REAL,
        longitude REAL,

        is_default INTEGER NOT NULL DEFAULT 0
          CHECK (
            is_default IN (0, 1)
          ),
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL,
        FOREIGN KEY (customer_id)
          REFERENCES $customerProfilesTable(id)
          ON DELETE CASCADE
      )
    ''');

    await db.execute('''
      CREATE INDEX IF NOT EXISTS idx_customer_addresses_customer
      ON $customerAddressesTable(customer_id)
    ''');

    // Only one address per customer may be marked
    // as the default delivery address.
    await db.execute('''
      CREATE UNIQUE INDEX IF NOT EXISTS idx_customer_default_address
      ON $customerAddressesTable(customer_id)
      WHERE is_default = 1
    ''');
  }

  /// Version 6: Durable pending order submissions.
  ///
  /// Stores a prepared order's original ID and serialized payload
  /// so interrupted submissions can be recovered after app restart.
  Future<void> _createPendingOrderSubmissionsTable(Database db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS $pendingOrderSubmissionsTable (
        order_id TEXT PRIMARY KEY,
        created_at TEXT NOT NULL,
        order_payload TEXT NOT NULL,
        submission_state TEXT NOT NULL
          CHECK (
            submission_state IN (
              'prepared',
              'uncertain'
            )
          ),
        updated_at TEXT NOT NULL
      )
    ''');
  }

  /// Version 7: Checkout reconciliation tracking.
  ///
  /// Records the original cart snapshot associated with an order.
  /// Reconciliation must be coordinated with CartManager to prevent
  /// concurrent cart saves from overwriting committed changes.
  Future<void> _createCheckoutReconciliationsTable(Database db) async {
    await db.execute('''
    CREATE TABLE IF NOT EXISTS $checkoutReconciliationsTable (
      order_id TEXT PRIMARY KEY,
      cart_snapshot TEXT NOT NULL,
      reconciliation_state TEXT NOT NULL
        CHECK (
          reconciliation_state IN (
            'pending',
            'completed'
          )
        ),
      created_at TEXT NOT NULL,
      completed_at TEXT,
      CHECK (
        (
          reconciliation_state = 'pending'
          AND completed_at IS NULL
        )
        OR
        (
          reconciliation_state = 'completed'
          AND completed_at IS NOT NULL
        )
      )
    )
  ''');
  }

  /// Close the current SQLite connection.
  Future<void> close() async {
    final db = _database;
    _database = null;

    if (db != null && db.isOpen) {
      await db.close();
    }
  }
}
