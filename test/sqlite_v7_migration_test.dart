import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:sudhamrtam_customer_app/database/milk_database_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('SQLite v6 to v7 migration preserves existing data', () async {
    sqfliteFfiInit();

    const sourcePath =
        r'C:\Sudhamrtam\backups\milestone_126_7_migration_test\sudhamrtam_milk_before_v7.db';

    final sourceFile = File(sourcePath);

    expect(
      sourceFile.existsSync(),
      isTrue,
      reason: 'Protected SQLite v6 fixture must exist.',
    );

    final directory = await Directory.systemTemp.createTemp(
      'sudhamrtam_v6_to_v7_',
    );

    final testPath =
        '${directory.path}${Platform.pathSeparator}migration_test.db';

    final service = MilkDatabaseService.instance;
    var configured = false;

    try {
      // Upgrade only a disposable copy.
      await sourceFile.copy(testPath);

      // Verify the source copy starts at version 6.
      final baselineDb = await databaseFactoryFfi.openDatabase(
        testPath,
        options: OpenDatabaseOptions(readOnly: true, singleInstance: false),
      );

      try {
        final version = await baselineDb.rawQuery('PRAGMA user_version');

        expect(version.first.values.first, 6);
      } finally {
        await baselineDb.close();
      }

      // Opening through MilkDatabaseService performs
      // the application's v6-to-v7 migration.
      service.configureForTesting(
        factory: databaseFactoryFfi,
        databasePath: testPath,
      );
      configured = true;

      final db = await service.database;

      final version = await db.rawQuery('PRAGMA user_version');
      expect(version.first.values.first, 7);

      final integrity = await db.rawQuery('PRAGMA integrity_check');
      expect(integrity.first.values.first, 'ok');

      // Verify existing records remain intact.
      const expectedCounts = <String, int>{
        'milk_subscriptions': 2,
        'milk_shift_schedules': 3,
        'cart_items': 1,
        'customer_orders': 0,
        'customer_order_items': 0,
        'customer_profiles': 1,
        'customer_addresses': 0,
        'pending_order_submissions': 0,
      };

      for (final entry in expectedCounts.entries) {
        final rows = await db.rawQuery(
          'SELECT COUNT(*) AS total FROM ${entry.key}',
        );

        expect(
          rows.first['total'],
          entry.value,
          reason: '${entry.key} must preserve its records.',
        );
      }

      // Verify the new v7 table exists.
      final tableRows = await db.rawQuery(
        "SELECT name FROM sqlite_master "
        "WHERE type = 'table' AND name = ?",
        ['checkout_reconciliations'],
      );

      expect(tableRows, isNotEmpty);

      // Verify the expected columns.
      final columns = await db.rawQuery(
        'PRAGMA table_info(checkout_reconciliations)',
      );

      final columnNames = columns
          .map((column) => column['name'] as String)
          .toSet();

      expect(
        columnNames,
        containsAll([
          'order_id',
          'cart_snapshot',
          'reconciliation_state',
          'created_at',
          'completed_at',
        ]),
      );

      // New reconciliation table should start empty.
      final reconciliationCount = await db.rawQuery(
        'SELECT COUNT(*) AS total FROM checkout_reconciliations',
      );

      expect(reconciliationCount.first['total'], 0);

      // Confirm foreign key enforcement remains enabled.
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
