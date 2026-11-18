import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:sudhamrtam_customer_app/database/milk_database_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(sqfliteFfiInit);

  test('SQLite v5 to v7 upgrade preserves v6 checkout schema', () async {
    const sourcePath =
        r'D:\Sudhamrtam\backups\milestone_126_7_migration_test\sudhamrtam_milk_before_v6.db';

    final sourceFile = File(sourcePath);

    expect(
      await sourceFile.exists(),
      isTrue,
      reason: 'Protected SQLite v5 backup must exist.',
    );

    final directory = await Directory.systemTemp.createTemp(
      'sudhamrtam_v5_to_v7_',
    );

    final testPath =
        '${directory.path}${Platform.pathSeparator}upgrade_test.db';

    final service = MilkDatabaseService.instance;
    var configured = false;

    try {
      await sourceFile.copy(testPath);

      final baselineDb = await databaseFactoryFfi.openDatabase(
        testPath,
        options: OpenDatabaseOptions(readOnly: true, singleInstance: false),
      );

      try {
        final version = await baselineDb.rawQuery('PRAGMA user_version');

        expect(
          version.first.values.first,
          5,
          reason: 'The input database must be SQLite v5.',
        );
      } finally {
        await baselineDb.close();
      }

      service.configureForTesting(
        factory: databaseFactoryFfi,
        databasePath: testPath,
      );
      configured = true;

      final db = await service.database;

      final version = await db.rawQuery('PRAGMA user_version');

      expect(version.first.values.first, MilkDatabaseService.databaseVersion);

      final integrity = await db.rawQuery('PRAGMA integrity_check');

      expect(integrity.first.values.first, 'ok');

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
        final rows = await db.rawQuery(
          'SELECT COUNT(*) AS total FROM ${entry.key}',
        );

        expect(
          rows.first['total'],
          entry.value,
          reason: '${entry.key} records must be preserved.',
        );
      }

      final pendingColumns = await db.rawQuery(
        'PRAGMA table_info(pending_order_submissions)',
      );

      final pendingNames = pendingColumns
          .map((column) => column['name'] as String)
          .toSet();

      expect(
        pendingNames,
        containsAll([
          'order_id',
          'created_at',
          'order_payload',
          'submission_state',
          'updated_at',
        ]),
      );

      final reconciliationColumns = await db.rawQuery(
        'PRAGMA table_info(checkout_reconciliations)',
      );

      final reconciliationNames = reconciliationColumns
          .map((column) => column['name'] as String)
          .toSet();

      expect(
        reconciliationNames,
        containsAll([
          'order_id',
          'cart_snapshot',
          'reconciliation_state',
          'created_at',
          'completed_at',
        ]),
      );

      final pendingCount = await db.rawQuery(
        'SELECT COUNT(*) AS total '
        'FROM pending_order_submissions',
      );

      expect(pendingCount.first['total'], 0);

      final reconciliationCount = await db.rawQuery(
        'SELECT COUNT(*) AS total '
        'FROM checkout_reconciliations',
      );

      expect(reconciliationCount.first['total'], 0);
    } finally {
      if (configured) {
        await service.close();
        service.resetTestingConfiguration();
      }

      await directory.delete(recursive: true);
    }
  });
}
