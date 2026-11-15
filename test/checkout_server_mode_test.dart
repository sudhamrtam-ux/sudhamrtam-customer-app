import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:sudhamrtam_customer_app/app/sudhamrtam_app.dart';
import 'package:sudhamrtam_customer_app/database/customer_address_database_service.dart';
import 'package:sudhamrtam_customer_app/database/customer_profile_database_service.dart';
import 'package:sudhamrtam_customer_app/database/milk_database_service.dart';
import 'package:sudhamrtam_customer_app/features/checkout/checkout_order_session.dart';
import 'package:sudhamrtam_customer_app/features/checkout/checkout_screen.dart';
import 'package:sudhamrtam_customer_app/features/checkout/durable_checkout_coordinator.dart';
import 'package:sudhamrtam_customer_app/models/cart_manager.dart';
import 'package:sudhamrtam_customer_app/models/customer_address.dart';
import 'package:sudhamrtam_customer_app/models/customer_order.dart';
import 'package:sudhamrtam_customer_app/models/product.dart';
import 'package:sudhamrtam_customer_app/services/account_sync_service.dart';
import 'package:sudhamrtam_customer_app/services/order_api_client.dart';
import 'package:sudhamrtam_customer_app/services/phone_auth_service.dart';

const testProduct = Product(
  id: 'test_milk',
  name: 'Test Milk',
  category: 'Fresh Dairy',
  description: 'Widget test product.',
  price: 50,
  unit: '1 L',
  icon: Icons.local_drink_outlined,
);

const rules = OrderRules(
  minimumOrderPaise: 20000,
  deliveryFeePaise: 0,
  cutoffHourIst: 21,
);

class FakeAuth implements PhoneAuthGateway {
  AuthUser? user;

  @override
  AuthUser? get currentUser => user;

  @override
  Stream<AuthUser?> authStateChanges() => const Stream.empty();

  @override
  Future<PhoneCodeRequest> requestCode(String p, {int? resendToken}) =>
      throw UnimplementedError();

  @override
  Future<AuthUser> confirmCode(String v, String c) =>
      throw UnimplementedError();

  @override
  Future<void> signOut() async => user = null;
}

/// Records orders; can refuse the next one like the server would.
class FakeCoordinator extends DurableCheckoutCoordinator {
  final List<CustomerOrder> received = [];
  Object? failNext;

