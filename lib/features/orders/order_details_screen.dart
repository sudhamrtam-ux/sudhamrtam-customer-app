import 'package:flutter/material.dart';

import '../../core/widgets/site_layout.dart';
import '../checkout/order_destination.dart';

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
  static const Color _line = Color(0xFFD6E0C8);
  static const Color _heading = Color(0xFF4F7A1F);

  static const _shadow = [
    BoxShadow(color: Color(0x0F2F4A14), blurRadius: 12, offset: Offset(0, 4)),
  ];

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

  /// A white card with a border, an icon and heading, and a line under
  /// the heading (owner request 2026-11-26: proper borders).
  Widget _card(String title, IconData icon, List<Widget> children, {Key? key}) {
    return Container(
      key: key,
      width: double.infinity,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: _line),
        boxShadow: _shadow,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: double.infinity,
            padding: const EdgeInsets.fromLTRB(14, 10, 14, 10),
            decoration: const BoxDecoration(
              color: Color(0xFFF6F9F1),
              borderRadius: BorderRadius.vertical(top: Radius.circular(14)),
              border: Border(bottom: BorderSide(color: _line)),
            ),
            child: Row(
              children: [
                Icon(icon, size: 18, color: _heading),
                const SizedBox(width: 8),
                Flexible(
                  child: Text(
                    title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: _heading,
                      letterSpacing: 0.3,
                    ),
                  ),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 12, 14, 6),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: children,
            ),
          ),
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
        boxShadow: _shadow,
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

  Widget _products() => _card(
    'ORDERED PRODUCTS',
    Icons.shopping_basket_outlined,
    key: const Key('order-details-products'),
    [
      ...order.items.map(_buildOrderItem),
      const Divider(height: 12),
      _detailRow('Total Quantity', '${order.totalQuantity}'),
      _detailRow(
        'Product Subtotal',
        '₹${order.subtotal.toStringAsFixed(2)}',
        strong: true,
      ),
    ],
  );

  Widget _delivery() {
    final notes = order.notes?.trim();
    return _card(
      'DELIVERY & BILLING',
      Icons.local_shipping_outlined,
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
        // Billed to (owner request 2026-11-26).
        if (order.fulfillmentMethod == FulfillmentMethod.delivery)
          _detailRow(
            'Billed to',
            order.billedElsewhere
                ? [
                    [
                      order.billingName ?? '',
                      if (order.billingPhone != null) order.billingPhone!,
                    ].where((p) => p.isNotEmpty).join(' · '),
                    order.billingAddress!,
                  ].join('\n')
                : 'Same as delivery address',
          ),
      ],
    );
  }

  Widget _payment() => _card(
    'PAYMENT INFORMATION',
    Icons.account_balance_wallet_outlined,
    key: const Key('order-details-payment'),
    [
      // With a server: the method, status and Pay online from there
      // (a Cash on Delivery order can be paid online later).
      if (OrderDestination.server == null)
        _detailRow('Method', _formatPayment(order.paymentMethod))
      else
        OrderPaymentStatusView(order: order),
    ],
  );

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
