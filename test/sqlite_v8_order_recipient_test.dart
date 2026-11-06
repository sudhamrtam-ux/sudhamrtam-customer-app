import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:sudhamrtam_customer_app/database/milk_database_service.dart';
import 'package:sudhamrtam_customer_app/database/order_database_service.dart';
import 'package:sudhamrtam_customer_app/database/pending_order_submission_service.dart';
import 'package:sudhamrtam_customer_app/models/customer_order.dart';
import 'package:sudhamrtam_customer_app/models/order_item.dart';

CustomerOrder deliveryOrder(
  String id, {
  String? recipientName = 'Lakshmi Devi',
  String? recipientPhone = '9876543210',
}) {
  return CustomerOrder(
    id: id,
    createdAt: DateTime.utc(2026, 11, 6, 7),
    items: const [
      OrderItem(
        productId: 'cow_milk',
        productName: 'Cow Milk',
        unit: '1 L',
        quantity: 2,
        unitPrice: 50,
      ),
    ],
    fulfillmentMethod: FulfillmentMethod.delivery,
    paymentMethod: OrderPaymentMethod.cashOnDelivery,
    deliveryAddress: 'Kukatpally, Hyderabad',
    recipientName: recipientName,
    recipientPhone: recipientPhone,
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(sqfliteFfiInit);

  final service = MilkDatabaseService.instance;

  late Directory directory;
  late String dbPath;

  setUp(() async {
    directory = await Directory.systemTemp.createTemp('sudhamrtam_v8_');
    dbPath = '${directory.path}${Platform.pathSeparator}v8.db';
  });

  tearDown(() async {
    await service.close();
    service.resetTestingConfiguration();
    await directory.delete(recursive: true);
  });

  test('Fresh v8 install stores and restores the delivery recipient', () async {
    service.configureForTesting(
      factory: databaseFactoryFfi,
      databasePath: dbPath,
    );

    final db = await service.database;

    final version = await db.rawQuery('PRAGMA user_version');
    expect(version.first.values.first, 8);

    final columns = (await db.rawQuery('PRAGMA table_info(customer_orders)'))
        .map((column) => column['name'] as String)
        .toSet();

    expect(columns, containsAll(['recipient_name', 'recipient_phone']));

    await OrderDatabaseService.instance.saveOrder(deliveryOrder('with-name'));
    await OrderDatabaseService.instance.saveOrder(
      deliveryOrder('legacy', recipientName: null, recipientPhone: null),
    );

    final saved = await OrderDatabaseService.instance.getOrderById('with-name');
    expect(saved?.recipientName, 'Lakshmi Devi');
    expect(saved?.recipientPhone, '9876543210');

    final legacy = await OrderDatabaseService.instance.getOrderById('legacy');
    expect(legacy?.recipientName, isNull);
    expect(legacy?.recipientPhone, isNull);
  });

  test('v7 to v8 migration keeps existing orders', () async {
    // Build a minimal v7 database containing one older
    // delivery order without recipient columns.
    final v7 = await databaseFactoryFfi.openDatabase(
      dbPath,
      options: OpenDatabaseOptions(
        version: 7,
        onCreate: (db, _) async {
          await db.execute('''
            CREATE TABLE customer_orders (
              id TEXT PRIMARY KEY,
              created_at TEXT NOT NULL,
              fulfillment_method TEXT NOT NULL,
              payment_method TEXT NOT NULL,
              status TEXT NOT NULL DEFAULT 'pending',
              delivery_address TEXT,
              notes TEXT,
              subtotal REAL NOT NULL
            )
          ''');
          await db.insert('customer_orders', {
            'id': 'old-order',
            'created_at': '2026-11-01T07:00:00.000Z',
            'fulfillment_method': 'delivery',
            'payment_method': 'cashOnDelivery',
            'status': 'delivered',
            'delivery_address': 'Kukatpally, Hyderabad',
            'notes': null,
            'subtotal': 100.0,
          });
        },
      ),
    );
    await v7.close();

    service.configureForTesting(
      factory: databaseFactoryFfi,
      databasePath: dbPath,
    );

    final db = await service.database;

    final version = await db.rawQuery('PRAGMA user_version');
    expect(version.first.values.first, 8);

    final rows = await db.query('customer_orders');
    expect(rows, hasLength(1));
    expect(rows.first['id'], 'old-order');
    expect(rows.first['delivery_address'], 'Kukatpally, Hyderabad');
    expect(rows.first['recipient_name'], isNull);
    expect(rows.first['recipient_phone'], isNull);

    final integrity = await db.rawQuery('PRAGMA integrity_check');
    expect(integrity.first.values.first, 'ok');
  });

  test('Pending submission payload preserves the recipient', () async {
    service.configureForTesting(
      factory: databaseFactoryFfi,
      databasePath: dbPath,
    );

    await PendingOrderSubmissionService.instance.savePreparedOrder(
      deliveryOrder('pending-order'),
    );

    final pending = await PendingOrderSubmissionService.instance
        .getPendingOrder();

    expect(pending?.recipientName, 'Lakshmi Devi');
    expect(pending?.recipientPhone, '9876543210');
  });

  test('Orders without a recipient serialize exactly as before v8', () {
    // Durable pending payloads are compared byte-for-byte,
    // so a checkout prepared by the v7 app must still match
    // after upgrading.
    final map = deliveryOrder(
      'legacy',
      recipientName: null,
      recipientPhone: null,
    ).toMap();

    expect(map.containsKey('recipient_name'), isFalse);
    expect(map.containsKey('recipient_phone'), isFalse);

    final restored = CustomerOrder.fromMap(
      Map<String, Object?>.from(jsonDecode(jsonEncode(map)) as Map),
      items: deliveryOrder('legacy').items,
    );

    expect(restored.recipientName, isNull);
  });
}
