import 'dart:convert';

import 'package:sqflite/sqflite.dart';

import '../models/milk_subscription.dart';
import 'milk_database_service.dart';

/// Persists milk subscriptions and their independent delivery shifts.
///
/// The database stores shift-based subscriptions only. Older single-schedule
/// subscriptions must be migrated before being passed to [saveSubscription].
class MilkSubscriptionRepository {
  MilkSubscriptionRepository({MilkDatabaseService? databaseService})
    : _databaseService = databaseService ?? MilkDatabaseService.instance;

  final MilkDatabaseService _databaseService;

  Future<void> saveSubscription(MilkSubscription subscription) async {
    _validate(subscription);
    final db = await _databaseService.database;
    await db.transaction((txn) => _write(txn, subscription));
  }

  /// Saves [saves] (new or updated plans) and cancels [cancelIds]
  /// in one transaction, so merging deliveries never leaves milk
  /// counted twice or lost halfway.
  Future<void> saveChanges({
    required List<MilkSubscription> saves,
    List<String> cancelIds = const [],
  }) async {
    for (final plan in saves) {
      _validate(plan);
    }
    if (saves.any((plan) => cancelIds.contains(plan.id))) {
      throw ArgumentError('A plan cannot be saved and cancelled together.');
    }
    final db = await _databaseService.database;

    await db.transaction((txn) async {
      for (final plan in saves) {
        await _write(txn, plan);
      }
      for (final id in cancelIds) {
        final updated = await txn.update(
          MilkDatabaseService.subscriptionsTable,
          {
            'status': MilkSubscriptionStatus.cancelled.name,
            'cancelled_at': DateTime.now().toIso8601String(),
          },
          where: 'id = ?',
          whereArgs: [id],
        );
        if (updated != 1) {
          throw StateError('Cannot cancel missing plan $id.');
        }
      }
    });
  }

  /// Replaces every saved plan with [plans] (the server's copy), in
  /// one transaction.
  Future<void> replaceAll(List<MilkSubscription> plans) async {
    for (final plan in plans) {
      _validate(plan);
    }
    final db = await _databaseService.database;
    await db.transaction((txn) async {
      await txn.delete(MilkDatabaseService.schedulesTable);
      await txn.delete(MilkDatabaseService.subscriptionsTable);
      for (final plan in plans) {
        await _write(txn, plan);
      }
    });
  }

  /// Removes every saved plan (sign-out: they are on the server).
  Future<void> deleteAll() => replaceAll(const []);

  Future<void> _write(Transaction txn, MilkSubscription subscription) async {
    await txn.insert(MilkDatabaseService.subscriptionsTable, {
      'id': subscription.id,
      'product_id': subscription.productId,
      'status': subscription.status.name,
      'created_at': subscription.startDate.toIso8601String(),
      'cancelled_at': subscription.cancelledAt?.toIso8601String(),
      'resume_on': subscription.resumeOn?.toIso8601String(),
    }, conflictAlgorithm: ConflictAlgorithm.replace);

    // Replacing the parent row may cascade-delete old shifts; explicitly
    // delete them as well so updates always reflect the supplied schedules.
    await txn.delete(
      MilkDatabaseService.schedulesTable,
      where: 'subscription_id = ?',
      whereArgs: [subscription.id],
    );

    for (final schedule in subscription.shiftSchedules) {
      await txn.insert(MilkDatabaseService.schedulesTable, {
        'subscription_id': subscription.id,
        'shift': schedule.shift.name,
        'quantity_ml': schedule.quantityMl,
        'frequency': schedule.frequency.name,
        'selected_weekdays': jsonEncode(schedule.selectedWeekdays),
        'selected_random_dates': jsonEncode(
          schedule.selectedRandomDates
              .map((date) => date.toIso8601String())
              .toList(),
        ),
        'start_date': schedule.startDate.toIso8601String(),
        'end_date': schedule.endDate?.toIso8601String(),
      });
    }
  }

