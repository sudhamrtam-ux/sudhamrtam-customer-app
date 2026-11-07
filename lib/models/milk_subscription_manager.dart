import 'package:flutter/foundation.dart';

import 'milk_plan_merge.dart';
import 'milk_subscription.dart';
import '../database/milk_subscription_repository.dart';

/// Plans of the same milk that deliver in the same shift (made
/// before deliveries were merged automatically).
class DuplicateMilkPlans {
  final String productId;

  /// The plans involved, oldest first.
  final List<MilkSubscription> plans;

  /// How they merge; `changes.isPossible` is false if they can't.
  final MilkPlanChanges changes;

  const DuplicateMilkPlans(this.productId, this.plans, this.changes);

  bool get canCombine => changes.isPossible;
}

class MilkSubscriptionManager extends ChangeNotifier {
  final List<MilkSubscription> _subscriptions = [];
  final MilkSubscriptionRepository _repository = MilkSubscriptionRepository();
  bool _isWriting = false;

  bool get isWriting => _isWriting;

  /// Restores subscriptions that were previously saved in SQLite.
  ///
  /// Call this once during application startup, before runApp().
  /// Loading is refused if this manager already contains subscriptions,
  /// to avoid overwriting unsaved in-memory changes.
  Future<void> loadSavedSubscriptions(
    List<MilkSubscription> savedSubscriptions,
  ) async {
    if (_subscriptions.isNotEmpty) {
      throw StateError(
        'Cannot load saved subscriptions into a non-empty manager.',
      );
    }

    final ids = <String>{};

    for (final subscription in savedSubscriptions) {
      if (!ids.add(subscription.id) || !_isValidSubscription(subscription)) {
        throw StateError(
          'Invalid or duplicate saved subscription: ${subscription.id}',
        );
      }
    }

    _subscriptions.addAll(savedSubscriptions.map(_copyWithScheduleSnapshots));

    notifyListeners();
  }

  // ============================================================
  // SUBSCRIPTION GETTERS
  // ============================================================

  List<MilkSubscription> get subscriptions => List.unmodifiable(_subscriptions);

  List<MilkSubscription> get activeSubscriptions => _subscriptions
      .where(
        (subscription) => subscription.status == MilkSubscriptionStatus.active,
      )
      .toList(growable: false);

  int get subscriptionCount => _subscriptions.length;

  // ============================================================
  // ONE PLAN PER MILK AND SHIFT
  // ============================================================

  /// The customer's plans for [productId] that are not cancelled,
  /// oldest first.
  List<MilkSubscription> plansFor(String productId) => [
    for (final subscription in _subscriptions)
      if (subscription.productId == productId &&
          subscription.status != MilkSubscriptionStatus.cancelled &&
          subscription.shiftSchedules.isNotEmpty)
        subscription,
  ];

  /// The shifts in which [plan] would deliver the same milk as
  /// another (not cancelled) plan.
  Set<MilkDeliveryShift> sharedShifts(MilkSubscription plan) => {
    for (final other in plansFor(plan.productId))
      if (other.id != plan.id)
        for (final schedule in plan.shiftSchedules)
          if (other.scheduleFor(schedule.shift) != null) schedule.shift,
  };

  /// How a new plan fits with the existing plans for its milk:
  /// shifts already delivered by a plan are added to that plan;
  /// the other shifts form the new plan.
  MilkPlanChanges checkNewPlan(MilkSubscription incoming) =>
      planNewSubscription(plansFor(incoming.productId), incoming);

  /// Saves a new plan (with any merged deliveries) in one step.
  Future<bool> saveNewPlan(MilkPlanChanges changes) async {
    if (!changes.isPossible) return false;
    return _applyChanges(changes.saves, changes.cancelIds);
  }

