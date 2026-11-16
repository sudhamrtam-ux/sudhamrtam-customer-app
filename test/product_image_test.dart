import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:sudhamrtam_customer_app/features/shop/product_image.dart';
import 'package:sudhamrtam_customer_app/models/product_catalog.dart';
import 'package:sudhamrtam_customer_app/models/product_photos.dart';

void main() {
  test('every product photo and the logo are bundled', () {
    for (final asset in [...productImageAssets.values, sudhamrtamLogoAsset]) {
      expect(File(asset).existsSync(), isTrue, reason: asset);
    }
  });

  test('photos are keyed by real product IDs', () {
    final ids = {for (final p in ProductCatalog.products) p.id};
    expect(ids, containsAll(productImageAssets.keys));
  });

  testWidgets('shows the photo, or the icon when there is none', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Column(
          children: [
            SizedBox(
              height: 100,
              child: ProductImage(
                productId: 'cow_milk',
                icon: Icons.local_drink_outlined,
              ),
            ),
            SizedBox(
              height: 100,
              child: ProductImage(
                // A product added later, before its photo.
                productId: 'new_product',
                icon: Icons.breakfast_dining_outlined,
              ),
            ),
          ],
        ),
      ),
    );

    expect(find.byType(Image), findsOneWidget);
    expect(find.byIcon(Icons.breakfast_dining_outlined), findsOneWidget);
    expect(find.byIcon(Icons.local_drink_outlined), findsNothing);
  });

  testWidgets("a new size without a photo shows its product's", (tester) async {
    productOtherSizes = {
      'paneer_200_g': ['paneer'],
    };
    addTearDown(() => productOtherSizes = const {});
    await tester.pumpWidget(
      const MaterialApp(
        home: SizedBox(
          height: 100,
          child: ProductImage(
            productId: 'paneer_200_g',
            icon: Icons.breakfast_dining_outlined,
          ),
        ),
      ),
    );
    final image = tester.widget<Image>(find.byType(Image));
    expect(
      (image.image as AssetImage).assetName,
      'assets/images/products/paneer.jpg',
    );
    expect(find.byIcon(Icons.breakfast_dining_outlined), findsNothing);
  });
}