  Future<List<MilkSubscription>> loadSubscriptions() async {
    final db = await _databaseService.database;
    final parents = await db.query(
      MilkDatabaseService.subscriptionsTable,
      orderBy: 'created_at ASC, id ASC',
    );
    final children = await db.query(
      MilkDatabaseService.schedulesTable,
      orderBy: 'id ASC',
    );

    final bySubscription = <String, List<MilkShiftSchedule>>{};
    for (final row in children) {
      final subscriptionId = row['subscription_id'] as String;
      final weekdayJson =
          jsonDecode(row['selected_weekdays'] as String) as List<dynamic>;
      final dateJson =
          jsonDecode(row['selected_random_dates'] as String) as List<dynamic>;
      final schedule = MilkShiftSchedule(
        shift: MilkDeliveryShift.values.byName(row['shift'] as String),
        quantityMl: row['quantity_ml'] as int,
        frequency: MilkDeliveryFrequency.values.byName(
          row['frequency'] as String,
        ),
        selectedWeekdays: List<int>.unmodifiable(weekdayJson.cast<int>()),
        selectedRandomDates: List<DateTime>.unmodifiable(
          dateJson.map((value) => DateTime.parse(value as String)),
        ),
        startDate: DateTime.parse(row['start_date'] as String),
        endDate: row['end_date'] == null
            ? null
            : DateTime.parse(row['end_date'] as String),
      );
      bySubscription.putIfAbsent(subscriptionId, () => []).add(schedule);
    }

    return parents
        .map((row) {
          final id = row['id'] as String;
          final schedules = bySubscription[id] ?? <MilkShiftSchedule>[];
          if (schedules.isEmpty) {
            throw StateError('Subscription $id has no saved shift schedules.');
          }
          final first = schedules.first;
          // Legacy fields remain required by the current model. These are
          // compatibility values; the authoritative data is shiftSchedules.
          return MilkSubscription(
            id: id,
            productId: row['product_id'] as String,
            shiftSchedules: List<MilkShiftSchedule>.unmodifiable(schedules),
            quantity: 1,
            frequency: first.frequency,
            selectedWeekdays: List<int>.unmodifiable(first.selectedWeekdays),
            selectedRandomDates: List<DateTime>.unmodifiable(
              first.selectedRandomDates,
            ),
            startDate: DateTime.parse(row['created_at'] as String),
            status: MilkSubscriptionStatus.values.byName(
              row['status'] as String,
            ),
            cancelledAt: row['cancelled_at'] == null
                ? null
                : DateTime.parse(row['cancelled_at'] as String),
            resumeOn: row['resume_on'] == null
                ? null
                : DateTime.parse(row['resume_on'] as String),
          );
        })
        .toList(growable: false);
  }

  Future<void> deleteSubscription(String subscriptionId) async {
    final db = await _databaseService.database;
    await db.delete(
      MilkDatabaseService.subscriptionsTable,
      where: 'id = ?',
      whereArgs: [subscriptionId],
    );
    // Related shifts are removed automatically by ON DELETE CASCADE.
  }

  Future<void> updateSubscription(MilkSubscription subscription) async {
    final db = await _databaseService.database;
    final rows = await db.query(
      MilkDatabaseService.subscriptionsTable,
      columns: ['id'],
      where: 'id = ?',
      whereArgs: [subscription.id],
      limit: 1,
    );
    if (rows.isEmpty) {
      throw StateError(
        'Cannot update missing subscription ${subscription.id}.',
      );
    }
    await saveSubscription(subscription);
  }

  void _validate(MilkSubscription subscription) {
    if (subscription.id.isEmpty) {
      throw ArgumentError('Subscription ID must not be empty.');
    }
    if (subscription.productId != 'buffalo_milk' &&
        subscription.productId != 'cow_milk') {
      throw ArgumentError('Only Cow Milk and Buffalo Milk are supported.');
    }
    final schedules = subscription.shiftSchedules;
    if (schedules.isEmpty || schedules.length > 2) {
      throw ArgumentError('Provide one or two delivery shift schedules.');
    }
    if (schedules.map((s) => s.shift).toSet().length != schedules.length) {
      throw ArgumentError('Morning and Evening shifts must be unique.');
    }
    for (final schedule in schedules) {
      if (schedule.quantityMl < 500 ||
          schedule.quantityMl > 10000 ||
          schedule.quantityMl % 500 != 0) {
        throw ArgumentError(
          'Shift quantity must be 500–10000 ml in 500 ml steps.',
        );
      }
      if (schedule.endDate != null &&
          schedule.endDate!.isBefore(schedule.startDate)) {
        throw ArgumentError('Shift end date must not precede its start date.');
      }
      if (schedule.frequency == MilkDeliveryFrequency.selectedDays &&
          (schedule.selectedWeekdays.isEmpty ||
              schedule.selectedWeekdays.any((d) => d < 1 || d > 7) ||
              schedule.selectedWeekdays.toSet().length !=
                  schedule.selectedWeekdays.length)) {
        throw ArgumentError(
          'Select distinct weekdays between Monday and Sunday.',
        );
      }
      if (schedule.frequency == MilkDeliveryFrequency.randomDays &&
          schedule.selectedRandomDates.isEmpty) {
        throw ArgumentError('Select at least one random delivery date.');
      }
    }
  }
}
