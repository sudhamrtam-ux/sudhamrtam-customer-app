import '../../models/customer_order.dart';
import '../../models/order_item.dart';

/// Compares the immutable submission details of two orders.
///
/// Intended for checking whether an existing saved order
/// corresponds to the same originally prepared submission.
///
/// Order status is excluded because it can change after
/// the order has been saved.
class OrderSnapshotEquivalence {
  const OrderSnapshotEquivalence._();

  static bool matches(CustomerOrder prepared, CustomerOrder saved) {
    if (prepared.id != saved.id) return false;

    if (!prepared.createdAt.isAtSameMomentAs(saved.createdAt)) {
      return false;
    }

    if (prepared.fulfillmentMethod != saved.fulfillmentMethod) {
      return false;
    }

    if (prepared.paymentMethod != saved.paymentMethod) {
      return false;
    }

    if (prepared.deliveryAddress != saved.deliveryAddress) {
      return false;
    }

    if (prepared.recipientName != saved.recipientName) {
      return false;
    }

    if (prepared.recipientPhone != saved.recipientPhone) {
      return false;
    }

    if (prepared.notes != saved.notes) {
      return false;
    }

    if (!_validItems(prepared.items) || !_validItems(saved.items)) {
      return false;
    }

    if (prepared.items.length != saved.items.length) {
      return false;
    }

    final preparedItems = <String, OrderItem>{};
    final savedItems = <String, OrderItem>{};

    for (final item in prepared.items) {
      if (preparedItems.containsKey(item.productId)) {
        return false;
      }
      preparedItems[item.productId] = item;
    }

    for (final item in saved.items) {
      if (savedItems.containsKey(item.productId)) {
        return false;
      }
      savedItems[item.productId] = item;
    }

    if (preparedItems.length != savedItems.length) {
      return false;
    }

    for (final entry in preparedItems.entries) {
      final savedItem = savedItems[entry.key];

      if (savedItem == null) return false;

      if (!_sameItem(entry.value, savedItem)) {
        return false;
      }
    }

    return true;
  }

  static bool _validItems(List<OrderItem> items) {
    if (items.isEmpty) return false;

    for (final item in items) {
      if (item.productId.trim().isEmpty ||
          item.productName.trim().isEmpty ||
          item.unit.trim().isEmpty ||
          item.quantity <= 0 ||
          item.quantity > 100 ||
          !item.unitPrice.isFinite ||
          item.unitPrice <= 0) {
        return false;
      }

      final lineTotal = item.totalPrice;

      if (!lineTotal.isFinite || lineTotal <= 0) {
        return false;
      }
    }

    return true;
  }

  static bool _sameItem(OrderItem a, OrderItem b) {
    return a.productId == b.productId &&
        a.productName == b.productName &&
        a.unit == b.unit &&
        a.quantity == b.quantity &&
        a.unitPrice == b.unitPrice;
  }
}