  /// Plans that deliver the same milk in the same shift.
  List<DuplicateMilkPlans> get duplicatePlans {
    final byProduct = <String, List<MilkSubscription>>{};
    for (final plan in _subscriptions) {
      if (plan.status == MilkSubscriptionStatus.cancelled ||
          plan.shiftSchedules.isEmpty) {
        continue;
      }
      byProduct.putIfAbsent(plan.productId, () => []).add(plan);
    }

    final groups = <DuplicateMilkPlans>[];
    for (final entry in byProduct.entries) {
      final changes = combineSharedShifts(entry.value);
      if (changes == null) continue;
      final involved = {
        for (final outcome in changes.shifts) ...[
          outcome.target!.id,
          for (final plan in entry.value)
            if (plan.scheduleFor(outcome.shift) != null) plan.id,
        ],
      };
      groups.add(
        DuplicateMilkPlans(entry.key, [
          for (final plan in entry.value)
            if (involved.contains(plan.id)) plan,
        ], changes),
      );
    }
    return groups;
  }

  /// Merges the shared shifts of [productId]'s plans, in one
  /// database transaction.
  Future<bool> combinePlans(String productId) async {
    for (final group in duplicatePlans) {
      if (group.productId == productId && group.canCombine) {
        return _applyChanges(group.changes.saves, group.changes.cancelIds);
      }
    }
    return false;
  }

  Future<bool> _applyChanges(
    List<MilkSubscription> saves,
    List<String> cancelIds,
  ) async {
    if (_isWriting || saves.any((plan) => !_isValidSubscription(plan))) {
      return false;
    }
    for (final plan in saves) {
      final current = _subscriptions.where((s) => s.id == plan.id);
      if (current.isNotEmpty &&
          current.first.status == MilkSubscriptionStatus.cancelled) {
        return false;
      }
    }

    final snapshots = saves.map(_copyWithScheduleSnapshots).toList();

    _isWriting = true;
    try {
      await _repository.saveChanges(saves: snapshots, cancelIds: cancelIds);

      for (final snapshot in snapshots) {
        final index = _subscriptions.indexWhere((s) => s.id == snapshot.id);
        if (index == -1) {
          _subscriptions.add(snapshot);
        } else {
          _subscriptions[index] = snapshot;
        }
      }
      for (var i = 0; i < _subscriptions.length; i++) {
        if (cancelIds.contains(_subscriptions[i].id)) {
          _subscriptions[i] = _copyWithScheduleSnapshots(
            _subscriptions[i].copyWith(
              status: MilkSubscriptionStatus.cancelled,
            ),
          );
        }
      }
      notifyListeners();
      return true;
    } finally {
      _isWriting = false;
    }
  }

  // ============================================================
  // QUANTITY RULES
  // ============================================================

  static const int minimumQuantityMl = 500;
  static const int maximumQuantityMl = 10000;
  static const int quantityStepMl = 500;

  bool _isValidQuantityMl(int quantityMl) {
    return quantityMl >= minimumQuantityMl &&
        quantityMl <= maximumQuantityMl &&
        quantityMl % quantityStepMl == 0;
  }

  // ============================================================
  // VALIDATE A SINGLE SHIFT
  // ============================================================

  bool _isValidShiftSchedule(MilkShiftSchedule schedule) {
    if (!_isValidQuantityMl(schedule.quantityMl)) {
      return false;
    }

    if (schedule.endDate != null &&
        schedule.endDate!.isBefore(schedule.startDate)) {
      return false;
    }

    if (schedule.frequency == MilkDeliveryFrequency.selectedDays) {
      if (schedule.selectedWeekdays.isEmpty) {
        return false;
      }

      final weekdays = schedule.selectedWeekdays;

      if (weekdays.any((day) => day < 1 || day > 7)) {
        return false;
      }

      if (weekdays.toSet().length != weekdays.length) {
        return false;
      }
    }

    if (schedule.frequency == MilkDeliveryFrequency.randomDays) {
      if (schedule.selectedRandomDates.isEmpty) {
        return false;
      }

      final normalizedDates = schedule.selectedRandomDates.map((date) {
        return DateTime(date.year, date.month, date.day);
      }).toList();

      if (normalizedDates.toSet().length != normalizedDates.length) {
        return false;
      }

      for (final date in normalizedDates) {
        final start = DateTime(
          schedule.startDate.year,
          schedule.startDate.month,
          schedule.startDate.day,
        );

        if (date.isBefore(start)) {
          return false;
        }

        if (schedule.endDate != null) {
          final end = DateTime(
            schedule.endDate!.year,
            schedule.endDate!.month,
            schedule.endDate!.day,
          );

          if (date.isAfter(end)) {
            return false;
          }
        }
      }
    }

    return true;
  }

