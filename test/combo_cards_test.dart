import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:sudhamrtam_customer_app/database/milk_database_service.dart';
import 'package:sudhamrtam_customer_app/features/home/home_screen.dart';
import 'package:sudhamrtam_customer_app/models/cart_manager.dart';
import 'package:sudhamrtam_customer_app/models/catalog_repository.dart';
import 'package:sudhamrtam_customer_app/models/combo_offer.dart';

ComboOffer diwali({int pricePaise = 18900, int max = 2}) =>
    ComboOffer.fromJson({
      'id': 'diwali_combo_1',
      'title': 'Diwali Delight',
      'occasion': 'festive',
      'discount_bp': 1000,
      'starts_on': '2026-11-07',
      'ends_on': '2026-11-20',
      'max_per_order': max,
      'items': [
        {
          'product_id': 'curd',
          'name': 'Curd',
          'unit_label': '500 g',
          'quantity': 2,
          'unit_price_paise': 6000,
          'is_available': true,
        },
        {
          'product_id': 'cow_milk',
          'name': 'Cow Milk',
          'unit_label': '1 L',
          'quantity': 1,
          'unit_price_paise': 9000,
          'is_available': true,
        },
      ],
      'full_paise': 21000,
      'price_paise': pricePaise,
      'savings_paise': 21000 - pricePaise,
    });

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(sqfliteFfiInit);

  final databaseService = MilkDatabaseService.instance;
  late Directory directory;

  setUp(() async {
    directory = await Directory.systemTemp.createTemp('sudhamrtam_combo_');
    databaseService.configureForTesting(
      factory: databaseFactoryFfi,
      databasePath: '${directory.path}${Platform.pathSeparator}combo.db',
    );
    await databaseService.database;
  });

  tearDown(() async {
    await databaseService.close();
    databaseService.resetTestingConfiguration();
    await directory.delete(recursive: true);
  });

  test('a combo is one cart line, at the combo price, with its limit', () {
    final combo = diwali();
    final product = combo.toProduct();
    expect(product.id, 'combo__diwali_combo_1');
    expect(isComboProductId(product.id), isTrue);
    expect(comboIdOf(product.id), 'diwali_combo_1');
    expect(product.price, 189.0);
    expect(product.maxQuantity, 2);
    expect(product.description, '2 × Curd (500 g) · 1 × Cow Milk (1 L)');
    expect(combo.discountLabel, '10% OFF');
    expect(combo.occasionLabel, 'Festive offer');

    // Ended: the cart keeps it, unavailable.
    final combos = ComboRepository()..setCombos([combo]);
    expect(combos.productById(product.id)!.isAvailable, isTrue);
    combos.setCombos(const []);
    expect(combos.productById(product.id)!.isAvailable, isFalse);
    expect(combos.productById('combo__never_seen'), isNull);
    expect(combos.productById('curd'), isNull);
  });

  testWidgets('Home shows combo cards; Add to cart, then up to the limit', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1080, 5000);
    tester.view.devicePixelRatio = 2;
    addTearDown(tester.view.reset);

    final combos = ComboRepository()..setCombos([diwali()]);
    final catalog = CatalogRepository();
    final cart = CartManager(
      productLookup: (id) => isComboProductId(id)
          ? combos.productById(id)
          : catalog.productById(id),
    );
    await tester.runAsync(catalog.initialize);
    await tester.runAsync(cart.initialize);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: HomeScreen(
            catalog: catalog,
            cart: cart,
            combos: combos,
            loadRules: null,
            loadOffers: null,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    // An offer tile with the gift picture (2026-11-26): the discount,
    // the products, the title on the tag, the prices and the end.
    expect(find.byKey(const Key('combo-cards')), findsOneWidget);
    expect(find.byKey(const Key('combo-card-diwali_combo_1')), findsOneWidget);
    expect(find.text('10% off'), findsOneWidget);
    // The cross belt over the corner (2026-11-26).
    expect(find.text('10% OFF'), findsOneWidget);
    expect(find.text('FESTIVE OFFER'), findsOneWidget);
    expect(find.text('Diwali Delight'), findsOneWidget);
    expect(find.text('You save ₹21.00'), findsOneWidget);
    // No picture from the owner: the gift with the title on its tag.
    expect(find.text('DIWALI'), findsOneWidget);
    expect(find.text('DELIGHT'), findsOneWidget);
    expect(find.text('×2'), findsOneWidget);
    expect(find.text('₹210.00'), findsOneWidget);
    expect(find.text('₹189.00'), findsOneWidget);
    expect(find.text('Ends 20 Nov'), findsOneWidget);

    await tester.tap(find.byKey(const Key('combo-add-diwali_combo_1')));
    await tester.pumpAndSettle();
    expect(cart.quantityFor('combo__diwali_combo_1'), 1);
    expect(cart.subtotal, 189.0);
    expect(find.text('1 in cart'), findsOneWidget);
    expect(find.text('Diwali Delight added to cart'), findsOneWidget);

    await tester.tap(find.byKey(const Key('combo-plus')));
    await tester.pumpAndSettle();
    expect(cart.quantityFor('combo__diwali_combo_1'), 2);
    // At the limit (2 per order): + is off, and the cart refuses more.
    expect(cart.increaseQuantity('combo__diwali_combo_1'), isFalse);
    expect(cart.updateQuantity('combo__diwali_combo_1', 3), isFalse);

    await tester.tap(find.byKey(const Key('combo-minus')));
    await tester.pumpAndSettle();
    expect(cart.quantityFor('combo__diwali_combo_1'), 1);

    // The price follows the combo; an ended combo stays, unavailable.
    combos.setCombos([diwali(pricePaise: 18000)]);
    cart.refreshProducts();
    expect(cart.subtotal, 180.0);
    combos.setCombos(const []);
    cart.refreshProducts();
    await tester.pumpAndSettle();
    expect(cart.items.single.product.isAvailable, isFalse);
    expect(find.byKey(const Key('combo-cards')), findsNothing);

    var done = false;
    cart.waitForPendingSaves().then((_) => done = true);
    for (var i = 0; i < 200 && !done; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 20)),
      );
      await tester.pump();
    }
    expect(tester.takeException(), isNull);
  });
}
