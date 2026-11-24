import 'package:flutter/material.dart';

import '../../core/widgets/site_layout.dart';

import '../../app/sudhamrtam_app.dart';
import '../../database/customer_profile_database_service.dart';
import '../../services/account_api_client.dart';
import '../../services/account_sync_service.dart';
import '../../core/widgets/page_app_bar.dart';

class CustomerProfileScreen extends StatefulWidget {
  CustomerProfileScreen({super.key, AccountSyncService? account})
    : account = account ?? sudhamrtamAccount;

  final AccountSyncService account;

  @override
  State<CustomerProfileScreen> createState() => _CustomerProfileScreenState();
}

class _CustomerProfileScreenState extends State<CustomerProfileScreen> {
  static const Color _brandGreen = Color(0xFF82B440);

  static const String _localCustomerId = AccountSyncService.localCustomerId;

  final _formKey = GlobalKey<FormState>();

  final _nameController = TextEditingController();
  final _phoneController = TextEditingController();
  final _emailController = TextEditingController();

  final _profileService = CustomerProfileDatabaseService.instance;

  /// The OTP-verified number when signed in (not editable).
  String? get _verifiedPhone => widget.account.verifiedPhone;

  bool _isLoading = true;
  bool _isSaving = false;
  String? _loadError;

  String _savedName = '';
  String _savedPhone = '';
  String _savedEmail = '';

  @override
  void initState() {
    super.initState();
    _loadProfile();
  }

  @override
  void dispose() {
    _nameController.dispose();
    _phoneController.dispose();
    _emailController.dispose();
    super.dispose();
  }

  bool get _hasUnsavedChanges {
    return _nameController.text.trim() != _savedName ||
        _phoneController.text.trim() != _savedPhone ||
        _emailController.text.trim() != _savedEmail;
  }

  Future<void> _loadProfile() async {
    setState(() {
      _isLoading = true;
      _loadError = null;
    });

    try {
      final profile = await _profileService.getProfileById(_localCustomerId);

      if (!mounted) return;

      _nameController.text = profile?.fullName ?? '';
      _phoneController.text = _verifiedPhone ?? profile?.phoneNumber ?? '';
      _emailController.text = profile?.email ?? '';

      _savedName = _nameController.text.trim();
      _savedPhone = _phoneController.text.trim();
      _savedEmail = _emailController.text.trim();

      setState(() {
        _isLoading = false;
      });
    } catch (error) {
      if (!mounted) return;

      setState(() {
        _isLoading = false;
        _loadError = 'Unable to load your profile. Please retry.';
      });
    }
  }

  String? _validateName(String? value) {
    final name = value?.trim() ?? '';

    if (name.isEmpty) {
      return 'Please enter your full name.';
    }

    if (name.length < 2) {
      return 'Name must contain at least 2 characters.';
    }

    if (name.length > 100) {
      return 'Name cannot exceed 100 characters.';
    }

    return null;
  }

  String? _validatePhone(String? value) {
    final phone = value?.trim() ?? '';

    if (phone.isEmpty) {
      return null;
    }

    if (!RegExp(r'^[6-9][0-9]{9}$').hasMatch(phone)) {
      return 'Enter a valid 10-digit Indian mobile number.';
    }

    return null;
  }

  String? _validateEmail(String? value) {
    final email = value?.trim() ?? '';

    if (email.isEmpty) {
      return null;
    }

    if (!RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(email)) {
      return 'Enter a valid email address.';
    }

    if (email.length > 254) {
      return 'Email address is too long.';
    }

    return null;
  }

