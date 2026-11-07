import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:sudhamrtam_customer_app/database/milk_database_service.dart';
import 'package:sudhamrtam_customer_app/database/order_database_service.dart';
import 'package:sudhamrtam_customer_app/features/orders/order_history_screen.dart';
import 'package:sudhamrtam_customer_app/features/payment/order_payment_status.dart';
import 'package:sudhamrtam_customer_app/features/payment/payment_launcher.dart';
import 'package:sudhamrtam_customer_app/features/payment/payment_screen.dart';
import 'package:sudhamrtam_customer_app/models/customer_order.dart';
import 'package:sudhamrtam_customer_app/models/order_item.dart';
import 'package:sudhamrtam_customer_app/services/order_api_client.dart';

const orderId = 'fedcba9876543210fedcba9876543210';

CustomerOrder onlineOrder() => CustomerOrder(
  id: orderId,
  createdAt: DateTime.utc(2026, 11, 7, 9, 55),
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
  paymentMethod: OrderPaymentMethod.online,
  deliveryAddress: 'Flat 1, Hyderabad, Telangana, 500090',
  recipientName: 'Asha',
  recipientPhone: '9876543210',
  addressId: 'home_1',
);

/// The server's payment endpoints, in memory.
class FakePaymentServer {
  String paymentMethod = 'online';
  String paymentStatus = 'awaiting_online';
  String orderStatus = 'pending';
  final calls = <String>[];

  /// Paid after this many more checks (null: never by itself).
  int? paidAfterChecks;
  http.Response? nextStart;

  Map<String, Object?> get order => {
    'id': orderId,
    'status': orderStatus,
    'payment_method': paymentMethod,
    'payment_status': paymentStatus,
    'payment_due_at': paymentStatus == 'awaiting_online'
        ? '2026-11-07T15:30:00.000Z'
        : null,
  };

  http.Response ok(Object body) => http.Response(jsonEncode(body), 200);

  Future<http.Response> handle(http.Request request) async {
    final path = request.url.path;
    calls.add('${request.method} $path');

    if (path.endsWith('/payment')) {
      final override = nextStart;
      if (override != null) {
        nextStart = null;
        return override;
      }
      return ok({
        'order_id': orderId,
        'payment_session_id': 'session_123',
        'environment': 'sandbox',
      });
    }
    if (path.endsWith('/payment/check')) {
      final after = paidAfterChecks;
      if (after != null) {
        if (after <= 1) {
          paymentStatus = 'paid_online';
          paidAfterChecks = null;
        } else {
          paidAfterChecks = after - 1;
        }
      }
      return ok({'order': order});
    }
    if (path.endsWith('/payment/cash-on-delivery')) {
      paymentMethod = 'cash_on_delivery';
      paymentStatus = 'due_on_delivery';
      return ok({'order': order});
    }
    if (request.method == 'GET' && path == '/v1/orders') {
      return ok({
        'orders': [order],
      });
    }
    if (request.method == 'GET') return ok({'order': order});
    return http.Response('{"error":"NOT_FOUND"}', 404);
  }
}

class FakeLauncher implements PaymentLauncher {
  FakeLauncher(this.result);
  PaymentLaunchResult result;
  final sessions = <PaymentSession>[];

