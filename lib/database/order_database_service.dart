import 'package:sqflite/sqflite.dart';

import '../models/customer_order.dart';
import '../models/order_item.dart';
import 'milk_database_service.dart';

/// Manages local SQLite storage for customer orders.
class OrderDatabaseService {
  OrderDatabaseService._();

  static final OrderDatabaseService instance = OrderDatabaseService._();

  /// Saves an order and all its items atomically.
  ///
  /// Existing order IDs are rejected to prevent
  /// accidental overwriting of historical orders.
  Future<void> saveOrder(CustomerOrder order) async {
    if (!order.hasValidPrices) {
      throw StateError('Cannot save an order with unconfigured prices.');
    }

    final db = await MilkDatabaseService.instance.database;

    await db.transaction((txn) async {
      await txn.insert(
        MilkDatabaseService.ordersTable,
        order.toMap(),
        conflictAlgorithm: ConflictAlgorithm.abort,
      );

      for (final item in order.items) {
        await txn.insert(MilkDatabaseService.orderItemsTable, {
          'order_id': order.id,
          ...item.toMap(),
        }, conflictAlgorithm: ConflictAlgorithm.abort);
      }
    });
  }

  /// Retrieves an order and all its product snapshots.
  Future<CustomerOrder?> getOrderById(String orderId) async {
    final db = await MilkDatabaseService.instance.database;

    return db.transaction((txn) async {
      final orderRows = await txn.query(
        MilkDatabaseService.ordersTable,
        where: 'id = ?',
        whereArgs: [orderId],
        limit: 1,
      );

      if (orderRows.isEmpty) {
        return null;
      }

      final itemRows = await txn.query(
        MilkDatabaseService.orderItemsTable,
        where: 'order_id = ?',
        whereArgs: [orderId],
        orderBy: 'id ASC',
      );

      final items = itemRows.map((row) => OrderItem.fromMap(row)).toList();

      return CustomerOrder.fromMap(orderRows.first, items: items);
    });
  }

  /// Retrieves all saved orders, newest first.
  Future<List<CustomerOrder>> getAllOrders() async {
    final db = await MilkDatabaseService.instance.database;

    return db.transaction((txn) async {
      final orderRows = await txn.query(
        MilkDatabaseService.ordersTable,
        orderBy: 'created_at DESC, id DESC',
      );

      if (orderRows.isEmpty) {
        return <CustomerOrder>[];
      }

      final itemRows = await txn.query(
        MilkDatabaseService.orderItemsTable,
        orderBy: 'id ASC',
      );

      final itemsByOrderId = <String, List<OrderItem>>{};

      for (final row in itemRows) {
        final orderId = row['order_id'] as String;

        itemsByOrderId
            .putIfAbsent(orderId, () => <OrderItem>[])
            .add(OrderItem.fromMap(row));
      }

      return orderRows.map((row) {
        final orderId = row['id'] as String;

        return CustomerOrder.fromMap(
          row,
          items: itemsByOrderId[orderId] ?? <OrderItem>[],
        );
      }).toList();
    });
  }

  /// Updates only the status of an existing order.
  ///
  /// Returns false if no matching order exists.
  Future<bool> updateOrderStatus(String orderId, OrderStatus status) async {
    final db = await MilkDatabaseService.instance.database;

    final updatedRows = await db.update(
      MilkDatabaseService.ordersTable,
      {'status': status.name},
      where: 'id = ?',
      whereArgs: [orderId],
    );

    return updatedRows > 0;
  }

  /// Updates only the payment method of an existing order (an
  /// unpaid online order switched to Cash on Delivery).
  Future<bool> updatePaymentMethod(
    String orderId,
    OrderPaymentMethod method,
  ) async {
    final db = await MilkDatabaseService.instance.database;

    final updatedRows = await db.update(
      MilkDatabaseService.ordersTable,
      {'payment_method': method.name},
      where: 'id = ?',
      whereArgs: [orderId],
    );

    return updatedRows > 0;
  }

  /// Returns the number of stored customer orders.
  Future<int> getOrderCount() async {
    final db = await MilkDatabaseService.instance.database;

    final result = await db.rawQuery(
      'SELECT COUNT(*) AS total '
      'FROM ${MilkDatabaseService.ordersTable}',
    );

    return Sqflite.firstIntValue(result) ?? 0;
  }
}
