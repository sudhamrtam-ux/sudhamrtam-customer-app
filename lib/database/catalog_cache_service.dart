import 'dart:convert';

import 'package:sqflite/sqflite.dart';

import '../models/product.dart';
import 'milk_database_service.dart';

/// One product as sent by `GET /v1/catalog` (prices in paise).
class CatalogProductData {
  final String id;
  final String name;
  final String category;
  final String description;
  final String unitLabel;
  final int pricePaise;
  final bool isAvailable;

  const CatalogProductData({
    required this.id,
    required this.name,
    required this.category,
    required this.description,
    required this.unitLabel,
    required this.pricePaise,
    required this.isAvailable,
  });

  factory CatalogProductData.fromJson(Map<String, Object?> json) {
    final pricePaise = json['price_paise'];

    if (pricePaise is! int || pricePaise <= 0) {
      throw FormatException('Invalid price for product ${json['id']}.');
    }

    return CatalogProductData(
      id: json['id'] as String,
      name: json['name'] as String,
      category: json['category'] as String,
      description: (json['description'] as String?) ?? '',
      unitLabel: json['unit_label'] as String,
      pricePaise: pricePaise,
      isAvailable: (json['is_available'] as bool?) ?? true,
    );
  }

  Map<String, Object?> toJson() => {
    'id': id,
    'name': name,
    'category': category,
    'description': description,
    'unit_label': unitLabel,
    'price_paise': pricePaise,
    'is_available': isAvailable,
  };

  Product toProduct() {
    return Product(
      id: id,
      name: name,
      category: category,
      description: description,
      // Paise are exact integers; rupees are only for display
      // and for the existing app price model.
      price: pricePaise / 100,
      unit: unitLabel,
      icon: productIconFor(id, category),
      isAvailable: isAvailable,
    );
  }
}

/// The last catalog received for one delivery area.
class CachedCatalog {
  final String areaId;
  final String areaName;
  final DateTime fetchedAt;
  final List<CatalogProductData> products;

  CachedCatalog({
    required this.areaId,
    required this.areaName,
    required this.fetchedAt,
    required List<CatalogProductData> products,
  }) : products = List.unmodifiable(products);
}

/// Local SQLite storage for server catalogs (schema v9).
///
/// Rows are keyed by `area_id`. Prices are the same in every
/// area, so the app uses a single row
/// (`CatalogRepository.cacheKey`); the column is kept so the
/// schema does not need to change.
class CatalogCacheService {
  CatalogCacheService._();

  static final CatalogCacheService instance = CatalogCacheService._();

  Future<Database> get _db => MilkDatabaseService.instance.database;

  /// Replaces the cached catalog stored under its key.
  Future<void> saveCatalog(CachedCatalog catalog) async {
    final db = await _db;

    await db.insert(MilkDatabaseService.catalogCacheTable, {
      'area_id': catalog.areaId,
      'area_name': catalog.areaName,
      'payload': jsonEncode([for (final p in catalog.products) p.toJson()]),
      'fetched_at': catalog.fetchedAt.toUtc().toIso8601String(),
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  /// Returns the cached catalog stored under [areaId], or null.
  Future<CachedCatalog?> loadCatalog(String areaId) async {
    final db = await _db;

    final rows = await db.query(
      MilkDatabaseService.catalogCacheTable,
      where: 'area_id = ?',
      whereArgs: [areaId],
      limit: 1,
    );

    if (rows.isEmpty) return null;
    return _decode(rows.first);
  }

  CachedCatalog _decode(Map<String, Object?> row) {
    final list = jsonDecode(row['payload'] as String) as List<Object?>;

    return CachedCatalog(
      areaId: row['area_id'] as String,
      areaName: row['area_name'] as String,
      fetchedAt: DateTime.parse(row['fetched_at'] as String),
      products: [
        for (final item in list)
          CatalogProductData.fromJson(Map<String, Object?>.from(item as Map)),
      ],
    );
  }
}
