import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:sudhamrtam_customer_app/database/atomic_checkout_preparation_service.dart';
import 'package:sudhamrtam_customer_app/database/milk_database_service.dart';
import 'package:sudhamrtam_customer_app/models/customer_order.dart';
import 'package:sudhamrtam_customer_app/models/order_item.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(sqfliteFfiInit);

  late Directory directory;
  late Database db;

  final databaseService = MilkDatabaseService.instance;
  final preparationService = AtomicCheckoutPreparationService.instance;

  setUp(() async {
    directory = await Directory.systemTemp.createTemp(
      'sudhamrtam_atomic_checkout_',
    );

    databaseService.configureForTesting(
      factory: databaseFactoryFfi,
      databasePath:
          '${directory.path}${Platform.pathSeparator}atomic_checkout.db',
    );

    db = await databaseService.database;
  });

  tearDown(() async {
    await databaseService.close();
    databaseService.resetTestingConfiguration();
    await directory.delete(recursive: true);
  });

  CustomerOrder makeOrder(String id) {
    return CustomerOrder(
      id: id,
      createdAt: DateTime.utc(2026, 11, 5),
      fulfillmentMethod: FulfillmentMethod.pickup,
      paymentMethod: OrderPaymentMethod.cashOnDelivery,
      items: const [
        OrderItem(
          productId: 'buffalo_milk',
          productName: 'Buffalo Milk',
          unit: 'L',
          quantity: 2,
          unitPrice: 80,
        ),
      ],
    );
  }

  Future<void> seedCart({int quantity = 2}) async {
    await db.insert(MilkDatabaseService.cartItemsTable, {
      'product_id': 'buffalo_milk',
      'quantity': quantity,
    });
  }

  Future<int> rowCount(String table, String orderId) async {
    final rows = await db.query(
      table,
      where: 'order_id = ?',
      whereArgs: [orderId],
    );

    return rows.length;
  }

  test('preparation saves both records atomically', () async {
    final order = makeOrder('atomic-success');

    await seedCart();
    await preparationService.prepareCheckout(order);

    expect(
      await rowCount(
        MilkDatabaseService.pendingOrderSubmissionsTable,
        order.id,
      ),
      1,
    );

    expect(
      await rowCount(
        MilkDatabaseService.checkoutReconciliationsTable,
        order.id,
      ),
      1,
    );

    final cart = await db.query(MilkDatabaseService.cartItemsTable);
    expect(cart.length, 1);
    expect(cart.first['quantity'], 2);
  });

  test('identical preparation is idempotent', () async {
    final order = makeOrder('atomic-repeat');

    await seedCart();
    await preparationService.prepareCheckout(order);
    await preparationService.prepareCheckout(order);

    expect(
      await rowCount(
        MilkDatabaseService.pendingOrderSubmissionsTable,
        order.id,
      ),
      1,
    );

    expect(
      await rowCount(
        MilkDatabaseService.checkoutReconciliationsTable,
        order.id,
      ),
      1,
    );
  });

  test('another unresolved checkout is rejected', () async {
    final firstOrder = makeOrder('atomic-first');
    final secondOrder = makeOrder('atomic-second');

    await seedCart();
    await preparationService.prepareCheckout(firstOrder);

    await expectLater(
      preparationService.prepareCheckout(secondOrder),
      throwsA(isA<StateError>()),
    );

    expect(
      await rowCount(
        MilkDatabaseService.pendingOrderSubmissionsTable,
        secondOrder.id,
      ),
      0,
    );

    expect(
      await rowCount(
        MilkDatabaseService.checkoutReconciliationsTable,
        secondOrder.id,
      ),
      0,
    );
  });

  test('changed cart blocks checkout preparation', () async {
    final order = makeOrder('atomic-cart-changed');

    await seedCart(quantity: 3);

    await expectLater(
      preparationService.prepareCheckout(order),
      throwsA(isA<StateError>()),
    );

    expect(
      await rowCount(
        MilkDatabaseService.pendingOrderSubmissionsTable,
        order.id,
      ),
      0,
    );

    expect(
      await rowCount(
        MilkDatabaseService.checkoutReconciliationsTable,
        order.id,
      ),
      0,
    );

    final cart = await db.query(MilkDatabaseService.cartItemsTable);
    expect(cart.first['quantity'], 3);
  });

  test('failed second insert rolls back first insert', () async {
    final order = makeOrder('atomic-rollback');

    await seedCart();

    // Simulate failure when the reconciliation record
    // is inserted, after the pending order insert.
    await db.execute('''
      CREATE TRIGGER reject_reconciliation_insert
      BEFORE INSERT ON ${MilkDatabaseService.checkoutReconciliationsTable}
      BEGIN
        SELECT RAISE(
          ABORT,
          'Simulated reconciliation insert failure'
        );
      END
    ''');

    await expectLater(
      preparationService.prepareCheckout(order),
      throwsA(isA<Exception>()),
    );

    // Neither record should survive the failed transaction.
    expect(
      await rowCount(
        MilkDatabaseService.pendingOrderSubmissionsTable,
        order.id,
      ),
      0,
    );

    expect(
      await rowCount(
        MilkDatabaseService.checkoutReconciliationsTable,
        order.id,
      ),
      0,
    );

    // The original shopping cart must remain unchanged.
    final cart = await db.query(MilkDatabaseService.cartItemsTable);

    expect(cart.length, 1);
    expect(cart.first['quantity'], 2);

    await db.execute('DROP TRIGGER reject_reconciliation_insert');
  });
}
