import 'package:flutter/foundation.dart';

import '../database/cart_database_service.dart';
import 'cart_item.dart';
import 'product.dart';
import 'product_catalog.dart';

/// Resolves a saved product ID to a product, or null if unknown.
typedef ProductLookup = Product? Function(String productId);

/// Manages Sudhamrtam Shopping Cart state and SQLite persistence.
class CartManager extends ChangeNotifier {
  /// [productLookup] resolves saved cart rows to products.
  /// The app passes `CatalogRepository.productById`; when
  /// omitted, the built-in catalog is used.
  CartManager({ProductLookup? productLookup})
    : _productLookup = productLookup ?? _builtInLookup;

  static Product? _builtInLookup(String productId) {
    for (final product in ProductCatalog.products) {
      if (product.id == productId) return product;
    }
    return null;
  }

  final ProductLookup _productLookup;

  /// Unknown IDs become an unavailable placeholder, so a
  /// saved item is never silently deleted from the cart.
  Product _resolveProduct(String productId) =>
      _productLookup(productId) ?? Product.unknown(productId);

  final Map<String, CartItem> _items = {};

  /// Set when a catalog update arrived during checkout;
  /// applied as soon as the checkout locks are released.
  bool _productsStale = false;

  static const int maxQuantityPerProduct = 100;

  /// The most of [product] the cart may hold.
  static int maxQuantityOf(Product product) =>
      product.maxQuantity ?? maxQuantityPerProduct;

  bool _isInitialized = false;
  bool _isLoading = false;

  // Active checkout processing lock.
  bool _isCheckoutLocked = false;

  // Protects the cart while a durable checkout
  // remains unresolved during the current session.
  bool _isCheckoutRecoveryLocked = false;

  Future<void>? _initializationFuture;

  // Database operations execute sequentially.
  Future<void> _pendingSave = Future<void>.value();

  Object? _lastPersistenceError;

  bool get hasPersistenceError => _lastPersistenceError != null;

  // ==========================================
  // CART STATUS
  // ==========================================

  bool get isInitialized => _isInitialized;

  bool get isLoading => _isLoading;

  /// True whenever cart mutations must be blocked.
  ///
  /// This includes active checkout processing and
  /// unresolved checkout recovery.
  bool get isCheckoutLocked => _isCheckoutLocked || _isCheckoutRecoveryLocked;

  bool get isCheckoutRecoveryLocked => _isCheckoutRecoveryLocked;

  List<CartItem> get items => List<CartItem>.unmodifiable(_items.values);

  int get uniqueItemCount => _items.length;

  int get itemCount => totalQuantity;

  int get totalQuantity =>
      _items.values.fold<int>(0, (total, item) => total + item.quantity);

  double get subtotal =>
      _items.values.fold<double>(0.0, (total, item) => total + item.totalPrice);

  bool get isEmpty => _items.isEmpty;

  bool get isNotEmpty => _items.isNotEmpty;

  int quantityFor(String productId) => _items[productId]?.quantity ?? 0;

  // ==========================================
  // SQLITE INITIALIZATION
  // ==========================================

  /// Restores the saved Shopping Cart from SQLite.
  ///
  /// Startup recovery must be completed before this
  /// method is called.
  Future<void> initialize() {
    return _initializationFuture ??= _loadSavedCart();
  }

