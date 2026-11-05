import 'dart:convert';

import 'package:sqflite/sqflite.dart';

import '../models/customer_order.dart';
import 'milk_database_service.dart';

/// Atomically prepares a durable customer checkout.
///
/// Writes the pending order and its cart reconciliation
/// record in one SQLite transaction.
///
/// This service does not submit the order, charge a payment,
/// or change cart quantities.
class AtomicCheckoutPreparationService {
  AtomicCheckoutPreparationService._();

  static final AtomicCheckoutPreparationService instance =
      AtomicCheckoutPreparationService._();

  static const String prepared = 'prepared';
  static const String reconciliationPending = 'pending';

  /// Saves both checkout preparation records atomically.
  ///
  /// Requirements:
  /// - The order must have valid products and prices.
  /// - The persisted cart must exactly match the order.
  /// - No other unresolved checkout may exist.
  ///
  /// Retrying with the same order ID and identical data
  /// is allowed if both records already exist.
  ///
  /// A partially prepared or conflicting checkout is
  /// rejected without changing existing records.
  Future<void> prepareCheckout(CustomerOrder order) async {
    if (order.id.trim().isEmpty) {
      throw StateError('Order ID cannot be empty.');
    }

    if (order.items.isEmpty || !order.hasValidPrices) {
      throw StateError(
        'Cannot prepare an order with empty items '
        'or invalid prices.',
      );
    }

    final expectedCart = _quantitiesFromOrder(order);

    final orderPayload = jsonEncode({
      'order': order.toMap(),
      'items': [for (final item in order.items) item.toMap()],
    });

    final cartSnapshot = _encodeSnapshot(expectedCart);

    final db = await MilkDatabaseService.instance.database;

    await db.transaction((txn) async {
      // ------------------------------------------
      // 1. Look for existing preparation records.
      // ------------------------------------------

      final pendingRows = await txn.query(
        MilkDatabaseService.pendingOrderSubmissionsTable,
        where: 'order_id = ?',
        whereArgs: [order.id],
        limit: 1,
      );

      final reconciliationRows = await txn.query(
        MilkDatabaseService.checkoutReconciliationsTable,
        where: 'order_id = ?',
        whereArgs: [order.id],
        limit: 1,
      );

      final hasPending = pendingRows.isNotEmpty;
      final hasReconciliation = reconciliationRows.isNotEmpty;

      // ------------------------------------------
      // 2. Handle idempotent preparation.
      // ------------------------------------------

      if (hasPending || hasReconciliation) {
        if (!hasPending || !hasReconciliation) {
          throw StateError(
            'Incomplete checkout preparation detected. '
            'Recovery is required before continuing.',
          );
        }

        final existingPending = pendingRows.first;
        final existingReconciliation = reconciliationRows.first;

        if (existingPending['order_payload'] != orderPayload ||
            existingReconciliation['cart_snapshot'] != cartSnapshot) {
          throw StateError(
            'Existing checkout data conflicts '
            'with the requested order.',
          );
        }

        final submissionState = existingPending['submission_state'] as String;

        final reconciliationState =
            existingReconciliation['reconciliation_state'] as String;

        if (reconciliationState != reconciliationPending) {
          throw StateError('This checkout has already been reconciled.');
        }

        if (submissionState != prepared && submissionState != 'uncertain') {
          throw StateError('Unknown pending submission state.');
        }

        // An identical prepared checkout already exists.
        // Do not create another record or modify the cart.
        return;
      }

      // ------------------------------------------
      // 3. Reject another unresolved checkout.
      // ------------------------------------------

      final otherPending = await txn.query(
        MilkDatabaseService.pendingOrderSubmissionsTable,
        columns: ['order_id'],
        limit: 1,
      );

      if (otherPending.isNotEmpty) {
        throw StateError(
          'Resolve the existing pending order '
          'before preparing another checkout.',
        );
      }

      final otherReconciliation = await txn.query(
        MilkDatabaseService.checkoutReconciliationsTable,
        columns: ['order_id'],
        where: 'reconciliation_state = ?',
        whereArgs: [reconciliationPending],
        limit: 1,
      );

      if (otherReconciliation.isNotEmpty) {
        throw StateError(
          'Resolve the previous checkout reconciliation '
          'before preparing another.',
        );
      }

      // ------------------------------------------
      // 4. Prevent preparing an already saved order.
      // ------------------------------------------

      final savedOrders = await txn.query(
        MilkDatabaseService.ordersTable,
        columns: ['id'],
        where: 'id = ?',
        whereArgs: [order.id],
        limit: 1,
      );

      if (savedOrders.isNotEmpty) {
        throw StateError('This order ID already exists in saved orders.');
      }

      // ------------------------------------------
      // 5. Verify the persisted cart.
      // ------------------------------------------

      final persistedCart = await _loadCart(txn);

      if (!_sameQuantities(persistedCart, expectedCart)) {
        throw StateError(
          'Persisted cart does not match '
          'the prepared order.',
        );
      }

      final now = DateTime.now().toUtc().toIso8601String();

      // ------------------------------------------
      // 6. Insert pending submission.
      // ------------------------------------------

      await txn.insert(MilkDatabaseService.pendingOrderSubmissionsTable, {
        'order_id': order.id,
        'created_at': order.createdAt.toUtc().toIso8601String(),
        'order_payload': orderPayload,
        'submission_state': prepared,
        'updated_at': now,
      }, conflictAlgorithm: ConflictAlgorithm.abort);

      // ------------------------------------------
      // 7. Insert reconciliation snapshot.
      //
      // Both inserts belong to the same transaction.
      // A failure here rolls back the pending insert.
      // ------------------------------------------

      await txn.insert(MilkDatabaseService.checkoutReconciliationsTable, {
        'order_id': order.id,
        'cart_snapshot': cartSnapshot,
        'reconciliation_state': reconciliationPending,
        'created_at': now,
        'completed_at': null,
      }, conflictAlgorithm: ConflictAlgorithm.abort);
    });
  }

