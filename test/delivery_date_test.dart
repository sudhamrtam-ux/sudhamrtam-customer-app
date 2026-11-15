import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:sudhamrtam_customer_app/database/milk_database_service.dart';
import 'package:sudhamrtam_customer_app/database/order_database_service.dart';
import 'package:sudhamrtam_customer_app/features/checkout/order_snapshot_equivalence.dart';
import 'package:sudhamrtam_customer_app/models/customer_order.dart';
import 'package:sudhamrtam_customer_app/models/order_item.dart';
import 'package:sudhamrtam_customer_app/services/order_api_client.dart';

CustomerOrder order({String? deliveryDate}) => CustomerOrder(
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
  deliveryDate: deliveryDate,
);

void main() {
  setUpAll(sqfliteFfiInit);

  const rules = OrderRules(
    minimumOrderPaise: 20000,
    deliveryFeePaise: 0,
    cutoffHourIst: 21,
    maxDaysAhead: 7,
  );

  test('the dates a customer may choose: the earliest up to a week ahead', () {
    // 15:30 India time on Saturday 7 November.
    final day = rules.deliveryDatesFor(DateTime.utc(2026, 11, 7, 10));
    expect(day.first, DateTime(2026, 11, 8));
    expect(day.last, DateTime(2026, 11, 14));
    expect(day, hasLength(7));
    // After the 9 PM cut-off the earliest is the day after tomorrow.
    final night = rules.deliveryDatesFor(DateTime.utc(2026, 11, 7, 15, 31));
    expect(night.first, DateTime(2026, 11, 9));
    expect(night.last, DateTime(2026, 11, 14));
    // A server without the setting: only the earliest.
    const old = OrderRules(
      minimumOrderPaise: 20000,
      deliveryFeePaise: 0,
      cutoffHourIst: 21,
    );
    expect(old.deliveryDatesFor(DateTime.utc(2026, 11, 7, 10)), [
      DateTime(2026, 11, 8),
    ]);
  });

  test('the chosen date is sent and kept only when chosen', () {
    expect(order().toMap().containsKey('delivery_date'), isFalse);
    expect(
      OrderApiClient.requestBody(order()).containsKey('delivery_date'),
      isFalse,
    );
    final chosen = order(deliveryDate: '2026-11-12');
    expect(chosen.toMap()['delivery_date'], '2026-11-12');
    expect(OrderApiClient.requestBody(chosen)['delivery_date'], '2026-11-12');
    expect(
      CustomerOrder.fromMap(chosen.toMap(), items: chosen.items).deliveryDate,
      '2026-11-12',
    );
    expect(
      chosen.copyWith(status: OrderStatus.delivered).deliveryDate,
      '2026-11-12',
    );
    // A different date is a different order.
    expect(OrderSnapshotEquivalence.matches(chosen, order()), isFalse);
  });

  group('phone database', () {
    late Directory directory;

    setUp(() async {
      directory = await Directory.systemTemp.createTemp('sudhamrtam_date_');
      MilkDatabaseService.instance.configureForTesting(
        factory: databaseFactoryFfi,
        databasePath: '${directory.path}${Platform.pathSeparator}date.db',
      );
    });

    tearDown(() async {
      await MilkDatabaseService.instance.close();
      MilkDatabaseService.instance.resetTestingConfiguration();
      await directory.delete(recursive: true);
    });

    test('saves and reads the chosen date', () async {
      await OrderDatabaseService.instance.saveOrder(
        order(deliveryDate: '2026-11-12'),
      );
      final saved = await OrderDatabaseService.instance.getOrderById(
        order().id,
      );
      expect(saved!.deliveryDate, '2026-11-12');
    });

    test('v19 to v20 keeps orders and adds an empty date', () async {
      // A v20 database made into a v19 one with an order in it.
      await MilkDatabaseService.instance.database;
      await MilkDatabaseService.instance.close();
      final path = '${directory.path}${Platform.pathSeparator}date.db';
      final old = await databaseFactoryFfi.openDatabase(path);
      await old.execute(
        'ALTER TABLE customer_orders DROP COLUMN delivery_date',
      );
      await old.insert('customer_orders', order().toMap());
      await old.insert('customer_order_items', {
        'order_id': order().id,
        ...order().items.single.toMap(),
      });
      await old.setVersion(19);
      await old.close();

      final db = await MilkDatabaseService.instance.database;
      expect(await db.getVersion(), MilkDatabaseService.databaseVersion);
      final kept = await OrderDatabaseService.instance.getOrderById(order().id);
      expect(kept!.recipientName, 'Asha');
      expect(kept.deliveryDate, isNull);
    });
  });
}
