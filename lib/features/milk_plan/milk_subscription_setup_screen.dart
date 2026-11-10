import 'package:flutter/material.dart';

import '../../app/sudhamrtam_app.dart';
import '../../models/milk_subscription.dart';
import '../../services/milk_plan_api_client.dart';
import '../../models/milk_plan_merge.dart';
import 'milk_plan_merge_dialog.dart';

const _brandGreen = Color(0xFF82B440);

class _ShiftDraft {
  bool enabled;
  int quantityMl;
  MilkDeliveryFrequency frequency;
  final Set<int> weekdays;
  final Set<DateTime> randomDates;
  DateTime startDate;
  DateTime? endDate;

  _ShiftDraft({
    this.enabled = false,
    this.quantityMl = 500,
    this.frequency = MilkDeliveryFrequency.daily,
    Set<int>? weekdays,
    Set<DateTime>? randomDates,
    DateTime? startDate,
    this.endDate,
  }) : weekdays = weekdays ?? <int>{},
       randomDates = randomDates ?? <DateTime>{},
       startDate = startDate ?? DateUtils.dateOnly(DateTime.now());

  factory _ShiftDraft.fromSchedule(MilkShiftSchedule schedule) {
    return _ShiftDraft(
      enabled: true,
      quantityMl: schedule.quantityMl,
      frequency: schedule.frequency,
      weekdays: schedule.selectedWeekdays.toSet(),
      randomDates: schedule.selectedRandomDates.map(DateUtils.dateOnly).toSet(),
      startDate: DateUtils.dateOnly(schedule.startDate),
      endDate: schedule.endDate,
    );
  }

  MilkShiftSchedule toSchedule(MilkDeliveryShift shift) {
    final days = weekdays.toList()..sort();
    final dates = randomDates.toList()..sort();
    final start = frequency == MilkDeliveryFrequency.randomDays
        ? dates.first
        : startDate;
    return MilkShiftSchedule(
      shift: shift,
      quantityMl: quantityMl,
      frequency: frequency,
      selectedWeekdays: frequency == MilkDeliveryFrequency.selectedDays
          ? days
          : <int>[],
      selectedRandomDates: frequency == MilkDeliveryFrequency.randomDays
          ? dates
          : <DateTime>[],
      startDate: start,
      endDate: endDate,
    );
  }
}

class MilkSubscriptionSetupScreen extends StatefulWidget {
  final String productName;
  final MilkSubscription? existingSubscription;

  const MilkSubscriptionSetupScreen({
    super.key,
    required this.productName,
    this.existingSubscription,
  });

  @override
  State<MilkSubscriptionSetupScreen> createState() =>
      _MilkSubscriptionSetupScreenState();
}

