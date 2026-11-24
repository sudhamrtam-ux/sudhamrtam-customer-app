import 'package:flutter/material.dart';

import '../../models/customer_order.dart';
import '../../services/order_api_client.dart';

/// A short coloured label, e.g. "Payment made" or "Delivery pending".
class StatusLabel {
  final String text;
  final Color color;
  final IconData icon;

  const StatusLabel(this.text, this.color, this.icon);
}

const _green = Color(0xFF4E8A1E);

/// Where the order is on its way to the customer.
StatusLabel deliveryLabel(OrderStatus status) {
  switch (status) {
    case OrderStatus.pending:
    case OrderStatus.confirmed:
    case OrderStatus.preparing:
      return const StatusLabel(
        'Delivery pending',
        Colors.orange,
        Icons.schedule_outlined,
      );
    case OrderStatus.outForDelivery:
      return const StatusLabel(
        'Out for delivery',
        Colors.deepPurple,
        Icons.local_shipping_outlined,
      );
    case OrderStatus.readyForPickup:
      return const StatusLabel(
        'Ready for pickup',
        Colors.deepPurple,
        Icons.storefront_outlined,
      );
    case OrderStatus.delivered:
      return const StatusLabel('Delivered', _green, Icons.check_circle_outline);
    case OrderStatus.pickedUp:
      return const StatusLabel('Picked up', _green, Icons.check_circle_outline);
    case OrderStatus.notDelivered:
      return const StatusLabel(
        'Not delivered',
        Color(0xFFE65100),
        Icons.error_outline,
      );
    case OrderStatus.cancelled:
      return const StatusLabel('Cancelled', Colors.red, Icons.cancel_outlined);
  }
}

/// Whether the order is paid. [server] is the server's view when
/// known; otherwise only the payment method is shown.
StatusLabel paymentLabel(CustomerOrder order, OrderPaymentStatus? server) {
  if (server != null) {
    if (server.isPaid) {
      return const StatusLabel('Payment made', _green, Icons.verified_outlined);
    }
    if (server.isPaidByUpi) {
      return const StatusLabel('Paid by UPI', _green, Icons.verified_outlined);
    }
    if (server.isAwaitingPayment) {
      return const StatusLabel(
        'Payment pending',
        Colors.orange,
        Icons.hourglass_bottom,
      );
    }
    if (server.isCancelledUnpaid) {
      return const StatusLabel('Not paid', Colors.red, Icons.money_off);
    }
    return const StatusLabel(
      'Cash on Delivery',
      Colors.black87,
      Icons.payments_outlined,
    );
  }

  return order.paymentMethod == OrderPaymentMethod.online
      ? const StatusLabel(
          'Online payment',
          Colors.black54,
          Icons.credit_card_outlined,
        )
      : const StatusLabel(
          'Cash on Delivery',
          Colors.black87,
          Icons.payments_outlined,
        );
}

/// The order status to show: the server's "cancelled" (by staff, or an
/// unpaid online order after the cut-off), "delivered" and "not
/// delivered" win over the status saved on the phone.
OrderStatus effectiveStatus(CustomerOrder order, OrderPaymentStatus? server) {
  switch (server?.orderStatus) {
    case 'cancelled':
      return OrderStatus.cancelled;
    case 'delivered':
      return order.fulfillmentMethod == FulfillmentMethod.pickup
          ? OrderStatus.pickedUp
          : OrderStatus.delivered;
    case 'not_delivered':
      return OrderStatus.notDelivered;
  }
  return order.status;
}

/// A small pill showing [label].
class StatusChip extends StatelessWidget {
  const StatusChip(this.label, {super.key});

  final StatusLabel label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: label.color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(label.icon, size: 14, color: label.color),
          const SizedBox(width: 4),
          Text(
            label.text,
            style: TextStyle(
              color: label.color,
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}
