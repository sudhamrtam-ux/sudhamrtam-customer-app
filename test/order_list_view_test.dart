import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:sudhamrtam_customer_app/app/sudhamrtam_app.dart';
import 'package:sudhamrtam_customer_app/database/milk_database_service.dart';
import 'package:sudhamrtam_customer_app/database/order_database_service.dart';
import 'package:sudhamrtam_customer_app/features/orders/order_history_screen.dart';
import 'package:sudhamrtam_customer_app/models/customer_order.dart';
import 'package:sudhamrtam_customer_app/models/order_item.dart';
import 'package:sudhamrtam_customer_app/models/product.dart';
import 'package:sudhamrtam_customer_app/services/order_api_client.dart';
import 'package:sudhamrtam_customer_app/services/support_api_client.dart';

/// My Orders as cards: a header (placed, total, number), where the order
/// is, the items with photos and "Buy it again". Prices are SAMPLE data.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final database = MilkDatabaseService.instance;
  late Directory directory;

  const milk = Product(
    id: 'buffalo_milk',
    name: 'Buffalo Milk',
    category: 'Fresh Dairy',
    description: 'SAMPLE',
    price: 90,
    unit: '1 L',
    icon: Icons.local_drink_outlined,
  );

  CustomerOrder order(
    String id,
    DateTime at,
    List<OrderItem> items, {
    String? deliveryDate,
  }) => CustomerOrder(
    id: id,
    createdAt: at,
    items: items,
    fulfillmentMethod: FulfillmentMethod.delivery,
    paymentMethod: OrderPaymentMethod.cashOnDelivery,
    deliveryAddress: 'SAMPLE address',
    deliveryDate: deliveryDate,
  );

  OrderItem item(String id, String name, {int quantity = 1}) => OrderItem(
    productId: id,
    productName: name,
    unit: '1 L',
    quantity: quantity,
    unitPrice: 90,
  );

  setUpAll(() async {
    sqfliteFfiInit();
    directory = await Directory.systemTemp.createTemp('sudhamrtam_orders_');
    database.configureForTesting(
      factory: databaseFactoryFfi,
      databasePath: '${directory.path}${Platform.pathSeparator}orders.db',
    );
    await sudhamrtamCart.initialize();
    final orders = OrderDatabaseService.instance;
    await orders.saveOrder(
      order('aaaa0000aaaa0000aaaa0000aaaa0001', DateTime(2026, 11, 18, 10), [
        item('buffalo_milk', 'Buffalo Milk', quantity: 2),
      ], deliveryDate: '2026-12-06'),
    );
    await orders.saveOrder(
      order('aaaa0000aaaa0000aaaa0000aaaa0002', DateTime(2026, 10, 26, 10), [
        item('cow_milk', 'Cow Milk'),
        item('curd', 'Curd'),
        item('paneer', 'Paneer'),
        item('cow_ghee', 'Cow Ghee'),
      ]),
    );
    await orders.updateOrderStatus(
      'aaaa0000aaaa0000aaaa0000aaaa0002',
      OrderStatus.delivered,
    );
  });

  // The cart saves finished in the tests (settle); waiting here would
  // wait on the test clock.
  tearDownAll(() async {
    await database.close();
    database.resetTestingConfiguration();
    await directory.delete(recursive: true);
  });

  /// Lets the database (real clock) and the screen (test clock) catch up.
  Future<void> settle(WidgetTester tester) async {
    for (var i = 0; i < 20; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 10)),
      );
      await tester.pump();
    }
  }

  /// Opens My Orders and waits for it to load: the phone's orders
  /// (SQLite), then the server's statuses, which are saved back and may
  /// reload the list. Waits until the spinner is gone and [until] (what
  /// the test expects once loading is done) is shown, at most 5 s of
  /// real time, so a busy machine (the whole suite in parallel) cannot
  /// make the test look too early.
  Future<void> open(
    WidgetTester tester, {
    OrderApiClient? api,
    SupportApiClient? support,
    Finder? until,
  }) async {
    tester.view.physicalSize = const Size(1080, 4000);
    tester.view.devicePixelRatio = 2.5;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        home: OrderHistoryScreen(
          api: api,
          support: support,
          productLookup: (id) => id == milk.id ? milk : null,
          clock: () => DateTime(2026, 11, 26, 9),
        ),
      ),
    );
    bool loaded() =>
        find.byType(CircularProgressIndicator).evaluate().isEmpty &&
        (until == null || until.evaluate().isNotEmpty);
    for (var i = 0; i < 500 && (i < 20 || !loaded()); i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 10)),
      );
      await tester.pump();
    }
  }

  testWidgets('cards show date, total, status and the items', (tester) async {
    await open(tester);

    expect(find.text('2 orders placed'), findsOneWidget);
    expect(find.text('18 November 2026'), findsOneWidget);
    expect(find.text('₹180.00'), findsOneWidget);
    expect(find.text('Arriving 6 December'), findsOneWidget);
    expect(find.text('Delivered'), findsOneWidget);
    // Three items shown, the fourth in the details.
    expect(find.text('+ 1 more item'), findsOneWidget);
    expect(find.text('Cow Ghee'), findsNothing);
    final photo = tester.widget<Image>(
      find.descendant(
        of: find.byKey(const Key('order-photo-buffalo_milk')),
        matching: find.byType(Image),
      ),
    );
    expect(
      (photo.image as AssetImage).assetName,
      'assets/images/products/buffalo_milk.jpg',
    );
  });

  testWidgets('filter and search', (tester) async {
    await open(tester);

    await tester.tap(find.byKey(const Key('orders-open')));
    await tester.pump();
    expect(find.text('1 order of 2 shown'), findsOneWidget);
    expect(find.text('Delivered'), findsNothing);

    await tester.tap(find.byKey(const Key('orders-all')));
    await tester.enterText(find.byKey(const Key('order-search')), 'paneer');
    await tester.pump();
    expect(find.text('Paneer'), findsOneWidget);
    expect(find.text('Arriving 6 December'), findsNothing);
  });

  testWidgets('period filter: last 15 days, last 3 months', (tester) async {
    await open(tester);
    expect(find.text('2 orders placed'), findsOneWidget);

    // 26 Nov: the order of 18 Nov is in the last 15 days, 26 Oct is not.
    await tester.tap(find.byKey(const Key('period-filter')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('period-days15')));
    await tester.pumpAndSettle();
    expect(find.text('1 order of 2 shown'), findsOneWidget);
    expect(
      tester.widget<Text>(find.byKey(const Key('period-label'))).data,
      'Last 15 days',
    );

    await tester.tap(find.byKey(const Key('period-filter')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('period-months3')));
    await tester.pumpAndSettle();
    expect(find.text('2 orders placed'), findsOneWidget);

    await tester.tap(find.byKey(const Key('period-filter')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('period-days7')));
    await tester.pumpAndSettle();
    expect(find.text('0 orders of 2 shown'), findsOneWidget);
    expect(find.textContaining('Try another period'), findsOneWidget);
  });

  testWidgets('on a tablet the buttons stand beside the items', (tester) async {
    await open(tester);
    // A tablet in portrait: 1200 px at 2 = 600 wide (the HONOR Pad).
    tester.view.physicalSize = const Size(1200, 4000);
    tester.view.devicePixelRatio = 2;
    await tester.pump();

    expect(find.text('DELIVER TO'), findsNWidgets(2));
    final help = find.byKey(const Key('help-aaaa0000aaaa0000aaaa0000aaaa0001'));
    final buy = find.byKey(const Key('buy-again-buffalo_milk'));
    expect(help, findsOneWidget);
    // Beside, not below: the help button is right of the item, at its
    // height.
    expect(tester.getTopLeft(help).dx, greaterThan(tester.getTopRight(buy).dx));
    expect(tester.getTopLeft(help).dy, lessThan(tester.getBottomLeft(buy).dy));
    expect(tester.takeException(), isNull);
  });

  testWidgets('Buy it again puts one in the cart', (tester) async {
    await open(tester);

    await tester.tap(find.byKey(const Key('buy-again-buffalo_milk')));
    await tester.pump();
    // The cart's save, on the real clock.
    await settle(tester);
    expect(sudhamrtamCart.quantityFor('buffalo_milk'), 1);
    expect(find.text('Buffalo Milk (1 L) added to your cart.'), findsOneWidget);

    // A product no longer in the shop.
    await tester.tap(find.byKey(const Key('buy-again-curd')));
    await tester.pump();
    expect(find.text('Curd is not available right now.'), findsOneWidget);
    sudhamrtamCart.clearCart();
    await settle(tester);
  });

  testWidgets('says when the latest statuses cannot be read', (tester) async {
    await open(
      tester,
      api: OrderApiClient(
        baseUrl: 'http://api.test',
        token: () => 'tok',
        httpClient: MockClient(
          (_) async => throw const SocketException('offline'),
        ),
      ),
      until: find.byKey(const Key('orders-status-problem')),
    );
    expect(find.byKey(const Key('orders-status-problem')), findsOneWidget);
    expect(find.textContaining('No internet connection'), findsOneWidget);
    // The phone's statuses are still shown.
    expect(find.text('Arriving 6 December'), findsOneWidget);
  });

  testWidgets('an order with a help conversation says so', (tester) async {
    final support = SupportApiClient(
      baseUrl: 'https://api.test',
      token: () => 'tok',
      httpClient: MockClient(
        (_) async => http.Response(
          jsonEncode({
            'queries': [
              {
                'id': 'q_help_000001',
                'ref': 'Q-1009',
                'topic': 'order',
                'message': 'Late',
                'created_at': '2026-11-19T05:00:00.000Z',
                'handled_at': null,
                'reply': 'On its way',
                'order_id': 'aaaa0000aaaa0000aaaa0000aaaa0001',
                'order_ref': 'SUD0000001',
                'last_message_at': '2026-11-19T06:00:00.000Z',
                'last_from': 'staff',
                'unread': true,
              },
            ],
          }),
          200,
        ),
      ),
    );
    await open(
      tester,
      support: support,
      until: find.text('Open help conversation'),
    );
    await settle(tester);

    expect(
      find.text('Help request Q-1009  ·  New reply', findRichText: true),
      findsOneWidget,
    );
    expect(find.text('Open help conversation'), findsOneWidget);
    // The other order has none yet.
    expect(find.text('Get help with this order'), findsOneWidget);
  });

  // Last: it changes the saved statuses.
  testWidgets('Cancel order: unpaid orders the server allows (2026-11-25)', (
    tester,
  ) async {
    var status = 'pending';
    final calls = <String>[];
    Map<String, Object?> json(String n, {required bool cancellable}) => {
      'id': 'aaaa0000aaaa0000aaaa0000aaaa000$n',
      'order_ref': 'SUD000000$n',
      'status': n == '1' ? status : 'pending',
      'payment_method': 'cash_on_delivery',
      'payment_status': 'due_on_delivery',
      'can_cancel': cancellable && status == 'pending',
    };
    final api = OrderApiClient(
      baseUrl: 'http://api.test',
      token: () => 'tok',
      httpClient: MockClient((request) async {
        calls.add('${request.method} ${request.url.path}');
        if (request.method == 'POST') {
          status = 'cancelled';
          return http.Response(
            jsonEncode({'order': json('1', cancellable: true)}),
            200,
          );
        }
        return http.Response(
          jsonEncode({
            'orders': [
              json('1', cancellable: true),
              json('2', cancellable: false),
            ],
          }),
          200,
        );
      }),
    );
    const one = 'aaaa0000aaaa0000aaaa0000aaaa0001';
    await open(
      tester,
      api: api,
      until: find.byKey(const Key('cancel-order-$one')),
    );
    await settle(tester);
    // Only where the server says so.
    expect(
      find.byKey(const Key('cancel-order-aaaa0000aaaa0000aaaa0000aaaa0002')),
      findsNothing,
    );

    await tester.ensureVisible(find.byKey(const Key('cancel-order-$one')));
    await tester.tap(find.byKey(const Key('cancel-order-$one')));
    await tester.pumpAndSettle();
    expect(find.text('Cancel this order?'), findsOneWidget);
    await tester.tap(find.byKey(const Key('cancel-order-yes')));
    for (var i = 0; i < 20 && find.text('Cancelled').evaluate().isEmpty; i++) {
      await settle(tester);
    }
    expect(calls, contains('POST /v1/orders/$one/cancel'));
    expect(find.text('Cancelled'), findsOneWidget);
    expect(find.byKey(const Key('cancel-order-$one')), findsNothing);
  });

  testWidgets("the server's Cancelled and Not delivered are shown and kept", (
    tester,
  ) async {
    Map<String, Object?> json(String id, String ref, String status) => {
      'id': id,
      'order_ref': ref,
      'status': status,
      'payment_method': 'cash_on_delivery',
      'payment_status': 'due_on_delivery',
    };
    final api = OrderApiClient(
      baseUrl: 'http://api.test',
      token: () => 'tok',
      httpClient: MockClient(
        (_) async => http.Response(
          jsonEncode({
            'orders': [
              json(
                'aaaa0000aaaa0000aaaa0000aaaa0001',
                'SUD0000001',
                'cancelled',
              ),
              json(
                'aaaa0000aaaa0000aaaa0000aaaa0002',
                'SUD0000002',
                'not_delivered',
              ),
            ],
          }),
          200,
        ),
      ),
    );
    await open(tester, api: api, until: find.text('Not delivered'));
    await settle(tester);

    expect(find.text('Cancelled'), findsOneWidget);
    expect(find.text('Not delivered'), findsOneWidget);
    expect(find.text('Arriving 6 December'), findsNothing);
    expect(find.byKey(const Key('orders-status-problem')), findsNothing);
    // Neither is waiting for delivery any more.
    await tester.tap(find.byKey(const Key('orders-open')));
    await tester.pump();
    expect(find.text('0 orders of 2 shown'), findsOneWidget);

    // Cancelled is kept on the phone, for the details page and the home
    // card; Not delivered only comes from the server.
    Future<Map<String, OrderStatus>> saved() async => {
      for (final o in (await tester.runAsync(
        () => OrderDatabaseService.instance.getAllOrders(),
      ))!)
        o.id.substring(31): o.status,
    };
    // The save runs in the background: wait for it (slow when every
    // test file runs at once).
    for (
      var i = 0;
      i < 20 && (await saved())['1'] != OrderStatus.cancelled;
      i++
    ) {
      await settle(tester);
    }
    expect(await saved(), {
      '1': OrderStatus.cancelled,
      '2': OrderStatus.delivered,
    });
  });
}
