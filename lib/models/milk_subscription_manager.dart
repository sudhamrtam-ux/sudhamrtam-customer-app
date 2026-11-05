import 'package:flutter/foundation.dart';

import 'milk_subscription.dart';
import '../database/milk_subscription_repository.dart';

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

  bool get isEmpty => _subscriptions.isEmpty;

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
        _subscriptions.any((item) => item.id == subscription.id)) {
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
        updatedSubscription.shiftSchedules.isEmpty) {
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
