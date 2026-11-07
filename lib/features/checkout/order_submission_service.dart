import '../../database/order_database_service.dart';
import '../../models/customer_order.dart';
import 'order_destination.dart';
import 'order_snapshot_equivalence.dart';

/// Coordinates order submission.
///
/// By default an order is saved through [OrderDestination]:
/// sent to the server first when one is configured, then saved
/// on the phone.
///
/// A prepared order is submitted using its existing ID.
/// The same ID must be reused when retrying a submission.
///
/// Existing saved orders must match the original
/// prepared order snapshot before being accepted.
class OrderSubmissionService {
  OrderSubmissionService({
    Future<void> Function(CustomerOrder)? saveOrder,
    Future<CustomerOrder?> Function(String)? getOrderById,
  }) : _saveOrder = saveOrder ?? OrderDestination.save,
       _getOrderById =
           getOrderById ?? OrderDatabaseService.instance.getOrderById;

  final Future<void> Function(CustomerOrder) _saveOrder;
  final Future<CustomerOrder?> Function(String) _getOrderById;

  bool _isSubmitting = false;
  CustomerOrder? _pendingOrder;

  bool get isSubmitting => _isSubmitting;

  CustomerOrder? get pendingOrder => _pendingOrder;

  /// Verifies that an existing saved order represents
  /// the same original submission.
  ///
  /// A matching order ID alone is not sufficient.
  CustomerOrder _verifyExistingOrder(
    CustomerOrder prepared,
    CustomerOrder saved,
  ) {
    if (!OrderSnapshotEquivalence.matches(prepared, saved)) {
      throw StateError(
        'An existing saved order does not match '
        'the prepared order snapshot. '
        'Submission has been stopped to protect customer data.',
      );
    }

    return saved;
  }

  /// Submits an already prepared order.
  ///
  /// Concurrent submissions are rejected.
  ///
  /// If submission fails, the prepared order is retained
  /// so retries reuse the same order ID.
  Future<CustomerOrder> submit(CustomerOrder order) async {
    if (_isSubmitting) {
      throw StateError('An order submission is already in progress.');
    }

    if (_pendingOrder != null && _pendingOrder!.id != order.id) {
      throw StateError(
        'A previous order is pending. '
        'Resolve it before submitting a new order.',
      );
    }

    // Never allow a different snapshot to replace
    // an unresolved submission with the same ID.
    if (_pendingOrder != null &&
        !OrderSnapshotEquivalence.matches(_pendingOrder!, order)) {
      throw StateError(
        'The pending order snapshot does not match '
        'the requested submission.',
      );
    }

    _pendingOrder = order;
    _isSubmitting = true;

    try {
      // The previous save may have completed even if
      // its confirmation was interrupted.
      final existing = await _getOrderById(order.id);

      if (existing != null) {
        final verified = _verifyExistingOrder(order, existing);

        _pendingOrder = null;
        return verified;
      }

      try {
        await _saveOrder(order);
      } catch (saveError) {
        // A database write may have succeeded before
        // an error was reported. Re-read the saved order.
        //
        // A mismatched existing order must not be accepted.
        try {
          final existingAfterError = await _getOrderById(order.id);

          if (existingAfterError != null) {
            final verified = _verifyExistingOrder(order, existingAfterError);

            _pendingOrder = null;
            return verified;
          }
        } on StateError {
          // Preserve snapshot mismatch errors rather
          // than silently treating them as success.
          rethrow;
        } catch (_) {
          // Verification was unavailable.
          // Preserve the original save failure.
        }

        Error.throwWithStackTrace(saveError, StackTrace.current);
      }

      _pendingOrder = null;
      return order;
    } finally {
      _isSubmitting = false;
    }
  }

  /// Retries the previously prepared order.
  ///
  /// Never generates a new order ID.
  Future<CustomerOrder> retryPendingOrder() async {
    if (_isSubmitting) {
      throw StateError('An order submission is already in progress.');
    }

    final order = _pendingOrder;

    if (order == null) {
      throw StateError('There is no pending order to retry.');
    }

    return submit(order);
  }
}
