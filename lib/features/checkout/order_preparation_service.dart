import 'dart:math';

import '../../models/cart_manager.dart';
import '../../models/customer_order.dart';
import '../../models/order_item.dart';
import 'checkout_validator.dart';

/// Prepares a validated customer order from the shopping cart.
///
/// This service does not save orders, clear the cart,
/// or initiate payment transactions.
class OrderPreparationService {
  const OrderPreparationService._();

  /// Creates a customer order snapshot ready for persistence.
  static CustomerOrder prepare({
    required CartManager cart,
    required FulfillmentMethod fulfillmentMethod,
    required OrderPaymentMethod paymentMethod,
    String? deliveryAddress,
    String? deliveryInstructions,
  }) {
    final normalizedAddress = deliveryAddress?.trim();
    final normalizedInstructions = deliveryInstructions?.trim();

    // Validate the current cart and checkout selections.
    final validation = CheckoutValidator.validate(
      cart: cart,
      fulfillmentMethod: fulfillmentMethod,
      paymentMethod: paymentMethod,
      deliveryAddress: normalizedAddress,
    );

    if (!validation.isValid) {
      throw StateError(validation.errors.join('\n'));
    }

    // Capture product details and prices at preparation time.
    final orderItems = <OrderItem>[
      for (final cartItem in cart.items)
        OrderItem.fromProduct(cartItem.product, quantity: cartItem.quantity),
    ];

    // Generate a random order identifier.
    final random = Random.secure();
    final randomBytes = List<int>.generate(16, (_) => random.nextInt(256));

    final orderId = randomBytes
        .map((byte) => byte.toRadixString(16).padLeft(2, '0'))
        .join();

    return CustomerOrder(
      id: orderId,
      createdAt: DateTime.now().toUtc(),
      items: orderItems,
      fulfillmentMethod: fulfillmentMethod,
      paymentMethod: paymentMethod,
      status: OrderStatus.pending,
      deliveryAddress: fulfillmentMethod == FulfillmentMethod.delivery
          ? normalizedAddress
          : null,
      notes:
          fulfillmentMethod == FulfillmentMethod.delivery &&
              normalizedInstructions != null &&
              normalizedInstructions.isNotEmpty
          ? normalizedInstructions
          : null,
    );
  }
}
