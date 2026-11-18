import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:sudhamrtam_customer_app/database/milk_database_service.dart';
import 'package:sudhamrtam_customer_app/features/home/home_screen.dart';
import 'package:sudhamrtam_customer_app/models/cart_manager.dart';
import 'package:sudhamrtam_customer_app/models/catalog_repository.dart';
import 'package:sudhamrtam_customer_app/services/order_api_client.dart';

const rules = OrderRules(
  minimumOrderPaise: 20000,
  deliveryFeePaise: 0,
  cutoffHourIst: 21,
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(sqfliteFfiInit);

  final databaseService = MilkDatabaseService.instance;
  late Directory directory;
  late CatalogRepository catalog;
  late CartManager cart;

  setUp(() async {
    directory = await Directory.systemTemp.createTemp('sudhamrtam_home_');
    databaseService.configureForTesting(
      factory: databaseFactoryFfi,
      databasePath: '${directory.path}${Platform.pathSeparator}home.db',
    );
    await databaseService.database;
  });

  tearDown(() async {
    await databaseService.close();
    databaseService.resetTestingConfiguration();
    await directory.delete(recursive: true);
  });

  Future<void> pumpHome(
    WidgetTester tester, {
    void Function(String?)? onOpenShop,
    VoidCallback? onOpenMilkPlan,
    OrderRulesLoader? loadRules,
    OffersLoader? loadOffers,
    DateTime? now,
    String? name,
  }) async {
    tester.view.physicalSize = const Size(1080, 5000);
    tester.view.devicePixelRatio = 2;
    addTearDown(tester.view.reset);

    catalog = CatalogRepository();
    cart = CartManager();
    await tester.runAsync(catalog.initialize);
    await tester.runAsync(cart.initialize);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: HomeScreen(
            catalog: catalog,
            cart: cart,
            onOpenShop: onOpenShop,
            onOpenMilkPlan: onOpenMilkPlan,
            loadRules: loadRules,
            loadOffers: loadOffers,
            clock: now == null ? null : () => now,
            loadCustomerName: () async => name,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  /// Cart saves run on SQLite's real thread: alternate real waiting
  /// with frames until every queued save has finished.
  Future<void> drainSaves(WidgetTester tester) async {
    var done = false;
    cart.waitForPendingSaves().then((_) => done = true);
    for (var i = 0; i < 500 && !done; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 20)),
      );
      await tester.pump();
    }
    expect(done, isTrue, reason: 'cart saves did not finish');
  }

  /// Unmounts the screen (stops its timer) and lets cart saves finish.
  Future<void> finish(WidgetTester tester) async {
    await drainSaves(tester);
    await tester.pumpWidget(const SizedBox());
  }

  testWidgets('shows the offer line when there are offers', (tester) async {
    await pumpHome(
      tester,
      loadOffers: () async => ['Fresh paneer', 'Ghee offer'],
    );
    expect(find.byKey(const Key('offer-ticker')), findsOneWidget);
    expect(find.text('Fresh paneer   •   Ghee offer'), findsOneWidget);
    // It stays above the page, which scrolls under it.
    expect(
      tester.getTopLeft(find.byKey(const Key('offer-ticker'))).dy,
      lessThan(tester.getTopLeft(find.text('Welcome to Sudhamrtam')).dy),
    );
    await finish(tester);
  });

  test('the greeting follows the time of day, with the first name', () {
    expect(
      greetingLine(DateTime(2026, 11, 17, 7), 'Asha Rani'),
      'Good morning, Asha 😊',
    );
    expect(greetingLine(DateTime(2026, 11, 17, 13), null), 'Good afternoon 😊');
    expect(greetingLine(DateTime(2026, 11, 17, 19), '  '), 'Good evening 😊');
    expect(
      greetingLine(DateTime(2026, 11, 17, 2), 'Bala'),
      'Good evening, Bala 😊',
    );
    // Initials are skipped.
    expect(
      greetingLine(DateTime(2026, 11, 17, 9), 'V Naga Raju'),
      'Good morning, Naga 😊',
    );
    expect(
      greetingLine(DateTime(2026, 11, 17, 9), 'K. Ravi'),
      'Good morning, Ravi 😊',
    );
    expect(greetingLine(DateTime(2026, 11, 17, 9), 'V'), 'Good morning, V 😊');
  });

  testWidgets('Home greets the customer by name above the welcome', (
    tester,
  ) async {
    await pumpHome(
      tester,
      loadOffers: () async => [],
      now: DateTime(2026, 11, 17, 8),
      name: 'Asha',
    );
    expect(find.text('Good morning, Asha 😊'), findsOneWidget);
    expect(
      tester.getTopLeft(find.byKey(const Key('homeGreeting'))).dy,
      lessThan(tester.getTopLeft(find.text('Welcome to Sudhamrtam')).dy),
    );
    // The milk plan badge sits in the top-right corner, beside the
    // welcome; the banner comes right after (owner, 2026-11-17).
    final badge = tester.getRect(find.byKey(const Key('accountStatus')));
    final welcome = tester.getRect(find.text('Welcome to Sudhamrtam'));
    expect(badge.left, greaterThan(welcome.right));
    expect(badge.top, lessThan(welcome.bottom));
    expect(
      tester.getTopLeft(find.byKey(const Key('homeShopNow'))).dy,
      lessThan(tester.getTopLeft(find.text('Daily Essentials')).dy),
    );
    await finish(tester);
  });

  testWidgets('no offer line without offers or when offline', (tester) async {
    await pumpHome(tester, loadOffers: () async => []);
    expect(find.byKey(const Key('offer-ticker')), findsNothing);
    await finish(tester);

    await pumpHome(tester, loadOffers: () async => throw Exception('offline'));
    expect(find.byKey(const Key('offer-ticker')), findsNothing);
    expect(find.text('Welcome to Sudhamrtam'), findsOneWidget);
    await finish(tester);
  });

  testWidgets('shortcuts open the shop, a category and the milk plan', (
    tester,
  ) async {
    final opened = <String?>[];
    var milkPlanOpened = false;

    await pumpHome(
      tester,
      onOpenShop: opened.add,
      onOpenMilkPlan: () => milkPlanOpened = true,
    );

    await tester.tap(find.byKey(const Key('homeShopNow')));
    await tester.tap(find.byKey(const Key('homeCategory_Ghee')));
    await tester.tap(find.text('See all'));
    await tester.tap(find.byKey(const Key('homeMilkPlan')));

    expect(opened, [null, 'Ghee', 'Fresh Dairy']);
    expect(milkPlanOpened, isTrue);
    // Categories come from the catalog, with product counts.
    expect(find.text('Wood-Pressed Oils'), findsOneWidget);
    expect(find.text('4 products'), findsWidgets);

    await finish(tester);
  });

  testWidgets('daily essentials add to the cart and change quantity', (
    tester,
  ) async {
    await pumpHome(tester);

    final card = find.byKey(const Key('quickAdd_cow_milk'));
    await tester.tap(find.descendant(of: card, matching: find.text('ADD')));
    await tester.pump();

    expect(cart.quantityFor('cow_milk'), 1);
    expect(find.text('Cow Milk added to cart'), findsOneWidget);
    await drainSaves(tester);

    await tester.tap(
      find.descendant(of: card, matching: find.byTooltip('Add one')),
    );
    await tester.pump();
    expect(cart.quantityFor('cow_milk'), 2);
    expect(find.descendant(of: card, matching: find.text('2')), findsOneWidget);
    // Home says what is waiting in the cart (owner, 2026-11-17).
    expect(find.byKey(const Key('homeCartWaiting')), findsOneWidget);
    expect(find.text('2 items in your cart · ₹180'), findsOneWidget);
    await drainSaves(tester);

    for (var i = 0; i < 2; i++) {
      await tester.tap(
        find.descendant(of: card, matching: find.byTooltip('Remove one')),
      );
      await tester.pump();
      await drainSaves(tester);
    }
    expect(cart.quantityFor('cow_milk'), 0);
    expect(
      find.descendant(of: card, matching: find.text('ADD')),
      findsOneWidget,
    );
    // An empty cart is not mentioned.
    expect(find.byKey(const Key('homeCartWaiting')), findsNothing);

    await finish(tester);
  });

  testWidgets('before the cut-off: time left to order for tomorrow', (
    tester,
  ) async {
    await pumpHome(
      tester,
      loadRules: () async => rules,
      // 10:00 AM in India.
      now: DateTime.utc(2026, 11, 7, 4, 30),
    );

    expect(
      find.text('Order by 9 PM for delivery tomorrow morning'),
      findsOneWidget,
    );
    expect(find.text('11 h 0 min left to order'), findsOneWidget);
    expect(
      find.text('Free delivery on orders of ₹200 or more • Cash on Delivery'),
      findsOneWidget,
    );

    await finish(tester);
  });

  testWidgets('the card says online payment only when the server offers it', (
    tester,
  ) async {
    await pumpHome(
      tester,
      loadRules: () async => const OrderRules(
        minimumOrderPaise: 20000,
        deliveryFeePaise: 0,
        cutoffHourIst: 21,
        paymentMethods: ['cash_on_delivery', 'online'],
      ),
      now: DateTime.utc(2026, 11, 7, 4, 30),
    );

    expect(
      find.text(
        'Free delivery on orders of ₹200 or more • '
        'Cash on Delivery or pay online',
      ),
      findsOneWidget,
    );

    await finish(tester);
  });

  testWidgets('after the cut-off: shows the later delivery date', (
    tester,
  ) async {
    await pumpHome(
      tester,
      loadRules: () async => rules,
      // 10:00 PM in India on Saturday 7 Nov.
      now: DateTime.utc(2026, 11, 7, 16, 30),
    );

    expect(find.text('Order now for delivery on Mon, 9 Nov'), findsOneWidget);
    expect(find.text("Today's 9 PM cut-off has passed."), findsOneWidget);

    await finish(tester);
  });

  testWidgets('without a server or offline there is no delivery card', (
    tester,
  ) async {
    await pumpHome(tester);
    expect(find.byKey(const Key('homeDeliveryCard')), findsNothing);
    await finish(tester);

    await pumpHome(
      tester,
      loadRules: () async =>
          throw const OrderApiException('Could not load the order rules.'),
    );
    expect(find.byKey(const Key('homeDeliveryCard')), findsNothing);
    await finish(tester);
  });
}
