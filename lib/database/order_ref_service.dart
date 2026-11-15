import 'package:sqflite/sqflite.dart';

import 'milk_database_service.dart';

/// The server's short order numbers ("ORD-1001"), by order ID. Shown
/// instead of the long order ID, so an order is easy to share and
/// discuss. Orders not on the server (test orders) have none.
class OrderRefService {
  OrderRefService._();

  static final OrderRefService instance = OrderRefService._();

  Future<Database> get _db => MilkDatabaseService.instance.database;

  Future<void> save(String orderId, String orderRef) async {
    await (await _db).insert(MilkDatabaseService.orderRefsTable, {
      'order_id': orderId,
      'order_ref': orderRef,
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<void> saveAll(Map<String, String> refs) async {
    if (refs.isEmpty) return;
    final db = await _db;
    await db.transaction((tx) async {
      final batch = tx.batch();
      refs.forEach(
        (id, ref) => batch.insert(MilkDatabaseService.orderRefsTable, {
          'order_id': id,
          'order_ref': ref,
        }, conflictAlgorithm: ConflictAlgorithm.replace),
      );
      await batch.commit(noResult: true);
    });
  }

  Future<String?> refFor(String orderId) async {
    final rows = await (await _db).query(
      MilkDatabaseService.orderRefsTable,
      columns: ['order_ref'],
      where: 'order_id = ?',
      whereArgs: [orderId],
    );
    return rows.isEmpty ? null : rows.first['order_ref'] as String;
  }

  Future<Map<String, String>> all() async {
    final rows = await (await _db).query(MilkDatabaseService.orderRefsTable);
    return {
      for (final r in rows) r['order_id'] as String: r['order_ref'] as String,
    };
  }
}
