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

  const createdAt = '2026-11-05T09:00:00';
  const productId = 'cow_milk';
  const productName = 'Cow Milk';
  const productUnit = 'litre';
  const quantity = 2;
  const unitPrice = 50.0;

  setUp(() async {
    directory = await Directory.systemTemp.createTemp(
      'sudhamrtam_startup_integration_',
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
  // TEST ORDER SNAPSHOT
  // =====================================================

  CustomerOrder createPendingOrder(String orderId) {
    return CustomerOrder(
      id: orderId,
      createdAt: DateTime.parse(createdAt),
      items: [
        OrderItem(
          productId: productId,
          productName: productName,
          unit: productUnit,
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

  // =====================================================
  // DATABASE FIXTURES
  // =====================================================

  Future<void> insertOrder(String orderId) async {
    await db.insert(MilkDatabaseService.ordersTable, {
      'id': orderId,
      'created_at': createdAt,
      'fulfillment_method': 'pickup',
      'payment_method': 'cashOnDelivery',
      'status': 'pending',
      'delivery_address': null,
      'notes': null,
      'subtotal': quantity * unitPrice,
    });

    // The saved order must contain the same item
    // as its original pending submission.
    await db.insert(MilkDatabaseService.orderItemsTable, {
      'order_id': orderId,
      'product_id': productId,
      'product_name': productName,
      'unit': productUnit,
      'quantity': quantity,
      'unit_price': unitPrice,
    });
  }

  Future<void> insertPendingSubmission(String orderId) async {
    final pendingOrder = createPendingOrder(orderId);

    await db.insert(MilkDatabaseService.pendingOrderSubmissionsTable, {
      'order_id': orderId,
      'created_at': createdAt,
      'order_payload': encodePendingOrder(pendingOrder),
      'submission_state': 'prepared',
      'updated_at': createdAt,
    });
  }

  Future<void> insertReconciliation(
    String orderId, {
    required String state,
  }) async {
    await db.insert(MilkDatabaseService.checkoutReconciliationsTable, {
      'order_id': orderId,
      'cart_snapshot': jsonEncode({productId: quantity}),
      'reconciliation_state': state,
      'created_at': createdAt,
      'completed_at': state == 'completed' ? '2026-11-05T09:01:00' : null,
    });
  }

  CheckoutStartupController makeController(List<String> events) {
    return CheckoutStartupController(
      recover: () async {
        events.add('recovery');

        return CheckoutRecoveryExecutor.instance.recoverAtStartup();
      },
      initializeCart: () async {
        events.add('cart');
      },
    );
  }

  // =====================================================
  // TEST 1: CLEAN STARTUP
  // =====================================================

  test('Clean database initializes cart after recovery inspection', () async {
    final events = <String>[];
    final controller = makeController(events);

    final result = await controller.start();

    expect(
      result.status,
      CheckoutRecoveryExecutionStatus.noRecoveryNeeded,
      reason: result.message,
    );

    expect(controller.isReady, isTrue);
    expect(events, ['recovery', 'cart']);
  });

  // =====================================================
  // TEST 2: UNSUBMITTED CHECKOUT
  // =====================================================

  test('Unsubmitted checkout blocks cart initialization', () async {
    await insertPendingSubmission('pending-001');
    await insertReconciliation('pending-001', state: 'pending');

    final events = <String>[];
    final controller = makeController(events);

    final result = await controller.start();

    expect(
      result.status,
      CheckoutRecoveryExecutionStatus.awaitingSubmission,
      reason: result.message,
    );

    expect(controller.isReady, isFalse);
    expect(events, ['recovery']);

    final pending = await db.query(
      MilkDatabaseService.pendingOrderSubmissionsTable,
    );

    expect(pending.length, 1);
  });

  // =====================================================
  // TEST 3: ORPHANED COMPLETED RECONCILIATION
  // =====================================================

  test('Orphaned completed reconciliation blocks startup', () async {
    await insertReconciliation('orphan-001', state: 'completed');

    final events = <String>[];
    final controller = makeController(events);

    final result = await controller.start();

    expect(
      result.status,
      CheckoutRecoveryExecutionStatus.blocked,
      reason: result.message,
    );

    expect(controller.isReady, isFalse);
    expect(events, ['recovery']);

    final reconciliations = await db.query(
      MilkDatabaseService.checkoutReconciliationsTable,
    );

    expect(reconciliations.length, 1);
  });

  // =====================================================
  // TEST 4: COMPLETED RECONCILIATION CLEANUP
  // =====================================================

  test('Completed reconciliation permits pending cleanup', () async {
    const orderId = 'completed-001';

    await insertOrder(orderId);
    await insertPendingSubmission(orderId);
    await insertReconciliation(orderId, state: 'completed');

    final events = <String>[];
    final controller = makeController(events);

    final result = await controller.start();

    expect(
      result.status,
      CheckoutRecoveryExecutionStatus.recovered,
      reason: result.message,
    );

    expect(controller.isReady, isTrue);
    expect(events, ['recovery', 'cart']);

    final pending = await db.query(
      MilkDatabaseService.pendingOrderSubmissionsTable,
    );

    expect(pending, isEmpty);

    final reconciliations = await db.query(
      MilkDatabaseService.checkoutReconciliationsTable,
    );

    expect(reconciliations.length, 1);

    expect(reconciliations.first['reconciliation_state'], 'completed');

    // Verify the original saved order remains intact.
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
    expect(savedItems.single['quantity'], quantity);
    expect(savedItems.single['unit_price'], unitPrice);
  });

  // =====================================================
  // TEST 5: MISSING RECONCILIATION
  // =====================================================

  test('Missing reconciliation blocks startup', () async {
    await insertPendingSubmission('missing-reconciliation-001');

    final events = <String>[];
    final controller = makeController(events);

    final result = await controller.start();

    expect(
      result.status,
      CheckoutRecoveryExecutionStatus.blocked,
      reason: result.message,
    );

    expect(controller.isReady, isFalse);
    expect(events, ['recovery']);

    final pending = await db.query(
      MilkDatabaseService.pendingOrderSubmissionsTable,
    );

    expect(pending.length, 1);
  });

  // =====================================================
  // TEST 6: UNMATCHED PENDING RECONCILIATION
  // =====================================================

  test('Unmatched pending reconciliation blocks startup', () async {
    await insertReconciliation('unmatched-001', state: 'pending');

    final events = <String>[];
    final controller = makeController(events);

    final result = await controller.start();

    expect(
      result.status,
      CheckoutRecoveryExecutionStatus.blocked,
      reason: result.message,
    );

    expect(controller.isReady, isFalse);
    expect(events, ['recovery']);
  });
}
