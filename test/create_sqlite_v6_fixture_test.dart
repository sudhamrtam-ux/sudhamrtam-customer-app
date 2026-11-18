import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(sqfliteFfiInit);

  test('Protected SQLite v6 migration fixture remains valid', () async {
    const backupFolder =
        r'D:\Sudhamrtam\backups\milestone_126_7_migration_test';

    final fixtureFile = File(
      '$backupFolder${Platform.pathSeparator}'
      'sudhamrtam_milk_before_v7.db',
    );

    expect(
      await fixtureFile.exists(),
      isTrue,
      reason: 'Protected v6 fixture must already exist.',
    );

    final db = await databaseFactoryFfi.openDatabase(
      fixtureFile.path,
      options: OpenDatabaseOptions(readOnly: true, singleInstance: false),
    );

    try {
      final version = await db.rawQuery('PRAGMA user_version');

      expect(
        version.first.values.first,
        6,
        reason: 'The protected fixture must remain at SQLite v6.',
      );

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
        'pending_order_submissions': 0,
      };

      for (final entry in expectedCounts.entries) {
        final rows = await db.rawQuery(
          'SELECT COUNT(*) AS total FROM ${entry.key}',
        );

        expect(
          rows.first['total'],
          entry.value,
          reason: '${entry.key} count must remain unchanged.',
        );
      }

      final reconciliationTable = await db.rawQuery(
        "SELECT name FROM sqlite_master "
        "WHERE type = 'table' AND name = ?",
        ['checkout_reconciliations'],
      );

      expect(
        reconciliationTable,
        isEmpty,
        reason: 'The v7 table must not exist in the v6 fixture.',
      );
    } finally {
      await db.close();
    }
  });
}