  @override
  Future<PaymentLaunchResult> launch(PaymentSession session) async {
    sessions.add(session);
    return result;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(sqfliteFfiInit);

  late Directory directory;
  late FakePaymentServer server;
  late OrderApiClient api;

  setUp(() async {
    directory = await Directory.systemTemp.createTemp('sudhamrtam_payment_');
    MilkDatabaseService.instance.configureForTesting(
      factory: databaseFactoryFfi,
      databasePath: '${directory.path}${Platform.pathSeparator}payment.db',
    );
    await OrderDatabaseService.instance.saveOrder(onlineOrder());

    server = FakePaymentServer();
    api = OrderApiClient(
      baseUrl: 'http://api.test',
      token: () => 'tok',
      httpClient: MockClient(server.handle),
    );
  });

  tearDown(() async {
    await MilkDatabaseService.instance.close();
    MilkDatabaseService.instance.resetTestingConfiguration();
    await directory.delete(recursive: true);
  });

  group('OrderApiClient payments', () {
    test('reads whether the server offers online payment', () {
      const cod = OrderRules(
        minimumOrderPaise: 20000,
        deliveryFeePaise: 0,
        cutoffHourIst: 21,
      );
      expect(cod.offersOnlinePayment, isFalse);

      const both = OrderRules(
        minimumOrderPaise: 20000,
        deliveryFeePaise: 0,
        cutoffHourIst: 21,
        paymentMethods: ['cash_on_delivery', 'online'],
      );
      expect(both.offersOnlinePayment, isTrue);
    });

    test('starts, checks and switches a payment', () async {
      final session = await api.startPayment(orderId);
      expect(session.paymentSessionId, 'session_123');
      expect(session.isSandbox, isTrue);

      final waiting = await api.checkPayment(orderId);
      expect(waiting.isAwaitingPayment, isTrue);
      expect(waiting.paymentDueAt, DateTime.utc(2026, 11, 7, 15, 30));

      final cod = await api.switchToCashOnDelivery(orderId);
      expect(cod.isCashOnDelivery, isTrue);
      expect(server.calls, [
        'POST /v1/orders/$orderId/payment',
        'POST /v1/orders/$orderId/payment/check',
        'POST /v1/orders/$orderId/payment/cash-on-delivery',
      ]);
    });

    test('refusals keep their code; outages are retryable', () async {
      server.nextStart = http.Response(
        '{"error":"ALREADY_PAID","message":"This order is already paid."}',
        409,
      );
      await expectLater(
        api.startPayment(orderId),
        throwsA(
          isA<PaymentRejectedException>().having(
            (e) => e.isAlreadyPaid,
            'isAlreadyPaid',
            isTrue,
          ),
        ),
      );

      server.nextStart = http.Response(
        '{"error":"PAYMENT_PROVIDER_ERROR","message":"Try again."}',
        502,
      );
      await expectLater(
        api.startPayment(orderId),
        throwsA(isA<OrderApiException>()),
      );
    });
  });

  group('PaymentScreen', () {
    Future<void> pumpScreen(
      WidgetTester tester,
      PaymentLauncher launcher,
    ) async {
      tester.view.physicalSize = const Size(1080, 3000);
      tester.view.devicePixelRatio = 2;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(
        MaterialApp(
          home: PaymentScreen(
            order: onlineOrder(),
            api: api,
            launcher: launcher,
            confirmDelay: const Duration(milliseconds: 10),
          ),
        ),
      );
    }

    /// Lets HTTP and SQLite work finish (they run outside the
    /// test's fake clock) until [finder] shows up.
    Future<void> waitFor(WidgetTester tester, Finder finder) async {
      for (var i = 0; i < 100 && finder.evaluate().isEmpty; i++) {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 20)),
        );
        await tester.pump(const Duration(milliseconds: 20));
      }
      expect(finder, findsOneWidget);
    }

    testWidgets('a confirmed payment shows success', (tester) async {
      server.paidAfterChecks = 1;
      final launcher = FakeLauncher(const PaymentLaunchFinished());

      await pumpScreen(tester, launcher);
      await waitFor(tester, find.byKey(const Key('paymentPaid')));

      expect(find.text('Payment successful'), findsOneWidget);
      expect(find.byKey(const Key('sandboxBanner')), findsOneWidget);
      expect(launcher.sessions.single.paymentSessionId, 'session_123');
    });

    testWidgets('waits for Cashfree to confirm a reported success', (
      tester,
    ) async {
      server.paidAfterChecks = 3;

      await pumpScreen(tester, FakeLauncher(const PaymentLaunchFinished()));
      await waitFor(tester, find.byKey(const Key('paymentPaid')));

      expect(
        server.calls.where((c) => c.endsWith('/payment/check')),
        hasLength(3),
      );
    });

    testWidgets('the payment screen alone never marks an order paid', (
      tester,
    ) async {
      // The SDK says "success", but the server never confirms.
      await pumpScreen(tester, FakeLauncher(const PaymentLaunchFinished()));
      await waitFor(tester, find.byKey(const Key('paymentNotPaid')));

      expect(find.text('Payment not completed'), findsOneWidget);
    });

