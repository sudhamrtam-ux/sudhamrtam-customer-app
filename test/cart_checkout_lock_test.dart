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

  test('Checkout lock protects cart and waits for SQLite saves', () async {
    final directory = await Directory.systemTemp.createTemp(
      'sudhamrtam_cart_lock_',
    );

    final databasePath =
        '${directory.path}${Platform.pathSeparator}cart_lock.db';

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

      expect(cart.isInitialized, isTrue);
      expect(cart.isCheckoutLocked, isFalse);
      expect(cart.hasPersistenceError, isFalse);

      final product = ProductCatalog.products.first;

      expect(cart.addProduct(product), isTrue);

      // Checkout must wait for the queued SQLite save.
      final locked = await cart.beginCheckoutCartLock();

      expect(locked, isTrue);
      expect(cart.isCheckoutLocked, isTrue);
      expect(cart.hasPersistenceError, isFalse);

      // Verify the cart item was persisted.
      final db = await databaseService.database;

      final rows = await db.query(
        MilkDatabaseService.cartItemsTable,
        where: 'product_id = ?',
        whereArgs: [product.id],
      );

      expect(rows.length, 1);
      expect(rows.first['quantity'], 1);

      // Cart mutations must be rejected during checkout.
      expect(cart.addProduct(product), isFalse);
      expect(cart.increaseQuantity(product.id), isFalse);
      expect(cart.decreaseQuantity(product.id), isFalse);
      expect(cart.updateQuantity(product.id, 2), isFalse);
      expect(cart.removeProduct(product.id), isFalse);

      cart.clearCart();
      expect(cart.quantityFor(product.id), 1);

      // A second checkout lock must not be granted.
      expect(await cart.beginCheckoutCartLock(), isFalse);

      // Unlocking restores normal cart operations.
      cart.endCheckoutCartLock();

      expect(cart.isCheckoutLocked, isFalse);
      expect(cart.increaseQuantity(product.id), isTrue);

      await cart.waitForPendingSaves();

      final updatedRows = await db.query(
        MilkDatabaseService.cartItemsTable,
        where: 'product_id = ?',
        whereArgs: [product.id],
      );

      expect(updatedRows.length, 1);
      expect(updatedRows.first['quantity'], 2);
      expect(cart.hasPersistenceError, isFalse);
    } finally {
      cart.endCheckoutCartLock();
      cart.dispose();

      if (configured) {
        await databaseService.close();
        databaseService.resetTestingConfiguration();
      }

      await directory.delete(recursive: true);
    }
  });
}
