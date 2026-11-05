import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:sudhamrtam_customer_app/app/checkout_startup_controller.dart';
import 'package:sudhamrtam_customer_app/database/checkout_recovery_executor.dart';
import 'package:sudhamrtam_customer_app/features/checkout/checkout_recovery_gate_screen.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const blockedResult = CheckoutRecoveryExecutionResult(
    status: CheckoutRecoveryExecutionStatus.blocked,
    orderId: 'test-order-001',
    message: 'Checkout requires investigation.',
  );

  const recoveredResult = CheckoutRecoveryExecutionResult(
    status: CheckoutRecoveryExecutionStatus.recovered,
    orderId: 'test-order-001',
    message: 'Checkout recovered successfully.',
  );

  Future<void> showGate(
    WidgetTester tester, {
    required Future<CheckoutRecoveryExecutionResult> Function() retryRecovery,
    required Future<void> Function() onRecoveryCompleted,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        home: CheckoutRecoveryGateScreen(
          initialResult: blockedResult,
          retryRecovery: retryRecovery,
          onRecoveryCompleted: onRecoveryCompleted,
        ),
      ),
    );
  }

  testWidgets('Blocked startup displays recovery gate and order details', (
    tester,
  ) async {
    await showGate(
      tester,
      retryRecovery: () async => blockedResult,
      onRecoveryCompleted: () async {},
    );

    expect(find.text('Checkout Recovery Required'), findsOneWidget);

    expect(find.text('Checkout requires investigation.'), findsOneWidget);

    expect(find.text('Order ID: test-order-001'), findsOneWidget);

    expect(find.text('Retry Recovery'), findsOneWidget);
  });

  testWidgets('Failed retry keeps recovery gate visible', (tester) async {
    var retryCount = 0;
    var completionCount = 0;

    await showGate(
      tester,
      retryRecovery: () async {
        retryCount++;
        return blockedResult;
      },
      onRecoveryCompleted: () async {
        completionCount++;
      },
    );

    await tester.tap(find.text('Retry Recovery'));
    await tester.pumpAndSettle();

    expect(retryCount, 1);
    expect(completionCount, 0);

    expect(find.text('Checkout Recovery Required'), findsOneWidget);

    expect(find.text('Retry Recovery'), findsOneWidget);
  });

  testWidgets('Recovery exception displays error and permits retry', (
    tester,
  ) async {
    var retryCount = 0;

    await showGate(
      tester,
      retryRecovery: () async {
        retryCount++;
        throw StateError('Simulated network failure');
      },
      onRecoveryCompleted: () async {},
    );

    await tester.tap(find.text('Retry Recovery'));
    await tester.pumpAndSettle();

    expect(retryCount, 1);

    expect(
      find.textContaining('Recovery could not be completed'),
      findsOneWidget,
    );

    expect(find.text('Retry Recovery'), findsOneWidget);
  });

  testWidgets('Repeated taps do not start overlapping recovery', (
    tester,
  ) async {
    final completer = Completer<CheckoutRecoveryExecutionResult>();

    var retryCount = 0;

    await showGate(
      tester,
      retryRecovery: () {
        retryCount++;
        return completer.future;
      },
      onRecoveryCompleted: () async {},
    );

    await tester.tap(find.text('Retry Recovery'));
    await tester.pump();

    expect(retryCount, 1);

    expect(find.text('Checking recovery...'), findsOneWidget);

    final button = tester.widget<FilledButton>(find.byType(FilledButton));

    expect(button.onPressed, isNull);

    completer.complete(blockedResult);
    await tester.pumpAndSettle();

    expect(retryCount, 1);
    expect(find.text('Retry Recovery'), findsOneWidget);
  });

  testWidgets(
    'Cart initialization failure is displayed and retry remains available',
    (tester) async {
      var retryCount = 0;
      var initializationCount = 0;

      await showGate(
        tester,
        retryRecovery: () async {
          retryCount++;
          return recoveredResult;
        },
        onRecoveryCompleted: () async {
          initializationCount++;

          if (initializationCount == 1) {
            throw StateError('Simulated cart initialization failure');
          }
        },
      );

      await tester.tap(find.text('Retry Recovery'));
      await tester.pumpAndSettle();

      expect(retryCount, 1);
      expect(initializationCount, 1);

      expect(find.textContaining('could not be initialized'), findsOneWidget);

      expect(find.text('Retry Recovery'), findsOneWidget);

      await tester.tap(find.text('Retry Recovery'));
      await tester.pumpAndSettle();

      expect(retryCount, 2);
      expect(initializationCount, 2);

      expect(find.text('Startup Completed'), findsOneWidget);
    },
  );

  testWidgets(
    'Controller integration opens customer app only after cart initialization',
    (tester) async {
      var recoveryAttempts = 0;
      var cartInitializations = 0;

      final cartCompleter = Completer<void>();

      final controller = CheckoutStartupController(
        recover: () async {
          recoveryAttempts++;

          if (recoveryAttempts == 1) {
            return blockedResult;
          }

          return recoveredResult;
        },
        initializeCart: () async {
          cartInitializations++;
          await cartCompleter.future;
        },
      );

      final initialResult = await controller.start();

      expect(initialResult.status, CheckoutRecoveryExecutionStatus.blocked);

      expect(controller.isReady, isFalse);

      await tester.pumpWidget(
        MaterialApp(
          home: StatefulBuilder(
            builder: (context, setState) {
              if (controller.isReady) {
                return const Scaffold(
                  body: Center(child: Text('Customer App Ready')),
                );
              }

              return CheckoutRecoveryGateScreen(
                initialResult: initialResult,
                retryRecovery: controller.retryRecovery,
                onRecoveryCompleted: () async {
                  await controller.completeStartup();

                  if (!context.mounted) return;

                  setState(() {});
                },
              );
            },
          ),
        ),
      );

      expect(find.text('Checkout Recovery Required'), findsOneWidget);

      expect(find.text('Customer App Ready'), findsNothing);

      await tester.tap(find.text('Retry Recovery'));
      await tester.pump();

      // Recovery may succeed, but the cart is still loading.
      expect(recoveryAttempts, 2);
      expect(cartInitializations, 1);
      expect(controller.isReady, isFalse);

      expect(find.text('Customer App Ready'), findsNothing);

      cartCompleter.complete();
      await tester.pumpAndSettle();

      expect(controller.isReady, isTrue);

      expect(find.text('Customer App Ready'), findsOneWidget);

      expect(find.text('Checkout Recovery Required'), findsNothing);
    },
  );
}
