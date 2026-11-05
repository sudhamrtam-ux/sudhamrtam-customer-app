import '../features/checkout/order_snapshot_equivalence.dart';
import 'checkout_reconciliation_service.dart';
import 'checkout_startup_recovery_service.dart';
import 'order_database_service.dart';
import 'pending_order_submission_service.dart';

/// Result of attempting safe startup checkout recovery.
enum CheckoutRecoveryExecutionStatus {
  /// No unresolved checkout exists.
  noRecoveryNeeded,

  /// A saved order was reconciled and its pending
  /// submission was removed.
  recovered,

  /// A prepared order has not been saved.
  /// Preserve the cart and pending submission.
  awaitingSubmission,

  /// Automatic recovery was stopped because the
  /// checkout records or cart require investigation.
  blocked,
}

/// Immutable result of checkout recovery execution.
class CheckoutRecoveryExecutionResult {
  final CheckoutRecoveryExecutionStatus status;
  final String? orderId;
  final String message;

  const CheckoutRecoveryExecutionResult({
    required this.status,
    required this.orderId,
    required this.message,
  });

  /// Normal startup is allowed only when recovery
  /// is unnecessary or has completed successfully.
  bool get canContinueNormalStartup =>
      status == CheckoutRecoveryExecutionStatus.noRecoveryNeeded ||
      status == CheckoutRecoveryExecutionStatus.recovered;
}

/// Executes recovery before CartManager initialization.
///
/// Do not invoke this service while the app is running
/// and cart persistence operations may be queued.
///
/// A saved order must match its original durable pending
/// submission before cart reconciliation or pending cleanup.
class CheckoutRecoveryExecutor {
  CheckoutRecoveryExecutor._();

  static final CheckoutRecoveryExecutor instance = CheckoutRecoveryExecutor._();

  // =====================================================
  // VERIFY SAVED ORDER SNAPSHOT
  // =====================================================

  /// Verifies that the saved order matches the durable
  /// original pending submission.
  ///
  /// A matching order ID alone is not sufficient.
  ///
  /// Throws StateError when:
  /// - The expected pending order is missing.
  /// - The saved order is missing.
  /// - Immutable order details do not match.
  ///
  /// This method does not modify the database.
  Future<void> _verifySavedOrderSnapshot(String orderId) async {
    final pending = await PendingOrderSubmissionService.instance
        .getPendingOrder();

    if (pending == null || pending.id != orderId) {
      throw StateError('The expected pending order snapshot was not found.');
    }

    final saved = await OrderDatabaseService.instance.getOrderById(orderId);

    if (saved == null) {
      throw StateError(
        'The saved order was not found during recovery verification.',
      );
    }

    if (!OrderSnapshotEquivalence.matches(pending, saved)) {
      throw StateError(
        'Saved order differs from the original pending submission. '
        'Automatic recovery has been stopped.',
      );
    }
  }

  // =====================================================
  // STARTUP RECOVERY
  // =====================================================

  Future<CheckoutRecoveryExecutionResult> recoverAtStartup() async {
    final inspection = await CheckoutStartupRecoveryService.instance
        .inspectRecoveryState();

    switch (inspection.status) {
      // -------------------------------------------------
      // CASE 1: NO PENDING CHECKOUT
      // -------------------------------------------------
      case CheckoutRecoveryStatus.noPendingCheckout:
        return const CheckoutRecoveryExecutionResult(
          status: CheckoutRecoveryExecutionStatus.noRecoveryNeeded,
          orderId: null,
          message: 'No checkout recovery is required.',
        );

      // -------------------------------------------------
      // CASE 2: ORDER NOT YET SAVED
      // -------------------------------------------------
      case CheckoutRecoveryStatus.awaitingOrderSubmission:
        return CheckoutRecoveryExecutionResult(
          status: CheckoutRecoveryExecutionStatus.awaitingSubmission,
          orderId: inspection.orderId,
          message:
              'An unfinished order submission was found. '
              'The cart and pending order have been preserved.',
        );

      // -------------------------------------------------
      // CASE 3: INCONSISTENT RECOVERY STATE
      // -------------------------------------------------
      case CheckoutRecoveryStatus.requiresManualRecovery:
        return CheckoutRecoveryExecutionResult(
          status: CheckoutRecoveryExecutionStatus.blocked,
          orderId: inspection.orderId,
          message:
              'Checkout recovery requires investigation. '
              'No customer data has been modified.',
        );

      // -------------------------------------------------
      // CASE 4: SAVED ORDER NEEDS CART RECONCILIATION
      // -------------------------------------------------
      case CheckoutRecoveryStatus.needsCartReconciliation:
        final orderId = inspection.orderId;

        if (orderId == null) {
          return const CheckoutRecoveryExecutionResult(
            status: CheckoutRecoveryExecutionStatus.blocked,
            orderId: null,
            message: 'Recovery order ID is missing.',
          );
        }

        try {
          // Verify the complete immutable order snapshot
          // before allowing any cart modifications.
          await _verifySavedOrderSnapshot(orderId);

          // Clear the persisted cart and mark reconciliation
          // completed in one SQLite transaction.
          await CheckoutReconciliationService.instance.reconcileSavedOrder(
            orderId,
          );

          // Remove the pending submission only after
          // successful reconciliation.
          final cleanupCompleted = await PendingOrderSubmissionService.instance
              .completeReconciledSubmission(orderId);

          if (!cleanupCompleted) {
            throw StateError(
              'Pending submission cleanup could not be '
              'verified for order $orderId.',
            );
          }

          return CheckoutRecoveryExecutionResult(
            status: CheckoutRecoveryExecutionStatus.recovered,
            orderId: orderId,
            message: 'Saved order reconciled and pending submission completed.',
          );
        } catch (error) {
          // Preserve the cart and pending records when
          // verification or reconciliation fails.
          return CheckoutRecoveryExecutionResult(
            status: CheckoutRecoveryExecutionStatus.blocked,
            orderId: orderId,
            message: 'Automatic checkout recovery stopped safely: $error',
          );
        }

      // -------------------------------------------------
      // CASE 5: RECONCILIATION COMPLETE, CLEANUP PENDING
      // -------------------------------------------------
      case CheckoutRecoveryStatus.needsPendingCleanup:
        final orderId = inspection.orderId;

        if (orderId == null) {
          return const CheckoutRecoveryExecutionResult(
            status: CheckoutRecoveryExecutionStatus.blocked,
            orderId: null,
            message: 'Recovery order ID is missing.',
          );
        }

        try {
          // Verify the saved order against the durable
          // pending snapshot before deleting recovery data.
          await _verifySavedOrderSnapshot(orderId);

          final cleanupCompleted = await PendingOrderSubmissionService.instance
              .completeReconciledSubmission(orderId);

          if (!cleanupCompleted) {
            throw StateError(
              'Pending submission cleanup could not be '
              'verified for order $orderId.',
            );
          }

          return CheckoutRecoveryExecutionResult(
            status: CheckoutRecoveryExecutionStatus.recovered,
            orderId: orderId,
            message: 'Previously reconciled order cleanup completed.',
          );
        } catch (error) {
          // Keep the pending submission available
          // for investigation if verification fails.
          return CheckoutRecoveryExecutionResult(
            status: CheckoutRecoveryExecutionStatus.blocked,
            orderId: orderId,
            message: 'Pending submission cleanup stopped safely: $error',
          );
        }
    }
  }
}