class _MilkSubscriptionSetupScreenState
    extends State<MilkSubscriptionSetupScreen> {
  late _ShiftDraft _earlyMorning;
  late _ShiftDraft _morning;
  late _ShiftDraft _evening;
  bool _isSaving = false;

  /// Each shift's draft, in delivery order.
  Map<MilkDeliveryShift, _ShiftDraft> get _drafts => {
    MilkDeliveryShift.earlyMorning: _earlyMorning,
    MilkDeliveryShift.morning: _morning,
    MilkDeliveryShift.evening: _evening,
  };

  bool get _isEditing => widget.existingSubscription != null;

  @override
  void initState() {
    super.initState();
    _earlyMorning = _ShiftDraft();
    _morning = _ShiftDraft(enabled: true, quantityMl: 1000);
    _evening = _ShiftDraft();

    final existing = widget.existingSubscription;
    if (existing == null) return;

    if (existing.shiftSchedules.isNotEmpty) {
      final earlySchedule = existing.scheduleFor(
        MilkDeliveryShift.earlyMorning,
      );
      _earlyMorning = earlySchedule == null
          ? _ShiftDraft()
          : _ShiftDraft.fromSchedule(earlySchedule);
      final morningSchedule = existing.scheduleFor(MilkDeliveryShift.morning);
      final eveningSchedule = existing.scheduleFor(MilkDeliveryShift.evening);
      _morning = morningSchedule == null
          ? _ShiftDraft()
          : _ShiftDraft.fromSchedule(morningSchedule);
      _evening = eveningSchedule == null
          ? _ShiftDraft()
          : _ShiftDraft.fromSchedule(eveningSchedule);
    } else {
      // Migration of plans created before morning/evening support.
      // The old quantity represented units; treat one unit as 1 litre.
      _morning = _ShiftDraft(
        enabled: true,
        quantityMl: existing.quantity * 1000,
        frequency: existing.frequency,
        weekdays: existing.selectedWeekdays.toSet(),
        randomDates: existing.selectedRandomDates
            .map(DateUtils.dateOnly)
            .toSet(),
        startDate: DateUtils.dateOnly(existing.startDate),
        endDate: existing.endDate,
      );
      _evening = _ShiftDraft();
    }
  }

  String _quantityLabel(int ml) {
    if (ml % 1000 == 0) return '${ml ~/ 1000} L';
    return '${(ml / 1000).toStringAsFixed(1)} L';
  }

  Future<void> _pickDate(_ShiftDraft draft) async {
    final today = DateUtils.dateOnly(DateTime.now());
    final picked = await showDatePicker(
      context: context,
      initialDate: today,
      firstDate: today,
      lastDate: today.add(const Duration(days: 365)),
      helpText: 'Select Milk Delivery Date',
    );
    if (!mounted || picked == null) return;
    setState(() => draft.randomDates.add(DateUtils.dateOnly(picked)));
  }

  void _showError(String message) {
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
  }

  bool _validateDraft(_ShiftDraft draft, String shiftName) {
    if (!draft.enabled) return true;
    if (draft.quantityMl < 500 ||
        draft.quantityMl > 10000 ||
        draft.quantityMl % 500 != 0) {
      _showError('$shiftName quantity must be between 0.5 L and 10 L.');
      return false;
    }
    if (draft.frequency == MilkDeliveryFrequency.selectedDays &&
        draft.weekdays.isEmpty) {
      _showError('Select at least one $shiftName delivery weekday.');
      return false;
    }
    if (draft.frequency == MilkDeliveryFrequency.randomDays) {
      if (draft.randomDates.isEmpty) {
        _showError('Select at least one $shiftName delivery date.');
        return false;
      }
      final today = DateUtils.dateOnly(DateTime.now());
      if (draft.randomDates.any((date) => date.isBefore(today))) {
        _showError('Remove past $shiftName delivery dates before saving.');
        return false;
      }
    }
    if (draft.endDate != null && draft.endDate!.isBefore(draft.startDate)) {
      _showError('$shiftName end date cannot precede start date.');
      return false;
    }
    return true;
  }

  Future<void> _saveMilkSubscription() async {
    if (_isSaving) return;

    if (!_drafts.values.any((draft) => draft.enabled)) {
      _showError('Choose at least one delivery time.');
      return;
    }
    for (final MapEntry(key: shift, value: draft) in _drafts.entries) {
      if (!_validateDraft(draft, shiftText(shift))) return;
    }

    // A disabled Save button also prevents duplicate requests.
    setState(() => _isSaving = true);

    try {
      final existing = widget.existingSubscription;
      final productId =
          existing?.productId ??
          (widget.productName == 'Buffalo Milk' ? 'buffalo_milk' : 'cow_milk');

      final schedules = <MilkShiftSchedule>[
        for (final MapEntry(key: shift, value: draft) in _drafts.entries)
          if (draft.enabled) draft.toSchedule(shift),
      ];

      // Maintain the legacy fields while the remaining screens migrate.
      final legacyStart = schedules
          .map((schedule) => schedule.startDate)
          .reduce((a, b) => a.isBefore(b) ? a : b);

      // One plan per milk and shift: a shift that another plan
      // already delivers is added to that plan (after asking).
      if (existing == null) {
        final changes = sudhamrtamMilkSubscriptions.checkNewPlan(
          MilkSubscription(
            id: DateTime.now().microsecondsSinceEpoch.toString(),
            productId: productId,
            shiftSchedules: schedules,
            quantity: 1,
            frequency: MilkDeliveryFrequency.daily,
            startDate: legacyStart,
          ),
        );
        if (changes.mergesIntoExisting) {
          await _offerAddToPlan(changes);
          return;
        }
      } else {
        // An edit may not add a shift another plan already has.
        final shared = sudhamrtamMilkSubscriptions
            .sharedShifts(existing.copyWith(shiftSchedules: schedules))
            .difference(sudhamrtamMilkSubscriptions.sharedShifts(existing));
        if (shared.isNotEmpty) {
          final names = shared.map(shiftText).join(' and ');
          _showError(
            'Another ${milkName(productId)} plan already has your '
            '${names.toLowerCase()} delivery. Change the quantity in that '
            'plan instead.',
          );
          return;
        }
      }

      bool saved;
      if (existing != null) {
        saved = await sudhamrtamMilkSubscriptions.updateSubscription(
          existing.copyWith(
            shiftSchedules: schedules,
            quantity: 1,
            frequency: MilkDeliveryFrequency.daily,
            selectedWeekdays: <int>[],
            selectedRandomDates: <DateTime>[],
            startDate: legacyStart,
          ),
        );
      } else {
        final subscription = MilkSubscription(
          id: DateTime.now().microsecondsSinceEpoch.toString(),
          productId: productId,
          shiftSchedules: schedules,
          quantity: 1,
          frequency: MilkDeliveryFrequency.daily,
          startDate: legacyStart,
        );
        saved = await sudhamrtamMilkSubscriptions.addSubscription(subscription);
      }

      if (!mounted) return;
      if (!saved) {
        _showError(
          'Subscription was not saved. Please check your plan and retry.',
        );
        return;
      }

      final messenger = ScaffoldMessenger.of(context);
      Navigator.of(context).pop();
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            existing != null
                ? 'Milk subscription updated successfully!'
                : 'Milk subscription saved successfully!',
          ),
        ),
      );
    } catch (error, stackTrace) {
      debugPrint('Milk subscription save error: $error');
      debugPrintStack(stackTrace: stackTrace);
      if (mounted) {
        _showError(
          error is MilkPlanSyncException
              ? error.message
              : 'Unable to save subscription. Please try again.',
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isSaving = false);
      }
    }
  }

  Future<void> _offerAddToPlan(MilkPlanChanges changes) async {
    final choice = await showAddToPlanDialog(context, changes: changes);
    if (!mounted) return;

    switch (choice) {
      case AddToPlanChoice.cancel:
        return;
      case AddToPlanChoice.edit:
        final plan = changes.blockingPlan;
        if (plan == null) return;
        await Navigator.of(context).pushReplacement(
          MaterialPageRoute<void>(
            builder: (context) => MilkSubscriptionSetupScreen(
              productName: widget.productName,
              existingSubscription: plan,
            ),
          ),
        );
        return;
      case AddToPlanChoice.add:
        final bool saved;
        try {
          saved = await sudhamrtamMilkSubscriptions.saveNewPlan(changes);
        } on MilkPlanSyncException catch (error) {
          if (mounted) _showError(error.message);
          return;
        }
        if (!mounted) return;
        if (!saved) {
          _showError('Your plan was not updated. Please try again.');
          return;
        }
        final messenger = ScaffoldMessenger.of(context);
        Navigator.of(context).pop();
        messenger.showSnackBar(
          SnackBar(
            content: Text('Added to your ${milkName(changes.productId)} plan.'),
          ),
        );
    }
  }

  Widget _shiftCard(MilkDeliveryShift shift, _ShiftDraft draft) {
    final title = shiftText(shift);
    const weekdays = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
    final dates = draft.randomDates.toList()..sort();

    return Card(
      margin: const EdgeInsets.only(bottom: 18),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SwitchListTile(
              key: Key('shift-${shift.name}'),
              contentPadding: EdgeInsets.zero,
              secondary: Icon(shiftIcon(shift), color: _brandGreen),
              title: Text(
                '$title Delivery',
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
              subtitle: Text(
                [
                  if (shift == MilkDeliveryShift.earlyMorning)
                    'Last evening\'s milk, kept cold overnight.',
                  draft.enabled ? 'Enabled' : 'Not selected',
                ].join('\n'),
              ),
              value: draft.enabled,
              activeTrackColor: const Color(0xFFE5F0D7),
              activeThumbColor: _brandGreen,
              onChanged: (enabled) => setState(() => draft.enabled = enabled),
            ),
            if (draft.enabled) ...[
              Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Text(
                  shiftDeadlineText(shift),
                  style: const TextStyle(fontSize: 12, color: Colors.black54),
                ),
              ),
              const Divider(),
              const SizedBox(height: 12),
              const Text(
                'Quantity per delivery',
                style: TextStyle(fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  IconButton.filledTonal(
                    onPressed: draft.quantityMl > 500
                        ? () => setState(() => draft.quantityMl -= 500)
                        : null,
                    icon: const Icon(Icons.remove),
                  ),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 20),
                    child: Text(
                      _quantityLabel(draft.quantityMl),
                      style: const TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  IconButton.filledTonal(
                    onPressed: draft.quantityMl < 10000
                        ? () => setState(() => draft.quantityMl += 500)
                        : null,
                    icon: const Icon(Icons.add),
                  ),
                ],
              ),
              const SizedBox(height: 18),
              const Text(
                'Delivery frequency',
                style: TextStyle(fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 8),
              DropdownButtonFormField<MilkDeliveryFrequency>(
                key: ValueKey('$title-${draft.frequency.name}'),
                initialValue: draft.frequency,
                decoration: const InputDecoration(border: OutlineInputBorder()),
                items: const [
                  DropdownMenuItem(
                    value: MilkDeliveryFrequency.daily,
                    child: Text('Daily Delivery'),
                  ),
                  DropdownMenuItem(
                    value: MilkDeliveryFrequency.alternateDays,
                    child: Text('Alternate Days'),
                  ),
                  DropdownMenuItem(
                    value: MilkDeliveryFrequency.selectedDays,
                    child: Text('Selected Days'),
                  ),
                  DropdownMenuItem(
                    value: MilkDeliveryFrequency.randomDays,
                    child: Text('Random Days'),
                  ),
                ],
                onChanged: (value) {
                  if (value != null) {
                    setState(() => draft.frequency = value);
                  }
                },
              ),
              if (draft.frequency == MilkDeliveryFrequency.selectedDays) ...[
                const SizedBox(height: 18),
                const Text('Choose weekdays'),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: List.generate(7, (index) {
                    final day = index + 1;
                    return FilterChip(
                      label: Text(weekdays[index]),
                      selected: draft.weekdays.contains(day),
                      selectedColor: const Color(0xFFE5F0D7),
                      onSelected: (selected) => setState(() {
                        if (selected) {
                          draft.weekdays.add(day);
                        } else {
                          draft.weekdays.remove(day);
                        }
                      }),
                    );
                  }),
                ),
              ],
              if (draft.frequency == MilkDeliveryFrequency.randomDays) ...[
                const SizedBox(height: 18),
                OutlinedButton.icon(
                  onPressed: () => _pickDate(draft),
                  icon: const Icon(Icons.calendar_month_outlined),
                  label: const Text('Add Delivery Date'),
                ),
                const SizedBox(height: 8),
                if (dates.isEmpty)
                  const Text(
                    'No delivery dates selected.',
                    style: TextStyle(color: Colors.black54),
                  ),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: dates.map((date) {
                    return InputChip(
                      label: Text('${date.day}/${date.month}/${date.year}'),
                      onDeleted: () =>
                          setState(() => draft.randomDates.remove(date)),
                    );
                  }).toList(),
                ),
              ],
            ],
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final totalMl = _drafts.values
        .where((draft) => draft.enabled)
        .fold<int>(0, (sum, draft) => sum + draft.quantityMl);
    return Scaffold(
      appBar: AppBar(
        title: Text(
          _isEditing ? 'Edit Milk Subscription' : 'Set Up Milk Subscription',
        ),
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: const Color(0xFFF5F8F0),
                borderRadius: BorderRadius.circular(16),
              ),
              child: Column(
                children: [
                  const Icon(
                    Icons.water_drop_outlined,
                    size: 56,
                    color: _brandGreen,
                  ),
                  const SizedBox(height: 10),
                  Text(
                    widget.productName,
                    style: Theme.of(context).textTheme.headlineSmall
                        ?.copyWith(fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'Choose Early morning, Morning, Evening, or more than one.',
                    textAlign: TextAlign.center,
                  ),
                  if (_isEditing) ...[
                    const SizedBox(height: 12),
                    const Chip(label: Text('Editing Existing Plan')),
                  ],
                ],
              ),
            ),
            const SizedBox(height: 24),
            for (final MapEntry(key: shift, value: draft) in _drafts.entries)
              _shiftCard(shift, draft),
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: const Color(0xFFF5F8F0),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Combined quantity when all chosen shifts deliver',
                    style: TextStyle(color: Colors.black54),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    _quantityLabel(totalMl),
                    style: const TextStyle(
                      fontSize: 22,
                      color: _brandGreen,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 4),
                  const Text(
                    'Actual daily quantity depends on each shift schedule.',
                    style: TextStyle(fontSize: 12, color: Colors.black54),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),
            FilledButton.icon(
              onPressed: _isSaving ? null : _saveMilkSubscription,
              icon: Icon(
                _isEditing ? Icons.save_outlined : Icons.check_circle_outline,
              ),
              label: Text(
                _isSaving
                    ? 'Saving...'
                    : (_isEditing ? 'Save Changes' : 'Save Milk Subscription'),
              ),
              style: FilledButton.styleFrom(
                backgroundColor: _brandGreen,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 16),
              ),
            ),
            const SizedBox(height: 24),
            const Center(
              child: Text(
                'Pure • Natural • Delivered Fresh',
                style: TextStyle(fontWeight: FontWeight.w600),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
