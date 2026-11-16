import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:sudhamrtam_customer_app/database/customer_address_database_service.dart';
import 'package:sudhamrtam_customer_app/database/milk_database_service.dart';
import 'package:sudhamrtam_customer_app/features/account/address_form_screen.dart';
import 'package:sudhamrtam_customer_app/features/account/map_location_field.dart';
import 'package:sudhamrtam_customer_app/models/customer_address.dart';
import 'package:sudhamrtam_customer_app/services/account_api_client.dart';
import 'package:sudhamrtam_customer_app/services/account_sync_service.dart';

import 'fake_map.dart';

/// Owner decision 2026-11-16: every address needs its spot on the map,
/// so the delivery partner can navigate there.
void main() {
  late Directory directory;

  setUpAll(sqfliteFfiInit);

  setUp(() async {
    directory = await Directory.systemTemp.createTemp('sudhamrtam_map_');
    MilkDatabaseService.instance.configureForTesting(
      factory: databaseFactoryFfi,
      databasePath: '${directory.path}${Platform.pathSeparator}map.db',
    );
  });

  tearDown(() async {
    await MilkDatabaseService.instance.close();
    MilkDatabaseService.instance.resetTestingConfiguration();
    await directory.delete(recursive: true);
  });

  Future<void> open(
    WidgetTester tester, {
    CustomerAddress? existing,
    CurrentLocationFinder findLocation = fakeFindLocation,
  }) async {
    tester.view.physicalSize = const Size(1080, 5000);
    tester.view.devicePixelRatio = 2;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        home: AddressFormScreen(
          existingAddress: existing,
          account: AccountSyncService.localOnly(),
          findLocation: findLocation,
          mapBuilder: fakeMap,
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> fill(WidgetTester tester) async {
    Future<void> type(String label, String text) =>
        tester.enterText(find.widgetWithText(TextFormField, label), text);
    await type('Recipient Name', 'Asha');
    await type('Mobile Number', '9876543210');
    await type('Street / Road / Locality', 'Road 4');
    await type('Society / Apartment Name', 'Green Towers');
    await type('Block / Tower', 'B');
    await type('Flat Number', '101');
    await type('PIN Code', '500090');
  }

  Future<void> save(WidgetTester tester) async {
    final button = find.byType(FilledButton).last;
    await tester.ensureVisible(button);
    await tester.tap(button);
    await tester.pump();
  }

  Future<List<CustomerAddress>> saved(WidgetTester tester) async {
    List<CustomerAddress> list = const [];
    for (var i = 0; i < 50 && list.isEmpty; i++) {
      list =
          await tester.runAsync(() async {
            await Future<void>.delayed(const Duration(milliseconds: 50));
            return CustomerAddressDatabaseService.instance
                .getAddressesByCustomerId(AccountSyncService.localCustomerId);
          }) ??
          const [];
      await tester.pump();
    }
    return list;
  }

  testWidgets('the address is not saved without a spot on the map', (
    tester,
  ) async {
    await open(tester);
    await fill(tester);
    await save(tester);
    await tester.pumpAndSettle();
    expect(
      find.textContaining('Please mark your home on the map'),
      findsOneWidget,
    );
    final none = await tester.runAsync(
      () => CustomerAddressDatabaseService.instance.getAddressesByCustomerId(
        AccountSyncService.localCustomerId,
      ),
    );
    expect(none, isEmpty);
  });

  testWidgets('"Use my current location" marks the spot; dragging moves it', (
    tester,
  ) async {
    await open(tester);
    await fill(tester);
    expect(find.byKey(const Key('fakeMap')), findsNothing);

    await useCurrentLocation(tester);
    expect(find.text('pin 17.512345,78.389123'), findsOneWidget);

    // The customer moves the pin to the gate.
    await tester.tap(find.byKey(const Key('fakeMap')));
    await tester.pumpAndSettle();
    expect(find.text('pin 17.5,78.4'), findsOneWidget);

    await save(tester);
    final a = (await saved(tester)).single;
    expect([a.latitude, a.longitude], [17.5, 78.4]);
    // The server gets it too, for the partner's Navigate button.
    final json = AddressJson.toJson(a);
    expect([json['latitude'], json['longitude']], [17.5, 78.4]);
  });

  testWidgets('away from home: choose on the map by tapping it', (
    tester,
  ) async {
    await open(tester);
    await fill(tester);
    final choose = find.byKey(const Key('chooseOnMap'));
    await tester.ensureVisible(choose);
    await tester.tap(choose);
    await tester.pumpAndSettle();
    expect(find.text('no pin'), findsOneWidget);
    expect(find.text('Tap the map at your home.'), findsOneWidget);

    await tester.tap(find.byKey(const Key('fakeMap')));
    await tester.pumpAndSettle();
    await save(tester);
    final a = (await saved(tester)).single;
    expect([a.latitude, a.longitude], [17.5, 78.4]);
  });

  testWidgets('when the location cannot be read, the map opens to tap', (
    tester,
  ) async {
    await open(
      tester,
      findLocation: () async => throw const LocationProblem(
        'Without your location, please tap the map at your home.',
      ),
    );
    await useCurrentLocation(tester);
    expect(
      find.text('Without your location, please tap the map at your home.'),
      findsOneWidget,
    );
    expect(find.text('no pin'), findsOneWidget);
  });

  testWidgets('editing keeps the saved spot', (tester) async {
    final now = DateTime(2026, 11, 16);
    await open(
      tester,
      existing: CustomerAddress(
        id: 'a1',
        customerId: AccountSyncService.localCustomerId,
        label: 'Home',
        recipientName: 'Asha',
        phoneNumber: '9876543210',
        addressLine1: 'Road 4',
        landmark: '',
        city: 'Hyderabad',
        state: 'Telangana',
        postalCode: '500090',
        latitude: 17.49,
        longitude: 78.38,
        isDefault: true,
        createdAt: now,
        updatedAt: now,
        societyOther: 'Green Towers',
        block: 'B',
        flat: '101',
      ),
    );
    expect(find.text('pin 17.49,78.38'), findsOneWidget);
    await save(tester);
    final a = (await saved(tester)).single;
    expect([a.latitude, a.longitude], [17.49, 78.38]);
  });
}
