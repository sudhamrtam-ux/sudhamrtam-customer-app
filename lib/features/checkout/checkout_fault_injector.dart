import '../../database/atomic_checkout_preparation_service.dart';
import '../../models/cart_manager.dart';
import '../../models/customer_order.dart';

/// Checkout stages at which a failure can be simulated.
enum CheckoutFault {
  /// Normal checkout.
  none,

  /// The checkout is durably prepared, but the order is
  /// not saved. Restarting the app should show the
  /// Unfinished Order screen.
  afterPreparation,

  /// The order is saved and the SQLite cart is cleared,
  /// but the in-memory cart refresh fails. Restarting the
  /// app should complete recovery automatically.
  afterOrderSaved,
}

/// DEBUG BUILDS ONLY: simulates checkout failures so that
/// recovery can be tested on a physical device.
///
/// Plugs into [DurableCheckoutCoordinator]'s existing
/// `prepareCheckout` and `refreshCart` hooks. An armed
/// fault fires once and then disarms, so an in-session
/// Retry behaves normally.
class CheckoutFaultInjector {
  CheckoutFaultInjector({
    Future<void> Function(CustomerOrder)? prepareCheckout,
    Future<void> Function(CartManager)? refreshCart,
  }) : _prepareCheckout =
           prepareCheckout ??
           AtomicCheckoutPreparationService.instance.prepareCheckout,
       _refreshCart =
           refreshCart ?? ((cart) => cart.refreshAfterCheckoutReconciliation());

  final Future<void> Function(CustomerOrder) _prepareCheckout;
  final Future<void> Function(CartManager) _refreshCart;

  CheckoutFault armed = CheckoutFault.none;

  Future<void> prepareCheckout(CustomerOrder order) async {
    // The real preparation always runs first, so the
    // durable records exist exactly as after a crash.
    await _prepareCheckout(order);

    if (_fire(CheckoutFault.afterPreparation)) {
      throw StateError(
        'Simulated failure after preparing the order (debug test).',
      );
    }
  }

  Future<void> refreshCart(CartManager cart) async {
    if (_fire(CheckoutFault.afterOrderSaved)) {
      throw StateError(
        'Simulated failure after saving the order (debug test).',
      );
    }

    await _refreshCart(cart);
  }

  bool _fire(CheckoutFault fault) {
    if (armed != fault) return false;

    armed = CheckoutFault.none;
    return true;
  }
}
