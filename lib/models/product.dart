import 'package:flutter/material.dart';

class Product {
  final String id;
  final String name;
  final String category;
  final String description;
  final double price;
  final String unit;
  final IconData icon;

  /// False when the product is not sold in the selected
  /// delivery area (or is unknown). Such products may stay
  /// in the cart but block checkout.
  final bool isAvailable;

  /// At most this many in the cart (a combo offer's limit per
  /// order); null: the cart's own limit.
  final int? maxQuantity;

  const Product({
    required this.id,
    required this.name,
    required this.category,
    required this.description,
    required this.price,
    required this.unit,
    required this.icon,
    this.isAvailable = true,
    this.maxQuantity,
  });

  /// Placeholder for a saved cart item whose product is
  /// no longer known. Keeps the item visible instead of
  /// silently deleting it; checkout is blocked until the
  /// customer removes it.
  factory Product.unknown(String id) {
    return Product(
      id: id,
      name: 'Unavailable product',
      category: 'Unavailable',
      description: 'This product is no longer available.',
      price: 0,
      unit: '-',
      icon: Icons.help_outline,
      isAvailable: false,
    );
  }

  Product copyWith({double? price, bool? isAvailable}) {
    return Product(
      id: id,
      name: name,
      category: category,
      description: description,
      price: price ?? this.price,
      unit: unit,
      icon: icon,
      isAvailable: isAvailable ?? this.isAvailable,
      maxQuantity: maxQuantity,
    );
  }
}

/// Icon for a product that came from the server, which
/// does not send icons. Matches the built-in catalog.
IconData productIconFor(String productId, String category) {
  switch (productId) {
    case 'buffalo_milk':
    case 'cow_milk':
      return Icons.local_drink_outlined;
    case 'curd':
      return Icons.breakfast_dining_outlined;
    case 'raw_honey':
      return Icons.spa_outlined;
  }

  switch (category) {
    case 'Wood-Pressed Oils':
      return Icons.water_drop_outlined;
    case 'Ghee':
      return Icons.soup_kitchen_outlined;
    case 'Fresh Dairy':
      return Icons.egg_alt_outlined;
  }

  return Icons.shopping_basket_outlined;
}
