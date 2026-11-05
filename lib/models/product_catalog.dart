import 'package:flutter/material.dart';

import 'product.dart';

/// Central product catalog for Sudhamrtam.
///
/// All product IDs must remain unique because they are
/// used by the Shopping Cart and SQLite persistence.
class ProductCatalog {
  ProductCatalog._();

  static const List<Product> products = [
    // ============================
    // FRESH DAIRY
    // ============================

    Product(
      id: 'buffalo_milk',
      name: 'Buffalo Milk',
      category: 'Fresh Dairy',
      description: 'Fresh buffalo milk from Sudhamrtam.',
      price: 0.0,
      unit: '1 L',
      icon: Icons.local_drink_outlined,
    ),

    Product(
      id: 'cow_milk',
      name: 'Cow Milk',
      category: 'Fresh Dairy',
      description: 'Fresh cow milk from Sudhamrtam.',
      price: 0.0,
      unit: '1 L',
      icon: Icons.local_drink_outlined,
    ),

    Product(
      id: 'curd',
      name: 'Curd',
      category: 'Fresh Dairy',
      description: 'Fresh curd from Sudhamrtam.',
      price: 0.0,
      unit: '500 g',
      icon: Icons.breakfast_dining_outlined,
    ),

    // ============================
    // NATURAL GOODNESS
    // ============================
    Product(
      id: 'raw_honey',
      name: 'Raw Honey',
      category: 'Natural Goodness',
      description: 'Naturally sourced raw honey.',
      price: 0.0,
      unit: '500 g',
      icon: Icons.spa_outlined,
    ),

    // ============================
    // WOOD-PRESSED OILS
    // ============================
    Product(
      id: 'groundnut_oil',
      name: 'Groundnut Oil',
      category: 'Wood-Pressed Oils',
      description: 'Traditionally wood-pressed groundnut oil.',
      price: 0.0,
      unit: '1 L',
      icon: Icons.water_drop_outlined,
    ),

    Product(
      id: 'sesame_oil',
      name: 'Sesame Oil',
      category: 'Wood-Pressed Oils',
      description: 'Traditionally wood-pressed sesame oil.',
      price: 0.0,
      unit: '1 L',
      icon: Icons.water_drop_outlined,
    ),

    Product(
      id: 'sunflower_oil',
      name: 'Sunflower Oil',
      category: 'Wood-Pressed Oils',
      description: 'Traditionally wood-pressed sunflower oil.',
      price: 0.0,
      unit: '1 L',
      icon: Icons.water_drop_outlined,
    ),

    Product(
      id: 'coconut_oil',
      name: 'Coconut Oil',
      category: 'Wood-Pressed Oils',
      description: 'Traditionally wood-pressed coconut oil.',
      price: 0.0,
      unit: '1 L',
      icon: Icons.water_drop_outlined,
    ),
  ];
}
