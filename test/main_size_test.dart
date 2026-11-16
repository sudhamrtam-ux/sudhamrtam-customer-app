import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:sudhamrtam_customer_app/models/catalog_repository.dart';
import 'package:sudhamrtam_customer_app/models/product.dart';

Product size(String id, String unit) => Product(
  id: id,
  name: 'Buffalo Milk',
  category: 'Fresh Dairy',
  description: '',
  price: 45,
  unit: unit,
  icon: Icons.local_drink_outlined,
);

/// Daily Essentials on Home shows each product's main size (owner
/// decision 2026-11-16).
void main() {
  test('1 L or 1 kg is the main size, wherever it is in the list', () {
    expect(mainSize([size('b500', '500 ml'), size('b1', '1 L')]).id, 'b1');
    expect(
      mainSize([
        size('p200', '200 g'),
        size('p400', '400 g'),
        size('p1', '1 kg'),
      ]).id,
      'p1',
    );
  });

  test('without 1 L or 1 kg, the first size', () {
    expect(mainSize([size('h250', '250 g'), size('h500', '500 g')]).id, 'h250');
  });
}
