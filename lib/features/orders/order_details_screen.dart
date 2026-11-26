import 'package:flutter/material.dart';

import '../../core/widgets/site_layout.dart';

import '../../models/combo_offer.dart';
import '../../models/customer_order.dart';
import '../../models/order_item.dart';
import '../payment/order_payment_status.dart';
import 'order_number.dart';
import 'order_status_labels.dart';
import '../../core/widgets/page_app_bar.dart';

/// One order (owner request 2026-11-26: everything on one screen). A
/// computer shows the products on the left and delivery and payment on
/// the right; a phone shows the same cards one under the other.
class OrderDetailsScreen extends StatelessWidget {
  final CustomerOrder order;

  const OrderDetailsScreen({super.key, required this.order});

  static const Color _brandGreen = Color(0xFF82B440);
  static const Color _line = Color(0xFFE3EAD6);

  String _formatDate(DateTime date) {
    final local = date.toLocal();

    final day = local.day.toString().padLeft(2, '0');
    final month = local.month.toString().padLeft(2, '0');
    final year = local.year;

    final hour = local.hour.toString().padLeft(2, '0');
    final minute = local.minute.toString().padLeft(2, '0');

    return '$day/$month/$year  $hour:$minute';
  }

  /// "Fri, 27 Nov" for a delivery day (YYYY-MM-DD).
  static String _dayText(String iso) {
    final d = DateTime.tryParse(iso);
    if (d == null) return iso;
    const days = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
    const months = [
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', //
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
    ];
    return '${days[d.weekday - 1]}, ${d.day} ${months[d.month - 1]}';
  }

  String _formatFulfillment(FulfillmentMethod method) {
    switch (method) {
      case FulfillmentMethod.delivery:
        return 'Home Delivery';
      case FulfillmentMethod.pickup:
        return 'Store Pickup';
    }
  }

  String _formatPayment(OrderPaymentMethod method) {
    switch (method) {
      case OrderPaymentMethod.online:
        return 'Online Payment';
      case OrderPaymentMethod.cashOnDelivery:
        return 'Cash on Delivery / Pickup';
    }
  }

  /// A white card with a small heading.
  Widget _card(String title, List<Widget> children, {Key? key}) {
    return Container(
      key: key,
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 6),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: _line),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w700,
              color: Color(0xFF4F7A1F),
              letterSpacing: 0.3,
            ),
          ),
          const SizedBox(height: 8),
          ...children,
        ],
      ),
    );
  }

  Widget _detailRow(String label, String value, {bool strong = false}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            flex: 2,
            child: Text(label, style: const TextStyle(color: Colors.black54)),
          ),
          Expanded(
            flex: 3,
            child: Text(
              value,
              textAlign: TextAlign.end,
              style: TextStyle(
                fontWeight: strong ? FontWeight.w800 : FontWeight.w600,
                fontSize: strong ? 15 : null,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildOrderItem(OrderItem item) {
    const grey = TextStyle(color: Colors.black54, fontSize: 13);
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(
            Icons.shopping_basket_outlined,
            color: _brandGreen,
            size: 22,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Wrap(
                  spacing: 6,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    Text(
                      item.productName,
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                    if (isComboProductId(item.productId))
                      const Text(
                        'Combo offer',
                        style: TextStyle(
                          color: Color(0xFFD14A6E),
                          fontWeight: FontWeight.w700,
                          fontSize: 12,
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 2),
                Wrap(
                  spacing: 10,
                  children: [
                    Text(
                      'Quantity: ${item.quantity} × ${item.unit}',
                      style: grey,
                    ),
                    Text(
                      'Unit Price: ₹${item.unitPrice.toStringAsFixed(2)}',
                      style: grey,
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Text(
            '₹${item.totalPrice.toStringAsFixed(2)}',
            style: const TextStyle(fontWeight: FontWeight.bold),
          ),
        ],
      ),
    );
  }

  /// The order number, when it was placed and comes, and its status.
  Widget _header() {
    final day = order.deliveryDate;
    return Container(
      key: const Key('order-details-header'),
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: _line),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                OrderNumberText(
                  orderId: order.id,
                  style: const TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  [
                    'Placed ${_formatDate(order.createdAt)}',
                    if (day != null) 'Delivery ${_dayText(day)}',
                  ].join(' · '),
                  style: const TextStyle(color: Colors.black54, fontSize: 13),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          StatusChip(deliveryLabel(order.status)),
        ],
      ),
    );
  }

  Widget _products() =>
      _card('ORDERED PRODUCTS', key: const Key('order-details-products'), [
        ...order.items.map(_buildOrderItem),
        const Divider(height: 12),
        _detailRow('Total Quantity', '${order.totalQuantity}'),
        _detailRow(
          'Product Subtotal',
          '₹${order.subtotal.toStringAsFixed(2)}',
          strong: true,
        ),
      ]);

  Widget _delivery() {
    final notes = order.notes?.trim();
    return _card(
      'DELIVERY / PICKUP',
      key: const Key('order-details-delivery'),
      [
        _detailRow('Method', _formatFulfillment(order.fulfillmentMethod)),
        if (order.fulfillmentMethod == FulfillmentMethod.delivery) ...[
          _detailRow(
            'Recipient',
            [
              order.recipientName ?? 'Not recorded',
              if (order.recipientPhone != null) order.recipientPhone!,
            ].join(' · '),
          ),
          _detailRow('Address', order.deliveryAddress ?? 'Not available'),
        ],
        if (notes != null && notes.isNotEmpty)
          _detailRow('Instructions', notes),
      ],
    );
  }

  Widget _payment() =>
      _card('PAYMENT INFORMATION', key: const Key('order-details-payment'), [
        _detailRow('Method', _formatPayment(order.paymentMethod)),
        if (order.paymentMethod == OrderPaymentMethod.online)
          OrderPaymentStatusView(order: order),
      ]);

  @override
  Widget build(BuildContext context) {
    return SiteScaffold(
      appBar: PageAppBar(title: const Text('Order Details')),
      body: LayoutBuilder(
        builder: (context, constraints) {
          final wide = constraints.maxWidth >= 760;
          return SingleChildScrollView(
            padding: const EdgeInsets.all(12),
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 1000),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _header(),
                    const SizedBox(height: 10),
                    if (wide)
                      Row(
                        key: const Key('order-details-wide'),
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(flex: 3, child: _products()),
                          const SizedBox(width: 10),
                          Expanded(
                            flex: 2,
                            child: Column(
                              children: [
                                _delivery(),
                                const SizedBox(height: 10),
                                _payment(),
                              ],
                            ),
                          ),
                        ],
                      )
                    else ...[
                      _products(),
                      const SizedBox(height: 10),
                      _delivery(),
                      const SizedBox(height: 10),
                      _payment(),
                    ],
                    const SizedBox(height: 8),
                    const Text(
                      'Product subtotal excludes any delivery charges, '
                      'discounts or taxes.',
                      style: TextStyle(color: Colors.black45, fontSize: 12),
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}
