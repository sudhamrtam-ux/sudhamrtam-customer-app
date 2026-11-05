import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:sudhamrtam_customer_app/database/cart_database_service.dart';
import 'package:sudhamrtam_customer_app/database/milk_database_service.dart';
import 'package:sudhamrtam_customer_app/models/cart_manager.dart';
import 'package:sudhamrtam_customer_app/models/product_catalog.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  sqfliteFfiInit();

  late Directory testDirectory;
  late CartManager cart;

  setUp(() async {
    testDirectory = await Directory.systemTemp.createTemp(
      'sudhamrtam_cart_refresh_',
    );

    MilkDatabaseService.instance.configureForTesting(
      factory: databaseFactoryFfi,
      databasePath: '${testDirectory.path}/cart_refresh.db',
    );

    cart = CartManager();
  });

  tearDown(() async {
    cart.dispose();
    await MilkDatabaseService.instance.close();
    if (await testDirectory.exists()) {
      await testDirectory.delete(recursive: true);
    }
  });

  test(
    'refresh updates memory from SQLite without restoring old cart items',
    () async {
      final product = ProductCatalog.products.first;

      await cart.initialize();

      expect(cart.addProduct(product, quantity: 2), isTrue);
      await cart.waitForPendingSaves();

      expect(cart.quantityFor(product.id), 2);

      final locked = await cart.beginCheckoutCartLock();
      expect(locked, isTrue);

      try {
        // Simulate the SQLite cart state after reconciliation.
        await CartDatabaseService.instance.clearCart();

        // Memory still contains the original items.
        expect(cart.quantityFor(product.id), 2);

        await cart.refreshAfterCheckoutReconciliation();

        expect(cart.isEmpty, isTrue);
        expect(await CartDatabaseService.instance.loadCart(), isEmpty);

        // Verify that no delayed cart save restores the old items.
        await cart.waitForPendingSaves();

        expect(await CartDatabaseService.instance.loadCart(), isEmpty);
      } finally {
        cart.endCheckoutCartLock();
      }
    },
  );

  test('refresh requires the checkout cart lock', () async {
    await cart.initialize();

    await expectLater(
      cart.refreshAfterCheckoutReconciliation(),
      throwsStateError,
    );
  });

  test('cart can accept new items after refresh and unlock', () async {
    final product = ProductCatalog.products.first;

    await cart.initialize();

    expect(cart.addProduct(product), isTrue);
    await cart.waitForPendingSaves();

    expect(await cart.beginCheckoutCartLock(), isTrue);

    try {
      await CartDatabaseService.instance.clearCart();
      await cart.refreshAfterCheckoutReconciliation();

      expect(cart.isEmpty, isTrue);
    } finally {
      cart.endCheckoutCartLock();
    }

    expect(cart.addProduct(product, quantity: 3), isTrue);
    await cart.waitForPendingSaves();

    expect(cart.quantityFor(product.id), 3);
    expect(await CartDatabaseService.instance.loadCart(), {product.id: 3});
  });
}
