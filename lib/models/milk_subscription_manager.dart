import 'package:flutter/foundation.dart';

import 'milk_plan_merge.dart';
import 'milk_subscription.dart';
import '../database/milk_subscription_repository.dart';
import '../services/milk_plan_api_client.dart';

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

/// The customer's milk plans.
///
/// - **Signed out ([remote] null):** plans are saved on the phone.
/// - **Signed in:** every change goes to the server first; the
///   phone then mirrors the server's answer. If the server can't
///   be reached, nothing changes and [MilkPlanSyncException] is
///   thrown. Before the first change of a session, plans that
///   exist only on the phone are uploaded ([syncWithServer]), so
///   mirroring never loses them.
/// - Changes and syncs run one at a time.
class MilkSubscriptionManager extends ChangeNotifier {
  final List<MilkSubscription> _subscriptions = [];
  final MilkSubscriptionRepository _repository = MilkSubscriptionRepository();
  bool _isWriting = false;

  bool get isWriting => _isWriting;

  /// True once plans are in memory (restored or mirrored).
  bool _loaded = false;

  MilkPlanRemote? _remote;
  bool _syncedThisSession = false;
  Future<void> _queue = Future.value();

  /// The server, while signed in; null: plans stay on the phone.
  MilkPlanRemote? get remote => _remote;
  set remote(MilkPlanRemote? value) {
    _remote = value;
    _syncedThisSession = false;
  }

  /// Runs [action] after every earlier change or sync finished.
  Future<T> _serial<T>(Future<T> Function() action) {
    final result = _queue.then((_) => action());
    _queue = result.then((_) {}, onError: (_) {});
    return result;
  }

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
    _loaded = true;

    notifyListeners();
  }

  /// Loads the plans saved on this phone. Call once at startup.
  ///
  /// A plan that no longer passes validation is skipped (it stays
  /// in the database untouched) instead of hiding every other
  /// plan. Returns how many were skipped.
  Future<int> restoreSavedSubscriptions() async {
    // Already mirrored from the server (or restored): keep that.
    if (_loaded) return 0;
    final saved = await _repository.loadSubscriptions();
    final ids = <String>{};
    final usable = [
      for (final plan in saved)
        if (_isValidSubscription(plan) && ids.add(plan.id)) plan,
    ];
    await loadSavedSubscriptions(usable);
    return saved.length - usable.length;
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

    await _commit(saves, cancelIds);
    return true;
  }

  // ============================================================
  // SAVING: PHONE OR SERVER
  // ============================================================

  /// Saves [saves] and cancels [cancelIds]: on the server first
  /// when signed in, otherwise on the phone. Throws if not saved.
  Future<void> _commit(List<MilkSubscription> saves, List<String> cancelIds) =>
      _serial(() async {
        final snapshots = saves.map(_copyWithScheduleSnapshots).toList();
        _isWriting = true;
        try {
          final server = _remote;
          if (server == null) {
            await _commitLocal(snapshots, cancelIds);
            return;
          }
          if (!_syncedThisSession) await _syncLocked(server);
          await _mirror(await server.applyChanges(snapshots, cancelIds));
        } finally {
          _isWriting = false;
        }
      });

  Future<void> _commitLocal(
    List<MilkSubscription> snapshots,
    List<String> cancelIds,
  ) async {
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
          _subscriptions[i].copyWith(status: MilkSubscriptionStatus.cancelled),
        );
      }
    }
    notifyListeners();
  }

  /// Replaces the phone's plans with the server's [plans].
  Future<void> _mirror(List<MilkSubscription> plans) async {
    final ids = <String>{};
    final usable = [
      for (final plan in plans)
        if (_isValidSubscription(plan) && ids.add(plan.id))
          _copyWithScheduleSnapshots(plan),
    ];
    await _repository.replaceAll(usable);
    _subscriptions
      ..clear()
      ..addAll(usable);
    _loaded = true;
    notifyListeners();
  }

  /// Uploads plans that exist only on this phone, then mirrors the
  /// server. Where the account already has a plan for the same
  /// milk and shift, the account's plan wins (quantities are not
  /// added: the same plan on two phones would double the milk).
  /// Returns how many shifts were left out for that reason.
  Future<int> syncWithServer() => _serial(() async {
    final server = _remote;
    if (server == null) return 0;
    return _syncLocked(server);
  });

  Future<int> _syncLocked(MilkPlanRemote server) async {
    final serverPlans = await server.fetchPlans();
    final serverIds = {for (final plan in serverPlans) plan.id};
    String key(MilkSubscription plan, MilkShiftSchedule shift) =>
        '${plan.productId}:${shift.shift.name}';
    final taken = {
      for (final plan in serverPlans)
        if (plan.status != MilkSubscriptionStatus.cancelled)
          for (final shift in plan.shiftSchedules) key(plan, shift),
    };

    var leftOut = 0;
    final uploads = <MilkSubscription>[];
    for (final plan in await _repository.loadSubscriptions()) {
      if (plan.status == MilkSubscriptionStatus.cancelled ||
          serverIds.contains(plan.id) ||
          !_isValidSubscription(plan)) {
        continue;
      }
      final kept = [
        for (final shift in plan.shiftSchedules)
          if (!taken.contains(key(plan, shift))) shift,
      ];
      leftOut += plan.shiftSchedules.length - kept.length;
      if (kept.isEmpty) continue;
      taken.addAll(kept.map((shift) => key(plan, shift)));
      uploads.add(
        _copyWithScheduleSnapshots(plan.copyWith(shiftSchedules: kept)),
      );
    }

    final result = uploads.isEmpty
        ? serverPlans
        : await server.applyChanges(uploads, const []);
    await _mirror(result);
    _syncedThisSession = true;
    return leftOut;
  }

  /// Sign-out: the plans belong to the account (they are on the
  /// server), so they are removed from this phone.
  Future<void> forgetAll() => _serial(() async {
    await _repository.deleteAll();
    _subscriptions.clear();
    _syncedThisSession = false;
    _loaded = true;
    notifyListeners();
  });

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

    // At most one schedule per shift.
    if (schedules.length > MilkDeliveryShift.values.length) {
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

    await _commit([subscription], const []);
    return true;
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

    await _commit([updated], const []);
    return true;
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

    if (newStatus == MilkSubscriptionStatus.cancelled) {
      await _commit(const [], [updated.id]);
    } else {
      await _commit([updated], const []);
    }
    return true;
  }
}
