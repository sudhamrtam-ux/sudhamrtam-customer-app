import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:sudhamrtam_customer_app/database/customer_address_database_service.dart';
import 'package:sudhamrtam_customer_app/database/milk_database_service.dart';
import 'package:sudhamrtam_customer_app/features/account/address_form_screen.dart';
import 'package:sudhamrtam_customer_app/features/home/address_details_card.dart';
import 'package:sudhamrtam_customer_app/models/customer_address.dart';
import 'package:sudhamrtam_customer_app/services/account_api_client.dart';
import 'package:sudhamrtam_customer_app/services/account_sync_service.dart';
import 'package:sudhamrtam_customer_app/services/catalog_api_client.dart';

import 'fake_map.dart';

CustomerAddress address({
  String? societyId,
  String? societyName,
  String? societyOther,
  String? block,
  String? flat,
  bool isHouse = false,
  bool isDefault = true,
}) {
  final now = DateTime(2026, 11, 11);
  return CustomerAddress(
    id: 'a1',
    customerId: AccountSyncService.localCustomerId,
    areaId: 'nizampet',
    label: 'Home',
    recipientName: 'Asha',
    phoneNumber: '9876543210',
    addressLine1: 'Road 4',
    landmark: '',
    city: 'Hyderabad',
    state: 'Telangana',
    postalCode: '500090',
    isDefault: isDefault,
    createdAt: now,
    updatedAt: now,
    societyId: societyId,
    societyName: societyName,
    societyOther: societyOther,
    block: block,
    flat: flat,
    isHouse: isHouse,
  );
}

