import 'dart:async';

import 'package:flutter_test/flutter_test.dart';

import 'package:sudhamrtam_customer_app/features/checkout/order_submission_service.dart';
import 'package:sudhamrtam_customer_app/models/customer_order.dart';
import 'package:sudhamrtam_customer_app/models/order_item.dart';

// ==========================================
// TEST ORDER
// ==========================================

CustomerOrder createTestOrder(String id) {
  return CustomerOrder(
    id: id,
    createdAt: DateTime.utc(2026, 11, 5),
    items: [
      const OrderItem(
        productId: 'buffalo-milk',
        productName: 'Buffalo Milk',
        unit: '1 L',
        quantity: 2,
        unitPrice: 100,
      ),
    ],
    fulfillmentMethod: FulfillmentMethod.pickup,
    paymentMethod: OrderPaymentMethod.cashOnDelivery,
  );
}

// ==========================================
// IN-MEMORY ORDER STORAGE
// ==========================================

class FakeOrderStore {
  final Map<String, CustomerOrder> orders = {};

  int saveCalls = 0;
  bool failNextSave = false;
  bool saveThenThrow = false;

  Future<void> saveOrder(CustomerOrder order) async {
    saveCalls++;

    if (failNextSave) {
      failNextSave = false;
      throw StateError('Simulated database failure');
    }

    if (orders.containsKey(order.id)) {
      throw StateError('Duplicate order ID');
    }

    orders[order.id] = order;

    if (saveThenThrow) {
      saveThenThrow = false;
      throw StateError('Simulated lost confirmation');
    }
  }

  Future<CustomerOrder?> getOrderById(String id) async {
    return orders[id];
  }

  OrderSubmissionService createService() {
    return OrderSubmissionService(
      saveOrder: saveOrder,
      getOrderById: getOrderById,
    );
  }
}

// ==========================================
// AUTOMATED TESTS
// ==========================================

void main() {
  group('Sudhamrtam Order Submission', () {
    test('Saves a valid prepared order once', () async {
      final store = FakeOrderStore();
      final service = store.createService();
      final order = createTestOrder('ORDER-001');

      final result = await service.submit(order);

      expect(result.id, order.id);
      expect(store.saveCalls, 1);
      expect(store.orders.length, 1);
      expect(service.isSubmitting, isFalse);
      expect(service.pendingOrder, isNull);
    });

    test('Rejects simultaneous submissions', () async {
      final store = FakeOrderStore();
      final saveStarted = Completer<void>();
      final allowSave = Completer<void>();

      final service = OrderSubmissionService(
        saveOrder: (order) async {
          store.saveCalls++;
          saveStarted.complete();
          await allowSave.future;
          store.orders[order.id] = order;
        },
        getOrderById: store.getOrderById,
      );

      final firstOrder = createTestOrder('ORDER-002');
      final secondOrder = createTestOrder('ORDER-003');

      final firstSubmission = service.submit(firstOrder);

      await saveStarted.future;

      expect(service.isSubmitting, isTrue);

      await expectLater(service.submit(secondOrder), throwsStateError);

      allowSave.complete();

      await firstSubmission;

      expect(store.saveCalls, 1);
      expect(store.orders.length, 1);
      expect(store.orders.containsKey(firstOrder.id), isTrue);
      expect(store.orders.containsKey(secondOrder.id), isFalse);
      expect(service.isSubmitting, isFalse);
    });

    test('Retains the same order after a failed save', () async {
      final store = FakeOrderStore();
      store.failNextSave = true;

      final service = store.createService();
      final order = createTestOrder('ORDER-004');

      await expectLater(service.submit(order), throwsStateError);

      expect(service.pendingOrder?.id, order.id);
      expect(service.isSubmitting, isFalse);
      expect(store.orders, isEmpty);
    });

    test('Retries a failed save with the original ID', () async {
      final store = FakeOrderStore();
      store.failNextSave = true;

      final service = store.createService();
      final order = createTestOrder('ORDER-005');

      await expectLater(service.submit(order), throwsStateError);

      final result = await service.retryPendingOrder();

      expect(result.id, order.id);
      expect(store.saveCalls, 2);
      expect(store.orders.length, 1);
      expect(service.pendingOrder, isNull);
    });

    test('Recognizes an order saved before confirmation failed', () async {
      final store = FakeOrderStore();
      store.saveThenThrow = true;

      final service = store.createService();
      final order = createTestOrder('ORDER-006');

      final result = await service.submit(order);

      expect(result.id, order.id);
      expect(store.saveCalls, 1);
      expect(store.orders.length, 1);
      expect(service.pendingOrder, isNull);
    });

    test('Does not save an already existing order again', () async {
      final store = FakeOrderStore();
      final order = createTestOrder('ORDER-007');

      store.orders[order.id] = order;

      final service = store.createService();

      final result = await service.submit(order);

      expect(result.id, order.id);
      expect(store.saveCalls, 0);
      expect(store.orders.length, 1);
    });

    test('Blocks a different order while a failed order is pending', () async {
      final store = FakeOrderStore();
      store.failNextSave = true;

      final service = store.createService();

      await expectLater(
        service.submit(createTestOrder('ORDER-008')),
        throwsStateError,
      );

      await expectLater(
        service.submit(createTestOrder('ORDER-009')),
        throwsStateError,
      );

      expect(service.pendingOrder?.id, 'ORDER-008');
      expect(store.saveCalls, 1);
    });

    test('Rejects retry when there is no pending order', () async {
      final store = FakeOrderStore();
      final service = store.createService();

      await expectLater(service.retryPendingOrder(), throwsStateError);
    });
  });
}
