import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import 'package:sudhamrtam_customer_app/database/milk_database_service.dart';
import 'package:sudhamrtam_customer_app/database/order_database_service.dart';
import 'package:sudhamrtam_customer_app/models/customer_order.dart';
import 'package:sudhamrtam_customer_app/models/order_item.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('Customer order persists after SQLite database reopening', (
    tester,
  ) async {
    final databaseService = MilkDatabaseService.instance;
    final orderService = OrderDatabaseService.instance;

    final orderId =
        '__test_order_restart_${DateTime.now().microsecondsSinceEpoch}__';

    final order = CustomerOrder(
      id: orderId,
      createdAt: DateTime.now().toUtc(),
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

    var orderSaved = false;

    try {
      // Step 1: Save the order using the service.
      await orderService.saveOrder(order);
      orderSaved = true;

      // Step 2: Confirm the order exists.
      final beforeClose = await orderService.getOrderById(orderId);

      expect(beforeClose, isNotNull);
      expect(beforeClose!.items.length, 2);
      expect(beforeClose.subtotal, 660.0);

      // Step 3: Close the SQLite connection.
      await databaseService.close();

      // Step 4: Reopen the database.
      final reopenedDatabase = await databaseService.database;

      expect(reopenedDatabase.isOpen, isTrue);

      // Step 5: Retrieve the order again.
      final restored = await orderService.getOrderById(orderId);

      expect(restored, isNotNull);
      expect(restored!.id, orderId);
      expect(restored.items.length, 2);
      expect(restored.totalQuantity, 3);
      expect(restored.subtotal, 660.0);
      expect(restored.status, OrderStatus.pending);

      // Verify product details.
      expect(restored.items[0].productId, 'cow_milk');
      expect(restored.items[0].quantity, 2);
      expect(restored.items[0].unitPrice, 80.0);

      expect(restored.items[1].productId, 'raw_honey');
      expect(restored.items[1].quantity, 1);
      expect(restored.items[1].unitPrice, 500.0);

      // Verify the order appears in history.
      final allOrders = await orderService.getAllOrders();

      expect(allOrders.any((item) => item.id == orderId), isTrue);
    } finally {
      // Always reopen the database before cleanup.
      final db = await databaseService.database;

      // Delete only the temporary test order.
      if (orderSaved) {
        await db.delete(
          MilkDatabaseService.ordersTable,
          where: 'id = ?',
          whereArgs: [orderId],
        );
      }
    }

    // Verify temporary data was removed.
    final remaining = await orderService.getOrderById(orderId);

    expect(remaining, isNull);
  });
}
