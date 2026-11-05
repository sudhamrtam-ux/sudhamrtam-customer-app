import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:sudhamrtam_customer_app/database/milk_database_service.dart';
import 'package:sudhamrtam_customer_app/models/cart_manager.dart';
import 'package:sudhamrtam_customer_app/models/product_catalog.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() {
    sqfliteFfiInit();
  });

  test(
    'Checkout refuses to proceed after SQLite persistence failure',
    () async {
      final directory = await Directory.systemTemp.createTemp(
        'sudhamrtam_cart_failure_',
      );

      final databasePath =
          '${directory.path}${Platform.pathSeparator}cart_failure.db';

      final databaseService = MilkDatabaseService.instance;
      final cart = CartManager();

      var configured = false;

      try {
        databaseService.configureForTesting(
          factory: databaseFactoryFfi,
          databasePath: databasePath,
        );
        configured = true;

        await cart.initialize();

        final product = ProductCatalog.products.first;
        final db = await databaseService.database;

        // Simulate a database write failure by removing
        // the cart table in this disposable test database.
        await db.execute('DROP TABLE ${MilkDatabaseService.cartItemsTable}');

        // Queue a cart save. It should fail because the
        // cart table is missing.
        expect(cart.addProduct(product), isTrue);

        await cart.waitForPendingSaves();

        expect(cart.hasPersistenceError, isTrue);

        // Checkout must reject the unsaved cart.
        await expectLater(
          cart.beginCheckoutCartLock(),
          throwsA(isA<StateError>()),
        );

        expect(cart.isCheckoutLocked, isFalse);

        // Restore the table to simulate database recovery.
        await db.execute('''
        CREATE TABLE ${MilkDatabaseService.cartItemsTable} (
          product_id TEXT PRIMARY KEY,
          quantity INTEGER NOT NULL
            CHECK (quantity >= 1 AND quantity <= 100)
        )
      ''');

        // Trigger another complete cart snapshot save.
        expect(cart.increaseQuantity(product.id), isTrue);

        await cart.waitForPendingSaves();

        expect(cart.hasPersistenceError, isFalse);

        // Checkout should now be allowed.
        expect(await cart.beginCheckoutCartLock(), isTrue);
        expect(cart.isCheckoutLocked, isTrue);

        final rows = await db.query(
          MilkDatabaseService.cartItemsTable,
          where: 'product_id = ?',
          whereArgs: [product.id],
        );

        expect(rows.length, 1);
        expect(rows.first['quantity'], 2);

        cart.endCheckoutCartLock();
      } finally {
        cart.endCheckoutCartLock();

        // Ensure all queued saves have finished before closing.
        await cart.waitForPendingSaves();
        cart.dispose();

        if (configured) {
          await databaseService.close();
          databaseService.resetTestingConfiguration();
        }

        await directory.delete(recursive: true);
      }
    },
  );
}
