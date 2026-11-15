import 'dart:async';

import 'package:flutter/material.dart';

import '../core/theme/app_theme.dart';
import '../features/messages/message_inbox.dart';
import '../features/messages/messages_screen.dart';
import '../features/account/profile_photo.dart';
import '../features/shell/customer_shell.dart';
import '../models/cart_manager.dart';
import '../models/catalog_repository.dart';
import '../models/combo_offer.dart';
import '../models/milk_subscription_manager.dart';
import '../services/account_sync_service.dart';
import '../services/catalog_api_client.dart';
import '../services/feedback_api_client.dart';
import '../services/support_api_client.dart';
import '../services/milk_bill_api_client.dart';
import '../services/milk_plan_sync_service.dart';
import '../services/phone_auth_service.dart';
import '../services/push_notifications.dart';

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

/// Today's combo offers (empty without a server).
final ComboRepository sudhamrtamCombos = ComboRepository(
  load: apiBaseUrl.isEmpty
      ? null
      : ComboApiClient(baseUrl: apiBaseUrl).fetchCombos,
);

/// Products from the catalog; combo lines from the combos.
final CartManager sudhamrtamCart = CartManager(
  productLookup: (id) => isComboProductId(id)
      ? sudhamrtamCombos.productById(id)
      : sudhamrtamCatalog.productById(id),
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
    sudhamrtamCombos.addListener(sudhamrtamCart.refreshProducts);
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
  unawaited(sudhamrtamCombos.refresh());
}

/// Monthly milk bills, or null when this build has no server.
/// Set by main().
MilkBillApiClient? sudhamrtamMilkBills;

/// Customer feedback, or null when this build has no server.
/// Set by main().
FeedbackApiClient? sudhamrtamFeedback;

/// Help & Support queries, or null when this build has no server.
/// Set by main().
SupportApiClient? sudhamrtamSupport;

/// Messages from Sudhamrtam (the bell), or null when this build has
/// no server. Set by main().
MessageInbox? sudhamrtamMessages;

/// Phone notifications; null without a server or Firebase.
PushNotifications? sudhamrtamPush;

/// For opening pages and showing notes from outside a page (a tapped
/// notification).
final sudhamrtamNavigatorKey = GlobalKey<NavigatorState>();
final sudhamrtamMessengerKey = GlobalKey<ScaffoldMessengerState>();

/// The signed-in customer's profile photo; null without a server.
ProfilePhoto? sudhamrtamProfilePhoto;

final MilkSubscriptionManager sudhamrtamMilkSubscriptions =
    MilkSubscriptionManager();

/// Keeps milk plans in step with the signed-in account. Local-only
/// until main() sets it up for a build with a server.
MilkPlanSyncService sudhamrtamMilkSync = MilkPlanSyncService(
  manager: sudhamrtamMilkSubscriptions,
);

class SudhamrtamApp extends StatefulWidget {
  const SudhamrtamApp({super.key});

  @override
  State<SudhamrtamApp> createState() => _SudhamrtamAppState();
}

class _SudhamrtamAppState extends State<SudhamrtamApp> {
  final List<StreamSubscription<Object?>> _subscriptions = [];

  @override
  void initState() {
    super.initState();
    final push = sudhamrtamPush;
    if (push == null) return;
    _subscriptions
      ..add(push.taps.listen(_open))
      ..add(push.arrivals.listen(_arrived));
    // The notification that opened the app from closed.
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      final tap = await push.initialTap();
      if (tap != null) _open(tap);
    });
  }

  @override
  void dispose() {
    for (final s in _subscriptions) {
      s.cancel();
    }
    super.dispose();
  }

  /// A tapped notification: the message opens in Messages.
  void _open(PushTap tap) {
    final inbox = sudhamrtamMessages;
    final navigator = sudhamrtamNavigatorKey.currentState;
    if (tap.type != 'message' || inbox == null || navigator == null) return;
    unawaited(inbox.refresh());
    navigator.push(
      MaterialPageRoute<void>(builder: (_) => MessagesScreen(inbox: inbox)),
    );
  }

  /// Arrived while the app is open: the bell updates and a note shows.
  void _arrived(PushArrival arrival) {
    if (arrival.tap.type != 'message') return;
    unawaited(sudhamrtamMessages?.refresh());
    sudhamrtamMessengerKey.currentState?.showSnackBar(
      SnackBar(
        content: Text('New message: ${arrival.title ?? 'from Sudhamrtam'}'),
        behavior: SnackBarBehavior.floating,
        action: SnackBarAction(
          label: 'Open',
          onPressed: () => _open(arrival.tap),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Sudhamrtam',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light,
      navigatorKey: sudhamrtamNavigatorKey,
      scaffoldMessengerKey: sudhamrtamMessengerKey,
      home: const CustomerShell(),
    );
  }
}
