import 'package:flutter/material.dart';

import '../../database/order_database_service.dart';
import '../../models/customer_order.dart';
import '../../services/order_api_client.dart';
import '../checkout/order_destination.dart';
import 'order_details_screen.dart';
import 'order_status_labels.dart';
import '../../core/widgets/page_app_bar.dart';

class OrderHistoryScreen extends StatefulWidget {
  OrderHistoryScreen({super.key, OrderApiClient? api})
    : api = api ?? OrderDestination.server;

  /// Payment statuses come from here; null without a server.
  final OrderApiClient? api;

  @override
  State<OrderHistoryScreen> createState() => _OrderHistoryScreenState();
}

class _OrderHistoryScreenState extends State<OrderHistoryScreen> {
  static const Color _brandGreen = Color(0xFF82B440);

  late Future<List<CustomerOrder>> _ordersFuture;

  /// The server's payment status per order; empty if unknown
  /// (no server, offline, or a local test order).
  Map<String, OrderPaymentStatus> _payments = const {};

  @override
  void initState() {
    super.initState();
    _loadOrders();
  }

  void _loadOrders() {
    _ordersFuture = OrderDatabaseService.instance.getAllOrders();
    _loadPayments();
  }

  Future<void> _loadPayments() async {
    final api = widget.api;
    if (api == null) return;
    try {
      final payments = await api.fetchPaymentStatuses();
      if (mounted) setState(() => _payments = payments);
    } catch (_) {
      // Offline: the cards show the payment method instead.
    }
  }

  Future<void> _refreshOrders() async {
    setState(() {
      _loadOrders();
    });

    try {
      await _ordersFuture;
    } catch (_) {
      // Database errors are displayed by FutureBuilder.
    }
  }

  String _formatDate(DateTime date) {
    final local = date.toLocal();

    final day = local.day.toString().padLeft(2, '0');
    final month = local.month.toString().padLeft(2, '0');
    final year = local.year;

    return '$day/$month/$year';
  }

  String _formatFulfillment(FulfillmentMethod method) {
    switch (method) {
      case FulfillmentMethod.delivery:
        return 'Home Delivery';

      case FulfillmentMethod.pickup:
        return 'Store Pickup';
    }
  }

  // ==========================================
  // OPEN ORDER DETAILS
  // ==========================================

  void _openOrderDetails(CustomerOrder order) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (context) => OrderDetailsScreen(order: order),
      ),
    );
  }

  // ==========================================
  // EMPTY ORDER HISTORY
  // ==========================================

  Widget _buildEmptyState() {
    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      children: const [
        SizedBox(height: 120),

        Icon(Icons.receipt_long_outlined, size: 72, color: _brandGreen),

        SizedBox(height: 20),

        Center(
          child: Text(
            'No Orders Yet',
            style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
          ),
        ),

        SizedBox(height: 10),

        Padding(
          padding: EdgeInsets.symmetric(horizontal: 32),
          child: Text(
            'Your order history will appear here '
            'once orders become available.',
            textAlign: TextAlign.center,
            style: TextStyle(color: Colors.black54),
          ),
        ),
      ],
    );
  }

  // ==========================================
  // ORDER HISTORY CARD
  // ==========================================

  Widget _buildOrderCard(CustomerOrder order) {
    final server = _payments[order.id];
    final delivery = deliveryLabel(effectiveStatus(order, server));
    final payment = paymentLabel(order, server);

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      clipBehavior: Clip.antiAlias,

      // Makes the entire order card clickable.
      child: InkWell(
        onTap: () => _openOrderDetails(order),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // ORDER ID
              Text(
                'Order #${order.id}',
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 15,
                ),
              ),

              const SizedBox(height: 10),

              // PAYMENT AND DELIVERY STATUS
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  StatusChip(payment, key: Key('payment_${order.id}')),
                  StatusChip(delivery, key: Key('delivery_${order.id}')),
                ],
              ),

              const SizedBox(height: 12),

              // ORDER DATE
              Text(
                'Date: ${_formatDate(order.createdAt)}',
                style: const TextStyle(color: Colors.black54),
              ),

              const SizedBox(height: 8),

              // TOTAL QUANTITY
              Text('Quantity: ${order.totalQuantity}'),

              const SizedBox(height: 8),

              // FULFILLMENT METHOD
              Text(
                'Fulfillment: '
                '${_formatFulfillment(order.fulfillmentMethod)}',
              ),

              const Divider(height: 28),

              // PRODUCT SUBTOTAL
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text(
                    'Product Subtotal',
                    style: TextStyle(fontWeight: FontWeight.w600),
                  ),

                  Text(
                    '₹${order.subtotal.toStringAsFixed(2)}',
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      color: _brandGreen,
                      fontSize: 16,
                    ),
                  ),
                ],
              ),

              const SizedBox(height: 12),

              // VIEW DETAILS INDICATOR
              const Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  Text(
                    'View Details',
                    style: TextStyle(
                      color: _brandGreen,
                      fontWeight: FontWeight.w600,
                    ),
                  ),

                  SizedBox(width: 4),

                  Icon(Icons.arrow_forward_ios, size: 14, color: _brandGreen),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ==========================================
  // DATABASE ERROR STATE
  // ==========================================

  Widget _buildErrorState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.error_outline, size: 56, color: Colors.orange),

            const SizedBox(height: 16),

            const Text(
              'Unable to Load Orders',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),

            const SizedBox(height: 8),

            const Text('Please try again.', textAlign: TextAlign.center),

            const SizedBox(height: 16),

            FilledButton(onPressed: _refreshOrders, child: const Text('Retry')),
          ],
        ),
      ),
    );
  }

  // ==========================================
  // MAIN SCREEN
  // ==========================================

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: PageAppBar(
        title: const Text('My Orders'),
        actions: [
          IconButton(
            tooltip: 'Refresh orders',
            icon: const Icon(Icons.refresh),
            onPressed: _refreshOrders,
          ),
        ],
      ),

      body: FutureBuilder<List<CustomerOrder>>(
        future: _ordersFuture,
        builder: (context, snapshot) {
          // LOADING STATE

          if (snapshot.connectionState != ConnectionState.done) {
            return const Center(
              child: CircularProgressIndicator(color: _brandGreen),
            );
          }

          // ERROR STATE

          if (snapshot.hasError) {
            return _buildErrorState();
          }

          final orders = snapshot.data ?? <CustomerOrder>[];

          // EMPTY STATE

          if (orders.isEmpty) {
            return RefreshIndicator(
              onRefresh: _refreshOrders,
              child: _buildEmptyState(),
            );
          }

          // ORDER LIST

          return RefreshIndicator(
            onRefresh: _refreshOrders,
            child: ListView.builder(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.all(16),
              itemCount: orders.length,
              itemBuilder: (context, index) {
                return _buildOrderCard(orders[index]);
              },
            ),
          );
        },
      ),
    );
  }
}
