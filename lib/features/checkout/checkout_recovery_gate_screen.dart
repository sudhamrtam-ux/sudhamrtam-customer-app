import 'package:flutter/material.dart';

import '../../database/checkout_recovery_executor.dart';
import '../../database/pending_order_submission_service.dart';
import '../../models/customer_order.dart';

typedef RecoveryOrderAction = Future<CheckoutRecoveryExecutionResult> Function(
  String orderId,
);

/// Restricted screen displayed when checkout recovery
/// cannot safely complete during application startup.
///
/// Normal customer navigation remains inaccessible
/// until recovery and cart initialization succeed.
///
/// When an order was started but never saved, the
/// customer chooses to finish placing it or cancel it
/// (keeping their cart).
class CheckoutRecoveryGateScreen extends StatefulWidget {
  final CheckoutRecoveryExecutionResult initialResult;

  /// Called after recovery succeeds.
  ///
  /// The parent must initialize CartManager before
  /// opening the normal customer application.
  final Future<void> Function() onRecoveryCompleted;

  /// Re-runs startup recovery.
  ///
  /// In production this is the startup controller's
  /// retry, which must succeed before cart initialization
  /// is authorized. It is also run after a finish or
  /// cancel decision for that reason.
  ///
  /// When omitted, the production recovery executor is used.
  final Future<CheckoutRecoveryExecutionResult> Function()? retryRecovery;

  /// Optional overrides for deterministic testing.
  final RecoveryOrderAction? finishPendingOrder;
  final RecoveryOrderAction? cancelPendingOrder;
  final Future<CustomerOrder?> Function()? loadPendingOrder;

  const CheckoutRecoveryGateScreen({
    super.key,
    required this.initialResult,
    required this.onRecoveryCompleted,
    this.retryRecovery,
    this.finishPendingOrder,
    this.cancelPendingOrder,
    this.loadPendingOrder,
  });

  @override
  State<CheckoutRecoveryGateScreen> createState() =>
      _CheckoutRecoveryGateScreenState();
}

