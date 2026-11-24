import 'package:flutter/material.dart';

import '../../app/sudhamrtam_app.dart';
import '../../database/customer_profile_database_service.dart';
import '../../services/account_sync_service.dart';
import '../../services/phone_auth_service.dart';

/// The customer's name from their profile (synced from the account
/// when signed in); null when none is saved.
Future<String?> savedCustomerName() async {
  final profile = await CustomerProfileDatabaseService.instance.getProfileById(
    AccountSyncService.localCustomerId,
  );
  final name = profile?.fullName.trim() ?? '';
  return name.isEmpty ? null : name;
}

/// "+91 90523 01616" for "+919052301616"; other numbers as they are.
String phoneText(String? phone) {
  final match = RegExp(r'^\+91(\d{5})(\d{5})$').firstMatch(phone ?? '');
  if (match == null) return phone ?? '';
  return '+91 ${match[1]} ${match[2]}';
}

/// Builds with the signed-in customer and their name (owner request
/// 2026-11-24: show the name, not the number). [user] is null when
/// signed out; [name] is null until a name is saved. Rebuilds when
/// they sign in or out, or the profile changes.
class SignedInName extends StatelessWidget {
  const SignedInName({
    super.key,
    required this.builder,
    this.auth,
    this.account,
    this.loadName = savedCustomerName,
  });

  final Widget Function(BuildContext context, AuthUser? user, String? name)
  builder;

  /// Overrides for tests; default to the app's.
  final PhoneAuthGateway? auth;
  final AccountSyncService? account;
  final Future<String?> Function() loadName;

  @override
  Widget build(BuildContext context) {
    final gateway = auth ?? sudhamrtamAuth;
    if (gateway == null) return builder(context, null, null);
    return StreamBuilder<AuthUser?>(
      stream: gateway.authStateChanges(),
      initialData: gateway.currentUser,
      builder: (context, snapshot) {
        final user = snapshot.data;
        if (user == null) return builder(context, null, null);
        return ListenableBuilder(
          listenable: account ?? sudhamrtamAccount,
          builder: (context, _) => FutureBuilder<String?>(
            // A new future each time the account changes.
            future: loadName(),
            builder: (context, name) => builder(context, user, name.data),
          ),
        );
      },
    );
  }
}
