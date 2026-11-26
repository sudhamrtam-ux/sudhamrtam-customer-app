import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:sudhamrtam_customer_app/database/customer_address_database_service.dart';
import 'package:sudhamrtam_customer_app/database/customer_profile_database_service.dart';
import 'package:sudhamrtam_customer_app/database/milk_database_service.dart';
import 'package:sudhamrtam_customer_app/features/account/saved_addresses_screen.dart';
import 'package:sudhamrtam_customer_app/models/customer_address.dart';
import 'package:sudhamrtam_customer_app/services/account_sync_service.dart';

/// Saved addresses: "Use for bills" marks the address on the monthly
/// milk bill, one at a time (owner decision 2026-11-26).
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final db = MilkDatabaseService.instance;
  late Directory dir;

  setUpAll(() async {
    sqfliteFfiInit();
    dir = await Directory.systemTemp.createTemp('sudhamrtam_billing_');
    db.configureForTesting(
      factory: databaseFactoryFfi,
      databasePath: '${dir.path}${Platform.pathSeparator}billing.db',
    );
    await CustomerProfileDatabaseService.instance.saveSyncedProfile(
      customerId: AccountSyncService.localCustomerId,
      fullName: 'Asha',
    );
    final now = DateTime(2026, 11, 26);
    CustomerAddress address(String id, String label, {bool def = false}) =>
        CustomerAddress(
          id: id,
          customerId: AccountSyncService.localCustomerId,
          label: label,
          recipientName: 'Asha',
          phoneNumber: '9876543210',
          addressLine1: '$label street',
          landmark: '',
          city: 'Hyderabad',
          state: 'Telangana',
          postalCode: '500090',
          isDefault: def,
          createdAt: now,
          updatedAt: now,
        );
    await CustomerAddressDatabaseService.instance.replaceAllAddresses(
      AccountSyncService.localCustomerId,
      [address('home', 'Home', def: true), address('office', 'Office')],
    );
  });

  tearDownAll(() async {
    await db.close();
    db.resetTestingConfiguration();
    await dir.delete(recursive: true);
  });

  Future<List<String>> billing() async => [
    for (final a
        in await CustomerAddressDatabaseService.instance
            .getAddressesByCustomerId(AccountSyncService.localCustomerId))
      if (a.isBilling) a.id,
  ];

  Future<void> settle(WidgetTester tester) async {
    for (var i = 0; i < 10; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 20)),
      );
      await tester.pump();
    }
  }

  testWidgets('Use for bills: one address at a time, and back', (tester) async {
    tester.view.physicalSize = const Size(800, 2000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final account = AccountSyncService.localOnly();
    await tester.pumpWidget(
      MaterialApp(home: SavedAddressesScreen(account: account)),
    );
    await settle(tester);
    expect(find.byKey(const Key('billing-chip')), findsNothing);

    await tester.tap(find.byKey(const Key('billing-toggle-office')));
    await settle(tester);
    expect(await tester.runAsync(billing), ['office']);
    expect(find.byKey(const Key('billing-chip')), findsOneWidget);

    await tester.tap(find.byKey(const Key('billing-toggle-home')));
    await settle(tester);
    expect(await tester.runAsync(billing), ['home']);

    await tester.tap(find.byKey(const Key('billing-toggle-home')));
    await settle(tester);
    expect(await tester.runAsync(billing), isEmpty);
    expect(find.text('Use for bills'), findsNWidgets(2));
  });
}
