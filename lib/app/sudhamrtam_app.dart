import 'dart:async';

import 'package:flutter/material.dart';

import '../core/theme/app_theme.dart';
import '../features/shell/customer_shell.dart';
import '../models/cart_manager.dart';
import '../models/catalog_repository.dart';
import '../models/milk_subscription_manager.dart';
import '../services/account_sync_service.dart';
import '../services/catalog_api_client.dart';
import '../services/phone_auth_service.dart';

/// Phone login, or null when this build has no server
/// (API_BASE_URL) or the saved login could not be read. The app
/// still works; sign-in shows as unavailable. Set by main().
PhoneAuthGateway? sudhamrtamAuth;

/// The phone's profile and saved addresses, synced with the
/// signed-in account when there is a server. Set by main().
AccountSyncService sudhamrtamAccount = AccountSyncService.localOnly();

/// Uses the server only when the build sets API_BASE_URL.
final CatalogRepository sudhamrtamCatalog = CatalogRepository(
  api: CatalogApiClient.fromEnvironment(),
);

final CartManager sudhamrtamCart = CartManager(
  productLookup: sudhamrtamCatalog.productById,
);

bool _catalogLinkedToCart = false;
bool _milkPlansRestored = false;

/// Loads local catalog data, then the cart and saved milk plans. Runs only after
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

  // Milk plans saved on this phone. A failure here must not stop
  // the app; the plans stay in the database.
  if (!_milkPlansRestored) {
    _milkPlansRestored = true;
    try {
      final skipped = await sudhamrtamMilkSubscriptions
          .restoreSavedSubscriptions();
      if (skipped > 0) debugPrint('Skipped $skipped invalid milk plan(s).');
    } catch (error) {
      debugPrint('Milk plans could not be loaded: $error');
    }
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
