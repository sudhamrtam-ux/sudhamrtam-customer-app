import 'dart:async';

import 'package:flutter/material.dart';

import '../../app/sudhamrtam_app.dart';
import '../../models/cart_manager.dart';
import '../../models/catalog_repository.dart';
import '../../models/product.dart';
import '../../services/catalog_api_client.dart' show apiBaseUrl;
import '../../services/offer_api_client.dart';
import '../../services/order_api_client.dart';
import '../checkout/order_destination.dart';
import '../shop/product_image.dart';
import 'offer_ticker.dart';

const _green = Color(0xFF82B440);
const _paleGreen = Color(0xFFF5F8F0);
const _borderGreen = Color(0xFFE1EBCF);

/// Loads the owner's order rules; null when there is no server.
typedef OrderRulesLoader = Future<OrderRules> Function();

OrderRulesLoader? _defaultRulesLoader() => OrderDestination.server?.fetchRules;

/// Loads today's offer texts; null when there is no server.
typedef OffersLoader = Future<List<String>> Function();

OffersLoader? _defaultOffersLoader() =>
    apiBaseUrl.isEmpty ? null : OfferApiClient(baseUrl: apiBaseUrl).fetchOffers;

/// Home tab: shortcuts into the shop, today's delivery cut-off,
/// one-tap adding of daily essentials, and the milk plan.
class HomeScreen extends StatefulWidget {
  HomeScreen({
    super.key,
    this.onOpenShop,
    this.onOpenMilkPlan,
    this.onOpenCart,
    this.catalog,
    this.cart,
    OrderRulesLoader? loadRules,
    OffersLoader? loadOffers,
    DateTime Function()? clock,
  }) : loadRules = loadRules ?? _defaultRulesLoader(),
       loadOffers = loadOffers ?? _defaultOffersLoader(),
       clock = clock ?? DateTime.now;

  /// Opens the Shop tab, filtered to [category] (null: all).
  final void Function(String? category)? onOpenShop;
  final VoidCallback? onOpenMilkPlan;
  final VoidCallback? onOpenCart;

  /// Overrides for tests; default to the app's catalog and cart.
  final CatalogRepository? catalog;
  final CartManager? cart;

  /// Null when the app has no server: the delivery card is hidden.
  final OrderRulesLoader? loadRules;

  /// Null when the app has no server: no offer line.
  final OffersLoader? loadOffers;
  final DateTime Function() clock;

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  OrderRules? _rules;
  List<String> _offers = const [];
  Timer? _ticker;

  CatalogRepository get _catalog => widget.catalog ?? sudhamrtamCatalog;
  CartManager get _cart => widget.cart ?? sudhamrtamCart;

  @override
  void initState() {
    super.initState();
    _loadRules();
    _loadOffers();
    // Keeps the "time left to order" current.
    _ticker = Timer.periodic(const Duration(minutes: 1), (_) {
      if (mounted && _rules != null) setState(() {});
    });
  }

  Future<void> _loadRules() async {
    final load = widget.loadRules;
    if (load == null) return;
    try {
      final rules = await load();
      if (mounted) setState(() => _rules = rules);
    } catch (_) {
      // Offline: the delivery card simply stays hidden.
    }
  }

  Future<void> _loadOffers() async {
    final load = widget.loadOffers;
    if (load == null) return;
    try {
      final offers = await load();
      if (mounted) setState(() => _offers = offers);
    } catch (_) {
      // Offline: keep what is shown (nothing on first load).
    }
  }

  @override
  void dispose() {
    _ticker?.cancel();
    super.dispose();
  }