  @override
  Future<CustomerOrder> submitPreparedOrder({
    required CustomerOrder order,
    required CartManager cart,
  }) async {
    received.add(order);
    final failure = failNext;
    if (failure != null) {
      failNext = null;
      cart.beginCheckoutRecoveryLock();
      throw failure;
    }
    cart.endCheckoutRecoveryLock();
    return order;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final databaseService = MilkDatabaseService.instance;
  late Directory directory;
  late FakeCoordinator coordinator;
  late FakeAuth auth;

  setUpAll(() async {
    sqfliteFfiInit();
    directory = await Directory.systemTemp.createTemp('sudhamrtam_srv_ui_');
    databaseService.configureForTesting(
      factory: databaseFactoryFfi,
      databasePath: '${directory.path}${Platform.pathSeparator}ui.db',
    );
    await sudhamrtamCart.initialize();
  });

  tearDownAll(() async {
    await sudhamrtamCart.waitForPendingSaves();
    await databaseService.close();
    databaseService.resetTestingConfiguration();
    await directory.delete(recursive: true);
  });

  Future<void> setUpAddress({required String? areaId}) async {
    await CustomerProfileDatabaseService.instance.saveSyncedProfile(
      customerId: AccountSyncService.localCustomerId,
      fullName: 'Asha',
    );
    final now = DateTime(2026, 11, 7);
    await CustomerAddressDatabaseService.instance.replaceAllAddresses(
      AccountSyncService.localCustomerId,
      [
        CustomerAddress(
          id: 'home_1',
          customerId: AccountSyncService.localCustomerId,
          areaId: areaId,
          label: 'Home',
          recipientName: 'Asha',
          phoneNumber: '9876543210',
          addressLine1: 'Flat 1',
          landmark: '',
          city: 'Hyderabad',
          state: 'Telangana',
          postalCode: '500090',
          isDefault: true,
          createdAt: now,
          updatedAt: now,
        ),
      ],
    );
  }

  Future<void> setCart(int quantity) async {
    sudhamrtamCart.endCheckoutRecoveryLock();
    sudhamrtamCart.clearCart();
    expect(sudhamrtamCart.addProduct(testProduct, quantity: quantity), isTrue);
    await sudhamrtamCart.waitForPendingSaves();
  }

  setUp(() async {
    coordinator = FakeCoordinator();
    auth = FakeAuth()
      ..user = const AuthUser(uid: 'c1', phoneNumber: '+919999900001');
    await setCart(4); // ₹200
  });

  Future<void> pump(
    WidgetTester tester, {
    OrderRules serverRules = rules,
  }) async {
    tester.view.physicalSize = const Size(1200, 6000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      MaterialApp(
        home: CheckoutScreen(
          enableTestOrders: false, // like a release build
          sendsToServer: true,
          coordinator: coordinator,
          auth: auth,
          loadRules: () async => serverRules,
          orderSession: CheckoutOrderSession(
            loadPendingOrder: () async => null,
          ),
        ),
      ),
    );
    // Addresses load from SQLite on a real thread.
    for (var i = 0; i < 20; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 20)),
      );
      await tester.pump();
    }
  }

  Finder button(String label) => find.ancestor(
    of: find.text(label),
    matching: find.byWidgetPredicate((w) => w is ButtonStyleButton),
  );

  bool isEnabled(WidgetTester tester, String label) =>
      tester.widget<ButtonStyleButton>(button(label)).onPressed != null;

  testWidgets('a signed-in customer can place a real order', (tester) async {
    await tester.runAsync(() => setUpAddress(areaId: 'nizampet'));
    await pump(tester);

    expect(find.text('Store Pickup'), findsNothing);
    expect(find.text('Online Payment'), findsNothing);
    expect(find.text('Cash on Delivery'), findsWidgets);
    expect(find.byKey(const Key('serverRequirements')), findsNothing);
    expect(isEnabled(tester, 'Place Order'), isTrue);

    await tester.tap(button('Place Order'));
    await tester.pump();

    final order = coordinator.received.single;
    expect(order.addressId, 'home_1');
    expect(order.fulfillmentMethod, FulfillmentMethod.delivery);
    expect(order.paymentMethod, OrderPaymentMethod.cashOnDelivery);
  });

  testWidgets('the customer chooses the delivery date (morning)', (
    tester,
  ) async {
    await tester.runAsync(() => setUpAddress(areaId: 'nizampet'));
    const monthly = OrderRules(
      minimumOrderPaise: 20000,
      deliveryFeePaise: 0,
      cutoffHourIst: 21,
      maxDaysAhead: 30,
    );
    await pump(tester, serverRules: monthly);

    expect(find.text('Delivery Date'), findsOneWidget);
    final dates = monthly.deliveryDatesFor(DateTime.now());
    expect(find.text('Earliest delivery'), findsOneWidget);

    // A calendar pops up; typed here, as the month shown depends on
    // today.
    final pick = dates[20];
    await tester.ensureVisible(find.byKey(const Key('delivery-date-pick')));
    await tester.tap(find.byKey(const Key('delivery-date-pick')));
    await tester.pumpAndSettle();
    expect(find.text('Delivery date (morning)'), findsOneWidget);
    await tester.tap(find.byIcon(Icons.edit_outlined));
    await tester.pumpAndSettle();
    String two(int n) => n.toString().padLeft(2, '0');
    await tester.enterText(
      find.byType(TextField).last,
      '${two(pick.month)}/${two(pick.day)}/${pick.year}',
    );
    await tester.tap(find.text('Choose'));
    await tester.pumpAndSettle();
    expect(find.text('Your chosen date'), findsOneWidget);

    await tester.tap(button('Place Order'));
    await tester.pump();
    final iso =
        '${pick.year}-${pick.month.toString().padLeft(2, '0')}-'
        '${pick.day.toString().padLeft(2, '0')}';
    expect(coordinator.received.single.deliveryDate, iso);
  });

  testWidgets('without a choice the earliest date is used', (tester) async {
    await tester.runAsync(() => setUpAddress(areaId: 'nizampet'));
    await pump(tester);
    // An older server: no date to choose.
    expect(find.text('Delivery Date'), findsNothing);
    await tester.tap(button('Place Order'));
    await tester.pump();
    expect(coordinator.received.single.deliveryDate, isNull);
  });

  testWidgets('online payment is offered when the server takes it', (
    tester,
  ) async {
    await tester.runAsync(() => setUpAddress(areaId: 'nizampet'));
    await pump(
      tester,
      serverRules: const OrderRules(
        minimumOrderPaise: 20000,
        deliveryFeePaise: 0,
        cutoffHourIst: 21,
        paymentMethods: ['cash_on_delivery', 'online'],
      ),
    );

    expect(find.text('Pay Online'), findsOneWidget);
    await tester.tap(find.text('Pay Online'));
    await tester.pump();

    expect(isEnabled(tester, 'Place Order & Pay'), isTrue);
    await tester.tap(button('Place Order & Pay'));
    await tester.pump();

    final order = coordinator.received.single;
    expect(order.paymentMethod, OrderPaymentMethod.online);
    expect(order.addressId, 'home_1');
  });

  testWidgets('online payment is hidden when the server does not take it', (
    tester,
  ) async {
    await tester.runAsync(() => setUpAddress(areaId: 'nizampet'));
    await pump(tester);

    expect(find.text('Pay Online'), findsNothing);
  });

  testWidgets('signing in is required', (tester) async {
    auth.user = null;
    await tester.runAsync(() => setUpAddress(areaId: 'nizampet'));
    await pump(tester);

    expect(
      find.text('Sign in with your mobile number to place your order.'),
      findsOneWidget,
    );
    expect(isEnabled(tester, 'Place Order'), isFalse);
  });

  testWidgets('the address needs a delivery area', (tester) async {
    await tester.runAsync(() => setUpAddress(areaId: null));
    await pump(tester);

    expect(find.text('Edit address'), findsOneWidget);
    expect(isEnabled(tester, 'Place Order'), isFalse);
  });

  testWidgets('orders below ₹200 cannot be placed', (tester) async {
    await tester.runAsync(() async {
      await setUpAddress(areaId: 'nizampet');
      await setCart(3); // ₹150
    });
    await pump(tester);

    expect(
      find.textContaining('The minimum order for delivery is ₹200. Add ₹50.00'),
      findsOneWidget,
    );
    expect(isEnabled(tester, 'Place Order'), isFalse);
  });

  testWidgets('a refused order can be cancelled, keeping the cart', (
    tester,
  ) async {
    await tester.runAsync(() => setUpAddress(areaId: 'nizampet'));
    coordinator.failNext = const OrderRejectedException(
      'PRODUCT_UNAVAILABLE',
      'Some products are not available right now.',
    );
    await pump(tester);

    await tester.tap(button('Place Order'));
    await tester.pump();

    expect(
      find.text('Some products are not available right now.'),
      findsOneWidget,
    );
    expect(find.byKey(const Key('cancelRejectedOrder')), findsOneWidget);
    expect(sudhamrtamCart.isCheckoutRecoveryLocked, isTrue);
  });

  testWidgets('a connection problem offers a retry of the same order', (
    tester,
  ) async {
    await tester.runAsync(() => setUpAddress(areaId: 'nizampet'));
    coordinator.failNext = const OrderApiException(
      'No internet connection. Your order is kept; please try again.',
    );
    await pump(tester);

    await tester.tap(button('Place Order'));
    await tester.pump();

    expect(find.byKey(const Key('cancelRejectedOrder')), findsNothing);
    expect(isEnabled(tester, 'Retry Order'), isTrue);

    await tester.tap(button('Retry Order'));
    await tester.pump();

    expect(coordinator.received, hasLength(2));
    expect(coordinator.received[1].id, coordinator.received[0].id);
  });
}
