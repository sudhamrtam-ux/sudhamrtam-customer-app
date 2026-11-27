import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:sudhamrtam_customer_app/app/sudhamrtam_app.dart';
import 'package:sudhamrtam_customer_app/database/milk_database_service.dart';
import 'package:sudhamrtam_customer_app/features/cart/cart_screen.dart';
import 'package:sudhamrtam_customer_app/models/product.dart';

/// The cart shows each product's photo, as the shop does (it showed only
/// the category icon before, 19 Nov 2026). Prices are SAMPLE data.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final databaseService = MilkDatabaseService.instance;
  late Directory directory;

  setUpAll(() async {
    sqfliteFfiInit();
    directory = await Directory.systemTemp.createTemp('sudhamrtam_cart_photo_');
    databaseService.configureForTesting(
      factory: databaseFactoryFfi,
      databasePath: '${directory.path}${Platform.pathSeparator}cart.db',
    );
    await sudhamrtamCart.initialize();
  });

  tearDownAll(() async {
    await sudhamrtamCart.waitForPendingSaves();
    await databaseService.close();
    databaseService.resetTestingConfiguration();
    await directory.delete(recursive: true);
  });

  // Outside the widget test's fake clock, so the SQLite save finishes.
  setUp(() async {
    const milk = Product(
      id: 'buffalo_milk',
      name: 'Buffalo Milk',
      category: 'Fresh Dairy',
      description: 'SAMPLE',
      price: 90,
      unit: '1 L',
      icon: Icons.local_drink_outlined,
    );
    sudhamrtamCart.clearCart();
    expect(sudhamrtamCart.addProduct(milk), isTrue);
    await sudhamrtamCart.waitForPendingSaves();
  });

  testWidgets('a cart item shows its product photo', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(home: Scaffold(body: CartScreen())),
    );
    await tester.pump();

    final photo = find.byKey(const Key('cart-photo-buffalo_milk'));
    expect(photo, findsOneWidget);
    final image = tester.widget<Image>(
      find.descendant(of: photo, matching: find.byType(Image)),
    );
    expect(
      (image.image as AssetImage).assetName,
      'assets/images/products/buffalo_milk.jpg',
    );
    expect(
      find.descendant(
        of: photo,
        matching: find.byIcon(Icons.local_drink_outlined),
      ),
      findsNothing,
    );
    // One unit, not "1 units" (2026-11-27).
    expect(find.text('1 unit selected'), findsOneWidget);
  });
}
