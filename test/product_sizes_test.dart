import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:sudhamrtam_customer_app/app/sudhamrtam_app.dart';
import 'package:sudhamrtam_customer_app/database/milk_database_service.dart';
import 'package:sudhamrtam_customer_app/features/shop/product_details_screen.dart';
import 'package:sudhamrtam_customer_app/features/shop/shop_screen.dart';

void main() {
  late Directory directory;

  setUpAll(sqfliteFfiInit);

  setUp(() async {
    directory = await Directory.systemTemp.createTemp('sudhamrtam_sizes_');
    MilkDatabaseService.instance.configureForTesting(
      factory: databaseFactoryFfi,
      databasePath: '${directory.path}${Platform.pathSeparator}x.db',
    );
  });

  tearDown(() async {
    await MilkDatabaseService.instance.close();
    MilkDatabaseService.instance.resetTestingConfiguration();
    await directory.delete(recursive: true);
  });

  testWidgets('honey: choose 250 g, 500 g or 1 kg on the product page', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1080, 4000);
    tester.view.devicePixelRatio = 2;
    addTearDown(tester.view.reset);
    await tester.runAsync(sudhamrtamCatalog.initialize);
    final honey = sudhamrtamCatalog.productById('raw_honey')!;

    await tester.pumpWidget(
      MaterialApp(
        home: ProductDetailsScreen(
          productId: honey.id,
          productName: honey.name,
          category: honey.category,
          productIcon: honey.icon,
          description: honey.description,
          unit: honey.unit,
          price: honey.price,
        ),
      ),
    );
    expect(find.text('250 g · ₹150'), findsOneWidget);
    expect(find.text('500 g · ₹290'), findsOneWidget);
    expect(find.text('1 kg · ₹550'), findsOneWidget);
    expect(find.text('Price: ₹550.00'), findsOneWidget);
    expect(find.text('FSSAI Lic. No. 23625029000830'), findsOneWidget);

    await tester.tap(find.byKey(const Key('size-honey_250g')));
    await tester.pumpAndSettle();
    expect(find.text('Price: ₹150.00'), findsOneWidget);
    expect(
      tester
          .widget<ChoiceChip>(find.byKey(const Key('size-honey_250g')))
          .selected,
      isTrue,
    );
  });

  testWidgets('the Shop shows honey once, with its sizes', (tester) async {
    tester.view.physicalSize = const Size(1080, 6000);
    tester.view.devicePixelRatio = 2;
    addTearDown(tester.view.reset);
    await tester.runAsync(sudhamrtamCatalog.initialize);

    await tester.pumpWidget(
      const MaterialApp(home: Scaffold(body: ShopScreen())),
    );
    await tester.pumpAndSettle();
    expect(find.text('Honey (Multi Flower)'), findsOneWidget);
    expect(find.text('From ₹150'), findsOneWidget);
    expect(find.byKey(const Key('sizes-honey_250g')), findsOneWidget);
    expect(find.text('3 sizes'), findsOneWidget);

    // It opens on the cheapest size, with the others to choose from.
    await tester.tap(find.text('Honey (Multi Flower)'));
    await tester.pumpAndSettle();
    expect(find.text('Price: ₹150.00'), findsOneWidget);
    expect(find.text('1 kg · ₹550'), findsOneWidget);
  });

  testWidgets(
    'the bill next to the quantity: price × quantity, and the cart after',
    (tester) async {
      tester.view.physicalSize = const Size(1080, 4000);
      tester.view.devicePixelRatio = 2;
      addTearDown(tester.view.reset);
      await tester.runAsync(sudhamrtamCatalog.initialize);
      await tester.runAsync(sudhamrtamCart.initialize);
      final honey = sudhamrtamCatalog.productById('honey_250g')!;

      await tester.pumpWidget(
        MaterialApp(
          home: ProductDetailsScreen(
            productId: honey.id,
            productName: honey.name,
            category: honey.category,
            productIcon: honey.icon,
            description: honey.description,
            unit: honey.unit,
            price: honey.price,
          ),
        ),
      );
      String text(String key) => (tester.widget<Text>(
        find
            .descendant(of: find.byKey(Key(key)), matching: find.byType(Text))
            .first,
      )).data!;

      expect(text('quantity-bill-line'), '₹150.00 × 1 pack (250 g)');
      expect(find.text('Add to Cart · ₹150.00'), findsOneWidget);

      await tester.tap(find.byKey(const Key('qty-plus')));
      await tester.pump();
      await tester.tap(find.byKey(const Key('qty-plus')));
      await tester.pumpAndSettle();
      expect(tester.widget<Text>(find.byKey(const Key('qty-value'))).data, '3');
      expect(text('quantity-bill-line'), '₹150.00 × 3 packs (250 g)');
      expect(find.text('₹450.00'), findsWidgets);
      expect(find.text('Add to Cart · ₹450.00'), findsOneWidget);
      expect(find.byKey(const Key('cart-after')), findsNothing);

      await tester.runAsync(() async {
        await tester.tap(find.byKey(const Key('add-to-cart')));
        await Future<void>.delayed(const Duration(milliseconds: 200));
      });
      await tester.pumpAndSettle();
      expect(find.text('Already in your cart: 3'), findsOneWidget);
      expect(text('cart-after'), 'Your cart will have 6');
      expect(find.text('₹900.00'), findsOneWidget);

      // At most 10: the cart after stops at 10, with a note.
      for (var i = 0; i < 6; i++) {
        await tester.tap(find.byKey(const Key('qty-plus')));
        await tester.pump();
      }
      await tester.pumpAndSettle();
      expect(text('cart-after'), 'Your cart will have 10');
      expect(
        find.text('At most 10 of one product can be in the cart.'),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    },
  );
}
