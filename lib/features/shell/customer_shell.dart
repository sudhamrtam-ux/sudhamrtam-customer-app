import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../app/sudhamrtam_app.dart';
import '../../core/widgets/page_app_bar.dart';
import '../../core/widgets/site_layout.dart';
import '../home/home_screen.dart';
import '../messages/messages_screen.dart';
import '../shop/product_image.dart';
import '../shop/shop_screen.dart';
import 'site_header.dart';
import '../cart/cart_screen.dart';
import '../cart/site_cart_rail.dart';
import '../milk_plan/milk_plan_screen.dart';
import '../milk_plan/milk_sqlite_test_screen.dart';
import '../account/account_screen.dart';
import '../tour/app_tour.dart';

class CustomerShell extends StatefulWidget {
  const CustomerShell({
    super.key,
    this.signedIn,
    this.tourSeen = appTourSeen,
    this.markTourSeen = markAppTourSeen,
  });

  /// Whether a customer is signed in; defaults to the app's account.
  final bool Function()? signedIn;

  /// The first-login tour's memory on this phone; tests replace it.
  final Future<bool> Function() tourSeen;
  final Future<void> Function() markTourSeen;

  @override
  State<CustomerShell> createState() => _CustomerShellState();
}

class _CustomerShellState extends State<CustomerShell> {
  int _selectedIndex = 0;

  /// Shop filter; set when Home opens a category.
  String? _shopCategory;

  /// For the tour: the bottom bar and the Messages bell.
  final _barKey = GlobalKey();
  final _bellKey = GlobalKey();
  bool _touring = false;
  bool _checkingTour = false;

  bool get _signedIn => widget.signedIn?.call() ?? sudhamrtamAccount.isSignedIn;

  @override
  void initState() {
    super.initState();
    homeRequests.addListener(_showHome);
    tabRequests.addListener(_showTab);
    appTourRequests.addListener(_replayTour);
    sudhamrtamAccount.addListener(_maybeStartTour);
    WidgetsBinding.instance.addPostFrameCallback((_) => _maybeStartTour());
  }

  @override
  void dispose() {
    homeRequests.removeListener(_showHome);
    tabRequests.removeListener(_showTab);
    appTourRequests.removeListener(_replayTour);
    sudhamrtamAccount.removeListener(_maybeStartTour);
    super.dispose();
  }

  /// After signing in, once per phone (owner decision 2026-11-28); not
  /// over another page (e.g. signing in during checkout): then on the
  /// next tab tap.
  Future<void> _maybeStartTour() async {
    if (!mounted || _touring || _checkingTour) return;
    if (isWideSite(context) || !_signedIn) return;
    if (!(ModalRoute.of(context)?.isCurrent ?? true)) return;
    _checkingTour = true;
    try {
      if (await widget.tourSeen()) return;
    } catch (_) {
      // Only a guide: never in the way when the phone cannot remember.
      return;
    } finally {
      _checkingTour = false;
    }
    if (mounted && !isWideSite(context)) setState(() => _touring = true);
  }

  /// Account → "Show the app tour".
  void _replayTour() {
    if (mounted && !isWideSite(context)) setState(() => _touring = true);
  }

  void _endTour() {
    setState(() => _touring = false);
    widget.markTourSeen().catchError((_) {});
  }

  /// Where bottom-bar tab [tab] is on screen.
  Rect? _slot(int tab) {
    final bar = rectOf(_barKey);
    if (bar == null) return null;
    final width = bar.width / 5;
    return Rect.fromLTWH(
      bar.left + tab * width,
      bar.top,
      width,
      bar.height,
    ).deflate(4);
  }

  /// A page's Home button: the Home tab again.
  void _showHome() {
    if (mounted && _selectedIndex != 0) setState(() => _selectedIndex = 0);
  }

  /// A page asked for a tab (Cart or Shop).
  void _showTab() {
    final tab = tabRequests.value;
    if (tab == null || !mounted) return;
    tabRequests.value = null;
    setState(() {
      if (tab == 1) _shopCategory = null;
      _selectedIndex = tab;
    });
  }

  void _openShop(String? category) {
    setState(() {
      _shopCategory = category;
      _selectedIndex = 1;
    });
  }

  void _select(int index) {
    setState(() {
      // The Shop tab itself always opens on all products.
      if (index == 1) _shopCategory = null;
      _selectedIndex = index;
    });
    // Home and Milk Plan show the plans: fetch any change
    // Sudhamrtam made (e.g. an approval).
    if (index == 0 || index == 2) {
      unawaited(sudhamrtamMilkSync.refresh());
    }
    // Signed in on another page: the tour comes now.
    unawaited(_maybeStartTour());
  }

