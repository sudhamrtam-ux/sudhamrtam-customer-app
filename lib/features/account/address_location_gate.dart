import 'package:flutter/material.dart';

import '../../app/sudhamrtam_app.dart';
import '../../database/customer_address_database_service.dart';
import '../../models/customer_address.dart';
import '../../services/account_sync_service.dart';
import 'address_form_screen.dart';

/// The address milk goes to: the default one, else the first.
CustomerAddress? milkAddress(List<CustomerAddress> addresses) =>
    addresses.where((a) => a.isDefault).firstOrNull ?? addresses.firstOrNull;

/// Asked before a new milk plan is saved; true when it may go on.
typedef MilkAddressCheck = Future<bool> Function(BuildContext context);

Future<List<CustomerAddress>> _savedAddresses() =>
    CustomerAddressDatabaseService.instance.getAddressesByCustomerId(
      AccountSyncService.localCustomerId,
    );

/// Before a new milk plan (owner decision 2026-11-16): the address the
/// milk goes to must have its spot on the map. If it has none, offers
/// the address form and checks again after it closes.
///
/// Builds without a server deliver nothing, so they are not asked.
Future<bool> checkMilkAddressLocation(
  BuildContext context, {
  bool? hasServer,
  Future<List<CustomerAddress>> Function() loadAddresses = _savedAddresses,
}) async {
  if (!(hasServer ?? sudhamrtamAuth != null)) return true;

  final address = milkAddress(await loadAddresses());
  if (address != null && address.hasMapLocation) return true;
  if (!context.mounted) return false;

  final go = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      key: const Key('milkAddressLocationDialog'),
      title: const Text('Mark your home on the map'),
      content: Text(
        address == null
            ? 'Please add your delivery address and mark it on the map, '
                  'so our delivery partner can reach you.'
            : 'Your ${address.label} address is not marked on the map yet. '
                  'Please mark it, so our delivery partner can reach you.',
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, false),
          child: const Text('Not now'),
        ),
        FilledButton(
          key: const Key('milkAddressLocationAdd'),
          style: FilledButton.styleFrom(
            backgroundColor: const Color(0xFF82B440),
          ),
          onPressed: () => Navigator.pop(context, true),
          child: Text(address == null ? 'Add address' : 'Add location'),
        ),
      ],
    ),
  );
  if (go != true || !context.mounted) return false;

  await Navigator.of(context).push<bool>(
    MaterialPageRoute<bool>(
      builder: (_) => AddressFormScreen(existingAddress: address),
    ),
  );
  return milkAddress(await loadAddresses())?.hasMapLocation ?? false;
}
