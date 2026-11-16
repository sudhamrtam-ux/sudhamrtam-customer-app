import 'dart:async';

import 'package:flutter/foundation.dart';

import '../database/catalog_cache_service.dart';
import '../services/catalog_api_client.dart';
import 'product.dart';
import 'product_catalog.dart';
import 'product_photos.dart';

/// Where the current product list came from.
enum CatalogSource {
  /// The catalog compiled into the app (nothing cached yet,
  /// or the cache could not be read).
  builtIn,

  /// The last server catalog saved on this phone.
  cached,

  /// Fetched from the server during this session.
  server,
}

/// Single source of products for the Shop, product details
/// and the cart.
///
/// Every customer sees the same products at the same prices
/// (owner decision, 6 November 2026).
///
/// Startup reads only local data, so it never waits for the
/// network. [refresh] then fetches the catalog in the
/// background, when a server is configured.
class CatalogRepository extends ChangeNotifier {
  CatalogRepository({
    CatalogCacheService? cache,
    CatalogApiClient? api,
    List<Product> builtInProducts = ProductCatalog.products,
  }) : _cache = cache ?? CatalogCacheService.instance,
       // Named parameters cannot be private initializing formals.
       // ignore: prefer_initializing_formals
       _api = api,
       _builtIn = List.unmodifiable(builtInProducts) {
    _useBuiltIn();
  }

  /// Cache row used for the single shared catalog.
  static const String cacheKey = 'all';

  final CatalogCacheService _cache;
  final CatalogApiClient? _api;
  final List<Product> _builtIn;

  CatalogSource _source = CatalogSource.builtIn;

  /// Products shown in the Shop, in display order.
  List<Product> _products = const [];

  /// Every product this phone knows about (built-in plus the
  /// cached catalog), used to recognise cart items that are
  /// no longer sold.
  Map<String, Product> _knownProducts = const {};

  Future<void>? _initialization;
  Future<bool>? _refreshing;
  Object? _lastRefreshError;

  CatalogSource get source => _source;
  List<Product> get products => _products;

  /// True when this build is configured to use the server.
  bool get canUseServer => _api != null;

  bool get isRefreshing => _refreshing != null;

  /// The error from the last failed refresh, if any.
  Object? get lastRefreshError => _lastRefreshError;

  // =====================================================
  // LOCAL STARTUP
  // =====================================================

  /// Loads the cached catalog, if any.
  ///
  /// Never throws: if local data cannot be read, the
  /// built-in catalog is used so the app can still start.
  Future<void> initialize() => _initialization ??= _loadLocal();

  Future<void> _loadLocal() async {
    try {
      final cached = await _cache.loadCatalog(cacheKey);

      if (cached == null) {
        _useBuiltIn();
      } else {
        _apply(cached.products, CatalogSource.cached);
      }
    } catch (error) {
      debugPrint('Catalog cache could not be read: $error');
      _useBuiltIn();
    }

    notifyListeners();
  }

  // =====================================================
  // SERVER
  // =====================================================

  /// Fetches the catalog and saves it on the phone.
  ///
  /// Returns true when the fetched catalog was applied.
  /// Returns false (keeping the current products) when no
  /// server is configured or the fetch fails; the error is
  /// available in [lastRefreshError]. Concurrent calls share
  /// one request.
  Future<bool> refresh() {
    final api = _api;
    if (api == null) return Future.value(false);

    return _refreshing ??= _refresh(api);
  }

  Future<bool> _refresh(CatalogApiClient api) async {
    notifyListeners();

    try {
      final products = await api.fetchCatalog();

      await _cache.saveCatalog(
        CachedCatalog(
          areaId: cacheKey,
          areaName: 'All areas',
          fetchedAt: DateTime.now().toUtc(),
          products: products,
        ),
      );

      _apply(products, CatalogSource.server);
      _lastRefreshError = null;
      return true;
    } catch (error) {
      debugPrint('Catalog refresh failed: $error');
      _lastRefreshError = error;
      return false;
    } finally {
      _refreshing = null;
      notifyListeners();
    }
  }

  // =====================================================
  // INTERNAL STATE
  // =====================================================

  void _apply(List<CatalogProductData> items, CatalogSource source) {
    final products = [for (final item in items) item.toProduct()];

    // Keep built-in products known, so cart items for products
    // the server no longer sells show as unavailable.
    _knownProducts = {
      for (final product in _builtIn) product.id: product,
      for (final product in products) product.id: product,
    };
    _products = List.unmodifiable(products);
    _source = source;
    setProductPhotoUrls({
      for (final item in items)
        if (item.photoUrl != null) item.id: item.photoUrl!,
    });
    _setOtherSizes(products);
  }

  static void _setOtherSizes(List<Product> products) {
    productOtherSizes = {
      for (final sizes in productsByName(products))
        for (final p in sizes)
          p.id: [
            for (final other in sizes)
              if (other.id != p.id) other.id,
          ],
    };
  }

  void _useBuiltIn() {
    setProductPhotoUrls(const {});
    _source = CatalogSource.builtIn;
    _products = _builtIn;
    _setOtherSizes(_builtIn);
    _knownProducts = {for (final product in _builtIn) product.id: product};
  }

  // =====================================================
  // LOOKUP
  // =====================================================

  /// Resolves a product ID for the cart.
  ///
  /// - In the current catalog: that product and price.
  /// - Known but no longer sold: the product marked unavailable.
  /// - Never seen: null (the cart shows a placeholder).
  Product? productById(String id) {
    for (final product in _products) {
      if (product.id == id) return product;
    }

    return _knownProducts[id]?.copyWith(isAvailable: false);
  }
}

/// The products grouped by name, in catalog order: one entry per
/// product, holding all its sizes (Honey 250 g, 500 g and 1 kg).
List<List<Product>> productsByName(List<Product> products) {
  final groups = <String, List<Product>>{};
  for (final product in products) {
    (groups[product.name] ??= []).add(product);
  }
  return groups.values.toList();
}

/// A product's main size (owner decision 2026-11-16): 1 L or 1 kg when
/// sold in it (Buffalo Milk 1 L, not 500 ml), else the first size.
Product mainSize(List<Product> sizes) =>
    sizes
        .where(
          (p) => const {'1 l', '1 kg'}.contains(
            p.unit.trim().toLowerCase().replaceAll(RegExp(r'\s+'), ' '),
          ),
        )
        .firstOrNull ??
    sizes.first;
