import 'package:flutter/material.dart';

import '../../app/sudhamrtam_app.dart';
import '../../database/order_database_service.dart';
import '../../database/order_ref_service.dart';
import '../../models/combo_offer.dart';
import '../../models/customer_order.dart';
import '../../models/order_item.dart';
import '../../models/product.dart';
import '../../services/order_api_client.dart';
import '../checkout/order_destination.dart';
import '../shop/product_image.dart';
import 'order_details_screen.dart';
import 'order_number.dart';
import 'order_status_labels.dart';
import '../../core/widgets/page_app_bar.dart';

/// The product an order line was, as it is in the shop today; null when
/// it is gone. Products from the catalog, combo lines from today's combos.
typedef OrderProductLookup = Product? Function(String productId);

Product? _shopProduct(String id) => isComboProductId(id)
    ? sudhamrtamCombos.productById(id)
    : sudhamrtamCatalog.productById(id);

const _months = [
  'January',
  'February',
  'March',
  'April',
  'May',
  'June',
  'July',
  'August',
  'September',
  'October',
  'November',
  'December',
];

/// "18 November 2026".
String longDate(DateTime date) {
  final local = date.toLocal();
  return '${local.day} ${_months[local.month - 1]} ${local.year}';
}

/// "6 December" from the chosen delivery day "2026-12-06"; null if
/// it cannot be read.
String? deliveryDayLabel(String? deliveryDate) {
  final day = deliveryDate == null ? null : DateTime.tryParse(deliveryDate);
  return day == null ? null : '${day.day} ${_months[day.month - 1]}';
}

/// The big line at the top of an order: where it is now.
StatusLabel orderHeadline(CustomerOrder order, OrderStatus status) {
  final label = deliveryLabel(status);
  final waiting =
      status == OrderStatus.pending ||
      status == OrderStatus.confirmed ||
      status == OrderStatus.preparing;
  final day = deliveryDayLabel(order.deliveryDate);
  if (!waiting || day == null) return label;
  return StatusLabel(
    order.fulfillmentMethod == FulfillmentMethod.pickup
        ? 'Pickup on $day'
        : 'Arriving $day',
    const Color(0xFF2E7D6B),
    label.icon,
  );
}

/// Still on its way to the customer (not delivered, picked up, given
/// up on or cancelled).
bool isOpenOrder(OrderStatus status) =>
    status != OrderStatus.delivered &&
    status != OrderStatus.pickedUp &&
    status != OrderStatus.notDelivered &&
    status != OrderStatus.cancelled;

class OrderHistoryScreen extends StatefulWidget {
  OrderHistoryScreen({
    super.key,
    OrderApiClient? api,
    OrderProductLookup? productLookup,
  }) : api = api ?? OrderDestination.server,
       productLookup = productLookup ?? _shopProduct;

  /// Payment statuses come from here; null without a server.
  final OrderApiClient? api;

  /// For photos and "Buy it again".
  final OrderProductLookup productLookup;

  @override
  State<OrderHistoryScreen> createState() => _OrderHistoryScreenState();
}

class _OrderHistoryScreenState extends State<OrderHistoryScreen> {
  static const Color _brandGreen = Color(0xFF82B440);
  static const Color _headerGrey = Color(0xFFF0F2F2);
  static const Color _border = Color(0xFFD5D9D9);

  /// Items shown on a card; the rest are in the order details.
  static const int _itemsShown = 3;

  late Future<List<CustomerOrder>> _ordersFuture;

  /// The server's payment status per order; empty if unknown
  /// (no server, offline, or a local test order).
  Map<String, OrderPaymentStatus> _payments = const {};

  /// Why the latest statuses could not be read; null when they were
  /// (or there is no server).
  String? _paymentsProblem;

  final _search = TextEditingController();
  String _query = '';
  bool _openOnly = false;

