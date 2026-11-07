import 'dart:async';

import 'package:flutter/foundation.dart';

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
class MilkPlanSyncService extends ChangeNotifier {
  MilkPlanSyncService({required this.manager, this.api, this.auth});

  final MilkSubscriptionManager manager;
  final MilkPlanRemote? api;
  final PhoneAuthGateway? auth;

  StreamSubscription<AuthUser?>? _authSubscription;
  bool _signedIn = false;

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
    try {
      final leftOut = await manager.syncWithServer();
      message = leftOut == 0
          ? null
          : 'Your account already had a plan for the same milk and shift, '
                'so $leftOut ${leftOut == 1 ? 'delivery' : 'deliveries'} '
                'from this phone ${leftOut == 1 ? 'was' : 'were'} not added. '
                'Edit your plan if you need more milk.';
    } on MilkPlanSyncException catch (error) {
      message = error.message;
      if (error.unauthorized) await auth?.signOut();
    } catch (error) {
      message = 'Your milk plans could not be updated: $error';
    }
    notifyListeners();
  }

  @override
  void dispose() {
    _authSubscription?.cancel();
    super.dispose();
  }
}
