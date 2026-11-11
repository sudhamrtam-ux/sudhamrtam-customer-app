import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';

import '../database/customer_address_database_service.dart';
import '../database/customer_profile_database_service.dart';
import '../database/milk_database_service.dart';
import '../models/customer_address.dart';
import '../models/customer_profile.dart';
import 'account_api_client.dart';
import 'phone_auth_service.dart';

/// Keeps the phone's profile and saved addresses in step with the
/// signed-in customer's account on the server.
///
/// The phone keeps one local copy (customer ID `local_customer`),
/// which checkout and the account screens read, also offline.
///
/// - **Signed out:** changes are saved on the phone only.
/// - **First sync for an account:** the profile and addresses
///   already on the phone are uploaded (the server's own values
///   win), then the phone mirrors the server.
/// - **Signed in:** every change is saved to the server first and
///   then on the phone; without a connection nothing changes.
///   At start-up the phone refreshes its copy from the server.
/// - **Sign-out:** the phone's copy is removed (it is safe on the
///   server), so the next person to sign in does not inherit it.
class AccountSyncService extends ChangeNotifier {
  AccountSyncService({this.api, this.auth});

  /// Local-only mode: no server, no sign-in.
  AccountSyncService.localOnly() : api = null, auth = null;

  static const String localCustomerId = 'local_customer';

  static const String _linkedKey = 'account_linked_customer_id';
  static const String _regNoKey = 'account_reg_no';

  /// The customer's Reg No from the last sync (null without one).
  Future<String?> regNo() async {
    try {
      return await _getSetting(_regNoKey);
    } catch (_) {
      return null;
    }
  }

  /// Asks the server for the Reg No (it is given when a plan is
  /// approved, maybe after the last sync); offline, the saved one.
  /// Queued after other syncs, so an older one cannot overwrite it.
  Future<String?> refreshRegNo() => _serial(() async {
    final client = api;
    if (!isSignedIn || client == null) return regNo();
    try {
      final profile = await client.getProfile();
      await _setSetting(_regNoKey, profile.regNo);
      return profile.regNo;
    } catch (_) {
      return regNo();
    }
  });

  static const String _unsyncedKey = 'account_unsynced_address_ids';

  final AccountApiClient? api;
  final PhoneAuthGateway? auth;

  final _addresses = CustomerAddressDatabaseService.instance;
  final _profiles = CustomerProfileDatabaseService.instance;

  StreamSubscription<AuthUser?>? _authSubscription;
  Future<void> _queue = Future.value();

  /// Message from the last failed background sync, if any.
  String? lastSyncError;

  bool get isSignedIn => api != null && auth?.currentUser != null;

  /// The signed-in phone number without +91, if signed in.
  String? get verifiedPhone {
    final phone = isSignedIn ? auth!.currentUser!.phoneNumber : null;
    if (phone == null) return null;
    return phone.startsWith('+91') ? phone.substring(3) : phone;
  }

  /// Starts following sign-in and sign-out. Call once.
  void attach() {
    final gateway = auth;
    if (gateway == null || api == null) return;

    _authSubscription = gateway.authStateChanges().listen((user) {
      unawaited(user == null ? _onSignedOut() : syncNow());
    });

    if (gateway.currentUser != null) unawaited(syncNow());
  }

  @override
  void dispose() {
    _authSubscription?.cancel();
    super.dispose();
  }

  /// Runs [action] after every earlier sync operation finished.
  Future<T> _serial<T>(Future<T> Function() action) {
    final result = _queue.then((_) => action());
    _queue = result.then((_) {}, onError: (_) {});
    return result;
  }

  /// Uploads (first time) or refreshes the phone's copy.
  /// Never throws; a failure is kept in [lastSyncError].
  Future<void> syncNow() => _serial(() async {
    final user = auth?.currentUser;
    final client = api;
    if (user == null || client == null) return;

    try {
      if (await _getSetting(_linkedKey) != user.uid) {
        await _uploadPhoneData(client);
        await _setSetting(_linkedKey, user.uid);
      } else {
        await _pull(client);
      }
      lastSyncError = null;
    } on AccountApiException catch (error) {
      lastSyncError = error.message;
      if (error.unauthorized) await auth?.signOut();
    } catch (error) {
      lastSyncError = 'Could not update your account: $error';
    }
    notifyListeners();
  });