  @override
  void initState() {
    super.initState();
    _loadOrders();
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
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
      if (mounted) {
        setState(() {
          _payments = payments;
          _paymentsProblem = null;
        });
      }
      await _saveServerStatuses(payments);
      // Keep the short order numbers for offline use and the details.
      final refs = {
        for (final e in payments.entries)
          if (e.value.orderRef != null) e.key: e.value.orderRef!,
      };
      try {
        await OrderRefService.instance.saveAll(refs);
      } catch (_) {
        // They show again next time.
      }
    } catch (error) {
      // The cards show what the phone knows: the payment method, and
      // the status saved here.
      debugPrint('My Orders: latest statuses not loaded: $error');
      if (mounted) {
        setState(
          () => _paymentsProblem = error is OrderApiException
              ? error.message
              : 'Could not read the latest order statuses.',
        );
      }
    }
  }

  /// Keeps the server's Cancelled / Delivered on the phone too, so the
  /// details page and the home card show it, also offline. Not
  /// delivered is only shown: the phone's orders table (schema v3)
  /// does not take that status, and the server keeps telling it.
  Future<void> _saveServerStatuses(
    Map<String, OrderPaymentStatus> payments,
  ) async {
    try {
      final local = await _ordersFuture;
      var changed = false;
      for (final order in local) {
        final status = effectiveStatus(order, payments[order.id]);
        if (status != order.status && status != OrderStatus.notDelivered) {
          changed |= await OrderDatabaseService.instance.updateOrderStatus(
            order.id,
            status,
          );
        }
      }
      if (changed && mounted) {
        setState(() {
          _ordersFuture = OrderDatabaseService.instance.getAllOrders();
        });
      }
    } catch (error) {
      debugPrint('My Orders: statuses not saved: $error');
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

  String _formatFulfillment(FulfillmentMethod method) {
    switch (method) {
      case FulfillmentMethod.delivery:
        return 'Home delivery';

      case FulfillmentMethod.pickup:
        return 'Store pickup';
    }
  }

  void _openOrderDetails(CustomerOrder order) {
    // The status the card shows (the server's when known).
    final shown = order.copyWith(
      status: effectiveStatus(order, _payments[order.id]),
    );
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (context) => OrderDetailsScreen(order: shown),
      ),
    );
  }

  /// Puts one of [item] in the cart, at today's price.
  void _buyAgain(OrderItem item) {
    final messenger = ScaffoldMessenger.of(context);
    final product = widget.productLookup(item.productId);
    final String message;
    if (product == null || !product.isAvailable) {
      message = '${item.productName} is not available right now.';
    } else if (sudhamrtamCart.addProduct(product)) {
      message = '${product.name} (${product.unit}) added to your cart.';
    } else {
      message =
          'Could not add ${product.name}: the cart is busy or already '
          'has the most allowed.';
    }
    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  /// Orders matching the search and the "Not yet delivered" filter.
  List<CustomerOrder> _filtered(List<CustomerOrder> orders) {
    final q = _query.trim().toLowerCase();
    return [
      for (final order in orders)
        if ((!_openOnly ||
                isOpenOrder(effectiveStatus(order, _payments[order.id]))) &&
            (q.isEmpty ||
                order.items.any(
                  (i) => i.productName.toLowerCase().contains(q),
                ) ||
                order.id.toLowerCase().contains(q) ||
                (_payments[order.id]?.orderRef?.toLowerCase().contains(q) ??
                    false)))
          order,
    ];
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
  // SEARCH AND FILTER
  // ==========================================

  Widget _buildTop(int total, int shown) {
    final problem = _paymentsProblem;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (problem != null)
          Container(
            key: const Key('orders-status-problem'),
            margin: const EdgeInsets.only(bottom: 10),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.orange.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(Icons.cloud_off_outlined, color: Colors.orange),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'Showing the statuses saved on this phone. $problem',
                  ),
                ),
              ],
            ),
          ),
        TextField(
          key: const Key('order-search'),
          controller: _search,
          onChanged: (v) => setState(() => _query = v),
          textInputAction: TextInputAction.search,
          decoration: InputDecoration(
            hintText: 'Search your orders',
            prefixIcon: const Icon(Icons.search),
            suffixIcon: _query.isEmpty
                ? null
                : IconButton(
                    tooltip: 'Clear search',
                    icon: const Icon(Icons.close),
                    onPressed: () => setState(() {
                      _search.clear();
                      _query = '';
                    }),
                  ),
            isDense: true,
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(24)),
          ),
        ),
        const SizedBox(height: 10),
        Wrap(
          spacing: 8,
          runSpacing: 4,
          children: [
            ChoiceChip(
              key: const Key('orders-all'),
              label: const Text('All orders'),
              selected: !_openOnly,
              onSelected: (_) => setState(() => _openOnly = false),
            ),
            ChoiceChip(
              key: const Key('orders-open'),
              label: const Text('Not yet delivered'),
              selected: _openOnly,
              onSelected: (_) => setState(() => _openOnly = true),
            ),
          ],
        ),
        const SizedBox(height: 10),
        Text.rich(
          key: const Key('orders-count'),
          TextSpan(
            children: [
              TextSpan(
                text: '$shown ${shown == 1 ? 'order' : 'orders'}',
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
              TextSpan(text: shown == total ? ' placed' : ' of $total shown'),
            ],
          ),
        ),
        const SizedBox(height: 10),
      ],
    );
  }

  // ==========================================
  // ORDER CARD
  // ==========================================

  Widget _headerField(String label, String value) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          label,
          style: const TextStyle(
            fontSize: 11,
            letterSpacing: 0.5,
            color: Colors.black54,
          ),
        ),
        const SizedBox(height: 2),
        Text(value, style: const TextStyle(fontSize: 14)),
      ],
    );
  }

  Widget _buildHeader(CustomerOrder order, OrderPaymentStatus? server) {
    return Container(
      color: _headerGrey,
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: _headerField('ORDER PLACED', longDate(order.createdAt)),
              ),
              _headerField('TOTAL', '₹${order.subtotal.toStringAsFixed(2)}'),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: OrderNumberText(
                  key: ValueKey('${order.id}-${server?.orderRef}'),
                  orderId: order.id,
                  orderRef: server?.orderRef,
                  maxLines: 1,
                  style: const TextStyle(fontSize: 12, color: Colors.black54),
                ),
              ),
              InkWell(
                key: Key('details_${order.id}'),
                onTap: () => _openOrderDetails(order),
                child: const Padding(
                  padding: EdgeInsets.symmetric(vertical: 4),
                  child: Text(
                    'View order details',
                    style: TextStyle(
                      color: Color(0xFF007185),
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildItemRow(OrderItem item) {
    final product = widget.productLookup(item.productId);
    final combo = isComboProductId(item.productId);
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox.square(
            dimension: 72,
            child: ProductImage(
              key: Key('order-photo-${item.productId}'),
              productId: item.productId,
              icon:
                  product?.icon ??
                  (combo
                      ? Icons.local_offer_outlined
                      : Icons.shopping_basket_outlined),
              iconSize: 40,
              borderRadius: 8,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  item.productName,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Color(0xFF007185),
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  '${item.unit} × ${item.quantity}  ·  '
                  '₹${item.totalPrice.toStringAsFixed(2)}',
                  style: const TextStyle(fontSize: 13, color: Colors.black54),
                ),
                const SizedBox(height: 6),
                FilledButton.icon(
                  key: Key('buy-again-${item.productId}'),
                  onPressed: () => _buyAgain(item),
                  icon: const Icon(Icons.replay, size: 18),
                  label: const Text('Buy it again'),
                  style: FilledButton.styleFrom(
                    backgroundColor: const Color(0xFFFFD814),
                    foregroundColor: Colors.black87,
                    visualDensity: VisualDensity.compact,
                    shape: const StadiumBorder(),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildOrderCard(CustomerOrder order) {
    final server = _payments[order.id];
    final headline = orderHeadline(order, effectiveStatus(order, server));
    final payment = paymentLabel(order, server);
    final more = order.items.length - _itemsShown;

    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border.all(color: _border),
        borderRadius: BorderRadius.circular(10),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _buildHeader(order, server),
          const Divider(height: 1, color: _border),
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 12, 14, 4),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // WHERE THE ORDER IS NOW
                Text(
                  headline.text,
                  key: Key('delivery_${order.id}'),
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: headline.color,
                  ),
                ),
                const SizedBox(height: 6),
                Wrap(
                  spacing: 8,
                  runSpacing: 6,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    StatusChip(payment, key: Key('payment_${order.id}')),
                    Text(
                      _formatFulfillment(order.fulfillmentMethod),
                      style: const TextStyle(
                        fontSize: 13,
                        color: Colors.black54,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 14),

                // ITEMS
                for (final item in order.items.take(_itemsShown))
                  _buildItemRow(item),
                if (more > 0)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Text(
                      '+ $more more ${more == 1 ? 'item' : 'items'}',
                      style: const TextStyle(color: Colors.black54),
                    ),
                  ),

                OutlinedButton(
                  onPressed: () => _openOrderDetails(order),
                  style: OutlinedButton.styleFrom(
                    minimumSize: const Size.fromHeight(40),
                    shape: const StadiumBorder(),
                    foregroundColor: Colors.black87,
                  ),
                  child: const Text('View order details'),
                ),
                const SizedBox(height: 10),
              ],
            ),
          ),
        ],
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

          final shown = _filtered(orders);
          return RefreshIndicator(
            onRefresh: _refreshOrders,
            child: ListView.builder(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.all(14),
              itemCount: shown.length + 1 + (shown.isEmpty ? 1 : 0),
              itemBuilder: (context, index) {
                if (index == 0) return _buildTop(orders.length, shown.length);
                if (shown.isEmpty) {
                  return const Padding(
                    padding: EdgeInsets.only(top: 40),
                    child: Center(
                      child: Text(
                        'No orders match.',
                        style: TextStyle(color: Colors.black54),
                      ),
                    ),
                  );
                }
                return _buildOrderCard(shown[index - 1]);
              },
            ),
          );
        },
      ),
    );
  }
}
