import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:sudhamrtam_customer_app/app/checkout_startup_controller.dart';
import 'package:sudhamrtam_customer_app/database/checkout_recovery_executor.dart';
import 'package:sudhamrtam_customer_app/database/milk_database_service.dart';
import 'package:sudhamrtam_customer_app/models/customer_order.dart';
import 'package:sudhamrtam_customer_app/models/order_item.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(sqfliteFfiInit);

  final databaseService = MilkDatabaseService.instance;

  late Directory directory;
  late Database db;

  const orderId = 'startup-recovery-order-001';
  const productId = 'cow_milk';
  const initialQuantity = 2;
  const unitPrice = 50.0;
  const createdAt = '2026-11-05T09:00:00';

  setUp(() async {
    directory = await Directory.systemTemp.createTemp(
      'sudhamrtam_saved_order_recovery_',
    );

    databaseService.configureForTesting(
      factory: databaseFactoryFfi,
      databasePath: '${directory.path}${Platform.pathSeparator}checkout.db',
    );

    db = await databaseService.database;
  });

  tearDown(() async {
    await databaseService.close();
    databaseService.resetTestingConfiguration();
    await directory.delete(recursive: true);
  });

  // =====================================================
  // ORIGINAL PENDING ORDER SNAPSHOT
  // =====================================================

  CustomerOrder createPendingOrder() {
    return CustomerOrder(
      id: orderId,
      createdAt: DateTime.parse(createdAt),
      items: [
        OrderItem(
          productId: productId,
          productName: 'Cow Milk',
          unit: 'litre',
          quantity: initialQuantity,
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

  // =====================================================
  // SQLITE TEST FIXTURES
  // =====================================================

  Future<void> prepareSavedOrderScenario({
    int cartQuantity = initialQuantity,
    int savedOrderQuantity = initialQuantity,
    double savedUnitPrice = unitPrice,
    String savedProductId = productId,
    String savedPaymentMethod = 'cashOnDelivery',
    String reconciliationState = 'pending',
    bool includeCart = true,
  }) async {
    final pendingOrder = createPendingOrder();

    if (includeCart) {
      await db.insert(MilkDatabaseService.cartItemsTable, {
        'product_id': productId,
        'quantity': cartQuantity,
      });
    }

    await db.insert(MilkDatabaseService.ordersTable, {
      'id': orderId,
      'created_at': createdAt,
      'fulfillment_method': 'pickup',
      'payment_method': savedPaymentMethod,
      'status': 'pending',
      'delivery_address': null,
      'notes': null,
      'subtotal': savedOrderQuantity * savedUnitPrice,
    });

    await db.insert(MilkDatabaseService.orderItemsTable, {
      'order_id': orderId,
      'product_id': savedProductId,
      'product_name': 'Cow Milk',
      'unit': 'litre',
      'quantity': savedOrderQuantity,
      'unit_price': savedUnitPrice,
    });

    await db.insert(MilkDatabaseService.pendingOrderSubmissionsTable, {
      'order_id': orderId,
      'created_at': createdAt,
      'order_payload': encodePendingOrder(pendingOrder),
      'submission_state': 'prepared',
      'updated_at': createdAt,
    });

    await db.insert(MilkDatabaseService.checkoutReconciliationsTable, {
      'order_id': orderId,
      'cart_snapshot': jsonEncode({productId: initialQuantity}),
      'reconciliation_state': reconciliationState,
      'created_at': createdAt,
      'completed_at': reconciliationState == 'completed'
          ? '2026-11-05T09:01:00'
          : null,
    });
  }

  CheckoutStartupController createController(List<String> events) {
    return CheckoutStartupController(
      recover: () async {
        events.add('recovery');
        return CheckoutRecoveryExecutor.instance.recoverAtStartup();
      },
      initializeCart: () async {
        events.add('cart');

        final cartRows = await db.query(MilkDatabaseService.cartItemsTable);

        if (cartRows.isNotEmpty) {
          throw StateError('Cart initialized before persisted reconciliation.');
        }
      },
    );
  }

  // =====================================================
  // SHARED SAFETY ASSERTIONS
  // =====================================================

  Future<void> expectBlockedWithoutDataLoss({
    required String expectedReconciliationState,
    int expectedCartQuantity = initialQuantity,
  }) async {
    final events = <String>[];
    final controller = createController(events);

    final result = await controller.start();

    expect(
      result.status,
      CheckoutRecoveryExecutionStatus.blocked,
      reason: result.message,
    );

    expect(controller.isReady, isFalse);
    expect(events, ['recovery']);

    // A blocked recovery must preserve the persisted cart.
    final cartRows = await db.query(MilkDatabaseService.cartItemsTable);

    expect(cartRows.length, 1);
    expect(cartRows.single['product_id'], productId);
    expect(cartRows.single['quantity'], expectedCartQuantity);

    // The original pending submission must remain available.
    final pendingRows = await db.query(
      MilkDatabaseService.pendingOrderSubmissionsTable,
    );

    expect(pendingRows.length, 1);
    expect(pendingRows.single['order_id'], orderId);

    expect(
      pendingRows.single['order_payload'],
      encodePendingOrder(createPendingOrder()),
    );

    // Recovery must not change reconciliation state.
    final reconciliationRows = await db.query(
      MilkDatabaseService.checkoutReconciliationsTable,
      where: 'order_id = ?',
      whereArgs: [orderId],
    );

    expect(reconciliationRows.length, 1);
    expect(
      reconciliationRows.single['reconciliation_state'],
      expectedReconciliationState,
    );

    // The saved order must not be deleted.
    final savedOrders = await db.query(
      MilkDatabaseService.ordersTable,
      where: 'id = ?',
      whereArgs: [orderId],
    );

    expect(savedOrders.length, 1);

    final savedItems = await db.query(
      MilkDatabaseService.orderItemsTable,
      where: 'order_id = ?',
      whereArgs: [orderId],
    );

    expect(savedItems.length, 1);
  }

  // =====================================================
  // TEST 1: SUCCESSFUL RECOVERY
  // =====================================================

  test('Saved order recovers before cart initialization', () async {
    await prepareSavedOrderScenario();

    final events = <String>[];
    final controller = createController(events);

    final result = await controller.start();

    expect(
      result.status,
      CheckoutRecoveryExecutionStatus.recovered,
      reason: result.message,
    );

    expect(result.orderId, orderId);
    expect(controller.isReady, isTrue);
    expect(events, ['recovery', 'cart']);

    final cartRows = await db.query(MilkDatabaseService.cartItemsTable);

    expect(cartRows, isEmpty);

    final pendingRows = await db.query(
      MilkDatabaseService.pendingOrderSubmissionsTable,
    );

    expect(pendingRows, isEmpty);

    final reconciliationRows = await db.query(
      MilkDatabaseService.checkoutReconciliationsTable,
      where: 'order_id = ?',
      whereArgs: [orderId],
    );

    expect(reconciliationRows.length, 1);
    expect(reconciliationRows.single['reconciliation_state'], 'completed');
    expect(reconciliationRows.single['completed_at'], isNotNull);

    final savedOrders = await db.query(
      MilkDatabaseService.ordersTable,
      where: 'id = ?',
      whereArgs: [orderId],
    );

    expect(savedOrders.length, 1);

    final savedItems = await db.query(
      MilkDatabaseService.orderItemsTable,
      where: 'order_id = ?',
      whereArgs: [orderId],
    );

    expect(savedItems.length, 1);
    expect(savedItems.single['quantity'], initialQuantity);
  });

  // =====================================================
  // TEST 2: CHANGED PERSISTED CART
  // =====================================================

  test('Changed persisted cart blocks automatic recovery', () async {
    await prepareSavedOrderScenario(cartQuantity: 3);

    await expectBlockedWithoutDataLoss(
      expectedReconciliationState: 'pending',
      expectedCartQuantity: 3,
    );
  });

  // =====================================================
  // TEST 3: QUANTITY MISMATCH
  // =====================================================

  test('Saved order item mismatch blocks recovery', () async {
    await prepareSavedOrderScenario(savedOrderQuantity: 3);

    await expectBlockedWithoutDataLoss(expectedReconciliationState: 'pending');
  });

  // =====================================================
  // TEST 4: SAFE RESTART
  // =====================================================

  test('Restart after successful recovery is safe', () async {
    await prepareSavedOrderScenario();

    final firstEvents = <String>[];
    final firstController = createController(firstEvents);

    final firstResult = await firstController.start();

    expect(
      firstResult.status,
      CheckoutRecoveryExecutionStatus.recovered,
      reason: firstResult.message,
    );

    expect(firstController.isReady, isTrue);
    expect(firstEvents, ['recovery', 'cart']);

    // Simulate restarting against the recovered database.
    final secondEvents = <String>[];
    final secondController = createController(secondEvents);

    final secondResult = await secondController.start();

    expect(
      secondResult.status,
      CheckoutRecoveryExecutionStatus.noRecoveryNeeded,
      reason: secondResult.message,
    );

    expect(secondController.isReady, isTrue);
    expect(secondEvents, ['recovery', 'cart']);

    final pendingRows = await db.query(
      MilkDatabaseService.pendingOrderSubmissionsTable,
    );

    expect(pendingRows, isEmpty);

    final reconciliations = await db.query(
      MilkDatabaseService.checkoutReconciliationsTable,
    );

    expect(reconciliations.length, 1);
    expect(reconciliations.single['reconciliation_state'], 'completed');
  });

  // =====================================================
  // TEST 5: UNIT PRICE MISMATCH
  // =====================================================

  test('Saved order price mismatch blocks recovery', () async {
    await prepareSavedOrderScenario(savedUnitPrice: 60.0);

    await expectBlockedWithoutDataLoss(expectedReconciliationState: 'pending');
  });

  // =====================================================
  // TEST 6: PRODUCT ID MISMATCH
  // =====================================================

  test('Saved order product mismatch blocks recovery', () async {
    await prepareSavedOrderScenario(savedProductId: 'different_product');

    await expectBlockedWithoutDataLoss(expectedReconciliationState: 'pending');
  });

  // =====================================================
  // TEST 7: PAYMENT METHOD MISMATCH
  // =====================================================

  test('Saved order payment mismatch blocks recovery', () async {
    await prepareSavedOrderScenario(savedPaymentMethod: 'online');

    await expectBlockedWithoutDataLoss(expectedReconciliationState: 'pending');
  });

  // =====================================================
  // TEST 8: COMPLETED RECONCILIATION PRICE MISMATCH
  // =====================================================

  test(
    'Completed reconciliation with price mismatch preserves pending order',
    () async {
      await prepareSavedOrderScenario(
        savedUnitPrice: 60.0,
        reconciliationState: 'completed',
      );

      await expectBlockedWithoutDataLoss(
        expectedReconciliationState: 'completed',
      );
    },
  );

  // =====================================================
  // TEST 9: COMPLETED RECONCILIATION MATCH
  // =====================================================

  test(
    'Completed reconciliation with matching snapshot cleans pending order',
    () async {
      // A completed reconciliation means the persisted cart
      // has already been cleared by the earlier transaction.
      await prepareSavedOrderScenario(
        reconciliationState: 'completed',
        includeCart: false,
      );

      final events = <String>[];
      final controller = createController(events);

      final result = await controller.start();

      expect(
        result.status,
        CheckoutRecoveryExecutionStatus.recovered,
        reason: result.message,
      );

      expect(result.orderId, orderId);
      expect(controller.isReady, isTrue);
      expect(events, ['recovery', 'cart']);

      // Only pending submission cleanup remains.
      final pendingRows = await db.query(
        MilkDatabaseService.pendingOrderSubmissionsTable,
      );

      expect(pendingRows, isEmpty);

      // Reconciliation must remain completed.
      final reconciliationRows = await db.query(
        MilkDatabaseService.checkoutReconciliationsTable,
        where: 'order_id = ?',
        whereArgs: [orderId],
      );

      expect(reconciliationRows.length, 1);
      expect(reconciliationRows.single['reconciliation_state'], 'completed');

      // The cart must remain empty.
      final cartRows = await db.query(MilkDatabaseService.cartItemsTable);

      expect(cartRows, isEmpty);

      // The saved order must remain durable.
      final savedOrders = await db.query(
        MilkDatabaseService.ordersTable,
        where: 'id = ?',
        whereArgs: [orderId],
      );

      expect(savedOrders.length, 1);
    },
  );

  // =====================================================
  // TEST 10: COMPLETED RECONCILIATION QUANTITY MISMATCH
  // =====================================================

  test(
    'Completed reconciliation with quantity mismatch preserves pending order',
    () async {
      await prepareSavedOrderScenario(
        savedOrderQuantity: 3,
        reconciliationState: 'completed',
        includeCart: false,
      );

      final events = <String>[];
      final controller = createController(events);

      final result = await controller.start();

      expect(
        result.status,
        CheckoutRecoveryExecutionStatus.blocked,
        reason: result.message,
      );

      expect(controller.isReady, isFalse);
      expect(events, ['recovery']);

      final pendingRows = await db.query(
        MilkDatabaseService.pendingOrderSubmissionsTable,
      );

      expect(pendingRows.length, 1);
      expect(
        pendingRows.single['order_payload'],
        encodePendingOrder(createPendingOrder()),
      );

      final reconciliationRows = await db.query(
        MilkDatabaseService.checkoutReconciliationsTable,
        where: 'order_id = ?',
        whereArgs: [orderId],
      );

      expect(reconciliationRows.length, 1);
      expect(reconciliationRows.single['reconciliation_state'], 'completed');

      final cartRows = await db.query(MilkDatabaseService.cartItemsTable);

      expect(cartRows, isEmpty);

      final savedItems = await db.query(
        MilkDatabaseService.orderItemsTable,
        where: 'order_id = ?',
        whereArgs: [orderId],
      );

      expect(savedItems.length, 1);
      expect(savedItems.single['quantity'], 3);
    },
  );
}