  Future<void> _saveProfile() async {
    if (_isSaving || _isLoading || _loadError != null) {
      return;
    }

    if (!_formKey.currentState!.validate()) {
      return;
    }

    setState(() {
      _isSaving = true;
    });

    try {
      final name = _nameController.text.trim();
      final phone = _phoneController.text.trim();
      final email = _emailController.text.trim();

      await widget.account.saveProfile(
        fullName: name,
        email: email.isEmpty ? null : email,
        phoneNumber: phone.isEmpty ? null : phone,
      );

      if (!mounted) return;

      _nameController.text = name;
      _phoneController.text = phone;
      _emailController.text = email;

      _savedName = name;
      _savedPhone = phone;
      _savedEmail = email;

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Profile saved successfully.'),
          behavior: SnackBarBehavior.floating,
        ),
      );
    } on AccountApiException catch (error) {
      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Profile not saved: ${error.message}'),
          behavior: SnackBarBehavior.floating,
        ),
      );
    } catch (error) {
      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Unable to save profile. Please try again.'),
          behavior: SnackBarBehavior.floating,
        ),
      );
    } finally {
      if (mounted) {
        setState(() {
          _isSaving = false;
        });
      }
    }
  }

  Future<bool> _confirmLeave() async {
    if (_isSaving) {
      return false;
    }

    if (!_hasUnsavedChanges) {
      return true;
    }

    final shouldLeave = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: const Text('Discard changes?'),
          content: const Text(
            'You have unsaved profile changes. '
            'Do you want to leave without saving?',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: const Text('Keep Editing'),
            ),
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(true),
              child: const Text('Discard'),
            ),
          ],
        );
      },
    );

    return shouldLeave ?? false;
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: !_isSaving && !_hasUnsavedChanges,
      onPopInvokedWithResult: (didPop, result) async {
        if (didPop || _isSaving) return;

        if (await _confirmLeave() && context.mounted) {
          Navigator.of(context).pop();
        }
      },
      child: SiteScaffold(
        appBar: PageAppBar(title: const Text('My Profile')),
        body: _buildBody(),
      ),
    );
  }

  Widget _buildBody() {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator(color: _brandGreen));
    }

    if (_loadError != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(
                Icons.error_outline,
                size: 48,
                color: Colors.redAccent,
              ),
              const SizedBox(height: 16),
              Text(_loadError!, textAlign: TextAlign.center),
              const SizedBox(height: 16),
              FilledButton(onPressed: _loadProfile, child: const Text('Retry')),
            ],
          ),
        ),
      );
    }

    return Form(
      key: _formKey,
      child: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          const SizedBox(height: 16),

          const Center(
            child: Icon(
              Icons.account_circle_outlined,
              size: 84,
              color: _brandGreen,
            ),
          ),

          const SizedBox(height: 12),

          Text(
            'My Profile',
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.headlineSmall
                ?.copyWith(fontWeight: FontWeight.bold),
          ),

          const SizedBox(height: 8),

          const Text(
            'Manage your Sudhamrtam customer information',
            textAlign: TextAlign.center,
            style: TextStyle(color: Colors.black54),
          ),

          const SizedBox(height: 32),

          const Text(
            'PERSONAL INFORMATION',
            style: TextStyle(
              fontWeight: FontWeight.bold,
              color: Colors.black54,
              letterSpacing: 1.1,
            ),
          ),

          const SizedBox(height: 16),

          TextFormField(
            controller: _nameController,
            enabled: !_isSaving,
            textCapitalization: TextCapitalization.words,
            textInputAction: TextInputAction.next,
            maxLength: 100,
            decoration: const InputDecoration(
              labelText: 'Full Name *',
              hintText: 'Enter your full name',
              prefixIcon: Icon(Icons.person_outline),
              border: OutlineInputBorder(),
            ),
            validator: _validateName,
            onChanged: (_) => setState(() {}),
          ),

          const SizedBox(height: 12),

          TextFormField(
            key: const Key('profilePhoneField'),
            controller: _phoneController,
            enabled: !_isSaving,
            readOnly: _verifiedPhone != null,
            keyboardType: TextInputType.phone,
            textInputAction: TextInputAction.next,
            maxLength: 10,
            decoration: InputDecoration(
              labelText: _verifiedPhone != null
                  ? 'Mobile Number'
                  : 'Mobile Number (Optional)',
              hintText: '10-digit mobile number',
              prefixIcon: const Icon(Icons.phone_outlined),
              border: const OutlineInputBorder(),
              helperText: _verifiedPhone != null
                  ? 'Verified when you signed in'
                  : 'Not OTP-verified',
            ),
            validator: _validatePhone,
            onChanged: (_) => setState(() {}),
          ),

          const SizedBox(height: 12),

          TextFormField(
            controller: _emailController,
            enabled: !_isSaving,
            keyboardType: TextInputType.emailAddress,
            textInputAction: TextInputAction.done,
            decoration: const InputDecoration(
              labelText: 'Email Address (Optional)',
              hintText: 'Enter your email address',
              prefixIcon: Icon(Icons.email_outlined),
              border: OutlineInputBorder(),
            ),
            validator: _validateEmail,
            onChanged: (_) => setState(() {}),
          ),

          const SizedBox(height: 24),

          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: _brandGreen.withValues(alpha: 0.10),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(Icons.info_outline, color: _brandGreen),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    widget.account.isSignedIn
                        ? 'Your profile is saved to your Sudhamrtam account.'
                        : 'Your profile is saved on this phone only. '
                              'Sign in to keep it in your account.',
                    style: const TextStyle(fontSize: 13),
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: 24),

          FilledButton.icon(
            onPressed: _isSaving ? null : _saveProfile,
            icon: _isSaving
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.save_outlined),
            label: Text(_isSaving ? 'Saving...' : 'Save Profile'),
            style: FilledButton.styleFrom(
              backgroundColor: _brandGreen,
              minimumSize: const Size.fromHeight(52),
            ),
          ),

          const SizedBox(height: 16),
        ],
      ),
    );
  }
}
