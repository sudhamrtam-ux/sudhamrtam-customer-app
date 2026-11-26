import 'package:flutter/material.dart';

import '../../app/sudhamrtam_app.dart' show sudhamrtamMilkSync;
import '../../services/milk_bill_api_client.dart';
import 'milk_bills_screen.dart' show billDateLabel, billRupees;

const _green = Color(0xFF3F6A14);
const _border = Color(0xFFD9E6C8);

/// The day after [date] ("2026-11-09" → "2026-11-10").
String _dayAfter(String date) {
  final d = DateTime.parse(date).add(const Duration(days: 1));
  return '${d.year}-${d.month.toString().padLeft(2, '0')}-'
      '${d.day.toString().padLeft(2, '0')}';
}

/// "Settle bill and close subscription" on the Milk Bills page (owner
/// request and decisions 2026-11-26). Milk stops on the next possible
/// day, the account stays, and the final bill comes the morning after
/// the last delivery. Shows nothing without subscriptions or a closing.
class SettleAndCloseCard extends StatefulWidget {
  const SettleAndCloseCard({
    super.key,
    required this.api,
    this.onClosed,
    this.onOpenBill,
  });

  final MilkBillApiClient api;

  /// After closing (the bills list may want to reload).
  final VoidCallback? onClosed;

  /// Opens a final bill by its ID.
  final void Function(String billId)? onOpenBill;

  @override
  State<SettleAndCloseCard> createState() => _SettleAndCloseCardState();
}

class _SettleAndCloseCardState extends State<SettleAndCloseCard> {
  ClosingInfo? _info;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final info = await widget.api.fetchClosing();
      if (mounted) setState(() => _info = info);
    } on MilkBillException {
      // The bills still show; the card waits for the next visit.
    }
  }

  Future<void> _settle() async {
    final info = _info;
    if (info == null || _busy) return;
    final yes = await showDialog<bool>(
      context: context,
      builder: (context) => _SettleDialog(info: info),
    );
    if (yes != true || !mounted) return;
    setState(() => _busy = true);
    try {
      final after = await widget.api.closeSubscription();
      if (!mounted) return;
      setState(() => _info = after);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Your subscription is closed. Last milk: '
            '${billDateLabel(after.closing?.lastDeliveryDate ?? info.lastDeliveryDate)}.',
          ),
        ),
      );
      // The plans on this phone show as cancelled.
      await sudhamrtamMilkSync.refresh(force: true);
      widget.onClosed?.call();
    } on MilkBillException catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(error.message)));
        await _load();
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Widget _frame({required Key key, required List<Widget> children}) =>
      Container(
        key: key,
        margin: const EdgeInsets.only(top: 8, bottom: 16),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: const Color(0xFFF7FAF2),
          border: Border.all(color: _border),
          borderRadius: BorderRadius.circular(14),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: children,
        ),
      );

  Widget _title(IconData icon, String text) => Row(
    children: [
      Icon(icon, color: _green, size: 20),
      const SizedBox(width: 8),
      Expanded(
        child: Text(
          text,
          style: const TextStyle(
            fontWeight: FontWeight.w600,
            fontSize: 15,
            color: _green,
          ),
        ),
      ),
    ],
  );

  @override
  Widget build(BuildContext context) {
    final info = _info;
    if (info == null) return const SizedBox.shrink();
    final closing = info.closing;

    // Closed, final bill on its way.
    if (closing != null && closing.isWaiting) {
      return _frame(
        key: const Key('closing-waiting'),
        children: [
          _title(Icons.event_available_outlined, 'Subscription closed'),
          const SizedBox(height: 6),
          Text(
            'Last milk delivery: ${billDateLabel(closing.lastDeliveryDate)}. '
            'Your final bill comes on the morning of '
            '${billDateLabel(_dayAfter(closing.lastDeliveryDate))}; '
            'we will let you know.',
          ),
        ],
      );
    }

    // Closed and billed: pay what is left, or all settled.
    if (closing != null && info.openPlans == 0) {
      if (info.unpaidPaise > 0) {
        final unpaidFinal = closing.billIds.isEmpty
            ? null
            : closing.billIds.last;
        return _frame(
          key: const Key('closing-pay'),
          children: [
            _title(
              Icons.receipt_long_outlined,
              'Final bill ready: ${billRupees(info.unpaidPaise)} to pay',
            ),
            const SizedBox(height: 6),
            const Text(
              'Pay online, by UPI, or in cash to our delivery partner. '
              'Your account stays open; you can subscribe again once it is paid.',
            ),
            if (unpaidFinal != null && widget.onOpenBill != null) ...[
              const SizedBox(height: 10),
              FilledButton.icon(
                key: const Key('closing-pay-bill'),
                onPressed: () => widget.onOpenBill!(unpaidFinal),
                icon: const Icon(Icons.payments_outlined, size: 18),
                label: const Text('Pay final bill'),
                style: FilledButton.styleFrom(
                  backgroundColor: const Color(0xFF82B440),
                ),
              ),
            ],
          ],
        );
      }
      return _frame(
        key: const Key('closing-settled'),
        children: [
          _title(Icons.verified_outlined, 'Subscription closed and settled'),
          const SizedBox(height: 6),
          const Text(
            'Thank you for being with Sudhamrtam. Your account stays open: '
            'shop any time, or start a new subscription whenever you like.',
          ),
        ],
      );
    }

    if (!info.canClose) return const SizedBox.shrink();
    return _frame(
      key: const Key('closing-offer'),
      children: [
        _title(Icons.logout_outlined, 'Moving out or stopping milk?'),
        const SizedBox(height: 6),
        const Text(
          'Close your milk subscription and settle the full and final bill '
          'in one go. Your account stays open.',
        ),
        const SizedBox(height: 10),
        OutlinedButton.icon(
          key: const Key('settle-and-close'),
          onPressed: _busy ? null : _settle,
          icon: _busy
              ? const SizedBox.square(
                  dimension: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.task_alt_outlined, size: 18),
          label: const Text('Settle bill and close subscription'),
          style: OutlinedButton.styleFrom(
            foregroundColor: _green,
            side: const BorderSide(color: Color(0xFF82B440)),
          ),
        ),
      ],
    );
  }
}

