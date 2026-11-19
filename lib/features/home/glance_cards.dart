import 'package:flutter/material.dart';

import '../../app/sudhamrtam_app.dart';
import '../../database/order_database_service.dart';
import '../../models/customer_order.dart';
import '../checkout/order_destination.dart';
import '../messages/message_inbox.dart';
import '../messages/messages_screen.dart';
import '../orders/order_details_screen.dart';
import '../orders/order_number.dart';

/// Cards for the top of Home (owner, 2026-11-17): the customer's last
/// order and new messages, each shown only when there is something to
/// say.

const _darkGreen = Color(0xFF4F7A1F);
const _paleGreen = Color(0xFFF2F7EA);
const _ink = Color(0xFF1F2A14);

/// A white card with a round icon, two lines and an arrow.
class GlanceCard extends StatelessWidget {
  const GlanceCard({
    super.key,
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
    this.iconColor = _darkGreen,
    this.iconBackground = _paleGreen,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback? onTap;
  final Color iconColor;
  final Color iconBackground;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(20),
          boxShadow: const [
            BoxShadow(
              color: Color(0x14000000),
              blurRadius: 18,
              offset: Offset(0, 6),
            ),
          ],
        ),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            borderRadius: BorderRadius.circular(20),
            onTap: onTap,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 12, 12),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: iconBackground,
                      shape: BoxShape.circle,
                    ),
                    child: Icon(icon, color: iconColor),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontWeight: FontWeight.bold,
                            color: _ink,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          subtitle,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 12,
                            color: Colors.black54,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const Icon(Icons.chevron_right, color: _darkGreen),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// =====================================================
// LAST ORDER
// =====================================================

/// The server's view of an order: its status ("pending", "delivered",
/// "not_delivered", "cancelled") and short number.
typedef OrderStatusLookup =
    Future<({String status, String? orderRef})?> Function(String orderId);

Future<CustomerOrder?> _latestOrder() async {
  final orders = await OrderDatabaseService.instance.getAllOrders();
  return orders.firstOrNull;
}

Future<({String status, String? orderRef})?> _serverStatus(
  String orderId,
) async {
  final server = OrderDestination.server;
  if (server == null) return null;
  final s = await server.fetchPaymentStatus(orderId);
  return (status: s.orderStatus, orderRef: s.orderRef);
}

const _weekdays = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
const _months = [
  'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', //
  'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
];

/// "tomorrow", "today" or "Fri, 20 Nov".
String _dayText(DateTime day, DateTime today) {
  final d = DateUtils.dateOnly(day);
  final t = DateUtils.dateOnly(today);
  if (d == t) return 'today';
  if (d == t.add(const Duration(days: 1))) return 'tomorrow';
  return '${_weekdays[d.weekday - 1]}, ${d.day} ${_months[d.month - 1]}';
}

/// What the last-order card says; null when it is old news (finished
/// more than 2 days ago).
({String line, IconData icon, Color color})? lastOrderLine(
  CustomerOrder order,
  String? serverStatus,
  DateTime now,
) {
  final day = order.deliveryDate == null
      ? null
      : DateTime.tryParse(order.deliveryDate!);
  final status =
      serverStatus ??
      switch (order.status) {
        OrderStatus.delivered || OrderStatus.pickedUp => 'delivered',
        OrderStatus.notDelivered => 'not_delivered',
        OrderStatus.cancelled => 'cancelled',
        _ => 'pending',
      };
  // Old news: its delivery day (or the day it was placed) is more
  // than 2 days ago, delivered or not (an order nobody marked would
  // otherwise say "on its way" for ever).
  final when = day ?? order.createdAt;
  if (DateUtils.dateOnly(now).difference(DateUtils.dateOnly(when)).inDays > 2) {
    return null;
  }
  return switch (status) {
    'delivered' => (
      line: 'Delivered${day == null ? '' : ' ${_dayText(day, now)}'}',
      icon: Icons.check_circle_outline,
      color: _darkGreen,
    ),
    'cancelled' => (
      line: 'Cancelled',
      icon: Icons.cancel_outlined,
      color: Colors.red.shade700,
    ),
    'not_delivered' => (
      line: 'Not delivered. Please contact us if you need help.',
      icon: Icons.error_outline,
      color: Colors.orange.shade800,
    ),
    _ => (
      line: day == null
          ? 'On its way soon'
          : 'Arriving ${_dayText(day, now)} morning',
      icon: Icons.local_shipping_outlined,
      color: _darkGreen,
    ),
  };
}

