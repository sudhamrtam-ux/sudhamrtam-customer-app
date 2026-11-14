import 'package:flutter/material.dart';

import '../../database/milk_database_service.dart';
import '../../database/milk_subscription_repository.dart';
import '../../models/milk_subscription.dart';
import '../../core/widgets/page_app_bar.dart';

/// Temporary manual test screen. Do not include in production navigation.
class MilkSqliteTestScreen extends StatefulWidget {
  const MilkSqliteTestScreen({super.key});

  @override
  State<MilkSqliteTestScreen> createState() => _MilkSqliteTestScreenState();
}

class _MilkSqliteTestScreenState extends State<MilkSqliteTestScreen> {
  bool _running = false;
  String _result = 'Tap Run SQLite Test to begin.';

  Future<void> _runTest() async {
    if (_running) return;
    setState(() {
      _running = true;
      _result = 'Running database checks...';
    });

    final repository = MilkSubscriptionRepository();
    final database = MilkDatabaseService.instance;
    final id = 'sqlite_test_${DateTime.now().microsecondsSinceEpoch}';
    final start = DateTime(2026, 11, 3);
    var testPassed = false;
    String message;

    try {
      final subscription = MilkSubscription(
        id: id,
        productId: 'buffalo_milk',
        quantity: 1,
        frequency: MilkDeliveryFrequency.daily,
        startDate: start,
        shiftSchedules: [
          MilkShiftSchedule(
            shift: MilkDeliveryShift.morning,
            quantityMl: 1000,
            frequency: MilkDeliveryFrequency.daily,
            startDate: start,
          ),
          MilkShiftSchedule(
            shift: MilkDeliveryShift.evening,
            quantityMl: 500,
            frequency: MilkDeliveryFrequency.selectedDays,
            selectedWeekdays: [1, 3, 5],
            startDate: start,
          ),
        ],
      );

      await repository.saveSubscription(subscription);
      await database.close();

      var loaded = (await repository.loadSubscriptions())
          .where((item) => item.id == id)
          .toList();
      if (loaded.length != 1 ||
          loaded.single.scheduleFor(MilkDeliveryShift.morning)?.quantityMl !=
              1000 ||
          loaded.single.scheduleFor(MilkDeliveryShift.evening)?.quantityMl !=
              500 ||
          loaded.single.scheduleFor(MilkDeliveryShift.evening)?.frequency !=
              MilkDeliveryFrequency.selectedDays ||
          loaded.single
                  .scheduleFor(MilkDeliveryShift.evening)!
                  .selectedWeekdays
                  .join(',') !=
              '1,3,5') {
        throw StateError('Saved schedules did not reload correctly.');
      }

      final updated = loaded.single.copyWith(
        shiftSchedules: [
          loaded.single
              .scheduleFor(MilkDeliveryShift.morning)!
              .copyWith(quantityMl: 1500),
          loaded.single.scheduleFor(MilkDeliveryShift.evening)!,
        ],
      );
      await repository.updateSubscription(updated);
      await database.close();

      loaded = (await repository.loadSubscriptions())
          .where((item) => item.id == id)
          .toList();
      if (loaded.length != 1 ||
          loaded.single.scheduleFor(MilkDeliveryShift.morning)?.quantityMl !=
              1500 ||
          loaded.single.scheduleFor(MilkDeliveryShift.evening)?.quantityMl !=
              500) {
        throw StateError('Updated schedules did not reload correctly.');
      }

      await repository.deleteSubscription(id);
      await database.close();
      loaded = (await repository.loadSubscriptions())
          .where((item) => item.id == id)
          .toList();
      if (loaded.isNotEmpty) {
        throw StateError('Test subscription was not deleted.');
      }

      testPassed = true;
      message =
          'PASS: Save, reopen, load, update, reopen, and delete all worked.';
    } catch (error) {
      message = 'FAILED: $error\nTest ID: $id';
      // Leave failed test data intact for investigation.
    }

    if (!mounted) return;
    setState(() {
      _running = false;
      _result = message;
    });
    if (testPassed) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('SQLite test passed!')));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: PageAppBar(title: const Text('SQLite Storage Test')),
      body: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            FilledButton(
              onPressed: _running ? null : _runTest,
              child: Text(_running ? 'Testing...' : 'Run SQLite Test'),
            ),
            const SizedBox(height: 20),
            SelectableText(_result),
          ],
        ),
      ),
    );
  }
}
