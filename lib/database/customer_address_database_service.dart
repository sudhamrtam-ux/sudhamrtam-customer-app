import 'package:sqflite/sqflite.dart';

import '../models/customer_address.dart';
import 'milk_database_service.dart';

/// Manages locally saved customer delivery addresses.
///
/// All addresses belong to an existing local customer profile.
/// Server synchronization is done by AccountSyncService.
class CustomerAddressDatabaseService {
  CustomerAddressDatabaseService._();

  static final CustomerAddressDatabaseService instance =
      CustomerAddressDatabaseService._();

  static const String _table = MilkDatabaseService.customerAddressesTable;

  static const String _profilesTable =
      MilkDatabaseService.customerProfilesTable;

  /// Saves a new address.
  ///
  /// Returns false if the address ID already exists.
  /// Throws StateError if the customer profile does not exist.
  ///
  /// A new address marked as default replaces the previous default
  /// within the same SQLite transaction.
  Future<bool> saveAddress(CustomerAddress address) async {
    _validateAddress(address);

    final db = await MilkDatabaseService.instance.database;

    return db.transaction((txn) async {
      await _requireCustomer(txn, address.customerId);

      final existing = await txn.query(
        _table,
        columns: ['id'],
        where: 'id = ?',
        whereArgs: [address.id],
        limit: 1,
      );

      if (existing.isNotEmpty) {
        return false;
      }

      if (address.isDefault) {
        await _clearDefault(txn, address.customerId, address.updatedAt);
      }

      await txn.insert(_table, address.toMap());
      return true;
    });
  }

  /// Returns all saved addresses for a customer.
  ///
  /// The default address appears first.
  Future<List<CustomerAddress>> getAddressesByCustomerId(
    String customerId,
  ) async {
    if (customerId.trim().isEmpty) {
      return [];
    }

    final db = await MilkDatabaseService.instance.database;

    final rows = await db.query(
      _table,
      where: 'customer_id = ?',
      whereArgs: [customerId],
      orderBy: 'is_default DESC, created_at ASC, id ASC',
    );

    return rows.map(CustomerAddress.fromMap).toList();
  }

  /// Returns an address by its unique ID.
  Future<CustomerAddress?> getAddressById(String addressId) async {
    if (addressId.trim().isEmpty) {
      return null;
    }

    final db = await MilkDatabaseService.instance.database;

    final rows = await db.query(
      _table,
      where: 'id = ?',
      whereArgs: [addressId],
      limit: 1,
    );

    if (rows.isEmpty) {
      return null;
    }

    return CustomerAddress.fromMap(rows.first);
  }

  /// Returns the default address for a customer, if one exists.
  Future<CustomerAddress?> getDefaultAddress(String customerId) async {
    if (customerId.trim().isEmpty) {
      return null;
    }

    final db = await MilkDatabaseService.instance.database;

    final rows = await db.query(
      _table,
      where: 'customer_id = ? AND is_default = 1',
      whereArgs: [customerId],
      limit: 1,
    );

    if (rows.isEmpty) {
      return null;
    }

    return CustomerAddress.fromMap(rows.first);
  }

  /// Updates an existing address.
  ///
  /// Returns false if the address does not exist or does not
  /// belong to the specified customer.
  ///
  /// Customer ownership cannot be changed.
  Future<bool> updateAddress(CustomerAddress address) async {
    _validateAddress(address);

    final db = await MilkDatabaseService.instance.database;

    return db.transaction((txn) async {
      final existing = await txn.query(
        _table,
        columns: ['id'],
        where: 'id = ? AND customer_id = ?',
        whereArgs: [address.id, address.customerId],
        limit: 1,
      );

      if (existing.isEmpty) {
        return false;
      }

      if (address.isDefault) {
        await _clearDefault(txn, address.customerId, address.updatedAt);
      }

      // Do not modify the primary key, customer ownership,
      // or original creation timestamp.
      final updated = await txn.update(
        _table,
        {
          'area_id': address.areaId,
          'label': address.label,
          'recipient_name': address.recipientName,
          'phone_number': address.phoneNumber,
          'address_line_1': address.addressLine1,
          'address_line_2': address.addressLine2,
          'landmark': address.landmark,
          'city': address.city,
          'state': address.state,
          'postal_code': address.postalCode,
          'latitude': address.latitude,
          'longitude': address.longitude,
          'is_default': address.isDefault ? 1 : 0,
          'updated_at': address.updatedAt.toIso8601String(),
        },
        where: 'id = ? AND customer_id = ?',
        whereArgs: [address.id, address.customerId],
      );

      return updated > 0;
    });
  }

