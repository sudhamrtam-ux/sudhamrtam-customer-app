import 'dart:async';

import 'package:flutter/widgets.dart';

import '../models/milk_subscription_manager.dart';
import 'milk_plan_api_client.dart';
import 'phone_auth_service.dart';

/// Connects the milk plans to the signed-in account.
///
/// - **Sign-in (or start-up while signed in):** plans go to the
///   server first from now on; plans that exist only on this phone
///   are uploaded, and the phone mirrors the account.
/// - **Sign-out:** the plans are removed from this phone (they are
///   safe on the server), so the next person does not see them.
/// - **Back in the app, or Home / Milk Plan opened:** [refresh], so
///   what Sudhamrtam changed meanwhile (an approval, a rejection, a
///   plan back from vacation) shows without restarting the app.
class MilkPlanSyncService extends ChangeNotifier {
  MilkPlanSyncService({
    required this.manager,
    this.api,
    this.auth,
    DateTime Function()? clock,
  }) : _clock = clock ?? DateTime.now;

  final MilkSubscriptionManager manager;
  final MilkPlanRemote? api;
  final PhoneAuthGateway? auth;
  final DateTime Function() _clock;

  StreamSubscription<AuthUser?>? _authSubscription;
  AppLifecycleListener? _lifecycle;
  bool _signedIn = false;
  DateTime? _lastSync;

  /// [refresh] asks the server at most this often.
  static const refreshGap = Duration(seconds: 15);

  /// Something the customer should know after the last sync: a
  /// connection problem, or plans that were left out because the
  /// account already had a plan for that milk and shift.
  String? message;

  bool get isAvailable => api != null && auth != null;

  /// Starts following sign-in and sign-out. Call once, after the
  /// saved plans were loaded.
  void attach() {
    final gateway = auth;
    if (gateway == null || api == null) return;

    _authSubscription = gateway.authStateChanges().listen((user) {
      if (user == null) {
        unawaited(_onSignedOut());
      } else if (!_signedIn) {
        _onSignedIn();
      }
    });

    if (gateway.currentUser != null) _onSignedIn();

    try {
      _lifecycle = AppLifecycleListener(onResume: () => unawaited(refresh()));
    } on FlutterError {
      // No widgets binding (plain unit tests): nothing to follow.
    }
  }

  /// Refreshes from the account unless that happened in the last
  /// [refreshGap] ([force]: always). Never throws.
  Future<void> refresh({bool force = false}) async {
    if (!_signedIn || manager.remote == null) return;
    final last = _lastSync;
    if (!force && last != null && _clock().difference(last) < refreshGap) {
      return;
    }
    await syncNow();
  }

  void _onSignedIn() {
    _signedIn = true;
    manager.remote = api;
    unawaited(syncNow());
  }

  Future<void> _onSignedOut() async {
    if (!_signedIn) return; // Never signed in: keep the phone's plans.
    _signedIn = false;
    manager.remote = null;
    message = null;
    await manager.forgetAll();
    notifyListeners();
  }

  /// Uploads phone-only plans and refreshes from the account.
  /// Never throws; problems end up in [message].
  Future<void> syncNow() async {
    if (manager.remote == null) return;
    _lastSync = _clock();
    try {
      final leftOut = await manager.syncWithServer();
      message = leftOut == 0
          ? null
          : 'Your account already had a subscription for the same milk and shift, '
                'so $leftOut ${leftOut == 1 ? 'delivery' : 'deliveries'} '
                'from this phone ${leftOut == 1 ? 'was' : 'were'} not added. '
                'Edit your subscription if you need more milk.';
    } on MilkPlanSyncException catch (error) {
      message = error.message;
      if (error.unauthorized) await auth?.signOut();
    } catch (error) {
      message = 'Your subscriptions could not be updated: $error';
    }
    notifyListeners();
  }

  @override
  void dispose() {
    _authSubscription?.cancel();
    _lifecycle?.dispose();
    super.dispose();
  }
}
