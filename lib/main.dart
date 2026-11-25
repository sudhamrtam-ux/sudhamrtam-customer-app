import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import 'app/checkout_startup_controller.dart';
import 'app/splash_video.dart';
import 'app/sudhamrtam_app.dart';
import 'core/theme/app_theme.dart';
import 'database/checkout_recovery_executor.dart';
import 'database/web_database_setup.dart';
import 'features/checkout/order_destination.dart';
import 'features/checkout/checkout_recovery_gate_screen.dart';
import 'features/messages/message_inbox.dart';
import 'features/account/profile_photo.dart';
import 'services/account_api_client.dart';
import 'services/account_sync_service.dart';
import 'services/api_phone_auth_gateway.dart';
import 'services/catalog_api_client.dart';
import 'services/firebase_push_platform.dart';
import 'services/push_notifications.dart';
import 'services/feedback_api_client.dart';
import 'services/message_api_client.dart';
import 'services/profile_photo_api_client.dart';
import 'services/milk_bill_api_client.dart';
import 'services/milk_plan_api_client.dart';
import 'services/milk_plan_sync_service.dart';
import 'services/milk_tomorrow_client.dart';
import 'services/order_api_client.dart';
import 'services/support_api_client.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // The website keeps the app's SQLite database in the browser; the
  // Windows app in its own folder.
  await useWebDatabaseIfNeeded();

  // The opening animation (owner, 2026-11-17) plays first, while the
  // app gets ready below; the app opens when both are done.
  final splashDone = Completer<void>();
  runApp(
    SplashVideoApp(
      onDone: () {
        if (!splashDone.isCompleted) splashDone.complete();
      },
    ),
  );

  // Phone login through the backend, only when this build has
  // a server (API_BASE_URL). Optional: a failure here must not
  // stop the app from starting or block checkout recovery.
  if (apiBaseUrl.isNotEmpty) {
    try {
      final auth = ApiPhoneAuthGateway(
        baseUrl: apiBaseUrl,
        store: SecureSessionStore(),
      );
      await auth.restore();
      sudhamrtamAuth = auth;
      sudhamrtamAccount = AccountSyncService(
        api: AccountApiClient(
          baseUrl: apiBaseUrl,
          token: () => auth.sessionToken,
        ),
        auth: auth,
      );
      sudhamrtamMilkSync = MilkPlanSyncService(
        manager: sudhamrtamMilkSubscriptions,
        api: MilkPlanApiClient(
          baseUrl: apiBaseUrl,
          token: () => auth.sessionToken,
        ),
        auth: auth,
      );
      sudhamrtamMilkBills = MilkBillApiClient(
        baseUrl: apiBaseUrl,
        token: () => auth.sessionToken,
      );
      sudhamrtamMilkTomorrow = MilkTomorrowClient(
        baseUrl: apiBaseUrl,
        token: () => auth.sessionToken,
      );
      sudhamrtamFeedback = FeedbackApiClient(
        baseUrl: apiBaseUrl,
        token: () => auth.sessionToken,
      );
      sudhamrtamSupport = SupportApiClient(
        baseUrl: apiBaseUrl,
        token: () => auth.sessionToken,
      );
      sudhamrtamMessages = MessageInbox(
        api: MessageApiClient(
          baseUrl: apiBaseUrl,
          token: () => auth.sessionToken,
        ),
      )..attach(auth.authStateChanges());
      sudhamrtamProfilePhoto = ProfilePhoto(
        api: ProfilePhotoApiClient(
          baseUrl: apiBaseUrl,
          token: () => auth.sessionToken,
        ),
      )..attach(auth.authStateChanges());
      // Orders go to the server (before startup recovery, so an
      // unfinished order is finished on the server too).
      OrderDestination.server = OrderApiClient(
        baseUrl: apiBaseUrl,
        token: () => auth.sessionToken,
      );
      unawaited(auth.checkSession());
    } catch (error) {
      debugPrint('Sign-in could not start: $error');
    }

    // Phone notifications (Firebase): optional; the app works
    // without them. Phones only: not the website or Windows.
    final auth = sudhamrtamAuth;
    final phone =
        !kIsWeb &&
        (defaultTargetPlatform == TargetPlatform.android ||
            defaultTargetPlatform == TargetPlatform.iOS);
    if (auth is ApiPhoneAuthGateway && phone) {
      try {
        final push = PushNotifications(
          platform: await FirebasePushPlatform.start(),
          api: PushApiClient(baseUrl: apiBaseUrl),
          session: () => auth.sessionToken,
        )..attach(auth.authStateChanges());
        auth.beforeSignOut = push.unregister;
        sudhamrtamPush = push;
      } catch (error) {
        debugPrint('Phone notifications could not start: $error');
      }
    }
  }

  final startupController = CheckoutStartupController(
    recover: CheckoutRecoveryExecutor.instance.recoverAtStartup,
    initializeCart: initializeCatalogAndCart,
  );

  final startupResult = await startupController.start();

  // After checkout recovery: refresh the profile and addresses
  // from the account (in the background; works offline too).
  sudhamrtamAccount.attach();
  // Milk plans: upload phone-only plans and mirror the account.
  sudhamrtamMilkSync.attach();

  await splashDone.future;

  if (startupController.isReady) {
    runApp(const SudhamrtamApp());
    return;
  }

  runApp(
    SudhamrtamRecoveryApp(
      initialResult: startupResult,
      startupController: startupController,
    ),
  );
}

/// Restricted application shown until recovery and
/// cart initialization have both completed.
class SudhamrtamRecoveryApp extends StatefulWidget {
  final CheckoutRecoveryExecutionResult initialResult;
  final CheckoutStartupController startupController;

  const SudhamrtamRecoveryApp({
    super.key,
    required this.initialResult,
    required this.startupController,
  });

  @override
  State<SudhamrtamRecoveryApp> createState() => _SudhamrtamRecoveryAppState();
}

class _SudhamrtamRecoveryAppState extends State<SudhamrtamRecoveryApp> {
  bool _isReady = false;

  Future<void> _completeStartup() async {
    if (_isReady) return;

    await widget.startupController.completeStartup();

    if (!widget.startupController.isReady) {
      throw StateError('Cart initialization did not complete successfully.');
    }

    if (!mounted) return;

    setState(() {
      _isReady = true;
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_isReady) {
      return const SudhamrtamApp();
    }

    return MaterialApp(
      title: 'Sudhamrtam - Checkout Recovery',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light,
      home: CheckoutRecoveryGateScreen(
        initialResult: widget.initialResult,
        retryRecovery: widget.startupController.retryRecovery,
        onRecoveryCompleted: _completeStartup,
      ),
    );
  }
}
