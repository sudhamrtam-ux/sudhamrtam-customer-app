import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:sudhamrtam_customer_app/app/sudhamrtam_app.dart';
import 'package:sudhamrtam_customer_app/database/milk_database_service.dart';
import 'package:sudhamrtam_customer_app/features/milk_plan/milk_subscription_setup_screen.dart';
import 'package:sudhamrtam_customer_app/models/milk_subscription.dart';
import 'package:sudhamrtam_customer_app/models/subscription_products.dart';

/// A subscription product that comes on some days only (owner
/// request 2026-11-25, step 4).
///
/// In its own file: the app's shared plan manager queues writes.
const _curdJson = {
  'product_id': 'curd',
  'name': 'Curd',
  'unit_label': '500 g',
  'measure': 'pack',
  'quantities': [1, 2, 3],
  'shifts': ['morning'],
  'weekdays': [1, 2, 3, 4, 5, 6, 7],
  'offered': true,
  'ends_on': null,
  'sort_order': 3,
};

final _curd = SubscriptionOffer.fromJson(_curdJson);

/// Paneer on Mon, Wed and Fri only.
final _paneer = SubscriptionOffer.fromJson({
  ..._curdJson,
  'product_id': 'paneer',
  'name': 'Paneer',
  'unit_label': '200 g',
  'quantities': [1, 2],
  'weekdays': [1, 3, 5],
});

void main() {
  late Directory directory;
  late String path;

  setUpAll(sqfliteFfiInit);

  setUp(() async {
    directory = await Directory.systemTemp.createTemp('sudhamrtam_subs_');
    path = '${directory.path}${Platform.pathSeparator}milk.db';
    MilkDatabaseService.instance.configureForTesting(
      factory: databaseFactoryFfi,
      databasePath: path,
    );
    sudhamrtamSubscriptionProducts.setOffers([
      ...builtInSubscriptionOffers,
      _curd,
      _paneer,
    ]);
  });

  tearDown(() async {
    sudhamrtamSubscriptionProducts.reset();
    await MilkDatabaseService.instance.close();
    MilkDatabaseService.instance.resetTestingConfiguration();
    await directory.delete(recursive: true);
  });

  Future<void> waitUntil(WidgetTester tester, bool Function() done) async {
    for (var i = 0; i < 500 && !done(); i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 10)),
      );
      await tester.pump();
    }
  }

  void bigScreen(WidgetTester tester) {
    tester.view.physicalSize = const Size(1600, 8000);
    tester.view.devicePixelRatio = 2;
    addTearDown(tester.view.reset);
  }

  testWidgets('a product on some days only offers those days', (tester) async {
    bigScreen(tester);
    await tester.runAsync(() => MilkDatabaseService.instance.database);
    await tester.pumpWidget(
      MaterialApp(
        home: MilkSubscriptionSetupScreen(
          productId: 'paneer',
          checkAddress: (_) async => true,
        ),
      ),
    );
    expect(find.byKey(const Key('offer-days-morning')), findsOneWidget);
    expect(find.text('Paneer comes on Mon, Wed and Fri.'), findsOneWidget);
    // Selected days, with only those days to pick.
    expect(find.byKey(const Key('day-morning-1')), findsOneWidget);
    expect(find.byKey(const Key('day-morning-2')), findsNothing);
    expect(find.byKey(const Key('day-morning-5')), findsOneWidget);
    // Daily is not offered.
    await tester.tap(
      find.byType(DropdownButtonFormField<MilkDeliveryFrequency>),
    );
    await tester.pumpAndSettle();
    expect(find.text('Daily Delivery'), findsNothing);
    expect(find.text('Random Days'), findsWidgets);
    await tester.tap(find.text('Selected Days').last);
    await tester.pumpAndSettle();

    // Leave Wednesday out.
    await tester.tap(find.byKey(const Key('day-morning-3')));
    await tester.pump();
    await tester.tap(find.text('Save Subscription'));
    await waitUntil(
      tester,
      () =>
          !sudhamrtamMilkSubscriptions.isWriting &&
          sudhamrtamMilkSubscriptions.plansFor('paneer').isNotEmpty,
    );
    final saved = sudhamrtamMilkSubscriptions.plansFor('paneer').single;
    final morning = saved.scheduleFor(MilkDeliveryShift.morning)!;
    expect(morning.frequency, MilkDeliveryFrequency.selectedDays);
    expect(morning.selectedWeekdays, [1, 5]);
    expect(morning.endDate, isNull);
  });
}
