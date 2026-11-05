import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:sudhamrtam_customer_app/database/customer_profile_database_service.dart';
import 'package:sudhamrtam_customer_app/database/milk_database_service.dart';
import 'package:sudhamrtam_customer_app/models/customer_profile.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  sqfliteFfiInit();

  final databaseService = MilkDatabaseService.instance;
  final profileService = CustomerProfileDatabaseService.instance;

  late Directory tempDirectory;

  CustomerProfile createProfile({
    String id = 'customer_001',
    String name = 'Test Customer',
  }) {
    return CustomerProfile(
      id: id,
      fullName: name,
      phoneNumber: '9876543210',
      email: 'test@example.com',
      createdAt: DateTime.utc(2026, 11, 1),
      updatedAt: DateTime.utc(2026, 11, 1),
    );
  }

  setUp(() async {
    tempDirectory = await Directory.systemTemp.createTemp(
      'sudhamrtam_profile_test_',
    );

    final databasePath =
        '${tempDirectory.path}${Platform.pathSeparator}test.db';

    databaseService.configureForTesting(
      factory: databaseFactoryFfi,
      databasePath: databasePath,
    );

    // Creates a fresh SQLite version 4 database.
    await databaseService.database;
  });

  tearDown(() async {
    await databaseService.close();
    databaseService.resetTestingConfiguration();

    if (await tempDirectory.exists()) {
      await tempDirectory.delete(recursive: true);
    }
  });

  test('Saves and retrieves a customer profile', () async {
    final profile = createProfile();

    await profileService.saveProfile(profile);

    final saved = await profileService.getProfileById(profile.id);

    expect(saved, isNotNull);
    expect(saved!.id, profile.id);
    expect(saved.fullName, 'Test Customer');
    expect(saved.phoneNumber, '9876543210');
    expect(saved.email, 'test@example.com');
  });

  test('Returns null for an unknown customer', () async {
    final profile = await profileService.getProfileById('unknown_customer');

    expect(profile, isNull);
  });

  test('Checks whether a customer profile exists', () async {
    final profile = createProfile();

    expect(await profileService.profileExists(profile.id), isFalse);

    await profileService.saveProfile(profile);

    expect(await profileService.profileExists(profile.id), isTrue);
  });

  test('Updates an existing customer profile', () async {
    final profile = createProfile();

    await profileService.saveProfile(profile);

    final updated = profile.copyWith(
      fullName: 'Updated Customer',
      updatedAt: DateTime.utc(2026, 11, 4),
    );

    final success = await profileService.updateProfile(updated);

    expect(success, isTrue);

    final saved = await profileService.getProfileById(profile.id);

    expect(saved!.fullName, 'Updated Customer');
    expect(saved.updatedAt, DateTime.utc(2026, 11, 4));
    expect(saved.createdAt, profile.createdAt);
  });

  test('UPSERT preserves the original creation date', () async {
    final profile = createProfile();

    await profileService.saveProfile(profile);

    final replacement = CustomerProfile(
      id: profile.id,
      fullName: 'Revised Customer',
      createdAt: DateTime.utc(2030, 1, 1),
      updatedAt: DateTime.utc(2026, 11, 4),
    );

    await profileService.saveProfile(replacement);

    final saved = await profileService.getProfileById(profile.id);

    expect(saved!.fullName, 'Revised Customer');
    expect(saved.createdAt, profile.createdAt);
  });

  test('Rejects an empty customer ID', () async {
    final profile = createProfile(id: ' ');

    await expectLater(profileService.saveProfile(profile), throwsArgumentError);
  });

  test('Rejects an empty customer name', () async {
    final profile = createProfile(name: ' ');

    await expectLater(profileService.saveProfile(profile), throwsArgumentError);
  });

  test('UPSERT preserves saved delivery addresses', () async {
    final profile = createProfile();

    await profileService.saveProfile(profile);

    final db = await databaseService.database;

    // Insert a test address linked to the customer.
    await db.insert(MilkDatabaseService.customerAddressesTable, {
      'id': 'address_001',
      'customer_id': profile.id,
      'label': 'Home',
      'recipient_name': 'Test Customer',
      'phone_number': '9876543210',
      'address_line_1': 'Test Street',
      'address_line_2': null,
      'landmark': '',
      'city': 'Hyderabad',
      'state': 'Telangana',
      'postal_code': '500001',
      'is_default': 1,
      'created_at': DateTime.utc(2026, 11, 1).toIso8601String(),
      'updated_at': DateTime.utc(2026, 11, 1).toIso8601String(),
    });

    // Update the customer using UPSERT.
    await profileService.saveProfile(
      profile.copyWith(
        fullName: 'Updated Customer',
        updatedAt: DateTime.utc(2026, 11, 4),
      ),
    );

    final addresses = await db.query(
      MilkDatabaseService.customerAddressesTable,
      where: 'customer_id = ?',
      whereArgs: [profile.id],
    );

    expect(addresses.length, 1);
    expect(addresses.first['id'], 'address_001');
    expect(addresses.first['is_default'], 1);
  });

  test('Enforces one default address per customer', () async {
    final profile = createProfile();

    await profileService.saveProfile(profile);

    final db = await databaseService.database;

    Map<String, Object?> address(String id) => {
      'id': id,
      'customer_id': profile.id,
      'label': 'Home',
      'recipient_name': 'Test Customer',
      'phone_number': '9876543210',
      'address_line_1': 'Test Street',
      'landmark': '',
      'city': 'Hyderabad',
      'state': 'Telangana',
      'postal_code': '500001',
      'is_default': 1,
      'created_at': DateTime.utc(2026, 11, 1).toIso8601String(),
      'updated_at': DateTime.utc(2026, 11, 1).toIso8601String(),
    };

    await db.insert(
      MilkDatabaseService.customerAddressesTable,
      address('address_001'),
    );

    await expectLater(
      db.insert(
        MilkDatabaseService.customerAddressesTable,
        address('address_002'),
      ),
      throwsA(isA<Exception>()),
    );
  });
}
