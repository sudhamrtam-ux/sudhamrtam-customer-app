import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:sudhamrtam_customer_app/database/atomic_checkout_preparation_service.dart';
import 'package:sudhamrtam_customer_app/database/checkout_recovery_executor.dart';
import 'package:sudhamrtam_customer_app/database/milk_database_service.dart';
import 'package:sudhamrtam_customer_app/database/order_database_service.dart';
import 'package:sudhamrtam_customer_app/database/pending_order_submission_service.dart';
import 'package:sudhamrtam_customer_app/features/checkout/order_snapshot_equivalence.dart';
import 'package:sudhamrtam_customer_app/models/customer_order.dart';
import 'package:sudhamrtam_customer_app/models/order_item.dart';

/// Covers the customer's decision for an order that was
/// prepared durably but never saved before the app closed.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(sqfliteFfiInit);

  final databaseService = MilkDatabaseService.instance;
  final executor = CheckoutRecoveryExecutor.instance;

  late Directory directory;
  late Database db;

  const orderId = 'unfinished-order-001';
  const productId = 'cow_milk';
  const quantity = 2;

  CustomerOrder unfinishedOrder() {
    return CustomerOrder(
      id: orderId,
      createdAt: DateTime.utc(2026, 11, 6, 8),
      items: const [
        OrderItem(
          productId: productId,
          productName: 'Cow Milk',
          unit: '1 L',
          quantity: quantity,
          unitPrice: 85,
        ),
      ],
      fulfillmentMethod: FulfillmentMethod.pickup,
      paymentMethod: OrderPaymentMethod.cashOnDelivery,
    );
  }

  Future<int> count(String table) async {
    final rows = await db.rawQuery('SELECT COUNT(*) AS total FROM $table');
    return rows.first['total'] as int;
  }

  setUp(() async {
    directory = await Directory.systemTemp.createTemp(
      'sudhamrtam_unfinished_order_',
    );

    databaseService.configureForTesting(
      factory: databaseFactoryFfi,
      databasePath: '${directory.path}${Platform.pathSeparator}checkout.db',
    );

    db = await databaseService.database;

    await db.insert(MilkDatabaseService.cartItemsTable, {
      'product_id': productId,
      'quantity': quantity,
    });

    // Simulate an app closed right after durable
    // preparation, before the order was saved.
    await AtomicCheckoutPreparationService.instance.prepareCheckout(
      unfinishedOrder(),
    );

    final startup = await executor.recoverAtStartup();
    expect(startup.status, CheckoutRecoveryExecutionStatus.awaitingSubmission);
    expect(startup.orderId, orderId);
  });

  tearDown(() async {
    await databaseService.close();
    databaseService.resetTestingConfiguration();
    await directory.delete(recursive: true);
  });

  test('Finish saves the original order and clears the cart', () async {
    final result = await executor.finishAwaitingSubmission(orderId);

    expect(result.status, CheckoutRecoveryExecutionStatus.recovered);
    expect(result.canContinueNormalStartup, isTrue);

    final saved = await OrderDatabaseService.instance.getOrderById(orderId);
    expect(saved, isNotNull);
    expect(OrderSnapshotEquivalence.matches(unfinishedOrder(), saved!), isTrue);

    expect(await count(MilkDatabaseService.cartItemsTable), 0);
    expect(await count(MilkDatabaseService.pendingOrderSubmissionsTable), 0);

    final next = await executor.recoverAtStartup();
    expect(next.status, CheckoutRecoveryExecutionStatus.noRecoveryNeeded);
  });

  test('Finishing twice does not create a second order', () async {
    await executor.finishAwaitingSubmission(orderId);

    final second = await executor.finishAwaitingSubmission(orderId);

    expect(second.status, CheckoutRecoveryExecutionStatus.noRecoveryNeeded);
    expect(await count(MilkDatabaseService.ordersTable), 1);
  });

  test('Cancel discards the order and keeps the cart', () async {
    final result = await executor.cancelAwaitingSubmission(orderId);

    expect(result.status, CheckoutRecoveryExecutionStatus.noRecoveryNeeded);
    expect(result.canContinueNormalStartup, isTrue);

    expect(await OrderDatabaseService.instance.getOrderById(orderId), isNull);
    expect(await count(MilkDatabaseService.pendingOrderSubmissionsTable), 0);
    expect(await count(MilkDatabaseService.checkoutReconciliationsTable), 0);

    final cartRows = await db.query(MilkDatabaseService.cartItemsTable);
    expect(cartRows, hasLength(1));
    expect(cartRows.first['product_id'], productId);
    expect(cartRows.first['quantity'], quantity);
  });

  test('A saved order cannot be cancelled', () async {
    // The order was saved (for example by an interrupted
    // finish) before the customer chose to cancel.
    await OrderDatabaseService.instance.saveOrder(unfinishedOrder());

    expect(
      await PendingOrderSubmissionService.instance.cancelUnsavedSubmission(
        orderId,
      ),
      isFalse,
    );

    // Nothing was deleted by the refused cancellation.
    expect(await count(MilkDatabaseService.pendingOrderSubmissionsTable), 1);
    expect(await count(MilkDatabaseService.checkoutReconciliationsTable), 1);

    final result = await executor.cancelAwaitingSubmission(orderId);

    // Normal recovery completes the saved order instead.
    expect(result.status, CheckoutRecoveryExecutionStatus.recovered);
    expect(result.message, contains('could not be cancelled'));
    expect(await count(MilkDatabaseService.ordersTable), 1);
    expect(await count(MilkDatabaseService.cartItemsTable), 0);
  });

  test('Finish uses the durable snapshot, not the current cart', () async {
    // Even if the persisted cart changed unexpectedly,
    // finishing must not rebuild the order from it.
    await db.update(
      MilkDatabaseService.cartItemsTable,
      {'quantity': 5},
      where: 'product_id = ?',
      whereArgs: [productId],
    );

    final result = await executor.finishAwaitingSubmission(orderId);

    final saved = await OrderDatabaseService.instance.getOrderById(orderId);
    expect(saved!.items.single.quantity, quantity);

    // The cart no longer matches the checkout snapshot,
    // so reconciliation stops safely and keeps the cart.
    expect(result.status, CheckoutRecoveryExecutionStatus.blocked);
    expect(await count(MilkDatabaseService.cartItemsTable), 1);
  });
}
