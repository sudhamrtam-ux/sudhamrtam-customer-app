import 'package:flutter/material.dart';

import 'product.dart';

/// Central product catalog for Sudhamrtam.
///
/// All product IDs must remain unique because they are
/// used by the Shopping Cart and SQLite persistence.
///
/// PRICES ARE PROVISIONAL (set 6 November 2026):
/// - Taken from https://sudhamrtam.in/products.php for the
///   "Praneeth Pranav Flora" delivery area. Prices differ
///   by area on the website; the app has no areas yet.
/// - Curd is not listed on the website. ₹120 per kg was
///   provided directly by the business owner.
/// - Replace with backend, area-based pricing (roadmap Phase 4).
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
      price: 90.0,
      unit: '1 L',
      icon: Icons.local_drink_outlined,
    ),

    Product(
      id: 'cow_milk',
      name: 'Cow Milk',
      category: 'Fresh Dairy',
      description: 'Fresh cow milk from Sudhamrtam.',
      price: 85.0,
      unit: '1 L',
      icon: Icons.local_drink_outlined,
    ),

    Product(
      id: 'curd',
      name: 'Curd',
      category: 'Fresh Dairy',
      description: 'Fresh curd from Sudhamrtam.',
      price: 120.0,
      unit: '1 kg',
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
      price: 550.0,
      unit: '1 kg',
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
      price: 430.0,
      unit: '1 kg',
      icon: Icons.water_drop_outlined,
    ),

    Product(
      id: 'sesame_oil',
      name: 'Sesame Oil',
      category: 'Wood-Pressed Oils',
      description: 'Traditionally wood-pressed sesame oil.',
      price: 460.0,
      unit: '1 kg',
      icon: Icons.water_drop_outlined,
    ),

    Product(
      id: 'sunflower_oil',
      name: 'Sunflower Oil',
      category: 'Wood-Pressed Oils',
      description: 'Traditionally wood-pressed sunflower oil.',
      price: 550.0,
      unit: '1 kg',
      icon: Icons.water_drop_outlined,
    ),

    Product(
      id: 'coconut_oil',
      name: 'Coconut Oil',
      category: 'Wood-Pressed Oils',
      description: 'Traditionally wood-pressed coconut oil.',
      price: 700.0,
      unit: '1 kg',
      icon: Icons.water_drop_outlined,
    ),
  ];
}
