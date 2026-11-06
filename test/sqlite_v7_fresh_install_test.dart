import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:sudhamrtam_customer_app/database/milk_database_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('Fresh SQLite v7 installation creates all tables', () async {
    sqfliteFfiInit();

    final directory = await Directory.systemTemp.createTemp(
      'sudhamrtam_v7_fresh_',
    );

    final databasePath =
        '${directory.path}${Platform.pathSeparator}fresh_v7.db';

    final service = MilkDatabaseService.instance;
    var configured = false;

    try {
      service.configureForTesting(
        factory: databaseFactoryFfi,
        databasePath: databasePath,
      );
      configured = true;

      final db = await service.database;

      // Verify database version.
      final version = await db.rawQuery('PRAGMA user_version');
      expect(version.first.values.first, MilkDatabaseService.databaseVersion);

      // Verify database integrity.
      final integrity = await db.rawQuery('PRAGMA integrity_check');
      expect(integrity.first.values.first, 'ok');

      // Verify all application tables exist.
      const expectedTables = <String>{
        'milk_subscriptions',
        'milk_shift_schedules',
        'cart_items',
        'customer_orders',
        'customer_order_items',
        'customer_profiles',
        'customer_addresses',
        'pending_order_submissions',
        'checkout_reconciliations',
      };

      final tableRows = await db.rawQuery(
        "SELECT name FROM sqlite_master WHERE type = 'table'",
      );

      final actualTables = tableRows
          .map((row) => row['name'] as String)
          .toSet();

      expect(actualTables, containsAll(expectedTables));

      // Verify reconciliation columns.
      final columns = await db.rawQuery(
        'PRAGMA table_info(checkout_reconciliations)',
      );

      final columnNames = columns.map((row) => row['name'] as String).toSet();

      expect(
        columnNames,
        containsAll(<String>{
          'order_id',
          'cart_snapshot',
          'reconciliation_state',
          'created_at',
          'completed_at',
        }),
      );

      // Verify reconciliation state constraints.
      final now = DateTime.now().toUtc().toIso8601String();

      await db.insert(
        MilkDatabaseService.checkoutReconciliationsTable,
        <String, Object?>{
          'order_id': 'fresh-install-test-order',
          'cart_snapshot': '{"buffalo_milk":2}',
          'reconciliation_state': 'pending',
          'created_at': now,
          'completed_at': null,
        },
      );

      final rows = await db.query(
        MilkDatabaseService.checkoutReconciliationsTable,
        where: 'order_id = ?',
        whereArgs: <Object>['fresh-install-test-order'],
      );

      expect(rows.length, 1);
      expect(rows.first['reconciliation_state'], 'pending');

      // Invalid reconciliation states must be rejected.
      await expectLater(
        db.insert(
          MilkDatabaseService.checkoutReconciliationsTable,
          <String, Object?>{
            'order_id': 'invalid-state-test',
            'cart_snapshot': '{}',
            'reconciliation_state': 'invalid',
            'created_at': now,
            'completed_at': null,
          },
        ),
        throwsA(isA<Exception>()),
      );

      // Verify foreign key enforcement.
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
