import 'product.dart';

/// Represents one product included in a customer order.
///
/// Product details and prices are captured at the time
/// the order is created, so future catalog changes do
/// not alter historical order records.
class OrderItem {
  final String productId;
  final String productName;
  final String unit;
  final int quantity;
  final double unitPrice;

  const OrderItem({
    required this.productId,
    required this.productName,
    required this.unit,
    required this.quantity,
    required this.unitPrice,
  }) : assert(quantity > 0),
       assert(unitPrice >= 0);

  /// Total amount for this order item.
  double get totalPrice => unitPrice * quantity;

  /// Creates an order item from a catalog product.
  factory OrderItem.fromProduct(Product product, {required int quantity}) {
    if (quantity <= 0) {
      throw ArgumentError.value(
        quantity,
        'quantity',
        'Quantity must be greater than zero.',
      );
    }

    if (product.price < 0) {
      throw ArgumentError.value(
        product.price,
        'price',
        'Product price cannot be negative.',
      );
    }

    return OrderItem(
      productId: product.id,
      productName: product.name,
      unit: product.unit,
      quantity: quantity,
      unitPrice: product.price,
    );
  }

  /// Converts an order item into a SQLite-compatible map.
  Map<String, Object?> toMap() {
    return {
      'product_id': productId,
      'product_name': productName,
      'unit': unit,
      'quantity': quantity,
      'unit_price': unitPrice,
    };
  }

  /// Restores an order item from a SQLite record.
  factory OrderItem.fromMap(Map<String, Object?> map) {
    return OrderItem(
      productId: map['product_id'] as String,
      productName: map['product_name'] as String,
      unit: map['unit'] as String,
      quantity: map['quantity'] as int,
      unitPrice: (map['unit_price'] as num).toDouble(),
    );
  }
}
