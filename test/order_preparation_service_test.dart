import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:sudhamrtam_customer_app/features/checkout/order_preparation_service.dart';
import 'package:sudhamrtam_customer_app/models/cart_item.dart';
import 'package:sudhamrtam_customer_app/models/cart_manager.dart';
import 'package:sudhamrtam_customer_app/models/customer_order.dart';
import 'package:sudhamrtam_customer_app/models/product.dart';

// ==========================================
// TEST-ONLY CART — NO SQLITE OPERATIONS
// ==========================================

class TestCartManager extends CartManager {
  final List<CartItem> testItems;

  TestCartManager(this.testItems);

  @override
  bool get isInitialized => true;

  @override
  bool get isLoading => false;

  @override
  List<CartItem> get items => List<CartItem>.unmodifiable(testItems);

  @override
  bool get isEmpty => testItems.isEmpty;

  @override
  bool get isNotEmpty => testItems.isNotEmpty;

  @override
  double get subtotal =>
      testItems.fold<double>(0.0, (total, item) => total + item.totalPrice);
}

// ==========================================
// TEST PRODUCT
// ==========================================

Product createTestProduct({
  required String id,
  required String name,
  required double price,
}) {
  return Product(
    id: id,
    name: name,
    category: 'Dairy',
    description: 'Order preparation test product',
    price: price,
    unit: '1 L',
    icon: Icons.local_drink_outlined,
  );
}

// ==========================================
// TEST CART
// ==========================================

TestCartManager createValidCart() {
  return TestCartManager([
    CartItem(
      product: createTestProduct(
        id: 'buffalo-milk-test',
        name: 'Buffalo Milk',
        price: 100,
      ),
      quantity: 2,
    ),
    CartItem(
      product: createTestProduct(
        id: 'cow-milk-test',
        name: 'Cow Milk',
        price: 80,
      ),
      quantity: 1,
    ),
  ]);
}

// ==========================================
// AUTOMATED TESTS
// ==========================================

void main() {
  group('Sudhamrtam Order Preparation', () {
    test('Prepares a valid Home Delivery order', () {
      final cart = createValidCart();

      final order = OrderPreparationService.prepare(
        cart: cart,
        fulfillmentMethod: FulfillmentMethod.delivery,
        paymentMethod: OrderPaymentMethod.cashOnDelivery,
        deliveryAddress: ' Kukatpally, Hyderabad ',
        recipientName: ' Lakshmi Devi ',
        recipientPhone: ' 9876543210 ',
        deliveryInstructions: ' Leave at the gate ',
      );

      expect(order.id, isNotEmpty);
      expect(order.createdAt.isUtc, isTrue);
      expect(order.status, OrderStatus.pending);

      expect(order.fulfillmentMethod, FulfillmentMethod.delivery);

      expect(order.paymentMethod, OrderPaymentMethod.cashOnDelivery);

      expect(order.deliveryAddress, 'Kukatpally, Hyderabad');
      expect(order.recipientName, 'Lakshmi Devi');
      expect(order.recipientPhone, '9876543210');
      expect(order.notes, 'Leave at the gate');

      expect(order.items.length, 2);
      expect(order.totalQuantity, 3);
      expect(order.subtotal, 280.0);

      expect(order.items[0].productName, 'Buffalo Milk');
      expect(order.items[0].quantity, 2);
      expect(order.items[0].unitPrice, 100.0);

      expect(order.items[1].productName, 'Cow Milk');
      expect(order.items[1].quantity, 1);
      expect(order.items[1].unitPrice, 80.0);
    });

    test('Store Pickup excludes delivery details', () {
      final order = OrderPreparationService.prepare(
        cart: createValidCart(),
        fulfillmentMethod: FulfillmentMethod.pickup,
        paymentMethod: OrderPaymentMethod.online,
        deliveryAddress: 'Unused address',
        recipientName: 'Unused name',
        recipientPhone: 'Unused phone',
        deliveryInstructions: 'Unused instructions',
      );

      expect(order.fulfillmentMethod, FulfillmentMethod.pickup);
      expect(order.paymentMethod, OrderPaymentMethod.online);
      expect(order.deliveryAddress, isNull);
      expect(order.recipientName, isNull);
      expect(order.recipientPhone, isNull);
      expect(order.notes, isNull);
    });

    test('Rejects Home Delivery without recipient name or phone', () {
      for (final (name, phone) in [
        (null, '9876543210'),
        ('Lakshmi Devi', null),
        ('   ', '9876543210'),
        ('Lakshmi Devi', '   '),
      ]) {
        expect(
          () => OrderPreparationService.prepare(
            cart: createValidCart(),
            fulfillmentMethod: FulfillmentMethod.delivery,
            paymentMethod: OrderPaymentMethod.cashOnDelivery,
            deliveryAddress: 'Kukatpally, Hyderabad',
            recipientName: name,
            recipientPhone: phone,
          ),
          throwsStateError,
          reason: 'name=$name phone=$phone',
        );
      }
    });

    test('Rejects Home Delivery without an address', () {
      expect(
        () => OrderPreparationService.prepare(
          cart: createValidCart(),
          fulfillmentMethod: FulfillmentMethod.delivery,
          paymentMethod: OrderPaymentMethod.cashOnDelivery,
          deliveryAddress: '   ',
        ),
        throwsStateError,
      );
    });

    test('Rejects products with unconfigured prices', () {
      final cart = TestCartManager([
        CartItem(
          product: createTestProduct(
            id: 'unpriced-product',
            name: 'Unpriced Milk',
            price: 0,
          ),
          quantity: 1,
        ),
      ]);

      expect(
        () => OrderPreparationService.prepare(
          cart: cart,
          fulfillmentMethod: FulfillmentMethod.pickup,
          paymentMethod: OrderPaymentMethod.cashOnDelivery,
        ),
        throwsStateError,
      );
    });

    test('Generates different IDs for separate orders', () {
      final cart = createValidCart();

      final firstOrder = OrderPreparationService.prepare(
        cart: cart,
        fulfillmentMethod: FulfillmentMethod.pickup,
        paymentMethod: OrderPaymentMethod.cashOnDelivery,
      );

      final secondOrder = OrderPreparationService.prepare(
        cart: cart,
        fulfillmentMethod: FulfillmentMethod.pickup,
        paymentMethod: OrderPaymentMethod.cashOnDelivery,
      );

      expect(firstOrder.id, isNot(secondOrder.id));
    });

    test('Does not clear or modify the shopping cart', () {
      final cart = createValidCart();

      final initialItems = cart.items.length;
      final initialSubtotal = cart.subtotal;

      OrderPreparationService.prepare(
        cart: cart,
        fulfillmentMethod: FulfillmentMethod.pickup,
        paymentMethod: OrderPaymentMethod.cashOnDelivery,
      );

      expect(cart.items.length, initialItems);
      expect(cart.subtotal, initialSubtotal);
      expect(cart.isNotEmpty, isTrue);
    });

    test('Prepared order items are immutable', () {
      final order = OrderPreparationService.prepare(
        cart: createValidCart(),
        fulfillmentMethod: FulfillmentMethod.pickup,
        paymentMethod: OrderPaymentMethod.cashOnDelivery,
      );

      expect(() => order.items.clear(), throwsUnsupportedError);
    });
  });
}
