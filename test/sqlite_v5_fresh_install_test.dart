import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:sudhamrtam_customer_app/database/milk_database_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(sqfliteFfiInit);

  test('Fresh SQLite v7 database preserves GPS schema', () async {
    final directory = await Directory.systemTemp.createTemp(
      'sudhamrtam_fresh_gps_',
    );

    final databasePath =
        '${directory.path}${Platform.pathSeparator}fresh_test.db';

    final service = MilkDatabaseService.instance;
    var configured = false;

    try {
      service.configureForTesting(
        factory: databaseFactoryFfi,
        databasePath: databasePath,
      );
      configured = true;

      final db = await service.database;

      final version = await db.rawQuery('PRAGMA user_version');

      expect(version.first.values.first, MilkDatabaseService.databaseVersion);

      final integrity = await db.rawQuery('PRAGMA integrity_check');

      expect(integrity.first.values.first, 'ok');

      final columns = await db.rawQuery(
        'PRAGMA table_info(customer_addresses)',
      );

      final columnNames = columns
          .map((column) => column['name'] as String)
          .toSet();

      expect(columnNames, contains('latitude'));
      expect(columnNames, contains('longitude'));

      const requiredTables = [
        'milk_subscriptions',
        'milk_shift_schedules',
        'cart_items',
        'customer_orders',
        'customer_order_items',
        'customer_profiles',
        'customer_addresses',
        'pending_order_submissions',
        'checkout_reconciliations',
      ];

      for (final table in requiredTables) {
        final rows = await db.rawQuery(
          "SELECT name FROM sqlite_master "
          "WHERE type = 'table' AND name = ?",
          [table],
        );

        expect(rows, isNotEmpty, reason: 'Required table $table must exist.');
      }

      final foreignKeys = await db.rawQuery('PRAGMA foreign_keys');

      expect(foreignKeys.first.values.first, 1);
    } finally {
      if (configured) {
        await service.close();
        service.resetTestingConfiguration();
      }

      await directory.delete(recursive: true);
    }
  });
}
