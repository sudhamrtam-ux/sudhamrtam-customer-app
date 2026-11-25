import 'dart:async';

import 'package:flutter/material.dart';

import '../../app/sudhamrtam_app.dart';
import '../../core/widgets/site_layout.dart';
import '../../models/cart_manager.dart';
import '../../models/catalog_repository.dart';
import '../../models/combo_offer.dart';
import '../../models/product.dart';
import '../../services/catalog_api_client.dart' show apiBaseUrl;
import '../../services/offer_api_client.dart';
import '../../services/order_api_client.dart';
import '../checkout/order_destination.dart';
import '../milk_bills/milk_bills_screen.dart';
import '../shop/product_image.dart';
import '../../models/milk_subscription.dart';
import '../../models/milk_subscription_manager.dart';
import '../account/customer_name.dart';
import 'account_status.dart';
import 'address_details_card.dart';
import 'combo_cards.dart';
import 'glance_cards.dart';
import 'offer_ticker.dart';
import 'tomorrow_milk_card.dart';

const _green = Color(0xFF82B440);
const _darkGreen = Color(0xFF4F7A1F);
const _paleGreen = Color(0xFFF2F7EA);
const _ink = Color(0xFF1F2A14);

/// The modern card look on Home (owner, 2026-11-17): white, rounded,
/// with a soft shadow instead of a border.
BoxDecoration _cardDecoration({Color color = Colors.white}) => BoxDecoration(
  color: color,
  borderRadius: BorderRadius.circular(20),
  boxShadow: const [
    BoxShadow(color: Color(0x14000000), blurRadius: 18, offset: Offset(0, 6)),
  ],
);

/// Loads the owner's order rules; null when there is no server.
typedef OrderRulesLoader = Future<OrderRules> Function();

OrderRulesLoader? _defaultRulesLoader() => OrderDestination.server?.fetchRules;

/// Loads today's offer texts; null when there is no server.
typedef OffersLoader = Future<List<String>> Function();

OffersLoader? _defaultOffersLoader() =>
    apiBaseUrl.isEmpty ? null : OfferApiClient(baseUrl: apiBaseUrl).fetchOffers;

/// The customer's name from their profile; null without one.

/// "Good morning", "Good afternoon" or "Good evening" at [time].
String greetingFor(DateTime time) => time.hour >= 4 && time.hour < 12
    ? 'Good morning'
    : time.hour >= 12 && time.hour < 17
    ? 'Good afternoon'
    : 'Good evening';

