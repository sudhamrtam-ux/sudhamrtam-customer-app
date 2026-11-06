import 'dart:async';

import 'package:flutter/foundation.dart';

import '../database/catalog_cache_service.dart';
import '../services/catalog_api_client.dart';
import 'product.dart';
import 'product_catalog.dart';

/// Where the current product list came from.
enum CatalogSource {
  /// The catalog compiled into the app (no area selected,
  /// nothing cached, or the cache could not be read).
  builtIn,

  /// The last server catalog saved on this phone.
  cached,

  /// Fetched from the server during this session.
  server,
}

/// Single source of products for the Shop, product details
/// and the cart.
///
/// Startup reads only local data, so it never waits for the
/// network. [refresh] then fetches the selected area's
/// catalog in the background, when a server is configured.
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

  final CatalogCacheService _cache;
  final CatalogApiClient? _api;
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
  Future<bool>? _refreshing;
  String? _refreshingAreaId;
  Object? _lastRefreshError;

  CatalogSource get source => _source;
  String? get selectedAreaId => _selectedAreaId;
  String? get selectedAreaName => _selectedAreaName;
  List<Product> get products => _products;

  /// True when this build is configured to use the server.
  bool get canUseServer => _api != null;

  bool get isRefreshing => _refreshing != null;

  /// The error from the last failed refresh, if any.
  Object? get lastRefreshError => _lastRefreshError;

  // =====================================================
  // LOCAL STARTUP
  // =====================================================

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

      _knownProducts = known;

      final selected = areaId == null
          ? null
          : allCached.where((c) => c.areaId == areaId).firstOrNull;

      if (selected == null) {
        _useBuiltIn(keepKnown: true);
        _selectedAreaId = areaId;
      } else {
        _apply(
          areaId: selected.areaId,
          areaName: selected.areaName,
          items: selected.products,
          source: CatalogSource.cached,
        );
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

  /// Delivery areas offered by the server.
  Future<List<DeliveryArea>> fetchAreas() {
    final api = _api;

    if (api == null) {
      throw StateError('No server is configured for this build.');
    }

    return api.fetchAreas();
  }

  /// Makes [area] the customer's delivery area.
  ///
  /// Its cached catalog (if any) is shown immediately, then
  /// a fresh catalog is fetched.
  Future<bool> selectArea(DeliveryArea area) async {
    // Record the selection before any await, so a response
    // for the previous area arriving meanwhile is ignored.
    _selectedAreaId = area.id;
    _selectedAreaName = area.name;

    await _cache.setSelectedAreaId(area.id);

    final cached = await _cache.loadCatalog(area.id);

    // A newer selection was made while this one was loading.
    if (_selectedAreaId != area.id) return false;

    if (cached != null) {
      _apply(
        areaId: cached.areaId,
        areaName: cached.areaName,
        items: cached.products,
        source: CatalogSource.cached,
      );
    }

    notifyListeners();

    return refresh();
  }

  /// Fetches the selected area's catalog and saves it.
  ///
  /// Returns true when the fetched catalog was applied.
  /// Returns false (keeping the current products) when no
  /// server or area is configured, when the fetch fails (see
  /// [lastRefreshError]), or when the area changed meanwhile.
  ///
  /// Concurrent calls for the same area share one request; a
  /// call for a newly selected area always starts its own.
  Future<bool> refresh() {
    final api = _api;
    final areaId = _selectedAreaId;

    if (api == null || areaId == null) return Future.value(false);

    final inFlight = _refreshing;
    if (inFlight != null && _refreshingAreaId == areaId) return inFlight;

    _refreshingAreaId = areaId;
    return _refreshing = _refresh(api, areaId);
  }

  Future<bool> _refresh(CatalogApiClient api, String areaId) async {
    notifyListeners();

    try {
      final catalog = await api.fetchCatalog(areaId);

      await _cache.saveCatalog(
        CachedCatalog(
          areaId: catalog.area.id,
          areaName: catalog.area.name,
          fetchedAt: DateTime.now().toUtc(),
          products: catalog.products,
        ),
      );

      // The customer may have switched area while waiting:
      // remember the products, but do not show them.
      if (_selectedAreaId != areaId) {
        _rememberKnown(catalog.products);
        return false;
      }

      _apply(
        areaId: catalog.area.id,
        areaName: catalog.area.name,
        items: catalog.products,
        source: CatalogSource.server,
      );

      _lastRefreshError = null;
      return true;
    } catch (error) {
      debugPrint('Catalog refresh failed: $error');
      if (_selectedAreaId == areaId) _lastRefreshError = error;
      return false;
    } finally {
      if (_refreshingAreaId == areaId) {
        _refreshing = null;
        _refreshingAreaId = null;
      }
      notifyListeners();
    }
  }

  // =====================================================
  // INTERNAL STATE
  // =====================================================

  void _apply({
    required String areaId,
    required String areaName,
    required List<CatalogProductData> items,
    required CatalogSource source,
  }) {
    final products = [for (final item in items) item.toProduct()];
    final known = Map<String, Product>.of(_knownProducts);

    for (final product in products) {
      known[product.id] = product;
    }

    _source = source;
    _selectedAreaId = areaId;
    _selectedAreaName = areaName;
    _products = List.unmodifiable(products);
    _knownProducts = known;
  }

  /// Adds products from another area's catalog to the known
  /// products, without changing what is shown.
  void _rememberKnown(List<CatalogProductData> items) {
    final known = Map<String, Product>.of(_knownProducts);

    for (final item in items) {
      known.putIfAbsent(item.id, item.toProduct);
    }

    _knownProducts = known;
  }

  void _useBuiltIn({bool keepKnown = false}) {
    _source = CatalogSource.builtIn;
    _selectedAreaName = null;
    _products = _builtIn;

    if (!keepKnown) {
      _knownProducts = {for (final product in _builtIn) product.id: product};
    }
  }

  // =====================================================
  // LOOKUP
  // =====================================================

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
