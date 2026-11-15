import 'package:flutter/material.dart';

import '../../models/combo_offer.dart';
import '../../models/customer_order.dart';
import '../../models/order_item.dart';
import '../payment/order_payment_status.dart';
import 'order_status_labels.dart';
import '../../core/widgets/page_app_bar.dart';

class OrderDetailsScreen extends StatelessWidget {
  final CustomerOrder order;

  const OrderDetailsScreen({super.key, required this.order});

  static const Color _brandGreen = Color(0xFF82B440);

  String _formatDate(DateTime date) {
    final local = date.toLocal();

    final day = local.day.toString().padLeft(2, '0');
    final month = local.month.toString().padLeft(2, '0');
    final year = local.year;

    final hour = local.hour.toString().padLeft(2, '0');
    final minute = local.minute.toString().padLeft(2, '0');

    return '$day/$month/$year  $hour:$minute';
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

  Widget _sectionTitle(String title) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Text(
        title,
        style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
      ),
    );
  }

  Widget _detailRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
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
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildOrderItem(OrderItem item) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(
            Icons.shopping_basket_outlined,
            color: _brandGreen,
            size: 28,
          ),

          const SizedBox(width: 12),

          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
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
                    ),
                  ),

                const SizedBox(height: 4),

                Text(
                  'Quantity: ${item.quantity} × ${item.unit}',
                  style: const TextStyle(color: Colors.black54),
                ),

                const SizedBox(height: 4),

                Text(
                  'Unit Price: ₹${item.unitPrice.toStringAsFixed(2)}',
                  style: const TextStyle(color: Colors.black54),
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: PageAppBar(title: const Text('Order Details')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // ==================================
          // ORDER INFORMATION
          // ==================================

          _sectionTitle('Order Information'),

          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Order #${order.id}',
                    style: const TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.bold,
                    ),
                  ),

                  const SizedBox(height: 16),

                  _detailRow('Order Date', _formatDate(order.createdAt)),

                  const Divider(),

                  const SizedBox(height: 8),

                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text(
                        'Delivery Status',
                        style: TextStyle(fontWeight: FontWeight.w600),
                      ),

                      StatusChip(deliveryLabel(order.status)),
                    ],
                  ),
                ],
              ),
            ),
          ),

          const SizedBox(height: 24),

          // ==================================
          // ORDERED PRODUCTS
          // ==================================
          _sectionTitle('Ordered Products'),

          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                children: [
                  ...order.items.map(_buildOrderItem),

                  const Divider(),

                  _detailRow('Total Quantity', '${order.totalQuantity}'),

                  _detailRow(
                    'Product Subtotal',
                    '₹${order.subtotal.toStringAsFixed(2)}',
                  ),
                ],
              ),
            ),
          ),

          const SizedBox(height: 24),

          // ==================================
          // FULFILLMENT
          // ==================================
          _sectionTitle('Delivery / Pickup'),

          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                children: [
                  _detailRow(
                    'Fulfillment Method',
                    _formatFulfillment(order.fulfillmentMethod),
                  ),

                  if (order.fulfillmentMethod ==
                      FulfillmentMethod.delivery) ...[
                    _detailRow(
                      'Recipient',
                      order.recipientName ?? 'Not recorded',
                    ),
                    _detailRow('Phone', order.recipientPhone ?? 'Not recorded'),
                    _detailRow(
                      'Delivery Address',
                      order.deliveryAddress ?? 'Not available',
                    ),
                  ],
                ],
              ),
            ),
          ),

          const SizedBox(height: 24),

          // ==================================
          // PAYMENT
          // ==================================
          _sectionTitle('Payment Information'),

          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                children: [
                  _detailRow(
                    'Payment Method',
                    _formatPayment(order.paymentMethod),
                  ),
                  if (order.paymentMethod == OrderPaymentMethod.online)
                    OrderPaymentStatusView(order: order),
                ],
              ),
            ),
          ),

          // ==================================
          // CUSTOMER NOTES
          // ==================================
          if (order.notes != null && order.notes!.trim().isNotEmpty) ...[
            const SizedBox(height: 24),

            _sectionTitle('Delivery Instructions'),

            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Text(order.notes!),
              ),
            ),
          ],

          const SizedBox(height: 24),

          // ==================================
          // INFORMATION NOTICE
          // ==================================
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: const Color(0xFFF5F8F0),
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(Icons.info_outline, color: _brandGreen),
                SizedBox(width: 12),
                Expanded(
                  child: Text(
                    'This screen displays saved order details. '
                    'Product subtotal excludes any delivery '
                    'charges, discounts, or taxes.',
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: 24),
        ],
      ),
    );
  }
}
