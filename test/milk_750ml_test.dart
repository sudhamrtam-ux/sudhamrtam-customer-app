import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:sudhamrtam_customer_app/database/milk_database_service.dart';
import 'package:sudhamrtam_customer_app/features/milk_plan/milk_plan_merge_dialog.dart';
import 'package:sudhamrtam_customer_app/models/milk_plan_merge.dart';
import 'package:sudhamrtam_customer_app/models/milk_quantity.dart';
import 'package:sudhamrtam_customer_app/models/milk_subscription.dart';

final start = DateTime(2026, 11, 11);

MilkSubscription plan(String id, int morningMl) => MilkSubscription(
  id: id,
  productId: 'cow_milk',
  shiftSchedules: [
    MilkShiftSchedule(
      shift: MilkDeliveryShift.morning,
      quantityMl: morningMl,
      frequency: MilkDeliveryFrequency.daily,
      startDate: start,
    ),
  ],
  quantity: 1,
  frequency: MilkDeliveryFrequency.daily,
  startDate: start,
);

void main() {
  group('750 ml packets (owner decision 2026-11-11)', () {
    test('whole litres plus 0.5 or 0.75 L, never x.25 L', () {
      for (final ml in [500, 750, 1000, 1500, 1750, 2000, 9750, 10000]) {
        expect(isAllowedMilkMl(ml), isTrue, reason: '$ml');
      }
      for (final ml in [0, 250, 600, 1250, 2250, 10250, 10500]) {
        expect(isAllowedMilkMl(ml), isFalse, reason: '$ml');
      }
    });

    test('the + and - buttons step through the packet sizes', () {
      final up = <int>[500];
      while (up.length < 7) {
        up.add(nextMilkMl(up.last)!);
      }
      expect(up, [500, 750, 1000, 1500, 1750, 2000, 2500]);
      expect(nextMilkMl(10000), isNull);
      expect(previousMilkMl(1000), 750);
      expect(previousMilkMl(1500), 1000);
      expect(previousMilkMl(500), isNull);
    });

    test('litres show 0.75 L, not 0.80 L', () {
      expect(milkLitresText(750), '0.75 L');
      expect(milkLitresText(1750), '1.75 L');
      expect(milkLitresText(1500), '1.50 L');
      expect(milkLitresText(2000), '2.00 L');
      expect(litresText(750), '0.75 L');
    });

    test('adding plans that make x.25 L is not merged', () {
      final changes = planNewSubscription([plan('a', 750)], plan('new', 500));
      expect(changes.isPossible, isFalse);
      expect(changes.shifts.single.kind, ShiftMergeKind.unpackable);
      expect(mergeLines(changes).single, contains('makes 1.25 L'));

      final fine = planNewSubscription([plan('a', 750)], plan('new', 1000));
      expect(fine.isPossible, isTrue);
      expect(fine.shifts.single.kind, ShiftMergeKind.addQuantity);
      expect(fine.saves.single.shiftSchedules.single.quantityMl, 1750);
    });
  });

  group('on the phone', () {
    late Directory directory;
    late String path;

    setUpAll(sqfliteFfiInit);
    setUp(() async {
      directory = await Directory.systemTemp.createTemp('sudhamrtam_750_');
      path = '${directory.path}${Platform.pathSeparator}milk.db';
      MilkDatabaseService.instance.configureForTesting(
        factory: databaseFactoryFfi,
        databasePath: path,
      );
    });
    tearDown(() async {
      await MilkDatabaseService.instance.close();
      MilkDatabaseService.instance.resetTestingConfiguration();
      await directory.delete(recursive: true);
    });

    Future<void> insertSchedule(DatabaseExecutor db, int ml, String shift) =>
        db.insert('milk_shift_schedules', {
          'subscription_id': 'p1',
          'shift': shift,
          'quantity_ml': ml,
          'frequency': 'daily',
          'start_date': start.toIso8601String(),
        });

    test('v16 to v17 keeps plans and allows 750 ml', () async {
      // Build today's database, then put back the v16 schedules
      // table (500 ml steps only), as on a phone before this update.
      await MilkDatabaseService.instance.database;
      await MilkDatabaseService.instance.close();
      final old = await databaseFactoryFfi.openDatabase(path);
      await old.execute('DROP TABLE milk_shift_schedules');
      await old.execute('''
        CREATE TABLE milk_shift_schedules (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          subscription_id TEXT NOT NULL,
          shift TEXT NOT NULL
            CHECK (shift IN ('earlyMorning', 'morning', 'evening')),
          quantity_ml INTEGER NOT NULL
            CHECK (quantity_ml >= 500 AND quantity_ml <= 10000
              AND quantity_ml % 500 = 0),
          frequency TEXT NOT NULL,
          selected_weekdays TEXT NOT NULL DEFAULT '[]',
          selected_random_dates TEXT NOT NULL DEFAULT '[]',
          start_date TEXT NOT NULL,
          end_date TEXT,
          FOREIGN KEY (subscription_id) REFERENCES milk_subscriptions(id)
            ON DELETE CASCADE,
          UNIQUE (subscription_id, shift))''');
      await old.insert('milk_subscriptions', {
        'id': 'p1',
        'product_id': 'cow_milk',
        'created_at': start.toIso8601String(),
      });
      await insertSchedule(old, 1500, 'morning');
      await expectLater(
        insertSchedule(old, 750, 'evening'),
        throwsA(isA<DatabaseException>()),
      );
      await old.setVersion(16);
      await old.close();

      final db = await MilkDatabaseService.instance.database;
      expect(await db.getVersion(), MilkDatabaseService.databaseVersion);
      final rows = await db.query('milk_shift_schedules');
      expect(rows.single, containsPair('quantity_ml', 1500));

      await insertSchedule(db, 750, 'evening');
      await expectLater(
        insertSchedule(db, 1250, 'earlyMorning'),
        throwsA(isA<DatabaseException>()),
      );
      expect(await db.query('milk_shift_schedules'), hasLength(2));
    });
  });
}
