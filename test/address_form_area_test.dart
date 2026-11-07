import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:sudhamrtam_customer_app/database/customer_address_database_service.dart';
import 'package:sudhamrtam_customer_app/database/milk_database_service.dart';
import 'package:sudhamrtam_customer_app/features/account/address_form_screen.dart';
import 'package:sudhamrtam_customer_app/services/account_sync_service.dart';
import 'package:sudhamrtam_customer_app/services/catalog_api_client.dart';

void main() {
  late Directory directory;

  setUpAll(sqfliteFfiInit);

  setUp(() async {
    directory = await Directory.systemTemp.createTemp('sudhamrtam_area_');
    MilkDatabaseService.instance.configureForTesting(
      factory: databaseFactoryFfi,
      databasePath: '${directory.path}${Platform.pathSeparator}area.db',
    );
  });

  tearDown(() async {
    await MilkDatabaseService.instance.close();
    MilkDatabaseService.instance.resetTestingConfiguration();
    await directory.delete(recursive: true);
  });

  Future<void> fillForm(WidgetTester tester) async {
    Future<void> type(String label, String text) => tester.enterText(
      find.widgetWithText(TextFormField, label),
      text,
    );

    await type('Recipient Name', 'Asha');
    await type('Mobile Number', '9876543210');
    await type('House / Flat / Street Address', 'Flat 1');
    await type('PIN Code', '500090');
  }

  Future<void> tapSave(WidgetTester tester) async {
    final save = find.text('Save Address');
    await tester.ensureVisible(save);
    await tester.tap(save);
  }

  testWidgets('the delivery area is required and saved', (tester) async {
    tester.view.physicalSize = const Size(1080, 4000);
    tester.view.devicePixelRatio = 2;
    addTearDown(tester.view.reset);

    final account = AccountSyncService.localOnly();

    await tester.pumpWidget(
      MaterialApp(
        home: AddressFormScreen(
          account: account,
          loadAreas: () async => const [
            DeliveryArea(id: 'nizampet', name: 'Nizampet'),
            DeliveryArea(id: 'flora', name: 'Praneeth Pranav Flora'),
          ],
        ),
      ),
    );
    await tester.pumpAndSettle();

    await fillForm(tester);
    await tapSave(tester);
    await tester.pumpAndSettle();
    expect(find.text('Please choose your delivery area'), findsOneWidget);

    await tester.tap(find.byKey(const Key('areaField')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Nizampet').last);
    await tester.pumpAndSettle();

    await tapSave(tester);
    await tester.pump();

    // The save writes to SQLite on a real thread: alternate real
    // waiting with frames so each step of the save can continue.
    List<dynamic>? saved;
    for (var i = 0; i < 50 && (saved?.isEmpty ?? true); i++) {
      saved = await tester.runAsync(() async {
        await Future<void>.delayed(const Duration(milliseconds: 50));
        return CustomerAddressDatabaseService.instance
            .getAddressesByCustomerId(AccountSyncService.localCustomerId);
      });
      await tester.pump();
    }
    expect(saved!.single.areaId, 'nizampet');
  });

  testWidgets('without a server there is no area choice', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: AddressFormScreen(account: AccountSyncService.localOnly()),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('areaField')), findsNothing);
  });
}