  // ============================================================
  // VALIDATE ALL SHIFTS
  // ============================================================

  bool _isValidShiftSchedules(List<MilkShiftSchedule> schedules) {
    // At least one shift is required.
    if (schedules.isEmpty) {
      return false;
    }

    // Only Morning and Evening are supported.
    if (schedules.length > 2) {
      return false;
    }

    final uniqueShifts = schedules.map((schedule) => schedule.shift).toSet();

    // Prevent duplicate shifts.
    if (uniqueShifts.length != schedules.length) {
      return false;
    }

    for (final schedule in schedules) {
      if (!_isValidShiftSchedule(schedule)) {
        return false;
      }
    }

    return true;
  }

  // ============================================================
  // LEGACY VALIDATION
  // ============================================================

  // Temporary compatibility with the existing setup screen.
  // This will be removed after the UI migration.

  bool _isValidLegacySubscription(MilkSubscription subscription) {
    if (subscription.quantity < 1 || subscription.quantity > 10) {
      return false;
    }

    if (subscription.frequency == MilkDeliveryFrequency.selectedDays) {
      if (subscription.selectedWeekdays.isEmpty ||
          subscription.selectedWeekdays.any((day) => day < 1 || day > 7)) {
        return false;
      }
    }

    if (subscription.frequency == MilkDeliveryFrequency.randomDays &&
        subscription.selectedRandomDates.isEmpty) {
      return false;
    }

    return true;
  }

  // ============================================================
  // SUBSCRIPTION VALIDATION
  // ============================================================

  bool _isValidSubscription(MilkSubscription subscription) {
    // Milk shifts apply only to Buffalo and Cow Milk.
    if (subscription.shiftSchedules.isNotEmpty) {
      if (subscription.productId != 'buffalo_milk' &&
          subscription.productId != 'cow_milk') {
        return false;
      }

      return _isValidShiftSchedules(subscription.shiftSchedules);
    }

    // Continue supporting the existing UI.
    return _isValidLegacySubscription(subscription);
  }

  // ============================================================
  // ADD SUBSCRIPTION
  // ============================================================

  Future<bool> addSubscription(MilkSubscription subscription) async {
    if (_isWriting ||
        !_isValidSubscription(subscription) ||
        subscription.shiftSchedules.isEmpty ||
        _subscriptions.any((item) => item.id == subscription.id) ||
        // One plan per milk and shift: use checkNewPlan/saveNewPlan.
        sharedShifts(subscription).isNotEmpty) {
      return false;
    }

    _isWriting = true;
    try {
      final snapshot = _copyWithScheduleSnapshots(subscription);
      await _repository.saveSubscription(snapshot);
      _subscriptions.add(snapshot);
      notifyListeners();
      return true;
    } finally {
      _isWriting = false;
    }
  }

  // ============================================================
  // UPDATE EXISTING SUBSCRIPTION
  // ============================================================