/// "Good morning, Asha Rani 😊": the whole name as saved (owner,
/// 2026-11-25: the first word alone cut names like "Nagar aju" short).
String greetingLine(DateTime time, String? name) {
  final full = (name ?? '').trim().split(RegExp(r'\s+')).join(' ');
  return full.isEmpty
      ? '${greetingFor(time)} 😊'
      : '${greetingFor(time)}, $full 😊';
}

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
    this.combos,
    this.milkPlans,
    OrderRulesLoader? loadRules,
    OffersLoader? loadOffers,
    DateTime Function()? clock,
    this.loadCustomerName = savedCustomerName,
    this.footer,
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

  /// Override for tests; defaults to the app's combo offers.
  final ComboRepository? combos;

  /// Override for tests; defaults to the app's milk plans.
  final MilkSubscriptionManager? milkPlans;

  /// Null when the app has no server: the delivery card is hidden.
  final OrderRulesLoader? loadRules;

  /// Null when the app has no server: no offer line.
  final OffersLoader? loadOffers;
  final DateTime Function() clock;

  /// The customer's name for the greeting; tests replace it.
  final Future<String?> Function() loadCustomerName;

  /// The website's footer, below everything (wide screens only).
  final Widget? footer;

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  OrderRules? _rules;
  List<String> _offers = const [];
  Timer? _ticker;

  /// Bumped on pull-to-refresh: reloads tomorrow's milk.
  int _tomorrowTick = 0;

  CatalogRepository get _catalog => widget.catalog ?? sudhamrtamCatalog;
  CartManager get _cart => widget.cart ?? sudhamrtamCart;
  ComboRepository get _combos => widget.combos ?? sudhamrtamCombos;

  @override
  void initState() {
    super.initState();
    _loadRules();
    _loadOffers();
    unawaited(_combos.refresh());
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
      animation: Listenable.merge([_catalog, _cart, _combos]),
      builder: (context, _) {
        final products = _catalog.products;
        // One card per product, in its main size (owner decision
        // 2026-11-16): 1 L or 1 kg when sold, else the first.
        final essentials = [
          for (final sizes in productsByName(
            products
                .where((p) => p.isAvailable && p.category == 'Fresh Dairy')
                .toList(),
          ))
            mainSize(sizes),
        ].take(4).toList();

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
        setState(() => _tomorrowTick++);
        await Future.wait([
          _catalog.refresh(),
          _loadRules(),
          _loadOffers(),
          _combos.refresh(),
        ]);
      },
      child: CustomScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        slivers: [
          SliverPadding(
            padding: sitePagePadding(
              context,
              top: isWideSite(context) ? 24 : 16,
              bottom: isWideSite(context) ? 40 : 16,
            ),
            sliver: SliverList.list(
              children: [
                // Welcome first, with the milk plan as a small button
                // (owner, 2026-11-17).
                // Welcome, with the milk plan badge in the corner, then the
                // banner (owner, 2026-11-17).
                _Greeting(
                  loadName: widget.loadCustomerName,
                  now: widget.clock,
                  status: AccountStatusCard(
                    plans: widget.milkPlans,
                    onOpen: widget.onOpenMilkPlan,
                    today: widget.clock,
                    compact: true,
                  ),
                ),
                const SizedBox(height: 14),
                _HeroCard(onShopNow: () => widget.onOpenShop?.call(null)),
                const SizedBox(height: 16),
                // What the customer should know at once; each only when it
                // applies.
                // An address without its map spot or details.
                const AddressDetailsCard(),
                // A milk bill to pay.
                const MilkBillsReminder(unpaidOnly: true),
                // New messages from Sudhamrtam.
                const NewMessagesCard(),
                // The last order: on its way, or just delivered.
                LastOrderCard(
                  key: ValueKey('last-order-$_tomorrowTick'),
                  now: widget.clock,
                ),
                // Items left in the cart.
                if (_cart.totalQuantity > 0) ...[
                  _CartWaitingCard(
                    items: _cart.totalQuantity,
                    subtotal: _cart.subtotal,
                    onOpen: widget.onOpenCart,
                  ),
                  const SizedBox(height: 12),
                ],
                // Skip tomorrow / extra milk tomorrow (owner decision 2026-11-15).
                TomorrowMilkCard(
                  key: ValueKey('tomorrow-$_tomorrowTick'),
                  client: sudhamrtamMilkTomorrow,
                  onChanged: () => sudhamrtamMilkSync.refresh(force: true),
                ),
                if (_rules != null) ...[
                  const SizedBox(height: 12),
                  _DeliveryCard(rules: _rules!, now: widget.clock()),
                ],
                // Combo offers (owner decision 2026-11-15).
                if (_combos.combos.isNotEmpty) ...[
                  const SizedBox(height: 16),
                  ComboCards(
                    combos: _combos.combos,
                    cart: _cart,
                    onOpenCart: widget.onOpenCart,
                  ),
                ],
                if (essentials.isNotEmpty) ...[
                  const SizedBox(height: 28),
                  _SectionTitle(
                    'Daily Essentials',
                    actionLabel: 'See all',
                    onAction: () => widget.onOpenShop?.call('Fresh Dairy'),
                  ),
                  const SizedBox(height: 12),
                  if (isWideSite(context))
                    // A website: the essentials side by side, filling the row.
                    GridView.builder(
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      itemCount: essentials.length,
                      gridDelegate:
                          const SliverGridDelegateWithFixedCrossAxisCount(
                            crossAxisCount: 4,
                            crossAxisSpacing: 20,
                            mainAxisSpacing: 20,
                            mainAxisExtent: 290,
                          ),
                      itemBuilder: (context, index) =>
                          _quickAdd(essentials[index]),
                    )
                  else
                    SizedBox(
                      height: 290,
                      child: ListView.separated(
                        scrollDirection: Axis.horizontal,
                        itemCount: essentials.length,
                        separatorBuilder: (context, index) =>
                            const SizedBox(width: 12),
                        itemBuilder: (context, index) =>
                            _quickAdd(essentials[index]),
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
                const SizedBox(height: 24),
                _MilkPlanCard(
                  onTap: widget.onOpenMilkPlan,
                  plans: widget.milkPlans ?? sudhamrtamMilkSubscriptions,
                ),
                const SizedBox(height: 24),
                const Center(
                  child: Text(
                    'Purity • Tradition • Wellness',
                    style: TextStyle(
                      color: _green,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
          ),
          if (widget.footer != null)
            SliverFillRemaining(
              // A short page: the footer still sits at the bottom.
              hasScrollBody: false,
              child: Align(
                alignment: Alignment.bottomCenter,
                child: widget.footer,
              ),
            ),
        ],
      ),
    );
  }

  Widget _quickAdd(Product product) => _QuickAddCard(
    product: product,
    quantity: _cart.quantityFor(product.id),
    onAdd: () => _add(product),
    onIncrease: () => _cart.increaseQuantity(product.id),
    onDecrease: () => _cart.decreaseQuantity(product.id),
  );
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
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(24),
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF9CCB57), _green, _darkGreen],
        ),
        boxShadow: const [
          BoxShadow(
            color: Color(0x3382B440),
            blurRadius: 20,
            offset: Offset(0, 8),
          ),
        ],
      ),
      child: Stack(
        children: [
          // Soft leaf shapes for depth.
          Positioned(
            right: -30,
            top: -30,
            child: Container(
              width: 140,
              height: 140,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: Colors.white.withValues(alpha: 0.10),
              ),
            ),
          ),
          Positioned(
            right: 16,
            bottom: 10,
            child: Icon(
              Icons.eco,
              size: 72,
              color: Colors.white.withValues(alpha: 0.18),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 18, 20, 18),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Pure Goodness, Naturally',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 20,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0.2,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  'Fresh dairy, natural honey and traditional wood-pressed oils.',
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.92),
                    fontSize: 14,
                    height: 1.35,
                  ),
                ),
                const SizedBox(height: 12),
                FilledButton.icon(
                  key: const Key('homeShopNow'),
                  onPressed: onShopNow,
                  style: FilledButton.styleFrom(
                    backgroundColor: Colors.white,
                    foregroundColor: _darkGreen,
                    shape: const StadiumBorder(),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 20,
                      vertical: 12,
                    ),
                  ),
                  icon: const Icon(Icons.storefront_outlined),
                  label: const Text(
                    'Shop Now',
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
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
    // Only what the server offers now (checkout follows the same rules).
    final payments = rules.offersOnlinePayment
        ? 'Cash on Delivery or pay online'
        : 'Cash on Delivery';

    return Container(
      key: const Key('homeDeliveryCard'),
      padding: const EdgeInsets.all(16),
      decoration: _cardDecoration(),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: const BoxDecoration(
              color: _paleGreen,
              shape: BoxShape.circle,
            ),
            child: const Icon(Icons.schedule_outlined, color: _darkGreen),
          ),
          const SizedBox(width: 14),
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
                    color: _darkGreen,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  '$terms • $payments',
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
                ?.copyWith(fontWeight: FontWeight.w800, color: _ink),
          ),
        ),
        if (actionLabel != null)
          TextButton(
            onPressed: onAction,
            style: TextButton.styleFrom(foregroundColor: _darkGreen),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  actionLabel!,
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
                const Icon(Icons.chevron_right, size: 18),
              ],
            ),
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
      padding: const EdgeInsets.all(10),
      decoration: _cardDecoration(),
      child: Column(
        children: [
          Container(
            height: 140,
            width: double.infinity,
            padding: const EdgeInsets.all(6),
            decoration: BoxDecoration(
              color: _paleGreen,
              borderRadius: BorderRadius.circular(14),
            ),
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
            style: const TextStyle(
              fontSize: 13,
              color: _darkGreen,
              fontWeight: FontWeight.w600,
            ),
          ),
          const Spacer(),
          if (quantity == 0)
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: onAdd,
                style: FilledButton.styleFrom(
                  backgroundColor: _green,
                  foregroundColor: Colors.white,
                  shape: const StadiumBorder(),
                  visualDensity: VisualDensity.compact,
                ),
                icon: const Icon(Icons.add, size: 18),
                label: const Text(
                  'ADD',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
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
    }
    // Products, not sizes: Honey in three sizes is one product.
    for (final sizes in productsByName(products)) {
      final category = sizes.first.category;
      counts[category] = (counts[category] ?? 0) + 1;
    }
    final categories = firstProduct.keys.toList();

    if (categories.isEmpty) return const SizedBox.shrink();

    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: categories.length,
      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
        // A website: every category in one row.
        crossAxisCount: isWideSite(context) ? 4 : 2,
        crossAxisSpacing: isWideSite(context) ? 20 : 12,
        mainAxisSpacing: 12,
        // Tall tiles so the product photo is the main thing.
        childAspectRatio: 0.78,
      ),
      itemBuilder: (context, index) {
        final category = categories[index];
        final count = counts[category]!;

        return DecoratedBox(
          decoration: _cardDecoration(),
          child: Material(
            color: Colors.transparent,
            child: InkWell(
              key: Key('homeCategory_$category'),
              borderRadius: BorderRadius.circular(20),
              onTap: () => onOpen(category),
              child: Padding(
                padding: const EdgeInsets.all(10),
                child: Column(
                  children: [
                    Expanded(
                      child: Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: _paleGreen,
                          borderRadius: BorderRadius.circular(14),
                        ),
                        child: ProductImage(
                          productId: firstProduct[category]!.id,
                          icon: firstProduct[category]!.icon,
                          iconSize: 56,
                          borderRadius: 10,
                        ),
                      ),
                    ),
                    const SizedBox(height: 10),
                    Text(
                      category,
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        color: _ink,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 2,
                      ),
                      decoration: BoxDecoration(
                        color: _paleGreen,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Text(
                        count == 1 ? '1 product' : '$count products',
                        style: const TextStyle(
                          fontSize: 11,
                          color: _darkGreen,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ],
                ),
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
  const _MilkPlanCard({required this.onTap, required this.plans});

  final VoidCallback? onTap;
  final MilkSubscriptionManager plans;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: plans,
      builder: (context, _) {
        // With a plan: manage it; without: start one.
        final hasPlan = plans.subscriptions.any(
          (p) => p.status != MilkSubscriptionStatus.cancelled,
        );
        return DecoratedBox(
          decoration: _cardDecoration(color: _paleGreen),
          child: Material(
            color: Colors.transparent,
            child: InkWell(
              key: const Key('homeMilkPlan'),
              borderRadius: BorderRadius.circular(20),
              onTap: onTap,
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: const BoxDecoration(
                        color: _green,
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(
                        Icons.calendar_month_outlined,
                        color: Colors.white,
                      ),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            hasPlan
                                ? 'Your Subscriptions'
                                : 'Set up a Subscription',
                            style: const TextStyle(
                              fontWeight: FontWeight.bold,
                              color: _ink,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            hasPlan
                                ? 'Change quantity, pause or add vacation days.'
                                : 'Choose your milk, quantity and delivery time.',
                            style: const TextStyle(
                              fontSize: 12,
                              color: Colors.black54,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const Icon(Icons.chevron_right, color: _darkGreen),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

// =====================================================
// GREETING
// =====================================================

/// "Welcome to Sudhamrtam" at the top, with the milk plan status as a
/// small button under it (owner, 2026-11-17).
class _Greeting extends StatefulWidget {
  const _Greeting({
    required this.status,
    required this.loadName,
    required this.now,
  });

  final Widget status;
  final Future<String?> Function() loadName;
  final DateTime Function() now;

  @override
  State<_Greeting> createState() => _GreetingState();
}

class _GreetingState extends State<_Greeting> {
  String? _name;

  @override
  void initState() {
    super.initState();
    // A new name (signing in, editing the profile) shows at once.
    sudhamrtamAccount.addListener(_load);
    _load();
  }

  @override
  void dispose() {
    sudhamrtamAccount.removeListener(_load);
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final name = await widget.loadName();
      if (mounted && name != _name) setState(() => _name = name);
    } catch (_) {
      // Only a greeting: without the name it still says hello.
    }
  }

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(child: _texts(context)),
        const SizedBox(width: 12),
        widget.status,
      ],
    );
  }

  Widget _texts(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          greetingLine(widget.now(), _name),
          key: const Key('homeGreeting'),
          // A long name stays on one line.
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(
            color: _darkGreen,
            fontSize: 17,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          'Welcome to Sudhamrtam',
          style: Theme.of(context).textTheme.headlineSmall?.copyWith(
            fontWeight: FontWeight.w800,
            color: _ink,
            letterSpacing: -0.2,
          ),
        ),
        const SizedBox(height: 4),
        const Text(
          'Pure farm goodness delivered to your doorstep.',
          style: TextStyle(color: Colors.black54, fontSize: 14),
        ),
      ],
    );
  }
}

// =====================================================
// CART WAITING
// =====================================================

/// "3 items in your cart · ₹450": items left in the cart, one tap to
/// check out.
class _CartWaitingCard extends StatelessWidget {
  const _CartWaitingCard({
    required this.items,
    required this.subtotal,
    required this.onOpen,
  });

  final int items;
  final double subtotal;
  final VoidCallback? onOpen;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: _cardDecoration(),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          key: const Key('homeCartWaiting'),
          borderRadius: BorderRadius.circular(20),
          onTap: onOpen,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 12, 12),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: const BoxDecoration(
                    color: _paleGreen,
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    Icons.shopping_cart_outlined,
                    color: _darkGreen,
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '$items ${items == 1 ? 'item' : 'items'} in your cart'
                        ' · ₹${subtotal.toStringAsFixed(0)}',
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          color: _ink,
                        ),
                      ),
                      const SizedBox(height: 2),
                      const Text(
                        'Finish your order before the cut-off.',
                        style: TextStyle(fontSize: 12, color: Colors.black54),
                      ),
                    ],
                  ),
                ),
                const Icon(Icons.chevron_right, color: _darkGreen),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
