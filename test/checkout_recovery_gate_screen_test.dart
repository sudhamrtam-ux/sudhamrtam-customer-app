import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:sudhamrtam_customer_app/database/checkout_recovery_executor.dart';
import 'package:sudhamrtam_customer_app/features/checkout/checkout_recovery_gate_screen.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  CheckoutRecoveryExecutionResult blockedResult() {
    return const CheckoutRecoveryExecutionResult(
      status: CheckoutRecoveryExecutionStatus.blocked,
      orderId: 'test-order-123',
      message: 'Checkout recovery requires investigation.',
    );
  }

  Widget buildTestApp({
    required CheckoutRecoveryExecutionResult initialResult,
    required Future<void> Function() onRecoveryCompleted,
  }) {
    return MaterialApp(
      home: CheckoutRecoveryGateScreen(
        initialResult: initialResult,
        onRecoveryCompleted: onRecoveryCompleted,
      ),
    );
  }

  testWidgets('blocked recovery screen displays order details', (tester) async {
    await tester.pumpWidget(
      buildTestApp(
        initialResult: blockedResult(),
        onRecoveryCompleted: () async {},
      ),
    );

    expect(find.text('Checkout Recovery Required'), findsOneWidget);

    expect(
      find.text('Checkout recovery requires investigation.'),
      findsOneWidget,
    );

    expect(find.text('Order ID: test-order-123'), findsOneWidget);

    expect(find.text('Retry Recovery'), findsOneWidget);
  });

  testWidgets('recovery screen does not initialize cart automatically', (
    tester,
  ) async {
    var initializationCount = 0;

    await tester.pumpWidget(
      buildTestApp(
        initialResult: blockedResult(),
        onRecoveryCompleted: () async {
          initializationCount++;
        },
      ),
    );

    await tester.pump();

    expect(initializationCount, 0);
    expect(find.text('Retry Recovery'), findsOneWidget);
  });

  testWidgets('recovery screen prevents normal navigation', (tester) async {
    await tester.pumpWidget(
      buildTestApp(
        initialResult: blockedResult(),
        onRecoveryCompleted: () async {},
      ),
    );

    expect(find.text('Checkout Recovery Required'), findsOneWidget);

    expect(find.text('Shop'), findsNothing);
    expect(find.text('Milk Plan'), findsNothing);
    expect(find.text('Cart'), findsNothing);
    expect(find.text('Account'), findsNothing);
  });

  testWidgets('retry button is available for blocked recovery', (tester) async {
    await tester.pumpWidget(
      buildTestApp(
        initialResult: blockedResult(),
        onRecoveryCompleted: () async {},
      ),
    );

    final retryButton = find.widgetWithText(FilledButton, 'Retry Recovery');

    expect(retryButton, findsOneWidget);

    final button = tester.widget<FilledButton>(retryButton);

    expect(button.onPressed, isNotNull);
  });
}
