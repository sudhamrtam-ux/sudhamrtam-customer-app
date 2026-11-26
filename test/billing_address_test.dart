import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:sudhamrtam_customer_app/features/checkout/order_preparation_service.dart';
import 'package:sudhamrtam_customer_app/features/orders/order_details_screen.dart';
import 'package:sudhamrtam_customer_app/models/customer_address.dart';
import 'package:sudhamrtam_customer_app/models/customer_order.dart';
import 'package:sudhamrtam_customer_app/models/order_item.dart';
import 'package:sudhamrtam_customer_app/services/order_api_client.dart';

import 'order_preparation_service_test.dart' show createValidCart;

/// Billing address (owner request and decisions 2026-11-26): the same
/// as delivery by default, or another saved address.
void main() {
  final at = DateTime(2026, 11, 26);
  CustomerAddress address(String id, String name, String line) =>
      CustomerAddress(
        id: id,
        customerId: 'c1',
        label: id == 'office' ? 'Office' : 'Home',
        recipientName: name,
        phoneNumber: '9876543210',
        addressLine1: line,
        landmark: '',
        city: 'Hyderabad',
        state: 'Telangana',
        postalCode: '500090',
        createdAt: at,
        updatedAt: at,
      );
  final home = address('home', 'Asha', 'Flat 101, Green Towers');
  final office = address(
    'office',
    'Asha Enterprises',
    'Plot 7, Industrial Estate',
  );

  CustomerOrder prepare(CustomerAddress? billing) =>
      OrderPreparationService.prepare(
        cart: createValidCart(),
        fulfillmentMethod: FulfillmentMethod.delivery,
        paymentMethod: OrderPaymentMethod.cashOnDelivery,
        deliveryAddress: home.formattedAddress,
        recipientName: home.recipientName,
        recipientPhone: home.phoneNumber,
        addressId: home.id,
        billing: billing,
      );

  test('same as delivery: nothing extra, and nothing extra is sent', () {
    for (final order in [prepare(null), prepare(home)]) {
      expect(order.billedElsewhere, isFalse);
      expect(order.billingAddressId, isNull);
      expect(order.toMap().keys.where((k) => k.startsWith('billing')), isEmpty);
      expect(
        OrderApiClient.requestBody(order).containsKey('billing_address_id'),
        isFalse,
      );
    }
  });

  test('billed to another saved address: kept with the order and sent', () {
    final order = prepare(office);
    expect(order.billedElsewhere, isTrue);
    expect(order.billingName, 'Asha Enterprises');
    expect(order.billingAddress, contains('Plot 7, Industrial Estate'));
    expect(OrderApiClient.requestBody(order)['billing_address_id'], 'office');

    // Saved on the phone and read back.
    final again = CustomerOrder.fromMap(order.toMap(), items: order.items);
    expect(again.billingName, 'Asha Enterprises');
    expect(again.billingAddress, order.billingAddress);
  });

  CustomerOrder saved({bool elsewhere = false}) => CustomerOrder(
    id: 'a' * 32,
    createdAt: at,
    items: const [
      OrderItem(
        productId: 'curd',
        productName: 'Curd',
        unit: '500 g',
        quantity: 1,
        unitPrice: 60,
      ),
    ],
    fulfillmentMethod: FulfillmentMethod.delivery,
    paymentMethod: OrderPaymentMethod.cashOnDelivery,
    deliveryAddress: home.formattedAddress,
    recipientName: 'Asha',
    recipientPhone: '9876543210',
    billingAddressId: elsewhere ? 'office' : null,
    billingName: elsewhere ? 'Asha Enterprises' : null,
    billingPhone: elsewhere ? '9876543210' : null,
    billingAddress: elsewhere ? office.formattedAddress : null,
  );

  testWidgets('Order Details: Billed to', (tester) async {
    await tester.pumpWidget(
      MaterialApp(home: OrderDetailsScreen(order: saved())),
    );
    expect(find.text('Billed to'), findsOneWidget);
    expect(find.text('Same as delivery address'), findsOneWidget);

    await tester.pumpWidget(
      MaterialApp(
        key: UniqueKey(),
        home: OrderDetailsScreen(order: saved(elsewhere: true)),
      ),
    );
    expect(find.text('Same as delivery address'), findsNothing);
    expect(
      find.textContaining('Asha Enterprises · 9876543210'),
      findsOneWidget,
    );
    expect(find.textContaining('Plot 7, Industrial Estate'), findsOneWidget);
  });
}