  /// The website's footer, on Home and Shop on a wide screen.
  Widget? _footer(BuildContext context) {
    if (!isWideSite(context)) return null;
    return ListenableBuilder(
      listenable: sudhamrtamCatalog,
      builder: (context, _) => SiteFooter(
        categories: {for (final p in sudhamrtamCatalog.products) p.category}
            .toList(),
        onOpenCategory: _openShop,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    // A computer's browser or a tablet on its side: a website.
    if (isWideSite(context)) {
      return Scaffold(
        key: const Key('site-shell'),
        backgroundColor: const Color(0xFFF7F9F3),
        appBar: PreferredSize(
          preferredSize: const Size.fromHeight(72),
          child: SiteHeader(selectedIndex: _selectedIndex, onSelect: _select),
        ),
        // The cart panel on the right while the cart has something in it
        // (owner request 2026-11-26), except on the Cart page itself.
        body: ListenableBuilder(
          listenable: sudhamrtamCart,
          builder: (context, _) {
            final page = _sitePage(context);
            if (sudhamrtamCart.isEmpty || _selectedIndex == 3) return page;
            final media = MediaQuery.of(context);
            return Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // The page lays itself out for the width left over.
                Expanded(
                  child: MediaQuery(
                    data: media.copyWith(
                      size: Size(
                        media.size.width - siteCartRailWidth,
                        media.size.height,
                      ),
                    ),
                    child: page,
                  ),
                ),
                SiteCartRail(
                  cart: sudhamrtamCart,
                  onOpenCart: () => _select(3),
                ),
              ],
            );
          },
        ),
      );
    }
    final phone = Scaffold(
      appBar: AppBar(
        // Away from Home: an arrow back to it.
        leading: _selectedIndex == 0
            ? null
            : IconButton(
                key: const Key('backHome'),
                tooltip: 'Back to Home',
                icon: const Icon(Icons.arrow_back),
                onPressed: () => setState(() => _selectedIndex = 0),
              ),
        title: Row(
          children: [
            ClipOval(
              child: Image.asset(
                sudhamrtamLogoAsset,
                width: 36,
                height: 36,
                fit: BoxFit.cover,
                errorBuilder: (context, error, stackTrace) =>
                    const SizedBox.shrink(),
              ),
            ),
            const SizedBox(width: 10),
            const Text(
              'Sudhamrtam',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
          ],
        ),

        // Temporary button for SQLite testing.
        actions: [
          // Messages from Sudhamrtam; hidden without a server.
          KeyedSubtree(key: _bellKey, child: const MessagesBell()),
          // A developer tool: only in debug builds.
          if (kDebugMode)
            IconButton(
              tooltip: 'SQLite Test',
              icon: const Icon(Icons.storage_outlined),
              onPressed: () {
                Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (context) => const MilkSqliteTestScreen(),
                  ),
                );
              },
            ),
        ],
      ),

      // Main screen content.
      body: _buildSelectedScreen(context),

      // Bottom navigation.
      bottomNavigationBar: NavigationBar(
        key: _barKey,
        selectedIndex: _selectedIndex,
        onDestinationSelected: _select,
        destinations: [
          const NavigationDestination(
            icon: Icon(Icons.home_outlined),
            label: 'Home',
          ),
          const NavigationDestination(
            icon: Icon(Icons.storefront_outlined),
            label: 'Shop',
          ),
          const NavigationDestination(
            icon: Icon(Icons.calendar_month_outlined),
            label: 'Subscriptions',
          ),
          NavigationDestination(
            // Shows how many items are in the cart.
            icon: ListenableBuilder(
              listenable: sudhamrtamCart,
              builder: (context, _) {
                final count = sudhamrtamCart.totalQuantity;
                return Badge(
                  isLabelVisible: count > 0,
                  label: Text(count > 99 ? '99+' : '$count'),
                  child: const Icon(Icons.shopping_cart_outlined),
                );
              },
            ),
            label: 'Cart',
          ),
          const NavigationDestination(
            icon: Icon(Icons.person_outline),
            label: 'Account',
          ),
        ],
      ),
    );
    // Always the same Stack, so the page keeps its state under the tour.
    return Stack(
      children: [
        phone,
        if (_touring)
          Positioned.fill(
            child: AppTourOverlay(
              steps: customerTourSteps(
                slot: _slot,
                bell: () => rectOf(_bellKey),
              ),
              onEnd: _endTour,
            ),
          ),
      ],
    );
  }

  /// Home, Shop and Cart lay themselves out as web pages; Milk Plan and
  /// Account sit in a readable column in the middle.
  Widget _sitePage(BuildContext context) =>
      _selectedIndex <= 1 || _selectedIndex == 3
      ? _buildSelectedScreen(context)
      : Align(
          alignment: Alignment.topCenter,
          child: ConstrainedBox(
            constraints: BoxConstraints(
              maxWidth: _selectedIndex == 2 || _selectedIndex == 4 ? 1100 : 860,
            ),
            child: _buildSelectedScreen(context),
          ),
        );

  // Display the screen selected in bottom navigation.
  Widget _buildSelectedScreen(BuildContext context) {
    switch (_selectedIndex) {
      case 0:
        return HomeScreen(
          onOpenShop: _openShop,
          onOpenMilkPlan: () => setState(() => _selectedIndex = 2),
          onOpenCart: () => setState(() => _selectedIndex = 3),
          footer: _footer(context),
        );

      case 1:
        return ShopScreen(
          category: _shopCategory,
          onCategoryChanged: (category) =>
              setState(() => _shopCategory = category),
          footer: _footer(context),
        );

      case 2:
        return const MilkPlanScreen();

      case 3:
        return const CartScreen();

      case 4:
        return AccountScreen();

      default:
        return HomeScreen(onOpenShop: _openShop);
    }
  }
}
