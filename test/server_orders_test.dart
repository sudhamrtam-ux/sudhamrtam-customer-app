import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:sudhamrtam_customer_app/database/atomic_checkout_preparation_service.dart';
import 'package:sudhamrtam_customer_app/database/checkout_recovery_executor.dart';
import 'package:sudhamrtam_customer_app/database/milk_database_service.dart';
import 'package:sudhamrtam_customer_app/database/order_database_service.dart';
import 'package:sudhamrtam_customer_app/database/pending_order_submission_service.dart';
import 'package:sudhamrtam_customer_app/features/checkout/order_destination.dart';
import 'package:sudhamrtam_customer_app/features/checkout/order_snapshot_equivalence.dart';
import 'package:sudhamrtam_customer_app/features/checkout/order_submission_service.dart';
import 'package:sudhamrtam_customer_app/models/customer_order.dart';
import 'package:sudhamrtam_customer_app/models/order_item.dart';
import 'package:sudhamrtam_customer_app/services/order_api_client.dart';

const orderId = '0123456789abcdef0123456789abcdef';

CustomerOrder serverOrder({String? addressId = 'home_1'}) => CustomerOrder(
  id: orderId,
  createdAt: DateTime.utc(2026, 11, 7, 9, 55, 0, 123),
  items: const [
    OrderItem(
      productId: 'cow_milk',
      productName: 'Cow Milk',
      unit: '1 L',
      quantity: 2,
      unitPrice: 90,
    ),
    OrderItem(
      productId: 'curd',
      productName: 'Curd',
      unit: '1 kg',
      quantity: 1,
      unitPrice: 120,
    ),
  ],
  fulfillmentMethod: FulfillmentMethod.delivery,
  paymentMethod: OrderPaymentMethod.cashOnDelivery,
  deliveryAddress: 'Flat 1, Hyderabad, Telangana, 500090',
  recipientName: 'Asha',
  recipientPhone: '9876543210',
  addressId: addressId,
  notes: 'Ring the bell',
);

/// Stand-in for the server's order endpoints.
class FakeOrderServer {
  final Map<String, String> orders = {}; // id -> request body
  final List<String> calls = [];
  bool offline = false;
  bool dropResponse = false; // the server saves, the reply is lost
  http.Response? next;

  Future<http.Response> handle(http.Request request) async {
    calls.add('${request.method} ${request.url.path}');
    if (offline) throw const SocketException('offline');

    final override = next;
    if (override != null) {
      next = null;
      return override;
    }

    final id = request.url.pathSegments.last;
    if (request.method == 'GET') {
      return orders.containsKey(id)
          ? http.Response('{"order":{}}', 200)
          : http.Response('{"error":"NOT_FOUND"}', 404);
    }

    final existing = orders[id];
    if (existing != null && existing != request.body) {
      return http.Response(
        '{"error":"ORDER_ID_CONFLICT","message":"Different order"}',
        409,
      );
    }
    final created = existing == null;
    orders[id] = request.body;
    if (dropResponse) {
      dropResponse = false;
      throw const SocketException('connection reset');
    }
    return http.Response('{"order":{}}', created ? 201 : 200);
  }
}

