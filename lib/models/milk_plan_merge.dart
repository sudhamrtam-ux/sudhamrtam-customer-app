import 'milk_subscription.dart';

/// Rule: one plan per milk *and* shift. Cow Milk morning and Cow
/// Milk evening may be separate plans (so each can be paused or
/// changed on its own), but two plans may never deliver the same
/// milk in the same shift: those deliveries are merged.

/// Matches MilkSubscriptionManager.maximumQuantityMl (10 L).
const int maximumShiftQuantityMl = 10000;

/// What happens to one delivery shift.
enum ShiftMergeKind {
  /// No plan delivers this milk in this shift: it gets its own
  /// (new) plan.
  newPlan,

  /// Another plan already delivers this milk in this shift, on the
  /// same days: the quantities are added in that plan.
  addQuantity,

  /// Same shift but different delivery days or end date: one shift
  /// has one schedule, so they cannot be added together.
  differentSchedule,

  /// Adding would go over the maximum per delivery.
  overLimit,

  /// One plan is paused and the other active: not merged
  /// automatically.
  differentStatus,
}

class ShiftMergeOutcome {
  final MilkDeliveryShift shift;
  final ShiftMergeKind kind;

  /// The plan that already delivers this shift (null for newPlan).
  final MilkSubscription? target;

  /// Quantity already delivered in this shift (0 for newPlan).
  final int existingMl;
  final int addedMl;

  /// The delivery days of the plan that keeps this shift.
  final MilkShiftSchedule schedule;

  /// The other schedule, when two could not be merged.
  final MilkShiftSchedule? otherSchedule;

  const ShiftMergeOutcome({
    required this.shift,
    required this.kind,
    required this.existingMl,
    required this.addedMl,
    required this.schedule,
    this.target,
    this.otherSchedule,
  });

  int get resultMl => existingMl + addedMl;

  bool get isPossible =>
      kind == ShiftMergeKind.newPlan || kind == ShiftMergeKind.addQuantity;

  bool get isMerge => kind != ShiftMergeKind.newPlan;
}

/// The result of merging deliveries: plans to save and plans to
/// cancel, applied together in one database transaction.
class MilkPlanChanges {
  final String productId;
  final List<ShiftMergeOutcome> shifts;

  /// Plans to save (updated existing plans and/or one new plan).
  final List<MilkSubscription> saves;

  /// Plans left without any shift.
  final List<String> cancelIds;

  const MilkPlanChanges({
    required this.productId,
    required this.shifts,
    required this.saves,
    required this.cancelIds,
  });

  bool get isPossible => shifts.every((s) => s.isPossible);

  /// True when something is merged into an existing plan (the
  /// customer is asked first). False: a plain new plan.
  bool get mergesIntoExisting => shifts.any((s) => s.isMerge);

  /// The first existing plan that could not take a delivery (to
  /// offer editing it).
  MilkSubscription? get blockingPlan {
    for (final outcome in shifts) {
      if (!outcome.isPossible) return outcome.target;
    }
    return null;
  }
}

/// Checks a new plan against the customer's plans for the same
/// milk ([existing]: not cancelled, oldest first).
///
/// Each shift of [incoming] is either added to the plan that
/// already delivers that shift, or kept in the new plan.
MilkPlanChanges planNewSubscription(
  List<MilkSubscription> existing,
  MilkSubscription incoming, {
  int maximumMl = maximumShiftQuantityMl,
}) {
  final outcomes = <ShiftMergeOutcome>[];
  final updated = <String, MilkSubscription>{};
  final remaining = <MilkShiftSchedule>[];

  for (final added in incoming.shiftSchedules) {
    MilkSubscription? target;
    for (final plan in existing) {
      if (plan.scheduleFor(added.shift) != null) {
        target = plan;
        break;
      }
    }

    if (target == null) {
      remaining.add(added);
      outcomes.add(
        ShiftMergeOutcome(
          shift: added.shift,
          kind: ShiftMergeKind.newPlan,
          existingMl: 0,
          addedMl: added.quantityMl,
          schedule: added,
        ),
      );
      continue;
    }

    final current = (updated[target.id] ?? target).scheduleFor(added.shift)!;
    final kind = !sameDeliveryDays(current, added)
        ? ShiftMergeKind.differentSchedule
        : current.quantityMl + added.quantityMl > maximumMl
        ? ShiftMergeKind.overLimit
        : ShiftMergeKind.addQuantity;

    if (kind == ShiftMergeKind.addQuantity) {
      updated[target.id] = _withSchedule(
        updated[target.id] ?? target,
        current.copyWith(quantityMl: current.quantityMl + added.quantityMl),
      );
    }

    outcomes.add(
      ShiftMergeOutcome(
        shift: added.shift,
        kind: kind,
        target: target,
        existingMl: current.quantityMl,
        addedMl: added.quantityMl,
        schedule: current,
        otherSchedule: added,
      ),
    );
  }

  return MilkPlanChanges(
    productId: incoming.productId,
    shifts: List.unmodifiable(outcomes),
    saves: [
      ...updated.values,
      if (remaining.isNotEmpty) incoming.copyWith(shiftSchedules: remaining),
    ],
    cancelIds: const [],
  );
}

