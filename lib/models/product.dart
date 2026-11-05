import 'package:flutter/material.dart';

class Product {
  final String id;
  final String name;
  final String category;
  final String description;
  final double price;
  final String unit;
  final IconData icon;
  final bool isAvailable;

  const Product({
    required this.id,
    required this.name,
    required this.category,
    required this.description,
    required this.price,
    required this.unit,
    required this.icon,
    this.isAvailable = true,
  });
}
