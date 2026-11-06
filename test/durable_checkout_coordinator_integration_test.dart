import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:sudhamrtam_customer_app/database/atomic_checkout_preparation_service.dart';
import 'package:sudhamrtam_customer_app/database/checkout_reconciliation_service.dart';
import 'package:sudhamrtam_customer_app/database/checkout_recovery_executor.dart';
import 'package:sudhamrtam_customer_app/database/checkout_startup_recovery_service.dart';
import 'package:sudhamrtam_customer_app/database/milk_database_service.dart';
import 'package:sudhamrtam_customer_app/database/order_database_service.dart';
import 'package:sudhamrtam_customer_app/database/pending_order_submission_service.dart';

import 'package:sudhamrtam_customer_app/features/checkout/durable_checkout_coordinator.dart';
import 'package:sudhamrtam_customer_app/features/checkout/order_submission_service.dart';

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
  late CartManager cart;
  late String productId;

  const orderId = 'coordinator-integration-001';
  const quantity = 2;

  // =====================================================
  // SQLITE TEST SETUP
  // =====================================================

  setUp(() async {
    directory = await Directory.systemTemp.createTemp(
      'sudhamrtam_coordinator_test_',
    );

    databaseService.configureForTesting(
      factory: databaseFactoryFfi,
      databasePath: '${directory.path}${Platform.pathSeparator}checkout.db',
    );

    db = await databaseService.database;

    expect(ProductCatalog.products, isNotEmpty);

    productId = ProductCatalog.products.first.id;

    await db.insert(MilkDatabaseService.cartItemsTable, {
      'product_id': productId,
      'quantity': quantity,
    });

    cart = CartManager();

    await cart.initialize();

    expect(cart.quantityFor(productId), quantity);
  });

  tearDown(() async {
    cart.dispose();

    await databaseService.close();

    databaseService.resetTestingConfiguration();

    await directory.delete(recursive: true);
  });

  // =====================================================
  // TEST HELPERS
  // =====================================================

  CustomerOrder createOrder({String id = orderId, double price = 50.0}) {
    return CustomerOrder(
      id: id,
      createdAt: DateTime.parse('2026-11-05T09:00:00'),
      items: [
        OrderItem(
          productId: productId,
          productName: 'Coordinator Test Product',
          unit: 'unit',
          quantity: quantity,
          unitPrice: price,
        ),
      ],
      fulfillmentMethod: FulfillmentMethod.pickup,
      paymentMethod: OrderPaymentMethod.cashOnDelivery,
      status: OrderStatus.pending,
    );
  }

  Future<List<Map<String, Object?>>> readRows(String table) async {
    return db.query(table);
  }

  // =====================================================
  // TEST 1 â€” SUCCESSFUL CHECKOUT
  // =====================================================

  test('Successful checkout saves one order and clears both carts', () async {
    final order = createOrder();

    final coordinator = DurableCheckoutCoordinator();

    final saved = await coordinator.submitPreparedOrder(
      order: order,
      cart: cart,
    );

    expect(saved.id, orderId);
    expect(coordinator.isProcessing, isFalse);

    expect(cart.isEmpty, isTrue);
    expect(cart.totalQuantity, 0);
    expect(cart.isCheckoutLocked, isFalse);
    expect(cart.isCheckoutRecoveryLocked, isFalse);

    final orders = await readRows(MilkDatabaseService.ordersTable);

    expect(orders.length, 1);
    expect(orders.single['id'], orderId);

    final persistedCart = await readRows(MilkDatabaseService.cartItemsTable);

    expect(persistedCart, isEmpty);

    final pending = await readRows(
      MilkDatabaseService.pendingOrderSubmissionsTable,
    );

    expect(pending, isEmpty);

    final state = await CheckoutReconciliationService.instance
        .getReconciliationState(orderId);

    expect(state, CheckoutReconciliationService.completed);
  });

  // =====================================================
  // TEST 2 â€” SUBMISSION FAILURE
  // =====================================================

  test(
    'Submission failure preserves cart and activates recovery lock',
    () async {
      final order = createOrder();

      final failingSubmission = OrderSubmissionService(
        saveOrder: (_) async {
          throw StateError('Simulated submission failure');
        },
      );

      final coordinator = DurableCheckoutCoordinator(
        orderSubmissionService: failingSubmission,
      );

      await expectLater(
        coordinator.submitPreparedOrder(order: order, cart: cart),
        throwsA(isA<StateError>()),
      );

      expect(coordinator.isProcessing, isFalse);

      expect(cart.quantityFor(productId), quantity);
      expect(cart.isCheckoutRecoveryLocked, isTrue);
      expect(cart.isCheckoutLocked, isTrue);

      expect(cart.increaseQuantity(productId), isFalse);

      final persistedCart = await readRows(MilkDatabaseService.cartItemsTable);

      expect(persistedCart.length, 1);
      expect(persistedCart.single['quantity'], quantity);

      final pending = await PendingOrderSubmissionService.instance
          .getPendingOrder();

      expect(pending, isNotNull);
      expect(pending!.id, orderId);

      final reconciliationState = await CheckoutReconciliationService.instance
          .getReconciliationState(orderId);

      expect(reconciliationState, CheckoutReconciliationService.pending);

      final orders = await readRows(MilkDatabaseService.ordersTable);

      expect(orders, isEmpty);
    },
  );

  // =====================================================
  // TEST 3 â€” RETRY SAME ORDER ID
  // =====================================================

  test('Retry after submission failure uses original ID', () async {
    final order = createOrder();

    var attempts = 0;

    final submission = OrderSubmissionService(
      saveOrder: (prepared) async {
        attempts++;

        if (attempts == 1) {
          throw StateError('First submission interrupted');
        }

        await OrderDatabaseService.instance.saveOrder(prepared);
      },
    );

    final coordinator = DurableCheckoutCoordinator(
      orderSubmissionService: submission,
    );

    await expectLater(
      coordinator.submitPreparedOrder(order: order, cart: cart),
      throwsA(isA<StateError>()),
    );

    expect(cart.isCheckoutRecoveryLocked, isTrue);

    final saved = await coordinator.submitPreparedOrder(
      order: order,
      cart: cart,
    );

    expect(saved.id, orderId);
    expect(attempts, 2);

    expect(cart.isEmpty, isTrue);
    expect(cart.isCheckoutLocked, isFalse);
    expect(cart.isCheckoutRecoveryLocked, isFalse);

    final orders = await readRows(MilkDatabaseService.ordersTable);

    expect(orders.length, 1);
    expect(orders.single['id'], orderId);

    final pending = await readRows(
      MilkDatabaseService.pendingOrderSubmissionsTable,
    );

    expect(pending, isEmpty);
  });

  // =====================================================
  // TEST 4 â€” CONFLICTING CHECKOUT
  // =====================================================

  test(
    'Conflicting order is rejected while original checkout remains protected',
    () async {
      final original = createOrder();

      final failingSubmission = OrderSubmissionService(
        saveOrder: (_) async {
          throw StateError('Submission interrupted');
        },
      );

      final coordinator = DurableCheckoutCoordinator(
        orderSubmissionService: failingSubmission,
      );

      await expectLater(
        coordinator.submitPreparedOrder(order: original, cart: cart),
        throwsA(isA<StateError>()),
      );

      final conflicting = createOrder(id: 'different-order-002');

      await expectLater(
        coordinator.submitPreparedOrder(order: conflicting, cart: cart),
        throwsA(isA<StateError>()),
      );

      expect(cart.isCheckoutRecoveryLocked, isTrue);

      final pending = await PendingOrderSubmissionService.instance
          .getPendingOrder();

      expect(pending, isNotNull);
      expect(pending!.id, orderId);

      final orders = await readRows(MilkDatabaseService.ordersTable);

      expect(orders, isEmpty);
    },
  );

  // =====================================================
  // TEST 5 â€” PREPARATION FAILURE
  // =====================================================

  test(
    'Preparation failure retains recovery lock and preserves cart',
    () async {
      final invalidOrder = CustomerOrder(
        id: 'preparation-failure-001',
        createdAt: DateTime.parse('2026-11-05T09:00:00'),
        items: [
          OrderItem(
            productId: productId,
            productName: 'Coordinator Test Product',
            unit: 'unit',
            quantity: quantity + 1,
            unitPrice: 50.0,
          ),
        ],
        fulfillmentMethod: FulfillmentMethod.pickup,
        paymentMethod: OrderPaymentMethod.cashOnDelivery,
        status: OrderStatus.pending,
      );

      final coordinator = DurableCheckoutCoordinator();

      await expectLater(
        coordinator.submitPreparedOrder(order: invalidOrder, cart: cart),
        throwsA(isA<StateError>()),
      );

      expect(coordinator.isProcessing, isFalse);

      expect(cart.isCheckoutRecoveryLocked, isTrue);
      expect(cart.isCheckoutLocked, isTrue);

      expect(cart.quantityFor(productId), quantity);

      expect(cart.increaseQuantity(productId), isFalse);

      final persistedCart = await readRows(MilkDatabaseService.cartItemsTable);

      expect(persistedCart.length, 1);
      expect(persistedCart.single['quantity'], quantity);

      final pending = await readRows(
        MilkDatabaseService.pendingOrderSubmissionsTable,
      );

      expect(pending, isEmpty);

      final reconciliations = await readRows(
        MilkDatabaseService.checkoutReconciliationsTable,
      );

      expect(reconciliations, isEmpty);

      final orders = await readRows(MilkDatabaseService.ordersTable);

      expect(orders, isEmpty);
    },
  );

  // =====================================================
  // TEST 6 â€” COMMIT SUCCEEDED, CONFIRMATION LOST
  // =====================================================

  test(
    'Committed preparation with lost confirmation retains recovery lock',
    () async {
      final order = createOrder();

      var preparationAttempts = 0;

      final coordinator = DurableCheckoutCoordinator(
        prepareCheckout: (prepared) async {
          preparationAttempts++;

          // Execute the real atomic SQLite transaction.
          await AtomicCheckoutPreparationService.instance.prepareCheckout(
            prepared,
          );

          // The transaction has committed.
          //
          // Simulate losing its confirmation before
          // the coordinator can continue.
          throw StateError('Simulated lost preparation confirmation');
        },
      );

      await expectLater(
        coordinator.submitPreparedOrder(order: order, cart: cart),
        throwsA(isA<StateError>()),
      );

      expect(preparationAttempts, 1);
      expect(coordinator.isProcessing, isFalse);

      expect(cart.isCheckoutRecoveryLocked, isTrue);
      expect(cart.isCheckoutLocked, isTrue);

      expect(cart.quantityFor(productId), quantity);

      expect(cart.increaseQuantity(productId), isFalse);

      // Verify that both preparation records committed.
      final pending = await readRows(
        MilkDatabaseService.pendingOrderSubmissionsTable,
      );

      expect(pending.length, 1);
      expect(pending.single['order_id'], orderId);

      final reconciliations = await readRows(
        MilkDatabaseService.checkoutReconciliationsTable,
      );

      expect(reconciliations.length, 1);
      expect(reconciliations.single['order_id'], orderId);
      expect(
        reconciliations.single['reconciliation_state'],
        CheckoutReconciliationService.pending,
      );

      // Submission has not occurred.
      final ordersBeforeRetry = await readRows(MilkDatabaseService.ordersTable);

      expect(ordersBeforeRetry, isEmpty);

      // Retry the same original order using
      // the normal production preparation service.
      final retryCoordinator = DurableCheckoutCoordinator();

      final saved = await retryCoordinator.submitPreparedOrder(
        order: order,
        cart: cart,
      );

      expect(saved.id, orderId);

      // Exactly one saved order.
      final ordersAfterRetry = await readRows(MilkDatabaseService.ordersTable);

      expect(ordersAfterRetry.length, 1);
      expect(ordersAfterRetry.single['id'], orderId);

      // Pending submission has been cleaned.
      final remainingPending = await readRows(
        MilkDatabaseService.pendingOrderSubmissionsTable,
      );

      expect(remainingPending, isEmpty);

      // Reconciliation is complete.
      final reconciliationState = await CheckoutReconciliationService.instance
          .getReconciliationState(orderId);

      expect(reconciliationState, CheckoutReconciliationService.completed);

      // Both persisted and in-memory carts are empty.
      final persistedCart = await readRows(MilkDatabaseService.cartItemsTable);

      expect(persistedCart, isEmpty);

      expect(cart.isEmpty, isTrue);

      // Locks are released only after success.
      expect(cart.isCheckoutRecoveryLocked, isFalse);
      expect(cart.isCheckoutLocked, isFalse);
    },
  );

  // =====================================================
  // TEST 7 â€” RECOVERY AFTER APPLICATION RESTART
  // =====================================================

  test('Startup recovery blocks an unfinished order submission', () async {
    final order = createOrder();

    // Simulate an interrupted submission.
    final coordinator = DurableCheckoutCoordinator(
      orderSubmissionService: OrderSubmissionService(
        saveOrder: (_) async {
          throw StateError('Simulated application interruption');
        },
      ),
    );

    await expectLater(
      coordinator.submitPreparedOrder(order: order, cart: cart),
      throwsA(isA<StateError>()),
    );

    // Verify the durable records exist.
    final pendingBeforeRestart = await PendingOrderSubmissionService.instance
        .getPendingOrder();

    expect(pendingBeforeRestart, isNotNull);
    expect(pendingBeforeRestart!.id, orderId);

    // Inspect the persisted checkout state using
    // the application's startup recovery services.
    final inspection = await CheckoutStartupRecoveryService.instance
        .inspectRecoveryState();

    expect(inspection.status, CheckoutRecoveryStatus.awaitingOrderSubmission);
    expect(inspection.orderId, orderId);

    final recovery = await CheckoutRecoveryExecutor.instance.recoverAtStartup();

    expect(recovery.status, CheckoutRecoveryExecutionStatus.awaitingSubmission);

    expect(recovery.canContinueNormalStartup, isFalse);

    // Recovery must preserve the pending order.
    final pendingAfterRecovery = await PendingOrderSubmissionService.instance
        .getPendingOrder();

    expect(pendingAfterRecovery, isNotNull);
    expect(pendingAfterRecovery!.id, orderId);

    // Persisted cart must remain unchanged.
    final persistedCart = await readRows(MilkDatabaseService.cartItemsTable);

    expect(persistedCart.length, 1);
    expect(persistedCart.single['quantity'], quantity);

    // No order was saved.
    final orders = await readRows(MilkDatabaseService.ordersTable);

    expect(orders, isEmpty);
  });

  // =====================================================
  // TEST 8 â€” ORPHANED PENDING RECONCILIATION
  // =====================================================

  test('Orphaned reconciliation blocks startup and new checkout', () async {
    final order = createOrder();

    // Insert an orphaned reconciliation record.
    //
    // The pending submission is deliberately missing.
    await db.insert(MilkDatabaseService.checkoutReconciliationsTable, {
      'order_id': orderId,
      'cart_snapshot': '{"$productId":$quantity}',
      'reconciliation_state': CheckoutReconciliationService.pending,
      'created_at': DateTime.now().toUtc().toIso8601String(),
      'completed_at': null,
    });

    // Startup inspection must detect inconsistency.
    final inspection = await CheckoutStartupRecoveryService.instance
        .inspectRecoveryState();

    expect(inspection.status, CheckoutRecoveryStatus.requiresManualRecovery);

    final recovery = await CheckoutRecoveryExecutor.instance.recoverAtStartup();

    expect(recovery.status, CheckoutRecoveryExecutionStatus.blocked);

    expect(recovery.canContinueNormalStartup, isFalse);

    // New checkout must not proceed.
    final coordinator = DurableCheckoutCoordinator();

    await expectLater(
      coordinator.submitPreparedOrder(order: order, cart: cart),
      throwsA(isA<StateError>()),
    );

    // The cart remains protected.
    expect(cart.isCheckoutRecoveryLocked, isTrue);
    expect(cart.isCheckoutLocked, isTrue);

    expect(cart.quantityFor(productId), quantity);

    expect(cart.increaseQuantity(productId), isFalse);

    // The persisted cart remains intact.
    final persistedCart = await readRows(MilkDatabaseService.cartItemsTable);

    expect(persistedCart.length, 1);
    expect(persistedCart.single['quantity'], quantity);

    // Preserve the orphaned reconciliation
    // for investigation.
    final reconciliations = await readRows(
      MilkDatabaseService.checkoutReconciliationsTable,
    );

    expect(reconciliations.length, 1);
    expect(reconciliations.single['order_id'], orderId);

    // No new pending submission.
    final pending = await readRows(
      MilkDatabaseService.pendingOrderSubmissionsTable,
    );

    expect(pending, isEmpty);

    // No saved order.
    final orders = await readRows(MilkDatabaseService.ordersTable);

    expect(orders, isEmpty);
  });

  // =====================================================
  // TEST 9 - REFRESH FAILURE PRESERVES RECOVERY EVIDENCE
  // =====================================================

  test(
    'Cart refresh failure retains pending checkout and recovery lock',
    () async {
      final order = createOrder();
      final coordinator = DurableCheckoutCoordinator(
        refreshCart: (_) async {
          throw StateError('Simulated cart refresh failure');
        },
      );

      await expectLater(
        coordinator.submitPreparedOrder(order: order, cart: cart),
        throwsA(isA<StateError>()),
      );

      expect(coordinator.isProcessing, isFalse);
      expect(cart.isCheckoutRecoveryLocked, isTrue);
      expect(cart.isCheckoutLocked, isTrue);
      expect(cart.quantityFor(productId), quantity);
      expect(cart.increaseQuantity(productId), isFalse);

      final orders = await readRows(MilkDatabaseService.ordersTable);
      expect(orders.length, 1);
      expect(orders.single['id'], orderId);

      final persistedCart = await readRows(MilkDatabaseService.cartItemsTable);
      expect(persistedCart, isEmpty);

      final pending = await PendingOrderSubmissionService.instance
          .getPendingOrder();
      expect(pending, isNotNull);
      expect(pending!.id, orderId);

      final state = await CheckoutReconciliationService.instance
          .getReconciliationState(orderId);
      expect(state, CheckoutReconciliationService.completed);
    },
  );

  // =====================================================
  // TEST 10 - SAFE RETRY AFTER REFRESH FAILURE
  // =====================================================

  test('Retry after cart refresh failure does not resubmit order', () async {
    final order = createOrder();
    var refreshAttempts = 0;
    var saveAttempts = 0;

    final coordinator = DurableCheckoutCoordinator(
      refreshCart: (currentCart) async {
        refreshAttempts++;
        if (refreshAttempts == 1) {
          throw StateError('First cart refresh failed');
        }
        await currentCart.refreshAfterCheckoutReconciliation();
      },
      orderSubmissionService: OrderSubmissionService(
        saveOrder: (prepared) async {
          saveAttempts++;
          await OrderDatabaseService.instance.saveOrder(prepared);
        },
      ),
    );

    await expectLater(
      coordinator.submitPreparedOrder(order: order, cart: cart),
      throwsA(isA<StateError>()),
    );
    expect(refreshAttempts, 1);
    expect(saveAttempts, 1);
    expect(cart.isCheckoutRecoveryLocked, isTrue);

    final saved = await coordinator.submitPreparedOrder(
      order: order,
      cart: cart,
    );

    expect(saved.id, orderId);
    expect(refreshAttempts, 2);
    expect(saveAttempts, 1);
    expect(await OrderDatabaseService.instance.getOrderCount(), 1);
    expect(await readRows(MilkDatabaseService.cartItemsTable), isEmpty);
    expect(
      await readRows(MilkDatabaseService.pendingOrderSubmissionsTable),
      isEmpty,
    );
    expect(cart.isEmpty, isTrue);
    expect(cart.isCheckoutRecoveryLocked, isFalse);
    expect(cart.isCheckoutLocked, isFalse);
  });

  // =====================================================
  // TEST 11 - CONFLICTING RETRY AFTER REFRESH FAILURE
  // =====================================================

  test('Different order cannot replace refresh-failed checkout', () async {
    final original = createOrder();
    final coordinator = DurableCheckoutCoordinator(
      refreshCart: (_) async {
        throw StateError('Simulated cart refresh failure');
      },
    );

    await expectLater(
      coordinator.submitPreparedOrder(order: original, cart: cart),
      throwsA(isA<StateError>()),
    );

    final conflicting = createOrder(id: 'conflicting-refresh-retry-002');
    await expectLater(
      DurableCheckoutCoordinator().submitPreparedOrder(
        order: conflicting,
        cart: cart,
      ),
      throwsA(isA<StateError>()),
    );

    expect(await OrderDatabaseService.instance.getOrderCount(), 1);
    expect(
      await OrderDatabaseService.instance.getOrderById(conflicting.id),
      isNull,
    );
    final pending = await PendingOrderSubmissionService.instance
        .getPendingOrder();
    expect(pending, isNotNull);
    expect(pending!.id, orderId);
    expect(cart.isCheckoutRecoveryLocked, isTrue);
    expect(cart.isCheckoutLocked, isTrue);
  });
}
