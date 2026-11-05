import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:sudhamrtam_customer_app/app/checkout_startup_controller.dart';
import 'package:sudhamrtam_customer_app/database/checkout_recovery_executor.dart';
import 'package:sudhamrtam_customer_app/database/milk_database_service.dart';
import 'package:sudhamrtam_customer_app/models/cart_manager.dart';
import 'package:sudhamrtam_customer_app/models/customer_order.dart';
import 'package:sudhamrtam_customer_app/models/order_item.dart';
import 'package:sudhamrtam_customer_app/models/product_catalog.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(sqfliteFfiInit);

  final databaseService = MilkDatabaseService.instance;

  late Directory directory;
  late Database db;

  const orderId = 'real-cart-recovery-001';
  const quantity = 2;
  const createdAt = '2026-11-05T09:00:00';
  const unitPrice = 50.0;

  late String productId;

  setUp(() async {
    directory = await Directory.systemTemp.createTemp(
      'sudhamrtam_real_cart_startup_',
    );

    databaseService.configureForTesting(
      factory: databaseFactoryFfi,
      databasePath: '${directory.path}${Platform.pathSeparator}checkout.db',
    );

    db = await databaseService.database;

    expect(
      ProductCatalog.products,
      isNotEmpty,
      reason: 'The cart test requires a catalog product.',
    );

    productId = ProductCatalog.products.first.id;
  });

  tearDown(() async {
    await databaseService.close();
    databaseService.resetTestingConfiguration();
    await directory.delete(recursive: true);
  });

  CustomerOrder createPendingOrder() {
    return CustomerOrder(
      id: orderId,
      createdAt: DateTime.parse(createdAt),
      items: [
        OrderItem(
          productId: productId,
          productName: 'Startup Test Product',
          unit: 'unit',
          quantity: quantity,
          unitPrice: unitPrice,
        ),
      ],
      fulfillmentMethod: FulfillmentMethod.pickup,
      paymentMethod: OrderPaymentMethod.cashOnDelivery,
      status: OrderStatus.pending,
    );
  }

  String encodePendingOrder(CustomerOrder order) {
    return jsonEncode({
      'order': order.toMap(),
      'items': [for (final item in order.items) item.toMap()],
    });
  }

  Future<void> insertCart({int cartQuantity = quantity}) async {
    await db.insert(MilkDatabaseService.cartItemsTable, {
      'product_id': productId,
      'quantity': cartQuantity,
    });
  }

  Future<void> insertPendingSubmission() async {
    final pendingOrder = createPendingOrder();

    await db.insert(MilkDatabaseService.pendingOrderSubmissionsTable, {
      'order_id': orderId,
      'created_at': createdAt,
      'order_payload': encodePendingOrder(pendingOrder),
      'submission_state': 'prepared',
      'updated_at': createdAt,
    });
  }

  Future<void> insertReconciliation({String state = 'pending'}) async {
    await db.insert(MilkDatabaseService.checkoutReconciliationsTable, {
      'order_id': orderId,
      'cart_snapshot': jsonEncode({productId: quantity}),
      'reconciliation_state': state,
      'created_at': createdAt,
      'completed_at': state == 'completed' ? '2026-11-05T09:01:00' : null,
    });
  }

  Future<void> insertSavedOrder({int itemQuantity = quantity}) async {
    await db.insert(MilkDatabaseService.ordersTable, {
      'id': orderId,
      'created_at': createdAt,
      'fulfillment_method': 'pickup',
      'payment_method': 'cashOnDelivery',
      'status': 'pending',
      'delivery_address': null,
      'notes': null,
      'subtotal': itemQuantity * unitPrice,
    });

    await db.insert(MilkDatabaseService.orderItemsTable, {
      'order_id': orderId,
      'product_id': productId,
      'product_name': 'Startup Test Product',
      'unit': 'unit',
      'quantity': itemQuantity,
      'unit_price': unitPrice,
    });
  }

  CheckoutStartupController createController(
    CartManager cart,
    List<String> events,
  ) {
    return CheckoutStartupController(
      recover: () async {
        events.add('recovery');

        return CheckoutRecoveryExecutor.instance.recoverAtStartup();
      },
      initializeCart: () async {
        events.add('cart');
        await cart.initialize();
      },
    );
  }

  test('Saved order recovery initializes real cart as empty', () async {
    await insertCart();
    await insertSavedOrder();
    await insertPendingSubmission();
    await insertReconciliation();

    final cart = CartManager();
    addTearDown(cart.dispose);

    final events = <String>[];
    final controller = createController(cart, events);

    final result = await controller.start();

    expect(
      result.status,
      CheckoutRecoveryExecutionStatus.recovered,
      reason: result.message,
    );

    expect(controller.isReady, isTrue);
    expect(cart.isInitialized, isTrue);
    expect(cart.isEmpty, isTrue);
    expect(cart.totalQuantity, 0);
    expect(events, ['recovery', 'cart']);

    final persistedCart = await db.query(MilkDatabaseService.cartItemsTable);

    expect(persistedCart, isEmpty);

    final pending = await db.query(
      MilkDatabaseService.pendingOrderSubmissionsTable,
    );

    expect(pending, isEmpty);

    final reconciliations = await db.query(
      MilkDatabaseService.checkoutReconciliationsTable,
    );

    expect(reconciliations.single['reconciliation_state'], 'completed');
  });

  test('Unsubmitted checkout prevents real cart initialization', () async {
    await insertCart();
    await insertPendingSubmission();
    await insertReconciliation();

    final cart = CartManager();
    addTearDown(cart.dispose);

    final events = <String>[];
    final controller = createController(cart, events);

    final result = await controller.start();

    expect(
      result.status,
      CheckoutRecoveryExecutionStatus.awaitingSubmission,
      reason: result.message,
    );

    expect(controller.isReady, isFalse);
    expect(cart.isInitialized, isFalse);
    expect(events, ['recovery']);

    final persistedCart = await db.query(MilkDatabaseService.cartItemsTable);

    expect(persistedCart.length, 1);
    expect(persistedCart.single['quantity'], quantity);

    final pending = await db.query(
      MilkDatabaseService.pendingOrderSubmissionsTable,
    );

    expect(pending.length, 1);
  });

  test('Reconciliation failure preserves cart and blocks startup', () async {
    await insertCart(cartQuantity: 3);
    await insertSavedOrder();
    await insertPendingSubmission();
    await insertReconciliation();

    final cart = CartManager();
    addTearDown(cart.dispose);

    final events = <String>[];
    final controller = createController(cart, events);

    final result = await controller.start();

    expect(
      result.status,
      CheckoutRecoveryExecutionStatus.blocked,
      reason: result.message,
    );

    expect(controller.isReady, isFalse);
    expect(cart.isInitialized, isFalse);
    expect(events, ['recovery']);

    final persistedCart = await db.query(MilkDatabaseService.cartItemsTable);

    expect(persistedCart.length, 1);
    expect(persistedCart.single['quantity'], 3);

    final pending = await db.query(
      MilkDatabaseService.pendingOrderSubmissionsTable,
    );

    expect(pending.length, 1);

    final reconciliations = await db.query(
      MilkDatabaseService.checkoutReconciliationsTable,
    );

    expect(reconciliations.single['reconciliation_state'], 'pending');
  });

  test('Second startup initializes fresh CartManager correctly', () async {
    await insertCart();
    await insertSavedOrder();
    await insertPendingSubmission();
    await insertReconciliation();

    final firstCart = CartManager();
    addTearDown(firstCart.dispose);

    final firstController = createController(firstCart, <String>[]);

    final firstResult = await firstController.start();

    expect(
      firstResult.status,
      CheckoutRecoveryExecutionStatus.recovered,
      reason: firstResult.message,
    );

    expect(firstCart.isInitialized, isTrue);
    expect(firstCart.isEmpty, isTrue);

    // Simulate another launch against the recovered database.
    final secondCart = CartManager();
    addTearDown(secondCart.dispose);

    final events = <String>[];
    final secondController = createController(secondCart, events);

    final secondResult = await secondController.start();

    expect(
      secondResult.status,
      CheckoutRecoveryExecutionStatus.noRecoveryNeeded,
      reason: secondResult.message,
    );

    expect(secondController.isReady, isTrue);
    expect(secondCart.isInitialized, isTrue);
    expect(secondCart.isEmpty, isTrue);
    expect(events, ['recovery', 'cart']);
  });

  test('Clean startup restores a persisted catalog product', () async {
    await insertCart();

    final cart = CartManager();
    addTearDown(cart.dispose);

    final events = <String>[];
    final controller = createController(cart, events);

    final result = await controller.start();

    expect(
      result.status,
      CheckoutRecoveryExecutionStatus.noRecoveryNeeded,
      reason: result.message,
    );

    expect(controller.isReady, isTrue);
    expect(cart.isInitialized, isTrue);
    expect(cart.quantityFor(productId), quantity);
    expect(cart.totalQuantity, quantity);
    expect(events, ['recovery', 'cart']);

    final persistedCart = await db.query(MilkDatabaseService.cartItemsTable);

    expect(persistedCart.length, 1);
    expect(persistedCart.single['quantity'], quantity);
  });
}
