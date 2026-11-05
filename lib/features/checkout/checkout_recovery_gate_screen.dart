import 'package:flutter/material.dart';

import '../../database/checkout_recovery_executor.dart';

/// Restricted screen displayed when checkout recovery
/// cannot safely complete during application startup.
///
/// Normal customer navigation remains inaccessible
/// until recovery and cart initialization succeed.
class CheckoutRecoveryGateScreen extends StatefulWidget {
  final CheckoutRecoveryExecutionResult initialResult;

  /// Called after recovery succeeds.
  ///
  /// The parent must initialize CartManager before
  /// opening the normal customer application.
  final Future<void> Function() onRecoveryCompleted;

  /// Optional recovery callback for deterministic testing.
  ///
  /// When omitted, the production recovery executor is used.
  final Future<CheckoutRecoveryExecutionResult> Function()? retryRecovery;

  const CheckoutRecoveryGateScreen({
    super.key,
    required this.initialResult,
    required this.onRecoveryCompleted,
    this.retryRecovery,
  });

  @override
  State<CheckoutRecoveryGateScreen> createState() =>
      _CheckoutRecoveryGateScreenState();
}

class _CheckoutRecoveryGateScreenState
    extends State<CheckoutRecoveryGateScreen> {
  late CheckoutRecoveryExecutionResult _result;

  bool _isRetrying = false;
  bool _startupCompleted = false;

  @override
  void initState() {
    super.initState();
    _result = widget.initialResult;
  }

  // ==========================================
  // RETRY CHECKOUT RECOVERY
  // ==========================================

  Future<void> _retryRecovery() async {
    if (_isRetrying || _startupCompleted) {
      return;
    }

    setState(() {
      _isRetrying = true;
    });

    try {
      final recoveryCallback =
          widget.retryRecovery ??
          CheckoutRecoveryExecutor.instance.recoverAtStartup;

      final result = await recoveryCallback();

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
          _isRetrying = false;
        });
      }
    }
  }

  // ==========================================
  // BUILD RECOVERY SCREEN
  // ==========================================

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

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
                    'Checkout Recovery Required',
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
                        ],
                      ),
                    ),
                  ),

                  const SizedBox(height: 24),

                  // ==================================
                  // RETRY RECOVERY BUTTON
                  // ==================================
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton.icon(
                      onPressed: _isRetrying || _startupCompleted
                          ? null
                          : _retryRecovery,
                      icon: _isRetrying
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.refresh),
                      label: Text(
                        _isRetrying
                            ? 'Checking recovery...'
                            : _startupCompleted
                            ? 'Startup Completed'
                            : 'Retry Recovery',
                      ),
                    ),
                  ),

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
