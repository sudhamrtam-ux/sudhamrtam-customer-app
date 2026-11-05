import 'package:flutter_test/flutter_test.dart';

import 'package:sudhamrtam_customer_app/features/checkout/checkout_validator.dart';
import 'package:sudhamrtam_customer_app/models/cart_manager.dart';
import 'package:sudhamrtam_customer_app/models/customer_order.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Sudhamrtam Checkout Validator', () {
    test('Rejects an uninitialized empty cart', () {
      final cart = CartManager();

      final result = CheckoutValidator.validate(
        cart: cart,
        fulfillmentMethod: FulfillmentMethod.pickup,
        paymentMethod: OrderPaymentMethod.cashOnDelivery,
      );

      expect(result.isValid, isFalse);

      expect(result.errors, contains('Shopping cart is not ready.'));

      expect(result.errors, contains('Your shopping cart is empty.'));
    });

    test('Requires an address for Home Delivery', () {
      final cart = CartManager();

      final result = CheckoutValidator.validate(
        cart: cart,
        fulfillmentMethod: FulfillmentMethod.delivery,
        paymentMethod: OrderPaymentMethod.cashOnDelivery,
        deliveryAddress: '',
      );

      expect(result.isValid, isFalse);

      expect(result.errors, contains('Please enter your delivery address.'));
    });

    test('Rejects an address containing only spaces', () {
      final cart = CartManager();

      final result = CheckoutValidator.validate(
        cart: cart,
        fulfillmentMethod: FulfillmentMethod.delivery,
        paymentMethod: OrderPaymentMethod.online,
        deliveryAddress: '   ',
      );

      expect(result.errors, contains('Please enter your delivery address.'));
    });

    test('Accepts a nonempty address for the address rule', () {
      final cart = CartManager();

      final result = CheckoutValidator.validate(
        cart: cart,
        fulfillmentMethod: FulfillmentMethod.delivery,
        paymentMethod: OrderPaymentMethod.cashOnDelivery,
        deliveryAddress: 'Kukatpally, Hyderabad',
      );

      expect(
        result.errors,
        isNot(contains('Please enter your delivery address.')),
      );

      // Other checks still fail because the cart
      // has not been initialized or populated.
      expect(result.isValid, isFalse);
    });

    test('Store Pickup does not require an address', () {
      final cart = CartManager();

      final result = CheckoutValidator.validate(
        cart: cart,
        fulfillmentMethod: FulfillmentMethod.pickup,
        paymentMethod: OrderPaymentMethod.cashOnDelivery,
      );

      expect(
        result.errors,
        isNot(contains('Please enter your delivery address.')),
      );
    });

    test('Validation errors cannot be modified', () {
      final cart = CartManager();

      final result = CheckoutValidator.validate(
        cart: cart,
        fulfillmentMethod: FulfillmentMethod.pickup,
        paymentMethod: OrderPaymentMethod.online,
      );

      expect(
        () => result.errors.add('Unexpected error'),
        throwsUnsupportedError,
      );
    });
  });
}
