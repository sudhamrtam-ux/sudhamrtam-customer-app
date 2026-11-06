import 'order_item.dart';

/// How the customer receives the order.
enum FulfillmentMethod { delivery, pickup }

/// Customer's selected payment method.
enum OrderPaymentMethod { online, cashOnDelivery }

/// Current lifecycle status of an order.
enum OrderStatus {
  pending,
  confirmed,
  preparing,
  outForDelivery,
  readyForPickup,
  delivered,
  pickedUp,
  cancelled,
}

/// Represents a Sudhamrtam customer order.
///
/// This model holds order data only.
/// Database storage and payment processing will be
/// implemented in later steps.
class CustomerOrder {
  final String id;
  final DateTime createdAt;
  final List<OrderItem> items;
  final FulfillmentMethod fulfillmentMethod;
  final OrderPaymentMethod paymentMethod;
  final OrderStatus status;

  // Required for delivery orders.
  final String? deliveryAddress;

  // Delivery contact captured at checkout (schema v8).
  // Null for pickup orders and for delivery orders
  // saved before v8.
  final String? recipientName;
  final String? recipientPhone;

  // Optional customer instructions.
  final String? notes;

  CustomerOrder({
    required this.id,
    required this.createdAt,
    required List<OrderItem> items,
    required this.fulfillmentMethod,
    required this.paymentMethod,
    this.status = OrderStatus.pending,
    this.deliveryAddress,
    this.recipientName,
    this.recipientPhone,
    this.notes,
  }) : items = List<OrderItem>.unmodifiable(items) {
    if (id.trim().isEmpty) {
      throw ArgumentError('Order ID cannot be empty.');
    }

    if (this.items.isEmpty) {
      throw ArgumentError('An order must contain at least one item.');
    }

    if (fulfillmentMethod == FulfillmentMethod.delivery &&
        (deliveryAddress == null || deliveryAddress!.trim().isEmpty)) {
      throw ArgumentError(
        'A delivery address is required for delivery orders.',
      );
    }
  }

  /// Total number of units in this order.
  int get totalQuantity =>
      items.fold<int>(0, (total, item) => total + item.quantity);

  /// Total product value before any delivery charges,
  /// discounts or taxes.
  double get subtotal =>
      items.fold<double>(0.0, (total, item) => total + item.totalPrice);

  /// True if all products have configured positive prices.
  bool get hasValidPrices => items.every((item) => item.unitPrice > 0);

  /// Creates a copy with updated order status.
  CustomerOrder copyWith({OrderStatus? status}) {
    return CustomerOrder(
      id: id,
      createdAt: createdAt,
      items: items,
      fulfillmentMethod: fulfillmentMethod,
      paymentMethod: paymentMethod,
      status: status ?? this.status,
      deliveryAddress: deliveryAddress,
      recipientName: recipientName,
      recipientPhone: recipientPhone,
      notes: notes,
    );
  }

  /// Converts order information into a database-ready map.
  ///
  /// Order items will be stored in a separate SQLite table.
  Map<String, Object?> toMap() {
    return {
      'id': id,
      'created_at': createdAt.toIso8601String(),
      'fulfillment_method': fulfillmentMethod.name,
      'payment_method': paymentMethod.name,
      'status': status.name,
      'delivery_address': deliveryAddress,
      // Recipient keys are written only when present, so
      // orders without them serialize exactly as before v8.
      // Durable pending payloads are compared byte-for-byte.
      if (recipientName != null) 'recipient_name': recipientName,
      if (recipientPhone != null) 'recipient_phone': recipientPhone,
      'notes': notes,
      'subtotal': subtotal,
    };
  }

  /// Restores an order and its items from stored data.
  factory CustomerOrder.fromMap(
    Map<String, Object?> map, {
    required List<OrderItem> items,
  }) {
    return CustomerOrder(
      id: map['id'] as String,
      createdAt: DateTime.parse(map['created_at'] as String),
      items: items,
      fulfillmentMethod: FulfillmentMethod.values.byName(
        map['fulfillment_method'] as String,
      ),
      paymentMethod: OrderPaymentMethod.values.byName(
        map['payment_method'] as String,
      ),
      status: OrderStatus.values.byName(map['status'] as String),
      deliveryAddress: map['delivery_address'] as String?,
      recipientName: map['recipient_name'] as String?,
      recipientPhone: map['recipient_phone'] as String?,
      notes: map['notes'] as String?,
    );
  }
}
