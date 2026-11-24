import 'package:flutter/material.dart';

import '../../core/widgets/site_layout.dart';

import '../../database/order_database_service.dart';
import '../../models/customer_order.dart';
import '../../services/order_api_client.dart';
import '../checkout/order_destination.dart';
import '../orders/order_details_screen.dart';
import 'payment_launcher.dart';
import '../../core/widgets/page_app_bar.dart';

const _green = Color(0xFF82B440);

enum _Phase {
  starting,
  paying,
  checking,
  paid,
  notPaid,
  cashOnDelivery,
  closed,
}

/// Pays for a placed online order with Cashfree.
///
/// The order already exists on the server. Whether it is paid is
/// always decided by the server (which asks Cashfree), never by
/// the payment screen's own result. If the payment does not go
/// through, the customer can try again or switch the order to
/// Cash on Delivery.
class PaymentScreen extends StatefulWidget {
  PaymentScreen({
    super.key,
    required this.order,
    OrderApiClient? api,
    PaymentLauncher? launcher,
    this.confirmDelay = const Duration(seconds: 2),
    this.autoStart = true,
  }) : api = api ?? OrderDestination.server,
       launcher = launcher ?? CashfreePaymentLauncher();

  final CustomerOrder order;

  /// Null when the app has no server (payment impossible).
  final OrderApiClient? api;
  final PaymentLauncher launcher;

  /// Wait between checks while Cashfree confirms a payment.
  final Duration confirmDelay;

  /// Opens the payment screen at once.
  final bool autoStart;

  @override
  State<PaymentScreen> createState() => _PaymentScreenState();
}

class _PaymentScreenState extends State<PaymentScreen> {
  _Phase _phase = _Phase.starting;
  String? _message;
  DateTime? _payBy;
  bool _sandbox = false;
  bool _busy = false;

  String get _orderId => widget.order.id;

  @override
  void initState() {
    super.initState();
    if (widget.api == null) {
      _phase = _Phase.notPaid;
      _message = 'Online payment needs a connection to Sudhamrtam.';
    } else if (widget.autoStart) {
      _pay();
    } else {
      _check();
    }
  }

  void _show(_Phase phase, [String? message]) {
    if (!mounted) return;
    setState(() {
      _phase = phase;
      _message = message;
    });
  }

  Future<void> _pay() async {
    final api = widget.api;
    if (api == null || _busy) return;
    _busy = true;
    _show(_Phase.starting);

    try {
      final PaymentSession session;
      try {
        session = await api.startPayment(_orderId);
      } on PaymentRejectedException catch (error) {
        if (error.isAlreadyPaid) {
          await _confirm(api);
        } else {
          await _applyRejection(error);
        }
        return;
      }

      if (mounted) setState(() => _sandbox = session.isSandbox);
      _show(_Phase.paying);

      final result = await widget.launcher.launch(session);
      await _confirm(
        api,
        launchMessage: result is PaymentLaunchFailed ? result.message : null,
        expectPaid: result is PaymentLaunchFinished,
      );
    } on OrderApiException catch (error) {
      _show(_Phase.notPaid, error.message);
    } finally {
      _busy = false;
    }
  }

  /// Checks with the server. After a reported success, Cashfree
  /// may need a moment, so a few checks are made.
  Future<void> _confirm(
    OrderApiClient api, {
    String? launchMessage,
    bool expectPaid = false,
  }) async {
    _show(_Phase.checking);
    var status = await api.checkPayment(_orderId);

    for (var i = 0; expectPaid && status.isAwaitingPayment && i < 3; i++) {
      await Future<void>.delayed(widget.confirmDelay);
      status = await api.checkPayment(_orderId);
    }

    await _applyStatus(
      status,
      notPaidMessage: expectPaid
          ? 'We have not received the payment confirmation yet. '
                'If money was deducted, tap Check Payment in a minute.'
          : launchMessage ?? 'The payment was not completed.',
    );
  }