  /// First sync for an account: send what is on the phone.
  Future<void> _uploadPhoneData(AccountApiClient client) async {
    final serverProfile = await client.getProfile();
    final serverAddresses = await client.listAddresses(
      localCustomerId: localCustomerId,
    );
    final localProfile = await _profiles.getProfileById(localCustomerId);
    final localAddresses = await _addresses.getAddressesByCustomerId(
      localCustomerId,
    );

    // The server's values win; only fill what it lacks.
    final name = localProfile?.fullName.trim() ?? '';
    final email = localProfile?.email?.trim() ?? '';
    final sendName = (serverProfile.fullName == null && name.isNotEmpty);
    final sendEmail = (serverProfile.email == null && email.isNotEmpty);
    if (sendName || sendEmail) {
      try {
        await client.updateProfile(
          fullName: sendName ? name : null,
          email: sendEmail ? email : null,
        );
      } on AccountApiException catch (error) {
        if (!error.rejected) rethrow;
      }
    }

    final serverIds = {for (final a in serverAddresses) a.id};
    final serverHasDefault = serverAddresses.any((a) => a.isDefault);
    final unsynced = <String>[];

    for (final address in localAddresses) {
      if (serverIds.contains(address.id)) continue;
      try {
        await client.putAddress(
          serverHasDefault ? address.copyWith(isDefault: false) : address,
        );
      } on AccountApiException catch (error) {
        // Invalid for the server: keep it on the phone for the
        // customer to fix, instead of losing it.
        if (!error.rejected) rethrow;
        unsynced.add(address.id);
      }
    }

    await _setSetting(_unsyncedKey, jsonEncode(unsynced));
    await _pull(client);
  }

  /// Replaces the phone's copy with the server's, keeping addresses
  /// that could not be uploaded yet.
  Future<void> _pull(AccountApiClient client) async {
    final profile = await client.getProfile();
    final serverAddresses = await client.listAddresses(
      localCustomerId: localCustomerId,
    );

    final unsyncedIds = await _unsyncedIds();
    final serverIds = {for (final a in serverAddresses) a.id};
    final keep = [
      for (final address in await _addresses.getAddressesByCustomerId(
        localCustomerId,
      ))
        if (unsyncedIds.contains(address.id) && !serverIds.contains(address.id))
          address.copyWith(isDefault: false),
    ];

    await _profiles.saveSyncedProfile(
      customerId: localCustomerId,
      fullName: profile.fullName ?? '',
      phoneNumber: verifiedPhone,
      email: profile.email,
    );
    await _setSetting(_regNoKey, profile.regNo);
    await _addresses.replaceAllAddresses(localCustomerId, [
      ...serverAddresses,
      ...keep,
    ]);
    await _setSetting(_unsyncedKey, jsonEncode([for (final a in keep) a.id]));
  }

  Future<void> _onSignedOut() => _serial(() async {
    await _profiles.deleteProfile(localCustomerId);
    await _setSetting(_linkedKey, null);
    await _setSetting(_unsyncedKey, null);
    await _setSetting(_regNoKey, null);
    lastSyncError = null;
    notifyListeners();
  });

  // ---- Changes made by the customer ----------------------------

  /// Saves (creates or updates) an address. When signed in it is
  /// saved to the server first; throws [AccountApiException] if
  /// that fails, and then nothing changes on the phone.
  Future<void> saveAddress(CustomerAddress address) => _serial(() async {
    var toStore = address;
    final client = api;

    if (isSignedIn && client != null) {
      toStore = await _call(() => client.putAddress(address));
      await _removeUnsynced(address.id);
    }

    await _ensureLocalProfile();
    final exists = await _addresses.getAddressById(address.id) != null;
    if (exists) {
      await _addresses.updateAddress(toStore);
    } else {
      await _addresses.saveAddress(toStore);
    }
    notifyListeners();
  });

