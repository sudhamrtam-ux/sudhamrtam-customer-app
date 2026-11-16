import 'package:flutter/material.dart';

import '../../models/product_photos.dart';

/// Product photos bundled with the app, by product ID. The owner's
/// photos from the server (productPhotoUrls) come first.
///
/// The photos come from the Sudhamrtam website
/// (sudhamrtam.in/admin/uploads/products/), resized for the app;
/// the curd photo was supplied by the owner.
/// Products without a photo show their icon instead.
const Map<String, String> productImageAssets = {
  'buffalo_milk': 'assets/images/products/buffalo_milk.jpg',
  'cow_milk': 'assets/images/products/cow_milk.jpg',
  'curd': 'assets/images/products/curd.jpg',
  'buffalo_ghee': 'assets/images/products/buffalo_ghee.jpg',
  'cow_ghee': 'assets/images/products/cow_ghee.jpg',
  'raw_honey': 'assets/images/products/raw_honey.jpg',
  'honey_250g': 'assets/images/products/raw_honey.jpg',
  'honey_500g': 'assets/images/products/raw_honey.jpg',
  'paneer': 'assets/images/products/paneer.jpg',
  'coconut_oil': 'assets/images/products/coconut_oil.jpg',
  'groundnut_oil': 'assets/images/products/groundnut_oil.jpg',
  'sesame_oil': 'assets/images/products/sesame_oil.jpg',
  'sunflower_oil': 'assets/images/products/sunflower_oil.jpg',
};

const String sudhamrtamLogoAsset = 'assets/images/logo.jpg';

/// A product's photo, or its [icon] when there is no photo.
///
/// The whole photo is always shown, scaled to fit the space and
/// centred, so tall bottles keep their caps and bases.
class ProductImage extends StatelessWidget {
  const ProductImage({
    super.key,
    required this.productId,
    required this.icon,
    this.iconSize = 42,
    this.iconColor = const Color(0xFF82B440),
    this.borderRadius = 12,
  });

  final String productId;
  final IconData icon;
  final double iconSize;
  final Color iconColor;
  final double borderRadius;

  /// This product's photo, else one of its other sizes' (a size added
  /// later, e.g. Paneer 200 g, shows the Paneer photo).
  String get _photoId {
    bool hasPhoto(String id) =>
        productImageAssets.containsKey(id) || productPhotoUrls.containsKey(id);
    if (hasPhoto(productId)) return productId;
    return productOtherSizes[productId]?.where(hasPhoto).firstOrNull ??
        productId;
  }

  @override
  Widget build(BuildContext context) {
    final photoId = _photoId;
    final asset = productImageAssets[photoId];
    final url = productPhotoUrls[photoId];
    final fallback = Center(
      child: Icon(icon, size: iconSize, color: iconColor),
    );

    if (asset == null && url == null) return fallback;

    final builtIn = asset == null
        ? fallback
        : Image.asset(
            asset,
            errorBuilder: (context, error, stackTrace) => fallback,
          );

    // Without a fixed size the image keeps its shape inside the
    // space, and the rounded corners follow the photo itself.
    return Center(
      child: ClipRRect(
        borderRadius: BorderRadius.circular(borderRadius),
        child: url == null
            ? builtIn
            // The owner's photo; the built-in one while it loads or
            // when it cannot be loaded (offline).
            : Image.network(
                url,
                frameBuilder: (context, child, frame, wasSynchronous) =>
                    frame == null && !wasSynchronous ? builtIn : child,
                errorBuilder: (context, error, stackTrace) => builtIn,
              ),
      ),
    );
  }
}