  Future<bool> updateSubscription(MilkSubscription updatedSubscription) async {
    if (_isWriting) return false;

    final index = _subscriptions.indexWhere(
      (item) => item.id == updatedSubscription.id,
    );
    if (index == -1) return false;

    final existing = _subscriptions[index];
    if (existing.status == MilkSubscriptionStatus.cancelled ||
        !_isValidSubscription(updatedSubscription) ||
        updatedSubscription.shiftSchedules.isEmpty ||
        // An edit may not add a shift another plan already delivers.
        sharedShifts(updatedSubscription)
            .difference(sharedShifts(existing))
            .isNotEmpty) {
      return false;
    }

    final updated = _copyWithScheduleSnapshots(
      existing.copyWith(
        productId: updatedSubscription.productId,
        quantity: updatedSubscription.quantity,
        frequency: updatedSubscription.frequency,
        selectedWeekdays: updatedSubscription.selectedWeekdays,
        selectedRandomDates: updatedSubscription.selectedRandomDates,
        startDate: updatedSubscription.startDate,
        shiftSchedules: updatedSubscription.shiftSchedules,
      ),
    );

    _isWriting = true;
    try {
      await _repository.updateSubscription(updated);
      _subscriptions[index] = updated;
      notifyListeners();
      return true;
    } finally {
      _isWriting = false;
    }
  }

  // ============================================================
  // COPY SCHEDULE DATA
  // ============================================================

  MilkSubscription _copyWithScheduleSnapshots(MilkSubscription subscription) {
    final schedules = subscription.shiftSchedules
        .map((schedule) {
          return schedule.copyWith(
            selectedWeekdays: List<int>.unmodifiable(schedule.selectedWeekdays),
            selectedRandomDates: List<DateTime>.unmodifiable(
              schedule.selectedRandomDates,
            ),
          );
        })
        .toList(growable: false);

    return subscription.copyWith(
      shiftSchedules: List<MilkShiftSchedule>.unmodifiable(schedules),
      selectedWeekdays: List<int>.unmodifiable(subscription.selectedWeekdays),
      selectedRandomDates: List<DateTime>.unmodifiable(
        subscription.selectedRandomDates,
      ),
    );
  }

  // ============================================================
  // PAUSE SUBSCRIPTION
  // ============================================================

  Future<bool> pauseSubscription(String subscriptionId) => _updateStatus(
    subscriptionId,
    MilkSubscriptionStatus.active,
    MilkSubscriptionStatus.paused,
  );

  // ============================================================
  // RESUME SUBSCRIPTION
  // ============================================================

  Future<bool> resumeSubscription(String subscriptionId) => _updateStatus(
    subscriptionId,
    MilkSubscriptionStatus.paused,
    MilkSubscriptionStatus.active,
  );

  // ============================================================
  // CANCEL SUBSCRIPTION
  // ============================================================

  Future<bool> cancelSubscription(String subscriptionId) async {
    if (_isWriting) return false;
    final index = _subscriptions.indexWhere(
      (item) => item.id == subscriptionId,
    );
    if (index == -1 ||
        _subscriptions[index].status == MilkSubscriptionStatus.cancelled) {
      return false;
    }
    return _persistStatus(index, MilkSubscriptionStatus.cancelled);
  }

  // ============================================================
  // INTERNAL STATUS UPDATE
  // ============================================================

  Future<bool> _updateStatus(
    String subscriptionId,
    MilkSubscriptionStatus requiredStatus,
    MilkSubscriptionStatus newStatus,
  ) async {
    if (_isWriting) return false;
    final index = _subscriptions.indexWhere(
      (item) => item.id == subscriptionId,
    );
    if (index == -1 || _subscriptions[index].status != requiredStatus) {
      return false;
    }
    return _persistStatus(index, newStatus);
  }

  Future<bool> _persistStatus(
    int index,
    MilkSubscriptionStatus newStatus,
  ) async {
    final updated = _copyWithScheduleSnapshots(
      _subscriptions[index].copyWith(status: newStatus),
    );
    if (updated.shiftSchedules.isEmpty) return false;

    _isWriting = true;
    try {
      await _repository.updateSubscription(updated);
      _subscriptions[index] = updated;
      notifyListeners();
      return true;
    } finally {
      _isWriting = false;
    }
  }
}
