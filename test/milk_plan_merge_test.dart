import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:sudhamrtam_customer_app/app/sudhamrtam_app.dart';
import 'package:sudhamrtam_customer_app/database/milk_database_service.dart';
import 'package:sudhamrtam_customer_app/database/milk_subscription_repository.dart';
import 'package:sudhamrtam_customer_app/features/milk_plan/milk_plan_screen.dart';
import 'package:sudhamrtam_customer_app/features/milk_plan/milk_subscription_setup_screen.dart';
import 'package:sudhamrtam_customer_app/models/milk_plan_merge.dart';
import 'package:sudhamrtam_customer_app/models/milk_subscription.dart';
import 'package:sudhamrtam_customer_app/models/milk_subscription_manager.dart';

final start = DateTime(2026, 11, 8);

MilkShiftSchedule shift(
  MilkDeliveryShift s,
  int ml, {
  MilkDeliveryFrequency frequency = MilkDeliveryFrequency.daily,
  List<int> weekdays = const [],
  DateTime? startDate,
  DateTime? endDate,
}) => MilkShiftSchedule(
  shift: s,
  quantityMl: ml,
  frequency: frequency,
  selectedWeekdays: weekdays,
  startDate: startDate ?? start,
  endDate: endDate,
);

MilkShiftSchedule morning(
  int ml, {
  MilkDeliveryFrequency frequency = MilkDeliveryFrequency.daily,
}) => shift(MilkDeliveryShift.morning, ml, frequency: frequency);

MilkShiftSchedule evening(int ml) => shift(MilkDeliveryShift.evening, ml);

MilkSubscription plan(
  String id,
  List<MilkShiftSchedule> schedules, {
  String productId = 'cow_milk',
  MilkSubscriptionStatus status = MilkSubscriptionStatus.active,
}) => MilkSubscription(
  id: id,
  productId: productId,
  shiftSchedules: schedules,
  quantity: 1,
  frequency: MilkDeliveryFrequency.daily,
  startDate: schedules.first.startDate,
  status: status,
);

/// (shift, ml) pairs of a plan, for compact checks.
List<(MilkDeliveryShift, int)> shifts(MilkSubscription p) => [
  for (final s in p.shiftSchedules) (s.shift, s.quantityMl),
];

/// A plan's ID and shifts as text (records holding lists are not
/// compared by content).
String d(String id, List<(MilkDeliveryShift, int)> shifts) => '$id $shifts';

const m = MilkDeliveryShift.morning;
const e = MilkDeliveryShift.evening;

