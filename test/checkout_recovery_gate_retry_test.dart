import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:sudhamrtam_customer_app/database/checkout_recovery_executor.dart';
import 'package:sudhamrtam_customer_app/features/checkout/checkout_recovery_gate_screen.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  // ==========================================
  // TEST RECOVERY RESULTS
  // ==========================================

  const blocked = CheckoutRecoveryExecutionResult(
    status: CheckoutRecoveryExecutionStatus.blocked,
    orderId: 'retry-test-order',
    message: 'Recovery is blocked.',
  );

  const recovered = CheckoutRecoveryExecutionResult(
    status: CheckoutRecoveryExecutionStatus.recovered,
    orderId: 'retry-test-order',
    message: 'Recovery completed.',
  );

  // ==========================================
  // TEST APPLICATION BUILDER
  // ==========================================

  Widget buildTestApp({
    required Future<CheckoutRecoveryExecutionResult> Function() retry,
    required Future<void> Function() onCompleted,
  }) {
    return MaterialApp(
      home: CheckoutRecoveryGateScreen(
        initialResult: blocked,
        retryRecovery: retry,
        onRecoveryCompleted: onCompleted,
      ),
    );
  }

  // ==========================================
  // TEST 1: SUCCESSFUL RETRY
  // ==========================================

  testWidgets('successful retry completes startup', (tester) async {
    var completionCount = 0;

    await tester.pumpWidget(
      buildTestApp(
        retry: () async => recovered,
        onCompleted: () async {
          completionCount++;
        },
      ),
    );

    await tester.tap(find.text('Retry Recovery'));
    await tester.pumpAndSettle();

    expect(completionCount, 1);

    expect(find.text('Startup Completed'), findsOneWidget);
  });

  // ==========================================
  // TEST 2: BLOCKED RETRY
  // ==========================================

  testWidgets('blocked retry does not complete startup', (tester) async {
    var completionCount = 0;

    await tester.pumpWidget(
      buildTestApp(
        retry: () async => blocked,
        onCompleted: () async {
          completionCount++;
        },
      ),
    );

    await tester.tap(find.text('Retry Recovery'));
    await tester.pumpAndSettle();

    expect(completionCount, 0);

    expect(find.text('Recovery is blocked.'), findsOneWidget);

    expect(find.text('Retry Recovery'), findsOneWidget);
  });

  // ==========================================
  // TEST 3: CART INITIALIZATION FAILURE
  // ==========================================

  testWidgets('cart initialization failure is displayed', (tester) async {
    await tester.pumpWidget(
      buildTestApp(
        retry: () async => recovered,
        onCompleted: () async {
          throw StateError('Simulated cart initialization failure');
        },
      ),
    );

    await tester.tap(find.text('Retry Recovery'));
    await tester.pumpAndSettle();

    expect(
      find.textContaining('shopping cart could not be initialized'),
      findsOneWidget,
    );

    expect(find.text('Retry Recovery'), findsOneWidget);
  });

  // ==========================================
  // TEST 4: PREVENT OVERLAPPING RETRIES
  // ==========================================

  testWidgets('repeated taps do not overlap recovery attempts', (tester) async {
    final completer = Completer<CheckoutRecoveryExecutionResult>();

    var retryCount = 0;
    var completionCount = 0;

    await tester.pumpWidget(
      buildTestApp(
        retry: () {
          retryCount++;
          return completer.future;
        },
        onCompleted: () async {
          completionCount++;
        },
      ),
    );

    await tester.tap(find.text('Retry Recovery'));
    await tester.pump();

    expect(retryCount, 1);

    // The button must be disabled while recovery
    // is still running.
    final button = tester.widget<FilledButton>(find.byType(FilledButton));

    expect(button.onPressed, isNull);

    // Finish the pending recovery operation.
    completer.complete(recovered);

    await tester.pumpAndSettle();

    expect(retryCount, 1);
    expect(completionCount, 1);

    // Successful startup must disable further retries.
    final completedButton = tester.widget<FilledButton>(
      find.byType(FilledButton),
    );

    expect(completedButton.onPressed, isNull);
  });

  // ==========================================
  // TEST 5: RECOVERY EXCEPTION
  // ==========================================

  testWidgets('recovery exception leaves the gate visible', (tester) async {
    var completionCount = 0;

    await tester.pumpWidget(
      buildTestApp(
        retry: () async {
          throw StateError('Simulated recovery failure');
        },
        onCompleted: () async {
          completionCount++;
        },
      ),
    );

    await tester.tap(find.text('Retry Recovery'));
    await tester.pumpAndSettle();

    expect(completionCount, 0);

    expect(
      find.textContaining('Recovery could not be completed'),
      findsOneWidget,
    );

    expect(find.text('Retry Recovery'), findsOneWidget);
  });
}
