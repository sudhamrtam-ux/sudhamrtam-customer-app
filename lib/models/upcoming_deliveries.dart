import 'milk_subscription.dart';

/// One delivery the customer's subscriptions will bring on a day
/// (owner request 2026-11-25, calendar of deliveries).
class UpcomingDelivery {
  const UpcomingDelivery({
    required this.productId,
    required this.shift,
    required this.quantity,
  });

  final String productId;
  final MilkDeliveryShift shift;

  /// ml, or packs for a pack product.
  final int quantity;
}

DateTime _dateOnly(DateTime d) => DateTime(d.year, d.month, d.day);

/// Whole days from [from] to [to] (dates only, no clock change issues).
int _daysBetween(DateTime from, DateTime to) => DateTime.utc(
  to.year,
  to.month,
  to.day,
).difference(DateTime.utc(from.year, from.month, from.day)).inDays;

/// Whether [schedule] delivers on [day]: the server's rule
/// (`deliversOn` in the backend's deliveries/schedule.ts).
bool scheduleDeliversOn(MilkShiftSchedule schedule, DateTime day) {
  final date = _dateOnly(day);
  if (date.isBefore(_dateOnly(schedule.startDate))) return false;
  final end = schedule.endDate;
  if (end != null && date.isAfter(_dateOnly(end))) return false;
  switch (schedule.frequency) {
    case MilkDeliveryFrequency.daily:
      return true;
    case MilkDeliveryFrequency.alternateDays:
      return _daysBetween(schedule.startDate, date) % 2 == 0;
    case MilkDeliveryFrequency.selectedDays:
      return schedule.selectedWeekdays.contains(date.weekday);
    case MilkDeliveryFrequency.randomDays:
      return schedule.selectedRandomDates.any((d) => _dateOnly(d) == date);
  }
}

/// What [plans] will deliver on [day], as they are now: not for
/// cancelled plans or ones waiting for approval, not on vacation days,
/// and for a paused plan only from its return date. One-day changes
/// and skips are not known here.
List<UpcomingDelivery> upcomingDeliveriesOn(
  Iterable<MilkSubscription> plans,
  DateTime day,
) {
  final date = _dateOnly(day);
  final result = <UpcomingDelivery>[];
  for (final plan in plans) {
    if (plan.status == MilkSubscriptionStatus.cancelled) continue;
    if (plan.approval == 'pending' || plan.approval == 'rejected') continue;
    if (plan.status == MilkSubscriptionStatus.paused) {
      final back = plan.resumeOn;
      if (back == null || date.isBefore(_dateOnly(back))) continue;
    }
    if (plan.isVacationDay(date)) continue;
    for (final schedule in plan.shiftSchedules) {
      if (scheduleDeliversOn(schedule, date)) {
        result.add(
          UpcomingDelivery(
            productId: plan.productId,
            shift: schedule.shift,
            quantity: schedule.quantityMl,
          ),
        );
      }
    }
  }
  result.sort((a, b) => a.shift.index.compareTo(b.shift.index));
  return result;
}
