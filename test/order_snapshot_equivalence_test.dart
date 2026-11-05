import 'package:flutter_test/flutter_test.dart';

import 'package:sudhamrtam_customer_app/features/checkout/order_snapshot_equivalence.dart';
import 'package:sudhamrtam_customer_app/models/customer_order.dart';
import 'package:sudhamrtam_customer_app/models/order_item.dart';

void main() {
  final createdAt = DateTime.utc(2026, 11, 5, 8, 30);

  OrderItem item({
    String productId = 'cow-milk',
    String productName = 'Cow Milk',
    String unit = '1 L',
    int quantity = 2,
    double unitPrice = 80.0,
  }) {
    return OrderItem(
      productId: productId,
      productName: productName,
      unit: unit,
      quantity: quantity,
      unitPrice: unitPrice,
    );
  }

  CustomerOrder order({
    String id = 'test-order-001',
    DateTime? timestamp,
    List<OrderItem>? items,
    FulfillmentMethod fulfillment = FulfillmentMethod.delivery,
    OrderPaymentMethod payment = OrderPaymentMethod.cashOnDelivery,
    OrderStatus status = OrderStatus.pending,
    String? address = 'Kukatpally, Hyderabad',
    String? notes = 'Morning delivery',
  }) {
    return CustomerOrder(
      id: id,
      createdAt: timestamp ?? createdAt,
      items: items ?? [item()],
      fulfillmentMethod: fulfillment,
      paymentMethod: payment,
      status: status,
      deliveryAddress: fulfillment == FulfillmentMethod.delivery
          ? address
          : null,
      notes: notes,
    );
  }

  test('Identical order snapshots match', () {
    expect(OrderSnapshotEquivalence.matches(order(), order()), isTrue);
  });

  test('Different order IDs are rejected', () {
    expect(
      OrderSnapshotEquivalence.matches(order(), order(id: 'different-order')),
      isFalse,
    );
  });

  test('Different creation timestamps are rejected', () {
    expect(
      OrderSnapshotEquivalence.matches(
        order(),
        order(timestamp: createdAt.add(const Duration(seconds: 1))),
      ),
      isFalse,
    );
  });

  test('Different quantities are rejected', () {
    expect(
      OrderSnapshotEquivalence.matches(
        order(),
        order(items: [item(quantity: 3)]),
      ),
      isFalse,
    );
  });

  test('Different prices are rejected', () {
    expect(
      OrderSnapshotEquivalence.matches(
        order(),
        order(items: [item(unitPrice: 90)]),
      ),
      isFalse,
    );
  });

  test('Different product details are rejected', () {
    expect(
      OrderSnapshotEquivalence.matches(
        order(),
        order(items: [item(productName: 'Buffalo Milk')]),
      ),
      isFalse,
    );
  });

  test('Different payment methods are rejected', () {
    expect(
      OrderSnapshotEquivalence.matches(
        order(),
        order(payment: OrderPaymentMethod.online),
      ),
      isFalse,
    );
  });

  test('Different delivery addresses are rejected', () {
    expect(
      OrderSnapshotEquivalence.matches(
        order(),
        order(address: 'Miyapur, Hyderabad'),
      ),
      isFalse,
    );
  });

  test('Different delivery instructions are rejected', () {
    expect(
      OrderSnapshotEquivalence.matches(
        order(),
        order(notes: 'Leave at reception'),
      ),
      isFalse,
    );
  });

  test('Different fulfillment methods are rejected', () {
    expect(
      OrderSnapshotEquivalence.matches(
        order(),
        order(fulfillment: FulfillmentMethod.pickup, notes: 'Morning delivery'),
      ),
      isFalse,
    );
  });

  test('Order status changes do not invalidate snapshot', () {
    expect(
      OrderSnapshotEquivalence.matches(
        order(),
        order(status: OrderStatus.confirmed),
      ),
      isTrue,
    );
  });

  test('Item order does not affect equivalence', () {
    final milk = item();
    final honey = item(
      productId: 'honey',
      productName: 'Raw Honey',
      unit: '500 g',
      quantity: 1,
      unitPrice: 350,
    );

    expect(
      OrderSnapshotEquivalence.matches(
        order(items: [milk, honey]),
        order(items: [honey, milk]),
      ),
      isTrue,
    );
  });

  test('Duplicate product IDs are rejected', () {
    expect(
      OrderSnapshotEquivalence.matches(
        order(items: [item(), item()]),
        order(items: [item(), item()]),
      ),
      isFalse,
    );
  });

  test('Invalid quantities are rejected', () {
    expect(
      OrderSnapshotEquivalence.matches(
        order(items: [item(quantity: 101)]),
        order(items: [item(quantity: 101)]),
      ),
      isFalse,
    );
  });
  test('Non-finite prices are rejected', () {
    expect(
      OrderSnapshotEquivalence.matches(
        order(items: [item(unitPrice: double.infinity)]),
        order(items: [item(unitPrice: double.infinity)]),
      ),
      isFalse,
    );
  });

  test('SQLite-style serialization round trip preserves equivalence', () {
    final original = order();

    final restoredItems = original.items
        .map((entry) => OrderItem.fromMap(entry.toMap()))
        .toList();

    final restored = CustomerOrder.fromMap(
      original.toMap(),
      items: restoredItems,
    );

    expect(OrderSnapshotEquivalence.matches(original, restored), isTrue);
  });
}
