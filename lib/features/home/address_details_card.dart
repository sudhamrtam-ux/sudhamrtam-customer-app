import 'package:flutter/material.dart';

import '../../app/sudhamrtam_app.dart';
import '../../database/customer_address_database_service.dart';
import '../../database/milk_database_service.dart';
import '../../models/customer_address.dart';
import '../../services/account_sync_service.dart';
import '../account/address_form_screen.dart';

/// The app setting that remembers "Not now".
const addressDetailsDismissedKey = 'address_details_dismissed';

Future<List<CustomerAddress>> _savedAddresses() =>
    CustomerAddressDatabaseService.instance.getAddressesByCustomerId(
      AccountSyncService.localCustomerId,
    );

Future<bool> _isDismissed() async {
  final db = await MilkDatabaseService.instance.database;
  final rows = await db.query(
    MilkDatabaseService.appSettingsTable,
    where: 'key = ?',
    whereArgs: [addressDetailsDismissedKey],
    limit: 1,
  );
  return rows.isNotEmpty;
}

Future<void> _dismiss() async {
  final db = await MilkDatabaseService.instance.database;
  await db.rawInsert(
    'INSERT OR REPLACE INTO ${MilkDatabaseService.appSettingsTable} '
    '(key, value) VALUES (?, ?)',
    [addressDetailsDismissedKey, DateTime.now().toIso8601String()],
  );
}

/// On Home, once (owner decision 2026-11-11): asks a customer whose
/// saved address has no society, block or flat to add them, so the
/// delivery partner finds them faster. "Not now" hides it for good.
///
/// An address not marked on the map (owner decision 2026-11-16) is
/// asked first, and that card stays until it is marked: new orders and
/// milk plans need it.
class AddressDetailsCard extends StatefulWidget {
  const AddressDetailsCard({
    super.key,
    this.account,
    this.asksForLocation,
    this.loadAddresses = _savedAddresses,
    this.isDismissed = _isDismissed,
    this.dismiss = _dismiss,
    this.openForm,
  });

  /// Reloads when addresses change; defaults to the app's account.
  final AccountSyncService? account;

  /// Asks for the map spot; defaults to builds with a server (the
  /// only ones that deliver).
  final bool? asksForLocation;
  final Future<List<CustomerAddress>> Function() loadAddresses;
  final Future<bool> Function() isDismissed;
  final Future<void> Function() dismiss;

  /// Opens the address form; tests replace it.
  final Future<void> Function(BuildContext, CustomerAddress)? openForm;

  @override
  State<AddressDetailsCard> createState() => _AddressDetailsCardState();
}

class _AddressDetailsCardState extends State<AddressDetailsCard> {
  CustomerAddress? _needing;

  /// True when [_needing] lacks its spot on the map.
  bool _needsLocation = false;
  late final AccountSyncService _account = widget.account ?? sudhamrtamAccount;

  @override
  void initState() {
    super.initState();
    _account.addListener(_check);
    _check();
  }

  @override
  void dispose() {
    _account.removeListener(_check);
    super.dispose();
  }

  Future<void> _check() async {
    try {
      final addresses = await widget.loadAddresses();
      // The default address first: that is where milk goes.
      final ordered = [
        ...addresses.where((a) => a.isDefault),
        ...addresses.where((a) => !a.isDefault),
      ];
      if (widget.asksForLocation ?? sudhamrtamAuth != null) {
        final unmarked = [
          for (final a in ordered)
            if (!a.hasMapLocation) a,
        ].firstOrNull;
        if (unmarked != null) {
          if (mounted) {
            setState(() {
              _needing = unmarked;
              _needsLocation = true;
            });
          }
          return;
        }
      }
      if (await widget.isDismissed()) {
        if (mounted) {
          setState(() {
            _needing = null;
            _needsLocation = false;
          });
        }
        return;
      }
      final needing = [
        for (final a in ordered)
          if (a.needsDetails) a,
      ].firstOrNull;
      if (mounted) {
        setState(() {
          _needing = needing;
          _needsLocation = false;
        });
      }
    } catch (_) {
      // Only a reminder: never get in the way of Home.
    }
  }

  Future<void> _open(CustomerAddress address) async {
    final open = widget.openForm;
    if (open != null) {
      await open(context, address);
    } else {
      await Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => AddressFormScreen(existingAddress: address),
        ),
      );
    }
    await _check();
  }

  @override
  Widget build(BuildContext context) {
    final address = _needing;
    if (address == null) return const SizedBox.shrink();
    const brandGreen = Color(0xFF82B440);
    return Card(
      key: const Key('addressDetailsCard'),
      margin: const EdgeInsets.only(bottom: 16),
      color: const Color(0xFFFFF8E1),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: const BorderSide(color: Color(0xFFFFCC80)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  _needsLocation ? Icons.pin_drop_outlined : Icons.apartment,
                  color: const Color(0xFFEF6C00),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    _needsLocation
                        ? 'Mark your home on the map'
                        : 'Help us find your door faster',
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 16,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              _needsLocation
                  ? 'Your ${address.label} address is not marked on the map '
                        'yet. Mark it so our delivery partner can reach you. '
                        'New orders and milk plans need it.'
                  : 'Please add your society, block/tower and flat number '
                        'to your ${address.label} address. Our delivery '
                        'partners deliver one building at a time.',
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                FilledButton(
                  key: const Key('addressDetailsAdd'),
                  style: FilledButton.styleFrom(backgroundColor: brandGreen),
                  onPressed: () => _open(address),
                  child: Text(_needsLocation ? 'Add location' : 'Add now'),
                ),
                const SizedBox(width: 8),
                // The map spot is required, so it cannot be put off.
                if (!_needsLocation)
                  TextButton(
                    key: const Key('addressDetailsLater'),
                    onPressed: () async {
                      await widget.dismiss();
                      if (mounted) setState(() => _needing = null);
                    },
                    child: const Text('Not now'),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