/// Merges plans of the same milk ([plans]: not cancelled, oldest
/// first) that deliver in the same shift. Returns null when no two
/// plans share a shift.
///
/// For each shared shift, the oldest plan keeps the delivery with
/// the quantities added; the shift is removed from the other plans.
/// A plan left without shifts is cancelled.
MilkPlanChanges? combineSharedShifts(
  List<MilkSubscription> plans, {
  int maximumMl = maximumShiftQuantityMl,
}) {
  final outcomes = <ShiftMergeOutcome>[];
  final working = {for (final plan in plans) plan.id: plan};

  for (final shift in MilkDeliveryShift.values) {
    final sharing = [
      for (final plan in plans)
        if (plan.scheduleFor(shift) != null) plan,
    ];
    if (sharing.length < 2) continue;

    final keeper = sharing.first;
    var schedule = keeper.scheduleFor(shift)!;
    var possible = true;

    for (final other in sharing.skip(1)) {
      final otherSchedule = other.scheduleFor(shift)!;
      final kind = other.status != keeper.status
          ? ShiftMergeKind.differentStatus
          : !sameDeliveryDays(schedule, otherSchedule)
          ? ShiftMergeKind.differentSchedule
          : schedule.quantityMl + otherSchedule.quantityMl > maximumMl
          ? ShiftMergeKind.overLimit
          : ShiftMergeKind.addQuantity;

      outcomes.add(
        ShiftMergeOutcome(
          shift: shift,
          kind: kind,
          target: keeper,
          existingMl: schedule.quantityMl,
          addedMl: otherSchedule.quantityMl,
          schedule: schedule,
          otherSchedule: otherSchedule,
        ),
      );

      if (kind != ShiftMergeKind.addQuantity) {
        possible = false;
        continue;
      }
      schedule = schedule.copyWith(
        quantityMl: schedule.quantityMl + otherSchedule.quantityMl,
      );
    }

    if (!possible) continue;
    working[keeper.id] = _withSchedule(working[keeper.id]!, schedule);
    for (final other in sharing.skip(1)) {
      working[other.id] = _withoutShift(working[other.id]!, shift);
    }
  }

  if (outcomes.isEmpty) return null;

  final saves = <MilkSubscription>[];
  final cancelIds = <String>[];
  for (final plan in plans) {
    final result = working[plan.id]!;
    if (identical(result, plan)) continue;
    if (result.shiftSchedules.isEmpty) {
      cancelIds.add(plan.id);
    } else {
      saves.add(result);
    }
  }

  return MilkPlanChanges(
    productId: plans.first.productId,
    shifts: List.unmodifiable(outcomes),
    saves: saves,
    cancelIds: cancelIds,
  );
}

MilkSubscription _withSchedule(
  MilkSubscription plan,
  MilkShiftSchedule schedule,
) => plan.copyWith(
  shiftSchedules: [
    for (final s in plan.shiftSchedules)
      if (s.shift == schedule.shift) schedule else s,
  ],
);

MilkSubscription _withoutShift(
  MilkSubscription plan,
  MilkDeliveryShift shift,
) => plan.copyWith(
  shiftSchedules: [
    for (final s in plan.shiftSchedules)
      if (s.shift != shift) s,
  ],
);

DateTime _day(DateTime date) => DateTime(date.year, date.month, date.day);

/// Whether two schedules deliver on exactly the same days, so their
/// quantities can simply be added.
bool sameDeliveryDays(MilkShiftSchedule a, MilkShiftSchedule b) {
  if (a.frequency != b.frequency) return false;

  final aEnd = a.endDate == null ? null : _day(a.endDate!);
  final bEnd = b.endDate == null ? null : _day(b.endDate!);
  if (aEnd != bEnd) return false;

  switch (a.frequency) {
    case MilkDeliveryFrequency.daily:
      return true;
    case MilkDeliveryFrequency.alternateDays:
      // Every other day from the start date: the same days only if
      // the start dates are an even number of days apart.
      final apart = _day(a.startDate).difference(_day(b.startDate)).inDays;
      return apart.isEven;
    case MilkDeliveryFrequency.selectedDays:
      final aDays = a.selectedWeekdays.toSet();
      final bDays = b.selectedWeekdays.toSet();
      return aDays.length == bDays.length && aDays.containsAll(bDays);
    case MilkDeliveryFrequency.randomDays:
      final aDates = a.selectedRandomDates.map(_day).toSet();
      final bDates = b.selectedRandomDates.map(_day).toSet();
      return aDates.length == bDates.length && aDates.containsAll(bDates);
  }
}