    testWidgets('a failed payment can switch to Cash on Delivery', (
      tester,
    ) async {
      await pumpScreen(
        tester,
        FakeLauncher(const PaymentLaunchFailed('Payment cancelled by user')),
      );
      await waitFor(tester, find.byKey(const Key('paymentNotPaid')));
      expect(find.textContaining('Payment cancelled by user'), findsOneWidget);
      expect(find.textContaining('or the order is cancelled'), findsOneWidget);

      await tester.tap(find.byKey(const Key('payByCash')));
      await waitFor(tester, find.byKey(const Key('paymentCod')));

      final saved = await tester.runAsync(
        () => OrderDatabaseService.instance.getOrderById(orderId),
      );
      expect(saved!.paymentMethod, OrderPaymentMethod.cashOnDelivery);
    });

    testWidgets('a failed payment can be tried again', (tester) async {
      final launcher = FakeLauncher(const PaymentLaunchFailed('Declined'));
      await pumpScreen(tester, launcher);
      await waitFor(tester, find.byKey(const Key('paymentNotPaid')));

      launcher.result = const PaymentLaunchFinished();
      server.paidAfterChecks = 1;
      await tester.tap(find.text('Try Again'));
      await waitFor(tester, find.byKey(const Key('paymentPaid')));

      expect(launcher.sessions, hasLength(2));
    });

    testWidgets('an order paid earlier shows as paid', (tester) async {
      server.nextStart = http.Response(
        '{"error":"ALREADY_PAID","message":"This order is already paid."}',
        409,
      );
      server.paymentStatus = 'paid_online';
      final launcher = FakeLauncher(const PaymentLaunchFinished());

      await pumpScreen(tester, launcher);
      await waitFor(tester, find.byKey(const Key('paymentPaid')));
      expect(launcher.sessions, isEmpty);
    });

    testWidgets('an order cancelled for non-payment says so', (tester) async {
      server.nextStart = http.Response(
        '{"error":"ORDER_CANCELLED","message":"This order was cancelled '
        'because it was not paid in time."}',
        410,
      );

      await pumpScreen(tester, FakeLauncher(const PaymentLaunchFinished()));
      await waitFor(tester, find.byKey(const Key('paymentClosed')));
      expect(find.textContaining('not paid in time'), findsOneWidget);
    });
  });

  group('OrderPaymentStatusView', () {
    Future<void> pumpView(WidgetTester tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: OrderPaymentStatusView(order: onlineOrder(), api: api),
          ),
        ),
      );
    }

    Future<void> settle(WidgetTester tester) async {
      for (var i = 0; i < 10; i++) {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 10)),
        );
        await tester.pump();
      }
    }

    testWidgets('unpaid orders offer Pay Now', (tester) async {
      await pumpView(tester);
      await settle(tester);

      expect(find.text('Payment pending'), findsOneWidget);
      expect(find.byKey(const Key('orderPayNow')), findsOneWidget);
    });

    testWidgets('paid orders show as paid', (tester) async {
      server.paymentStatus = 'paid_online';
      await pumpView(tester);
      await settle(tester);

      expect(find.text('Payment made'), findsOneWidget);
      expect(find.byKey(const Key('orderPayNow')), findsNothing);
    });
  });

  group('My Orders labels', () {
    testWidgets('show payment and delivery separately', (tester) async {
      server.paymentStatus = 'paid_online';
      await tester.pumpWidget(MaterialApp(home: OrderHistoryScreen(api: api)));
      for (var i = 0; i < 20; i++) {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 10)),
        );
        await tester.pump();
      }

      expect(find.text('Payment made'), findsOneWidget);
      expect(find.text('Delivery pending'), findsOneWidget);
    });

    testWidgets('an unpaid online order shows payment pending', (tester) async {
      await tester.pumpWidget(MaterialApp(home: OrderHistoryScreen(api: api)));
      for (var i = 0; i < 20; i++) {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 10)),
        );
        await tester.pump();
      }

      expect(find.text('Payment pending'), findsOneWidget);
    });

    testWidgets('offline, the payment method is shown instead', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: OrderHistoryScreen(
            api: OrderApiClient(
              baseUrl: 'http://api.test',
              token: () => 'tok',
              httpClient: MockClient(
                (_) async => throw const SocketException('offline'),
              ),
            ),
          ),
        ),
      );
      for (var i = 0; i < 20; i++) {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 10)),
        );
        await tester.pump();
      }

      expect(find.text('Online payment'), findsOneWidget);
      expect(find.text('Delivery pending'), findsOneWidget);
    });
  });
}
