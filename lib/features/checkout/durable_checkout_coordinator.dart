import '../../database/atomic_checkout_preparation_service.dart';
import '../../database/checkout_reconciliation_service.dart';
import '../../database/order_database_service.dart';
import '../../database/pending_order_submission_service.dart';
import '../../models/cart_manager.dart';
import '../../models/customer_order.dart';
import 'order_snapshot_equivalence.dart';
import 'order_submission_service.dart';

/// Coordinates a customer-initiated durable local checkout.
///
/// Every checkout must use a stable, preassigned order ID.
///
/// Unresolved or uncertain checkouts retain the cart recovery lock.
class DurableCheckoutCoordinator {
  DurableCheckoutCoordinator({
    OrderSubmissionService? orderSubmissionService,
    Future<void> Function(CustomerOrder)? prepareCheckout,
    Future<void> Function(CartManager)? refreshCart,
  }) : _orderSubmissionService =
           orderSubmissionService ?? OrderSubmissionService(),
       _prepareCheckout =
           prepareCheckout ??
           AtomicCheckoutPreparationService.instance.prepareCheckout,
       _refreshCart =
           refreshCart ?? ((cart) => cart.refreshAfterCheckoutReconciliation());

  final OrderSubmissionService _orderSubmissionService;

  final Future<void> Function(CustomerOrder) _prepareCheckout;

  final Future<void> Function(CartManager) _refreshCart;

  bool _isProcessing = false;

  bool get isProcessing => _isProcessing;