/// "Order SUD0000123 · 3 items · ₹450 — Arriving tomorrow morning".
class LastOrderCard extends StatefulWidget {
  const LastOrderCard({
    super.key,
    required this.now,
    this.loadLatest = _latestOrder,
    this.lookup = _serverStatus,
  });

  final DateTime Function() now;
  final Future<CustomerOrder?> Function() loadLatest;
  final OrderStatusLookup lookup;

  @override
  State<LastOrderCard> createState() => _LastOrderCardState();
}

class _LastOrderCardState extends State<LastOrderCard> {
  CustomerOrder? _order;
  String? _status;
  String? _ref;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final order = await widget.loadLatest();
      if (!mounted) return;
      setState(() => _order = order);
      if (order == null) return;
      final server = await widget.lookup(order.id);
      if (!mounted || server == null) return;
      setState(() {
        _status = server.status;
        _ref = server.orderRef;
      });
    } catch (_) {
      // Only a reminder: offline it shows what the phone knows.
    }
  }

  @override
  Widget build(BuildContext context) {
    final order = _order;
    if (order == null) return const SizedBox.shrink();
    final said = lastOrderLine(order, _status, widget.now());
    if (said == null) return const SizedBox.shrink();
    final items = order.totalQuantity;
    return GlanceCard(
      key: const Key('homeLastOrder'),
      icon: said.icon,
      iconColor: said.color,
      iconBackground: said.color.withValues(alpha: 0.10),
      title:
          '${orderTitle(order.id, _ref)} · $items '
          '${items == 1 ? 'item' : 'items'} · '
          '₹${order.subtotal.toStringAsFixed(0)}',
      subtitle: said.line,
      onTap: () async {
        await Navigator.of(context).push(
          MaterialPageRoute<void>(
            builder: (_) => OrderDetailsScreen(order: order),
          ),
        );
        await _load();
      },
    );
  }
}

// =====================================================
// NEW MESSAGES
// =====================================================

/// "2 new messages from Sudhamrtam", with the newest title; opens
/// Messages.
class NewMessagesCard extends StatelessWidget {
  const NewMessagesCard({super.key, this.inbox});

  /// Defaults to the app's inbox (none without a server).
  final MessageInbox? inbox;

  @override
  Widget build(BuildContext context) {
    final box = inbox ?? sudhamrtamMessages;
    if (box == null) return const SizedBox.shrink();
    return ListenableBuilder(
      listenable: box,
      builder: (context, _) {
        final count = box.unreadCount;
        if (count <= 0) return const SizedBox.shrink();
        final newest = (box.messages ?? const [])
            .where((m) => m.unread)
            .firstOrNull;
        return GlanceCard(
          key: const Key('homeNewMessages'),
          icon: Icons.mark_email_unread_outlined,
          iconColor: const Color(0xFF1565C0),
          iconBackground: const Color(0xFFE3F2FD),
          title:
              '$count new ${count == 1 ? 'message' : 'messages'} '
              'from Sudhamrtam',
          subtitle: newest?.title ?? 'Tap to read.',
          onTap: () => Navigator.of(context).push(
            MaterialPageRoute<void>(builder: (_) => MessagesScreen(inbox: box)),
          ),
        );
      },
    );
  }
}
