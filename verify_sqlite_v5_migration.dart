// ignore_for_file: avoid_print

import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'lib/database/milk_database_service.dart';

Future<void> main() async {
  sqfliteFfiInit();

  const testDatabasePath =
      r'C:\Sudhamrtam\backups\milestone_126_7_migration_test\sudhamrtam_milk.db';

  final service = MilkDatabaseService.instance;

  service.configureForTesting(
    factory: databaseFactoryFfi,
    databasePath: testDatabasePath,
  );

  try {
    final db = await service.database;

    final version = await db.rawQuery('PRAGMA user_version');

    final integrity = await db.rawQuery('PRAGMA integrity_check');

    final versionNumber = version.first.values.first;
    final integrityResult = integrity.first.values.first;

    if (versionNumber != 5) {
      throw StateError('Expected SQLite version 5, found $versionNumber');
    }

    if (integrityResult != 'ok') {
      throw StateError('SQLite integrity check failed: $integrityResult');
    }

    const expectedCounts = <String, int>{
      'milk_subscriptions': 2,
      'milk_shift_schedules': 3,
      'cart_items': 1,
      'customer_orders': 0,
      'customer_order_items': 0,
      'customer_profiles': 1,
      'customer_addresses': 0,
    };

    for (final entry in expectedCounts.entries) {
      final result = await db.rawQuery(
        'SELECT COUNT(*) AS total FROM ${entry.key}',
      );

      final actualCount = result.first['total'] as int;

      if (actualCount != entry.value) {
        throw StateError(
          '${entry.key}: expected ${entry.value}, '
          'found $actualCount',
        );
      }

      print('${entry.key}: $actualCount — PASS');
    }

    final columns = await db.rawQuery('PRAGMA table_info(customer_addresses)');

    final columnNames = columns
        .map((column) => column['name'] as String)
        .toSet();

    for (final column in ['latitude', 'longitude']) {
      if (!columnNames.contains(column)) {
        throw StateError('Missing GPS column: $column');
      }

      print('GPS column $column: PASS');
    }

    print('SQLite version: $versionNumber');
    print('SQLite integrity: $integrityResult');
    print('ALL MIGRATION CHECKS PASSED');
  } finally {
    await service.close();
    service.resetTestingConfiguration();
  }
}
