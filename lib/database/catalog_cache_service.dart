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

/// Local SQLite storage for server catalogs and the
/// customer's selected delivery area (schema v9).
class CatalogCacheService {
  CatalogCacheService._();

  static final CatalogCacheService instance = CatalogCacheService._();

  static const String selectedAreaIdKey = 'selected_area_id';

  Future<Database> get _db => MilkDatabaseService.instance.database;

  /// Replaces the cached catalog for an area.
  Future<void> saveCatalog(CachedCatalog catalog) async {
    final db = await _db;

    await db.insert(MilkDatabaseService.catalogCacheTable, {
      'area_id': catalog.areaId,
      'area_name': catalog.areaName,
      'payload': jsonEncode([for (final p in catalog.products) p.toJson()]),
      'fetched_at': catalog.fetchedAt.toUtc().toIso8601String(),
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  /// Returns the cached catalog for [areaId], or null.
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

  /// Returns every cached catalog (used to recognise cart
  /// products that are sold in a different area).
  Future<List<CachedCatalog>> loadAllCatalogs() async {
    final db = await _db;
    final rows = await db.query(MilkDatabaseService.catalogCacheTable);
    return [for (final row in rows) _decode(row)];
  }

  Future<String?> getSelectedAreaId() async {
    final db = await _db;

    final rows = await db.query(
      MilkDatabaseService.appSettingsTable,
      columns: ['value'],
      where: 'key = ?',
      whereArgs: [selectedAreaIdKey],
      limit: 1,
    );

    return rows.isEmpty ? null : rows.first['value'] as String;
  }

  Future<void> setSelectedAreaId(String areaId) async {
    if (areaId.trim().isEmpty) {
      throw ArgumentError('Area ID cannot be empty.');
    }

    final db = await _db;

    await db.insert(MilkDatabaseService.appSettingsTable, {
      'key': selectedAreaIdKey,
      'value': areaId,
    }, conflictAlgorithm: ConflictAlgorithm.replace);
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
