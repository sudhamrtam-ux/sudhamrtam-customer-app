import 'dart:async';

import 'package:flutter/material.dart';

import '../core/theme/app_theme.dart';
import '../features/shell/customer_shell.dart';
import '../models/cart_manager.dart';
import '../models/catalog_repository.dart';
import '../models/milk_subscription_manager.dart';
import '../services/catalog_api_client.dart';

/// Uses the server only when the build sets API_BASE_URL.
final CatalogRepository sudhamrtamCatalog = CatalogRepository(
  api: CatalogApiClient.fromEnvironment(),
);

final CartManager sudhamrtamCart = CartManager(
  productLookup: sudhamrtamCatalog.productById,
);

bool _catalogLinkedToCart = false;

/// Loads local catalog data, then the cart. Runs only after
/// checkout recovery has succeeded (see CheckoutStartupController).
///
/// Startup itself never uses the network. Afterwards, a fresh
/// catalog is fetched in the background (when a server is
/// configured) and cart prices follow it.
Future<void> initializeCatalogAndCart() async {
  await sudhamrtamCatalog.initialize();
  await sudhamrtamCart.initialize();

  if (!_catalogLinkedToCart) {
    _catalogLinkedToCart = true;
    sudhamrtamCatalog.addListener(sudhamrtamCart.refreshProducts);
  }

  unawaited(sudhamrtamCatalog.refresh());
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
