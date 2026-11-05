import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:sudhamrtam_customer_app/database/cart_database_service.dart';
import 'package:sudhamrtam_customer_app/database/milk_database_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() {
    sqfliteFfiInit();
  });

  test('Atomic cart save rolls back when an insert fails', () async {
    final directory = await Directory.systemTemp.createTemp(
      'sudhamrtam_cart_rollback_',
    );

    final databasePath =
        '${directory.path}${Platform.pathSeparator}rollback_test.db';

    final databaseService = MilkDatabaseService.instance;
    final cartService = CartDatabaseService.instance;

    var configured = false;

    try {
      databaseService.configureForTesting(
        factory: databaseFactoryFfi,
        databasePath: databasePath,
      );
      configured = true;

      final db = await databaseService.database;

      // Save a valid initial cart.
      await cartService.saveCartSnapshot({'buffalo_milk': 2, 'cow_milk': 1});

      expect(await cartService.loadCart(), {'buffalo_milk': 2, 'cow_milk': 1});

      // Create a test-only trigger that rejects one insert.
      // This causes the transaction to fail after the cart
      // has already been deleted inside the transaction.
      await db.execute('''
        CREATE TRIGGER reject_test_product
        BEFORE INSERT ON ${MilkDatabaseService.cartItemsTable}
        WHEN NEW.product_id = 'blocked_product'
        BEGIN
          SELECT RAISE(ABORT, 'Simulated SQLite insert failure');
        END
      ''');

      // The first insert succeeds, but the second fails.
      // SQLite must roll back the entire transaction.
      await expectLater(
        cartService.saveCartSnapshot({'buffalo_milk': 5, 'blocked_product': 1}),
        throwsA(isA<Exception>()),
      );

      // Verify the original cart was preserved completely.
      expect(await cartService.loadCart(), {'buffalo_milk': 2, 'cow_milk': 1});

      // Remove the test-only failure trigger.
      await db.execute('DROP TRIGGER reject_test_product');

      // Verify a later valid transaction can succeed.
      await cartService.saveCartSnapshot({'buffalo_milk': 5, 'cow_milk': 3});

      expect(await cartService.loadCart(), {'buffalo_milk': 5, 'cow_milk': 3});

      // Confirm database integrity.
      final integrity = await db.rawQuery('PRAGMA integrity_check');
      expect(integrity.first.values.first, 'ok');
    } finally {
      if (configured) {
        await databaseService.close();
        databaseService.resetTestingConfiguration();
      }

      await directory.delete(recursive: true);
    }
  });
}
