import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:sudhamrtam_customer_app/database/customer_address_database_service.dart';
import 'package:sudhamrtam_customer_app/database/customer_profile_database_service.dart';
import 'package:sudhamrtam_customer_app/database/milk_database_service.dart';
import 'package:sudhamrtam_customer_app/models/customer_address.dart';
import 'package:sudhamrtam_customer_app/models/customer_profile.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();

  final databaseService = MilkDatabaseService.instance;
  final profileService = CustomerProfileDatabaseService.instance;
  final addressService = CustomerAddressDatabaseService.instance;

  late Directory tempDirectory;

  final createdAt = DateTime.utc(2026, 11, 1);
  final updatedAt = DateTime.utc(2026, 11, 4);

  CustomerProfile makeProfile(String id) {
    return CustomerProfile(
      id: id,
      fullName: 'Test Customer',
      phoneNumber: '9876543210',
      createdAt: createdAt,
      updatedAt: createdAt,
    );
  }

  CustomerAddress makeAddress({
    String id = 'address_001',
    String customerId = 'customer_001',
    bool isDefault = false,
    String label = 'Home',
  }) {
    return CustomerAddress(
      id: id,
      customerId: customerId,
      label: label,
      recipientName: 'Test Customer',
      phoneNumber: '9876543210',
      addressLine1: 'Test Street',
      addressLine2: 'Apartment 1',
      landmark: 'Near Test Park',
      city: 'Hyderabad',
      state: 'Telangana',
      postalCode: '500001',
      isDefault: isDefault,
      createdAt: createdAt,
      updatedAt: createdAt,
    );
  }

  setUp(() async {
    tempDirectory = await Directory.systemTemp.createTemp(
      'sudhamrtam_address_test_',
    );

    final databasePath =
        '${tempDirectory.path}${Platform.pathSeparator}test.db';

    databaseService.configureForTesting(
      factory: databaseFactoryFfi,
      databasePath: databasePath,
    );

    await databaseService.database;

    await profileService.saveProfile(makeProfile('customer_001'));
    await profileService.saveProfile(makeProfile('customer_002'));
  });

  tearDown(() async {
    await databaseService.close();
    databaseService.resetTestingConfiguration();

    if (await tempDirectory.exists()) {
      await tempDirectory.delete(recursive: true);
    }
  });

  test('Saves and retrieves an address', () async {
    final address = makeAddress();

    expect(await addressService.saveAddress(address), isTrue);

    final saved = await addressService.getAddressById(address.id);

    expect(saved, isNotNull);
    expect(saved!.customerId, 'customer_001');
    expect(saved.label, 'Home');
    expect(saved.city, 'Hyderabad');
    expect(saved.addressLine2, 'Apartment 1');
  });

  test('Lists addresses for the correct customer', () async {
    await addressService.saveAddress(makeAddress());

    await addressService.saveAddress(
      makeAddress(id: 'address_002', customerId: 'customer_002'),
    );

    final addresses = await addressService.getAddressesByCustomerId(
      'customer_001',
    );

    expect(addresses.length, 1);
    expect(addresses.first.id, 'address_001');
  });

  test('Returns null for an unknown address', () async {
    final address = await addressService.getAddressById('unknown');

    expect(address, isNull);
  });

  test('Rejects duplicate address IDs', () async {
    final address = makeAddress();

    expect(await addressService.saveAddress(address), isTrue);
    expect(await addressService.saveAddress(address), isFalse);

    final addresses = await addressService.getAddressesByCustomerId(
      'customer_001',
    );

    expect(addresses.length, 1);
  });

  test('Rejects an address without an existing customer', () async {
    final address = makeAddress(customerId: 'missing_customer');

    await expectLater(addressService.saveAddress(address), throwsStateError);
  });

  test('Updates an address without changing its creation date', () async {
    final address = makeAddress();

    await addressService.saveAddress(address);

    final success = await addressService.updateAddress(
      address.copyWith(
        label: 'Office',
        city: 'Secunderabad',
        updatedAt: updatedAt,
      ),
    );

    expect(success, isTrue);

    final saved = await addressService.getAddressById(address.id);

    expect(saved!.label, 'Office');
    expect(saved.city, 'Secunderabad');
    expect(saved.createdAt, createdAt);
    expect(saved.updatedAt, updatedAt);
  });

  test('Cannot update an address belonging to another customer', () async {
    final address = makeAddress();

    await addressService.saveAddress(address);

    final otherCustomerAddress = makeAddress(
      id: 'address_001',
      customerId: 'customer_002',
    );

    expect(await addressService.updateAddress(otherCustomerAddress), isFalse);

    final saved = await addressService.getAddressById(address.id);

    expect(saved!.customerId, 'customer_001');
  });

  test('Sets a default address and clears the previous default', () async {
    await addressService.saveAddress(
      makeAddress(id: 'address_001', isDefault: true),
    );

    await addressService.saveAddress(makeAddress(id: 'address_002'));

    final success = await addressService.setDefaultAddress(
      customerId: 'customer_001',
      addressId: 'address_002',
    );

    expect(success, isTrue);

    final addresses = await addressService.getAddressesByCustomerId(
      'customer_001',
    );

    expect(addresses.where((a) => a.isDefault).length, 1);
    expect(addresses.first.id, 'address_002');
    expect(addresses.first.isDefault, isTrue);
  });

  test('Saving a new default address replaces the previous default', () async {
    await addressService.saveAddress(
      makeAddress(id: 'address_001', isDefault: true),
    );

    await addressService.saveAddress(
      makeAddress(id: 'address_002', isDefault: true),
    );

    final defaultAddress = await addressService.getDefaultAddress(
      'customer_001',
    );

    expect(defaultAddress!.id, 'address_002');

    final addresses = await addressService.getAddressesByCustomerId(
      'customer_001',
    );

    expect(addresses.where((a) => a.isDefault).length, 1);
  });

  test('Default addresses are independent for different customers', () async {
    await addressService.saveAddress(
      makeAddress(id: 'address_001', isDefault: true),
    );

    await addressService.saveAddress(
      makeAddress(
        id: 'address_002',
        customerId: 'customer_002',
        isDefault: true,
      ),
    );

    final firstDefault = await addressService.getDefaultAddress('customer_001');

    final secondDefault = await addressService.getDefaultAddress(
      'customer_002',
    );

    expect(firstDefault!.id, 'address_001');
    expect(secondDefault!.id, 'address_002');
  });

  test('Rejects setting another customer address as default', () async {
    await addressService.saveAddress(makeAddress());

    final success = await addressService.setDefaultAddress(
      customerId: 'customer_002',
      addressId: 'address_001',
    );

    expect(success, isFalse);
  });

  test('Deletes an address for its owner', () async {
    await addressService.saveAddress(makeAddress());

    final success = await addressService.deleteAddress(
      customerId: 'customer_001',
      addressId: 'address_001',
    );

    expect(success, isTrue);
    expect(await addressService.getAddressById('address_001'), isNull);
  });

  test('Cannot delete another customer address', () async {
    await addressService.saveAddress(makeAddress());

    final success = await addressService.deleteAddress(
      customerId: 'customer_002',
      addressId: 'address_001',
    );

    expect(success, isFalse);
    expect(await addressService.getAddressById('address_001'), isNotNull);
  });

  test('Deleting a default address leaves no default', () async {
    await addressService.saveAddress(
      makeAddress(id: 'address_001', isDefault: true),
    );

    await addressService.saveAddress(makeAddress(id: 'address_002'));

    await addressService.deleteAddress(
      customerId: 'customer_001',
      addressId: 'address_001',
    );

    final defaultAddress = await addressService.getDefaultAddress(
      'customer_001',
    );

    expect(defaultAddress, isNull);
  });

  test('Rejects an address with an empty required field', () async {
    final address = makeAddress(label: ' ');

    await expectLater(addressService.saveAddress(address), throwsArgumentError);
  });
}
