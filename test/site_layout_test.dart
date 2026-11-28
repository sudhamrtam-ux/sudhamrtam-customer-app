import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:sudhamrtam_customer_app/app/sudhamrtam_app.dart';
import 'package:sudhamrtam_customer_app/core/company.dart';
import 'package:sudhamrtam_customer_app/core/widgets/site_layout.dart';
import 'package:sudhamrtam_customer_app/database/milk_database_service.dart';
import 'package:sudhamrtam_customer_app/features/checkout/checkout_screen.dart';
import 'package:sudhamrtam_customer_app/features/shell/customer_shell.dart';
import 'package:sudhamrtam_customer_app/features/tour/app_tour.dart';
import 'package:sudhamrtam_customer_app/features/shop/product_details_screen.dart';
import 'package:sudhamrtam_customer_app/features/shop/shop_screen.dart';
import 'package:sudhamrtam_customer_app/services/order_api_client.dart';

/// The website look (2026-11-24): a wide screen gets a header, centred
/// pages and a footer; a phone keeps the app with its bottom tabs.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(sqfliteFfiInit);

  final db = MilkDatabaseService.instance;
  late Directory dir;

  setUpAll(() async {
    dir = await Directory.systemTemp.createTemp('sudhamrtam_site_');
    db.configureForTesting(
      factory: databaseFactoryFfi,
      databasePath: '${dir.path}${Platform.pathSeparator}site.db',
    );
    await db.database;
    await initializeCatalogAndCart();
  });

  tearDownAll(() async {
    await db.close();
    db.resetTestingConfiguration();
    await dir.delete(recursive: true);
  });

  Future<void> pumpShell(WidgetTester tester, Size size) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(const MaterialApp(home: CustomerShell()));
    await tester.pump();
  }

  /// Closes the pages and lets their timers finish.
  Future<void> closeShell(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(minutes: 1));
  }

  testWidgets('a computer: header, footer, no bottom tabs', (tester) async {
    final opened = <Uri>[];
    final original = openSiteLink;
    openSiteLink = (url) async {
      opened.add(url);
      return true;
    };
    addTearDown(() => openSiteLink = original);

    await pumpShell(tester, const Size(1440, 900));
    expect(find.byKey(const Key('site-shell')), findsOneWidget);
    expect(find.byType(NavigationBar), findsNothing);
    expect(find.byKey(const Key('site-cart')), findsOneWidget);

    // The footer, with the policy pages.
    final refunds = find.byKey(const Key('footer-refunds'));
    await tester.scrollUntilVisible(
      refunds,
      400,
      scrollable: find
          .descendant(
            of: find.byType(CustomScrollView),
            matching: find.byType(Scrollable),
          )
          .first,
    );
    // A shorter Home (2026-11-25): bring the whole link into view.
    await tester.ensureVisible(refunds);
    await tester.pumpAndSettle();
    await tester.tap(refunds);
    expect(opened, [Uri.parse(sudhamrtamRefundsUrl)]);

    // A footer category opens the shop on it.
    await tester.tap(find.byKey(const Key('footer-category-Ghee')));
    await tester.pumpAndSettle();
    expect(find.byType(ShopScreen), findsOneWidget);
    expect(
      tester
          .widget<ChoiceChip>(find.byKey(const Key('shopCategory_Ghee')))
          .selected,
      isTrue,
    );

    // The header's links.
    await tester.tap(find.byKey(const Key('site-nav-0')));
    await tester.pumpAndSettle();
    expect(find.text('Daily Essentials'), findsOneWidget);
    await tester.tap(find.byKey(const Key('site-nav-1')));
    await tester.pumpAndSettle();
    expect(find.text('Our Products'), findsOneWidget);
    await closeShell(tester);
  });

  testWidgets('a computer: the cart with its order box in view', (
    tester,
  ) async {
    sudhamrtamCart.clearCart();
    final milk = sudhamrtamCatalog.productById('buffalo_milk')!;
    final curd = sudhamrtamCatalog.productById('curd')!;
    sudhamrtamCart.addProduct(milk, quantity: 2);
    sudhamrtamCart.addProduct(curd);

    await pumpShell(tester, const Size(1440, 900));
    await tester.tap(find.byKey(const Key('site-cart')));
    await tester.pumpAndSettle();

    // Proceed to Checkout is on the first screen, no scrolling.
    final checkout = find.byKey(const Key('wide-cart-checkout'));
    expect(checkout, findsOneWidget);
    expect(tester.getRect(checkout).bottom, lessThan(900));
    expect(
      find.text('Subtotal (3 items): ₹300.00', findRichText: true),
      findsNWidgets(2),
    );

    // + adds one; the bin at 1 and Delete remove the product.
    await tester.tap(
      find.descendant(
        of: find.byKey(const Key('wide-cart-item-curd')),
        matching: find.byTooltip('Increase quantity'),
      ),
    );
    await tester.pump();
    expect(sudhamrtamCart.quantityFor('curd'), 2);
    await tester.tap(find.byKey(const Key('wide-cart-delete-curd')));
    await tester.pump();
    expect(sudhamrtamCart.quantityFor('curd'), 0);
    await tester.tap(find.byTooltip('Decrease quantity'));
    await tester.pump();
    await tester.tap(find.byTooltip('Remove product'));
    await tester.pump();
    expect(sudhamrtamCart.items, isEmpty);
    await closeShell(tester);
  });

  testWidgets('a computer: the cart panel on the right once something is in '
      'the cart', (tester) async {
    sudhamrtamCart.clearCart();
    await pumpShell(tester, const Size(1440, 900));
    expect(find.byKey(const Key('site-cart-rail')), findsNothing);

    sudhamrtamCart.addProduct(sudhamrtamCatalog.productById('cow_milk')!);
    await tester.pump();
    final rail = find.byKey(const Key('site-cart-rail'));
    expect(rail, findsOneWidget);
    expect(tester.getRect(rail).right, 1440);
    final price = sudhamrtamCatalog.productById('cow_milk')!.price;
    expect(
      tester.widget<Text>(find.byKey(const Key('site-cart-subtotal'))).data,
      '₹${price.toStringAsFixed(2)}',
    );
    // + adds one; at one the bin takes it out, and the panel goes.
    await tester.tap(find.byKey(const Key('site-cart-more-cow_milk')));
    await tester.pump();
    expect(sudhamrtamCart.quantityFor('cow_milk'), 2);
    expect(
      tester.widget<Text>(find.byKey(const Key('site-cart-subtotal'))).data,
      '₹${(price * 2).toStringAsFixed(2)}',
    );
    await tester.tap(find.byKey(const Key('site-cart-less-cow_milk')));
    await tester.pump();
    await tester.tap(find.byKey(const Key('site-cart-less-cow_milk')));
    await tester.pump();
    expect(sudhamrtamCart.isEmpty, isTrue);
    expect(rail, findsNothing);

    // Go to Cart opens the Cart page, which needs no panel.
    sudhamrtamCart.addProduct(sudhamrtamCatalog.productById('cow_milk')!);
    await tester.pump();
    await tester.tap(find.byKey(const Key('site-cart-go')));
    await tester.pump();
    expect(rail, findsNothing);
    expect(tester.takeException(), isNull);
    sudhamrtamCart.clearCart();
    await closeShell(tester);
  });

  testWidgets('a computer: the product page in two columns', (tester) async {
    tester.view.physicalSize = const Size(1440, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final milk = sudhamrtamCatalog.productById('buffalo_milk')!;
    await tester.pumpWidget(
      MaterialApp(
        home: ProductDetailsScreen(
          productId: milk.id,
          productName: milk.name,
          category: milk.category,
          productIcon: milk.icon,
          description: milk.description,
          unit: milk.unit,
          price: milk.price,
        ),
      ),
    );
    await tester.pump();
    expect(find.byKey(const Key('product-wide')), findsOneWidget);
    // Add to Cart is beside the photo, on the first screen.
    final add = find.byKey(const Key('add-to-cart'));
    expect(
      tester.getRect(add).left,
      greaterThan(tester.getRect(find.byKey(const Key('product-photo'))).right),
    );
    expect(tester.getRect(add).bottom, lessThan(900));
  });

  for (final width in [1200.0, 1440.0]) {
    testWidgets('a computer ($width wide): checkout in two columns', (
      tester,
    ) async {
      sudhamrtamCart.clearCart();
      sudhamrtamCart.addProduct(
        sudhamrtamCatalog.productById('buffalo_milk')!,
        quantity: 3,
      );
      tester.view.physicalSize = Size(width, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        MaterialApp(
          home: CheckoutScreen(
            enableTestOrders: false, // like the live website
            sendsToServer: true,
            loadRules: () async => const OrderRules(
              minimumOrderPaise: 20000,
              deliveryFeePaise: 0,
              cutoffHourIst: 21,
              maxDaysAhead: 30,
              paymentMethods: ['cash_on_delivery', 'online'],
            ),
          ),
        ),
      );
      // Addresses and rules load on a real thread.
      for (var i = 0; i < 20; i++) {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 20)),
        );
        await tester.pump();
      }

      expect(find.byKey(const Key('checkout-wide-steps')), findsOneWidget);
      // The order box: total and Place Order on the first screen.
      final summary = find.byKey(const Key('checkout-wide-summary'));
      expect(
        find.descendant(of: summary, matching: find.text('₹270.00')),
        findsNWidgets(2),
      );
      expect(
        find.descendant(of: summary, matching: find.text('Free')),
        findsOneWidget,
      );
      final place = find.byKey(const Key('checkout-place-order'));
      expect(tester.getRect(place).bottom, lessThan(900));
      expect(tester.takeException(), isNull);

      // Choosing Pay Online (the steps scroll; the order box stays)
      // changes the summary and the button.
      final online = find.byKey(const Key('checkout-option-online'));
      await tester.scrollUntilVisible(
        online,
        200,
        scrollable: find
            .descendant(
              of: find.byKey(const Key('checkout-wide-steps')),
              matching: find.byType(Scrollable),
            )
            .first,
      );
      expect(tester.getRect(place).bottom, lessThan(900));
      await tester.tap(online);
      await tester.pump();
      expect(
        find.descendant(
          of: summary,
          matching: find.text('Pay Online (UPI / Card / Net Banking)'),
        ),
        findsOneWidget,
      );
      expect(find.text('Place Order & Pay'), findsOneWidget);
      sudhamrtamCart.clearCart();
      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(minutes: 1));
    });
  }

  testWidgets('a computer: subscriptions in two columns', (tester) async {
    await pumpShell(tester, const Size(1440, 900));
    await tester.tap(find.byKey(const Key('site-nav-2')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('milkPlanWide')), findsOneWidget);
    expect(find.byKey(const Key('startPlan-Buffalo Milk')), findsOneWidget);
    expect(find.byKey(const Key('startPlan-Cow Milk')), findsOneWidget);
    expect(find.byKey(const Key('deliveryOptions')), findsOneWidget);
    // One page, one heading: no second bar.
    expect(find.text('Subscription'), findsNothing);
    await closeShell(tester);
  });

  testWidgets('a phone: the app with its bottom tabs, no footer', (
    tester,
  ) async {
    await pumpShell(tester, const Size(412, 900));
    expect(find.byKey(const Key('site-shell')), findsNothing);
    expect(find.byType(NavigationBar), findsOneWidget);
    expect(find.byKey(const Key('site-footer')), findsNothing);
    await closeShell(tester);
  });

  // The first-login tour (owner request and decisions 2026-11-28): here,
  // with the same app setup, so only one test file starts the whole shell.
  group('first-login tour', () {
    Finder inTour(Finder f) =>
        find.descendant(of: find.byKey(const Key('app-tour')), matching: f);

    late bool seen;
    late int marked;

    Future<void> pumpTour(
      WidgetTester tester, {
      bool signedIn = true,
      Size size = const Size(412, 915),
    }) async {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        MaterialApp(
          home: CustomerShell(
            signedIn: () => signedIn,
            tourSeen: () async => seen,
            markTourSeen: () async {
              seen = true;
              marked++;
            },
          ),
        ),
      );
      await tester.pump();
      await tester.pump();
    }

    setUp(() {
      seen = false;
      marked = 0;
    });

    Future<void> next(WidgetTester tester) async {
      await tester.tap(find.byKey(const Key('tour-next')));
      await tester.pump();
      await tester.pump();
    }

    testWidgets('after sign-in: welcome, each option lit up, Done', (
      tester,
    ) async {
      await pumpTour(tester);
      expect(find.byKey(const Key('app-tour')), findsOneWidget);
      expect(inTour(find.text('Welcome to Sudhamrtam')), findsOneWidget);
      expect(find.text('Show me'), findsOneWidget);

      await next(tester);
      expect(find.text('Shop'), findsWidgets);
      expect(find.textContaining('Order by 9 PM'), findsOneWidget);
      // No server here, so no Messages bell: that stop is passed over.
      expect(find.text('1 of 4'), findsOneWidget);
      await next(tester);
      expect(find.textContaining('Pause it when you travel'), findsOneWidget);
      expect(find.text('2 of 4'), findsOneWidget);
      await next(tester);
      expect(find.text('3 of 4'), findsOneWidget);
      await next(tester);
      expect(find.text('4 of 4'), findsOneWidget);
      expect(find.textContaining('see this tour again'), findsOneWidget);
      // The last stop: Done, no Skip.
      expect(find.byKey(const Key('tour-skip')), findsNothing);
      expect(find.text('Done'), findsOneWidget);
      await next(tester);
      expect(find.byKey(const Key('app-tour')), findsNothing);
      expect(marked, 1);
      await closeShell(tester);
    });

    testWidgets('Skip ends it; seen once, it does not come back', (
      tester,
    ) async {
      await pumpTour(tester);
      await next(tester);
      await tester.tap(find.byKey(const Key('tour-skip')));
      await tester.pump();
      expect(find.byKey(const Key('app-tour')), findsNothing);
      expect(marked, 1);
      await closeShell(tester);

      await pumpTour(tester);
      expect(find.byKey(const Key('app-tour')), findsNothing);
      await closeShell(tester);
    });

    testWidgets('not signed in, or the website layout: no tour', (
      tester,
    ) async {
      await pumpTour(tester, signedIn: false);
      expect(find.byKey(const Key('app-tour')), findsNothing);
      await closeShell(tester);

      await pumpTour(tester, size: const Size(1440, 900));
      expect(find.byKey(const Key('app-tour')), findsNothing);
      await closeShell(tester);
    });

    testWidgets('Account -> Show the app tour plays it again', (tester) async {
      seen = true;
      await pumpTour(tester);
      expect(find.byKey(const Key('app-tour')), findsNothing);
      await tester.tap(find.text('Account'));
      await tester.pump();
      await tester.pump();
      final tile = find.byKey(const Key('accountShowTour'));
      await tester.scrollUntilVisible(tile, 300);
      await tester.ensureVisible(tile);
      await tester.pump();
      await tester.tap(tile);
      await tester.pump();
      await tester.pump();
      expect(inTour(find.text('Welcome to Sudhamrtam')), findsOneWidget);
      expect(appTourRequests.value, greaterThan(0));
      await closeShell(tester);
    });
  });
}
