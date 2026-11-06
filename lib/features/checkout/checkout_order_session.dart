import '../../database/pending_order_submission_service.dart';
import '../../models/customer_order.dart';

/// Keeps one stable order (and order ID) for a checkout
/// until that checkout has been resolved.
///
/// A new order may be prepared only when no earlier
/// checkout attempt could still be unresolved:
///
/// 1. A durable pending order in SQLite always wins,
///    including one left behind by an earlier screen.
/// 2. While the cart recovery lock is active, the order
///    from the earlier attempt is reused, because its
///    preparation may have committed without confirmation.
/// 3. Otherwise a fresh order is prepared from the
///    customer's current selections.
///
/// This class never saves, submits, or clears anything.
class CheckoutOrderSession {
  CheckoutOrderSession({Future<CustomerOrder?> Function()? loadPendingOrder})
    : _loadPendingOrder =
          loadPendingOrder ??
          PendingOrderSubmissionService.instance.getPendingOrder;

  final Future<CustomerOrder?> Function() _loadPendingOrder;

  CustomerOrder? _order;

  /// The order most recently used for submission, if any.
  CustomerOrder? get currentOrder => _order;

  /// Returns the order to submit for this checkout attempt.
  ///
  /// [prepare] is called only when no unresolved order
  /// exists. [isRecoveryLocked] should reflect
  /// `CartManager.isCheckoutRecoveryLocked`.
  Future<CustomerOrder> resolveOrder({
    required bool isRecoveryLocked,
    required CustomerOrder Function() prepare,
  }) async {
    final durable = await _loadPendingOrder();

    if (durable != null) {
      return _order = durable;
    }

    final existing = _order;

    if (existing != null && isRecoveryLocked) {
      return existing;
    }

    return _order = prepare();
  }

  /// Forgets the order after its checkout completed.
  ///
  /// Ignored if [orderId] is not the current order.
  void markCompleted(String orderId) {
    if (_order?.id == orderId) {
      _order = null;
    }
  }
}
