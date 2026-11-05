import 'dart:convert';

import 'package:sqflite/sqflite.dart';

import '../models/customer_order.dart';
import 'milk_database_service.dart';

/// Reconciles a saved order against the persisted cart.
///
/// This service operates only on SQLite data. The in-memory
/// CartManager must be refreshed separately after success.
class CheckoutReconciliationService {
  CheckoutReconciliationService._();

  static final CheckoutReconciliationService instance =
      CheckoutReconciliationService._();

  static const String pending = 'pending';
  static const String completed = 'completed';

  /// Creates a durable checkout snapshot before order submission.
  ///
  /// Requires the persisted cart to exactly match the
  /// products and quantities in the prepared order.
  ///
  /// Repeating the operation with the same order and snapshot
  /// is allowed. A conflicting snapshot is rejected.
  Future<void> prepareReconciliation(CustomerOrder order) async {
    if (order.id.trim().isEmpty || order.items.isEmpty) {
      throw StateError('Cannot prepare an empty checkout.');
    }

    final expected = _quantitiesFromOrder(order);
    final snapshot = _encodeSnapshot(expected);
    final db = await MilkDatabaseService.instance.database;

    await db.transaction((txn) async {
      final existing = await txn.query(
        MilkDatabaseService.checkoutReconciliationsTable,
        columns: ['cart_snapshot'],
        where: 'order_id = ?',
        whereArgs: [order.id],
        limit: 1,
      );

      if (existing.isNotEmpty) {
        if (existing.first['cart_snapshot'] != snapshot) {
          throw StateError(
            'This order already has a different checkout snapshot.',
          );
        }
        return;
      }

      final otherUnresolved = await txn.query(
        MilkDatabaseService.checkoutReconciliationsTable,
        columns: ['order_id'],
        where: 'reconciliation_state = ?',
        whereArgs: [pending],
        limit: 1,
      );

      if (otherUnresolved.isNotEmpty) {
        throw StateError(
          'Resolve the previous checkout before preparing another.',
        );
      }

      final currentCart = await _loadCart(txn);

      if (!_sameQuantities(currentCart, expected)) {
        throw StateError(
          'Cart changed before checkout reconciliation was prepared.',
        );
      }

      await txn.insert(MilkDatabaseService.checkoutReconciliationsTable, {
        'order_id': order.id,
        'cart_snapshot': snapshot,
        'reconciliation_state': pending,
        'created_at': DateTime.now().toUtc().toIso8601String(),
        'completed_at': null,
      }, conflictAlgorithm: ConflictAlgorithm.abort);
    });
  }

