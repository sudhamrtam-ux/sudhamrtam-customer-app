import 'dart:async';

import 'package:flutter/material.dart';

import '../core/theme/app_theme.dart';
import '../features/shell/customer_shell.dart';
import '../models/cart_manager.dart';
import '../models/catalog_repository.dart';
import '../models/milk_subscription_manager.dart';
import '../services/catalog_api_client.dart';
import '../services/phone_auth_service.dart';

/// Phone login, or null when this build has no server
/// (API_BASE_URL) or the saved login could not be read. The app
/// still works; sign-in shows as unavailable. Set by main().
PhoneAuthGateway? sudhamrtamAuth;

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