  Future<void> deleteAddress(String addressId) => _serial(() async {
    final client = api;
    if (isSignedIn && client != null) {
      await _call(() => client.deleteAddress(addressId));
      await _removeUnsynced(addressId);
    }
    await _addresses.deleteAddress(
      customerId: localCustomerId,
      addressId: addressId,
    );
    notifyListeners();
  });

  Future<void> setDefaultAddress(String addressId) => _serial(() async {
    final client = api;
    if (isSignedIn && client != null && !(await _isUnsynced(addressId))) {
      await _call(() => client.setDefaultAddress(addressId));
    }
    await _addresses.setDefaultAddress(
      customerId: localCustomerId,
      addressId: addressId,
    );
    notifyListeners();
  });

  /// Saves name, email and (signed out only) phone.
  Future<void> saveProfile({
    required String fullName,
    String? email,
    String? phoneNumber,
  }) => _serial(() async {
    final client = api;

    if (isSignedIn && client != null) {
      final saved = await _call(
        () => client.updateProfile(fullName: fullName, email: email ?? ''),
      );
      await _profiles.saveSyncedProfile(
        customerId: localCustomerId,
        fullName: saved.fullName ?? '',
        phoneNumber: verifiedPhone,
        email: saved.email,
      );
    } else {
      final existing = await _profiles.getProfileById(localCustomerId);
      final now = DateTime.now();
      await _profiles.saveProfile(
        CustomerProfile(
          id: localCustomerId,
          fullName: fullName,
          phoneNumber: phoneNumber,
          email: email,
          createdAt: existing?.createdAt ?? now,
          updatedAt: now,
        ),
      );
    }
    notifyListeners();
  });

  /// Calls the server; on an ended session, signs out and rethrows.
  Future<T> _call<T>(Future<T> Function() request) async {
    try {
      return await request();
    } on AccountApiException catch (error) {
      if (error.unauthorized) unawaited(auth?.signOut());
      rethrow;
    }
  }

  /// Addresses need a profile row on the phone.
  Future<void> _ensureLocalProfile() async {
    if (await _profiles.profileExists(localCustomerId)) return;
    await _profiles.saveSyncedProfile(
      customerId: localCustomerId,
      fullName: '',
      phoneNumber: verifiedPhone,
    );
  }

  // ---- Small settings store (app_settings table) ---------------

  Future<Set<String>> _unsyncedIds() async {
    final raw = await _getSetting(_unsyncedKey);
    if (raw == null) return {};
    try {
      return {for (final id in jsonDecode(raw) as List) id as String};
    } catch (_) {
      return {};
    }
  }

  Future<bool> _isUnsynced(String id) async =>
      (await _unsyncedIds()).contains(id);

  Future<void> _removeUnsynced(String id) async {
    final ids = await _unsyncedIds();
    if (ids.remove(id)) {
      await _setSetting(_unsyncedKey, jsonEncode(ids.toList()));
    }
  }

  Future<String?> _getSetting(String key) async {
    final db = await MilkDatabaseService.instance.database;
    final rows = await db.query(
      MilkDatabaseService.appSettingsTable,
      where: 'key = ?',
      whereArgs: [key],
      limit: 1,
    );
    return rows.isEmpty ? null : rows.first['value'] as String;
  }

  Future<void> _setSetting(String key, String? value) async {
    final db = await MilkDatabaseService.instance.database;
    if (value == null) {
      await db.delete(
        MilkDatabaseService.appSettingsTable,
        where: 'key = ?',
        whereArgs: [key],
      );
    } else {
      await db.rawInsert(
        'INSERT OR REPLACE INTO ${MilkDatabaseService.appSettingsTable} '
        '(key, value) VALUES (?, ?)',
        [key, value],
      );
    }
  }
}
