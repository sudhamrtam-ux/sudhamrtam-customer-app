import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:sudhamrtam_customer_app/database/milk_database_service.dart';
import 'package:sudhamrtam_customer_app/features/shop/shop_screen.dart';
import 'package:sudhamrtam_customer_app/models/catalog_repository.dart';
import 'package:sudhamrtam_customer_app/services/catalog_api_client.dart';

Map<String, Object?> product(
  String id,
  String name,
  int paise, {
  bool available = true,
}) => {
  'id': id,
  'name': name,
  'category': 'Fresh Dairy',
  'description': '',
  'unit_label': '1 kg',
  'image_path': null,
  'price_paise': paise,
  'is_available': available,
};

MockClient fakeServer() {
  return MockClient(
    (_) async => http.Response(
      jsonEncode({
        'products': [
          product('paneer', 'Paneer', 80000),
          product('cow_ghee', 'Cow Ghee', 80000, available: false),
        ],
      }),
      200,
    ),
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(sqfliteFfiInit);

  final databaseService = MilkDatabaseService.instance;
  late Directory directory;

  setUp(() async {
    directory = await Directory.systemTemp.createTemp('sudhamrtam_shop_');
    databaseService.configureForTesting(
      factory: databaseFactoryFfi,
      databasePath: '${directory.path}${Platform.pathSeparator}shop.db',
    );
    await databaseService.database;
  });

  tearDown(() async {
    await databaseService.close();
    databaseService.resetTestingConfiguration();
    await directory.delete(recursive: true);
  });

  Future<void> pumpShop(WidgetTester tester, CatalogRepository catalog) async {
    tester.view.physicalSize = const Size(1080, 4000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: ShopScreen(catalog: catalog)),
      ),
    );
    await tester.pump();
  }

  testWidgets('Without a server: built-in products with prices', (
    tester,
  ) async {
    final catalog = CatalogRepository();
    await tester.runAsync(catalog.initialize);

    await pumpShop(tester, catalog);

    expect(find.text('Cow Milk'), findsOneWidget);
    // Buffalo and cow milk: flat ₹90 per litre.
    expect(find.text('₹90 / 1 L'), findsNWidgets(2));
    expect(find.text('Buffalo Ghee'), findsOneWidget);
    expect(find.text('₹880 / 1 kg'), findsOneWidget);
    expect(find.textContaining('Delivering to'), findsNothing);
    expect(find.textContaining('Updating prices'), findsNothing);
  });

  testWidgets('With a server: shows server products, no area picker', (
    tester,
  ) async {
    final catalog = CatalogRepository(
      api: CatalogApiClient(
        baseUrl: 'http://test.local',
        httpClient: fakeServer(),
      ),
    );
    await tester.runAsync(catalog.initialize);
    await tester.runAsync(catalog.refresh);

    await pumpShop(tester, catalog);

    expect(find.text('Paneer'), findsOneWidget);
    expect(find.text('₹800 / 1 kg'), findsOneWidget);
    expect(find.text('Not available'), findsOneWidget);
    expect(find.textContaining('Delivering to'), findsNothing);
    expect(find.textContaining('delivery area'), findsNothing);
  });

  testWidgets('Offline with a server configured: explains built-in prices', (
    tester,
  ) async {
    final catalog = CatalogRepository(
      api: CatalogApiClient(
        baseUrl: 'http://test.local',
        httpClient: MockClient(
          (_) async => throw const SocketException('offline'),
        ),
      ),
    );
    await tester.runAsync(catalog.initialize);
    await tester.runAsync(catalog.refresh);

    await pumpShop(tester, catalog);

    expect(
      find.text('Could not reach the server. Showing standard prices.'),
      findsOneWidget,
    );
  });

  testWidgets('Category chips filter the products', (tester) async {
    final catalog = CatalogRepository();
    await tester.runAsync(catalog.initialize);

    tester.view.physicalSize = const Size(1080, 4000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    String? category = 'Ghee';
    await tester.pumpWidget(
      MaterialApp(
        home: StatefulBuilder(
          builder: (context, setState) => Scaffold(
            body: ShopScreen(
              catalog: catalog,
              category: category,
              onCategoryChanged: (value) => setState(() => category = value),
            ),
          ),
        ),
      ),
    );
    await tester.pump();

    // Opened from Home on one category.
    expect(find.text('Buffalo Ghee'), findsOneWidget);
    expect(find.text('Cow Milk'), findsNothing);

    await tester.tap(find.byKey(const Key('shopCategory_all')));
    await tester.pump();
    expect(find.text('Cow Milk'), findsOneWidget);
    expect(find.text('Buffalo Ghee'), findsOneWidget);

    await tester.tap(find.byKey(const Key('shopCategory_Wood-Pressed Oils')));
    await tester.pump();
    expect(find.text('Sesame Oil'), findsOneWidget);
    expect(find.text('Cow Milk'), findsNothing);
  });
}
