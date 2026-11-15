import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:sudhamrtam_customer_app/app/sudhamrtam_app.dart';
import 'package:sudhamrtam_customer_app/database/milk_database_service.dart';
import 'package:sudhamrtam_customer_app/features/shop/product_details_screen.dart';

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
}
