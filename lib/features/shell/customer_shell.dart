import 'package:flutter/material.dart';

import '../home/home_screen.dart';
import '../shop/shop_screen.dart';
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'Sudhamrtam',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),

        // Temporary button for SQLite testing.
        actions: [
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
      body: _buildSelectedScreen(),

      // Bottom navigation.
      bottomNavigationBar: NavigationBar(
        selectedIndex: _selectedIndex,
        onDestinationSelected: (index) {
          setState(() {
            _selectedIndex = index;
          });
        },
        destinations: const [
          NavigationDestination(icon: Icon(Icons.home_outlined), label: 'Home'),
          NavigationDestination(
            icon: Icon(Icons.storefront_outlined),
            label: 'Shop',
          ),
          NavigationDestination(
            icon: Icon(Icons.calendar_month_outlined),
            label: 'Milk Plan',
          ),
          NavigationDestination(
            icon: Icon(Icons.shopping_cart_outlined),
            label: 'Cart',
          ),
          NavigationDestination(
            icon: Icon(Icons.person_outline),
            label: 'Account',
          ),
        ],
      ),
    );
  }

  // Display the screen selected in bottom navigation.
  Widget _buildSelectedScreen() {
    switch (_selectedIndex) {
      case 0:
        return const HomeScreen();

      case 1:
        return const ShopScreen();

      case 2:
        return const MilkPlanScreen();

      case 3:
        return const CartScreen();

      case 4:
        return AccountScreen();

      default:
        return const HomeScreen();
    }
  }

  // Temporary placeholder for the Account screen.

  // Account tab with access to Customer Order History.
}
