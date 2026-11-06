import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:sudhamrtam_customer_app/database/checkout_recovery_executor.dart';
import 'package:sudhamrtam_customer_app/features/checkout/checkout_recovery_gate_screen.dart';
import 'package:sudhamrtam_customer_app/models/customer_order.dart';
import 'package:sudhamrtam_customer_app/models/order_item.dart';

const orderId = 'unfinished-order-001';

CheckoutRecoveryExecutionResult result(CheckoutRecoveryExecutionStatus status) {
  return CheckoutRecoveryExecutionResult(
    status: status,
    orderId: orderId,
    message: 'Status: ${status.name}',
  );
}

CustomerOrder pendingOrder() {
  return CustomerOrder(
    id: orderId,
    createdAt: DateTime.utc(2026, 11, 6, 8),
    items: const [
      OrderItem(
        productId: 'cow_milk',
        productName: 'Cow Milk',
        unit: '1 L',
        quantity: 2,
        unitPrice: 85,
      ),
    ],
    fulfillmentMethod: FulfillmentMethod.pickup,
    paymentMethod: OrderPaymentMethod.cashOnDelivery,
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late List<String> events;

  setUp(() {
    events = [];
  });

  Future<void> pumpGate(
    WidgetTester tester, {
    CheckoutRecoveryExecutionStatus finishStatus =
        CheckoutRecoveryExecutionStatus.recovered,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        home: CheckoutRecoveryGateScreen(
          initialResult: result(
            CheckoutRecoveryExecutionStatus.awaitingSubmission,
          ),
          loadPendingOrder: () async => pendingOrder(),
          finishPendingOrder: (id) async {
            events.add('finish:$id');
            return result(finishStatus);
          },
          cancelPendingOrder: (id) async {
            events.add('cancel:$id');
            return result(CheckoutRecoveryExecutionStatus.noRecoveryNeeded);
          },
          retryRecovery: () async {
            events.add('retry');
            return result(CheckoutRecoveryExecutionStatus.noRecoveryNeeded);
          },
          onRecoveryCompleted: () async {
            events.add('completed');
          },
        ),
      ),
    );
    await tester.pump();
  }

  testWidgets('Unfinished order shows its summary and both choices', (
    tester,
  ) async {
    await pumpGate(tester);

    expect(find.text('Unfinished Order'), findsOneWidget);
    expect(find.text('Cow Milk — 2 × 1 L'), findsOneWidget);
    expect(find.text('Total: ₹170.00'), findsOneWidget);
    expect(find.text('Finish Placing Order'), findsOneWidget);
    expect(find.text('Cancel Order, Keep Cart'), findsOneWidget);
    expect(find.text('Retry Recovery'), findsNothing);
  });

  testWidgets('Finish re-checks recovery before opening the app', (
    tester,
  ) async {
    await pumpGate(tester);

    await tester.tap(find.text('Finish Placing Order'));
    await tester.pumpAndSettle();

    expect(events, ['finish:$orderId', 'retry', 'completed']);
  });

  testWidgets('Failed finish keeps the choices and the app closed', (
    tester,
  ) async {
    await pumpGate(
      tester,
      finishStatus: CheckoutRecoveryExecutionStatus.awaitingSubmission,
    );

    await tester.tap(find.text('Finish Placing Order'));
    await tester.pumpAndSettle();

    expect(events, ['finish:$orderId']);
    expect(find.text('Finish Placing Order'), findsOneWidget);
    expect(find.text('Cancel Order, Keep Cart'), findsOneWidget);
  });

  testWidgets('Cancel asks for confirmation first', (tester) async {
    await pumpGate(tester);

    await tester.ensureVisible(find.text('Cancel Order, Keep Cart'));
    await tester.tap(find.text('Cancel Order, Keep Cart'));
    await tester.pumpAndSettle();

    expect(find.text('Cancel this order?'), findsOneWidget);

    await tester.tap(find.text('Keep Order'));
    await tester.pumpAndSettle();

    expect(events, isEmpty);
    expect(find.text('Finish Placing Order'), findsOneWidget);
  });

  testWidgets('Confirmed cancel re-checks recovery and opens the app', (
    tester,
  ) async {
    await pumpGate(tester);

    await tester.ensureVisible(find.text('Cancel Order, Keep Cart'));
    await tester.tap(find.text('Cancel Order, Keep Cart'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Cancel Order'));
    await tester.pumpAndSettle();

    expect(events, ['cancel:$orderId', 'retry', 'completed']);
  });
}
