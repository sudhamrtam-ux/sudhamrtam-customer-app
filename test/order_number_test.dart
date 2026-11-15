import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:sudhamrtam_customer_app/database/milk_database_service.dart';
import 'package:sudhamrtam_customer_app/database/order_database_service.dart';
import 'package:sudhamrtam_customer_app/database/order_ref_service.dart';
import 'package:sudhamrtam_customer_app/features/checkout/order_destination.dart';
import 'package:sudhamrtam_customer_app/features/orders/order_number.dart';
import 'package:sudhamrtam_customer_app/models/customer_order.dart';
import 'package:sudhamrtam_customer_app/models/order_item.dart';
import 'package:sudhamrtam_customer_app/services/order_api_client.dart';

final _order = CustomerOrder(
  id: '0123456789abcdef0123456789abcdef',
  createdAt: DateTime.utc(2026, 11, 7, 10),
  items: const [
    OrderItem(
      productId: 'curd',
      productName: 'Curd',
      unit: '1 kg',
      quantity: 2,
      unitPrice: 120,
    ),
  ],
  fulfillmentMethod: FulfillmentMethod.delivery,
  paymentMethod: OrderPaymentMethod.cashOnDelivery,
  deliveryAddress: 'Flat 1, Hyderabad',
  recipientName: 'Asha',
  recipientPhone: '9876543210',
  addressId: 'home_1',
);

OrderApiClient _api(Map<String, Object?> order) => OrderApiClient(
  baseUrl: 'http://api.test',
  token: () => 'tok',
  httpClient: MockClient(
    (_) async => http.Response(jsonEncode({'order': order}), 201),
  ),
);

void main() {
  setUpAll(sqfliteFfiInit);

  test('the title shows the short number when known', () {
    expect(orderTitle('abc', 'ORD-1001'), 'Order ORD-1001');
    expect(orderTitle('abc', null), 'Order #abc');
  });

  test('placing an order returns its short number', () async {
    expect(
      await _api({'id': _order.id, 'order_ref': 'ORD-1001'}).placeOrder(_order),
      'ORD-1001',
    );
    // An older server: no number, still placed.
    expect(await _api({'id': _order.id}).placeOrder(_order), isNull);
    expect(
      OrderPaymentStatus.fromOrderJson({
        'payment_method': 'cash_on_delivery',
        'status': 'pending',
        'order_ref': 'ORD-1002',
      }).orderRef,
      'ORD-1002',
    );
  });

  group('phone database', () {
    late Directory directory;
    late String path;

    setUp(() async {
      directory = await Directory.systemTemp.createTemp('sudhamrtam_ref_');
      path = '${directory.path}${Platform.pathSeparator}ref.db';
      MilkDatabaseService.instance.configureForTesting(
        factory: databaseFactoryFfi,
        databasePath: path,
      );
    });

    tearDown(() async {
      OrderDestination.server = null;
      await MilkDatabaseService.instance.close();
      MilkDatabaseService.instance.resetTestingConfiguration();
      await directory.delete(recursive: true);
    });

    test('a placed order keeps its number on the phone', () async {
      OrderDestination.server = _api({
        'id': _order.id,
        'order_ref': 'ORD-1001',
      });
      await OrderDestination.save(_order);
      expect(
        await OrderDatabaseService.instance.getOrderById(_order.id),
        isNotNull,
      );
      expect(await OrderRefService.instance.refFor(_order.id), 'ORD-1001');

      await OrderRefService.instance.saveAll({'other_order': 'ORD-1002'});
      expect(await OrderRefService.instance.all(), {
        _order.id: 'ORD-1001',
        'other_order': 'ORD-1002',
      });
    });

    test('v20 to v21 keeps orders and adds the numbers table', () async {
      await OrderDatabaseService.instance.saveOrder(_order);
      await MilkDatabaseService.instance.close();
      final old = await databaseFactoryFfi.openDatabase(path);
      await old.execute('DROP TABLE order_refs');
      await old.setVersion(20);
      await old.close();

      final db = await MilkDatabaseService.instance.database;
      expect(await db.getVersion(), 21);
      expect(
        await OrderDatabaseService.instance.getOrderById(_order.id),
        isNotNull,
      );
      expect(await OrderRefService.instance.refFor(_order.id), isNull);
      await OrderRefService.instance.save(_order.id, 'ORD-1003');
      expect(await OrderRefService.instance.refFor(_order.id), 'ORD-1003');
    });
  });
}
