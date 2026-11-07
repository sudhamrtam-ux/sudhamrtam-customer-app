import '../models/customer_profile.dart';
import 'milk_database_service.dart';

/// Handles local SQLite persistence for customer profiles.
///
/// This service does not authenticate customers.
/// Phone numbers stored here are not OTP-verified.
class CustomerProfileDatabaseService {
  CustomerProfileDatabaseService._();

  static final CustomerProfileDatabaseService instance =
      CustomerProfileDatabaseService._();

  /// Inserts a profile or updates its editable fields.
  ///
  /// Uses SQLite UPSERT rather than REPLACE so existing
  /// saved addresses are not deleted by ON DELETE CASCADE.
  Future<void> saveProfile(CustomerProfile profile) async {
    _validateProfile(profile);

    final db = await MilkDatabaseService.instance.database;
    final values = profile.toMap();

    await db.rawInsert(
      '''
      INSERT INTO ${MilkDatabaseService.customerProfilesTable} (
        id,
        full_name,
        phone_number,
        email,
        created_at,
        updated_at
      )
      VALUES (?, ?, ?, ?, ?, ?)
      ON CONFLICT(id) DO UPDATE SET
        full_name = excluded.full_name,
        phone_number = excluded.phone_number,
        email = excluded.email,
        updated_at = excluded.updated_at
    ''',
      [
        values['id'],
        values['full_name'],
        values['phone_number'],
        values['email'],
        values['created_at'],
        values['updated_at'],
      ],
    );
  }

  /// Retrieves a customer profile by its local ID.
  ///
  /// Returns null if the profile does not exist.
  Future<CustomerProfile?> getProfileById(String customerId) async {
    if (customerId.trim().isEmpty) {
      return null;
    }

    final db = await MilkDatabaseService.instance.database;

    final rows = await db.query(
      MilkDatabaseService.customerProfilesTable,
      where: 'id = ?',
      whereArgs: [customerId],
      limit: 1,
    );

    if (rows.isEmpty) {
      return null;
    }

    return CustomerProfile.fromMap(rows.first);
  }

  /// Updates an existing customer profile.
  ///
  /// Returns true if the profile was found and updated.
  Future<bool> updateProfile(CustomerProfile profile) async {
    _validateProfile(profile);

    final db = await MilkDatabaseService.instance.database;

    final updatedRows = await db.update(
      MilkDatabaseService.customerProfilesTable,
      {
        'full_name': profile.fullName,
        'phone_number': profile.phoneNumber,
        'email': profile.email,
        'updated_at': profile.updatedAt.toIso8601String(),
      },
      where: 'id = ?',
      whereArgs: [profile.id],
    );

    return updatedRows > 0;
  }

  /// Mirrors the signed-in account's profile on the phone.
  ///
  /// Unlike [saveProfile], the name may be empty: an account can
  /// exist before the customer has entered a name.
  Future<void> saveSyncedProfile({
    required String customerId,
    required String fullName,
    String? phoneNumber,
    String? email,
  }) async {
    final db = await MilkDatabaseService.instance.database;
    final now = DateTime.now().toIso8601String();

    await db.rawInsert(
      '''
      INSERT INTO ${MilkDatabaseService.customerProfilesTable} (
        id, full_name, phone_number, email, created_at, updated_at
      )
      VALUES (?, ?, ?, ?, ?, ?)
      ON CONFLICT(id) DO UPDATE SET
        full_name = excluded.full_name,
        phone_number = excluded.phone_number,
        email = excluded.email,
        updated_at = excluded.updated_at
    ''',
      [customerId, fullName, phoneNumber, email, now, now],
    );
  }

  /// Deletes the profile and, through the foreign key, its
  /// saved addresses.
  Future<void> deleteProfile(String customerId) async {
    final db = await MilkDatabaseService.instance.database;
    await db.delete(
      MilkDatabaseService.customerAddressesTable,
      where: 'customer_id = ?',
      whereArgs: [customerId],
    );
    await db.delete(
      MilkDatabaseService.customerProfilesTable,
      where: 'id = ?',
      whereArgs: [customerId],
    );
  }

  /// Checks whether a customer profile exists.
  Future<bool> profileExists(String customerId) async {
    if (customerId.trim().isEmpty) {
      return false;
    }

    final profile = await getProfileById(customerId);

    return profile != null;
  }

  /// Validates essential profile fields before writing to SQLite.
  void _validateProfile(CustomerProfile profile) {
    if (profile.id.trim().isEmpty) {
      throw ArgumentError('Customer ID cannot be empty.');
    }

    if (profile.fullName.trim().isEmpty) {
      throw ArgumentError('Customer name cannot be empty.');
    }
  }
}
