import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/widgets/site_layout.dart';

import '../../app/sudhamrtam_app.dart';
import '../../database/customer_address_database_service.dart';
import '../../models/customer_address.dart';
import '../../services/account_api_client.dart';
import '../../services/account_sync_service.dart';
import 'address_form_screen.dart';
import '../../core/widgets/page_app_bar.dart';

class SavedAddressesScreen extends StatefulWidget {
  SavedAddressesScreen({super.key, AccountSyncService? account})
    : account = account ?? sudhamrtamAccount;

  final AccountSyncService account;

  @override
  State<SavedAddressesScreen> createState() => _SavedAddressesScreenState();
}

class _SavedAddressesScreenState extends State<SavedAddressesScreen> {
  static const Color _brandGreen = Color(0xFF82B440);
  static const String _customerId = AccountSyncService.localCustomerId;

  final _addressService = CustomerAddressDatabaseService.instance;

  bool _isLoading = true;
  bool _isDeleting = false;
  bool _isUpdatingDefault = false;

  String? _errorMessage;
  List<CustomerAddress> _addresses = [];

  @override
  void initState() {
    super.initState();
    widget.account.addListener(_onAccountChanged);
    _loadAddresses();
    // Fetch the latest from the account (no-op when signed out).
    unawaited(widget.account.syncNow());
  }

  @override
  void dispose() {
    widget.account.removeListener(_onAccountChanged);
    super.dispose();
  }

  void _onAccountChanged() {
    if (!_isDeleting && !_isUpdatingDefault) _loadAddresses();
  }

  /// A readable message for a failed change.
  String _reason(Object error) =>
      error is AccountApiException ? error.message : '$error';

