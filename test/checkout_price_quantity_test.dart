import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:sudhamrtam_customer_app/features/checkout/checkout_validator.dart';
import 'package:sudhamrtam_customer_app/models/cart_item.dart';
import 'package:sudhamrtam_customer_app/models/cart_manager.dart';
import 'package:sudhamrtam_customer_app/models/customer_order.dart';
import 'package:sudhamrtam_customer_app/models/product.dart';

// ==========================================
// TEST-ONLY CART
// ==========================================

// This cart never initializes SQLite and never
// schedules database writes.
//
// It overrides only the getters used by
// CheckoutValidator.

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
// TEMPORARY TEST PRODUCT
// ==========================================

Product testProduct({required double price, String id = 'test-product'}) {
  return Product(
    id: id,
    name: 'Test Milk',
    category: 'Dairy',
    description: 'Temporary validation test product',
    price: price,
    unit: '1 L',
    icon: Icons.local_drink_outlined,
  );
}

// ==========================================
// VALIDATE TEST CART
// ==========================================

CheckoutValidationResult validateTestCart({
  required double price,
  int quantity = 1,
}) {
  final product = testProduct(price: price);

  final cart = TestCartManager([
    CartItem(product: product, quantity: quantity),
  ]);

  return CheckoutValidator.validate(
    cart: cart,
    fulfillmentMethod: FulfillmentMethod.pickup,
    paymentMethod: OrderPaymentMethod.cashOnDelivery,
  );
}

// ==========================================
// AUTOMATED TESTS
// ==========================================

void main() {
  group('Sudhamrtam Checkout Price Validation', () {
    test('Rejects zero product price', () {
      final result = validateTestCart(price: 0);

      expect(result.isValid, isFalse);

      expect(result.errors, contains('Price is not configured for Test Milk.'));
    });

    test('Rejects negative product price', () {
      final result = validateTestCart(price: -10);

      expect(result.isValid, isFalse);

      expect(result.errors, contains('Price is not configured for Test Milk.'));
    });

    test('Rejects NaN product price', () {
      final result = validateTestCart(price: double.nan);

      expect(result.isValid, isFalse);

      expect(result.errors, contains('Price is not configured for Test Milk.'));
    });

    test('Rejects infinite product price', () {
      final result = validateTestCart(price: double.infinity);

      expect(result.isValid, isFalse);

      expect(result.errors, contains('Price is not configured for Test Milk.'));
    });

    test('Accepts valid positive product price', () {
      final result = validateTestCart(price: 80);

      expect(result.isValid, isTrue);
      expect(result.errors, isEmpty);
    });
  });

  group('Sudhamrtam Checkout Quantity Validation', () {
    test('Accepts quantity 1', () {
      final result = validateTestCart(price: 80, quantity: 1);

      expect(result.isValid, isTrue);
    });

    test('Accepts maximum quantity 100', () {
      final result = validateTestCart(
        price: 80,
        quantity: CartManager.maxQuantityPerProduct,
      );

      expect(result.isValid, isTrue);
    });

    test('Rejects quantity above maximum', () {
      final result = validateTestCart(price: 80, quantity: 101);

      expect(result.isValid, isFalse);

      expect(result.errors, contains('Invalid quantity for Test Milk.'));
    });

    test('Rejects invalid order subtotal', () {
      final result = validateTestCart(price: 0, quantity: 1);

      expect(result.isValid, isFalse);

      expect(result.errors, contains('Order subtotal is invalid.'));
    });
  });
}