void main() {
  late FakeOrderServer server;
  late OrderApiClient api;

  setUp(() {
    server = FakeOrderServer();
    api = OrderApiClient(
      baseUrl: 'http://api.test',
      token: () => 'tok',
      httpClient: MockClient(server.handle),
    );
  });

  group('OrderApiClient', () {
    test('sends the order snapshot in the server format', () {
      expect(OrderApiClient.requestBody(serverOrder()), {
        'client_created_at': '2026-11-07T09:55:00.123Z',
        'fulfillment': 'delivery',
        'payment_method': 'cash_on_delivery',
        'address_id': 'home_1',
        'recipient_name': 'Asha',
        'recipient_phone': '9876543210',
        'notes': 'Ring the bell',
        'items': [
          {'product_id': 'cow_milk', 'quantity': 2, 'unit_price_paise': 9000},
          {'product_id': 'curd', 'quantity': 1, 'unit_price_paise': 12000},
        ],
      });
    });

    test('combo lines go to the server as combos', () {
      final order = CustomerOrder(
        id: orderId,
        createdAt: DateTime.utc(2026, 11, 7, 9, 55),
        items: const [
          OrderItem(
            productId: 'curd',
            productName: 'Curd',
            unit: '1 kg',
            quantity: 1,
            unitPrice: 120,
          ),
          OrderItem(
            productId: 'combo__diwali_combo_1',
            productName: 'Diwali Delight',
            unit: 'Combo, save ₹21.00 each',
            quantity: 2,
            unitPrice: 189,
          ),
        ],
        fulfillmentMethod: FulfillmentMethod.delivery,
        paymentMethod: OrderPaymentMethod.cashOnDelivery,
        deliveryAddress: 'Flat 1, Hyderabad, Telangana, 500090',
        recipientName: 'Asha',
        recipientPhone: '9876543210',
        addressId: 'home_1',
      );
      final body = OrderApiClient.requestBody(order);
      expect(body['items'], [
        {'product_id': 'curd', 'quantity': 1, 'unit_price_paise': 12000},
      ]);
      expect(body['combos'], [
        {'combo_id': 'diwali_combo_1', 'quantity': 2, 'price_paise': 18900},
      ]);
      expect(
        const OrderRejectedException('COMBO_CHANGED', 'x').isComboChange,
        isTrue,
      );
      expect(
        const OrderRejectedException('COMBO_LIMIT', 'x').isComboChange,
        isTrue,
      );
      expect(
        const OrderRejectedException('PRICE_CHANGED', 'x').isComboChange,
        isFalse,
      );
    });

    test('converts rupees to whole paise without rounding errors', () {
      expect(OrderApiClient.toPaise(0.29), 29);
      expect(OrderApiClient.toPaise(880), 88000);
      expect(OrderApiClient.toPaise(19.99), 1999);
    });

    test('a refused order is a rejection, not a retryable error', () async {
      server.next = http.Response(
        jsonEncode({
          'error': 'PRICE_CHANGED',
          'message': 'Some prices have changed.',
        }),
        409,
      );

      await expectLater(
        api.placeOrder(serverOrder()),
        throwsA(
          isA<OrderRejectedException>()
              .having((e) => e.isPriceChange, 'isPriceChange', isTrue)
              .having((e) => e.message, 'message', 'Some prices have changed.'),
        ),
      );
    });

    test('no connection and server errors are retryable', () async {
      server.offline = true;
      await expectLater(
        api.placeOrder(serverOrder()),
        throwsA(isA<OrderApiException>()),
      );

      server.offline = false;
      server.next = http.Response('oops', 503);
      await expectLater(
        api.placeOrder(serverOrder()),
        throwsA(isA<OrderApiException>()),
      );
    });

    test(
      'an order without a saved address is refused before sending',
      () async {
        await expectLater(
          api.placeOrder(serverOrder(addressId: null)),
          throwsA(isA<OrderRejectedException>()),
        );
        expect(server.calls, isEmpty);
      },
    );

    test('delivery date follows the 9 PM India-time cut-off', () {
      const rules = OrderRules(
        minimumOrderPaise: 20000,
        deliveryFeePaise: 0,
        cutoffHourIst: 21,
      );
      // 20:59 IST on 7 Nov -> 8 Nov.
      expect(
        rules.deliveryDateFor(DateTime.utc(2026, 11, 7, 15, 29)),
        DateTime(2026, 11, 8),
      );
      // 21:00 IST on 7 Nov -> 9 Nov.
      expect(
        rules.deliveryDateFor(DateTime.utc(2026, 11, 7, 15, 30)),
        DateTime(2026, 11, 9),
      );
      // 00:30 IST on 8 Nov (still 7 Nov in UTC) -> 9 Nov.
      expect(
        rules.deliveryDateFor(DateTime.utc(2026, 11, 7, 19, 0)),
        DateTime(2026, 11, 9),
      );
    });
  });

  group('with the phone database', () {
    late Directory directory;
    final databaseService = MilkDatabaseService.instance;

    setUpAll(sqfliteFfiInit);

    setUp(() async {
      directory = await Directory.systemTemp.createTemp('sudhamrtam_srv_');
      databaseService.configureForTesting(
        factory: databaseFactoryFfi,
        databasePath: '${directory.path}${Platform.pathSeparator}srv.db',
      );
      OrderDestination.server = api;
    });

    tearDown(() async {
      OrderDestination.server = null;
      await databaseService.close();
      databaseService.resetTestingConfiguration();
      await directory.delete(recursive: true);
    });

    Future<CustomerOrder?> phoneOrder() =>
        OrderDatabaseService.instance.getOrderById(orderId);

    test(
      'the order is saved on the phone only after the server took it',
      () async {
        server.offline = true;
        final submission = OrderSubmissionService();

        await expectLater(
          submission.submit(serverOrder()),
          throwsA(isA<OrderApiException>()),
        );
        expect(await phoneOrder(), isNull);

        server.offline = false;
        await submission.retryPendingOrder();

        expect(server.orders.keys, [orderId]);
        final saved = await phoneOrder();
        expect(OrderSnapshotEquivalence.matches(serverOrder(), saved!), isTrue);
        expect(saved.addressId, 'home_1');
      },
    );

    test(
      'a lost reply is retried with the same order, never a second',
      () async {
        server.dropResponse = true;
        final submission = OrderSubmissionService();

        await expectLater(
          submission.submit(serverOrder()),
          throwsA(isA<OrderApiException>()),
        );
        expect(server.orders, hasLength(1)); // the server has it

        await submission.retryPendingOrder();

        expect(server.orders, hasLength(1));
        expect(
          server.calls.where((c) => c.startsWith('PUT')),
          hasLength(2), // the same PUT, sent twice
        );
        expect(await phoneOrder(), isNotNull);
      },
    );

    group('cancelling an unfinished order', () {
      final executor = CheckoutRecoveryExecutor.instance;

      setUp(() async {
        final db = await databaseService.database;
        // The cart must hold exactly what the order holds.
        await db.insert(MilkDatabaseService.cartItemsTable, {
          'product_id': 'cow_milk',
          'quantity': 2,
        });
        await db.insert(MilkDatabaseService.cartItemsTable, {
          'product_id': 'curd',
          'quantity': 1,
        });
        await AtomicCheckoutPreparationService.instance.prepareCheckout(
          serverOrder(),
        );
      });

      Future<bool> stillPending() async =>
          await PendingOrderSubmissionService.instance.getPendingOrder() !=
          null;

      test('is allowed when the server never received it', () async {
        final result = await executor.cancelAwaitingSubmission(orderId);

        expect(result.canContinueNormalStartup, isTrue);
        expect(await stillPending(), isFalse);
        expect(await phoneOrder(), isNull);
        expect(server.calls, ['GET /v1/orders/$orderId']);
      });

      test('keeps the order when the server already has it', () async {
        server.orders[orderId] = jsonEncode(
          OrderApiClient.requestBody(serverOrder()),
        );

        final result = await executor.cancelAwaitingSubmission(orderId);

        expect(result.message, contains('already received this order'));
        expect(await phoneOrder(), isNotNull);
        expect(await stillPending(), isFalse);
      });

      test('cancels nothing when the server cannot be asked', () async {
        server.offline = true;

        final result = await executor.cancelAwaitingSubmission(orderId);

        expect(
          result.status,
          CheckoutRecoveryExecutionStatus.awaitingSubmission,
        );
        expect(result.message, contains('was not cancelled'));
        expect(await stillPending(), isTrue);
      });
    });
  });

  group('order model', () {
    test('orders without an address ID serialize exactly as before v11', () {
      final map = serverOrder(addressId: null).toMap();
      expect(map.containsKey('address_id'), isFalse);
    });

    test('the address ID is part of the order snapshot', () {
      expect(
        OrderSnapshotEquivalence.matches(
          serverOrder(),
          serverOrder(addressId: 'other'),
        ),
        isFalse,
      );
    });
  });
}
