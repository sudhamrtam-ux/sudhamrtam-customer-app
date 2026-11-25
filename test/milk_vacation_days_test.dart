import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:sudhamrtam_customer_app/database/milk_database_service.dart';
import 'package:sudhamrtam_customer_app/database/milk_subscription_repository.dart';
import 'package:sudhamrtam_customer_app/features/home/account_status.dart';
import 'package:sudhamrtam_customer_app/features/milk_plan/vacation_days_screen.dart';
import 'package:sudhamrtam_customer_app/models/milk_subscription.dart';
import 'package:sudhamrtam_customer_app/models/milk_subscription_manager.dart';
import 'package:sudhamrtam_customer_app/services/milk_plan_api_client.dart';

/// 11 November 2026.
final today = DateTime(2026, 11, 11, 9);

MilkSubscription plan(String id, {List<DateTime> vacation = const []}) =>
    MilkSubscription(
      id: id,
      productId: 'cow_milk',
      shiftSchedules: [
        MilkShiftSchedule(
          shift: MilkDeliveryShift.morning,
          quantityMl: 1000,
          frequency: MilkDeliveryFrequency.daily,
          startDate: DateTime(2026, 11, 1),
        ),
      ],
      quantity: 1,
      frequency: MilkDeliveryFrequency.daily,
      startDate: DateTime(2026, 11, 1),
      vacationDates: vacation,
    );

DateTime nov(int day) => DateTime(2026, 11, day);

