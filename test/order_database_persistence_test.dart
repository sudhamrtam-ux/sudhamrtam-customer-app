import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:sudhamrtam_customer_app/database/milk_database_service.dart';
import 'package:sudhamrtam_customer_app/database/order_database_service.dart';
import 'package:sudhamrtam_customer_app/models/customer_order.dart';
import 'package:sudhamrtam_customer_app/models/order_item.dart';

// ==========================================
// TEST ORDER FACTORY
// ==========================================

CustomerOrder createTestOrder({required String id, List<OrderItem>? items}) {
  return CustomerOrder(
    id: id,
    createdAt: DateTime.utc(2026, 11, 5, 8, 0),
    items:
        items ??
        [
          const OrderItem(
            productId: 'buffalo_milk',
            productName: 'Buffalo Milk',
            unit: '1 L',
            quantity: 2,
            unitPrice: 100,
          ),
          const OrderItem(
            productId: 'cow_milk',
            productName: 'Cow Milk',
            unit: '1 L',
            quantity: 1,
            unitPrice: 80,
          ),
        ],
    fulfillmentMethod: FulfillmentMethod.delivery,
    paymentMethod: OrderPaymentMethod.cashOnDelivery,
    deliveryAddress: 'Kukatpally, Hyderabad',
    notes: 'Please call before delivery.',
  );
}

// ==========================================
// SQLITE TESTS
// ==========================================

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  sqfliteFfiInit();

  final databaseService = MilkDatabaseService.instance;
  final orderService = OrderDatabaseService.instance;

  late Directory testDirectory;

  setUpAll(() async {
    testDirectory = await Directory.systemTemp.createTemp(
      'sudhamrtam_order_persistence_',
    );

    final databasePath =
        '${testDirectory.path}${Platform.pathSeparator}orders_test.db';

    databaseService.configureForTesting(
      factory: databaseFactoryFfi,
      databasePath: databasePath,
    );

    // Open the isolated test database.
    await databaseService.database;
  });

  tearDownAll(() async {
    await databaseService.close();
    databaseService.resetTestingConfiguration();
    await testDirectory.delete(recursive: true);
  });

  group('Sudhamrtam SQLite Order Persistence', () {
    test('Saves and retrieves an order with product snapshots', () async {
      final original = createTestOrder(id: 'ORDER-TEST-001');

      await orderService.saveOrder(original);

      final saved = await orderService.getOrderById(original.id);

      expect(saved, isNotNull);
      expect(saved!.id, original.id);
      expect(saved.items.length, 2);
      expect(saved.totalQuantity, 3);
      expect(saved.subtotal, 280.0);
      expect(saved.deliveryAddress, 'Kukatpally, Hyderabad');
      expect(saved.notes, 'Please call before delivery.');

      expect(saved.items[0].productName, 'Buffalo Milk');
      expect(saved.items[0].quantity, 2);
      expect(saved.items[0].unitPrice, 100.0);

      expect(saved.items[1].productName, 'Cow Milk');
      expect(saved.items[1].quantity, 1);
      expect(saved.items[1].unitPrice, 80.0);
    });

    test('Rejects duplicate order IDs', () async {
      final duplicate = createTestOrder(id: 'ORDER-TEST-001');

      await expectLater(
        orderService.saveOrder(duplicate),
        throwsA(isA<Exception>()),
      );

      expect(await orderService.getOrderCount(), 1);
    });

    test('Rejects unconfigured product prices', () async {
      final invalid = createTestOrder(
        id: 'ORDER-TEST-002',
        items: [
          const OrderItem(
            productId: 'unpriced_milk',
            productName: 'Unpriced Milk',
            unit: '1 L',
            quantity: 1,
            unitPrice: 0,
          ),
        ],
      );

      await expectLater(orderService.saveOrder(invalid), throwsStateError);

      expect(await orderService.getOrderById(invalid.id), isNull);
    });

    test('Rolls back the entire order if an item fails', () async {
      final invalid = createTestOrder(
        id: 'ORDER-TEST-003',
        items: [
          const OrderItem(
            productId: 'valid_milk',
            productName: 'Valid Milk',
            unit: '1 L',
            quantity: 1,
            unitPrice: 100,
          ),
          const OrderItem(
            productId: 'invalid_quantity',
            productName: 'Invalid Quantity',
            unit: '1 L',
            quantity: 101,
            unitPrice: 50,
          ),
        ],
      );

      await expectLater(
        orderService.saveOrder(invalid),
        throwsA(isA<Exception>()),
      );

      // The order header and first item must also roll back.
      expect(await orderService.getOrderById(invalid.id), isNull);

      final db = await databaseService.database;

      final rows = await db.query(
        MilkDatabaseService.orderItemsTable,
        where: 'order_id = ?',
        whereArgs: [invalid.id],
      );

      expect(rows, isEmpty);
    });

    test('Retrieves saved orders newest first', () async {
      final second = createTestOrder(id: 'ORDER-TEST-004');

      await orderService.saveOrder(second);

      final orders = await orderService.getAllOrders();

      expect(orders.length, 2);
      expect(orders.map((order) => order.id), contains(second.id));
    });

    test('Updates the status of an existing order', () async {
      final updated = await orderService.updateOrderStatus(
        'ORDER-TEST-001',
        OrderStatus.confirmed,
      );

      expect(updated, isTrue);

      final saved = await orderService.getOrderById('ORDER-TEST-001');

      expect(saved!.status, OrderStatus.confirmed);
    });

    test('Returns false when updating an unknown order', () async {
      final updated = await orderService.updateOrderStatus(
        'UNKNOWN-ORDER',
        OrderStatus.confirmed,
      );

      expect(updated, isFalse);
    });
  });
}
