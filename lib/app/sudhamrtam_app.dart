import 'package:flutter/material.dart';

import '../core/theme/app_theme.dart';
import '../features/shell/customer_shell.dart';
import '../models/cart_manager.dart';
import '../models/catalog_repository.dart';
import '../models/milk_subscription_manager.dart';

final CatalogRepository sudhamrtamCatalog = CatalogRepository();

final CartManager sudhamrtamCart = CartManager(
  productLookup: sudhamrtamCatalog.productById,
);

/// Loads local catalog data, then the cart. Runs only after
/// checkout recovery has succeeded (see CheckoutStartupController).
///
/// Catalog loading never throws and never uses the network.
Future<void> initializeCatalogAndCart() async {
  await sudhamrtamCatalog.initialize();
  await sudhamrtamCart.initialize();
}

final MilkSubscriptionManager sudhamrtamMilkSubscriptions =
    MilkSubscriptionManager();

class SudhamrtamApp extends StatelessWidget {
  const SudhamrtamApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Sudhamrtam',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light,
      home: const CustomerShell(),
    );
  }
}
