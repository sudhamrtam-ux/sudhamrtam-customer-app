import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('SQLite v5 baseline is ready for v6 migration', () async {
    sqfliteFfiInit();

    const sourcePath =
        r'C:\Sudhamrtam\backups\milestone_126_7_migration_test\sudhamrtam_milk_before_v6.db';

    expect(
      File(sourcePath).existsSync(),
      isTrue,
      reason: 'The protected SQLite v5 backup must exist.',
    );

    final directory = await Directory.systemTemp.createTemp(
      'sudhamrtam_v6_baseline_',
    );

    final testPath = '${directory.path}${Platform.pathSeparator}baseline.db';

    Database? db;

    try {
      // Always test a disposable copy.
      await File(sourcePath).copy(testPath);

      db = await databaseFactoryFfi.openDatabase(
        testPath,
        options: OpenDatabaseOptions(readOnly: true, singleInstance: false),
      );

      final version = await db.rawQuery('PRAGMA user_version');

      expect(version.first.values.first, 5);

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
          reason: '${entry.key} must retain its baseline count.',
        );
      }

      final pendingTable = await db.rawQuery(
        "SELECT name FROM sqlite_master "
        "WHERE type = 'table' AND name = ?",
        ['pending_order_submissions'],
      );

      // This table will be introduced in SQLite v6.
      expect(pendingTable, isEmpty);
    } finally {
      await db?.close();
      await directory.delete(recursive: true);
    }
  });
}