  void _add(Product product) {
    final messenger = ScaffoldMessenger.of(context);
    final added = _cart.addProduct(product);
    messenger.hideCurrentSnackBar();
    messenger.showSnackBar(
      SnackBar(
        content: Text(
          added
              ? '${product.name} added to cart'
              : 'The cart cannot be changed right now.',
        ),
        duration: const Duration(seconds: 2),
        action: added && widget.onOpenCart != null
            ? SnackBarAction(
                label: 'VIEW CART',
                textColor: _green,
                onPressed: widget.onOpenCart!,
              )
            : null,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: Listenable.merge([_catalog, _cart]),
      builder: (context, _) {
        final products = _catalog.products;
        final essentials = products
            .where((p) => p.isAvailable && p.category == 'Fresh Dairy')
            .take(4)
            .toList();

        return SafeArea(
          child: Column(
            children: [
              if (_offers.isNotEmpty) OfferTicker(messages: _offers),
              Expanded(child: _scrollingBody(context, products, essentials)),
            ],
          ),
        );
      },
    );
  }

  Widget _scrollingBody(
    BuildContext context,
    List<Product> products,
    List<Product> essentials,
  ) {
    return RefreshIndicator(
      color: _green,
      onRefresh: () async {
        await Future.wait([_catalog.refresh(), _loadRules(), _loadOffers()]);
      },
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(16),
        children: [
          Text(
            'Welcome to Sudhamrtam',
            style: Theme.of(context).textTheme.headlineSmall
                ?.copyWith(fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          const Text('Pure farm goodness delivered to your doorstep.'),
          const SizedBox(height: 20),
          _HeroCard(onShopNow: () => widget.onOpenShop?.call(null)),
          if (_rules != null) ...[
            const SizedBox(height: 16),
            _DeliveryCard(rules: _rules!, now: widget.clock()),
          ],
          if (essentials.isNotEmpty) ...[
            const SizedBox(height: 28),
            _SectionTitle(
              'Daily Essentials',
              actionLabel: 'See all',
              onAction: () => widget.onOpenShop?.call('Fresh Dairy'),
            ),
            const SizedBox(height: 12),
            SizedBox(
              height: 290,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: essentials.length,
                separatorBuilder: (context, index) => const SizedBox(width: 12),
                itemBuilder: (context, index) {
                  final product = essentials[index];
                  return _QuickAddCard(
                    product: product,
                    quantity: _cart.quantityFor(product.id),
                    onAdd: () => _add(product),
                    onIncrease: () => _cart.increaseQuantity(product.id),
                    onDecrease: () => _cart.decreaseQuantity(product.id),
                  );
                },
              ),
            ),
          ],
          const SizedBox(height: 28),
          const _SectionTitle('Shop by Category'),
          const SizedBox(height: 12),
          _CategoryGrid(
            products: products,
            onOpen: (category) => widget.onOpenShop?.call(category),
          ),
          const SizedBox(height: 20),
          _MilkPlanCard(onTap: widget.onOpenMilkPlan),
          const SizedBox(height: 24),
          const Center(
            child: Text(
              'Purity • Tradition • Wellness',
              style: TextStyle(color: _green, fontWeight: FontWeight.w600),
            ),
          ),
        ],
      ),
    );
  }
}

// =====================================================
// HERO
// =====================================================

class _HeroCard extends StatelessWidget {
  const _HeroCard({required this.onShopNow});

  final VoidCallback onShopNow;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: _green,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Pure Goodness, Naturally',
            style: TextStyle(
              color: Colors.white,
              fontSize: 24,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 8),
          const Text(
            'Fresh dairy, natural honey and traditional wood-pressed oils.',
            style: TextStyle(color: Colors.white, fontSize: 15),
          ),
          const SizedBox(height: 16),
          FilledButton.icon(
            key: const Key('homeShopNow'),
            onPressed: onShopNow,
            style: FilledButton.styleFrom(
              backgroundColor: Colors.white,
              foregroundColor: _green,
            ),
            icon: const Icon(Icons.storefront_outlined),
            label: const Text(
              'Shop Now',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
          ),
        ],
      ),
    );
  }
}

// =====================================================
// DELIVERY CUT-OFF
// =====================================================

class _DeliveryCard extends StatelessWidget {
  const _DeliveryCard({required this.rules, required this.now});

  final OrderRules rules;
  final DateTime now;

  static const _days = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
  static const _months = [
    'Jan',
    'Feb',
    'Mar',
    'Apr',
    'May',
    'Jun',
    'Jul',
    'Aug',
    'Sep',
    'Oct',
    'Nov',
    'Dec',
  ];

  static String hourText(int hour) {
    final h = hour % 12 == 0 ? 12 : hour % 12;
    return '$h ${hour < 12 ? 'AM' : 'PM'}';
  }

  @override
  Widget build(BuildContext context) {
    // India time, as the server uses for the cut-off.
    final ist = now.toUtc().add(const Duration(hours: 5, minutes: 30));
    final cutoff = DateTime.utc(
      ist.year,
      ist.month,
      ist.day,
      rules.cutoffHourIst,
    );
    final left = cutoff.difference(ist);
    final cutoffText = hourText(rules.cutoffHourIst);

    final String title;
    final String detail;
    if (left > Duration.zero) {
      final hours = left.inHours;
      final minutes = left.inMinutes % 60;
      title = 'Order by $cutoffText for delivery tomorrow morning';
      detail = hours > 0
          ? '$hours h $minutes min left to order'
          : '$minutes min left to order';
    } else {
      final date = rules.deliveryDateFor(now);
      title =
          'Order now for delivery on '
          '${_days[date.weekday - 1]}, ${date.day} ${_months[date.month - 1]}';
      detail = "Today's $cutoffText cut-off has passed.";
    }

    final minimum = rules.minimumOrderRupees.toStringAsFixed(0);
    final terms = rules.deliveryFeePaise == 0
        ? 'Free delivery on orders of ₹$minimum or more'
        : 'Minimum order ₹$minimum';

    return Container(
      key: const Key('homeDeliveryCard'),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: _paleGreen,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: _borderGreen),
      ),
      child: Row(
        children: [
          const Icon(Icons.schedule_outlined, color: _green, size: 32),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 4),
                Text(
                  detail,
                  style: const TextStyle(
                    color: _green,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  '$terms • Cash on Delivery',
                  style: const TextStyle(fontSize: 12, color: Colors.black54),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// =====================================================
// SECTION TITLE
// =====================================================

class _SectionTitle extends StatelessWidget {
  const _SectionTitle(this.title, {this.actionLabel, this.onAction});

  final String title;
  final String? actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: Text(
            title,
            style: Theme.of(context).textTheme.titleLarge
                ?.copyWith(fontWeight: FontWeight.bold),
          ),
        ),
        if (actionLabel != null)
          TextButton(
            onPressed: onAction,
            style: TextButton.styleFrom(foregroundColor: _green),
            child: Text(actionLabel!),
          ),
      ],
    );
  }
}

