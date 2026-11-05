import 'dart:async';

import 'package:flutter_test/flutter_test.dart';

import 'package:sudhamrtam_customer_app/app/checkout_startup_controller.dart';
import 'package:sudhamrtam_customer_app/database/checkout_recovery_executor.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const noRecovery = CheckoutRecoveryExecutionResult(
    status: CheckoutRecoveryExecutionStatus.noRecoveryNeeded,
    orderId: null,
    message: 'No recovery required.',
  );

  const recovered = CheckoutRecoveryExecutionResult(
    status: CheckoutRecoveryExecutionStatus.recovered,
    orderId: 'order-123',
    message: 'Checkout recovered.',
  );

  const awaiting = CheckoutRecoveryExecutionResult(
    status: CheckoutRecoveryExecutionStatus.awaitingSubmission,
    orderId: 'order-123',
    message: 'Order submission is unresolved.',
  );

  const blocked = CheckoutRecoveryExecutionResult(
    status: CheckoutRecoveryExecutionStatus.blocked,
    orderId: 'order-123',
    message: 'Recovery blocked.',
  );

  test('normal startup initializes cart after recovery', () async {
    final events = <String>[];

    final controller = CheckoutStartupController(
      recover: () async {
        events.add('recovery');
        return noRecovery;
      },
      initializeCart: () async {
        events.add('cart');
      },
    );

    final result = await controller.start();

    expect(result.status, CheckoutRecoveryExecutionStatus.noRecoveryNeeded);
    expect(events, ['recovery', 'cart']);
    expect(controller.isReady, isTrue);
    expect(controller.isBusy, isFalse);
  });

  test('unresolved submission prevents cart initialization', () async {
    var cartCalls = 0;

    final controller = CheckoutStartupController(
      recover: () async => awaiting,
      initializeCart: () async {
        cartCalls++;
      },
    );

    final result = await controller.start();

    expect(result.status, CheckoutRecoveryExecutionStatus.awaitingSubmission);
    expect(cartCalls, 0);
    expect(controller.isReady, isFalse);
  });

  test('blocked recovery prevents cart initialization', () async {
    var cartCalls = 0;

    final controller = CheckoutStartupController(
      recover: () async => blocked,
      initializeCart: () async {
        cartCalls++;
      },
    );

    final result = await controller.start();

    expect(result.status, CheckoutRecoveryExecutionStatus.blocked);
    expect(cartCalls, 0);
    expect(controller.isReady, isFalse);
  });

  test('successful retry permits cart initialization', () async {
    var recoveryCalls = 0;
    var cartCalls = 0;

    final controller = CheckoutStartupController(
      recover: () async {
        recoveryCalls++;
        return recoveryCalls == 1 ? awaiting : recovered;
      },
      initializeCart: () async {
        cartCalls++;
      },
    );

    await controller.start();

    expect(controller.isReady, isFalse);
    expect(cartCalls, 0);

    final retryResult = await controller.retryRecovery();

    expect(retryResult.status, CheckoutRecoveryExecutionStatus.recovered);
    expect(cartCalls, 0);

    await controller.completeStartup();

    expect(controller.isReady, isTrue);
    expect(cartCalls, 1);
    expect(recoveryCalls, 2);
  });

  test('cart cannot initialize before successful recovery', () async {
    var cartCalls = 0;

    final controller = CheckoutStartupController(
      recover: () async => blocked,
      initializeCart: () async {
        cartCalls++;
      },
    );

    await controller.start();

    await expectLater(controller.completeStartup(), throwsA(isA<StateError>()));

    expect(cartCalls, 0);
    expect(controller.isReady, isFalse);
  });

  test('cart initialization failure blocks startup', () async {
    final controller = CheckoutStartupController(
      recover: () async => noRecovery,
      initializeCart: () async {
        throw StateError('Simulated cart failure');
      },
    );

    final result = await controller.start();

    expect(result.status, CheckoutRecoveryExecutionStatus.blocked);
    expect(result.message, contains('Shopping cart initialization failed'));
    expect(controller.isReady, isFalse);
    expect(controller.isBusy, isFalse);
  });

  test('cart failure can be retried after recovery', () async {
    var cartCalls = 0;

    final controller = CheckoutStartupController(
      recover: () async => recovered,
      initializeCart: () async {
        cartCalls++;

        if (cartCalls == 1) {
          throw StateError('Temporary cart failure');
        }
      },
    );

    final first = await controller.start();

    expect(first.status, CheckoutRecoveryExecutionStatus.blocked);
    expect(controller.isReady, isFalse);

    final retry = await controller.retryRecovery();

    expect(retry.canContinueNormalStartup, isTrue);

    await controller.completeStartup();

    expect(cartCalls, 2);
    expect(controller.isReady, isTrue);
  });

  test('recovery exception blocks startup', () async {
    var cartCalls = 0;

    final controller = CheckoutStartupController(
      recover: () async {
        throw StateError('Simulated database failure');
      },
      initializeCart: () async {
        cartCalls++;
      },
    );

    final result = await controller.start();

    expect(result.status, CheckoutRecoveryExecutionStatus.blocked);
    expect(result.message, contains('Startup recovery failed'));
    expect(cartCalls, 0);
    expect(controller.isReady, isFalse);
  });

  test('concurrent startup attempts are rejected', () async {
    final completer = Completer<CheckoutRecoveryExecutionResult>();

    var recoveryCalls = 0;
    var cartCalls = 0;

    final controller = CheckoutStartupController(
      recover: () {
        recoveryCalls++;
        return completer.future;
      },
      initializeCart: () async {
        cartCalls++;
      },
    );

    final firstStartup = controller.start();

    expect(controller.isBusy, isTrue);

    await expectLater(controller.start(), throwsA(isA<StateError>()));

    await expectLater(controller.retryRecovery(), throwsA(isA<StateError>()));

    expect(recoveryCalls, 1);

    completer.complete(noRecovery);

    await firstStartup;

    expect(cartCalls, 1);
    expect(controller.isReady, isTrue);
    expect(controller.isBusy, isFalse);
  });

  test('completed startup cannot initialize cart twice', () async {
    var recoveryCalls = 0;
    var cartCalls = 0;

    final controller = CheckoutStartupController(
      recover: () async {
        recoveryCalls++;
        return noRecovery;
      },
      initializeCart: () async {
        cartCalls++;
      },
    );

    await controller.start();
    await controller.start();
    await controller.completeStartup();

    expect(recoveryCalls, 1);
    expect(cartCalls, 1);
    expect(controller.isReady, isTrue);

    await expectLater(controller.retryRecovery(), throwsA(isA<StateError>()));
  });
}
