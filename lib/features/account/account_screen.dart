import 'package:flutter/material.dart';

import '../../app/sudhamrtam_app.dart';
import '../../services/phone_auth_service.dart';
import '../orders/order_history_screen.dart';
import 'customer_profile_screen.dart';
import 'phone_login_screen.dart';
import 'saved_addresses_screen.dart';

class AccountScreen extends StatelessWidget {
  const AccountScreen({super.key, this.auth});

  /// Optional override for tests; defaults to the app's login.
  final PhoneAuthGateway? auth;

  static const Color _brandGreen = Color(0xFF82B440);

  /// Opens the existing customer order history screen.
  void _openOrderHistory(BuildContext context) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(builder: (context) => const OrderHistoryScreen()),
    );
  }

  /// Opens the customer profile screen.
  void _openCustomerProfile(BuildContext context) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(builder: (context) => CustomerProfileScreen()),
    );
  }

  /// Opens the customer's saved delivery addresses.
  void _openSavedAddresses(BuildContext context) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(builder: (context) => SavedAddressesScreen()),
    );
  }

  /// Displays a message for features not yet implemented.
  void _showComingSoon(BuildContext context, String feature) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('$feature will be available soon.'),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  /// Builds a reusable Account menu tile.
  Widget _buildAccountTile({
    required IconData icon,
    required String title,
    required String subtitle,
    required VoidCallback onTap,
  }) {
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      elevation: 1,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        leading: Container(
          width: 44,
          height: 44,
          decoration: BoxDecoration(
            color: _brandGreen.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Icon(icon, color: _brandGreen),
        ),
        title: Text(title, style: const TextStyle(fontWeight: FontWeight.w600)),
        subtitle: Text(subtitle),
        trailing: const Icon(Icons.chevron_right, color: Colors.black45),
        onTap: onTap,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        const SizedBox(height: 16),

        // Account header.
        const Icon(Icons.account_circle_outlined, size: 76, color: _brandGreen),

        const SizedBox(height: 12),

        Text(
          'My Account',
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.headlineSmall
              ?.copyWith(fontWeight: FontWeight.bold),
        ),

        const SizedBox(height: 8),

        const Text(
          'Welcome to Sudhamrtam',
          textAlign: TextAlign.center,
          style: TextStyle(color: Colors.black54),
        ),

        const SizedBox(height: 12),

        const Text(
          'Pure goodness, delivered with care.',
          textAlign: TextAlign.center,
          style: TextStyle(color: _brandGreen, fontWeight: FontWeight.w500),
        ),

        const SizedBox(height: 20),

        _SignInCard(auth: auth ?? sudhamrtamAuth),

        const SizedBox(height: 20),

        // Account management heading.
        Text(
          'ACCOUNT MANAGEMENT',
          style: Theme.of(context).textTheme.labelMedium?.copyWith(
            color: Colors.black54,
            fontWeight: FontWeight.bold,
            letterSpacing: 1.1,
          ),
        ),

        const SizedBox(height: 12),

        // My Profile — active.
        _buildAccountTile(
          icon: Icons.person_outline,
          title: 'My Profile',
          subtitle: 'View and update your personal details',
          onTap: () => _openCustomerProfile(context),
        ),

        // Saved Addresses — active.
        _buildAccountTile(
          icon: Icons.location_on_outlined,
          title: 'Saved Addresses',
          subtitle: 'Manage your delivery addresses',
          onTap: () => _openSavedAddresses(context),
        ),

        // My Orders — existing working feature.
        _buildAccountTile(
          icon: Icons.receipt_long_outlined,
          title: 'My Orders',
          subtitle: 'View your order history and order status',
          onTap: () => _openOrderHistory(context),
        ),

        const SizedBox(height: 20),

        // Support heading.
        Text(
          'SUPPORT',
          style: Theme.of(context).textTheme.labelMedium?.copyWith(
            color: Colors.black54,
            fontWeight: FontWeight.bold,
            letterSpacing: 1.1,
          ),
        ),

        const SizedBox(height: 12),

        // Help & Support — placeholder.
        _buildAccountTile(
          icon: Icons.help_outline,
          title: 'Help & Support',
          subtitle: 'Get assistance with your Sudhamrtam account',
          onTap: () => _showComingSoon(context, 'Help & Support'),
        ),

        const SizedBox(height: 24),

        // Footer.
        const Center(
          child: Text(
            'Sudhamrtam • Pure by Nature',
            style: TextStyle(color: Colors.black45, fontSize: 12),
          ),
        ),

        const SizedBox(height: 16),
      ],
    );
  }
}

/// Shows who is signed in, or offers phone sign-in.
///
/// Signing in is optional for now: the app works without it.
class _SignInCard extends StatelessWidget {
  const _SignInCard({required this.auth});

  final PhoneAuthGateway? auth;

  static const Color _brandGreen = Color(0xFF82B440);

  @override
  Widget build(BuildContext context) {
    final gateway = auth;

    if (gateway == null) {
      return const Card(
        child: ListTile(
          leading: Icon(Icons.cloud_off_outlined),
          title: Text('Sign-in unavailable'),
          subtitle: Text(
            'Sign-in needs the Sudhamrtam server, which this build does not use yet.',
          ),
        ),
      );
    }

    return StreamBuilder<AuthUser?>(
      stream: gateway.authStateChanges(),
      initialData: gateway.currentUser,
      builder: (context, snapshot) {
        final user = snapshot.data;

        if (user == null) {
          return Card(
            child: ListTile(
              leading: const Icon(Icons.login, color: _brandGreen),
              title: const Text('Sign in with phone'),
              subtitle: const Text(
                'Use your mobile number and a one-time code',
              ),
              trailing: const Icon(Icons.chevron_right),
              onTap: () async {
                final signedIn = await Navigator.of(context).push<bool>(
                  MaterialPageRoute<bool>(
                    builder: (_) => PhoneLoginScreen(auth: gateway),
                  ),
                );

                if (signedIn == true && context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Signed in successfully.')),
                  );
                }
              },
            ),
          );
        }

        return Card(
          child: ListTile(
            leading: const Icon(Icons.verified_user, color: _brandGreen),
            title: Text('Signed in as ${user.phoneNumber ?? 'unknown number'}'),
            subtitle: const Text('Phone number verified'),
            trailing: TextButton(
              onPressed: gateway.signOut,
              child: const Text('Sign out'),
            ),
          ),
        );
      },
    );
  }
}
