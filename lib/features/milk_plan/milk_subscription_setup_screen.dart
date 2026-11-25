import 'package:flutter/material.dart';

import '../../core/widgets/site_layout.dart';

import '../../app/sudhamrtam_app.dart';
import '../account/address_location_gate.dart';
import '../../models/milk_subscription.dart';
import '../../services/milk_plan_api_client.dart';
import '../../models/milk_plan_merge.dart';
import '../../models/subscription_products.dart';
import 'milk_plan_merge_dialog.dart';
import '../../core/widgets/page_app_bar.dart';

const _brandGreen = Color(0xFF82B440);

class _ShiftDraft {
  bool enabled;
  int quantityMl;
  MilkDeliveryFrequency frequency;
  final Set<int> weekdays;
  final Set<DateTime> randomDates;
  DateTime startDate;
  DateTime? endDate;

  /// A running plan's quantity and frequency: still allowed after the
  /// owner changes the product's settings.
  int? originalQuantity;
  MilkDeliveryFrequency? originalFrequency;

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
        randomDates: schedule.selectedRandomDates
            .map(DateUtils.dateOnly)
            .toSet(),
        startDate: DateUtils.dateOnly(schedule.startDate),
        endDate: schedule.endDate,
      )
      ..originalQuantity = schedule.quantityMl
      ..originalFrequency = schedule.frequency;
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
  /// The product to subscribe to (owner request 2026-11-25: any
  /// subscription product). Older callers name a milk instead.
  final String? productId;
  final String? productName;
  final MilkSubscription? existingSubscription;

  /// Before a new plan: the milk's address must be on the map.
  final MilkAddressCheck checkAddress;

  const MilkSubscriptionSetupScreen({
    super.key,
    this.productId,
    this.productName,
    this.existingSubscription,
    this.checkAddress = checkMilkAddressLocation,
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

  /// Try for 7 days (owner request 2026-11-25): a new subscription
  /// that stops by itself after a week.
  bool _trial = false;

  /// Try for 7 days is for new customers only (owner decision
  /// 2026-11-26): none who has or had a subscription, waiting ones
  /// included; a rejected one does not count.
  bool get _canTry =>
      !_isEditing &&
      !sudhamrtamMilkSubscriptions.subscriptions.any((s) => !s.isRejected);

  /// The product and its settings.
  late final SubscriptionOffer _offer;

  bool get _isMilk => !_offer.isPack;

  /// Each shift's draft, in delivery order.
  Map<MilkDeliveryShift, _ShiftDraft> get _drafts => {
    MilkDeliveryShift.earlyMorning: _earlyMorning,
    MilkDeliveryShift.morning: _morning,
    MilkDeliveryShift.evening: _evening,
  };

  bool get _isEditing => widget.existingSubscription != null;

  /// The shifts to show: the product's, plus any a running plan has.
  List<MilkDeliveryShift> get _shifts => [
    for (final shift in MilkDeliveryShift.values)
      if (_offer.shifts.contains(shift) ||
          widget.existingSubscription?.scheduleFor(shift) != null)
        shift,
  ];

  static SubscriptionOffer _resolveOffer(MilkSubscriptionSetupScreen w) {
    final id =
        w.productId ??
        w.existingSubscription?.productId ??
        (w.productName == 'Buffalo Milk' ? 'buffalo_milk' : 'cow_milk');
    return sudhamrtamSubscriptionProducts.offerFor(id) ??
        SubscriptionOffer(
          productId: id,
          name: sudhamrtamSubscriptionProducts.nameOf(id),
          unitLabel: '',
          measure: SubscriptionMeasure.pack,
          quantities: const [1],
          shifts: MilkDeliveryShift.values,
          weekdays: const [1, 2, 3, 4, 5, 6, 7],
        );
  }

  /// A new draft for this product: its smallest quantity (milk: 0.5 L,
  /// or 1 L in the morning), on the days it comes.
  _ShiftDraft _newDraft({bool enabled = false, int? quantity}) {
    final first = _offer.quantities.first;
    return _ShiftDraft(
      enabled: enabled,
      quantityMl: quantity != null && _offer.quantities.contains(quantity)
          ? quantity
          : first,
      frequency: _offer.comesEveryDay
          ? MilkDeliveryFrequency.daily
          : MilkDeliveryFrequency.selectedDays,
      weekdays: _offer.comesEveryDay ? null : _offer.weekdays.toSet(),
    );
  }

  @override
  void initState() {
    super.initState();
    _offer = _resolveOffer(widget);
    // Milk starts with 1 L in the morning, as before; other products
    // with their first delivery time.
    final firstShift = _offer.shifts.contains(MilkDeliveryShift.morning)
        ? MilkDeliveryShift.morning
        : (_offer.shifts.isEmpty
              ? MilkDeliveryShift.morning
              : _offer.shifts.first);
    _earlyMorning = _newDraft(
      enabled: firstShift == MilkDeliveryShift.earlyMorning,
    );
    _morning = _newDraft(
      enabled: firstShift == MilkDeliveryShift.morning,
      quantity: 1000,
    );
    _evening = _newDraft(enabled: firstShift == MilkDeliveryShift.evening);

    final existing = widget.existingSubscription;
    if (existing == null) return;

    if (existing.shiftSchedules.isNotEmpty) {
      final earlySchedule = existing.scheduleFor(
        MilkDeliveryShift.earlyMorning,
      );
      _earlyMorning = earlySchedule == null
          ? _newDraft()
          : _ShiftDraft.fromSchedule(earlySchedule);
      final morningSchedule = existing.scheduleFor(MilkDeliveryShift.morning);
      final eveningSchedule = existing.scheduleFor(MilkDeliveryShift.evening);
      _morning = morningSchedule == null
          ? _newDraft()
          : _ShiftDraft.fromSchedule(morningSchedule);
      _evening = eveningSchedule == null
          ? _newDraft()
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
      _evening = _newDraft();
    }
  }

  String _quantityLabel(int quantity) => _offer.quantityText(quantity);

  /// Subscribe & save (owner decision 2026-11-25): "₹108 a pack when
  /// you subscribe (₹120 in the shop) · Save 10%". Null without a
  /// saving or a known price.
  String? _priceLine() {
    if (_offer.saveBp <= 0) return null;
    final product = sudhamrtamCatalog.productById(_offer.productId);
    if (product == null || product.price <= 0) return null;
    final shop = (product.price * 100).round();
    final saved = _offer.savedPricePaise(shop);
    String rupees(int paise) => paise % 100 == 0
        ? '₹${paise ~/ 100}'
        : '₹${(paise / 100).toStringAsFixed(2)}';
    final per = _offer.isPack ? 'a pack' : 'a litre';
    return '${rupees(saved)} $per when you subscribe '
        '(${rupees(shop)} in the shop) · Save ${_offer.savePercent}';
  }

  /// The quantities [draft] may have: the product's, plus what the
  /// running plan already has.
  List<int> _quantitiesFor(_ShiftDraft draft) {
    final all = {
      ..._offer.quantities,
      if (draft.originalQuantity != null) draft.originalQuantity!,
    }.toList()..sort();
    return all;
  }

  int? _nextQuantity(_ShiftDraft draft) {
    for (final q in _quantitiesFor(draft)) {
      if (q > draft.quantityMl) return q;
    }
    return null;
  }

  int? _previousQuantity(_ShiftDraft draft) {
    int? previous;
    for (final q in _quantitiesFor(draft)) {
      if (q >= draft.quantityMl) break;
      previous = q;
    }
    return previous;
  }

  /// The frequencies [draft] may use: on some days only, a product
  /// comes on selected or random days (a running plan keeps its own).
  List<MilkDeliveryFrequency> _frequenciesFor(_ShiftDraft draft) => [
    for (final f in MilkDeliveryFrequency.values)
      if (_offer.comesEveryDay ||
          f == MilkDeliveryFrequency.selectedDays ||
          f == MilkDeliveryFrequency.randomDays ||
          f == draft.originalFrequency)
        f,
  ];

  bool _dayAllowed(DateTime day) => _offer.weekdays.contains(day.weekday);

  /// "Mon, Wed and Fri".
  String get _offerDaysText {
    const names = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
    final days = [for (final d in _offer.weekdays) names[d - 1]];
    if (days.length == 1) return days.single;
    return '${days.sublist(0, days.length - 1).join(', ')} and ${days.last}';
  }

  Future<void> _pickDate(_ShiftDraft draft) async {
    final today = DateUtils.dateOnly(DateTime.now());
    var initial = today;
    while (!_offer.comesEveryDay && !_dayAllowed(initial)) {
      initial = initial.add(const Duration(days: 1));
    }
    final picked = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: today,
      lastDate: today.add(const Duration(days: 365)),
      selectableDayPredicate: _offer.comesEveryDay ? null : _dayAllowed,
      helpText: _isMilk ? 'Select Milk Delivery Date' : 'Select Delivery Date',
    );
    if (!mounted || picked == null) return;
    setState(() => draft.randomDates.add(DateUtils.dateOnly(picked)));
  }

  /// The customer chooses when milk starts (owner request 2026-11-15).
  Future<void> _pickStart(_ShiftDraft draft) async {
    final today = DateUtils.dateOnly(DateTime.now());
    final picked = await showDatePicker(
      context: context,
      initialDate: draft.startDate.isBefore(today) ? today : draft.startDate,
      firstDate: today,
      lastDate: today.add(const Duration(days: 90)),
      helpText: _isMilk ? 'Milk starts on' : 'Starts on',
    );
    if (!mounted || picked == null) return;
    setState(() => draft.startDate = DateUtils.dateOnly(picked));
  }

  void _showError(String message) {
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
  }

  bool _validateDraft(_ShiftDraft draft, String shiftName) {
    if (!draft.enabled) return true;
    if (!_quantitiesFor(draft).contains(draft.quantityMl)) {
      _showError(
        _isMilk && isMilkProductId(_offer.productId)
            ? '$shiftName quantity must be between 0.5 L and 10 L '
                  '(whole litres plus 0.5 or 0.75 L).'
            : 'Choose a $shiftName quantity offered for ${_offer.name}.',
      );
      return false;
    }
    if (!_frequenciesFor(draft).contains(draft.frequency)) {
      _showError('${_offer.name} comes on $_offerDaysText only.');
      return false;
    }
    if (draft.frequency == MilkDeliveryFrequency.selectedDays &&
        draft.originalFrequency != MilkDeliveryFrequency.selectedDays &&
        draft.weekdays.any((d) => !_offer.weekdays.contains(d))) {
      _showError('${_offer.name} comes on $_offerDaysText only.');
      return false;
    }
    if (_trial && draft.frequency == MilkDeliveryFrequency.randomDays) {
      _showError(
        'Try for 7 days works with daily, alternate or selected days. '
        'Choose one of those for $shiftName.',
      );
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

    // Shifts the product does not have are never sent.
    for (final shift in MilkDeliveryShift.values) {
      if (!_shifts.contains(shift)) _drafts[shift]!.enabled = false;
    }
    if (!_drafts.values.any((draft) => draft.enabled)) {
      _showError('Choose at least one delivery time.');
      return;
    }
    for (final MapEntry(key: shift, value: draft) in _drafts.entries) {
      if (!_validateDraft(draft, shiftText(shift))) return;
    }

    // A new plan needs the home marked on the map (owner decision
    // 2026-11-16); a running plan can still be changed.
    if (widget.existingSubscription == null) {
      setState(() => _isSaving = true);
      final ok = await widget.checkAddress(context);
      if (!mounted) return;
      setState(() => _isSaving = false);
      if (!ok) return;
    }

    // A disabled Save button also prevents duplicate requests.
    setState(() => _isSaving = true);

    try {
      final existing = widget.existingSubscription;
      final productId = existing?.productId ?? _offer.productId;

      final schedules = <MilkShiftSchedule>[
        for (final MapEntry(key: shift, value: draft) in _drafts.entries)
          if (draft.enabled)
            // A trial week: the 7th day is the last.
            _trial && existing == null && _canTry
                ? draft
                      .toSchedule(shift)
                      .copyWith(
                        endDate: draft.startDate.add(const Duration(days: 6)),
                      )
                : draft.toSchedule(shift),
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
            'Another ${milkName(productId)} subscription already has your '
            '${names.toLowerCase()} delivery. Change the quantity in that '
            'subscription instead.',
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
          'Subscription was not saved. Please check your subscription and retry.',
        );
        return;
      }

      final messenger = ScaffoldMessenger.of(context);
      Navigator.of(context).pop();
      final what = _isMilk
          ? 'Milk subscription'
          : '${_offer.name} subscription';
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            existing != null
                ? '$what updated successfully!'
                : _trial
                ? '$what saved: 7 days to try. Keep it going any time '
                      'from Subscriptions.'
                : '$what saved successfully!',
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
              productId: plan.productId,
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
          _showError('Your subscription was not updated. Please try again.');
          return;
        }
        final messenger = ScaffoldMessenger.of(context);
        Navigator.of(context).pop();
        messenger.showSnackBar(
          SnackBar(
            content: Text(
              'Added to your ${milkName(changes.productId)} subscription.',
            ),
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
                  if (shift == MilkDeliveryShift.earlyMorning && _isMilk)
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
                    key: Key('$title-less'),
                    onPressed: _previousQuantity(draft) != null
                        ? () => setState(
                            () => draft.quantityMl = _previousQuantity(draft)!,
                          )
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
                    key: Key('$title-more'),
                    onPressed: _nextQuantity(draft) != null
                        ? () => setState(
                            () => draft.quantityMl = _nextQuantity(draft)!,
                          )
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
                items: [
                  for (final f in _frequenciesFor(draft))
                    DropdownMenuItem(
                      value: f,
                      child: Text(switch (f) {
                        MilkDeliveryFrequency.daily => 'Daily Delivery',
                        MilkDeliveryFrequency.alternateDays => 'Alternate Days',
                        MilkDeliveryFrequency.selectedDays => 'Selected Days',
                        MilkDeliveryFrequency.randomDays => 'Random Days',
                      }),
                    ),
                ],
                onChanged: (value) {
                  if (value != null) {
                    setState(() => draft.frequency = value);
                  }
                },
              ),
              if (!_offer.comesEveryDay)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text(
                    '${_offer.name} comes on $_offerDaysText.',
                    key: Key('offer-days-${shift.name}'),
                    style: const TextStyle(fontSize: 12, color: Colors.black54),
                  ),
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
                    if (!_offer.weekdays.contains(day) &&
                        !(draft.originalFrequency ==
                                MilkDeliveryFrequency.selectedDays &&
                            draft.weekdays.contains(day))) {
                      return const SizedBox.shrink();
                    }
                    return FilterChip(
                      key: Key('day-${shift.name}-$day'),
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
              if (draft.frequency != MilkDeliveryFrequency.randomDays)
                _StartDateRow(
                  key: Key('$title-start'),
                  start: draft.startDate,
                  onChange: () => _pickStart(draft),
                ),
              // A running plan that ends (a trial week, or a set end):
              // the customer keeps it going here.
              if (_isEditing &&
                  draft.endDate != null &&
                  draft.frequency != MilkDeliveryFrequency.randomDays)
                _EndDateRow(
                  key: Key('$title-end'),
                  end: draft.endDate!,
                  productEnds: _offer.endsOn,
                  onKeepGoing: () => setState(() => draft.endDate = null),
                ),
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
    final totalMl = [
      for (final shift in _shifts)
        if (_drafts[shift]!.enabled) _drafts[shift]!.quantityMl,
    ].fold<int>(0, (sum, q) => sum + q);
    final shiftNames = _shifts.map(shiftText).toList();
    final shiftsHint = shiftNames.length == 1
        ? '${shiftNames.single} delivery.'
        : 'Choose ${shiftNames.sublist(0, shiftNames.length - 1).join(', ')}'
              ' or ${shiftNames.last}, or more than one.';
    return SiteScaffold(
      appBar: PageAppBar(
        title: Text(
          _isMilk
              ? (_isEditing
                    ? 'Edit Milk Subscription'
                    : 'Set Up Milk Subscription')
              : (_isEditing ? 'Edit Subscription' : 'Set Up Subscription'),
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
                  Icon(
                    _isMilk
                        ? Icons.water_drop_outlined
                        : Icons.shopping_basket_outlined,
                    size: 56,
                    color: _brandGreen,
                  ),
                  const SizedBox(height: 10),
                  Text(
                    _offer.isPack && _offer.unitLabel.isNotEmpty
                        ? '${_offer.name} · ${_offer.unitLabel}'
                        : _offer.name,
                    key: const Key('setup-product'),
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.headlineSmall
                        ?.copyWith(fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 8),
                  if (_priceLine() case final price?) ...[
                    const SizedBox(height: 6),
                    Text(
                      price,
                      key: const Key('setup-price'),
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        color: _brandGreen,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                  const SizedBox(height: 6),
                  Text(shiftsHint, textAlign: TextAlign.center),
                  if (_offer.endsOn != null) ...[
                    const SizedBox(height: 8),
                    Text(
                      '${_offer.name} subscriptions end on '
                      '${MaterialLocalizations.of(context).formatMediumDate(_offer.endsOn!)}.',
                      key: const Key('setup-product-ends'),
                      textAlign: TextAlign.center,
                      style: const TextStyle(color: Color(0xFFB26A00)),
                    ),
                  ],
                  if (_isEditing) ...[
                    const SizedBox(height: 12),
                    const Chip(label: Text('Editing Existing Subscription')),
                  ],
                ],
              ),
            ),
            const SizedBox(height: 24),
            if (_canTry)
              Card(
                margin: const EdgeInsets.only(bottom: 18),
                color: const Color(0xFFFFF8E1),
                child: SwitchListTile(
                  key: const Key('try-7-days'),
                  secondary: const Icon(
                    Icons.local_offer_outlined,
                    color: Color(0xFFB26A00),
                  ),
                  title: const Text(
                    'Try for 7 days',
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                  subtitle: Text(
                    _trial
                        ? 'Deliveries stop by themselves after 7 days. Liked '
                              'it? Tap "Keep it going" in Subscriptions.'
                        : 'Not sure yet? Get one week, then decide.',
                  ),
                  value: _trial,
                  activeThumbColor: const Color(0xFFB26A00),
                  onChanged: (on) => setState(() => _trial = on),
                ),
              ),
            for (final shift in _shifts) _shiftCard(shift, _drafts[shift]!),
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
                    totalMl == 0 ? '-' : _quantityLabel(totalMl),
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
                    : (_isEditing
                          ? 'Save Changes'
                          : _isMilk
                          ? 'Save Milk Subscription'
                          : 'Save Subscription'),
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

/// "Starts on Mon, 16 Nov 2026 [Change]". A plan already running
/// shows when it started; that cannot be changed here.
class _StartDateRow extends StatelessWidget {
  const _StartDateRow({super.key, required this.start, required this.onChange});

  final DateTime start;
  final VoidCallback onChange;

  @override
  Widget build(BuildContext context) {
    final today = DateUtils.dateOnly(DateTime.now());
    final started = start.isBefore(today);
    final label = MaterialLocalizations.of(context).formatFullDate(start);
    return Padding(
      padding: const EdgeInsets.only(top: 18),
      child: Row(
        children: [
          const Icon(Icons.event_outlined),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  started ? 'Started on' : 'Starts on',
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
                Text(label),
                if (!started)
                  const Text(
                    'Choose a later day to start later. '
                    'Lists already fixed are not changed.',
                    style: TextStyle(fontSize: 12, color: Colors.black54),
                  ),
              ],
            ),
          ),
          if (!started)
            TextButton(onPressed: onChange, child: const Text('Change')),
        ],
      ),
    );
  }
}

/// "Ends on Sat, 14 Nov 2026 [Keep it going]": a trial week or a set
/// end. Keep it going removes the end (not past a product's own end).
class _EndDateRow extends StatelessWidget {
  const _EndDateRow({
    super.key,
    required this.end,
    required this.productEnds,
    required this.onKeepGoing,
  });

  final DateTime end;
  final DateTime? productEnds;
  final VoidCallback onKeepGoing;

  @override
  Widget build(BuildContext context) {
    final label = MaterialLocalizations.of(context).formatFullDate(end);
    final fixed = productEnds != null && !end.isBefore(productEnds!);
    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: Row(
        children: [
          const Icon(Icons.event_busy_outlined),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Last delivery',
                  style: TextStyle(fontWeight: FontWeight.w600),
                ),
                Text(label),
                if (fixed)
                  const Text(
                    'This product is no longer offered after that day.',
                    style: TextStyle(fontSize: 12, color: Colors.black54),
                  ),
              ],
            ),
          ),
          if (!fixed)
            TextButton(
              key: const Key('keep-going'),
              onPressed: onKeepGoing,
              child: const Text('Keep it going'),
            ),
        ],
      ),
    );
  }
}