  Future<void> _check() async {
    final api = widget.api;
    if (api == null || _busy) return;
    _busy = true;
    try {
      await _confirm(api, launchMessage: 'This order has not been paid yet.');
    } on OrderApiException catch (error) {
      _show(_Phase.notPaid, error.message);
    } on PaymentRejectedException catch (error) {
      await _applyRejection(error);
    } finally {
      _busy = false;
    }
  }

  Future<void> _switchToCashOnDelivery() async {
    final api = widget.api;
    if (api == null || _busy) return;
    _busy = true;
    _show(_Phase.checking);

    try {
      final status = await api.switchToCashOnDelivery(_orderId);
      await _applyStatus(status);
    } on PaymentRejectedException catch (error) {
      if (error.isAlreadyPaid) {
        await _applyStatus(await api.fetchPaymentStatus(_orderId));
      } else if (error.code == 'PAYMENT_IN_PROGRESS') {
        _show(_Phase.notPaid, error.message);
      } else {
        await _applyRejection(error);
      }
    } on OrderApiException catch (error) {
      _show(_Phase.notPaid, error.message);
    } finally {
      _busy = false;
    }
  }

  Future<void> _applyStatus(
    OrderPaymentStatus status, {
    String? notPaidMessage,
  }) async {
    if (mounted) setState(() => _payBy = status.paymentDueAt);

    if (status.isPaid) {
      _show(_Phase.paid);
    } else if (status.isCashOnDelivery) {
      // Keep the order on this phone in step with the server.
      await OrderDatabaseService.instance.updatePaymentMethod(
        _orderId,
        OrderPaymentMethod.cashOnDelivery,
      );
      _show(_Phase.cashOnDelivery);
    } else if (status.isCancelledUnpaid) {
      await OrderDatabaseService.instance.updateOrderStatus(
        _orderId,
        OrderStatus.cancelled,
      );
      _show(
        _Phase.closed,
        'This order was cancelled because it was not paid in time.',
      );
    } else {
      _show(
        _Phase.notPaid,
        notPaidMessage ?? 'This order has not been paid yet.',
      );
    }
  }

  Future<void> _applyRejection(PaymentRejectedException error) async {
    switch (error.code) {
      case 'NOT_ONLINE_PAYMENT':
        await OrderDatabaseService.instance.updatePaymentMethod(
          _orderId,
          OrderPaymentMethod.cashOnDelivery,
        );
        _show(_Phase.cashOnDelivery);
      case 'ORDER_CANCELLED':
      case 'PAYMENT_WINDOW_CLOSED':
        _show(_Phase.closed, error.message);
      default:
        _show(_Phase.notPaid, error.message);
    }
  }

  Future<void> _viewOrder() async {
    final saved = await OrderDatabaseService.instance.getOrderById(_orderId);
    if (!mounted) return;
    await Navigator.of(context).pushReplacement(
      MaterialPageRoute<void>(
        builder: (context) => OrderDetailsScreen(order: saved ?? widget.order),
      ),
    );
  }

  String _time(DateTime time) {
    final local = time.toLocal();
    final hour = local.hour % 12 == 0 ? 12 : local.hour % 12;
    final minute = local.minute.toString().padLeft(2, '0');
    final now = DateTime.now();
    final today =
        local.year == now.year &&
        local.month == now.month &&
        local.day == now.day;
    return '$hour:$minute ${local.hour < 12 ? 'AM' : 'PM'}'
        '${today ? ' today' : ' on ${local.day}/${local.month}'}';
  }