  /// Makes an existing address the customer's default.
  ///
  /// Returns false if the address does not belong to the customer.
  Future<bool> setDefaultAddress({
    required String customerId,
    required String addressId,
  }) async {
    if (customerId.trim().isEmpty || addressId.trim().isEmpty) {
      return false;
    }

    final db = await MilkDatabaseService.instance.database;

    return db.transaction((txn) async {
      final rows = await txn.query(
        _table,
        columns: ['id'],
        where: 'id = ? AND customer_id = ?',
        whereArgs: [addressId, customerId],
        limit: 1,
      );

      if (rows.isEmpty) {
        return false;
      }

      final now = DateTime.now();

      await _clearDefault(txn, customerId, now);

      final updated = await txn.update(
        _table,
        {'is_default': 1, 'updated_at': now.toIso8601String()},
        where: 'id = ? AND customer_id = ?',
        whereArgs: [addressId, customerId],
      );

      return updated > 0;
    });
  }

  /// Deletes a saved address.
  ///
  /// Returns false if the address does not exist or belongs
  /// to a different customer.
  ///
  /// Deleting a default address does not automatically assign
  /// another default. The customer can choose one explicitly.
  Future<bool> deleteAddress({
    required String customerId,
    required String addressId,
  }) async {
    if (customerId.trim().isEmpty || addressId.trim().isEmpty) {
      return false;
    }

    final db = await MilkDatabaseService.instance.database;

    final deleted = await db.delete(
      _table,
      where: 'id = ? AND customer_id = ?',
      whereArgs: [addressId, customerId],
    );

    return deleted > 0;
  }

  /// Replaces all of a customer's addresses with [addresses]
  /// in one transaction (used to mirror the server's list).
  Future<void> replaceAllAddresses(
    String customerId,
    List<CustomerAddress> addresses,
  ) async {
    for (final address in addresses) {
      _validateAddress(address);
      if (address.customerId != customerId) {
        throw ArgumentError('Address ${address.id} belongs to another customer.');
      }
    }

    final db = await MilkDatabaseService.instance.database;

    await db.transaction((txn) async {
      await _requireCustomer(txn, customerId);
      await txn.delete(
        _table,
        where: 'customer_id = ?',
        whereArgs: [customerId],
      );
      for (final address in addresses) {
        await txn.insert(_table, address.toMap());
      }
    });
  }

  /// Deletes every saved address of a customer.
  Future<void> deleteAllAddresses(String customerId) async {
    final db = await MilkDatabaseService.instance.database;
    await db.delete(_table, where: 'customer_id = ?', whereArgs: [customerId]);
  }

  /// Removes the default flag from every address belonging
  /// to the specified customer.
  Future<void> _clearDefault(
    Transaction txn,
    String customerId,
    DateTime updatedAt,
  ) async {
    await txn.update(
      _table,
      {'is_default': 0, 'updated_at': updatedAt.toIso8601String()},
      where: 'customer_id = ? AND is_default = 1',
      whereArgs: [customerId],
    );
  }

  /// Verifies that the parent customer profile exists.
  Future<void> _requireCustomer(Transaction txn, String customerId) async {
    final rows = await txn.query(
      _profilesTable,
      columns: ['id'],
      where: 'id = ?',
      whereArgs: [customerId],
      limit: 1,
    );

    if (rows.isEmpty) {
      throw StateError('Customer profile does not exist: $customerId');
    }
  }

  /// Validates required address fields before writing to SQLite.
  void _validateAddress(CustomerAddress address) {
    if (address.id.trim().isEmpty) {
      throw ArgumentError('Address ID cannot be empty.');
    }

    if (address.customerId.trim().isEmpty) {
      throw ArgumentError('Customer ID cannot be empty.');
    }

    if (address.label.trim().isEmpty) {
      throw ArgumentError('Address label cannot be empty.');
    }

    if (address.recipientName.trim().isEmpty) {
      throw ArgumentError('Recipient name cannot be empty.');
    }

    if (address.phoneNumber.trim().isEmpty) {
      throw ArgumentError('Phone number cannot be empty.');
    }

    if (address.addressLine1.trim().isEmpty) {
      throw ArgumentError('Address line 1 cannot be empty.');
    }

    if (address.city.trim().isEmpty) {
      throw ArgumentError('City cannot be empty.');
    }

    if (address.state.trim().isEmpty) {
      throw ArgumentError('State cannot be empty.');
    }

    if (address.postalCode.trim().isEmpty) {
      throw ArgumentError('Postal code cannot be empty.');
    }
  }
}
