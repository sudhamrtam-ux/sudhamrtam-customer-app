import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:sudhamrtam_customer_app/features/orders/order_details_screen.dart';
import 'package:sudhamrtam_customer_app/models/customer_order.dart';
import 'package:sudhamrtam_customer_app/models/order_item.dart';

void main() {
  CustomerOrder createTestOrder({
    FulfillmentMethod fulfillmentMethod = FulfillmentMethod.delivery,
    OrderPaymentMethod paymentMethod = OrderPaymentMethod.cashOnDelivery,
    OrderStatus status = OrderStatus.pending,
    String? deliveryAddress = 'Kukatpally, Hyderabad',
    String? notes = 'Please deliver in the morning.',
  }) {
    return CustomerOrder(
      id: 'TEST-ORDER-001',
      createdAt: DateTime(2026, 11, 4, 8, 30),
      items: const [
        OrderItem(
          productId: 'test-milk',
          productName: 'Buffalo Milk',
          unit: '1 Litre',
          quantity: 2,
          unitPrice: 100.0,
        ),
        OrderItem(
          productId: 'test-honey',
          productName: 'Raw Honey',
          unit: '500 g',
          quantity: 1,
          unitPrice: 350.0,
        ),
      ],
      fulfillmentMethod: fulfillmentMethod,
      paymentMethod: paymentMethod,
      status: status,
      deliveryAddress: fulfillmentMethod == FulfillmentMethod.delivery
          ? deliveryAddress
          : null,
      notes: notes,
    );
  }

  Future<void> openOrderDetails(
    WidgetTester tester,
    CustomerOrder order,
  ) async {
    await tester.pumpWidget(
      MaterialApp(home: OrderDetailsScreen(order: order)),
    );
  }

  group('Order Details Screen', () {
    testWidgets('a computer: the whole order on one screen', (tester) async {
      tester.view.physicalSize = const Size(1280, 720);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await openOrderDetails(tester, createTestOrder());

      expect(find.byKey(const Key('order-details-wide')), findsOneWidget);
      // Products on the left, delivery and payment on the right.
      final products = tester.getRect(
        find.byKey(const Key('order-details-products')),
      );
      final payment = tester.getRect(
        find.byKey(const Key('order-details-payment')),
      );
      expect(payment.left, greaterThan(products.right));
      // Everything fits without scrolling.
      expect(payment.bottom, lessThan(720));
      expect(tester.getRect(find.text('₹550.00')).bottom, lessThan(720));
      expect(find.text('Please deliver in the morning.'), findsOneWidget);
    });

    testWidgets('displays order ID, date and status', (tester) async {
      final order = createTestOrder();

      await openOrderDetails(tester, order);

      expect(find.text('Order Details'), findsOneWidget);
      expect(find.text('Order #TEST-ORDER-001'), findsOneWidget);
      expect(find.text('Delivery pending'), findsOneWidget);
      expect(find.textContaining('04/11/2026'), findsOneWidget);
    });

    testWidgets('displays products, quantities and prices', (tester) async {
      final order = createTestOrder();

      await openOrderDetails(tester, order);

      expect(find.text('Buffalo Milk'), findsOneWidget);
      expect(find.text('Quantity: 2 × 1 Litre'), findsOneWidget);
      expect(find.text('Unit Price: ₹100.00'), findsOneWidget);
      expect(find.text('₹200.00'), findsOneWidget);

      await tester.scrollUntilVisible(find.text('Raw Honey'), 150);

      expect(find.text('Raw Honey'), findsOneWidget);
      expect(find.text('Quantity: 1 × 500 g'), findsOneWidget);
      expect(find.text('Unit Price: ₹350.00'), findsOneWidget);
      expect(find.text('₹350.00'), findsOneWidget);
    });

    testWidgets('displays correct subtotal and total quantity', (tester) async {
      final order = createTestOrder();

      expect(order.totalQuantity, 3);
      expect(order.subtotal, 550.0);

      await openOrderDetails(tester, order);

      await tester.scrollUntilVisible(find.text('Product Subtotal'), 150);

      expect(find.text('Total Quantity'), findsOneWidget);
      expect(find.text('3'), findsOneWidget);
      expect(find.text('Product Subtotal'), findsOneWidget);
      expect(find.text('₹550.00'), findsOneWidget);
    });

    testWidgets('displays delivery and payment information', (tester) async {
      final order = createTestOrder();

      await openOrderDetails(tester, order);

      await tester.scrollUntilVisible(find.text('PAYMENT INFORMATION'), 200);

      expect(find.text('Home Delivery'), findsOneWidget);
      expect(find.text('Kukatpally, Hyderabad'), findsOneWidget);
      expect(find.text('Cash on Delivery / Pickup'), findsOneWidget);
    });

    testWidgets('displays customer delivery instructions', (tester) async {
      final order = createTestOrder();

      await openOrderDetails(tester, order);

      await tester.scrollUntilVisible(
        find.text('Please deliver in the morning.'),
        200,
      );

      expect(find.text('Please deliver in the morning.'), findsOneWidget);
    });

    testWidgets('supports store pickup and online payment', (tester) async {
      final order = createTestOrder(
        fulfillmentMethod: FulfillmentMethod.pickup,
        paymentMethod: OrderPaymentMethod.online,
        status: OrderStatus.readyForPickup,
        notes: null,
      );

      await openOrderDetails(tester, order);

      expect(find.text('Ready for pickup'), findsOneWidget);

      await tester.scrollUntilVisible(find.text('Online Payment'), 200);

      expect(find.text('Store Pickup'), findsOneWidget);
      expect(find.text('Online Payment'), findsOneWidget);
      expect(find.text('Delivery Address'), findsNothing);
    });
  });
}