class _CheckoutRecoveryGateScreenState
    extends State<CheckoutRecoveryGateScreen> {
  late CheckoutRecoveryExecutionResult _result;

  bool _isBusy = false;
  String _busyLabel = 'Checking recovery...';
  bool _startupCompleted = false;

  CustomerOrder? _pendingOrder;

  bool get _isAwaitingDecision =>
      _result.status == CheckoutRecoveryExecutionStatus.awaitingSubmission &&
      _result.orderId != null;

  @override
  void initState() {
    super.initState();
    _result = widget.initialResult;
    _loadPendingOrderSummary();
  }

  // ==========================================
  // PENDING ORDER SUMMARY
  // ==========================================

  Future<void> _loadPendingOrderSummary() async {
    if (!_isAwaitingDecision) return;

    try {
      final loader =
          widget.loadPendingOrder ??
          PendingOrderSubmissionService.instance.getPendingOrder;

      final order = await loader();

      if (!mounted) return;

      setState(() {
        _pendingOrder = order?.id == _result.orderId ? order : null;
      });
    } catch (_) {
      // The summary is informational only.
    }
  }

  // ==========================================
  // RECOVERY ACTIONS
  // ==========================================

  Future<CheckoutRecoveryExecutionResult> _retry() {
    final recoveryCallback =
        widget.retryRecovery ??
        CheckoutRecoveryExecutor.instance.recoverAtStartup;

    return recoveryCallback();
  }

  Future<void> _retryRecovery() {
    return _runRecoveryAction(
      busyLabel: 'Checking recovery...',
      action: _retry,
    );
  }

  Future<void> _finishOrder() {
    final orderId = _result.orderId!;
    final finish =
        widget.finishPendingOrder ??
        CheckoutRecoveryExecutor.instance.finishAwaitingSubmission;

    return _runRecoveryAction(
      busyLabel: 'Placing order...',
      action: () => finish(orderId),
      reinspectOnSuccess: true,
    );
  }

  Future<void> _cancelOrder() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Cancel this order?'),
        content: const Text(
          'The unfinished order will be discarded. '
          'The products stay in your cart.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Keep Order'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Cancel Order'),
          ),
        ],
      ),
    );

    if (confirmed != true || !mounted) return;

    final orderId = _result.orderId!;
    final cancel =
        widget.cancelPendingOrder ??
        CheckoutRecoveryExecutor.instance.cancelAwaitingSubmission;

    await _runRecoveryAction(
      busyLabel: 'Cancelling order...',
      action: () => cancel(orderId),
      reinspectOnSuccess: true,
    );
  }

  /// Runs one recovery action and opens the app when safe.
  ///
  /// [reinspectOnSuccess] re-runs [_retry] after a finish
  /// or cancel decision, so the startup controller itself
  /// confirms recovery before the cart is initialized.
  Future<void> _runRecoveryAction({
    required String busyLabel,
    required Future<CheckoutRecoveryExecutionResult> Function() action,
    bool reinspectOnSuccess = false,
  }) async {
    if (_isBusy || _startupCompleted) {
      return;
    }

    setState(() {
      _isBusy = true;
      _busyLabel = busyLabel;
    });

    try {
      var result = await action();

      if (reinspectOnSuccess && result.canContinueNormalStartup) {
        result = await _retry();
      }

      if (!mounted) return;

      setState(() {
        _result = result;
      });

      // Do not initialize the customer application
      // while checkout recovery remains unresolved.
      if (!result.canContinueNormalStartup) {
        return;
      }

      // Recovery succeeded. The parent now initializes
      // CartManager before opening the customer application.
      try {
        await widget.onRecoveryCompleted();

        if (!mounted) return;

        setState(() {
          _startupCompleted = true;
        });
      } catch (error) {
        if (!mounted) return;

        setState(() {
          _result = CheckoutRecoveryExecutionResult(
            status: CheckoutRecoveryExecutionStatus.blocked,
            orderId: result.orderId,
            message:
                'Checkout recovery completed, but the shopping cart '
                'could not be initialized: $error',
          );
        });
      }
    } catch (error) {
      if (!mounted) return;

      setState(() {
        _result = CheckoutRecoveryExecutionResult(
          status: CheckoutRecoveryExecutionStatus.blocked,
          orderId: _result.orderId,
          message: 'Recovery could not be completed: $error',
        );
      });
    } finally {
      if (mounted) {
        setState(() {
          _isBusy = false;
        });
      }
    }
  }

  // ==========================================
  // BUILD RECOVERY SCREEN
  // ==========================================

  Widget _busyIcon() {
    return const SizedBox(
      width: 18,
      height: 18,
      child: CircularProgressIndicator(strokeWidth: 2),
    );
  }

  Widget _pendingOrderSummary(CustomerOrder order) {
    final hasPrices = order.hasValidPrices;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 12),
        const Divider(),
        for (final item in order.items)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 2),
            child: Text(
              '${item.productName} — ${item.quantity} × ${item.unit}',
            ),
          ),
        if (hasPrices) ...[
          const SizedBox(height: 6),
          Text(
            'Total: ₹${order.subtotal.toStringAsFixed(2)}',
            style: const TextStyle(fontWeight: FontWeight.bold),
          ),
        ],
        const SizedBox(height: 6),
        Text(
          order.fulfillmentMethod == FulfillmentMethod.delivery
              ? 'Home Delivery'
              : 'Store Pickup',
        ),
      ],
    );
  }

  List<Widget> _decisionButtons() {
    final disabled = _isBusy || _startupCompleted;

    return [
      SizedBox(
        width: double.infinity,
        child: FilledButton.icon(
          onPressed: disabled ? null : _finishOrder,
          icon: _isBusy ? _busyIcon() : const Icon(Icons.check_circle_outline),
          label: Text(_isBusy ? _busyLabel : 'Finish Placing Order'),
        ),
      ),
      const SizedBox(height: 12),
      SizedBox(
        width: double.infinity,
        child: OutlinedButton.icon(
          onPressed: disabled ? null : _cancelOrder,
          icon: const Icon(Icons.remove_shopping_cart_outlined),
          label: const Text('Cancel Order, Keep Cart'),
        ),
      ),
    ];
  }

  Widget _retryButton() {
    return SizedBox(
      width: double.infinity,
      child: FilledButton.icon(
        onPressed: _isBusy || _startupCompleted ? null : _retryRecovery,
        icon: _isBusy ? _busyIcon() : const Icon(Icons.refresh),
        label: Text(
          _isBusy
              ? _busyLabel
              : _startupCompleted
              ? 'Startup Completed'
              : 'Retry Recovery',
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final pendingOrder = _isAwaitingDecision ? _pendingOrder : null;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Sudhamrtam'),
        automaticallyImplyLeading: false,
      ),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 480),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.shield_outlined,
                    size: 72,
                    color: theme.colorScheme.primary,
                  ),

                  const SizedBox(height: 24),

                  Text(
                    _isAwaitingDecision
                        ? 'Unfinished Order'
                        : 'Checkout Recovery Required',
                    style: theme.textTheme.headlineSmall,
                    textAlign: TextAlign.center,
                  ),

                  const SizedBox(height: 16),

                  const Text(
                    'Your previous checkout needs attention '
                    'before you can continue shopping.',
                    textAlign: TextAlign.center,
                  ),

                  const SizedBox(height: 24),

                  // ==================================
                  // RECOVERY DETAILS
                  // ==================================
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'Recovery details',
                            style: TextStyle(fontWeight: FontWeight.bold),
                          ),

                          const SizedBox(height: 8),

                          Text(_result.message),

                          if (_result.orderId != null) ...[
                            const SizedBox(height: 12),
                            SelectableText('Order ID: ${_result.orderId}'),
                          ],

                          if (pendingOrder != null)
                            _pendingOrderSummary(pendingOrder),
                        ],
                      ),
                    ),
                  ),

                  const SizedBox(height: 24),

                  // ==================================
                  // ACTIONS
                  // ==================================
                  if (_isAwaitingDecision)
                    ..._decisionButtons()
                  else
                    _retryButton(),

                  const SizedBox(height: 16),

                  Text(
                    'Do not clear app data or uninstall the app '
                    'while checkout recovery is pending.',
                    style: theme.textTheme.bodySmall,
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
