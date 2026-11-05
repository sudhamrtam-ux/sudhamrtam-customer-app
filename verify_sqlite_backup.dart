// ignore_for_file: avoid_print

import 'dart:io';

import 'package:sqflite_common_ffi/sqflite_ffi.dart';

Future<void> main() async {
  sqfliteFfiInit();

  const databasePath =
      r'C:\Sudhamrtam\backups\milestone_126_7_android_sqlite_v4\sudhamrtam_milk.db';

  final file = File(databasePath);

  if (!await file.exists()) {
    throw StateError('Backup file not found.');
  }

  final db = await databaseFactoryFfi.openDatabase(
    databasePath,
    options: OpenDatabaseOptions(readOnly: true),
  );

  try {
    final integrity = await db.rawQuery('PRAGMA integrity_check');
    final version = await db.rawQuery('PRAGMA user_version');

    print('Integrity: $integrity');
    print('Database version: $version');

    const tables = [
      'milk_subscriptions',
      'milk_shift_schedules',
      'cart_items',
      'customer_orders',
      'customer_order_items',
      'customer_profiles',
      'customer_addresses',
    ];

    for (final table in tables) {
      final result = await db.rawQuery('SELECT COUNT(*) AS total FROM $table');

      print('$table: ${result.first['total']}');
    }
  } finally {
    await db.close();
  }
}
