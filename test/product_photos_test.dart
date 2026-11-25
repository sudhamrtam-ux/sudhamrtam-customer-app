import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:sudhamrtam_customer_app/database/catalog_cache_service.dart';
import 'package:sudhamrtam_customer_app/features/shop/product_image.dart';
import 'package:sudhamrtam_customer_app/models/product_photos.dart';

void main() {
  tearDown(() => productPhotoUrls = const {});

  test('the photo link is kept with the catalog (and left out when none)', () {
    final json = {
      'id': 'curd',
      'name': 'Curd',
      'category': 'Fresh Dairy',
      'unit_label': '500 g',
      'price_paise': 6000,
      'photo_url': '/v1/products/curd/photo?v=1763190000',
    };
    final item = CatalogProductData.fromJson(json);
    expect(item.photoUrl, '/v1/products/curd/photo?v=1763190000');
    expect(CatalogProductData.fromJson(item.toJson()).photoUrl, item.photoUrl);

    final none = CatalogProductData.fromJson({...json}..remove('photo_url'));
    expect(none.photoUrl, isNull);
    expect(none.toJson().containsKey('photo_url'), isFalse);
  });

  Future<void> pump(WidgetTester tester, String productId) => tester.pumpWidget(
    MaterialApp(
      home: SizedBox(
        width: 100,
        height: 100,
        child: ProductImage(productId: productId, icon: Icons.egg),
      ),
    ),
  );

  testWidgets("the owner's photo first; the built-in one otherwise", (
    tester,
  ) async {
    await pump(tester, 'curd');
    expect(tester.widget<Image>(find.byType(Image)).image, isA<AssetImage>());

    productPhotoUrls = {
      'curd': 'https://api.test/v1/products/curd/photo?v=2',
      'new_item': 'https://api.test/v1/products/new_item/photo?v=1',
    };
    await pump(tester, 'curd');
    final network = tester
        .widgetList<Image>(find.byType(Image))
        .map((i) => i.image)
        .whereType<NetworkImage>();
    expect(network.single.url, 'https://api.test/v1/products/curd/photo?v=2');

    // A new product with no built-in photo can still show one.
    await pump(tester, 'new_item');
    expect(find.byType(Image), findsWidgets);
  });
}
