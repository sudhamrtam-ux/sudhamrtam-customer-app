import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:sudhamrtam_customer_app/app/sudhamrtam_app.dart';
import 'package:sudhamrtam_customer_app/database/milk_database_service.dart';
import 'package:sudhamrtam_customer_app/database/milk_subscription_repository.dart';
import 'package:sudhamrtam_customer_app/features/milk_plan/milk_plan_screen.dart';
import 'package:sudhamrtam_customer_app/features/milk_plan/milk_subscription_setup_screen.dart';
import 'package:sudhamrtam_customer_app/models/milk_subscription.dart';
import 'package:sudhamrtam_customer_app/models/subscription_products.dart';

/// Subscriptions of any product (owner request 2026-11-25, step 4):
/// the owner's subscription products, packs, Try for 7 days.
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
  'save_bp': 1000,
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

  test('the server list: words per measure, stopped ones kept', () async {
    expect(_curd.isPack, isTrue);
    expect(_curd.quantityText(2), '2 × 500 g');
    expect(_curd.savePercent, '10%');
    expect(_curd.savedPricePaise(12000), 10800);
    // Rounded to the paisa, like the bill.
    expect(_curd.savedPricePaise(9999), 8999);
    expect(builtInSubscriptionOffers.first.saveBp, 0);
    expect(builtInSubscriptionOffers.first.quantityText(1500), '1.50 L');
    expect(builtInSubscriptionOffers.first.quantities, isNot(contains(1250)));

    late Uri asked;
    final load = subscriptionProductsLoader(
      'https://api.example.test',
      client: MockClient((request) async {
        asked = request.url;
        return http.Response(
          jsonEncode({
            'products': [
              _curdJson,
              {
                ..._curdJson,
                'product_id': 'ghee',
                'name': 'Ghee',
                'offered': false,
                'ends_on': '2026-12-01',
              },
            ],
          }),
          200,
        );
      }),
    );
    final products = SubscriptionProducts(load: load);
    await products.refresh();
    expect(asked.toString(), contains('all=true'));
    expect(products.offered.map((o) => o.productId), ['curd']);
    // A stopped product still has its name and measure.
    expect(products.nameOf('ghee'), 'Ghee');
    expect(products.offerFor('ghee')!.endsOn, DateTime(2026, 12, 1));
    // The milks are always known.
    expect(products.quantityText('cow_milk', 750), '0.75 L');
  });

  test('phone database v21 to v22 keeps plans and takes packs', () async {
    // Today's database, with the v21 milk-only checks put back.
    await MilkDatabaseService.instance.database;
    await MilkDatabaseService.instance.close();
    final old = await databaseFactoryFfi.openDatabase(path);
    final sql =
        (await old.rawQuery(
              "SELECT sql FROM sqlite_master WHERE name = 'milk_subscriptions'",
            )).single['sql']
            as String;
    await old.execute('DROP TABLE milk_shift_schedules');
    await old.execute('DROP TABLE milk_subscriptions');
    await old.execute(
      sql.replaceFirst(
        'CHECK (length(product_id) > 0)',
        "CHECK (product_id IN ('buffalo_milk', 'cow_milk'))",
      ),
    );
    await old.execute('''
      CREATE TABLE milk_shift_schedules (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        subscription_id TEXT NOT NULL,
        shift TEXT NOT NULL
          CHECK (shift IN ('earlyMorning', 'morning', 'evening')),
        quantity_ml INTEGER NOT NULL
          CHECK (quantity_ml >= 500 AND quantity_ml <= 10000
            AND quantity_ml % 250 = 0 AND quantity_ml % 1000 != 250),
        frequency TEXT NOT NULL,
        selected_weekdays TEXT NOT NULL DEFAULT '[]',
        selected_random_dates TEXT NOT NULL DEFAULT '[]',
        start_date TEXT NOT NULL,
        end_date TEXT,
        FOREIGN KEY (subscription_id) REFERENCES milk_subscriptions(id)
          ON DELETE CASCADE,
        UNIQUE (subscription_id, shift))''');
    final start = DateTime(2026, 11, 20);
    await old.insert('milk_subscriptions', {
      'id': 'p1',
      'product_id': 'cow_milk',
      'created_at': start.toIso8601String(),
    });
    await old.insert('milk_shift_schedules', {
      'subscription_id': 'p1',
      'shift': 'morning',
      'quantity_ml': 1500,
      'frequency': 'daily',
      'start_date': start.toIso8601String(),
    });
    await expectLater(
      old.insert('milk_subscriptions', {
        'id': 'c0',
        'product_id': 'curd',
        'created_at': start.toIso8601String(),
      }),
      throwsA(isA<DatabaseException>()),
    );
    await old.setVersion(21);
    await old.close();

    final db = await MilkDatabaseService.instance.database;
    expect(await db.getVersion(), MilkDatabaseService.databaseVersion);
    final plans = await MilkSubscriptionRepository().loadSubscriptions();
    expect(plans.single.productId, 'cow_milk');
    expect(plans.single.shiftSchedules.single.quantityMl, 1500);
    // No tables left from the rebuild.
    final tables = await db.rawQuery(
      "SELECT name FROM sqlite_master WHERE type = 'table' AND name LIKE '%v22%'",
    );
    expect(tables, isEmpty);

    await MilkSubscriptionRepository().saveSubscription(
      MilkSubscription(
        id: 'c1',
        productId: 'curd',
        shiftSchedules: [
          MilkShiftSchedule(
            shift: MilkDeliveryShift.morning,
            quantityMl: 2,
            frequency: MilkDeliveryFrequency.daily,
            startDate: start,
          ),
        ],
        quantity: 1,
        frequency: MilkDeliveryFrequency.daily,
        startDate: start,
      ),
    );
    final after = await MilkSubscriptionRepository().loadSubscriptions();
    expect(after.map((p) => p.productId), containsAll(['cow_milk', 'curd']));
  });

  testWidgets('curd in packs, morning only, tried for 7 days', (tester) async {
    bigScreen(tester);
    await tester.runAsync(() => MilkDatabaseService.instance.database);
    await tester.pumpWidget(
      MaterialApp(
        home: MilkSubscriptionSetupScreen(
          productId: 'curd',
          checkAddress: (_) async => true,
        ),
      ),
    );

    expect(find.text('Set Up Subscription'), findsOneWidget);
    expect(find.text('Curd · 500 g'), findsOneWidget);
    // Subscribe & save: the shop's ₹120, 10% off (step 6c).
    expect(
      find.text('₹108 a pack when you subscribe (₹120 in the shop) · Save 10%'),
      findsOneWidget,
    );
    // Only the delivery time the owner offers.
    expect(find.byKey(const Key('shift-morning')), findsOneWidget);
    expect(find.byKey(const Key('shift-evening')), findsNothing);
    expect(find.byKey(const Key('shift-earlyMorning')), findsNothing);
    expect(find.text('1 × 500 g'), findsWidgets);

    // Up to the largest offered quantity.
    await tester.tap(find.byKey(const Key('Morning-more')));
    await tester.tap(find.byKey(const Key('Morning-more')));
    await tester.pump();
    expect(find.text('3 × 500 g'), findsWidgets);
    final more = tester.widget<IconButton>(
      find.byKey(const Key('Morning-more')),
    );
    expect(more.onPressed, isNull);
    await tester.tap(find.byKey(const Key('Morning-less')));
    await tester.pump();

    await tester.tap(find.byKey(const Key('try-7-days')));
    await tester.pump();
    expect(find.textContaining('stop by themselves after 7 days'), findsOne);

    await tester.tap(find.text('Save Subscription'));
    await waitUntil(
      tester,
      () =>
          !sudhamrtamMilkSubscriptions.isWriting &&
          sudhamrtamMilkSubscriptions.plansFor('curd').isNotEmpty,
    );
    final plan = sudhamrtamMilkSubscriptions.plansFor('curd').single;
    final morning = plan.scheduleFor(MilkDeliveryShift.morning)!;
    expect(morning.quantityMl, 2);
    expect(
      morning.endDate,
      DateUtils.dateOnly(morning.startDate).add(const Duration(days: 6)),
    );
    expect(plan.shiftSchedules, hasLength(1));

    // Now an existing customer: no trial for another product.
    await tester.pumpWidget(
      MaterialApp(
        key: UniqueKey(),
        home: MilkSubscriptionSetupScreen(
          productId: 'paneer',
          checkAddress: (_) async => true,
        ),
      ),
    );
    await tester.pump();
    expect(find.text('Set Up Subscription'), findsOneWidget);
    expect(find.byKey(const Key('try-7-days')), findsNothing);

    // The Subscriptions page: the product, in packs, and Keep it going.
    await tester.pumpWidget(
      MaterialApp(key: UniqueKey(), home: const MilkPlanScreen()),
    );
    await tester.pump();
    expect(find.byKey(const Key('startPlan-Curd')), findsOneWidget);
    // Curd and Paneer (made from Curd) both save 10%.
    expect(find.text('Save 10% on subscription'), findsNWidgets(2));
    expect(find.byKey(const Key('startPlan-Paneer')), findsOneWidget);
    expect(find.byKey(const Key('milkCard_curd')), findsOneWidget);
    expect(find.text('2 × 500 g'), findsWidgets);
    expect(find.byKey(Key('endsNote_${plan.id}')), findsOneWidget);
    await tester.tap(find.byKey(Key('keepGoing_${plan.id}')));
    await waitUntil(
      tester,
      () =>
          !sudhamrtamMilkSubscriptions.isWriting &&
          sudhamrtamMilkSubscriptions
                  .plansFor('curd')
                  .single
                  .shiftSchedules
                  .single
                  .endDate ==
              null,
    );
    expect(
      sudhamrtamMilkSubscriptions
          .plansFor('curd')
          .single
          .shiftSchedules
          .single
          .endDate,
      isNull,
    );
    await tester.pump();
    expect(find.byKey(Key('endsNote_${plan.id}')), findsNothing);
    expect(find.text('Done: Curd keeps coming.'), findsOneWidget);
  });

  testWidgets('milk stays as before', (tester) async {
    bigScreen(tester);
    await tester.runAsync(() => MilkDatabaseService.instance.database);
    await tester.pumpWidget(
      MaterialApp(
        home: MilkSubscriptionSetupScreen(
          productId: 'buffalo_milk',
          checkAddress: (_) async => true,
        ),
      ),
    );
    expect(find.text('Set Up Milk Subscription'), findsOneWidget);
    for (final shift in MilkDeliveryShift.values) {
      expect(find.byKey(Key('shift-${shift.name}')), findsOneWidget);
    }
    expect(find.text('1.00 L'), findsWidgets);
    await tester.tap(find.byKey(const Key('Morning-more')));
    await tester.pump();
    // 1.25 L cannot be packed: 1.5 L comes next.
    expect(find.text('1.50 L'), findsWidgets);
    expect(find.byKey(const Key('offer-days-morning')), findsNothing);
  });
}
