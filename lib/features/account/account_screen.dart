import 'package:flutter/material.dart';

import 'customer_name.dart';

import '../../core/widgets/site_layout.dart';

import 'package:url_launcher/url_launcher.dart';

import '../../app/sudhamrtam_app.dart';
import '../../services/account_deletion_client.dart';
import '../../services/api_phone_auth_gateway.dart';
import '../../services/catalog_api_client.dart' show apiBaseUrl;
import '../../services/phone_auth_service.dart';
import 'delete_account_screen.dart';
import '../feedback/feedback_screen.dart';
import '../support/help_support_screen.dart';
import '../milk_bills/milk_bills_screen.dart';
import '../orders/order_history_screen.dart';
import 'customer_profile_screen.dart';
import 'phone_login_screen.dart';
import 'profile_photo.dart';
import 'saved_addresses_screen.dart';
import '../../core/company.dart';

class AccountScreen extends StatelessWidget {
  const AccountScreen({super.key, this.auth});

  /// Optional override for tests; defaults to the app's login.
  final PhoneAuthGateway? auth;

  static const Color _brandGreen = Color(0xFF82B440);

  /// Opens the existing customer order history screen.
  void _openOrderHistory(BuildContext context) {
    Navigator.of(
      context,
    ).push(MaterialPageRoute<void>(builder: (context) => OrderHistoryScreen()));
  }