  // ==========================================
  // ORDER QUANTITIES
  // ==========================================

  Map<String, int> _quantitiesFromOrder(CustomerOrder order) {
    final quantities = <String, int>{};

    for (final item in order.items) {
      final productId = item.productId;
      final quantity = item.quantity;

      if (productId.trim().isEmpty || quantity < 1 || quantity > 100) {
        throw StateError('Invalid product ID or quantity in checkout.');
      }

      if (quantities.containsKey(productId)) {
        throw StateError('Duplicate product ID in checkout: $productId');
      }

      quantities[productId] = quantity;
    }

    if (quantities.isEmpty) {
      throw StateError('Cannot prepare an empty checkout.');
    }

    return quantities;
  }

  // ==========================================
  // LOAD SQLITE CART
  // ==========================================

  Future<Map<String, int>> _loadCart(Transaction txn) async {
    final rows = await txn.query(
      MilkDatabaseService.cartItemsTable,
      columns: ['product_id', 'quantity'],
    );

    final result = <String, int>{};

    for (final row in rows) {
      final productId = row['product_id'] as String;
      final quantity = row['quantity'] as int;

      result[productId] = quantity;
    }

    return result;
  }

  // ==========================================
  // CANONICAL SNAPSHOT
  // ==========================================

  String _encodeSnapshot(Map<String, int> snapshot) {
    final sortedKeys = snapshot.keys.toList()..sort();

    return jsonEncode({for (final key in sortedKeys) key: snapshot[key]});
  }

  // ==========================================
  // CART COMPARISON
  // ==========================================

  bool _sameQuantities(Map<String, int> first, Map<String, int> second) {
    if (first.length != second.length) {
      return false;
    }

    for (final entry in first.entries) {
      if (second[entry.key] != entry.value) {
        return false;
      }
    }

    return true;
  }
}
