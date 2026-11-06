import 'package:flutter/foundation.dart';

import '../database/catalog_cache_service.dart';
import 'product.dart';
import 'product_catalog.dart';

/// Where the current product list came from.
enum CatalogSource {
  /// The catalog compiled into the app (no area selected,
  /// nothing cached, or the cache could not be read).
  builtIn,

  /// The last server catalog saved on this phone.
  cached,
}

/// Single source of products for the Shop, product details
/// and the cart.
///
/// Startup reads only local data, so it never waits for the
/// network. Fetching fresh catalogs from the server is added
/// in a later step.
class CatalogRepository extends ChangeNotifier {
  CatalogRepository({
    CatalogCacheService? cache,
    List<Product> builtInProducts = ProductCatalog.products,
  }) : _cache = cache ?? CatalogCacheService.instance,
       _builtIn = List.unmodifiable(builtInProducts) {
    _useBuiltIn();
  }

  final CatalogCacheService _cache;
  final List<Product> _builtIn;

  CatalogSource _source = CatalogSource.builtIn;
  String? _selectedAreaId;
  String? _selectedAreaName;

  /// Products sold in the selected area, in display order.
  List<Product> _products = const [];

  /// Every product this phone knows about (built-in plus all
  /// cached areas), used to recognise cart items that are
  /// not sold in the selected area.
  Map<String, Product> _knownProducts = const {};

  Future<void>? _initialization;

  CatalogSource get source => _source;
  String? get selectedAreaId => _selectedAreaId;
  String? get selectedAreaName => _selectedAreaName;
  List<Product> get products => _products;

  /// Loads the selected area and its cached catalog.
  ///
  /// Never throws: if local data cannot be read, the
  /// built-in catalog is used so the app can still start.
  Future<void> initialize() => _initialization ??= _loadLocal();

  Future<void> _loadLocal() async {
    try {
      final areaId = await _cache.getSelectedAreaId();
      final allCached = await _cache.loadAllCatalogs();

      final known = <String, Product>{
        for (final product in _builtIn) product.id: product,
      };

      for (final catalog in allCached) {
        for (final item in catalog.products) {
          known[item.id] = item.toProduct();
        }
      }

      final selected = areaId == null
          ? null
          : allCached.where((c) => c.areaId == areaId).firstOrNull;

      if (selected == null) {
        _useBuiltIn();
        _selectedAreaId = areaId;
        _knownProducts = Map.unmodifiable(known);
      } else {
        final products = [for (final p in selected.products) p.toProduct()];

        for (final product in products) {
          known[product.id] = product;
        }

        _source = CatalogSource.cached;
        _selectedAreaId = selected.areaId;
        _selectedAreaName = selected.areaName;
        _products = List.unmodifiable(products);
        _knownProducts = Map.unmodifiable(known);
      }
    } catch (error) {
      debugPrint('Catalog cache could not be read: $error');
      _useBuiltIn();
    }

    notifyListeners();
  }

  void _useBuiltIn() {
    _source = CatalogSource.builtIn;
    _selectedAreaName = null;
    _products = _builtIn;
    _knownProducts = {for (final product in _builtIn) product.id: product};
  }

  /// Resolves a product ID for the cart.
  ///
  /// - Sold in the selected area: that area's product and price.
  /// - Known but not sold here: the product marked unavailable.
  /// - Never seen: null (the cart shows a placeholder).
  Product? productById(String id) {
    for (final product in _products) {
      if (product.id == id) return product;
    }

    return _knownProducts[id]?.copyWith(isAvailable: false);
  }
}