/// What closing means, before the customer says yes.
class _SettleDialog extends StatelessWidget {
  const _SettleDialog({required this.info});

  final ClosingInfo info;

  @override
  Widget build(BuildContext context) {
    Widget row(String label, String value, {bool bold = false}) => Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        children: [
          Expanded(child: Text(label)),
          Text(
            value,
            style: TextStyle(
              fontWeight: bold ? FontWeight.bold : FontWeight.w500,
            ),
          ),
        ],
      ),
    );
    final last = billDateLabel(info.lastDeliveryDate);
    return AlertDialog(
      title: const Text('Settle bill and close subscription?'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'All your milk subscriptions stop after $last. '
              'Your account stays open: you can still shop and see your bills.',
            ),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: const Color(0xFFF5F8F0),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Column(
                children: [
                  row('Last milk delivery', last),
                  if (info.unpaidPaise > 0)
                    row('Unpaid bills', billRupees(info.unpaidPaise)),
                  row('Milk delivered, not billed yet', billRupees(info.soFarPaise)),
                  const Divider(),
                  row(
                    'To settle (about)',
                    billRupees(info.totalPaise),
                    bold: true,
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            Text(
              'Your final bill comes on the morning of '
              '${billDateLabel(_dayAfter(info.lastDeliveryDate))}, with the '
              'exact amount (including the last delivery). Pay online, by '
              'UPI, or in cash to our delivery partner.',
              style: const TextStyle(color: Colors.black54, fontSize: 13),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: const Text('Back'),
        ),
        FilledButton(
          key: const Key('settle-confirm'),
          onPressed: () => Navigator.of(context).pop(true),
          style: FilledButton.styleFrom(
            backgroundColor: const Color(0xFF82B440),
          ),
          child: const Text('Close subscription'),
        ),
      ],
    );
  }
}
