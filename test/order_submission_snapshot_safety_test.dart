import 'dart:async';

import 'package:flutter_test/flutter_test.dart';

import 'package:sudhamrtam_customer_app/features/checkout/order_submission_service.dart';
import 'package:sudhamrtam_customer_app/models/customer_order.dart';
import 'package:sudhamrtam_customer_app/models/order_item.dart';

void main() {
  final createdAt = DateTime.utc(2026, 11, 5, 8, 30);

  CustomerOrder makeOrder({
    String id = 'order-001',
    int quantity = 2,
    double unitPrice = 80,
    OrderStatus status = OrderStatus.pending,
  }) {
    return CustomerOrder(
      id: id,
      createdAt: createdAt,
      items: [
        OrderItem(
          productId: 'cow-milk',
          productName: 'Cow Milk',
          unit: '1 L',
          quantity: quantity,
          unitPrice: unitPrice,
        ),
      ],
      fulfillmentMethod: FulfillmentMethod.delivery,
      paymentMethod: OrderPaymentMethod.cashOnDelivery,
      status: status,
      deliveryAddress: 'Kukatpally, Hyderabad',
    );
  }

  test('New order is saved successfully', () async {
    CustomerOrder? saved;
    var saveCount = 0;

    final service = OrderSubmissionService(
      getOrderById: (_) async => saved,
      saveOrder: (order) async {
        saveCount++;
        saved = order;
      },
    );

    final result = await service.submit(makeOrder());

    expect(result.id, 'order-001');
    expect(saveCount, 1);
    expect(service.pendingOrder, isNull);
    expect(service.isSubmitting, isFalse);
  });

  test('Matching existing order is accepted without saving again', () async {
    final prepared = makeOrder();
    final saved = makeOrder(status: OrderStatus.confirmed);

    var saveCount = 0;

    final service = OrderSubmissionService(
      getOrderById: (_) async => saved,
      saveOrder: (_) async {
        saveCount++;
      },
    );

    final result = await service.submit(prepared);

    expect(result.status, OrderStatus.confirmed);
    expect(saveCount, 0);
    expect(service.pendingOrder, isNull);
  });

  test('Existing order with different quantity is rejected', () async {
    final prepared = makeOrder(quantity: 2);
    final saved = makeOrder(quantity: 3);

    var saveCount = 0;

    final service = OrderSubmissionService(
      getOrderById: (_) async => saved,
      saveOrder: (_) async {
        saveCount++;
      },
    );

    await expectLater(service.submit(prepared), throwsStateError);

    expect(saveCount, 0);
    expect(service.pendingOrder, same(prepared));
    expect(service.isSubmitting, isFalse);
  });

  test('Existing order with different price is rejected', () async {
    final prepared = makeOrder(unitPrice: 80);
    final saved = makeOrder(unitPrice: 90);

    final service = OrderSubmissionService(
      getOrderById: (_) async => saved,
      saveOrder: (_) async {},
    );

    await expectLater(service.submit(prepared), throwsStateError);

    expect(service.pendingOrder, same(prepared));
  });

  test('Save error after successful write is safely verified', () async {
    CustomerOrder? saved;
    var saveCount = 0;

    final service = OrderSubmissionService(
      getOrderById: (_) async => saved,
      saveOrder: (order) async {
        saveCount++;
        saved = order;
        throw Exception('Confirmation interrupted');
      },
    );

    final result = await service.submit(makeOrder());

    expect(result.id, 'order-001');
    expect(saveCount, 1);
    expect(service.pendingOrder, isNull);
  });

  test('Mismatched saved order after save error is rejected', () async {
    CustomerOrder? saved;

    final prepared = makeOrder();

    final service = OrderSubmissionService(
      getOrderById: (_) async => saved,
      saveOrder: (_) async {
        saved = makeOrder(quantity: 3);
        throw Exception('Save failed');
      },
    );

    await expectLater(service.submit(prepared), throwsStateError);

    expect(service.pendingOrder, same(prepared));
  });

  test('Failed submission retains original order for retry', () async {
    CustomerOrder? saved;
    var saveAttempts = 0;

    final prepared = makeOrder();

    final service = OrderSubmissionService(
      getOrderById: (_) async => saved,
      saveOrder: (order) async {
        saveAttempts++;

        if (saveAttempts == 1) {
          throw Exception('Temporary storage failure');
        }

        saved = order;
      },
    );

    await expectLater(service.submit(prepared), throwsException);

    expect(service.pendingOrder, same(prepared));

    final result = await service.retryPendingOrder();

    expect(result.id, prepared.id);
    expect(saveAttempts, 2);
    expect(service.pendingOrder, isNull);
  });

  test('Different snapshot cannot replace pending order', () async {
    final prepared = makeOrder(quantity: 2);

    final service = OrderSubmissionService(
      getOrderById: (_) async => null,
      saveOrder: (_) async {
        throw Exception('Storage unavailable');
      },
    );

    await expectLater(service.submit(prepared), throwsException);

    await expectLater(service.submit(makeOrder(quantity: 3)), throwsStateError);

    expect(service.pendingOrder, same(prepared));
  });

  test('Different order ID cannot replace pending order', () async {
    final prepared = makeOrder();

    final service = OrderSubmissionService(
      getOrderById: (_) async => null,
      saveOrder: (_) async {
        throw Exception('Storage unavailable');
      },
    );

    await expectLater(service.submit(prepared), throwsException);

    await expectLater(
      service.submit(makeOrder(id: 'order-002')),
      throwsStateError,
    );

    expect(service.pendingOrder, same(prepared));
  });

  test('Concurrent submissions are rejected', () async {
    final saveCompleter = Completer<void>();

    var saveCount = 0;

    final service = OrderSubmissionService(
      getOrderById: (_) async => null,
      saveOrder: (_) {
        saveCount++;
        return saveCompleter.future;
      },
    );

    final firstSubmission = service.submit(makeOrder());

    await Future<void>.delayed(Duration.zero);

    expect(service.isSubmitting, isTrue);

    await expectLater(service.submit(makeOrder()), throwsStateError);

    saveCompleter.complete();

    await firstSubmission;

    expect(saveCount, 1);
    expect(service.isSubmitting, isFalse);
  });
}
