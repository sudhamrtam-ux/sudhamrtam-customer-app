import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import 'package:sudhamrtam_customer_app/database/milk_database_service.dart';
import 'package:sudhamrtam_customer_app/database/order_database_service.dart';
import 'package:sudhamrtam_customer_app/models/customer_order.dart';
import 'package:sudhamrtam_customer_app/models/order_item.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('OrderDatabaseService saves, retrieves and updates orders', (
    tester,
  ) async {
    final service = OrderDatabaseService.instance;
    final db = await MilkDatabaseService.instance.database;

    final orderId =
        '__test_order_service_${DateTime.now().microsecondsSinceEpoch}__';

    // This test uses the public service methods.
    // Unlike the earlier rollback test, the service
    // commits its own database transaction.
    //
    // Cleanup is performed in finally.

    final initialCount = await service.getOrderCount();

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

    try {
      // 1. Save the order.
      await service.saveOrder(order);

      // 2. Retrieve by ID.
      final restored = await service.getOrderById(orderId);

      expect(restored, isNotNull);
      expect(restored!.id, orderId);
      expect(restored.items.length, 2);
      expect(restored.totalQuantity, 3);
      expect(restored.subtotal, 660.0);
      expect(restored.status, OrderStatus.pending);

      // 3. Verify order count.
      final countAfterSave = await service.getOrderCount();
      expect(countAfterSave, initialCount + 1);

      // 4. Verify order appears in history.
      final allOrders = await service.getAllOrders();

      expect(allOrders.any((item) => item.id == orderId), isTrue);

      // 5. Update order status.
      final updated = await service.updateOrderStatus(
        orderId,
        OrderStatus.confirmed,
      );

      expect(updated, isTrue);

      // 6. Retrieve updated order.
      final updatedOrder = await service.getOrderById(orderId);

      expect(updatedOrder, isNotNull);
      expect(updatedOrder!.status, OrderStatus.confirmed);
      expect(updatedOrder.items.length, 2);
      expect(updatedOrder.subtotal, 660.0);
    } finally {
      // Remove only the temporary test order.
      // Foreign-key cascade removes its order items.
      await db.delete(
        MilkDatabaseService.ordersTable,
        where: 'id = ?',
        whereArgs: [orderId],
      );
    }

    // 7. Verify cleanup.
    final remaining = await service.getOrderById(orderId);
    expect(remaining, isNull);

    final finalCount = await service.getOrderCount();
    expect(finalCount, initialCount);
  });
}
