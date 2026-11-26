import 'package:flutter/material.dart';

import '../../core/widgets/period_filter.dart';
import '../../core/widgets/site_layout.dart';

import '../../app/sudhamrtam_app.dart';
import '../../database/order_database_service.dart';
import '../../database/order_ref_service.dart';
import '../../models/combo_offer.dart';
import '../../models/customer_order.dart';
import '../../models/order_item.dart';
import '../../models/product.dart';
import '../../services/order_api_client.dart';
import '../checkout/order_destination.dart';
import '../payment/payment_screen.dart';
import '../shop/product_image.dart';
import '../../services/support_api_client.dart';
import '../support/help_support_screen.dart';
import '../support/support_conversation_screen.dart';
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
    SupportApiClient? support,
    DateTime Function()? clock,
  }) : clock = clock ?? DateTime.now,
       api = api ?? OrderDestination.server,
       productLookup = productLookup ?? _shopProduct,
       support = support ?? sudhamrtamSupport;

  /// Payment statuses come from here; null without a server.
  final OrderApiClient? api;

  /// Each order's help conversation; null without a server.
  final SupportApiClient? support;

  /// For photos and "Buy it again".
  final OrderProductLookup productLookup;

  /// Today, for the period filter; replaceable in tests.
  final DateTime Function() clock;

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

  /// The help conversation of each order that has one.
  Map<String, SupportQuery> _help = const {};

  final _search = TextEditingController();
  String _query = '';
  bool _openOnly = false;

  /// How far back the list goes (owner request 2026-11-26).
  Period _period = Period.all;

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
    _loadHelp();
  }

  Future<void> _loadHelp() async {
    final support = widget.support;
    if (support == null || !support.isSignedIn) return;
    try {
      final mine = await support.fetchMine();
      if (!mounted) return;
      setState(
        () => _help = {
          for (final q in mine)
            if (q.orderId != null) q.orderId!: q,
        },
      );
    } on SupportException {
      // The cards offer "Get help" as before.
    }
  }

  /// The order's conversation (a new one when it has none); Help &
  /// Support without a server or sign-in.
  Future<void> _openHelp(CustomerOrder order) async {
    final support = widget.support;
    final navigator = Navigator.of(context);
    if (support == null || !support.isSignedIn) {
      await navigator.push(
        MaterialPageRoute<void>(builder: (_) => const HelpSupportScreen()),
      );
      return;
    }
    final server = _payments[order.id];
    final info = SupportOrderInfo(
      orderId: order.id,
      title: orderTitle(order.id, server?.orderRef),
      status: orderHeadline(order, effectiveStatus(order, server)).text,
      lines: [
        for (final i in order.items)
          '${i.quantity} × ${i.productName} (${i.unit})',
      ],
      total: '₹${order.subtotal.toStringAsFixed(2)}',
    );
    await navigator.push(
      MaterialPageRoute<void>(
        builder: (_) => SupportConversationScreen(
          queryId: _help[order.id]?.id,
          order: info,
          api: support,
        ),
      ),
    );
    await _loadHelp();
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

  /// Orders matching the search, the period and the "Not yet
  /// delivered" filter.
  List<CustomerOrder> _filtered(List<CustomerOrder> orders) {
    final q = _query.trim().toLowerCase();
    final now = widget.clock();
    return [
      for (final order in orders)
        if (_period.includes(order.createdAt, now) &&
            (!_openOnly ||
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
            PeriodFilter(
              value: _period,
              onChanged: (p) => setState(() => _period = p),
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

  /// From this width the card spreads out: header in one row, the
  /// buttons in a column beside the items.
  static const double _wideCard = 520;

  /// The list does not get wider than this (tablets, computers).
  static const double _maxListWidth = 1000;

  static const Color _linkColor = Color(0xFF007185);

  /// [child] at most [_maxListWidth] wide, centred.
  Widget _limitWidth(Widget child) => Center(
    child: ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: _maxListWidth),
      child: child,
    ),
  );

  Widget _headerField(
    String label,
    String value, {
    CrossAxisAlignment align = CrossAxisAlignment.start,
  }) {
    return Column(
      crossAxisAlignment: align,
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
        Text(
          value,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontSize: 14),
        ),
      ],
    );
  }

  /// Who receives it: the delivery contact, or the store for pickup.
  String _deliverTo(CustomerOrder order) {
    if (order.fulfillmentMethod == FulfillmentMethod.pickup) {
      return 'Store pickup';
    }
    final name = order.recipientName?.trim();
    return name == null || name.isEmpty ? 'Home delivery' : name;
  }

  Widget _orderNumber(CustomerOrder order, OrderPaymentStatus? server) =>
      OrderNumberText(
        key: ValueKey('${order.id}-${server?.orderRef}'),
        orderId: order.id,
        orderRef: server?.orderRef,
        maxLines: 1,
        style: const TextStyle(fontSize: 12, color: Colors.black54),
      );

  Widget _detailsLink(CustomerOrder order) => InkWell(
    key: Key('details_${order.id}'),
    onTap: () => _openOrderDetails(order),
    child: const Padding(
      padding: EdgeInsets.symmetric(vertical: 4),
      child: Text(
        'View order details',
        style: TextStyle(color: _linkColor, fontWeight: FontWeight.w600),
      ),
    ),
  );

  Widget _buildHeader(
    CustomerOrder order,
    OrderPaymentStatus? server, {
    required bool wide,
  }) {
    final placed = _headerField('ORDER PLACED', longDate(order.createdAt));
    final total = _headerField(
      'TOTAL',
      '₹${order.subtotal.toStringAsFixed(2)}',
      align: wide ? CrossAxisAlignment.start : CrossAxisAlignment.end,
    );
    final deliverTo = _headerField(
      order.fulfillmentMethod == FulfillmentMethod.pickup
          ? 'PICKUP'
          : 'DELIVER TO',
      _deliverTo(order),
    );

    return Container(
      color: _headerGrey,
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 10),
      child: wide
          ? Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(width: 150, child: placed),
                SizedBox(width: 100, child: total),
                Expanded(child: deliverTo),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      _orderNumber(order, server),
                      _detailsLink(order),
                    ],
                  ),
                ),
              ],
            )
          : Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(child: placed),
                    total,
                  ],
                ),
                const SizedBox(height: 8),
                deliverTo,
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(child: _orderNumber(order, server)),
                    _detailsLink(order),
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
      padding: const EdgeInsets.only(bottom: 14),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox.square(
            dimension: 80,
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
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  item.productName,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: _linkColor,
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  '${item.unit} × ${item.quantity}  ·  '
                  '₹${item.totalPrice.toStringAsFixed(2)}',
                  style: const TextStyle(fontSize: 13, color: Colors.black54),
                ),
                const SizedBox(height: 8),
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

  /// Asks, then cancels the order on the server (owner decision
  /// 2026-11-25: unpaid orders, before 9 PM the day before delivery).
  /// Pays a Cash on Delivery order online (owner request 2026-11-26).
  Future<void> _payOnline(CustomerOrder order) async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) =>
            PaymentScreen(order: order, api: widget.api, payLater: true),
      ),
    );
    if (mounted) await _refreshOrders();
  }

  Future<void> _cancel(CustomerOrder order) async {
    final api = widget.api;
    if (api == null) return;
    final ref = _payments[order.id]?.orderRef;
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Cancel this order?'),
        content: Text(
          '${ref ?? 'This order'} will not be delivered. Nothing has been '
          'paid, so there is nothing to refund.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Keep order'),
          ),
          FilledButton(
            key: const Key('cancel-order-yes'),
            style: FilledButton.styleFrom(backgroundColor: Colors.red.shade700),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Cancel order'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    try {
      await api.cancelOrder(order.id);
      messenger.showSnackBar(
        SnackBar(content: Text('${ref ?? 'The order'} is cancelled.')),
      );
    } on PaymentRejectedException catch (error) {
      messenger.showSnackBar(SnackBar(content: Text(error.message)));
    } on OrderApiException catch (error) {
      messenger.showSnackBar(SnackBar(content: Text(error.message)));
    }
    await _loadPayments();
  }

  /// "View order details" and "Get help with this order", and
  /// "Cancel order" while the server allows it.
  List<Widget> _actions(CustomerOrder order) {
    final style = OutlinedButton.styleFrom(
      minimumSize: const Size.fromHeight(42),
      shape: const StadiumBorder(),
      foregroundColor: Colors.black87,
      side: const BorderSide(color: _border),
    );
    return [
      if (_payments[order.id]?.canPayOnline ?? false)
        FilledButton.icon(
          key: Key('pay-online-${order.id}'),
          onPressed: () => _payOnline(order),
          style: FilledButton.styleFrom(
            backgroundColor: _brandGreen,
            shape: const StadiumBorder(),
          ),
          icon: const Icon(Icons.credit_card, size: 18),
          label: const Text('Pay online now'),
        ),
      OutlinedButton(
        key: Key('details-button-${order.id}'),
        onPressed: () => _openOrderDetails(order),
        style: style,
        child: const Text('View order details'),
      ),
      OutlinedButton(
        key: Key('help-${order.id}'),
        onPressed: () => _openHelp(order),
        style: style,
        child: Text(
          _help.containsKey(order.id)
              ? 'Open help conversation'
              : 'Get help with this order',
        ),
      ),
      if (_payments[order.id]?.canCancel ?? false)
        OutlinedButton(
          key: Key('cancel-order-${order.id}'),
          onPressed: () => _cancel(order),
          style: style.copyWith(
            foregroundColor: WidgetStatePropertyAll(Colors.red.shade700),
          ),
          child: const Text('Cancel order'),
        ),
    ];
  }

  /// "Help request Q-1023 · New reply" under the status, when the order
  /// has a conversation; tapping it opens it.
  Widget? _helpLine(CustomerOrder order) {
    final q = _help[order.id];
    if (q == null) return null;
    final (String state, Color color) = q.unread
        ? ('New reply', const Color(0xFFE65100))
        : q.isResolved
        ? ('Resolved', const Color(0xFF4E8A1E))
        : q.lastFromSudhamrtam
        ? ('Replied', const Color(0xFF4E8A1E))
        : ('Waiting for Sudhamrtam', Colors.black54);
    return InkWell(
      key: Key('help-line-${order.id}'),
      onTap: () => _openHelp(order),
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Row(
          children: [
            Icon(
              q.unread ? Icons.mark_chat_unread_outlined : Icons.chat_outlined,
              size: 18,
              color: color,
            ),
            const SizedBox(width: 6),
            Flexible(
              child: Text.rich(
                TextSpan(
                  children: [
                    TextSpan(
                      text: 'Help request ${q.ref ?? ''}',
                      style: const TextStyle(color: Colors.black87),
                    ),
                    const TextSpan(text: '  ·  '),
                    TextSpan(
                      text: state,
                      style: TextStyle(
                        color: color,
                        fontWeight: q.unread ? FontWeight.bold : null,
                      ),
                    ),
                  ],
                ),
                style: const TextStyle(fontSize: 13.5),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildOrderCard(CustomerOrder order) {
    final server = _payments[order.id];
    final headline = orderHeadline(order, effectiveStatus(order, server));
    final payment = paymentLabel(order, server);
    final more = order.items.length - _itemsShown;

    // Where the order is now, how it is paid, and its items.
    final summary = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(headline.icon, color: headline.color, size: 22),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                headline.text,
                key: Key('delivery_${order.id}'),
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: headline.color,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 10,
          runSpacing: 6,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            StatusChip(payment, key: Key('payment_${order.id}')),
            Text(
              _formatFulfillment(order.fulfillmentMethod),
              style: const TextStyle(fontSize: 13, color: Colors.black54),
            ),
          ],
        ),
        ?_helpLine(order),
        const SizedBox(height: 16),
        for (final item in order.items.take(_itemsShown)) _buildItemRow(item),
        if (more > 0)
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: Text(
              '+ $more more ${more == 1 ? 'item' : 'items'}',
              style: const TextStyle(color: Colors.black54),
            ),
          ),
      ],
    );

    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border.all(color: _border),
        borderRadius: BorderRadius.circular(10),
      ),
      clipBehavior: Clip.antiAlias,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final wide = constraints.maxWidth >= _wideCard;
          final actions = _actions(order);
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _buildHeader(order, server, wide: wide),
              const Divider(height: 1, color: _border),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 14, 16, 6),
                child: wide
                    ? Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(child: summary),
                          const SizedBox(width: 24),
                          SizedBox(
                            width: 210,
                            child: Column(
                              children: [
                                for (final a in actions) ...[
                                  a,
                                  const SizedBox(height: 10),
                                ],
                              ],
                            ),
                          ),
                        ],
                      )
                    : Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          summary,
                          for (final a in actions) ...[
                            a,
                            const SizedBox(height: 10),
                          ],
                        ],
                      ),
              ),
            ],
          );
        },
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
    return SiteScaffold(
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
                if (index == 0) {
                  return _limitWidth(_buildTop(orders.length, shown.length));
                }
                if (shown.isEmpty) {
                  return const Padding(
                    padding: EdgeInsets.only(top: 40),
                    child: Center(
                      child: Text(
                        'No orders match. Try another period or search.',
                        style: TextStyle(color: Colors.black54),
                      ),
                    ),
                  );
                }
                return _limitWidth(_buildOrderCard(shown[index - 1]));
              },
            ),
          );
        },
      ),
    );
  }
}
