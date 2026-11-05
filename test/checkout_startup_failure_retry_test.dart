import 'dart:async';

import 'package:flutter_test/flutter_test.dart';

import 'package:sudhamrtam_customer_app/app/checkout_startup_controller.dart';
import 'package:sudhamrtam_customer_app/database/checkout_recovery_executor.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const successfulRecovery = CheckoutRecoveryExecutionResult(
    status: CheckoutRecoveryExecutionStatus.noRecoveryNeeded,
    orderId: null,
    message: 'Recovery completed.',
  );

  const blockedRecovery = CheckoutRecoveryExecutionResult(
    status: CheckoutRecoveryExecutionStatus.blocked,
    orderId: 'test-order-001',
    message: 'Recovery requires investigation.',
  );

  test('Recovery exception blocks startup without initializing cart', () async {
    var cartInitializations = 0;

    final controller = CheckoutStartupController(
      recover: () async {
        throw StateError('Simulated recovery failure');
      },
      initializeCart: () async {
        cartInitializations++;
      },
    );

    final result = await controller.start();

    expect(result.status, CheckoutRecoveryExecutionStatus.blocked);
    expect(controller.isReady, isFalse);
    expect(controller.isBusy, isFalse);
    expect(cartInitializations, 0);
  });

  test('Blocked recovery can succeed on retry', () async {
    var recoveryAttempts = 0;
    var cartInitializations = 0;

    final controller = CheckoutStartupController(
      recover: () async {
        recoveryAttempts++;

        if (recoveryAttempts == 1) {
          return blockedRecovery;
        }

        return successfulRecovery;
      },
      initializeCart: () async {
        cartInitializations++;
      },
    );

    final first = await controller.start();

    expect(first.status, CheckoutRecoveryExecutionStatus.blocked);
    expect(controller.isReady, isFalse);
    expect(cartInitializations, 0);

    final second = await controller.retryRecovery();

    expect(second.canContinueNormalStartup, isTrue);
    expect(controller.isReady, isFalse);
    expect(cartInitializations, 0);

    await controller.completeStartup();

    expect(controller.isReady, isTrue);
    expect(cartInitializations, 1);
    expect(recoveryAttempts, 2);
  });

  test('Cart initialization failure blocks startup', () async {
    var recoveryAttempts = 0;
    var cartInitializations = 0;

    final controller = CheckoutStartupController(
      recover: () async {
        recoveryAttempts++;
        return successfulRecovery;
      },
      initializeCart: () async {
        cartInitializations++;

        if (cartInitializations == 1) {
          throw StateError('Simulated cart load failure');
        }
      },
    );

    final first = await controller.start();

    expect(first.status, CheckoutRecoveryExecutionStatus.blocked);
    expect(controller.isReady, isFalse);
    expect(cartInitializations, 1);

    await expectLater(controller.completeStartup(), throwsStateError);

    // Failed initialization revokes authorization.
    // Recovery must succeed again before another attempt.
    final retry = await controller.retryRecovery();

    expect(retry.canContinueNormalStartup, isTrue);

    await controller.completeStartup();

    expect(controller.isReady, isTrue);
    expect(recoveryAttempts, 2);
    expect(cartInitializations, 2);
  });

  test('Recovery retry failure keeps startup blocked', () async {
    var cartInitializations = 0;

    final controller = CheckoutStartupController(
      recover: () async => blockedRecovery,
      initializeCart: () async {
        cartInitializations++;
      },
    );

    await controller.start();

    final retry = await controller.retryRecovery();

    expect(retry.status, CheckoutRecoveryExecutionStatus.blocked);
    expect(controller.isReady, isFalse);
    expect(cartInitializations, 0);

    await expectLater(controller.completeStartup(), throwsStateError);
  });

  test('Concurrent startup operations are rejected', () async {
    final recoveryCompleter = Completer<CheckoutRecoveryExecutionResult>();

    final controller = CheckoutStartupController(
      recover: () => recoveryCompleter.future,
      initializeCart: () async {},
    );

    final firstStartup = controller.start();

    expect(controller.isBusy, isTrue);

    await expectLater(controller.retryRecovery(), throwsStateError);

    await expectLater(controller.start(), throwsStateError);

    recoveryCompleter.complete(successfulRecovery);

    final result = await firstStartup;

    expect(result.canContinueNormalStartup, isTrue);
    expect(controller.isReady, isTrue);
    expect(controller.isBusy, isFalse);
  });

  test('Concurrent cart initialization is rejected', () async {
    final cartCompleter = Completer<void>();

    final controller = CheckoutStartupController(
      recover: () async => successfulRecovery,
      initializeCart: () => cartCompleter.future,
    );

    final startup = controller.start();

    // Recovery callback completes asynchronously.
    // Allow it to advance to cart initialization.
    await Future<void>.delayed(Duration.zero);

    expect(controller.isBusy, isTrue);

    await expectLater(controller.retryRecovery(), throwsStateError);

    await expectLater(controller.completeStartup(), throwsStateError);

    cartCompleter.complete();
    await startup;

    expect(controller.isReady, isTrue);
    expect(controller.isBusy, isFalse);
  });

  test('Completed startup does not initialize cart twice', () async {
    var cartInitializations = 0;

    final controller = CheckoutStartupController(
      recover: () async => successfulRecovery,
      initializeCart: () async {
        cartInitializations++;
      },
    );

    await controller.start();
    await controller.start();
    await controller.completeStartup();

    expect(controller.isReady, isTrue);
    expect(cartInitializations, 1);

    await expectLater(controller.retryRecovery(), throwsStateError);
  });
}