  /// Completes reconciliation for an already-saved order.
  ///
  /// The cart is cleared and the reconciliation record is
  /// marked completed in the same SQLite transaction.
  ///
  /// Returns true when reconciliation was performed.
  /// Returns false if it was already completed.
  ///
  /// Throws if the order is missing or the persisted cart
  /// no longer matches its original checkout snapshot.
  Future<bool> reconcileSavedOrder(String orderId) async {
    if (orderId.trim().isEmpty) {
      throw ArgumentError('Order ID cannot be empty.');
    }

    final db = await MilkDatabaseService.instance.database;

    return db.transaction((txn) async {
      final rows = await txn.query(
        MilkDatabaseService.checkoutReconciliationsTable,
        where: 'order_id = ?',
        whereArgs: [orderId],
        limit: 1,
      );

      if (rows.isEmpty) {
        throw StateError('Checkout reconciliation record was not found.');
      }

      final record = rows.first;
      final state = record['reconciliation_state'] as String;

      if (state == completed) {
        return false;
      }

      if (state != pending) {
        throw StateError('Unknown checkout reconciliation state.');
      }

      final orderRows = await txn.query(
        MilkDatabaseService.ordersTable,
        columns: ['id'],
        where: 'id = ?',
        whereArgs: [orderId],
        limit: 1,
      );

      if (orderRows.isEmpty) {
        throw StateError(
          'Cannot reconcile checkout before the order is saved.',
        );
      }

      final expected = _decodeSnapshot(record['cart_snapshot'] as String);

      final orderItems = await txn.query(
        MilkDatabaseService.orderItemsTable,
        columns: ['product_id', 'quantity'],
        where: 'order_id = ?',
        whereArgs: [orderId],
      );

      final savedQuantities = <String, int>{};

      for (final item in orderItems) {
        final productId = item['product_id'] as String;
        final quantity = item['quantity'] as int;

        if (savedQuantities.containsKey(productId)) {
          throw StateError('Duplicate product found in saved order.');
        }

        savedQuantities[productId] = quantity;
      }

      if (!_sameQuantities(savedQuantities, expected)) {
        throw StateError(
          'Saved order items do not match the checkout snapshot.',
        );
      }

      final currentCart = await _loadCart(txn);

      if (!_sameQuantities(currentCart, expected)) {
        throw StateError(
          'Persisted cart changed after checkout preparation. '
          'Automatic reconciliation was stopped.',
        );
      }

      await txn.delete(MilkDatabaseService.cartItemsTable);

      final updated = await txn.update(
        MilkDatabaseService.checkoutReconciliationsTable,
        {
          'reconciliation_state': completed,
          'completed_at': DateTime.now().toUtc().toIso8601String(),
        },
        where: 'order_id = ? AND reconciliation_state = ?',
        whereArgs: [orderId, pending],
      );

      if (updated != 1) {
        throw StateError('Checkout reconciliation state could not be updated.');
      }

      return true;
    });
  }

  /// Returns the stored reconciliation state, if any.
  Future<String?> getReconciliationState(String orderId) async {
    final db = await MilkDatabaseService.instance.database;

    final rows = await db.query(
      MilkDatabaseService.checkoutReconciliationsTable,
      columns: ['reconciliation_state'],
      where: 'order_id = ?',
      whereArgs: [orderId],
      limit: 1,
    );

    if (rows.isEmpty) return null;

    return rows.first['reconciliation_state'] as String;
  }

  Map<String, int> _quantitiesFromOrder(CustomerOrder order) {
    final quantities = <String, int>{};

    for (final item in order.items) {
      if (item.productId.trim().isEmpty ||
          item.quantity < 1 ||
          item.quantity > 100 ||
          quantities.containsKey(item.productId)) {
        throw StateError('Invalid or duplicate checkout product.');
      }

      quantities[item.productId] = item.quantity;
    }

    return quantities;
  }

  Future<Map<String, int>> _loadCart(Transaction txn) async {
    final rows = await txn.query(
      MilkDatabaseService.cartItemsTable,
      columns: ['product_id', 'quantity'],
    );

    return {
      for (final row in rows)
        row['product_id'] as String: row['quantity'] as int,
    };
  }

  String _encodeSnapshot(Map<String, int> snapshot) {
    final keys = snapshot.keys.toList()..sort();

    return jsonEncode({for (final key in keys) key: snapshot[key]});
  }

  Map<String, int> _decodeSnapshot(String encoded) {
    final decoded = jsonDecode(encoded);

    if (decoded is! Map) {
      throw const FormatException('Invalid checkout snapshot.');
    }

    final result = <String, int>{};

    for (final entry in decoded.entries) {
      final key = entry.key;
      final value = entry.value;

      if (key is! String ||
          key.trim().isEmpty ||
          value is! int ||
          value < 1 ||
          value > 100) {
        throw const FormatException('Invalid checkout snapshot item.');
      }

      result[key] = value;
    }

    if (result.isEmpty) {
      throw const FormatException('Empty checkout snapshot.');
    }

    return result;
  }

  bool _sameQuantities(Map<String, int> first, Map<String, int> second) {
    if (first.length != second.length) return false;

    for (final entry in first.entries) {
      if (second[entry.key] != entry.value) {
        return false;
      }
    }

    return true;
  }
}