void main() {
  group('a new subscription: one subscription per milk and shift', () {
    test('same shift and days: added to the existing subscription', () {
      final changes = planNewSubscription([
        plan('a', [morning(1000)]),
      ], plan('new', [morning(500)]));

      expect(changes.mergesIntoExisting, isTrue);
      expect(changes.isPossible, isTrue);
      expect(changes.saves.single.id, 'a');
      expect(shifts(changes.saves.single), [(m, 1500)]);
      // The plan keeps its start: extra milk comes with the next delivery.
      expect(changes.saves.single.shiftSchedules.single.startDate, start);
    });

    test('another shift stays a separate subscription', () {
      final changes = planNewSubscription([
        plan('a', [morning(1000)]),
      ], plan('new', [evening(500)]));

      expect(changes.mergesIntoExisting, isFalse);
      expect(changes.saves.single.id, 'new');
      expect(shifts(changes.saves.single), [(e, 500)]);
    });

    test(
      'morning + evening: morning merges, evening is a new subscription',
      () {
        final changes = planNewSubscription([
          plan('a', [morning(1000)]),
        ], plan('new', [morning(500), evening(500)]));

        expect(changes.saves.map((p) => d(p.id, shifts(p))), [
          d('a', [(m, 1500)]),
          d('new', [(e, 500)]),
        ]);
      },
    );

    test('each shift merges into the subscription that delivers it', () {
      final changes = planNewSubscription([
        plan('a', [morning(1000)]),
        plan('b', [evening(1000)]),
      ], plan('new', [morning(500), evening(500)]));

      expect(changes.saves.map((p) => d(p.id, shifts(p))), [
        d('a', [(m, 1500)]),
        d('b', [(e, 1500)]),
      ]);
    });

    test('different days in the same shift cannot be merged', () {
      final a = plan('a', [morning(1000)]);
      final changes = planNewSubscription(
        [a],
        plan('new', [
          morning(500, frequency: MilkDeliveryFrequency.alternateDays),
        ]),
      );

      expect(changes.isPossible, isFalse);
      expect(changes.shifts.single.kind, ShiftMergeKind.differentSchedule);
      expect(changes.blockingPlan?.id, 'a');
    });

    test('the total per delivery cannot go over 10.00 L', () {
      final changes = planNewSubscription([
        plan('a', [morning(9500)]),
      ], plan('new', [morning(1000)]));

      expect(changes.isPossible, isFalse);
      expect(changes.shifts.single.kind, ShiftMergeKind.overLimit);
    });
  });

  group('existing subscriptions sharing a shift', () {
    test('the shared shift merges; the other shift keeps its subscription', () {
      final changes = combineSharedShifts([
        plan('a', [morning(1000)]),
        plan('b', [morning(500), evening(500)]),
      ])!;

      expect(changes.isPossible, isTrue);
      expect(changes.saves.map((p) => d(p.id, shifts(p))), [
        d('a', [(m, 1500)]),
        d('b', [(e, 500)]),
      ]);
      expect(changes.cancelIds, isEmpty);
    });

    test('a subscription left without shifts is cancelled', () {
      final changes = combineSharedShifts([
        plan('a', [morning(1000)]),
        plan('b', [morning(500)]),
      ])!;

      expect(changes.saves.map((p) => d(p.id, shifts(p))), [
        d('a', [(m, 1500)]),
      ]);
      expect(changes.cancelIds, ['b']);
    });

    test('separate morning and evening subscriptions are fine', () {
      expect(
        combineSharedShifts([
          plan('a', [morning(1000)]),
          plan('b', [evening(500)]),
        ]),
        isNull,
      );
    });

    test(
      'a paused and an active subscription are not merged automatically',
      () {
        final changes = combineSharedShifts([
          plan('a', [morning(1000)]),
          plan('b', [morning(500)], status: MilkSubscriptionStatus.paused),
        ])!;

        expect(changes.isPossible, isFalse);
        expect(changes.shifts.single.kind, ShiftMergeKind.differentStatus);
      },
    );
  });

  group('same delivery days', () {
    test('alternate days match only on the same rhythm', () {
      final base = morning(500, frequency: MilkDeliveryFrequency.alternateDays);
      expect(
        sameDeliveryDays(
          base,
          base.copyWith(startDate: start.add(const Duration(days: 2))),
        ),
        isTrue,
      );
      expect(
        sameDeliveryDays(
          base,
          base.copyWith(startDate: start.add(const Duration(days: 1))),
        ),
        isFalse,
      );
    });

    test('weekdays must be the same set; end dates must match', () {
      final monThu = shift(
        m,
        500,
        frequency: MilkDeliveryFrequency.selectedDays,
        weekdays: [1, 4],
      );
      expect(
        sameDeliveryDays(monThu, monThu.copyWith(selectedWeekdays: [4, 1])),
        isTrue,
      );
      expect(
        sameDeliveryDays(monThu, monThu.copyWith(selectedWeekdays: [1, 5])),
        isFalse,
      );
      expect(
        sameDeliveryDays(
          morning(500),
          shift(m, 500, endDate: DateTime(2026, 12, 1)),
        ),
        isFalse,
      );
    });
  });

  group('saved on the phone', () {
    late Directory directory;

    setUpAll(sqfliteFfiInit);

    setUp(() async {
      directory = await Directory.systemTemp.createTemp('sudhamrtam_milk_');
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

    Future<MilkSubscription> reload(String id) async {
      final saved = await MilkSubscriptionRepository().loadSubscriptions();
      return saved.firstWhere((p) => p.id == id);
    }

    Future<MilkSubscriptionManager> loaded(List<MilkSubscription> plans) async {
      final repository = MilkSubscriptionRepository();
      for (final p in plans) {
        await repository.saveSubscription(p);
      }
      final manager = MilkSubscriptionManager();
      await manager.loadSavedSubscriptions(
        await repository.loadSubscriptions(),
      );
      return manager;
    }

    test(
      'a second subscription for the same milk and shift is refused',
      () async {
        final manager = MilkSubscriptionManager();
        expect(
          await manager.addSubscription(plan('a', [morning(1000)])),
          isTrue,
        );

        expect(
          await manager.addSubscription(plan('b', [morning(500)])),
          isFalse,
        );
        // Another shift, or another milk, is a separate plan.
        expect(
          await manager.addSubscription(plan('c', [evening(500)])),
          isTrue,
        );
        expect(
          await manager.addSubscription(
            plan('d', [morning(500)], productId: 'buffalo_milk'),
          ),
          isTrue,
        );
        expect(manager.subscriptionCount, 3);
      },
    );

    test('a mixed new subscription is saved in one step', () async {
      final manager = MilkSubscriptionManager();
      await manager.addSubscription(plan('a', [morning(1000)]));

      final changes = manager.checkNewPlan(
        plan('new', [morning(500), evening(500)]),
      );
      expect(await manager.saveNewPlan(changes), isTrue);

      expect(shifts(await reload('a')), [(m, 1500)]);
      expect(shifts(await reload('new')), [(e, 500)]);
      expect(manager.plansFor('cow_milk'), hasLength(2));
    });

    test('an edit cannot add a shift another subscription delivers', () async {
      final manager = MilkSubscriptionManager();
      await manager.addSubscription(plan('a', [morning(1000)]));
      await manager.addSubscription(plan('b', [evening(500)]));

      final b = manager.plansFor('cow_milk').last;
      expect(
        await manager.updateSubscription(
          b.copyWith(shiftSchedules: [morning(500), evening(500)]),
        ),
        isFalse,
      );
      expect(
        await manager.updateSubscription(
          b.copyWith(shiftSchedules: [evening(1000)]),
        ),
        isTrue,
      );
    });

    test('existing shared shifts merge in one step', () async {
      final manager = await loaded([
        plan('a', [morning(1000)]),
        plan('b', [morning(500), evening(500)]),
      ]);

      expect(manager.duplicatePlans.single.canCombine, isTrue);
      expect(await manager.combinePlans('cow_milk'), isTrue);
      expect(manager.duplicatePlans, isEmpty);

      expect(shifts(await reload('a')), [(m, 1500)]);
      final b = await reload('b');
      expect(shifts(b), [(e, 500)]);
      expect(b.status, MilkSubscriptionStatus.active);
    });

    test('a subscription with nothing left is cancelled', () async {
      final manager = await loaded([
        plan('a', [morning(1000)]),
        plan('b', [morning(500)]),
      ]);

      expect(await manager.combinePlans('cow_milk'), isTrue);
      expect(shifts(await reload('a')), [(m, 1500)]);
      expect((await reload('b')).status, MilkSubscriptionStatus.cancelled);
    });

    test('subscriptions that cannot merge are left unchanged', () async {
      final manager = await loaded([
        plan('a', [morning(1000)]),
        plan('b', [
          morning(500, frequency: MilkDeliveryFrequency.alternateDays),
        ]),
      ]);

      expect(manager.duplicatePlans.single.canCombine, isFalse);
      expect(await manager.combinePlans('cow_milk'), isFalse);
      expect((await reload('b')).status, MilkSubscriptionStatus.active);
    });

    test('subscriptions come back after the app restarts', () async {
      final before = MilkSubscriptionManager();
      await before.addSubscription(
        plan('a', [morning(1000)], productId: 'buffalo_milk'),
      );
      await before.addSubscription(
        plan('b', [evening(500)], productId: 'buffalo_milk'),
      );

      // A new manager is what the app has after a restart.
      final after = MilkSubscriptionManager();
      expect(await after.restoreSavedSubscriptions(), 0);
      expect(after.plansFor('buffalo_milk').map((p) => p.id), ['a', 'b']);

      // ...so the one-plan-per-shift rule still holds.
      expect(
        await after.addSubscription(
          plan('c', [morning(500)], productId: 'buffalo_milk'),
        ),
        isFalse,
      );
    });

    test('a failed save changes nothing', () async {
      final repository = MilkSubscriptionRepository();
      await repository.saveSubscription(plan('a', [morning(1000)]));

      await expectLater(
        repository.saveChanges(
          saves: [
            plan('a', [morning(1500)]),
          ],
          cancelIds: ['missing'],
        ),
        throwsStateError,
      );
      expect(shifts(await reload('a')), [(m, 1000)]);
    });
  });

  group('screens', () {
    late Directory directory;

    setUpAll(sqfliteFfiInit);

    setUp(() async {
      directory = await Directory.systemTemp.createTemp('sudhamrtam_milkui_');
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

    testWidgets('a second morning Cow Subscription asks to merge', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(1080, 6000);
      tester.view.devicePixelRatio = 2;
      addTearDown(tester.view.reset);

      // The app's shared manager: 1.00 L every morning.
      await tester.runAsync(
        () => sudhamrtamMilkSubscriptions.addSubscription(
          plan('existing', [
            shift(m, 1000, startDate: DateUtils.dateOnly(DateTime.now())),
          ]),
        ),
      );

      await tester.pumpWidget(
        const MaterialApp(
          home: MilkSubscriptionSetupScreen(productName: 'Cow Milk'),
        ),
      );

      // The new plan's default: 1.00 L every morning.
      await tester.tap(find.text('Save Milk Subscription'));
      await waitUntil(
        tester,
        () => find.byKey(const Key('addToPlanDialog')).evaluate().isNotEmpty,
      );

      expect(find.byKey(const Key('addToPlanDialog')), findsOneWidget);
      expect(
        find.textContaining('Morning: 1.00 L → 2.00 L every day'),
        findsOneWidget,
      );

      await tester.tap(find.byKey(const Key('addToPlanConfirm')));
      await waitUntil(
        tester,
        () =>
            !sudhamrtamMilkSubscriptions.isWriting &&
            sudhamrtamMilkSubscriptions
                    .plansFor('cow_milk')
                    .single
                    .shiftSchedules
                    .single
                    .quantityMl ==
                2000,
      );

      final plans = sudhamrtamMilkSubscriptions.plansFor('cow_milk');
      expect(plans, hasLength(1));
      expect(shifts(plans.single), [(m, 2000)]);
    });

    testWidgets('the subscription list offers to merge shared shifts', (
      tester,
    ) async {
      final plans = [
        plan('a', [morning(1000)]),
        plan('b', [morning(500), evening(500)]),
      ];
      final group = DuplicateMilkPlans(
        'cow_milk',
        plans,
        combineSharedShifts(plans)!,
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(body: DuplicatePlansBanner(group: group)),
        ),
      );

      expect(
        find.text('Two Cow Milk subscriptions deliver in the same shift'),
        findsOneWidget,
      );
      expect(
        find.textContaining('Morning: 1.00 L → 1.50 L every day'),
        findsOneWidget,
      );
      expect(find.byKey(const Key('combinePlans')), findsOneWidget);
    });
  });

  group('one card per milk', () {
    test('the total counts only deliveries that are coming', () {
      expect(
        milkTotalText([
          plan('a', [morning(1000)], productId: 'buffalo_milk'),
          plan('b', [evening(500)], productId: 'buffalo_milk'),
        ]),
        'Total: 1.50 L every day',
      );
      expect(
        milkTotalText([
          plan('a', [morning(1000)]),
          plan('b', [evening(500)], status: MilkSubscriptionStatus.paused),
        ]),
        'Total: 1.00 L every day (evening paused)',
      );
      expect(
        milkTotalText([
          plan('a', [morning(1000)]),
          plan('b', [
            shift(e, 500, frequency: MilkDeliveryFrequency.alternateDays),
          ]),
        ]),
        'Up to 1.50 L on days with both deliveries',
      );
      expect(
        milkTotalText([
          plan('a', [morning(1000)], status: MilkSubscriptionStatus.paused),
        ]),
        'All deliveries are paused',
      );
    });

    testWidgets('morning and evening subscriptions share one card', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(1080, 4000);
      tester.view.devicePixelRatio = 2;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: MilkProductCard(
                productId: 'buffalo_milk',
                plans: [
                  plan('b', [evening(500)], productId: 'buffalo_milk'),
                  plan('a', [morning(1000)], productId: 'buffalo_milk'),
                  plan('c', [
                    shift(MilkDeliveryShift.earlyMorning, 500),
                  ], productId: 'buffalo_milk'),
                ],
              ),
            ),
          ),
        ),
      );

      expect(find.text('Buffalo Milk'), findsOneWidget);
      expect(find.text('Early morning Delivery'), findsOneWidget);
      expect(find.text('Morning Delivery'), findsOneWidget);
      expect(find.text('Evening Delivery'), findsOneWidget);
      expect(find.text('Total: 2.00 L every day'), findsOneWidget);
      // Each plan keeps its own Pause button.
      expect(find.text('Pause'), findsNWidgets(3));
      // Early morning, then morning, then evening.
      expect(
        tester.getTopLeft(find.text('Early morning Delivery')).dy,
        lessThan(tester.getTopLeft(find.text('Morning Delivery')).dy),
      );
      expect(
        tester.getTopLeft(find.text('Morning Delivery')).dy,
        lessThan(tester.getTopLeft(find.text('Evening Delivery')).dy),
      );
    });
  });
}
