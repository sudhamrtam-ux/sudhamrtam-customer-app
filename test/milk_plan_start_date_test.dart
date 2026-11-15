import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:sudhamrtam_customer_app/app/sudhamrtam_app.dart';
import 'package:sudhamrtam_customer_app/database/milk_database_service.dart';
import 'package:sudhamrtam_customer_app/features/milk_plan/milk_subscription_setup_screen.dart';
import 'package:sudhamrtam_customer_app/models/milk_subscription.dart';

/// Early morning deliveries (owner decision 2026-11-10): last
/// evening's milk, kept cold; changes close at 9 PM the evening before.
///
/// In its own file: the app's shared plan manager queues writes,
/// and a write left from another test would hold this one up.
List<(MilkDeliveryShift, int)> shifts(MilkSubscription p) => [
  for (final s in p.shiftSchedules) (s.shift, s.quantityMl),
];

void main() {
  late Directory directory;

  setUpAll(sqfliteFfiInit);

  setUp(() async {
    directory = await Directory.systemTemp.createTemp('sudhamrtam_early_');
    MilkDatabaseService.instance.configureForTesting(
      factory: databaseFactoryFfi,
      databasePath: '${directory.path}${Platform.pathSeparator}milk.db',
    );
  });

  tearDown(() async {
    await MilkDatabaseService.instance.close();
    MilkDatabaseService.instance.resetTestingConfiguration();
    await directory.delete(recursive: true);
  });

  Future<void> waitUntil(WidgetTester tester, bool Function() done) async {
    for (var i = 0; i < 500 && !done(); i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 10)),
      );
      await tester.pump();
    }
  }

  testWidgets('the customer chooses when milk starts', (tester) async {
    tester.view.physicalSize = const Size(1080, 6000);
    tester.view.devicePixelRatio = 2;
    addTearDown(tester.view.reset);

    await tester.runAsync(() => MilkDatabaseService.instance.database);
    await tester.pumpWidget(
      const MaterialApp(
        home: MilkSubscriptionSetupScreen(productName: 'Cow Milk'),
      ),
    );

    // A new plan starts today unless the customer picks a later day.
    final row = find.byKey(const Key('Morning-start'));
    expect(
      find.descendant(of: row, matching: find.text('Starts on')),
      findsOneWidget,
    );
    final today = DateUtils.dateOnly(DateTime.now());
    final later = today.add(const Duration(days: 5));
    await tester.tap(find.descendant(of: row, matching: find.text('Change')));
    await tester.pumpAndSettle();
    // Type the date in the calendar's text mode.
    await tester.tap(find.byIcon(Icons.edit_outlined));
    await tester.pumpAndSettle();
    final mm = later.month.toString().padLeft(2, '0');
    final dd = later.day.toString().padLeft(2, '0');
    await tester.enterText(
      find.byType(TextField).last,
      '$mm/$dd/${later.year}',
    );
    await tester.tap(find.text('OK'));
    await tester.pumpAndSettle();
    expect(
      find.descendant(
        of: row,
        matching: find.text(
          MaterialLocalizations.of(tester.element(row)).formatFullDate(later),
        ),
      ),
      findsOneWidget,
    );

    await tester.tap(find.text('Save Milk Subscription'));
    await waitUntil(
      tester,
      () =>
          !sudhamrtamMilkSubscriptions.isWriting &&
          sudhamrtamMilkSubscriptions.plansFor('cow_milk').isNotEmpty,
    );
    final saved = sudhamrtamMilkSubscriptions.plansFor('cow_milk').single;
    expect(
      DateUtils.dateOnly(
        saved.scheduleFor(MilkDeliveryShift.morning)!.startDate,
      ),
      later,
    );
  });
}
