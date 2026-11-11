import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:sudhamrtam_customer_app/features/home/account_status.dart';
import 'package:sudhamrtam_customer_app/models/milk_subscription.dart';
import 'package:sudhamrtam_customer_app/models/milk_subscription_manager.dart';

/// 11 November 2026.
final today = DateTime(2026, 11, 11, 9);

MilkSubscription plan(
  String id,
  String product,
  MilkSubscriptionStatus status, {
  DateTime? resumeOn,
}) => MilkSubscription(
  id: id,
  productId: product,
  shiftSchedules: [
    MilkShiftSchedule(
      shift: MilkDeliveryShift.morning,
      quantityMl: 1000,
      frequency: MilkDeliveryFrequency.daily,
      startDate: DateTime(2026, 11, 1),
    ),
  ],
  quantity: 1,
  frequency: MilkDeliveryFrequency.daily,
  startDate: DateTime(2026, 11, 1),
  status: status,
  resumeOn: resumeOn,
);

const active = MilkSubscriptionStatus.active;
const paused = MilkSubscriptionStatus.paused;
const cancelled = MilkSubscriptionStatus.cancelled;

void main() {
  group('account status', () {
    AccountStatus of(List<MilkSubscription> plans) =>
        accountStatusFor(plans, today);

    test('inactive without an open plan', () {
      expect(of([]).state, AccountState.inactive);
      final s = of([plan('a', 'cow_milk', cancelled)]);
      expect((s.state, s.label), (AccountState.inactive, 'Inactive'));
    });

    test('active when milk is coming', () {
      final s = of([plan('a', 'buffalo_milk', active)]);
      expect((s.label, s.detail), ('Active', 'Buffalo Milk on the way'));
      expect(s.color, const Color(0xFF2E7D32));
    });

    test('active with notes about paused milk', () {
      final s = of([
        plan('a', 'buffalo_milk', active),
        plan('b', 'cow_milk', paused, resumeOn: DateTime(2026, 11, 20)),
      ]);
      expect(s.label, 'Active');
      expect(
        s.detail,
        'Buffalo Milk on the way · Cow Milk on vacation until 19 Nov',
      );
    });

    test('on vacation (blue) with the restart date', () {
      final s = of([
        plan('a', 'buffalo_milk', paused, resumeOn: DateTime(2026, 11, 20)),
        plan('b', 'cow_milk', paused, resumeOn: DateTime(2026, 11, 18)),
      ]);
      expect((s.state, s.label), (AccountState.vacation, 'On vacation'));
      expect(s.detail, 'Milk restarts on 18 Nov. Enjoy your trip!');
      expect(s.color, const Color(0xFF1565C0));
    });

    test('paused (orange) without a return date', () {
      final s = of([
        plan('a', 'buffalo_milk', paused),
        plan('b', 'cow_milk', paused, resumeOn: DateTime(2026, 11, 20)),
      ]);
      expect((s.state, s.label), (AccountState.paused, 'Paused'));
      expect(s.color, const Color(0xFFEF6C00));
    });

    test('back from vacation counts as active before the server says so', () {
      final s = of([
        plan('a', 'buffalo_milk', paused, resumeOn: DateTime(2026, 11, 11)),
      ]);
      expect(s.label, 'Active');
    });
  });

  testWidgets('the card on Home shows the status and opens Milk Plan', (
    tester,
  ) async {
    final manager = MilkSubscriptionManager();
    var opened = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: AccountStatusCard(
            plans: manager,
            onOpen: () => opened++,
            today: () => today,
          ),
        ),
      ),
    );
    expect(find.text('Inactive'), findsOneWidget);
    await tester.tap(find.byKey(const Key('accountStatus')));
    expect(opened, 1);
  });
}
