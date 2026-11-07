import 'dart:async';

import 'package:flutter/material.dart';

import 'app/checkout_startup_controller.dart';
import 'app/sudhamrtam_app.dart';
import 'core/theme/app_theme.dart';
import 'database/checkout_recovery_executor.dart';
import 'features/checkout/checkout_recovery_gate_screen.dart';
import 'services/api_phone_auth_gateway.dart';
import 'services/catalog_api_client.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

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
      unawaited(auth.checkSession());
    } catch (error) {
      debugPrint('Sign-in could not start: $error');
    }
  }

  final startupController = CheckoutStartupController(
    recover: CheckoutRecoveryExecutor.instance.recoverAtStartup,
    initializeCart: initializeCatalogAndCart,
  );

  final startupResult = await startupController.start();

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