  Future<void> _loadSavedCart() async {
    _isLoading = true;
    notifyListeners();

    try {
      final savedItems = await CartDatabaseService.instance.loadCart();

      _items.clear();

      for (final entry in savedItems.entries) {
        final quantity = entry.value;

        if (quantity < 1 || quantity > maxQuantityPerProduct) {
          continue;
        }

        _items[entry.key] = CartItem(
          product: _resolveProduct(entry.key),
          quantity: quantity,
        );
      }

      _isInitialized = true;
    } catch (error) {
      _isInitialized = false;
      _initializationFuture = null;

      debugPrint('Cart initialization failed: $error');
      rethrow;
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  // ==========================================
  // SQLITE SAVE QUEUE
  // ==========================================

  /// Queues an atomic snapshot of the current cart.
  ///
  /// Each snapshot is saved in one SQLite transaction.
  /// A failed snapshot is rolled back without partially
  /// modifying the persisted cart.
  ///
  /// Persistence errors remain visible to the checkout lock.
  void _scheduleSave() {
    if (!_isInitialized) return;

    final snapshot = {
      for (final item in _items.values) item.product.id: item.quantity,
    };

    _pendingSave = _pendingSave.then((_) async {
      try {
        await CartDatabaseService.instance.saveCartSnapshot(snapshot);

        _lastPersistenceError = null;
      } catch (error) {
        _lastPersistenceError = error;

        debugPrint('Cart SQLite save failed: $error');
      }
    });
  }

  Future<void> waitForPendingSaves() async {
    await _pendingSave;
  }

  void _notifyAndSave() {
    notifyListeners();
    _scheduleSave();
  }

  // ==========================================
  // ACTIVE CHECKOUT CART LOCK
  // ==========================================

  /// Prevents new cart mutations immediately, then
  /// waits for queued SQLite saves to finish.
  ///
  /// Returns false when the cart is unavailable or
  /// already being processed.
  ///
  /// The caller must release a successful lock with
  /// endCheckoutCartLock().
  Future<bool> beginCheckoutCartLock() async {
    if (!_isInitialized || _isLoading || _isCheckoutLocked) {
      return false;
    }

    _isCheckoutLocked = true;
    notifyListeners();

    try {
      await waitForPendingSaves();

      if (_lastPersistenceError != null) {
        throw StateError(
          'Checkout cannot proceed because cart persistence failed: '
          '$_lastPersistenceError',
        );
      }

      return true;
    } catch (_) {
      _isCheckoutLocked = false;
      notifyListeners();
      rethrow;
    }
  }

  /// Releases the temporary active checkout lock.
  ///
  /// Does not release the separate recovery lock.
  void endCheckoutCartLock() {
    if (!_isCheckoutLocked) return;

    _isCheckoutLocked = false;
    notifyListeners();
    _applyDeferredProductRefresh();
  }

  // ==========================================
  // CHECKOUT RECOVERY LOCK
  // ==========================================

  /// Blocks cart mutations while a durable checkout
  /// remains unresolved.
  ///
  /// The checkout coordinator must activate this
  /// after durable preparation succeeds.
  ///
  /// This is a session-local lock. After application
  /// restart, startup recovery must inspect SQLite
  /// before normal cart initialization.
  void beginCheckoutRecoveryLock() {
    if (_isCheckoutRecoveryLocked) return;

    _isCheckoutRecoveryLocked = true;
    notifyListeners();
  }

  /// Releases the recovery lock after checkout has
  /// been safely resolved.
  ///
  /// Do not call merely because order submission failed.
  void endCheckoutRecoveryLock() {
    if (!_isCheckoutRecoveryLocked) return;

    _isCheckoutRecoveryLocked = false;
    notifyListeners();
    _applyDeferredProductRefresh();
  }

  // ==========================================
  // CATALOG UPDATES (PRICES / AVAILABILITY)
  // ==========================================

  /// Re-resolves every cart item's product through the
  /// catalog lookup, updating prices and availability.
  ///
  /// Quantities are unchanged and nothing is written to
  /// SQLite (the cart stores only product IDs and
  /// quantities).
  ///
  /// Deferred while any checkout lock is active, so an
  /// order being placed never sees prices change mid-way.
  void refreshProducts() {
    if (!_isInitialized) return;

    if (isCheckoutLocked) {
      _productsStale = true;
      return;
    }

    _productsStale = false;
    var changed = false;

    for (final entry in _items.entries.toList()) {
      final current = entry.value.product;
      final updated = _resolveProduct(entry.key);

      if (updated.price != current.price ||
          updated.isAvailable != current.isAvailable ||
          updated.name != current.name ||
          updated.unit != current.unit) {
        _items[entry.key] = CartItem(
          product: updated,
          quantity: entry.value.quantity,
        );
        changed = true;
      }
    }

    if (changed) notifyListeners();
  }

  void _applyDeferredProductRefresh() {
    if (_productsStale && !isCheckoutLocked) {
      refreshProducts();
    }
  }

  // ==========================================
  // ADD PRODUCT
  // ==========================================

  bool addProduct(Product product, {int quantity = 1}) {
    if (!_isInitialized ||
        isCheckoutLocked ||
        quantity <= 0 ||
        !product.isAvailable) {
      return false;
    }

    final currentQuantity = quantityFor(product.id);

    if (currentQuantity + quantity > maxQuantityOf(product)) {
      return false;
    }

    _items[product.id] = CartItem(
      product: product,
      quantity: currentQuantity + quantity,
    );

    _notifyAndSave();
    return true;
  }

  // ==========================================
  // INCREASE QUANTITY
  // ==========================================

  bool increaseQuantity(String productId) {
    if (!_isInitialized || isCheckoutLocked) return false;

    final existing = _items[productId];

    if (existing == null ||
        !existing.product.isAvailable ||
        existing.quantity >= maxQuantityOf(existing.product)) {
      return false;
    }

    _items[productId] = existing.copyWith(quantity: existing.quantity + 1);

    _notifyAndSave();
    return true;
  }

  // ==========================================
  // DECREASE QUANTITY
  // ==========================================

  bool decreaseQuantity(String productId) {
    if (!_isInitialized || isCheckoutLocked) return false;

    final existing = _items[productId];

    if (existing == null) return false;

    if (existing.quantity == 1) {
      _items.remove(productId);
    } else {
      _items[productId] = existing.copyWith(quantity: existing.quantity - 1);
    }

    _notifyAndSave();
    return true;
  }

  // ==========================================
  // UPDATE QUANTITY
  // ==========================================

  bool updateQuantity(String productId, int quantity) {
    if (!_isInitialized || isCheckoutLocked) return false;

    final existing = _items[productId];

    if (existing == null || quantity < 0 || quantity > maxQuantityPerProduct) {
      return false;
    }

    // Unavailable products can only be reduced or removed.
    if (!existing.product.isAvailable && quantity > existing.quantity) {
      return false;
    }
    if (quantity > existing.quantity &&
        quantity > maxQuantityOf(existing.product)) {
      return false;
    }

    if (quantity == 0) {
      _items.remove(productId);
    } else {
      _items[productId] = existing.copyWith(quantity: quantity);
    }

    _notifyAndSave();
    return true;
  }

  // ==========================================
  // REMOVE PRODUCT
  // ==========================================

  bool removeProduct(String productId) {
    if (!_isInitialized || isCheckoutLocked || !_items.containsKey(productId)) {
      return false;
    }

    _items.remove(productId);

    _notifyAndSave();
    return true;
  }

  // ==========================================
  // CLEAR CART
  // ==========================================

  void clearCart() {
    if (!_isInitialized || isCheckoutLocked || _items.isEmpty) {
      return;
    }

    _items.clear();
    _notifyAndSave();
  }

  // ==========================================
  // REFRESH CART AFTER CHECKOUT
  // ==========================================

  /// Refreshes the in-memory cart from SQLite after
  /// successful checkout reconciliation.
  ///
  /// Does not write anything to SQLite.
  ///
  /// Requires the active checkout processing lock
  /// so cart mutations cannot occur during refresh.
  Future<void> refreshAfterCheckoutReconciliation() async {
    if (!_isInitialized || !_isCheckoutLocked) {
      throw StateError(
        'Cart refresh requires an initialized, '
        'checkout-locked cart.',
      );
    }

    // All queued cart saves must finish before the
    // reconciled SQLite state can be loaded.
    await waitForPendingSaves();

    final savedItems = await CartDatabaseService.instance.loadCart();

    final refreshedItems = <String, CartItem>{};

    for (final entry in savedItems.entries) {
      final quantity = entry.value;

      if (quantity < 1 || quantity > maxQuantityPerProduct) {
        throw StateError('Cannot refresh cart: invalid persisted cart item.');
      }

      refreshedItems[entry.key] = CartItem(
        product: _resolveProduct(entry.key),
        quantity: quantity,
      );
    }

    // Replace memory only after the complete SQLite
    // snapshot has been loaded and validated.
    _items
      ..clear()
      ..addAll(refreshedItems);

    _lastPersistenceError = null;

    notifyListeners();
  }
}
