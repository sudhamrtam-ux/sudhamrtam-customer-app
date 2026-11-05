import 'package:flutter/foundation.dart';

import '../database/cart_database_service.dart';
import 'cart_item.dart';
import 'product.dart';
import 'product_catalog.dart';

/// Manages Sudhamrtam Shopping Cart state and SQLite persistence.
class CartManager extends ChangeNotifier {
  final Map<String, CartItem> _items = {};

  static const int maxQuantityPerProduct = 100;

  bool _isInitialized = false;
  bool _isLoading = false;
  bool _isCheckoutLocked = false;

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
  bool get isCheckoutLocked => _isCheckoutLocked;

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
  /// Call this before runApp() in main.dart.
  Future<void> initialize() {
    return _initializationFuture ??= _loadSavedCart();
  }

  Future<void> _loadSavedCart() async {
    _isLoading = true;
    notifyListeners();

    try {
      final savedItems = await CartDatabaseService.instance.loadCart();
      final productsById = {
        for (final product in ProductCatalog.products) product.id: product,
      };

      _items.clear();

      for (final entry in savedItems.entries) {
        final product = productsById[entry.key];
        final quantity = entry.value;

        if (product == null ||
            quantity < 1 ||
            quantity > maxQuantityPerProduct) {
          continue;
        }

        _items[entry.key] = CartItem(product: product, quantity: quantity);
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

  /// Queues a complete cart snapshot for persistence.
  ///
  /// Existing behavior is retained. Save errors are logged, not propagated.
  /// A later step will add explicit persistence-failure reporting before
  /// checkout is permitted to finalize.

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
  // CHECKOUT CART LOCK
  // ==========================================

  /// Prevents new cart mutations immediately, then drains queued saves.
  ///
  /// Returns false when the cart is unavailable or already locked.
  /// The caller must release a successful lock with endCheckoutCartLock().
  ///
  /// IMPORTANT: Draining does not prove that all saves succeeded, because
  /// _scheduleSave currently logs and swallows persistence errors. Do not
  /// use this method alone to authorize an order or clear the cart.
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

  /// Releases the checkout lock. Does not change cart quantities.
  void endCheckoutCartLock() {
    if (!_isCheckoutLocked) return;
    _isCheckoutLocked = false;
    notifyListeners();
  }

  // ==========================================
  // ADD PRODUCT
  // ==========================================

  bool addProduct(Product product, {int quantity = 1}) {
    if (!_isInitialized || _isCheckoutLocked || quantity <= 0) {
      return false;
    }

    final currentQuantity = quantityFor(product.id);
    if (currentQuantity + quantity > maxQuantityPerProduct) {
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
    if (!_isInitialized || _isCheckoutLocked) return false;

    final existing = _items[productId];
    if (existing == null || existing.quantity >= maxQuantityPerProduct) {
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
    if (!_isInitialized || _isCheckoutLocked) return false;

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
    if (!_isInitialized || _isCheckoutLocked) return false;

    final existing = _items[productId];
    if (existing == null || quantity < 0 || quantity > maxQuantityPerProduct) {
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
    if (!_isInitialized ||
        _isCheckoutLocked ||
        !_items.containsKey(productId)) {
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
    if (!_isInitialized || _isCheckoutLocked || _items.isEmpty) {
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
  /// Requires the checkout lock to remain active so
  /// no cart mutation can occur during synchronization.
  Future<void> refreshAfterCheckoutReconciliation() async {
    if (!_isInitialized || !_isCheckoutLocked) {
      throw StateError(
        'Cart refresh requires an initialized, '
        'checkout-locked cart.',
      );
    }

    // All queued cart saves must have finished before
    // the reconciled SQLite state can be loaded.
    await waitForPendingSaves();

    final savedItems = await CartDatabaseService.instance.loadCart();

    final productsById = {
      for (final product in ProductCatalog.products) product.id: product,
    };

    final refreshedItems = <String, CartItem>{};

    for (final entry in savedItems.entries) {
      final product = productsById[entry.key];
      final quantity = entry.value;

      if (product == null || quantity < 1 || quantity > maxQuantityPerProduct) {
        throw StateError('Cannot refresh cart: invalid persisted cart item.');
      }

      refreshedItems[entry.key] = CartItem(
        product: product,
        quantity: quantity,
      );
    }

    // Only replace the in-memory cart after the entire
    // SQLite snapshot has been loaded and validated.
    _items
      ..clear()
      ..addAll(refreshedItems);

    _lastPersistenceError = null;

    notifyListeners();
  }
}
