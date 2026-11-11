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
            loadAreas: () async => const [
              DeliveryArea(id: 'nizampet', name: 'Nizampet'),
            ],
            loadSocieties: (area) async {
              asked.add(area);
              return const [DeliveryArea(id: 's1', name: 'Green Towers')];
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
