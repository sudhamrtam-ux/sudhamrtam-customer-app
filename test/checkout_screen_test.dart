import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:sudhamrtam_customer_app/app/sudhamrtam_app.dart';
import 'package:sudhamrtam_customer_app/database/milk_database_service.dart';
import 'package:sudhamrtam_customer_app/features/checkout/checkout_order_session.dart';
import 'package:sudhamrtam_customer_app/features/checkout/checkout_screen.dart';
import 'package:sudhamrtam_customer_app/features/checkout/durable_checkout_coordinator.dart';
import 'package:sudhamrtam_customer_app/features/orders/order_details_screen.dart';
import 'package:sudhamrtam_customer_app/models/cart_manager.dart';
import 'package:sudhamrtam_customer_app/models/customer_order.dart';
import 'package:sudhamrtam_customer_app/models/product.dart';

/// Priced test product, independent of the provisional catalog.
const testProduct = Product(
  id: 'test_milk',
  name: 'Test Milk',
  category: 'Fresh Dairy',
  description: 'Widget test product.',
  price: 50,
  unit: '1 L',
  icon: Icons.local_drink_outlined,
);

/// Records submissions and optionally simulates failures.
///
/// Mirrors the real coordinator's lock behavior: a failure
/// after preparation keeps the recovery lock; success
/// releases it.
class FakeCheckoutCoordinator extends DurableCheckoutCoordinator {
  final List<CustomerOrder> received = [];
  int failuresRemaining = 0;

  @override
  Future<CustomerOrder> submitPreparedOrder({
    required CustomerOrder order,
    required CartManager cart,
  }) async {
    received.add(order);

    if (failuresRemaining > 0) {
      failuresRemaining--;
      cart.beginCheckoutRecoveryLock();
      throw StateError('Simulated lost confirmation');
    }

    cart.endCheckoutRecoveryLock();
    return order;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final databaseService = MilkDatabaseService.instance;
  late Directory directory;
  late FakeCheckoutCoordinator coordinator;

  setUpAll(() async {
    sqfliteFfiInit();

    directory = await Directory.systemTemp.createTemp(
      'sudhamrtam_checkout_screen_',
    );

    databaseService.configureForTesting(
      factory: databaseFactoryFfi,
      databasePath: '${directory.path}${Platform.pathSeparator}checkout.db',
    );

    await sudhamrtamCart.initialize();
  });

  tearDownAll(() async {
    await sudhamrtamCart.waitForPendingSaves();
    await databaseService.close();
    databaseService.resetTestingConfiguration();
    await directory.delete(recursive: true);
  });

  setUp(() async {
    sudhamrtamCart.endCheckoutRecoveryLock();
    sudhamrtamCart.clearCart();
    expect(sudhamrtamCart.addProduct(testProduct, quantity: 2), isTrue);
    await sudhamrtamCart.waitForPendingSaves();

    coordinator = FakeCheckoutCoordinator();
  });

  Future<void> pumpCheckout(
    WidgetTester tester, {
    bool enableTestOrders = true,
  }) async {
    // Tall surface so the whole checkout list is built
    // without scrolling.
    tester.view.physicalSize = const Size(1200, 6000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      MaterialApp(
        home: CheckoutScreen(
          enableTestOrders: enableTestOrders,
          coordinator: coordinator,
          orderSession: CheckoutOrderSession(loadPendingOrder: () async => null),
        ),
      ),
    );
    await tester.pump();
  }

  Finder button(String label) => find.ancestor(
    of: find.text(label),
    matching: find.byWidgetPredicate((widget) => widget is ButtonStyleButton),
  );

  bool isEnabled(WidgetTester tester, String label) =>
      tester.widget<ButtonStyleButton>(button(label)).onPressed != null;

  Future<void> choosePickup(WidgetTester tester) async {
    await tester.tap(find.text('Store Pickup'));
    await tester.pump();
  }

  testWidgets('Release builds keep order placement disabled', (tester) async {
    await pumpCheckout(tester, enableTestOrders: false);
    await choosePickup(tester);

    expect(isEnabled(tester, 'Place Order — Coming Soon'), isFalse);
    expect(find.text('Place Test Order'), findsNothing);
  });

  testWidgets('Pickup with Cash on Delivery places one test order', (
    tester,
  ) async {
    await pumpCheckout(tester);
    await choosePickup(tester);

    expect(isEnabled(tester, 'Place Test Order'), isTrue);

    await tester.tap(button('Place Test Order'));
    await tester.pumpAndSettle();

    expect(coordinator.received, hasLength(1));

    final order = coordinator.received.single;
    expect(order.fulfillmentMethod, FulfillmentMethod.pickup);
    expect(order.paymentMethod, OrderPaymentMethod.cashOnDelivery);
    expect(order.items.single.productId, testProduct.id);
    expect(order.items.single.quantity, 2);

    expect(find.byType(OrderDetailsScreen), findsOneWidget);
  });

  testWidgets('Online payment disables test order placement', (tester) async {
    await pumpCheckout(tester);
    await choosePickup(tester);

    await tester.tap(find.text('Online Payment'));
    await tester.pump();

    expect(isEnabled(tester, 'Place Test Order'), isFalse);
    expect(find.textContaining('Online payment is not available'), findsOne);
  });

  testWidgets('Failed checkout retries with the same order ID', (tester) async {
    coordinator.failuresRemaining = 1;

    await pumpCheckout(tester);
    await choosePickup(tester);

    await tester.tap(button('Place Test Order'));
    await tester.pumpAndSettle();

    expect(find.text('Order could not be completed'), findsOneWidget);
    expect(find.textContaining('Your cart is locked'), findsOneWidget);
    expect(sudhamrtamCart.isCheckoutRecoveryLocked, isTrue);
    expect(isEnabled(tester, 'Retry Test Order'), isTrue);

    await tester.tap(button('Retry Test Order'));
    await tester.pumpAndSettle();

    expect(coordinator.received, hasLength(2));
    expect(coordinator.received[1].id, coordinator.received[0].id);
    expect(sudhamrtamCart.isCheckoutRecoveryLocked, isFalse);
    expect(find.byType(OrderDetailsScreen), findsOneWidget);
  });

  testWidgets('Retry resubmits the original order despite later changes', (
    tester,
  ) async {
    coordinator.failuresRemaining = 1;

    await pumpCheckout(tester);
    await choosePickup(tester);

    await tester.tap(button('Place Test Order'));
    await tester.pumpAndSettle();

    // Switching to Online Payment must not block or alter
    // the retry of the original Cash on Delivery order.
    await tester.tap(find.text('Online Payment'));
    await tester.pump();

    expect(isEnabled(tester, 'Retry Test Order'), isTrue);

    await tester.tap(button('Retry Test Order'));
    await tester.pumpAndSettle();

    expect(coordinator.received, hasLength(2));
    expect(coordinator.received[1].id, coordinator.received[0].id);
    expect(
      coordinator.received[1].paymentMethod,
      OrderPaymentMethod.cashOnDelivery,
    );
  });
}