void main() {
  group('vacation days (owner decision 2026-11-11)', () {
    test('days in a row show as a range', () {
      expect(vacationDaysText([nov(15)]), '15 Nov');
      expect(
        vacationDaysText([nov(24), nov(15), nov(22), nov(18), nov(23)]),
        '15 Nov, 18 Nov, 22–24 Nov',
      );
      expect(
        vacationDaysText([
          nov(30),
          DateTime(2026, 12, 1),
          DateTime(2026, 12, 2),
        ]),
        '30 Nov – 2 Dec',
      );
    });

    test('the subscription knows its days', () {
      final p = plan('a', vacation: [nov(10), nov(11), nov(15)]);
      expect(p.vacationDaysFrom(today), [nov(11), nov(15)]);
      expect(p.isVacationDay(today), isTrue);
      expect(p.isVacationDay(nov(12)), isFalse);
      // Edits keep them.
      expect(p.copyWith(status: MilkSubscriptionStatus.paused).vacationDates, [
        nov(10),
        nov(11),
        nov(15),
      ]);
    });

    test('the server JSON carries the days (past days left out)', () {
      final days = [DateTime(2030, 1, 2), DateTime(2030, 1, 1)];
      final json = MilkPlanApiClient.planToJson(
        plan('a', vacation: [DateTime(2020, 1, 1), ...days]),
      );
      expect(json['vacation_dates'], ['2030-01-02', '2030-01-01']);
      final back = MilkPlanApiClient.planFromJson({
        ...json,
        'vacation_dates': ['2030-01-02', '2030-01-01'],
      });
      expect(back.vacationDates, [DateTime(2030, 1, 1), DateTime(2030, 1, 2)]);
      expect(
        MilkPlanApiClient.planFromJson({...json}..remove('vacation_dates'))
            .vacationDates,
        isEmpty,
      );
    });

    test('Home: on vacation today, and when milk comes again', () {
      final away = plan('a', vacation: [nov(11), nov(12), nov(14)]);
      final s = accountStatusFor([away], today);
      expect(s.state, AccountState.vacation);
      expect(s.detail, contains('Milk restarts on 13 Nov'));

      // Another milk still coming: active, with a note.
      final both = accountStatusFor([
        away,
        plan('b').copyWith(productId: 'buffalo_milk'),
      ], today);
      expect(both.state, AccountState.active);
      expect(both.detail, contains('Cow Milk on vacation until 12 Nov'));

      // Vacation later: still active today.
      expect(
        accountStatusFor([
          plan('c', vacation: [nov(20)]),
        ], today).state,
        AccountState.active,
      );
    });
  });

  group('the calendar', () {
    Text summary(WidgetTester tester) => tester.widget<Text>(
      find.descendant(
        of: find.byKey(const Key('vacationSummary')),
        matching: find.byType(Text),
      ),
    );

    testWidgets('one day, separate days and a range, in any mix', (
      tester,
    ) async {
      List<DateTime>? saved;
      tester.view.physicalSize = const Size(1080, 3000);
      tester.view.devicePixelRatio = 2;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => Scaffold(
              body: TextButton(
                onPressed: () async {
                  saved = await Navigator.of(context).push<List<DateTime>>(
                    MaterialPageRoute(
                      builder: (_) => VacationDaysScreen(
                        milkName: 'Cow Milk',
                        today: today,
                        pickRange: (_, first, last) async {
                          expect(first, nov(12));
                          expect(last, DateTime(2027, 5, 10));
                          return DateTimeRange(start: nov(22), end: nov(24));
                        },
                      ),
                    ),
                  );
                },
                child: const Text('open'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();

      expect(find.text('November 2026'), findsOneWidget);
      expect(summary(tester).data, 'No vacation days chosen.');

      // Today cannot be chosen (its milk is already on the way).
      await tester.tap(find.byKey(const Key('vacationDay-2026-11-11')));
      await tester.pump();
      expect(summary(tester).data, 'No vacation days chosen.');

      await tester.tap(find.byKey(const Key('vacationDay-2026-11-15')));
      await tester.tap(find.byKey(const Key('vacationDay-2026-11-18')));
      await tester.tap(find.byKey(const Key('vacationDay-2026-11-20')));
      await tester.pump();
      // Tapping again takes a day off.
      await tester.tap(find.byKey(const Key('vacationDay-2026-11-20')));
      await tester.tap(find.byKey(const Key('vacationRange')));
      await tester.pumpAndSettle();
      expect(
        summary(tester).data,
        'No milk on 5 days: 15 Nov, 18 Nov, 22–24 Nov',
      );

      // Next month too.
      await tester.tap(find.byKey(const Key('vacationNextMonth')));
      await tester.pump();
      expect(find.text('December 2026'), findsOneWidget);
      await tester.tap(find.byKey(const Key('vacationDay-2026-12-01')));
      await tester.pump();

      await tester.tap(find.byKey(const Key('vacationSave')));
      await tester.pumpAndSettle();
      expect(saved, [
        nov(15),
        nov(18),
        nov(22),
        nov(23),
        nov(24),
        DateTime(2026, 12, 1),
      ]);
    });

    testWidgets('opens with the saved days; Clear all removes them', (
      tester,
    ) async {
      List<DateTime>? saved;
      tester.view.physicalSize = const Size(1080, 3000);
      tester.view.devicePixelRatio = 2;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => Scaffold(
              body: TextButton(
                onPressed: () async {
                  saved = await Navigator.of(context).push<List<DateTime>>(
                    MaterialPageRoute(
                      builder: (_) => VacationDaysScreen(
                        milkName: 'Cow Milk',
                        today: today,
                        // A past day is dropped.
                        initial: [nov(5), DateTime(2026, 12, 3)],
                      ),
                    ),
                  );
                },
                child: const Text('open'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      // Opens at the first saved day's month.
      expect(find.text('December 2026'), findsOneWidget);
      expect(summary(tester).data, 'No milk on 1 day: 3 Dec');

      await tester.tap(find.byKey(const Key('vacationClear')));
      await tester.pump();
      await tester.tap(find.byKey(const Key('vacationSave')));
      await tester.pumpAndSettle();
      expect(saved, isEmpty);
    });
  });

  group('on the phone', () {
    late Directory directory;
    late String path;

    setUpAll(sqfliteFfiInit);
    setUp(() async {
      directory = await Directory.systemTemp.createTemp('sudhamrtam_vac_');
      path = '${directory.path}${Platform.pathSeparator}milk.db';
      MilkDatabaseService.instance.configureForTesting(
        factory: databaseFactoryFfi,
        databasePath: path,
      );
    });
    tearDown(() async {
      await MilkDatabaseService.instance.close();
      MilkDatabaseService.instance.resetTestingConfiguration();
      await directory.delete(recursive: true);
    });

    test('the days are saved and survive a restart', () async {
      final manager = MilkSubscriptionManager();
      expect(await manager.addSubscription(plan('a')), isTrue);
      expect(
        await manager.setVacationDates('a', [nov(18), nov(15), nov(15)]),
        isTrue,
      );
      expect(manager.subscriptions.single.vacationDates, [nov(15), nov(18)]);

      final loaded = await MilkSubscriptionRepository().loadSubscriptions();
      expect(loaded.single.vacationDates, [nov(15), nov(18)]);

      expect(await manager.setVacationDates('a', const []), isTrue);
      expect(
        (await MilkSubscriptionRepository().loadSubscriptions())
            .single
            .vacationDates,
        isEmpty,
      );
    });

    test(
      'v17 to v18 keeps subscriptions and adds empty vacation days',
      () async {
        await MilkSubscriptionRepository().saveSubscription(plan('a'));
        await MilkDatabaseService.instance.close();
        final old = await databaseFactoryFfi.openDatabase(path);
        await old.execute(
          'ALTER TABLE milk_subscriptions DROP COLUMN vacation_dates',
        );
        await old.setVersion(17);
        await old.close();

        final db = await MilkDatabaseService.instance.database;
        expect(await db.getVersion(), MilkDatabaseService.databaseVersion);
        final loaded = await MilkSubscriptionRepository().loadSubscriptions();
        expect(loaded.single.id, 'a');
        expect(loaded.single.vacationDates, isEmpty);
      },
    );
  });
}
