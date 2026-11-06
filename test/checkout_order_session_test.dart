import 'package:flutter_test/flutter_test.dart';

import 'package:sudhamrtam_customer_app/features/checkout/checkout_order_session.dart';
import 'package:sudhamrtam_customer_app/models/customer_order.dart';
import 'package:sudhamrtam_customer_app/models/order_item.dart';

CustomerOrder createTestOrder(String id) {
  return CustomerOrder(
    id: id,
    createdAt: DateTime.utc(2026, 11, 6),
    items: [
      const OrderItem(
        productId: 'cow_milk',
        productName: 'Cow Milk',
        unit: '1 L',
        quantity: 2,
        unitPrice: 50,
      ),
    ],
    fulfillmentMethod: FulfillmentMethod.pickup,
    paymentMethod: OrderPaymentMethod.cashOnDelivery,
  );
}

void main() {
  CustomerOrder? durablePending;
  late int prepareCalls;
  late CheckoutOrderSession session;

  CustomerOrder Function() preparer(String id) {
    return () {
      prepareCalls++;
      return createTestOrder(id);
    };
  }

  setUp(() {
    durablePending = null;
    prepareCalls = 0;
    session = CheckoutOrderSession(loadPendingOrder: () async => durablePending);
  });

  test('Prepares a new order when nothing is unresolved', () async {
    final order = await session.resolveOrder(
      isRecoveryLocked: false,
      prepare: preparer('order-1'),
    );

    expect(order.id, 'order-1');
    expect(prepareCalls, 1);
    expect(session.currentOrder?.id, 'order-1');
  });

  test('Reuses the same order while recovery lock is active', () async {
    await session.resolveOrder(
      isRecoveryLocked: false,
      prepare: preparer('order-1'),
    );

    final retry = await session.resolveOrder(
      isRecoveryLocked: true,
      prepare: preparer('order-2'),
    );

    expect(retry.id, 'order-1');
    expect(prepareCalls, 1);
  });

  test('Durable pending order wins over any in-session order', () async {
    await session.resolveOrder(
      isRecoveryLocked: false,
      prepare: preparer('order-1'),
    );

    durablePending = createTestOrder('durable-order');

    final retry = await session.resolveOrder(
      isRecoveryLocked: false,
      prepare: preparer('order-2'),
    );

    expect(retry.id, 'durable-order');
    expect(session.currentOrder?.id, 'durable-order');
    expect(prepareCalls, 1);
  });

  test('Durable pending order is reused by a new screen session', () async {
    durablePending = createTestOrder('durable-order');

    final freshSession = CheckoutOrderSession(
      loadPendingOrder: () async => durablePending,
    );

    final order = await freshSession.resolveOrder(
      isRecoveryLocked: false,
      prepare: preparer('order-new'),
    );

    expect(order.id, 'durable-order');
    expect(prepareCalls, 0);
  });

  test(
    'Prepares a fresh order when the earlier attempt never locked the cart',
    () async {
      await session.resolveOrder(
        isRecoveryLocked: false,
        prepare: preparer('order-1'),
      );

      final next = await session.resolveOrder(
        isRecoveryLocked: false,
        prepare: preparer('order-2'),
      );

      expect(next.id, 'order-2');
      expect(prepareCalls, 2);
    },
  );

  test('Completed order is forgotten; other IDs are ignored', () async {
    await session.resolveOrder(
      isRecoveryLocked: false,
      prepare: preparer('order-1'),
    );

    session.markCompleted('other-order');
    expect(session.currentOrder?.id, 'order-1');

    session.markCompleted('order-1');
    expect(session.currentOrder, isNull);
  });

  test('Pending lookup failure is not swallowed', () async {
    final failingSession = CheckoutOrderSession(
      loadPendingOrder: () async => throw StateError('SQLite unavailable'),
    );

    await expectLater(
      failingSession.resolveOrder(
        isRecoveryLocked: false,
        prepare: preparer('order-1'),
      ),
      throwsStateError,
    );

    expect(prepareCalls, 0);
  });
}
