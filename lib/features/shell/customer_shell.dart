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
import '../milk_plan/milk_plan_screen.dart';
import '../milk_plan/milk_sqlite_test_screen.dart';
import '../account/account_screen.dart';

class CustomerShell extends StatefulWidget {
  const CustomerShell({super.key});

  @override
  State<CustomerShell> createState() => _CustomerShellState();
}

class _CustomerShellState extends State<CustomerShell> {
  int _selectedIndex = 0;

  /// Shop filter; set when Home opens a category.
  String? _shopCategory;

  @override
  void initState() {
    super.initState();
    homeRequests.addListener(_showHome);
    tabRequests.addListener(_showTab);
  }

  @override
  void dispose() {
    homeRequests.removeListener(_showHome);
    tabRequests.removeListener(_showTab);
    super.dispose();
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
        // Home, Shop and Cart lay themselves out as web pages; Milk
        // Plan and Account sit in a readable column in the middle.
        body: _selectedIndex <= 1 || _selectedIndex == 3
            ? _buildSelectedScreen(context)
            : Align(
                alignment: Alignment.topCenter,
                child: ConstrainedBox(
                  constraints: BoxConstraints(
                    maxWidth: _selectedIndex == 2 || _selectedIndex == 4
                        ? 1100
                        : 860,
                  ),
                  child: _buildSelectedScreen(context),
                ),
              ),
      );
    }
    return Scaffold(
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
          const MessagesBell(),
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
  }

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
