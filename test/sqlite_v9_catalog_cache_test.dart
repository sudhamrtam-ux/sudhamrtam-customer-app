import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:sudhamrtam_customer_app/database/milk_database_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(sqfliteFfiInit);

  final service = MilkDatabaseService.instance;

  late Directory directory;
  late String dbPath;

  setUp(() async {
    directory = await Directory.systemTemp.createTemp('sudhamrtam_v9_');
    dbPath = '${directory.path}${Platform.pathSeparator}v9.db';
  });

  tearDown(() async {
    await service.close();
    service.resetTestingConfiguration();
    await directory.delete(recursive: true);
  });

  Future<Set<String>> tables(Database db) async {
    final rows = await db.rawQuery(
      "SELECT name FROM sqlite_master WHERE type = 'table'",
    );
    return rows.map((r) => r['name'] as String).toSet();
  }

  test('Fresh v9 install creates catalog cache and settings', () async {
    service.configureForTesting(
      factory: databaseFactoryFfi,
      databasePath: dbPath,
    );

    final db = await service.database;

    final version = await db.rawQuery('PRAGMA user_version');
    expect(version.first.values.first, MilkDatabaseService.databaseVersion);

    expect(
      await tables(db),
      containsAll(['catalog_cache', 'app_settings', 'customer_orders']),
    );
  });

  test('v8 to v9 migration keeps existing data', () async {
    final v8 = await databaseFactoryFfi.openDatabase(
      dbPath,
      options: OpenDatabaseOptions(
        version: 8,
        onCreate: (db, _) async {
          await db.execute('''
            CREATE TABLE cart_items (
              product_id TEXT PRIMARY KEY,
              quantity INTEGER NOT NULL
            )
          ''');
          await db.insert('cart_items', {
            'product_id': 'cow_milk',
            'quantity': 3,
          });
        },
      ),
    );
    await v8.close();

    service.configureForTesting(
      factory: databaseFactoryFfi,
      databasePath: dbPath,
    );

    final db = await service.database;

    final version = await db.rawQuery('PRAGMA user_version');
    expect(version.first.values.first, MilkDatabaseService.databaseVersion);

    expect(await tables(db), containsAll(['catalog_cache', 'app_settings']));

    final cart = await db.query('cart_items');
    expect(cart.single['product_id'], 'cow_milk');
    expect(cart.single['quantity'], 3);

    final integrity = await db.rawQuery('PRAGMA integrity_check');
    expect(integrity.first.values.first, 'ok');
  });
}
