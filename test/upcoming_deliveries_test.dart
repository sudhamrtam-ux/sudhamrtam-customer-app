import 'package:flutter_test/flutter_test.dart';

import 'package:sudhamrtam_customer_app/models/milk_subscription.dart';
import 'package:sudhamrtam_customer_app/models/upcoming_deliveries.dart';

/// The calendar of deliveries (owner request 2026-11-25) follows the
/// server's delivery rule.
MilkSubscription plan(
  String id,
  List<MilkShiftSchedule> shifts, {
  String product = 'cow_milk',
  MilkSubscriptionStatus status = MilkSubscriptionStatus.active,
  DateTime? resumeOn,
  String? approval = 'approved',
  List<DateTime> vacation = const [],
}) => MilkSubscription(
  id: id,
  productId: product,
  shiftSchedules: shifts,
  quantity: 1,
  frequency: MilkDeliveryFrequency.daily,
  startDate: shifts.first.startDate,
  status: status,
  resumeOn: resumeOn,
  approval: approval,
  vacationDates: vacation,
);

MilkShiftSchedule shift(
  MilkDeliveryFrequency frequency, {
  MilkDeliveryShift at = MilkDeliveryShift.morning,
  int quantity = 1000,
  List<int> weekdays = const [],
  List<DateTime> dates = const [],
  DateTime? end,
}) => MilkShiftSchedule(
  shift: at,
  quantityMl: quantity,
  frequency: frequency,
  selectedWeekdays: weekdays,
  selectedRandomDates: dates,
  // Sunday 8 November 2026.
  startDate: DateTime(2026, 11, 8),
  endDate: end,
);

void main() {
  List<String> on(List<MilkSubscription> plans, int day) => [
    for (final d in upcomingDeliveriesOn(plans, DateTime(2026, 11, day)))
      '${d.productId} ${d.shift.name} ${d.quantity}',
  ];

  test('each frequency, like the server', () {
    final plans = [
      plan('a', [
        shift(MilkDeliveryFrequency.alternateDays),
        shift(
          MilkDeliveryFrequency.selectedDays,
          at: MilkDeliveryShift.evening,
          quantity: 500,
          weekdays: [1, 3],
        ),
      ]),
      plan('b', [
        shift(
          MilkDeliveryFrequency.randomDays,
          at: MilkDeliveryShift.earlyMorning,
          quantity: 2,
          dates: [DateTime(2026, 11, 11)],
        ),
      ], product: 'curd'),
    ];
    expect(on(plans, 7), isEmpty); // before the start
    expect(on(plans, 8), ['cow_milk morning 1000']); // Sunday, day 0
    expect(on(plans, 9), ['cow_milk evening 500']); // Monday, odd day
    expect(on(plans, 10), ['cow_milk morning 1000']);
    // Wednesday, with the curd date; early morning first.
    expect(on(plans, 11), ['curd earlyMorning 2', 'cow_milk evening 500']);
  });

  test('end dates, pauses, vacations and approval', () {
    final daily = shift(
      MilkDeliveryFrequency.daily,
      end: DateTime(2026, 11, 14),
    );
    expect(
      on([
        plan('t', [daily]),
      ], 14),
      hasLength(1),
    );
    expect(
      on([
        plan('t', [daily]),
      ], 15),
      isEmpty,
    ); // trial over
    expect(
      on([
        plan(
          'v',
          [shift(MilkDeliveryFrequency.daily)],
          vacation: [DateTime(2026, 11, 12)],
        ),
      ], 12),
      isEmpty,
    );
    final paused = plan(
      'p',
      [shift(MilkDeliveryFrequency.daily)],
      status: MilkSubscriptionStatus.paused,
      resumeOn: DateTime(2026, 11, 20),
    );
    expect(on([paused], 19), isEmpty);
    expect(on([paused], 20), hasLength(1));
    expect(
      on([
        plan('u', [
          shift(MilkDeliveryFrequency.daily),
        ], status: MilkSubscriptionStatus.paused),
      ], 20),
      isEmpty,
    );
    expect(
      on([
        plan('w', [shift(MilkDeliveryFrequency.daily)], approval: 'pending'),
      ], 12),
      isEmpty,
    );
    // Kept on the phone only (no server): it counts.
    expect(
      on([
        plan('l', [shift(MilkDeliveryFrequency.daily)], approval: null),
      ], 12),
      hasLength(1),
    );
    expect(
      on([
        plan('c', [
          shift(MilkDeliveryFrequency.daily),
        ], status: MilkSubscriptionStatus.cancelled),
      ], 12),
      isEmpty,
    );
  });
}