  /// Opens the customer profile screen.
  void _openCustomerProfile(BuildContext context) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(builder: (context) => CustomerProfileScreen()),
    );
  }

  /// Opens the customer's monthly milk bills.
  void _openMilkBills(BuildContext context) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(builder: (context) => const MilkBillsScreen()),
    );
  }

  void _openFeedback(BuildContext context) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(builder: (context) => const FeedbackScreen()),
    );
  }

  /// Opens the customer's saved delivery addresses.
  void _openSavedAddresses(BuildContext context) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(builder: (context) => SavedAddressesScreen()),
    );
  }

  void _openHelpSupport(BuildContext context) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(builder: (context) => const HelpSupportScreen()),
    );
  }

  /// A policy page (privacy, terms, refunds, contact), in the browser.
  Future<void> _openPage(BuildContext context, String url) async {
    final opened = await launchUrl(
      Uri.parse(url),
      mode: LaunchMode.externalApplication,
    ).catchError((_) => false);
    if (!opened && context.mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('Open $url in your browser.')));
    }
  }

  Future<void> _openDeleteAccount(
    BuildContext context,
    ApiPhoneAuthGateway gateway,
  ) async {
    final deleted = await Navigator.of(context).push<bool>(
      MaterialPageRoute<bool>(
        builder: (_) => DeleteAccountScreen(
          client: AccountDeletionClient(
            baseUrl: apiBaseUrl,
            token: () => gateway.sessionToken,
          ),
          signOut: gateway.signOut,
        ),
      ),
    );
    if (deleted == true && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Your account was deleted.')),
      );
    }
  }

  /// Builds a reusable Account menu tile.
  /// A section's tiles: one under the other on a phone; on a website
  /// (owner, 2026-11-24) three a row, like a shop's account page.
  Widget _tileGroup(BuildContext context, List<Widget> tiles) {
    if (!isWideSite(context)) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: tiles,
      );
    }
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = (constraints.maxWidth - 24) / 3;
        return Wrap(
          spacing: 12,
          children: [
            for (final tile in tiles) SizedBox(width: width, child: tile),
          ],
        );
      },
    );
  }

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

        // Account header: the photo (tap to change) when signed in.
        const Center(child: ProfilePhotoAvatar()),

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

        _tileGroup(context, [
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

          // Milk Bills — monthly bills from the server.
          _buildAccountTile(
            icon: Icons.request_quote_outlined,
            title: 'Milk Bills',
            subtitle: 'See and pay your monthly milk bills',
            onTap: () => _openMilkBills(context),
          ),
        ]),

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

        _tileGroup(context, [
          // Send Feedback — stars, topic and message to the team.
          _buildAccountTile(
            icon: Icons.rate_review_outlined,
            title: 'Send Feedback',
            subtitle: 'Tell us how we are doing',
            onTap: () => _openFeedback(context),
          ),

          // Help & Support: call, email or raise a query.
          _buildAccountTile(
            icon: Icons.help_outline,
            title: 'Help & Support',
            subtitle: 'Call us, email us or raise a query',
            onTap: () => _openHelpSupport(context),
          ),
        ]),

        const SizedBox(height: 20),

        Text(
          'ABOUT',
          style: Theme.of(context).textTheme.labelMedium?.copyWith(
            color: Colors.black54,
            fontWeight: FontWeight.bold,
            letterSpacing: 1.1,
          ),
        ),

        const SizedBox(height: 12),

        _tileGroup(context, [
          _buildAccountTile(
            icon: Icons.privacy_tip_outlined,
            title: 'Privacy Policy',
            subtitle: 'What we collect and how we use it',
            onTap: () => _openPage(context, sudhamrtamPrivacyUrl),
          ),

          _buildAccountTile(
            icon: Icons.description_outlined,
            title: 'Terms of Use',
            subtitle: 'Orders, milk plans, bills and payments',
            onTap: () => _openPage(context, sudhamrtamTermsUrl),
          ),

          _buildAccountTile(
            icon: Icons.currency_rupee,
            title: 'Refunds and Cancellations',
            subtitle: 'Cancel before 9 PM; refunds in 5–7 working days',
            onTap: () => _openPage(context, sudhamrtamRefundsUrl),
          ),

          _buildAccountTile(
            icon: Icons.contact_phone_outlined,
            title: 'Contact us',
            subtitle: 'Phone, email and address',
            onTap: () => _openPage(context, sudhamrtamContactUrl),
          ),
        ]),

        // Delete my account: signed in, with the server only.
        if ((auth ?? sudhamrtamAuth) case final ApiPhoneAuthGateway gateway)
          StreamBuilder<AuthUser?>(
            stream: gateway.authStateChanges(),
            initialData: gateway.currentUser,
            builder: (context, snapshot) => snapshot.data == null
                ? const SizedBox.shrink()
                : Center(
                    child: TextButton.icon(
                      key: const Key('openDeleteAccount'),
                      style: TextButton.styleFrom(
                        foregroundColor: const Color(0xFFC62828),
                      ),
                      onPressed: () => _openDeleteAccount(context, gateway),
                      icon: const Icon(Icons.delete_outline),
                      label: const Text('Delete my account'),
                    ),
                  ),
          ),

        const SizedBox(height: 24),

        // Footer.
        const Center(
          child: Text(
            'Sudhamrtam • Pure by Nature',
            style: TextStyle(color: Colors.black45, fontSize: 12),
          ),
        ),
        const SizedBox(height: 4),
        const Center(
          child: Text(
            '$sudhamrtamCompanyName\n'
            'GSTIN: $sudhamrtamGstin\n'
            'FSSAI Lic. No: $sudhamrtamFssai',
            key: Key('accountLicences'),
            textAlign: TextAlign.center,
            style: TextStyle(color: Colors.black45, fontSize: 11, height: 1.5),
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

        // The name, with the number under it (owner, 2026-11-24).
        return Card(
          child: ListTile(
            leading: const Icon(Icons.verified_user, color: _brandGreen),
            title: SignedInName(
              auth: gateway,
              builder: (context, _, name) => Text(
                'Signed in as ${name ?? phoneText(user.phoneNumber)}',
                key: const Key('accountSignedInAs'),
              ),
            ),
            // The number, and the Reg No on every bill (once a plan is
            // approved).
            subtitle: _RegNoLine(phone: phoneText(user.phoneNumber)),
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

/// "+91 90523 01616 · Reg No: SM-1002 · Phone number verified": the
/// Reg No is the number on every bill (owner decision 2026-11-11), once
/// a plan is approved.
class _RegNoLine extends StatefulWidget {
  const _RegNoLine({required this.phone});

  final String phone;

  @override
  State<_RegNoLine> createState() => _RegNoLineState();
}

class _RegNoLineState extends State<_RegNoLine> {
  late final Future<String?> _regNo = sudhamrtamAccount.refreshRegNo();

  @override
  Widget build(BuildContext context) => FutureBuilder<String?>(
    future: _regNo,
    builder: (context, regNo) => Text(
      [
        if (widget.phone.isNotEmpty) widget.phone,
        if (regNo.data != null) 'Reg No: ${regNo.data}',
        'Phone number verified',
      ].join(' · '),
      key: const Key('accountRegNo'),
    ),
  );
}