  @override
  Widget build(BuildContext context) {
    // Delivery is free, so the total is the items' subtotal.
    final total = '₹${widget.order.subtotal.toStringAsFixed(2)}';

    return SiteScaffold(
      appBar: PageAppBar(title: const Text('Payment')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(24),
          children: [
            if (_sandbox)
              Container(
                key: const Key('sandboxBanner'),
                padding: const EdgeInsets.all(12),
                margin: const EdgeInsets.only(bottom: 16),
                decoration: BoxDecoration(
                  color: const Color(0xFFFFF8E1),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Text(
                  'Test mode: no real money is charged.',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontWeight: FontWeight.w600),
                ),
              ),
            Text(
              'Order total',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodyMedium,
            ),
            Text(
              total,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.headlineMedium
                  ?.copyWith(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 32),
            ..._body(),
          ],
        ),
      ),
    );
  }

  List<Widget> _body() {
    switch (_phase) {
      case _Phase.starting:
        return _waiting('Opening the payment page…');
      case _Phase.checking:
        return _waiting('Checking your payment…');
      case _Phase.paying:
        return [
          ..._waiting('Complete the payment on the Cashfree page.'),
          const SizedBox(height: 16),
          TextButton(
            onPressed: _check,
            child: const Text('I have paid: check payment'),
          ),
        ];
      case _Phase.paid:
        return _result(
          key: 'paymentPaid',
          icon: Icons.check_circle,
          color: _green,
          title: 'Payment successful',
          detail: 'Thank you! Your order is confirmed and paid.',
          actions: [_primary('View Order', _viewOrder)],
        );
      case _Phase.cashOnDelivery:
        return _result(
          key: 'paymentCod',
          icon: Icons.payments_outlined,
          color: _green,
          title: 'Cash on Delivery',
          detail: 'Your order is confirmed. Please pay in cash on delivery.',
          actions: [_primary('View Order', _viewOrder)],
        );
      case _Phase.closed:
        return _result(
          key: 'paymentClosed',
          icon: Icons.cancel_outlined,
          color: Colors.red,
          title: 'Order not paid',
          detail: _message ?? 'This order can no longer be paid.',
          actions: [_primary('View Order', _viewOrder)],
        );
      case _Phase.notPaid:
        final payBy = _payBy;
        return _result(
          key: 'paymentNotPaid',
          icon: Icons.error_outline,
          color: Colors.orange,
          title: 'Payment not completed',
          detail: [
            _message ?? 'The payment was not completed.',
            if (payBy != null)
              'Pay by ${_time(payBy)}, or the order is cancelled.',
          ].join('\n\n'),
          actions: [
            _primary('Try Again', _pay),
            const SizedBox(height: 12),
            OutlinedButton(
              key: const Key('payByCash'),
              onPressed: _switchToCashOnDelivery,
              style: OutlinedButton.styleFrom(
                foregroundColor: _green,
                side: const BorderSide(color: _green),
                minimumSize: const Size.fromHeight(48),
              ),
              child: const Text('Pay by Cash on Delivery instead'),
            ),
            const SizedBox(height: 4),
            TextButton(onPressed: _check, child: const Text('Check Payment')),
            TextButton(onPressed: _viewOrder, child: const Text('View Order')),
          ],
        );
    }
  }

  List<Widget> _waiting(String text) => [
    const Center(child: CircularProgressIndicator(color: _green)),
    const SizedBox(height: 16),
    Text(text, textAlign: TextAlign.center),
  ];

  List<Widget> _result({
    required String key,
    required IconData icon,
    required Color color,
    required String title,
    required String detail,
    required List<Widget> actions,
  }) => [
    Icon(icon, key: Key(key), size: 72, color: color),
    const SizedBox(height: 16),
    Text(
      title,
      textAlign: TextAlign.center,
      style: Theme.of(context).textTheme.titleLarge
          ?.copyWith(fontWeight: FontWeight.bold),
    ),
    const SizedBox(height: 8),
    Text(detail, textAlign: TextAlign.center),
    const SizedBox(height: 32),
    ...actions,
  ];

  Widget _primary(String label, VoidCallback onPressed) => FilledButton(
    onPressed: onPressed,
    style: FilledButton.styleFrom(
      backgroundColor: _green,
      minimumSize: const Size.fromHeight(48),
    ),
    child: Text(label),
  );
}
