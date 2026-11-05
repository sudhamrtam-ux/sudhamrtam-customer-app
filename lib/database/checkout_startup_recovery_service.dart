import 'milk_database_service.dart';

/// Possible states detected during checkout startup recovery.
enum CheckoutRecoveryStatus {
  /// No unresolved checkout exists.
  noPendingCheckout,

  /// A pending checkout exists, but the order is not saved.
  awaitingOrderSubmission,

  /// The order was saved, but cart reconciliation
  /// has not yet completed.
  needsCartReconciliation,

  /// Cart reconciliation is complete, but the pending
  /// submission still needs cleanup.
  needsPendingCleanup,

  /// Checkout records are inconsistent or incomplete.
  /// Do not modify the cart automatically.
  requiresManualRecovery,
}

/// Immutable result of inspecting checkout recovery state.
class CheckoutRecoveryResult {
  final CheckoutRecoveryStatus status;
  final String? orderId;
  final String message;

  const CheckoutRecoveryResult({
    required this.status,
    required this.orderId,
    required this.message,
  });

  bool get hasUnresolvedCheckout =>
      status != CheckoutRecoveryStatus.noPendingCheckout;
}

/// Inspects durable SQLite checkout state at app startup.
///
/// This service is read-only. It does not retry order
/// submission, reconcile the cart, or delete pending records.
class CheckoutStartupRecoveryService {
  CheckoutStartupRecoveryService._();

  static final CheckoutStartupRecoveryService instance =
      CheckoutStartupRecoveryService._();

  Future<CheckoutRecoveryResult> inspectRecoveryState() async {
    final db = await MilkDatabaseService.instance.database;

    return db.transaction((txn) async {
      // Check historical completed reconciliations.
      //
      // A completed reconciliation must always have a
      // corresponding saved order. Historical records are
      // retained and are never deleted by this inspection.
      final orphanedCompletedRows = await txn.rawQuery(
        '''
        SELECT r.order_id
        FROM ${MilkDatabaseService.checkoutReconciliationsTable} AS r
        LEFT JOIN ${MilkDatabaseService.ordersTable} AS o
          ON o.id = r.order_id
        WHERE r.reconciliation_state = ?
          AND o.id IS NULL
        ORDER BY r.created_at ASC
        LIMIT 1
      ''',
        ['completed'],
      );

      if (orphanedCompletedRows.isNotEmpty) {
        final orderId = orphanedCompletedRows.first['order_id'] as String;

        return CheckoutRecoveryResult(
          status: CheckoutRecoveryStatus.requiresManualRecovery,
          orderId: orderId,
          message:
              'Completed checkout reconciliation has no saved order. '
              'Manual recovery is required.',
        );
      }

      final pendingRows = await txn.query(
        MilkDatabaseService.pendingOrderSubmissionsTable,
        columns: ['order_id'],
        orderBy: 'created_at ASC',
      );

      final reconciliationRows = await txn.query(
        MilkDatabaseService.checkoutReconciliationsTable,
        columns: ['order_id', 'reconciliation_state'],
        where: 'reconciliation_state = ?',
        whereArgs: ['pending'],
        orderBy: 'created_at ASC',
      );

      if (pendingRows.isEmpty && reconciliationRows.isEmpty) {
        return const CheckoutRecoveryResult(
          status: CheckoutRecoveryStatus.noPendingCheckout,
          orderId: null,
          message: 'No unresolved checkout was found.',
        );
      }

      if (pendingRows.length != 1) {
        return const CheckoutRecoveryResult(
          status: CheckoutRecoveryStatus.requiresManualRecovery,
          orderId: null,
          message: 'Unexpected number of pending checkout submissions.',
        );
      }

      final orderId = pendingRows.first['order_id'] as String;

      final reconciliation = await txn.query(
        MilkDatabaseService.checkoutReconciliationsTable,
        columns: ['reconciliation_state'],
        where: 'order_id = ?',
        whereArgs: [orderId],
        limit: 1,
      );

      if (reconciliation.isEmpty) {
        return CheckoutRecoveryResult(
          status: CheckoutRecoveryStatus.requiresManualRecovery,
          orderId: orderId,
          message: 'Pending checkout has no reconciliation record.',
        );
      }

      if (reconciliationRows.any((row) => row['order_id'] != orderId)) {
        return CheckoutRecoveryResult(
          status: CheckoutRecoveryStatus.requiresManualRecovery,
          orderId: orderId,
          message: 'Another unresolved reconciliation was detected.',
        );
      }

      final state = reconciliation.first['reconciliation_state'] as String;

      final savedOrder = await txn.query(
        MilkDatabaseService.ordersTable,
        columns: ['id'],
        where: 'id = ?',
        whereArgs: [orderId],
        limit: 1,
      );

      final orderExists = savedOrder.isNotEmpty;

      if (state == 'completed') {
        if (!orderExists) {
          return CheckoutRecoveryResult(
            status: CheckoutRecoveryStatus.requiresManualRecovery,
            orderId: orderId,
            message: 'Reconciliation is complete, but the order is missing.',
          );
        }

        return CheckoutRecoveryResult(
          status: CheckoutRecoveryStatus.needsPendingCleanup,
          orderId: orderId,
          message: 'Saved order is reconciled. Pending cleanup remains.',
        );
      }

      if (state != 'pending') {
        return CheckoutRecoveryResult(
          status: CheckoutRecoveryStatus.requiresManualRecovery,
          orderId: orderId,
          message: 'Unknown checkout reconciliation state.',
        );
      }

      if (!orderExists) {
        return CheckoutRecoveryResult(
          status: CheckoutRecoveryStatus.awaitingOrderSubmission,
          orderId: orderId,
          message: 'Checkout is prepared but the order is not saved.',
        );
      }

      return CheckoutRecoveryResult(
        status: CheckoutRecoveryStatus.needsCartReconciliation,
        orderId: orderId,
        message: 'Saved order requires cart reconciliation.',
      );
    });
  }
}
