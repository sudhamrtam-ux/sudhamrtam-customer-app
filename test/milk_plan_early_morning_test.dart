import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:sudhamrtam_customer_app/app/sudhamrtam_app.dart';
import 'package:sudhamrtam_customer_app/database/milk_database_service.dart';
import 'package:sudhamrtam_customer_app/database/milk_subscription_repository.dart';
import 'package:sudhamrtam_customer_app/features/milk_plan/milk_plan_screen.dart';
import 'package:sudhamrtam_customer_app/features/milk_plan/milk_subscription_setup_screen.dart';
import 'package:sudhamrtam_customer_app/models/milk_subscription.dart';
import 'package:sudhamrtam_customer_app/models/milk_subscription_manager.dart';

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

  test(
    'vacation: pause with a return date, kept on the phone; resume clears it',
    () async {
      final manager = MilkSubscriptionManager();
      await manager.loadSavedSubscriptions(const []);
      final plan = MilkSubscription(
        id: 'v1',
        productId: 'buffalo_milk',
        shiftSchedules: [
          MilkShiftSchedule(
            shift: MilkDeliveryShift.morning,
            quantityMl: 1000,
            frequency: MilkDeliveryFrequency.daily,
            startDate: DateTime(2026, 11, 8),
          ),
        ],
        quantity: 1,
        frequency: MilkDeliveryFrequency.daily,
        startDate: DateTime(2026, 11, 8),
      );
      expect(await manager.addSubscription(plan), isTrue);
      expect(
        await manager.pauseSubscription('v1', resumeOn: DateTime(2026, 11, 20)),
        isTrue,
      );
      var saved =
          (await MilkSubscriptionRepository().loadSubscriptions()).single;
      expect(saved.status, MilkSubscriptionStatus.paused);
      expect(saved.resumeOn, DateTime(2026, 11, 20));

      expect(await manager.resumeSubscription('v1'), isTrue);
      saved = (await MilkSubscriptionRepository().loadSubscriptions()).single;
      expect(saved.status, MilkSubscriptionStatus.active);
      expect(saved.resumeOn, isNull);

      // A plain pause has no return date.
      expect(await manager.pauseSubscription('v1'), isTrue);
      expect(manager.subscriptions.single.resumeOn, isNull);
    },
  );

  test('a cancelled plan keeps when it was cancelled', () async {
    final repo = MilkSubscriptionRepository();
    final plan = MilkSubscription(
      id: 'p1',
      productId: 'cow_milk',
      shiftSchedules: [
        MilkShiftSchedule(
          shift: MilkDeliveryShift.morning,
          quantityMl: 1000,
          frequency: MilkDeliveryFrequency.daily,
          startDate: DateTime(2026, 11, 8),
        ),
      ],
      quantity: 1,
      frequency: MilkDeliveryFrequency.daily,
      startDate: DateTime(2026, 11, 8),
    );
    await repo.saveChanges(saves: [plan]);
    expect((await repo.loadSubscriptions()).single.cancelledAt, isNull);

    // Cancelled on the phone: today.
    await repo.saveChanges(saves: const [], cancelIds: ['p1']);
    final cancelled = (await repo.loadSubscriptions()).single;
    expect(cancelled.status, MilkSubscriptionStatus.cancelled);
    expect(cancelled.cancelledAt, isNotNull);

    // The server's copy wins.
    await repo.replaceAll([
      cancelled.copyWith(cancelledAt: DateTime(2026, 11, 10, 9, 30)),
    ]);
    final mirrored = (await repo.loadSubscriptions()).single;
    expect(mirrored.cancelledAt, DateTime(2026, 11, 10, 9, 30));
    expect(
      planDatesText(mirrored),
      'Started 8 Nov 2026 · Cancelled 10 Nov 2026',
    );
    expect(
      planDatesText(mirrored.copyWith(status: MilkSubscriptionStatus.active)),
      'Started 8 Nov 2026 · Cancelled 10 Nov 2026',
    );
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

  test('v11 to the latest keeps milk plans and allows early morning', () async {
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
    expect(await db.getVersion(), MilkDatabaseService.databaseVersion);
    // v13: the cancel date column, empty for old plans.
    expect(
      (await db.query('milk_subscriptions')).single,
      containsPair('cancelled_at', null),
    );
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
