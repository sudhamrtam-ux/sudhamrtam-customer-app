import 'package:flutter/material.dart';

import 'product.dart';
import 'product_descriptions.dart';

/// Central product catalog for Sudhamrtam.
///
/// All product IDs must remain unique because they are
/// used by the Shopping Cart and SQLite persistence.
///
/// OFFLINE FALLBACK. When the app is built with API_BASE_URL,
/// products and prices come from the backend
/// (`GET /v1/catalog`) and this list is used only until the
/// first catalog is received. Keep it in step with the
/// backend's import (`sudhamrtam_backend/src/import/oldSite.ts`).
///
/// Prices (owner decisions, 6 November 2026): one price for
/// every customer in every area. Milk ₹90 per litre, Buffalo
/// Ghee ₹880 per kg, Curd ₹120 per kg; other prices from
/// https://sudhamrtam.in.
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
      description: buffaloMilkDescription,
      price: 90.0,
      unit: '1 L',
      icon: Icons.local_drink_outlined,
    ),

    Product(
      id: 'cow_milk',
      name: 'Cow Milk',
      category: 'Fresh Dairy',
      description: cowMilkDescription,
      price: 90.0,
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

    Product(
      id: 'paneer',
      name: 'Paneer',
      category: 'Fresh Dairy',
      description: paneerDescription,
      price: 800.0,
      unit: '1 kg',
      icon: Icons.egg_alt_outlined,
    ),

    // ============================
    // GHEE
    // ============================
    Product(
      id: 'buffalo_ghee',
      name: 'Buffalo Ghee',
      category: 'Ghee',
      description: buffaloGheeDescription,
      price: 880.0,
      unit: '1 kg',
      icon: Icons.soup_kitchen_outlined,
    ),

    Product(
      id: 'cow_ghee',
      name: 'Cow Ghee',
      category: 'Ghee',
      description: cowGheeDescription,
      price: 800.0,
      unit: '1 kg',
      icon: Icons.soup_kitchen_outlined,
    ),

    // ============================
    // NATURAL GOODNESS
    // ============================
    Product(
      id: 'raw_honey',
      name: 'Honey (Multi Flower)',
      category: 'Natural Goodness',
      description: rawHoneyDescription,
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
      description: groundnutOilDescription,
      price: 430.0,
      unit: '1 kg',
      icon: Icons.water_drop_outlined,
    ),

    Product(
      id: 'sesame_oil',
      name: 'Sesame Oil',
      category: 'Wood-Pressed Oils',
      description: sesameOilDescription,
      price: 460.0,
      unit: '1 kg',
      icon: Icons.water_drop_outlined,
    ),

    Product(
      id: 'sunflower_oil',
      name: 'Sunflower Oil',
      category: 'Wood-Pressed Oils',
      description: sunflowerOilDescription,
      price: 550.0,
      unit: '1 kg',
      icon: Icons.water_drop_outlined,
    ),

    Product(
      id: 'coconut_oil',
      name: 'Coconut Oil',
      category: 'Wood-Pressed Oils',
      description: coconutOilDescription,
      price: 700.0,
      unit: '1 kg',
      icon: Icons.water_drop_outlined,
    ),
  ];
}