// =====================================================
// QUICK ADD
// =====================================================

class _QuickAddCard extends StatelessWidget {
  const _QuickAddCard({
    required this.product,
    required this.quantity,
    required this.onAdd,
    required this.onIncrease,
    required this.onDecrease,
  });

  final Product product;
  final int quantity;
  final VoidCallback onAdd;
  final VoidCallback onIncrease;
  final VoidCallback onDecrease;

  @override
  Widget build(BuildContext context) {
    return Container(
      key: Key('quickAdd_${product.id}'),
      width: 160,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: _paleGreen,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: _borderGreen),
      ),
      child: Column(
        children: [
          SizedBox(
            height: 140,
            child: ProductImage(
              productId: product.id,
              icon: product.icon,
              iconSize: 36,
              borderRadius: 10,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            product.name,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 2),
          Text(
            '₹${product.price.toStringAsFixed(0)} / ${product.unit}',
            style: const TextStyle(fontSize: 12, color: Colors.black54),
          ),
          const Spacer(),
          if (quantity == 0)
            SizedBox(
              width: double.infinity,
              child: OutlinedButton(
                onPressed: onAdd,
                style: OutlinedButton.styleFrom(
                  foregroundColor: _green,
                  side: const BorderSide(color: _green),
                  visualDensity: VisualDensity.compact,
                ),
                child: const Text('ADD'),
              ),
            )
          else
            Container(
              decoration: BoxDecoration(
                color: _green,
                borderRadius: BorderRadius.circular(20),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  IconButton(
                    tooltip: 'Remove one',
                    visualDensity: VisualDensity.compact,
                    color: Colors.white,
                    icon: const Icon(Icons.remove, size: 18),
                    onPressed: onDecrease,
                  ),
                  Text(
                    '$quantity',
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  IconButton(
                    tooltip: 'Add one',
                    visualDensity: VisualDensity.compact,
                    color: Colors.white,
                    icon: const Icon(Icons.add, size: 18),
                    onPressed: onIncrease,
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

// =====================================================
// CATEGORIES
// =====================================================

class _CategoryGrid extends StatelessWidget {
  const _CategoryGrid({required this.products, required this.onOpen});

  final List<Product> products;
  final void Function(String category) onOpen;

  @override
  Widget build(BuildContext context) {
    // Categories in catalog order, with their product counts.
    final firstProduct = <String, Product>{};
    final counts = <String, int>{};
    for (final product in products) {
      final current = firstProduct[product.category];
      if (current == null ||
          (!productImageAssets.containsKey(current.id) &&
              productImageAssets.containsKey(product.id))) {
        firstProduct[product.category] = product;
      }
      counts[product.category] = (counts[product.category] ?? 0) + 1;
    }
    final categories = firstProduct.keys.toList();

    if (categories.isEmpty) return const SizedBox.shrink();

    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: categories.length,
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        crossAxisSpacing: 12,
        mainAxisSpacing: 12,
        // Tall tiles so the product photo is the main thing.
        childAspectRatio: 0.78,
      ),
      itemBuilder: (context, index) {
        final category = categories[index];
        final count = counts[category]!;

        return Material(
          color: _paleGreen,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
            side: const BorderSide(color: _borderGreen),
          ),
          child: InkWell(
            key: Key('homeCategory_$category'),
            borderRadius: BorderRadius.circular(16),
            onTap: () => onOpen(category),
            child: Padding(
              padding: const EdgeInsets.all(10),
              child: Column(
                children: [
                  Expanded(
                    child: ProductImage(
                      productId: firstProduct[category]!.id,
                      icon: firstProduct[category]!.icon,
                      iconSize: 56,
                      borderRadius: 10,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    category,
                    textAlign: TextAlign.center,
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    count == 1 ? '1 product' : '$count products',
                    style: const TextStyle(fontSize: 11),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

// =====================================================
// MILK PLAN
// =====================================================

class _MilkPlanCard extends StatelessWidget {
  const _MilkPlanCard({required this.onTap});

  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: const BorderSide(color: _green),
      ),
      child: InkWell(
        key: const Key('homeMilkPlan'),
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        child: const Padding(
          padding: EdgeInsets.all(16),
          child: Row(
            children: [
              Icon(Icons.calendar_month_outlined, color: _green, size: 32),
              SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Set up a Milk Plan',
                      style: TextStyle(fontWeight: FontWeight.bold),
                    ),
                    SizedBox(height: 4),
                    Text(
                      'Choose your milk, quantity and morning or evening.',
                      style: TextStyle(fontSize: 12, color: Colors.black54),
                    ),
                  ],
                ),
              ),
              Icon(Icons.chevron_right, color: _green),
            ],
          ),
        ),
      ),
    );
  }
}