  /// Submits or safely resumes a durable checkout.
  ///
  /// Checkout stages:
  /// 1. Acquire the active cart lock.
  /// 2. Inspect existing pending submission.
  /// 3. Inspect reconciliation state.
  /// 4. Resume completed reconciliation when applicable.
  /// 5. Atomically prepare the original checkout.
  /// 6. Verify and save the original order.
  /// 7. Reconcile the persisted SQLite cart.
  /// 8. Refresh the in-memory cart.
  /// 9. Clean up the pending submission.
  /// 10. Release locks only after successful completion.
  Future<CustomerOrder> submitPreparedOrder({
    required CustomerOrder order,
    required CartManager cart,
  }) async {
    if (_isProcessing) {
      throw StateError('Checkout is already in progress.');
    }

    _isProcessing = true;

    var cartLocked = false;
    var checkoutResolved = false;
    var preparationAttempted = false;

    try {
      // =================================================
      // 1. ACQUIRE ACTIVE CHECKOUT CART LOCK
      // =================================================

      cartLocked = await cart.beginCheckoutCartLock();

      if (!cartLocked) {
        throw StateError('The shopping cart is not ready for checkout.');
      }

      final pendingService = PendingOrderSubmissionService.instance;

      final reconciliationService = CheckoutReconciliationService.instance;

      final orderDatabase = OrderDatabaseService.instance;

      // =================================================
      // 2. INSPECT EXISTING PENDING SUBMISSION
      // =================================================

      CustomerOrder? pending;

      try {
        pending = await pendingService.getPendingOrder();
      } catch (_) {
        cart.beginCheckoutRecoveryLock();
        rethrow;
      }

      if (pending != null) {
        cart.beginCheckoutRecoveryLock();

        if (!OrderSnapshotEquivalence.matches(pending, order)) {
          throw StateError(
            'An unresolved checkout does not match this order. '
            'The original checkout must be resolved first.',
          );
        }
      }

      // =================================================
      // 3. INSPECT RECONCILIATION STATE
      // =================================================

      String? reconciliationState;

      try {
        reconciliationState = await reconciliationService
            .getReconciliationState(order.id);
      } catch (_) {
        cart.beginCheckoutRecoveryLock();
        rethrow;
      }

      // =================================================
      // 4. RESUME COMPLETED RECONCILIATION
      // =================================================

      if (reconciliationState == CheckoutReconciliationService.completed) {
        cart.beginCheckoutRecoveryLock();

        if (pending == null) {
          throw StateError(
            'Checkout was already completed. '
            'A new submission is not permitted.',
          );
        }

        // Verify that the saved order matches the
        // original durable checkout snapshot.
        final saved = await _verifySavedOrder(
          order: pending,
          orderDatabase: orderDatabase,
        );

        // IMPORTANT:
        // Refresh the in-memory cart BEFORE deleting
        // the original pending submission.
        //
        // If refresh fails, the pending record remains
        // available for a safe retry.
        await _refreshCart(cart);

        // Delete pending submission only after
        // successful in-memory refresh.
        final cleaned = await pendingService.completeReconciledSubmission(
          order.id,
        );

        if (!cleaned) {
          throw StateError('Pending checkout cleanup could not be verified.');
        }

        checkoutResolved = true;

        return saved;
      }

      // =================================================
      // 5. REJECT UNKNOWN RECONCILIATION STATES
      // =================================================

      if (reconciliationState != null &&
          reconciliationState != CheckoutReconciliationService.pending) {
        cart.beginCheckoutRecoveryLock();

        throw StateError('Unknown checkout reconciliation state.');
      }

      // =================================================
      // 6. REJECT ORPHANED PENDING RECONCILIATION
      // =================================================

      if (reconciliationState == CheckoutReconciliationService.pending &&
          pending == null) {
        cart.beginCheckoutRecoveryLock();

        throw StateError(
          'Checkout reconciliation exists without '
          'its original pending order. '
          'Manual recovery is required.',
        );
      }

      // =================================================
      // 7. PREPARE CHECKOUT ATOMICALLY
      // =================================================

      preparationAttempted = true;

      // Activate recovery protection before attempting
      // SQLite preparation.
      //
      // The transaction may commit even if the caller
      // does not receive its confirmation.
      cart.beginCheckoutRecoveryLock();

      await _prepareCheckout(order);

      // =================================================
      // 8. VERIFY DURABLE PENDING SNAPSHOT
      // =================================================

      final durablePending = await pendingService.getPendingOrder();

      if (durablePending == null ||
          !OrderSnapshotEquivalence.matches(durablePending, order)) {
        throw StateError(
          'The durable checkout snapshot '
          'could not be verified.',
        );
      }

      // =================================================
      // 9. SUBMIT ORIGINAL DURABLE ORDER
      // =================================================

      final saved = await _orderSubmissionService.submit(durablePending);

      if (!OrderSnapshotEquivalence.matches(durablePending, saved)) {
        throw StateError(
          'Saved order does not match '
          'the original checkout snapshot.',
        );
      }

      // =================================================
      // 10. VERIFY SAVED ORDER IN SQLITE
      // =================================================

      await _verifySavedOrder(
        order: durablePending,
        orderDatabase: orderDatabase,
      );

      // =================================================
      // 11. RECONCILE PERSISTED SQLITE CART
      // =================================================

      await reconciliationService.reconcileSavedOrder(order.id);

      // =================================================
      // 12. REFRESH IN-MEMORY CART
      // =================================================

      // IMPORTANT:
      // Both checkout protection locks remain active.
      //
      // The pending submission is intentionally
      // retained until refresh succeeds.
      //
      // If refresh fails:
      // - The saved order remains intact.
      // - SQLite reconciliation remains completed.
      // - The pending submission remains available.
      // - The recovery lock remains active.
      await _refreshCart(cart);

      // =================================================
      // 13. CLEAN UP PENDING SUBMISSION
      // =================================================

      // Cleanup happens only after the cart has
      // been refreshed successfully.
      final cleaned = await pendingService.completeReconciledSubmission(
        order.id,
      );

      if (!cleaned) {
        throw StateError(
          'Pending checkout cleanup '
          'could not be verified.',
        );
      }

      checkoutResolved = true;

      return saved;
    } catch (_) {
      // =================================================
      // FAILURE PROTECTION
      // =================================================

      // Preserve recovery protection whenever
      // checkout preparation may have committed.
      if (cartLocked && preparationAttempted) {
        cart.beginCheckoutRecoveryLock();
      }

      rethrow;
    } finally {
      // =================================================
      // LOCK CLEANUP
      // =================================================

      // Release the recovery lock only after
      // successful checkout completion.
      if (checkoutResolved) {
        cart.endCheckoutRecoveryLock();
      }

      // Always release the temporary processing lock
      // when it was successfully acquired.
      if (cartLocked) {
        cart.endCheckoutCartLock();
      }

      _isProcessing = false;
    }
  }

  // ===================================================
  // SAVED ORDER VERIFICATION
  // ===================================================

  /// Loads the saved order from SQLite and verifies
  /// its immutable fields against the original
  /// durable checkout snapshot.
  Future<CustomerOrder> _verifySavedOrder({
    required CustomerOrder order,
    required OrderDatabaseService orderDatabase,
  }) async {
    final saved = await orderDatabase.getOrderById(order.id);

    if (saved == null) {
      throw StateError(
        'The saved order could not be found '
        'during checkout verification.',
      );
    }

    if (!OrderSnapshotEquivalence.matches(order, saved)) {
      throw StateError(
        'The saved order differs from '
        'the original pending checkout. '
        'Automatic completion has been stopped.',
      );
    }

    return saved;
  }
}
