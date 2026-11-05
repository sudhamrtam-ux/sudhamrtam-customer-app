import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:sudhamrtam_customer_app/database/checkout_reconciliation_service.dart';
import 'package:sudhamrtam_customer_app/database/milk_database_service.dart';
import 'package:sudhamrtam_customer_app/models/customer_order.dart';
import 'package:sudhamrtam_customer_app/models/order_item.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(sqfliteFfiInit);

  late Directory directory;
  late Database db;

  final databaseService = MilkDatabaseService.instance;
  final reconciliationService = CheckoutReconciliationService.instance;

  setUp(() async {
    directory = await Directory.systemTemp.createTemp(
      'sudhamrtam_checkout_reconciliation_',
    );

    databaseService.configureForTesting(
      factory: databaseFactoryFfi,
      databasePath:
          '${directory.path}${Platform.pathSeparator}reconciliation.db',
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
      status: OrderStatus.pending,
      items: const [
        OrderItem(
          productId: 'buffalo_milk',
          productName: 'Buffalo Milk',
          unit: 'L',
          quantity: 2,
          unitPrice: 80,
        ),
      ],
      deliveryAddress: null,
      notes: null,
    );
  }

  Future<void> seedCart({int quantity = 2}) async {
    await db.insert(MilkDatabaseService.cartItemsTable, {
      'product_id': 'buffalo_milk',
      'quantity': quantity,
    });
  }

  Future<void> seedSavedOrder(String id) async {
    final order = makeOrder(id);

    await db.insert(MilkDatabaseService.ordersTable, order.toMap());

    for (final item in order.items) {
      await db.insert(MilkDatabaseService.orderItemsTable, {
        'order_id': id,
        ...item.toMap(),
      });
    }
  }

  Future<int> cartQuantity() async {
    final rows = await db.query(
      MilkDatabaseService.cartItemsTable,
      where: 'product_id = ?',
      whereArgs: ['buffalo_milk'],
    );

    return rows.isEmpty ? 0 : rows.first['quantity'] as int;
  }

  test('saved order reconciles matching cart', () async {
    final order = makeOrder('order-success');

    await seedCart();
    await reconciliationService.prepareReconciliation(order);
    await seedSavedOrder(order.id);

    final result = await reconciliationService.reconcileSavedOrder(order.id);

    expect(result, isTrue);
    expect(await cartQuantity(), 0);
    expect(
      await reconciliationService.getReconciliationState(order.id),
      CheckoutReconciliationService.completed,
    );
  });

  test('repeated reconciliation does not clear new cart items', () async {
    final order = makeOrder('order-idempotent');

    await seedCart();
    await reconciliationService.prepareReconciliation(order);
    await seedSavedOrder(order.id);

    expect(await reconciliationService.reconcileSavedOrder(order.id), isTrue);

    // Simulate a later cart addition.
    await seedCart(quantity: 1);

    expect(await reconciliationService.reconcileSavedOrder(order.id), isFalse);

    expect(await cartQuantity(), 1);
  });

  test('unsaved order cannot reconcile', () async {
    final order = makeOrder('order-unsaved');

    await seedCart();
    await reconciliationService.prepareReconciliation(order);

    await expectLater(
      reconciliationService.reconcileSavedOrder(order.id),
      throwsA(isA<StateError>()),
    );

    expect(await cartQuantity(), 2);
    expect(
      await reconciliationService.getReconciliationState(order.id),
      CheckoutReconciliationService.pending,
    );
  });

  test('changed cart blocks reconciliation', () async {
    final order = makeOrder('order-cart-changed');

    await seedCart();
    await reconciliationService.prepareReconciliation(order);
    await seedSavedOrder(order.id);

    await db.update(
      MilkDatabaseService.cartItemsTable,
      {'quantity': 3},
      where: 'product_id = ?',
      whereArgs: ['buffalo_milk'],
    );

    await expectLater(
      reconciliationService.reconcileSavedOrder(order.id),
      throwsA(isA<StateError>()),
    );

    expect(await cartQuantity(), 3);
    expect(
      await reconciliationService.getReconciliationState(order.id),
      CheckoutReconciliationService.pending,
    );
  });

  test('failed transaction rolls back cart deletion', () async {
    final order = makeOrder('order-rollback');

    await seedCart();
    await reconciliationService.prepareReconciliation(order);
    await seedSavedOrder(order.id);

    // Force the reconciliation state update to fail
    // after the cart deletion has been attempted.
    await db.execute('''
      CREATE TRIGGER reject_checkout_completion
      BEFORE UPDATE ON ${MilkDatabaseService.checkoutReconciliationsTable}
      WHEN NEW.reconciliation_state = 'completed'
      BEGIN
        SELECT RAISE(ABORT, 'Simulated reconciliation failure');
      END
    ''');

    await expectLater(
      reconciliationService.reconcileSavedOrder(order.id),
      throwsA(isA<Exception>()),
    );

    // SQLite must roll back the cart deletion.
    expect(await cartQuantity(), 2);
    expect(
      await reconciliationService.getReconciliationState(order.id),
      CheckoutReconciliationService.pending,
    );

    await db.execute('DROP TRIGGER reject_checkout_completion');
  });
}
