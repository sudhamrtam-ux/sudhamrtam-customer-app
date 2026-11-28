import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sudhamrtam_customer_app/features/milk_plan/not_approved_card.dart';
import 'package:sudhamrtam_customer_app/models/milk_subscription.dart';
import 'package:sudhamrtam_customer_app/models/milk_subscription_manager.dart';

// A new subscription Sudhamrtam did not approve shows with its reason
// on Home and Subscriptions (owner decision 2026-11-28).
final start = DateTime(2026, 11, 8);

MilkSubscription plan(
  String id, {
  String? approval,
  String? reason,
  DateTime? cancelledAt,
}) => MilkSubscription(
  id: id,
  productId: 'buffalo_milk',
  shiftSchedules: [
    MilkShiftSchedule(
      shift: MilkDeliveryShift.morning,
      quantityMl: 1000,
      frequency: MilkDeliveryFrequency.daily,
      startDate: start,
    ),
  ],
  quantity: 1,
  frequency: MilkDeliveryFrequency.daily,
  startDate: start,
  status: cancelledAt == null
      ? MilkSubscriptionStatus.active
      : MilkSubscriptionStatus.cancelled,
  cancelledAt: cancelledAt,
  approval: approval,
  rejectReason: reason,
);

void main() {
  late MilkSubscriptionManager manager;
  late Set<String> seen;
  late List<String> setups;
  late int supportOpened;

  Future<void> show(WidgetTester tester, {DateTime? now}) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: NotApprovedCard(
            manager: manager,
            isSeen: (id) async => seen.contains(id),
            markSeen: (id) async => seen.add(id),
            openSetup: (context, productId) async => setups.add(productId),
            openSupport: (_) => supportOpened++,
            clock: () => now ?? DateTime(2026, 11, 10),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  setUp(() async {
    manager = MilkSubscriptionManager();
    seen = {};
    setups = [];
    supportOpened = 0;
    await manager.loadSavedSubscriptions([
      plan('ok1', approval: 'approved'),
      plan(
        'no1',
        approval: 'rejected',
        reason: 'We do not deliver to Kondapur yet.',
        cancelledAt: DateTime(2026, 11, 9),
      ),
      // Cancelled by the customer: not a rejection.
      plan('cx1', approval: 'approved', cancelledAt: DateTime(2026, 11, 9)),
    ]);
  });

  testWidgets('shows the reason with ways forward; OK hides it for good', (
    tester,
  ) async {
    await show(tester);
    expect(find.byKey(const Key('notApproved_no1')), findsOneWidget);
    expect(find.byKey(const Key('notApproved_cx1')), findsNothing);
    expect(find.byKey(const Key('notApproved_ok1')), findsNothing);
    expect(
      find.text('Reason: We do not deliver to Kondapur yet.'),
      findsOneWidget,
    );
    expect(find.text('Answered on 9 Nov 2026'), findsOneWidget);

    await tester.tap(find.byKey(const Key('notApprovedRetry_no1')));
    expect(setups, ['buffalo_milk']);
    await tester.tap(find.byKey(const Key('notApprovedContact_no1')));
    expect(supportOpened, 1);

    await tester.tap(find.byKey(const Key('notApprovedOk_no1')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('notApproved_no1')), findsNothing);
    expect(seen, {'no1'});
    // Seen once is seen everywhere (Home and Subscriptions).
    await show(tester);
    expect(find.byKey(const Key('notApproved_no1')), findsNothing);
  });

  testWidgets('older than 30 days: not shown', (tester) async {
    await show(tester, now: DateTime(2026, 12, 10));
    expect(find.byKey(const Key('notApproved_no1')), findsNothing);
  });
}
