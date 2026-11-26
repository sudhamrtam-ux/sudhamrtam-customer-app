import 'package:flutter/material.dart';

import '../../models/customer_order.dart';
import '../../services/order_api_client.dart';
import '../checkout/order_destination.dart';
import '../orders/order_status_labels.dart';
import 'payment_screen.dart';

/// An order's payment, from the server: how it is paid, its status,
/// "Pay Now" while an online order is unpaid, and "Pay online now" for
/// a Cash on Delivery order until its delivery list is fixed (owner
/// request 2026-11-26). Shows nothing without a server.
class OrderPaymentStatusView extends StatefulWidget {
  OrderPaymentStatusView({super.key, required this.order, OrderApiClient? api})
    : api = api ?? OrderDestination.server;

  final CustomerOrder order;
  final OrderApiClient? api;

  @override
  State<OrderPaymentStatusView> createState() => _OrderPaymentStatusViewState();
}

class _OrderPaymentStatusViewState extends State<OrderPaymentStatusView> {
  OrderPaymentStatus? _status;
  bool _loading = true;
  bool _failed = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final api = widget.api;
    if (api == null) {
      setState(() => _loading = false);
      return;
    }
    setState(() {
      _loading = true;
      _failed = false;
    });
    try {
      final status = await api.fetchPaymentStatus(widget.order.id);
      if (mounted) setState(() => _status = status);
    } catch (_) {
      if (mounted) setState(() => _failed = true);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _payNow({bool later = false}) async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (context) => PaymentScreen(
          order: widget.order,
          api: widget.api,
          payLater: later,
        ),
      ),
    );
    if (mounted) _load();
  }

  @override
  Widget build(BuildContext context) {
    if (widget.api == null) return const SizedBox.shrink();

    if (_loading) {
      return const Padding(
        padding: EdgeInsets.only(top: 8),
        child: LinearProgressIndicator(color: Color(0xFF82B440)),
      );
    }

    final status = _status;
    if (_failed || status == null) {
      return Align(
        alignment: Alignment.centerLeft,
        child: TextButton(
          onPressed: _load,
          child: const Text('Payment status unavailable. Tap to retry.'),
        ),
      );
    }

    final label = paymentLabel(widget.order, status);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Row(
            children: [
              const Expanded(
                flex: 2,
                child: Text('Method', style: TextStyle(color: Colors.black54)),
              ),
              Text(
                status.paymentMethod == 'online'
                    ? 'Online Payment'
                    : 'Cash on Delivery / Pickup',
                key: const Key('orderPaymentMethod'),
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
            ],
          ),
        ),
        Row(
          children: [
            const Expanded(
              flex: 2,
              child: Text(
                'Payment Status',
                style: TextStyle(color: Colors.black54),
              ),
            ),
            StatusChip(label, key: const Key('orderPaymentStatus')),
          ],
        ),
        if (status.isAwaitingPayment) ...[
          const SizedBox(height: 12),
          FilledButton(
            key: const Key('orderPayNow'),
            onPressed: _payNow,
            style: FilledButton.styleFrom(
              backgroundColor: const Color(0xFF82B440),
            ),
            child: const Text('Pay Now'),
          ),
        ],
        if (status.canPayOnline) ...[
          const SizedBox(height: 12),
          FilledButton.icon(
            key: const Key('orderPayOnline'),
            onPressed: () => _payNow(later: true),
            style: FilledButton.styleFrom(
              backgroundColor: const Color(0xFF82B440),
            ),
            icon: const Icon(Icons.credit_card, size: 18),
            label: const Text('Pay online now'),
          ),
          const SizedBox(height: 6),
          const Text(
            'Or pay the delivery partner in cash or UPI. Paying online is '
            'open until 9 PM the day before delivery.',
            style: TextStyle(color: Colors.black54, fontSize: 12),
          ),
        ],
      ],
    );
  }
}
