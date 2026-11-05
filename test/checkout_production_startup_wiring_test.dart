import 'dart:async';

import 'package:flutter_test/flutter_test.dart';

import 'package:sudhamrtam_customer_app/app/checkout_startup_controller.dart';
import 'package:sudhamrtam_customer_app/app/sudhamrtam_app.dart';
import 'package:sudhamrtam_customer_app/database/checkout_recovery_executor.dart';
import 'package:sudhamrtam_customer_app/features/checkout/checkout_recovery_gate_screen.dart';
import 'package:sudhamrtam_customer_app/main.dart' as application;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const blockedResult = CheckoutRecoveryExecutionResult(
    status: CheckoutRecoveryExecutionStatus.blocked,
    orderId: 'startup-test-order',
    message: 'Checkout recovery is required.',
  );

  const recoveredResult = CheckoutRecoveryExecutionResult(
    status: CheckoutRecoveryExecutionStatus.recovered,
    orderId: 'startup-test-order',
    message: 'Checkout recovery completed.',
  );

  testWidgets(
    'Production recovery app remains blocked until cart initialization',
    (tester) async {
      final cartCompleter = Completer<void>();

      var recoveryAttempts = 0;
      var cartInitializations = 0;

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

      await tester.pumpWidget(
        application.SudhamrtamRecoveryApp(
          initialResult: initialResult,
          startupController: controller,
        ),
      );

      expect(find.byType(CheckoutRecoveryGateScreen), findsOneWidget);

      expect(find.byType(SudhamrtamApp), findsNothing);

      await tester.tap(find.text('Retry Recovery'));
      await tester.pump();

      expect(recoveryAttempts, 2);
      expect(cartInitializations, 1);

      expect(controller.isReady, isFalse);

      expect(find.byType(CheckoutRecoveryGateScreen), findsOneWidget);

      expect(find.byType(SudhamrtamApp), findsNothing);

      cartCompleter.complete();

      await tester.pumpAndSettle();

      expect(controller.isReady, isTrue);

      expect(find.byType(SudhamrtamApp), findsOneWidget);

      expect(find.byType(CheckoutRecoveryGateScreen), findsNothing);
    },
  );

  testWidgets('Production recovery app keeps gate visible after failed retry', (
    tester,
  ) async {
    var recoveryAttempts = 0;
    var cartInitializations = 0;

    final controller = CheckoutStartupController(
      recover: () async {
        recoveryAttempts++;
        return blockedResult;
      },
      initializeCart: () async {
        cartInitializations++;
      },
    );

    final initialResult = await controller.start();

    await tester.pumpWidget(
      application.SudhamrtamRecoveryApp(
        initialResult: initialResult,
        startupController: controller,
      ),
    );

    await tester.tap(find.text('Retry Recovery'));
    await tester.pumpAndSettle();

    expect(recoveryAttempts, 2);
    expect(cartInitializations, 0);
    expect(controller.isReady, isFalse);

    expect(find.byType(CheckoutRecoveryGateScreen), findsOneWidget);

    expect(find.byType(SudhamrtamApp), findsNothing);
  });

  testWidgets('Production recovery app displays cart initialization failure', (
    tester,
  ) async {
    var recoveryAttempts = 0;
    var cartInitializations = 0;

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
        throw StateError('Simulated cart initialization failure');
      },
    );

    final initialResult = await controller.start();

    await tester.pumpWidget(
      application.SudhamrtamRecoveryApp(
        initialResult: initialResult,
        startupController: controller,
      ),
    );

    await tester.tap(find.text('Retry Recovery'));
    await tester.pumpAndSettle();

    expect(recoveryAttempts, 2);
    expect(cartInitializations, 1);
    expect(controller.isReady, isFalse);

    expect(find.byType(CheckoutRecoveryGateScreen), findsOneWidget);

    expect(find.byType(SudhamrtamApp), findsNothing);

    expect(find.textContaining('could not be initialized'), findsOneWidget);

    expect(find.text('Retry Recovery'), findsOneWidget);
  });
}
