import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:sudhamrtam_customer_app/app/sudhamrtam_app.dart';
import 'package:sudhamrtam_customer_app/database/milk_database_service.dart';
import 'package:sudhamrtam_customer_app/database/order_database_service.dart';
import 'package:sudhamrtam_customer_app/features/orders/order_history_screen.dart';
import 'package:sudhamrtam_customer_app/models/customer_order.dart';
import 'package:sudhamrtam_customer_app/models/order_item.dart';
import 'package:sudhamrtam_customer_app/models/product.dart';

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

  Future<void> open(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1080, 4000);
    tester.view.devicePixelRatio = 2.5;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        home: OrderHistoryScreen(
          productLookup: (id) => id == milk.id ? milk : null,
        ),
      ),
    );
    for (var i = 0; i < 20; i++) {
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
}
