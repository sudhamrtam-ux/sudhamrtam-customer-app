import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:sudhamrtam_customer_app/app/sudhamrtam_app.dart';
import 'package:sudhamrtam_customer_app/database/milk_database_service.dart';
import 'package:sudhamrtam_customer_app/features/account/address_location_gate.dart';
import 'package:sudhamrtam_customer_app/features/home/address_details_card.dart';
import 'package:sudhamrtam_customer_app/features/milk_plan/milk_subscription_setup_screen.dart';
import 'package:sudhamrtam_customer_app/models/customer_address.dart';
import 'package:sudhamrtam_customer_app/services/account_sync_service.dart';

/// Owner decision 2026-11-16: an address not marked on the map is
/// asked for on Home, and new milk plans wait until it is marked.
CustomerAddress home({bool onMap = false, bool complete = true}) {
  final now = DateTime(2026, 11, 16);
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
    latitude: onMap ? 17.5 : null,
    longitude: onMap ? 78.4 : null,
    isDefault: true,
    createdAt: now,
    updatedAt: now,
    societyOther: complete ? 'Green Towers' : null,
    block: complete ? 'B' : null,
    flat: complete ? '101' : null,
  );
}

void main() {
  group('the Home card', () {
    Future<void> show(
      WidgetTester tester,
      List<CustomerAddress> addresses, {
      bool dismissed = false,
      List<String>? log,
    }) async {
      // A fresh card each time (it checks once when it opens).
      await tester.pumpWidget(const SizedBox());
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: AddressDetailsCard(
              account: AccountSyncService.localOnly(),
              asksForLocation: true,
              loadAddresses: () async => addresses,
              isDismissed: () async => dismissed,
              dismiss: () async {},
              openForm: (_, a) async => log?.add('open ${a.id}'),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
    }

    testWidgets('asks for the map spot and cannot be put off', (tester) async {
      final log = <String>[];
      // Even after "Not now" on the society card.
      await show(tester, [home()], dismissed: true, log: log);
      expect(find.text('Mark your home on the map'), findsOneWidget);
      expect(
        find.textContaining('New orders and subscriptions'),
        findsOneWidget,
      );
      expect(find.byKey(const Key('addressDetailsLater')), findsNothing);

      await tester.tap(find.text('Add location'));
      await tester.pumpAndSettle();
      expect(log, ['open a1']);
    });

    testWidgets('a marked address goes back to the society card', (
      tester,
    ) async {
      await show(tester, [home(onMap: true)]);
      expect(find.byKey(const Key('addressDetailsCard')), findsNothing);

      await show(tester, [home(onMap: true, complete: false)]);
      expect(find.text('Help us find your door faster'), findsOneWidget);
      expect(find.byKey(const Key('addressDetailsLater')), findsOneWidget);
    });
  });

  group('new subscriptions', () {
    Future<bool?> check(
      WidgetTester tester,
      List<CustomerAddress> addresses, {
      bool hasServer = true,
    }) async {
      bool? result;
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => TextButton(
              onPressed: () async => result = await checkMilkAddressLocation(
                context,
                hasServer: hasServer,
                loadAddresses: () async => addresses,
              ),
              child: const Text('check'),
            ),
          ),
        ),
      );
      await tester.tap(find.text('check'));
      await tester.pumpAndSettle();
      return result;
    }

    testWidgets('go on when the milk address is on the map', (tester) async {
      expect(await check(tester, [home(onMap: true)]), isTrue);
      expect(await check(tester, [home()], hasServer: false), isTrue);
    });

    testWidgets('wait until the home is marked', (tester) async {
      await check(tester, [home()]);
      expect(
        find.byKey(const Key('milkAddressLocationDialog')),
        findsOneWidget,
      );
      expect(
        find.textContaining('Your Home address is not marked on the map'),
        findsOneWidget,
      );
      await tester.tap(find.text('Not now'));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('milkAddressLocationDialog')), findsNothing);

      // No address at all: add one first.
      await check(tester, const []);
      expect(find.text('Add address'), findsOneWidget);
    });

    testWidgets('the subscription is not saved until the check passes', (
      tester,
    ) async {
      final directory = (await tester.runAsync(
        () => Directory.systemTemp.createTemp('sudhamrtam_plan_map_'),
      ))!;
      MilkDatabaseService.instance.configureForTesting(
        factory: databaseFactoryFfi,
        databasePath: '${directory.path}${Platform.pathSeparator}milk.db',
      );
      addTearDown(() async {
        await tester.runAsync(() async {
          await MilkDatabaseService.instance.close();
          MilkDatabaseService.instance.resetTestingConfiguration();
          await directory.delete(recursive: true);
        });
      });
      sqfliteFfiInit();
      tester.view.physicalSize = const Size(1080, 6000);
      tester.view.devicePixelRatio = 2;
      addTearDown(tester.view.reset);
      await tester.runAsync(() => MilkDatabaseService.instance.database);

      var asked = 0;
      await tester.pumpWidget(
        MaterialApp(
          home: MilkSubscriptionSetupScreen(
            productName: 'Cow Milk',
            checkAddress: (_) async {
              asked++;
              return false;
            },
          ),
        ),
      );
      await tester.tap(find.text('Save Milk Subscription'));
      await tester.pumpAndSettle();
      expect(asked, 1);
      expect(sudhamrtamMilkSubscriptions.plansFor('cow_milk'), isEmpty);
      // Still on the form, ready to try again.
      expect(find.text('Save Milk Subscription'), findsOneWidget);
    });
  });
}