  Future<void> _loadAddresses() async {
    if (!mounted) return;

    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final addresses = await _addressService.getAddressesByCustomerId(
        _customerId,
      );

      if (!mounted) return;

      setState(() {
        _addresses = addresses;
        _isLoading = false;
      });
    } catch (error) {
      if (!mounted) return;

      setState(() {
        _errorMessage = error.toString();
        _isLoading = false;
      });
    }
  }

  void _showMessage(String message) {
    if (!mounted) return;

    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(content: Text(message), behavior: SnackBarBehavior.floating),
      );
  }

  Future<void> _openAddAddressForm() async {
    if (_isDeleting || _isUpdatingDefault) return;

    final saved = await Navigator.of(context).push<bool>(
      MaterialPageRoute<bool>(
        builder: (context) => AddressFormScreen(account: widget.account),
      ),
    );

    if (!mounted) return;

    await _loadAddresses();

    if (!mounted) return;

    if (saved == true) {
      _showMessage('Delivery address added successfully!');
    }
  }

  Future<void> _openEditAddressForm(CustomerAddress address) async {
    if (_isDeleting || _isUpdatingDefault) return;

    final updated = await Navigator.of(context).push<bool>(
      MaterialPageRoute<bool>(
        builder: (context) => AddressFormScreen(
          existingAddress: address,
          account: widget.account,
        ),
      ),
    );

    if (!mounted) return;

    await _loadAddresses();

    if (!mounted) return;

    if (updated == true) {
      _showMessage('Delivery address updated successfully!');
    }
  }

  Future<void> _setDefaultAddress(CustomerAddress address) async {
    if (address.isDefault || _isDeleting || _isUpdatingDefault) {
      return;
    }

    setState(() {
      _isUpdatingDefault = true;
    });

    try {
      await widget.account.setDefaultAddress(address.id);

      if (!mounted) return;

      await _loadAddresses();

      if (!mounted) return;

      _showMessage('Default delivery address updated successfully!');
    } catch (error) {
      _showMessage('Unable to set default address: ${_reason(error)}');
    } finally {
      if (mounted) {
        setState(() {
          _isUpdatingDefault = false;
        });
      }
    }
  }

  Future<void> _deleteAddress(CustomerAddress address) async {
    if (_isDeleting || _isUpdatingDefault) return;

    // First protection: reject deletion of the default address.
    if (address.isDefault) {
      _showMessage(
        'This is your default delivery address. '
        'Please set another address as default before deleting it.',
      );
      return;
    }

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Delete Delivery Address?'),
        content: Text(
          'Are you sure you want to delete the '
          '${address.label} address?\n\n'
          'This action cannot be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.of(dialogContext).pop(false);
            },
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () {
              Navigator.of(dialogContext).pop(true);
            },
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirmed != true || !mounted) return;

    if (_isDeleting || _isUpdatingDefault) return;

    setState(() {
      _isDeleting = true;
    });

    try {
      // Second protection: check the latest database state.
      // This prevents deleting an address that became default
      // after the card was originally loaded.
      final currentAddress = await _addressService.getAddressById(address.id);

      if (!mounted) return;

      if (currentAddress == null) {
        _showMessage('This address no longer exists. Refreshing the list.');
        await _loadAddresses();
        return;
      }

      if (currentAddress.customerId != _customerId) {
        _showMessage('This address does not belong to the current customer.');
        return;
      }

      if (currentAddress.isDefault) {
        _showMessage(
          'Cannot delete the default delivery address. '
          'Please select another default address first.',
        );
        await _loadAddresses();
        return;
      }

      await widget.account.deleteAddress(address.id);

      if (!mounted) return;

      await _loadAddresses();

      if (!mounted) return;

      _showMessage('Delivery address deleted successfully!');
    } catch (error) {
      _showMessage('Unable to delete address: ${_reason(error)}');
    } finally {
      if (mounted) {
        setState(() {
          _isDeleting = false;
        });
      }
    }
  }

  Widget _buildAddressCard(CustomerAddress address) {
    final isBusy = _isDeleting || _isUpdatingDefault;

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.location_on_outlined, color: _brandGreen),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    address.label,
                    style: const TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                if (address.isDefault)
                  const Chip(
                    label: Text('Default'),
                    backgroundColor: Color(0xFFEAF4DB),
                  ),
              ],
            ),

            const SizedBox(height: 8),

            Text(
              address.recipientName,
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),

            const SizedBox(height: 4),
            Text(address.phoneNumber),

            const SizedBox(height: 8),
            Text(address.formattedAddress),

            if (address.hasMapLocation) ...[
              const SizedBox(height: 8),
              const Row(
                children: [
                  Icon(Icons.pin_drop_outlined, size: 18, color: _brandGreen),
                  SizedBox(width: 6),
                  Text('Map location saved'),
                ],
              ),
            ],

            if (address.isDefault) ...[
              const SizedBox(height: 12),
              const Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(Icons.lock_outline, size: 17, color: _brandGreen),
                  SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      'Protected default address. '
                      'Set another address as default to enable deletion.',
                      style: TextStyle(fontSize: 12, color: Colors.black54),
                    ),
                  ),
                ],
              ),
            ],

            const SizedBox(height: 12),
            const Divider(),
            const SizedBox(height: 4),

            Wrap(
              alignment: WrapAlignment.end,
              spacing: 8,
              runSpacing: 8,
              children: [
                if (!address.isDefault)
                  OutlinedButton.icon(
                    onPressed: isBusy
                        ? null
                        : () => _setDefaultAddress(address),
                    icon: const Icon(Icons.check_circle_outline, size: 18),
                    label: const Text('Set as Default'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: _brandGreen,
                      side: const BorderSide(color: _brandGreen),
                    ),
                  ),

                OutlinedButton.icon(
                  onPressed: isBusy
                      ? null
                      : () => _openEditAddressForm(address),
                  icon: const Icon(Icons.edit_outlined, size: 18),
                  label: const Text('Edit Address'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: _brandGreen,
                    side: const BorderSide(color: _brandGreen),
                  ),
                ),

                // Delete is disabled for the default address.
                OutlinedButton.icon(
                  onPressed: isBusy || address.isDefault
                      ? null
                      : () => _deleteAddress(address),
                  icon: const Icon(Icons.delete_outline, size: 18),
                  label: const Text('Delete'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.red,
                    disabledForegroundColor: Colors.grey,
                    side: BorderSide(
                      color: address.isDefault ? Colors.grey : Colors.red,
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              Icons.location_off_outlined,
              size: 72,
              color: _brandGreen,
            ),
            const SizedBox(height: 16),
            const Text(
              'No saved addresses yet',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            const Text(
              'Add your first delivery address to get started.',
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 20),
            FilledButton.icon(
              onPressed: _openAddAddressForm,
              icon: const Icon(Icons.add_location_alt_outlined),
              label: const Text('Add New Address'),
              style: FilledButton.styleFrom(
                backgroundColor: _brandGreen,
                foregroundColor: Colors.white,
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isBusy = _isDeleting || _isUpdatingDefault;

    return SiteScaffold(
      appBar: PageAppBar(title: const Text('Saved Addresses')),

      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _errorMessage != null
          ? Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(_errorMessage!, textAlign: TextAlign.center),
                    const SizedBox(height: 12),
                    OutlinedButton(
                      onPressed: _loadAddresses,
                      child: const Text('Retry'),
                    ),
                  ],
                ),
              ),
            )
          : _addresses.isEmpty
          ? _buildEmptyState()
          : RefreshIndicator(
              onRefresh: _loadAddresses,
              child: ListView.builder(
                padding: const EdgeInsets.all(16),
                itemCount: _addresses.length,
                itemBuilder: (context, index) {
                  return _buildAddressCard(_addresses[index]);
                },
              ),
            ),

      floatingActionButton: _addresses.isNotEmpty && !_isLoading
          ? FloatingActionButton.extended(
              onPressed: isBusy ? null : _openAddAddressForm,
              backgroundColor: _brandGreen,
              foregroundColor: Colors.white,
              icon: const Icon(Icons.add),
              label: const Text('Add Address'),
            )
          : null,
    );
  }
}
