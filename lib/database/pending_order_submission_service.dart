import 'dart:convert';

import 'package:sqflite/sqflite.dart';

import '../models/customer_order.dart';
import '../models/order_item.dart';
import 'milk_database_service.dart';

/// Durable local storage for unresolved order submissions.
class PendingOrderSubmissionService {
  PendingOrderSubmissionService._();

  static final PendingOrderSubmissionService instance =
      PendingOrderSubmissionService._();

  static const String prepared = 'prepared';
  static const String uncertain = 'uncertain';

  // ==========================================
  // ORDER SERIALIZATION
  // ==========================================

  String _encodeOrder(CustomerOrder order) {
    return jsonEncode({
      'order': order.toMap(),
      'items': [for (final item in order.items) item.toMap()],
    });
  }

  CustomerOrder _decodeOrder(String payload) {
    final decoded = jsonDecode(payload) as Map<String, dynamic>;

    final orderMap = Map<String, Object?>.from(decoded['order'] as Map);

    final itemMaps = decoded['items'] as List;

    final items = [
      for (final item in itemMaps)
        OrderItem.fromMap(Map<String, Object?>.from(item as Map)),
    ];

    return CustomerOrder.fromMap(orderMap, items: items);
  }

  // ==========================================
  // SAVE PREPARED ORDER
  // ==========================================

  /// Stores a prepared order before attempting submission.
  ///
  /// Re-saving the same ID is permitted only when
  /// the serialized order content is identical.
  Future<void> savePreparedOrder(CustomerOrder order) async {
    final db = await MilkDatabaseService.instance.database;

    final payload = _encodeOrder(order);
    final now = DateTime.now().toUtc().toIso8601String();

    await db.transaction((txn) async {
      final existing = await txn.query(
        MilkDatabaseService.pendingOrderSubmissionsTable,
        columns: ['order_payload'],
        where: 'order_id = ?',
        whereArgs: [order.id],
        limit: 1,
      );

      if (existing.isNotEmpty) {
        if (existing.first['order_payload'] != payload) {
          throw StateError('A different pending order already uses this ID.');
        }

        return;
      }

      final otherPending = await txn.query(
        MilkDatabaseService.pendingOrderSubmissionsTable,
        columns: ['order_id'],
        limit: 1,
      );

      if (otherPending.isNotEmpty) {
        throw StateError(
          'Resolve the existing pending order '
          'before preparing another.',
        );
      }

      await txn.insert(MilkDatabaseService.pendingOrderSubmissionsTable, {
        'order_id': order.id,
        'created_at': order.createdAt.toUtc().toIso8601String(),
        'order_payload': payload,
        'submission_state': prepared,
        'updated_at': now,
      }, conflictAlgorithm: ConflictAlgorithm.abort);
    });
  }

  // ==========================================
  // GET PENDING ORDER
  // ==========================================

  /// Retrieves the currently unresolved prepared order.
  Future<CustomerOrder?> getPendingOrder() async {
    final db = await MilkDatabaseService.instance.database;

    final rows = await db.query(
      MilkDatabaseService.pendingOrderSubmissionsTable,
      columns: ['order_payload'],
      orderBy: 'created_at ASC',
      limit: 1,
    );

    if (rows.isEmpty) {
      return null;
    }

    return _decodeOrder(rows.first['order_payload'] as String);
  }

  // ==========================================
  // GET SUBMISSION STATE
  // ==========================================

  /// Returns the persisted submission state.
  Future<String?> getSubmissionState(String orderId) async {
    final db = await MilkDatabaseService.instance.database;

    final rows = await db.query(
      MilkDatabaseService.pendingOrderSubmissionsTable,
      columns: ['submission_state'],
      where: 'order_id = ?',
      whereArgs: [orderId],
      limit: 1,
    );

    if (rows.isEmpty) {
      return null;
    }

    return rows.first['submission_state'] as String;
  }

  // ==========================================
  // MARK UNCERTAIN
  // ==========================================

  /// Marks an unresolved submission as uncertain.
  Future<void> markUncertain(String orderId) async {
    final db = await MilkDatabaseService.instance.database;

    final updated = await db.update(
      MilkDatabaseService.pendingOrderSubmissionsTable,
      {
        'submission_state': uncertain,
        'updated_at': DateTime.now().toUtc().toIso8601String(),
      },
      where: 'order_id = ?',
      whereArgs: [orderId],
    );

    if (updated != 1) {
      throw StateError('Pending order was not found.');
    }
  }

  // ==========================================
  // DELETE PENDING ORDER
  // ==========================================

  /// Removes a resolved submission record.
  ///
  /// Call only after confirming the order was saved
  /// or after an explicit, safe cancellation decision.
  ///
  /// This is a low-level method. For successful checkout,
  /// prefer completeReconciledSubmission().
  Future<void> deletePendingOrder(String orderId) async {
    final db = await MilkDatabaseService.instance.database;

    await db.delete(
      MilkDatabaseService.pendingOrderSubmissionsTable,
      where: 'order_id = ?',
      whereArgs: [orderId],
    );
  }

  // ==========================================
  // COMPLETE RECONCILED SUBMISSION (V7)
  // ==========================================

  /// Removes a pending submission only after:
  ///
  /// 1. The corresponding customer order exists.
  /// 2. Checkout reconciliation is marked completed.
  ///
  /// Both checks and the deletion occur inside
  /// one SQLite transaction.
  ///
  /// Returns:
  /// - true: A pending submission was removed.
  /// - false: No pending submission remained.
  ///
  /// Throws StateError if the order is missing or
  /// reconciliation has not been completed.
  Future<bool> completeReconciledSubmission(String orderId) async {
    if (orderId.trim().isEmpty) {
      throw ArgumentError('Order ID cannot be empty.');
    }

    final db = await MilkDatabaseService.instance.database;

    return db.transaction((txn) async {
      // Verify the order exists.
      final orderRows = await txn.query(
        MilkDatabaseService.ordersTable,
        columns: ['id'],
        where: 'id = ?',
        whereArgs: [orderId],
        limit: 1,
      );

      if (orderRows.isEmpty) {
        throw StateError(
          'Cannot complete submission: '
          'saved order not found.',
        );
      }

      // Verify checkout reconciliation is complete.
      final reconciliationRows = await txn.query(
        MilkDatabaseService.checkoutReconciliationsTable,
        columns: ['reconciliation_state'],
        where: 'order_id = ?',
        whereArgs: [orderId],
        limit: 1,
      );

      if (reconciliationRows.isEmpty ||
          reconciliationRows.first['reconciliation_state'] != 'completed') {
        throw StateError(
          'Cannot complete submission: '
          'checkout reconciliation is not completed.',
        );
      }

      // Remove the pending submission.
      final deleted = await txn.delete(
        MilkDatabaseService.pendingOrderSubmissionsTable,
        where: 'order_id = ?',
        whereArgs: [orderId],
      );

      return deleted == 1;
    });
  }
}
