import 'package:flutter/material.dart';

import '../../models/milk_plan_merge.dart';
import '../../models/milk_subscription.dart';

const _green = Color(0xFF82B440);

/// "1 L", "1.5 L", "0.5 L".
String litresText(int ml) {
  final litres = ml / 1000;
  return litres == litres.roundToDouble()
      ? '${litres.toStringAsFixed(0)} L'
      : '${litres.toStringAsFixed(1)} L';
}

String shiftText(MilkDeliveryShift shift) => switch (shift) {
  MilkDeliveryShift.earlyMorning => 'Early morning',
  MilkDeliveryShift.morning => 'Morning',
  MilkDeliveryShift.evening => 'Evening',
};

IconData shiftIcon(MilkDeliveryShift shift) => switch (shift) {
  MilkDeliveryShift.earlyMorning => Icons.bedtime_outlined,
  MilkDeliveryShift.morning => Icons.wb_sunny_outlined,
  MilkDeliveryShift.evening => Icons.nights_stay_outlined,
};

/// When changes to a shift's delivery close.
String shiftDeadlineText(MilkDeliveryShift shift) => switch (shift) {
  MilkDeliveryShift.earlyMorning => 'Changes close at 9 PM the evening before.',
  MilkDeliveryShift.morning => 'Changes close at 6 AM that morning.',
  MilkDeliveryShift.evening => 'Changes close at 6 PM that evening.',
};

/// "every day", "on alternate days", "on Mon, Thu", ...
String deliveryDaysText(MilkShiftSchedule schedule) {
  switch (schedule.frequency) {
    case MilkDeliveryFrequency.daily:
      return 'every day';
    case MilkDeliveryFrequency.alternateDays:
      return 'on alternate days';
    case MilkDeliveryFrequency.selectedDays:
      const names = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
      final days = schedule.selectedWeekdays.toList()..sort();
      return 'on ${days.map((d) => names[d - 1]).join(', ')}';
    case MilkDeliveryFrequency.randomDays:
      return 'on selected dates';
  }
}

String milkName(String productId) =>
    productId == 'buffalo_milk' ? 'Buffalo Milk' : 'Cow Milk';

/// One line per shift explaining what happens to it.
List<String> mergeLines(MilkPlanChanges changes) => [
  for (final outcome in changes.shifts) _line(outcome),
];

String _line(ShiftMergeOutcome outcome) {
  final shift = shiftText(outcome.shift);
  final days = deliveryDaysText(outcome.schedule);
  final otherDays = outcome.otherSchedule == null
      ? ''
      : deliveryDaysText(outcome.otherSchedule!);

  switch (outcome.kind) {
    case ShiftMergeKind.newPlan:
      return '$shift: ${litresText(outcome.addedMl)} $days, as a separate plan';
    case ShiftMergeKind.addQuantity:
      return '$shift: ${litresText(outcome.existingMl)} → '
          '${litresText(outcome.resultMl)} $days';
    case ShiftMergeKind.differentSchedule:
      return '$shift: one delivery is $days, the other $otherDays. '
          'One shift has one schedule, so they cannot be added together.';
    case ShiftMergeKind.overLimit:
      return '$shift: ${litresText(outcome.existingMl)} + '
          '${litresText(outcome.addedMl)} is more than the '
          '${litresText(maximumShiftQuantityMl)} limit per delivery.';
    case ShiftMergeKind.differentStatus:
      return '$shift: one plan is paused and the other is active.';
  }
}

enum AddToPlanChoice { add, edit, cancel }

/// Asks before merging a new plan's deliveries into the plan that
/// already delivers that milk in that shift (or, if that is not
/// possible, offers to edit that plan).
Future<AddToPlanChoice> showAddToPlanDialog(
  BuildContext context, {
  required MilkPlanChanges changes,
}) async {
  final name = milkName(changes.productId);
  final pausedShifts = [
    for (final outcome in changes.shifts)
      if (outcome.kind == ShiftMergeKind.addQuantity &&
          outcome.target?.status == MilkSubscriptionStatus.paused)
        shiftText(outcome.shift).toLowerCase(),
  ];

  final choice = await showDialog<AddToPlanChoice>(
    context: context,
    builder: (context) => AlertDialog(
      key: const Key('addToPlanDialog'),
      title: Text('You already get $name'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              changes.isPossible
                  ? 'Each shift has one $name plan, so this is added to '
                        'your existing delivery:'
                  : 'This cannot be added to your existing delivery:',
            ),
            const SizedBox(height: 12),
            for (final line in mergeLines(changes))
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Text(
                  '• $line',
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
              ),
            const SizedBox(height: 4),
            Text(
              changes.isPossible
                  ? 'The new quantity starts with your next delivery.'
                        '${pausedShifts.isEmpty ? '' : ' Your ${pausedShifts.join(' and ')} '
                                  'plan is paused and stays paused until you resume it.'}'
                  : 'You can edit that plan to change its quantity or '
                        'delivery days.',
              style: const TextStyle(color: Colors.black54),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(AddToPlanChoice.cancel),
          child: const Text('Cancel'),
        ),
        FilledButton(
          key: const Key('addToPlanConfirm'),
          style: FilledButton.styleFrom(backgroundColor: _green),
          onPressed: () => Navigator.of(context).pop(
            changes.isPossible ? AddToPlanChoice.add : AddToPlanChoice.edit,
          ),
          child: Text(changes.isPossible ? 'Add to my plan' : 'Edit my plan'),
        ),
      ],
    ),
  );
  return choice ?? AddToPlanChoice.cancel;
}
