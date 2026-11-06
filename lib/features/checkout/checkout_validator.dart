import '../../models/cart_manager.dart';
import '../../models/customer_order.dart';

/// Result of validating the current checkout details.
class CheckoutValidationResult {
  final bool isValid;
  final List<String> errors;

  CheckoutValidationResult({
    required this.isValid,
    required List<String> errors,
  }) : errors = List.unmodifiable(errors);
}

/// Validates checkout readiness without creating an order
/// or initiating any payment.
class CheckoutValidator {
  const CheckoutValidator._();

  static CheckoutValidationResult validate({
    required CartManager cart,
    required FulfillmentMethod fulfillmentMethod,
    required OrderPaymentMethod paymentMethod,
    String? deliveryAddress,
  }) {
    final errors = <String>[];

    // 1. Check cart initialization.
    if (!cart.isInitialized || cart.isLoading) {
      errors.add('Shopping cart is not ready.');
    }

    // 2. Check cart contents.
    if (cart.isEmpty) {
      errors.add('Your shopping cart is empty.');
    }

    // 3. Check product quantities and prices.
    for (final item in cart.items) {
      if (item.quantity <= 0 ||
          item.quantity > CartManager.maxQuantityPerProduct) {
        errors.add('Invalid quantity for ${item.product.name}.');
      }

      if (!item.product.isAvailable) {
        errors.add(
          '${item.product.name} is not available in your delivery area. '
          'Please remove it from your cart.',
        );
      } else if (!item.product.price.isFinite || item.product.price <= 0) {
        errors.add('Price is not configured for ${item.product.name}.');
      }
    }

    // 4. Check the total.
    if (!cart.subtotal.isFinite || (cart.isNotEmpty && cart.subtotal <= 0)) {
      errors.add('Order subtotal is invalid.');
    }

    // 5. Validate fulfillment details.
    if (fulfillmentMethod == FulfillmentMethod.delivery) {
      if (deliveryAddress == null || deliveryAddress.trim().isEmpty) {
        errors.add('Please enter your delivery address.');
      }
    }

    // 6. Verify supported payment options.
    switch (paymentMethod) {
      case OrderPaymentMethod.online:
      case OrderPaymentMethod.cashOnDelivery:
        break;
    }

    return CheckoutValidationResult(isValid: errors.isEmpty, errors: errors);
  }
}