void main() {
  group('address model', () {
    test('the delivery note survives the phone and the server', () {
      final now = DateTime(2026, 11, 14);
      final a = CustomerAddress(
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
        createdAt: now,
        updatedAt: now,
        deliveryNote: 'Ring twice',
      );
      expect(CustomerAddress.fromMap(a.toMap()).deliveryNote, 'Ring twice');
      expect(a.copyWith(label: 'Office').deliveryNote, 'Ring twice');
      final back = AddressJson.fromJson({
        ...AddressJson.toJson(a),
        'id': 'a1',
        'phone_e164': '+919876543210',
        'created_at': now.toIso8601String(),
        'updated_at': now.toIso8601String(),
      }, customerId: a.customerId);
      expect(back.deliveryNote, 'Ring twice');
    });

    test('flat, block and society come first in the address', () {
      expect(
        address(
          societyId: 's1',
          societyName: 'Green Towers',
          block: 'B',
          flat: '101',
        ).formattedAddress,
        'Flat 101, Block B, Green Towers, Road 4, Hyderabad, Telangana, 500090',
      );
      expect(
        address(
          societyOther: 'Lake View',
          block: 'Tower 2',
          flat: '12',
        ).formattedAddress,
        'Flat 12, Tower 2, Lake View, Road 4, Hyderabad, Telangana, 500090',
      );
      expect(
        address(isHouse: true, flat: '7-1-45').formattedAddress,
        'House 7-1-45, Road 4, Hyderabad, Telangana, 500090',
      );
    });

    test('which addresses still need the details', () {
      expect(address().needsDetails, isTrue);
      expect(address(flat: '101', block: 'B').needsDetails, isTrue);
      expect(
        address(societyId: 's1', block: 'B', flat: '101').needsDetails,
        isFalse,
      );
      expect(
        address(societyOther: 'Lake View', block: 'B', flat: '1').needsDetails,
        isFalse,
      );
      expect(address(isHouse: true, flat: '7').needsDetails, isFalse);
      expect(address(isHouse: true).needsDetails, isTrue);
    });

    test('the server JSON keeps the details both ways', () {
      final json = AddressJson.toJson(
        address(societyId: 's1', block: 'B', flat: '101'),
      );
      expect(json['society_id'], 's1');
      expect(json['block'], 'B');
      expect(json['flat'], '101');
      expect(json['is_house'], false);
      final back = AddressJson.fromJson({
        ...json,
        'id': 'a1',
        'phone_e164': '+919876543210',
        'society_name': 'Green Towers',
        'created_at': '2026-11-11T00:00:00.000Z',
        'updated_at': '2026-11-11T00:00:00.000Z',
      }, customerId: AccountSyncService.localCustomerId);
      expect(back.societyName, 'Green Towers');
      expect(back.flat, '101');
      expect(back.needsDetails, isFalse);
    });
  });

  group('on the phone', () {
    late Directory directory;

    setUpAll(sqfliteFfiInit);
    setUp(() async {
      directory = await Directory.systemTemp.createTemp('sudhamrtam_soc_');
      MilkDatabaseService.instance.configureForTesting(
        factory: databaseFactoryFfi,
        databasePath: '${directory.path}${Platform.pathSeparator}soc.db',
      );
    });
    tearDown(() async {
      await MilkDatabaseService.instance.close();
      MilkDatabaseService.instance.resetTestingConfiguration();
      await directory.delete(recursive: true);
    });

    testWidgets('the form picks a society from the area\'s list', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(1080, 5000);
      tester.view.devicePixelRatio = 2;
      addTearDown(tester.view.reset);
      final asked = <String>[];

      await tester.pumpWidget(
        MaterialApp(
          home: AddressFormScreen(
            account: AccountSyncService.localOnly(),
            findLocation: fakeFindLocation,
            mapBuilder: fakeMap,
            loadAreas: () async => const [
              DeliveryArea(id: 'nizampet', name: 'Nizampet'),
            ],
            loadSocieties: (area) async {
              asked.add(area);
              return const [SocietyChoice(id: 's1', name: 'Green Towers')];
            },
          ),
        ),
      );
      await tester.pumpAndSettle();

      Future<void> type(String label, String text) =>
          tester.enterText(find.widgetWithText(TextFormField, label), text);
      await type('Recipient Name', 'Asha');
      await type('Mobile Number', '9876543210');
      await type('Street / Road / Locality', 'Road 4');
      await type('PIN Code', '500090');
      await tester.tap(find.byKey(const Key('areaField')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Nizampet').last);
      await tester.pumpAndSettle();
      expect(asked, ['nizampet']);

      // Society, block and flat are needed.
      await tester.tap(find.text('Save Address'));
      await tester.pumpAndSettle();
      expect(find.text('Please choose your society'), findsOneWidget);
      expect(find.text('Please enter your block or tower'), findsOneWidget);
      expect(find.text('Please enter your flat number'), findsOneWidget);

      await tester.tap(find.textContaining('Society / Apartment').first);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Green Towers').last);
      await tester.pumpAndSettle();
      await type('Block / Tower', 'B');
      await type('Flat Number', '1203');
      await useCurrentLocation(tester);
      await tester.tap(find.text('Save Address'));
      await tester.pump();

      List<CustomerAddress>? saved;
      for (var i = 0; i < 50 && (saved?.isEmpty ?? true); i++) {
        saved = await tester.runAsync(() async {
          await Future<void>.delayed(const Duration(milliseconds: 50));
          return CustomerAddressDatabaseService.instance
              .getAddressesByCustomerId(AccountSyncService.localCustomerId);
        });
        await tester.pump();
      }
      final a = saved!.single;
      expect(
        [a.societyId, a.societyName, a.societyOther, a.block, a.flat],
        ['s1', 'Green Towers', null, 'B', '1203'],
      );
      expect(a.isHouse, isFalse);
    });

    testWidgets('a society with its address fills it in; a note is optional', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(1080, 5000);
      tester.view.devicePixelRatio = 2;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        MaterialApp(
          home: AddressFormScreen(
            account: AccountSyncService.localOnly(),
            findLocation: fakeFindLocation,
            mapBuilder: fakeMap,
            loadAreas: () async => const [
              DeliveryArea(id: 'nizampet', name: 'Nizampet'),
            ],
            loadSocieties: (_) async => const [
              SocietyChoice(
                id: 's1',
                name: 'Green Towers',
                addressLine1: 'Road 4, Nizampet',
                city: 'Hyderabad',
                state: 'Telangana',
                postalCode: '500090',
              ),
              SocietyChoice(id: 's2', name: 'Lake View'),
            ],
          ),
        ),
      );
      await tester.pumpAndSettle();

      Future<void> type(String label, String text) =>
          tester.enterText(find.widgetWithText(TextFormField, label), text);
      await type('Recipient Name', 'Asha');
      await type('Mobile Number', '9876543210');
      await tester.tap(find.byKey(const Key('areaField')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Nizampet').last);
      await tester.pumpAndSettle();

      // A society without an address: the customer types it.
      await tester.tap(find.textContaining('Society / Apartment').first);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Lake View').last);
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('societyAddress')), findsNothing);
      expect(
        find.widgetWithText(TextFormField, 'Street / Road / Locality'),
        findsOneWidget,
      );

      // Green Towers gives the street, city and PIN code.
      await tester.tap(find.text('Lake View').first);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Green Towers').last);
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('societyAddress')), findsOneWidget);
      expect(
        find.text('Road 4, Nizampet, Hyderabad, Telangana, 500090'),
        findsOneWidget,
      );
      expect(
        find.widgetWithText(TextFormField, 'Street / Road / Locality'),
        findsNothing,
      );
      expect(find.widgetWithText(TextFormField, 'PIN Code'), findsNothing);

      await type('Block / Tower', 'B');
      await type('Flat Number', '1203');
      await tester.enterText(
        find.byKey(const Key('deliveryNoteField')),
        ' Leave at the door ',
      );
      await useCurrentLocation(tester);
      await tester.tap(find.text('Save Address'));
      await tester.pump();

      List<CustomerAddress>? saved;
      for (var i = 0; i < 50 && (saved?.isEmpty ?? true); i++) {
        saved = await tester.runAsync(() async {
          await Future<void>.delayed(const Duration(milliseconds: 50));
          return CustomerAddressDatabaseService.instance
              .getAddressesByCustomerId(AccountSyncService.localCustomerId);
        });
        await tester.pump();
      }
      final a = saved!.single;
      expect(
        [a.addressLine1, a.city, a.state, a.postalCode, a.landmark],
        ['Road 4, Nizampet', 'Hyderabad', 'Telangana', '500090', ''],
      );
      expect([a.societyId, a.block, a.flat], ['s1', 'B', '1203']);
      expect(a.deliveryNote, 'Leave at the door');
      // The server gets the note too.
      expect(AddressJson.toJson(a)['delivery_note'], 'Leave at the door');
    });

    test(
      'v18 to v19 keeps addresses and adds an empty delivery note',
      () async {
        // A v19 database made into a v18 one with an address in it.
        await MilkDatabaseService.instance.database;
        await MilkDatabaseService.instance.close();
        final path = '${directory.path}${Platform.pathSeparator}soc.db';
        final old = await databaseFactoryFfi.openDatabase(path);
        await old.execute(
          'ALTER TABLE customer_addresses DROP COLUMN delivery_note',
        );
        await old.insert('customer_profiles', {
          'id': AccountSyncService.localCustomerId,
          'full_name': 'Asha',
          'created_at': '2026-11-11T00:00:00.000',
          'updated_at': '2026-11-11T00:00:00.000',
        });
        final row = address(societyId: 's1', block: 'B', flat: '101').toMap()
          ..remove('delivery_note');
        await old.insert('customer_addresses', row);
        await old.setVersion(18);
        await old.close();

        final db = await MilkDatabaseService.instance.database;
        expect(await db.getVersion(), MilkDatabaseService.databaseVersion);
        final kept = await CustomerAddressDatabaseService.instance
            .getAddressesByCustomerId(AccountSyncService.localCustomerId);
        expect([kept.single.id, kept.single.flat], ['a1', '101']);
        expect(kept.single.deliveryNote, isNull);
      },
    );

    testWidgets('an independent house needs only the house number', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(1080, 5000);
      tester.view.devicePixelRatio = 2;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        MaterialApp(
          home: AddressFormScreen(
            account: AccountSyncService.localOnly(),
            findLocation: fakeFindLocation,
            mapBuilder: fakeMap,
            loadAreas: () async => const [
              DeliveryArea(id: 'nizampet', name: 'Nizampet'),
            ],
            loadSocieties: (_) async => const [],
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('houseField')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('blockField')), findsNothing);
      expect(
        find.widgetWithText(TextFormField, 'House Number'),
        findsOneWidget,
      );
    });
  });

  group('the Home reminder', () {
    Future<void> show(
      WidgetTester tester,
      List<CustomerAddress> addresses, {
      bool dismissed = false,
      List<String>? log,
    }) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: AddressDetailsCard(
              account: AccountSyncService.localOnly(),
              loadAddresses: () async => addresses,
              isDismissed: () async => dismissed,
              dismiss: () async => log?.add('dismissed'),
              openForm: (_, a) async => log?.add('open ${a.id}'),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
    }

    testWidgets('asks once when an address lacks the details', (tester) async {
      final log = <String>[];
      await show(tester, [address()], log: log);
      expect(find.byKey(const Key('addressDetailsCard')), findsOneWidget);
      expect(find.textContaining('Home address'), findsOneWidget);

      await tester.tap(find.byKey(const Key('addressDetailsAdd')));
      await tester.pumpAndSettle();
      expect(log, ['open a1']);

      await tester.tap(find.byKey(const Key('addressDetailsLater')));
      await tester.pumpAndSettle();
      expect(log.last, 'dismissed');
      expect(find.byKey(const Key('addressDetailsCard')), findsNothing);
    });

    testWidgets('stays hidden when complete or dismissed', (tester) async {
      await show(tester, [address(societyId: 's1', block: 'B', flat: '1')]);
      expect(find.byKey(const Key('addressDetailsCard')), findsNothing);
      await show(tester, [address()], dismissed: true);
      expect(find.byKey(const Key('addressDetailsCard')), findsNothing);
    });
  });
}
