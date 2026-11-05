import 'package:sqflite/sqflite.dart';

import 'milk_database_service.dart';

/// Handles persistent SQLite storage for the shopping cart.
class CartDatabaseService {
  CartDatabaseService._();

  static final CartDatabaseService instance = CartDatabaseService._();

  /// Loads all saved cart items.
  Future<Map<String, int>> loadCart() async {
    final db = await MilkDatabaseService.instance.database;

    final rows = await db.query(
      MilkDatabaseService.cartItemsTable,
      columns: ['product_id', 'quantity'],
      orderBy: 'product_id ASC',
    );

    return {
      for (final row in rows)
        row['product_id'] as String: row['quantity'] as int,
    };
  }

  /// Saves or updates one cart item.
  Future<void> saveItem(String productId, int quantity) async {
    if (productId.isEmpty || quantity < 1 || quantity > 100) {
      throw ArgumentError('Invalid cart item');
    }

    final db = await MilkDatabaseService.instance.database;

    await db.insert(MilkDatabaseService.cartItemsTable, {
      'product_id': productId,
      'quantity': quantity,
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  /// Removes one cart item.
  Future<void> deleteItem(String productId) async {
    final db = await MilkDatabaseService.instance.database;

    await db.delete(
      MilkDatabaseService.cartItemsTable,
      where: 'product_id = ?',
      whereArgs: [productId],
    );
  }

  /// Removes all cart items.
  Future<void> clearCart() async {
    final db = await MilkDatabaseService.instance.database;

    await db.delete(MilkDatabaseService.cartItemsTable);
  }

  /// Atomically replaces the entire saved cart snapshot.
  ///
  /// All operations succeed together or are rolled back.
  /// An invalid snapshot is rejected before modifying SQLite.
  Future<void> saveCartSnapshot(Map<String, int> snapshot) async {
    for (final entry in snapshot.entries) {
      if (entry.key.trim().isEmpty || entry.value < 1 || entry.value > 100) {
        throw ArgumentError('Invalid cart snapshot item: ${entry.key}');
      }
    }

    final db = await MilkDatabaseService.instance.database;

    await db.transaction((txn) async {
      await txn.delete(MilkDatabaseService.cartItemsTable);

      for (final entry in snapshot.entries) {
        await txn.insert(MilkDatabaseService.cartItemsTable, {
          'product_id': entry.key,
          'quantity': entry.value,
        });
      }
    });
  }
}
