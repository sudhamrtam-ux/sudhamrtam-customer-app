import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import 'package:sudhamrtam_customer_app/database/milk_database_service.dart';
import 'package:sudhamrtam_customer_app/models/customer_order.dart';
import 'package:sudhamrtam_customer_app/models/order_item.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('SQLite V3 saves and retrieves customer order data', (
    tester,
  ) async {
    final db = await MilkDatabaseService.instance.database;

    const orderId = '__test_order_124_5_3__';

    // Track whether all assertions inside the
    // transaction completed successfully.
    var assertionsCompleted = false;

    // Ensure the test order ID is not already present.
    final existingOrders = await db.query(
      MilkDatabaseService.ordersTable,
      where: 'id = ?',
      whereArgs: [orderId],
    );

    expect(
      existingOrders,
      isEmpty,
      reason: 'Temporary test order ID must be unused.',
    );

    // Run test inserts inside a transaction.
    // An intentional exception rolls back all changes.
    await expectLater(
      () => db.transaction((txn) async {
        final order = CustomerOrder(
          id: orderId,
          createdAt: DateTime.utc(2026, 11, 3),
          items: const [
            OrderItem(
              productId: 'cow_milk',
              productName: 'Cow Milk',
              unit: 'litre',
              quantity: 2,
              unitPrice: 80.0,
            ),
            OrderItem(
              productId: 'raw_honey',
              productName: 'Raw Honey',
              unit: 'kg',
              quantity: 1,
              unitPrice: 500.0,
            ),
          ],
          fulfillmentMethod: FulfillmentMethod.pickup,
          paymentMethod: OrderPaymentMethod.cashOnDelivery,
        );

        // Verify order calculations.
        expect(order.totalQuantity, 3);
        expect(order.subtotal, 660.0);
        expect(order.hasValidPrices, isTrue);

        // Insert the order header.
        await txn.insert(MilkDatabaseService.ordersTable, order.toMap());

        // Insert associated order items.
        for (final item in order.items) {
          await txn.insert(MilkDatabaseService.orderItemsTable, {
            'order_id': order.id,
            ...item.toMap(),
          });
        }

        // Retrieve the saved order header.
        final orderRows = await txn.query(
          MilkDatabaseService.ordersTable,
          where: 'id = ?',
          whereArgs: [orderId],
        );

        expect(orderRows.length, 1);

        // Retrieve associated order items.
        final itemRows = await txn.query(
          MilkDatabaseService.orderItemsTable,
          where: 'order_id = ?',
          whereArgs: [orderId],
          orderBy: 'id ASC',
        );

        expect(itemRows.length, 2);

        // Reconstruct the CustomerOrder model.
        final restored = CustomerOrder.fromMap(
          orderRows.first,
          items: itemRows.map((row) => OrderItem.fromMap(row)).toList(),
        );

        // Verify restored order information.
        expect(restored.id, orderId);
        expect(restored.items.length, 2);
        expect(restored.totalQuantity, 3);
        expect(restored.subtotal, 660.0);

        expect(restored.fulfillmentMethod, FulfillmentMethod.pickup);

        expect(restored.paymentMethod, OrderPaymentMethod.cashOnDelivery);

        expect(restored.status, OrderStatus.pending);

        // Verify first product.
        expect(restored.items[0].productId, 'cow_milk');
        expect(restored.items[0].quantity, 2);
        expect(restored.items[0].unitPrice, 80.0);
        expect(restored.items[0].totalPrice, 160.0);

        // Verify second product.
        expect(restored.items[1].productId, 'raw_honey');
        expect(restored.items[1].quantity, 1);
        expect(restored.items[1].unitPrice, 500.0);
        expect(restored.items[1].totalPrice, 500.0);

        // Mark all assertions as completed.
        assertionsCompleted = true;

        // Force SQLite to roll back temporary test data.
        throw const _RollbackTestTransaction();
      }),
      throwsA(isA<_RollbackTestTransaction>()),
    );

    // Ensure the intentional rollback happened only
    // after all assertions passed.
    expect(
      assertionsCompleted,
      isTrue,
      reason: 'All order assertions must pass before rollback.',
    );

    // Verify the temporary order was removed.
    final remainingOrders = await db.query(
      MilkDatabaseService.ordersTable,
      where: 'id = ?',
      whereArgs: [orderId],
    );

    expect(
      remainingOrders,
      isEmpty,
      reason: 'Test order must not remain after rollback.',
    );

    // Verify associated order items were also removed.
    final remainingItems = await db.query(
      MilkDatabaseService.orderItemsTable,
      where: 'order_id = ?',
      whereArgs: [orderId],
    );

    expect(
      remainingItems,
      isEmpty,
      reason: 'Test order items must not remain after rollback.',
    );
  });
}

/// Intentional exception used to roll back test inserts.
class _RollbackTestTransaction implements Exception {
  const _RollbackTestTransaction();
}
