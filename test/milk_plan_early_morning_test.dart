import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:sudhamrtam_customer_app/app/sudhamrtam_app.dart';
import 'package:sudhamrtam_customer_app/database/milk_database_service.dart';
import 'package:sudhamrtam_customer_app/database/milk_subscription_repository.dart';
import 'package:sudhamrtam_customer_app/features/milk_plan/milk_subscription_setup_screen.dart';
import 'package:sudhamrtam_customer_app/models/milk_subscription.dart';

/// Early morning deliveries (owner decision 2026-11-10): last
/// evening's milk, kept cold; changes close at 9 PM the evening before.
///
/// In its own file: the app's shared plan manager queues writes,
/// and a write left from another test would hold this one up.
List<(MilkDeliveryShift, int)> shifts(MilkSubscription p) => [
  for (final s in p.shiftSchedules) (s.shift, s.quantityMl),
];

void main() {
  late Directory directory;

  setUpAll(sqfliteFfiInit);

  setUp(() async {
    directory = await Directory.systemTemp.createTemp('sudhamrtam_early_');
    MilkDatabaseService.instance.configureForTesting(
      factory: databaseFactoryFfi,
      databasePath: '${directory.path}${Platform.pathSeparator}milk.db',
    );
  });

  tearDown(() async {
    await MilkDatabaseService.instance.close();
    MilkDatabaseService.instance.resetTestingConfiguration();
    await directory.delete(recursive: true);
  });

  /// SQLite runs outside the test clock: alternate real waiting
  /// with frames until [done] (up to about 10 seconds).
  Future<void> waitUntil(WidgetTester tester, bool Function() done) async {
    for (var i = 0; i < 500 && !done(); i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 10)),
      );
      await tester.pump();
    }
  }

  test('v11 to v12 keeps milk plans and allows early morning', () async {
    final path = '${directory.path}${Platform.pathSeparator}milk.db';
    // A v11 phone: the schedules table allows only morning and evening.
    final old = await databaseFactoryFfi.openDatabase(
      path,
      options: OpenDatabaseOptions(
        version: 11,
        onCreate: (db, _) async {
          await db.execute('''
            CREATE TABLE milk_subscriptions (
              id TEXT PRIMARY KEY, product_id TEXT NOT NULL,
              quantity INTEGER NOT NULL, frequency TEXT NOT NULL,
              selected_weekdays TEXT NOT NULL DEFAULT '[]',
              selected_random_dates TEXT NOT NULL DEFAULT '[]',
              start_date TEXT NOT NULL, end_date TEXT,
              status TEXT NOT NULL DEFAULT 'active',
              created_at TEXT NOT NULL)''');
          await db.execute('''
            CREATE TABLE milk_shift_schedules (
              id INTEGER PRIMARY KEY AUTOINCREMENT,
              subscription_id TEXT NOT NULL,
              shift TEXT NOT NULL CHECK (shift IN ('morning', 'evening')),
              quantity_ml INTEGER NOT NULL,
              frequency TEXT NOT NULL,
              selected_weekdays TEXT NOT NULL DEFAULT '[]',
              selected_random_dates TEXT NOT NULL DEFAULT '[]',
              start_date TEXT NOT NULL,
              end_date TEXT,
              FOREIGN KEY (subscription_id) REFERENCES milk_subscriptions(id)
                ON DELETE CASCADE,
              UNIQUE (subscription_id, shift))''');
          await db.execute('''
            CREATE INDEX idx_milk_shift_subscription
            ON milk_shift_schedules(subscription_id)''');
        },
      ),
    );
    await old.insert('milk_subscriptions', {
      'id': 'p1',
      'product_id': 'buffalo_milk',
      'quantity': 1,
      'frequency': 'daily',
      'start_date': '2026-11-08T00:00:00.000',
      'created_at': '2026-11-08T00:00:00.000',
    });
    await old.insert('milk_shift_schedules', {
      'subscription_id': 'p1',
      'shift': 'evening',
      'quantity_ml': 1500,
      'frequency': 'daily',
      'start_date': '2026-11-08T00:00:00.000',
    });
    await expectLater(
      old.insert('milk_shift_schedules', {
        'subscription_id': 'p1',
        'shift': 'earlyMorning',
        'quantity_ml': 500,
        'frequency': 'daily',
        'start_date': '2026-11-08T00:00:00.000',
      }),
      throwsA(isA<DatabaseException>()),
    );
    await old.close();

    final db = await MilkDatabaseService.instance.database;
    expect(await db.getVersion(), 12);
    final rows = await db.query('milk_shift_schedules');
    expect(rows.single, containsPair('shift', 'evening'));
    expect(rows.single, containsPair('quantity_ml', 1500));

    await db.insert('milk_shift_schedules', {
      'subscription_id': 'p1',
      'shift': 'earlyMorning',
      'quantity_ml': 500,
      'frequency': 'daily',
      'start_date': '2026-11-08T00:00:00.000',
    });
    // Still one schedule per shift, and only known shifts.
    await expectLater(
      db.insert('milk_shift_schedules', {
        'subscription_id': 'p1',
        'shift': 'earlyMorning',
        'quantity_ml': 500,
        'frequency': 'daily',
        'start_date': '2026-11-08T00:00:00.000',
      }),
      throwsA(isA<DatabaseException>()),
    );
    await expectLater(
      db.insert('milk_shift_schedules', {
        'subscription_id': 'p1',
        'shift': 'midnight',
        'quantity_ml': 500,
        'frequency': 'daily',
        'start_date': '2026-11-08T00:00:00.000',
      }),
      throwsA(isA<DatabaseException>()),
    );
    final indexes = await db.rawQuery(
      "SELECT name FROM sqlite_master WHERE type = 'index' "
      "AND name = 'idx_milk_shift_subscription'",
    );
    expect(indexes, hasLength(1));
  });

  testWidgets('early morning: closes at 9 PM the evening before', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1080, 6000);
    tester.view.devicePixelRatio = 2;
    addTearDown(tester.view.reset);

    // Open the phone database outside the test clock first.
    await tester.runAsync(() => MilkDatabaseService.instance.database);
    await tester.pumpWidget(
      const MaterialApp(
        home: MilkSubscriptionSetupScreen(productName: 'Buffalo Milk'),
      ),
    );

    expect(find.text('Early morning Delivery'), findsOneWidget);
    expect(
      find.textContaining("Last evening's milk, kept cold overnight."),
      findsOneWidget,
    );
    // Notes appear for the shifts that are switched on.
    expect(find.text('Changes close at 6 AM that morning.'), findsOneWidget);
    expect(
      find.text('Changes close at 9 PM the evening before.'),
      findsNothing,
    );

    await tester.tap(find.byKey(const Key('shift-earlyMorning')));
    await tester.pump();
    expect(
      find.text('Changes close at 9 PM the evening before.'),
      findsOneWidget,
    );
    // Early morning is the first card.
    expect(
      tester.getTopLeft(find.text('Early morning Delivery')).dy,
      lessThan(tester.getTopLeft(find.text('Morning Delivery')).dy),
    );

    await tester.tap(find.text('Save Milk Subscription'));
    await waitUntil(
      tester,
      () =>
          !sudhamrtamMilkSubscriptions.isWriting &&
          sudhamrtamMilkSubscriptions.plansFor('buffalo_milk').isNotEmpty,
    );

    final saved = sudhamrtamMilkSubscriptions.plansFor('buffalo_milk');
    expect(shifts(saved.single), [
      (MilkDeliveryShift.earlyMorning, 500),
      (MilkDeliveryShift.morning, 1000),
    ]);

    // Kept on the phone and read back.
    final stored = await tester.runAsync(
      () => MilkSubscriptionRepository().loadSubscriptions(),
    );
    expect(
      stored!
          .where((p) => p.productId == 'buffalo_milk')
          .single
          .scheduleFor(MilkDeliveryShift.earlyMorning)
          ?.quantityMl,
      500,
    );
  });
}
