import 'package:flutter/material.dart';

import '../../core/widgets/period_filter.dart';
import '../../core/widgets/site_layout.dart';

import '../../app/sudhamrtam_app.dart';
import '../../models/milk_subscription_manager.dart';
import '../../services/milk_bill_api_client.dart';
import '../../services/order_api_client.dart' show onlinePaymentWorksHere;
import '../payment/payment_launcher.dart';
import 'bill_pdf.dart';
import 'milk_calendar.dart';
import '../../core/widgets/page_app_bar.dart';

const _green = Color(0xFF4E8A1E);
const _brandGreen = Color(0xFF82B440);

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

/// "2026-10" → "October 2026".
String billMonthLabel(String month) {
  final parts = month.split('-');
  return '${_months[int.parse(parts[1]) - 1]} ${parts[0]}';
}

/// "2026-11-08" → "8 Nov 2026".
String billDateLabel(String date) {
  final parts = date.split('-');
  final name = _months[int.parse(parts[1]) - 1].substring(0, 3);
  return '${int.parse(parts[2])} $name ${parts[0]}';
}

/// 23000 → "₹230", 23050 → "₹230.50", 139500 → "₹1,395",
/// 12345600 → "₹1,23,456" (Indian grouping).
String billRupees(int paise) {
  final digits = (paise ~/ 100).toString();
  final rest = paise % 100;
  var whole = digits;
  if (digits.length > 3) {
    final head = digits.substring(0, digits.length - 3);
    final groups = <String>[];
    for (var end = head.length; end > 0; end -= 2) {
      groups.insert(0, head.substring(end - 2 < 0 ? 0 : end - 2, end));
    }
    whole = '${groups.join(',')},${digits.substring(digits.length - 3)}';
  }
  return rest == 0 ? '₹$whole' : '₹$whole.${rest.toString().padLeft(2, '0')}';
}

/// 1500 → "1.50 L".
/// "Early morning", "Morning" or "Evening".
String billShiftLabel(String shift) => switch (shift) {
  'early_morning' => 'Early morning',
  'morning' => 'Morning',
  _ => 'Evening',
};

/// Always two decimals (owner decision 2026-11-11): "1.50 L".
String billLitres(int ml) => '${(ml / 1000).toStringAsFixed(2)} L';

(String, Color) _statusLabel(MilkBill bill) {
  if (bill.isPaid) {
    return (
      switch (bill.paymentMethod) {
        'cash' => 'Paid in cash',
        // Scanned the bill's UPI QR; recorded by staff (2026-11-24).
        'upi' => 'Paid by UPI',
        _ => 'Paid online',
      },
      _green,
    );
  }
  if (bill.overdue) return ('Overdue', Colors.red.shade700);
  return ('Payment due', Colors.orange.shade800);
}

/// A reminder on the Milk Plan tab: unpaid bills, or a way to the
/// paid ones. Shows nothing when signed out or when there are none.
class MilkBillsReminder extends StatefulWidget {
  const MilkBillsReminder({
    super.key,
    this.api,
    this.launcher,
    this.unpaidOnly = false,
  });

  final MilkBillApiClient? api;
  final PaymentLauncher? launcher;

  /// Home shows it only when a bill is waiting to be paid.
  final bool unpaidOnly;

  @override
  State<MilkBillsReminder> createState() => _MilkBillsReminderState();
}

class _MilkBillsReminderState extends State<MilkBillsReminder> {
  List<MilkBill>? _bills;

  MilkBillApiClient? get _api => widget.api ?? sudhamrtamMilkBills;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final api = _api;
    if (api == null || !api.isSignedIn) {
      if (mounted) setState(() => _bills = null);
      return;
    }
    try {
      final bills = await api.fetchBills();
      if (mounted) setState(() => _bills = bills);
    } on MilkBillException {
      // A reminder only: the Account tab still has the bills.
    }
  }

  Future<void> _open() async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => MilkBillsScreen(api: _api, launcher: widget.launcher),
      ),
    );
    await _load();
  }

  @override
  Widget build(BuildContext context) {
    final bills = _bills;
    if (bills == null || bills.isEmpty) return const SizedBox.shrink();

    final unpaid = bills.where((b) => b.isUnpaid).toList();
    if (unpaid.isEmpty && widget.unpaidOnly) return const SizedBox.shrink();
    final overdue = unpaid.any((b) => b.overdue);
    final total = unpaid.fold(0, (sum, b) => sum + b.totalPaise);

    final String title;
    final String subtitle;
    if (unpaid.isEmpty) {
      title = 'Milk Bills';
      subtitle = 'All paid. Tap to see your bills.';
    } else if (unpaid.length == 1) {
      final bill = unpaid.single;
      title =
          '${billMonthLabel(bill.month)} milk bill: '
          '${billRupees(bill.totalPaise)}';
      subtitle = bill.overdue
          ? 'Was due by ${billDateLabel(bill.dueDate!)}. Tap to pay.'
          : 'Due by ${billDateLabel(bill.dueDate!)}. Tap to pay.';
    } else {
      title = '${unpaid.length} unpaid milk bills: ${billRupees(total)}';
      subtitle = 'Tap to see and pay them.';
    }

    return Card(
      key: const Key('milkBillsReminder'),
      margin: const EdgeInsets.only(bottom: 16),
      color: unpaid.isEmpty
          ? null
          : overdue
          ? const Color(0xFFFFEBEE)
          : const Color(0xFFFFF8E1),
      child: ListTile(
        leading: Icon(
          Icons.receipt_long_outlined,
          color: unpaid.isEmpty
              ? _brandGreen
              : overdue
              ? Colors.red.shade700
              : Colors.orange.shade800,
        ),
        title: Text(title, style: const TextStyle(fontWeight: FontWeight.w600)),
        subtitle: Text(subtitle),
        trailing: const Icon(Icons.chevron_right),
        onTap: _open,
      ),
    );
  }
}

/// The customer's monthly milk bills.
class MilkBillsScreen extends StatefulWidget {
  const MilkBillsScreen({
    super.key,
    this.api,
    this.launcher,
    this.today,
    this.plans,
  });

  final MilkBillApiClient? api;
  final PaymentLauncher? launcher;

  /// The customer's milk plans (vacation days); defaults to the app's.
  final MilkSubscriptionManager? plans;

  /// For tests; defaults to now.
  final DateTime Function()? today;

  @override
  State<MilkBillsScreen> createState() => _MilkBillsScreenState();
}

class _MilkBillsScreenState extends State<MilkBillsScreen> {
  List<MilkBill>? _bills;

  /// How far back the bills go (owner request 2026-11-26).
  Period _period = Period.all;
  String? _error;

  MilkBillApiClient? get _api => widget.api ?? sudhamrtamMilkBills;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final api = _api;
    if (api == null) {
      setState(() => _error = 'Milk bills need a connection to Sudhamrtam.');
      return;
    }
    setState(() => _error = null);
    try {
      final bills = await api.fetchBills();
      if (mounted) setState(() => _bills = bills);
    } on MilkBillException catch (error) {
      if (mounted) setState(() => _error = error.message);
    }
  }

  Future<void> _open(MilkBill bill) async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => MilkBillScreen(
          bill: bill,
          api: _api!,
          launcher: widget.launcher ?? CashfreePaymentLauncher(),
        ),
      ),
    );
    await _load();
  }

  /// A bill (month "2026-11") is in the period when any of its days is.
  bool _billShown(String month) {
    final parts = month.split('-');
    final lastDay = DateTime(int.parse(parts[0]), int.parse(parts[1]) + 1, 0);
    return _period.includes(lastDay, (widget.today ?? DateTime.now)());
  }

  @override
  Widget build(BuildContext context) {
    final bills = _bills;
    return SiteScaffold(
      appBar: PageAppBar(title: const Text('Milk Bills')),
      body: SafeArea(
        child: bills == null
            ? Center(
                child: _error == null
                    ? const CircularProgressIndicator(color: _brandGreen)
                    : Padding(
                        padding: const EdgeInsets.all(24),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(_error!, textAlign: TextAlign.center),
                            const SizedBox(height: 8),
                            TextButton(
                              onPressed: _load,
                              child: const Text('Try again'),
                            ),
                          ],
                        ),
                      ),
              )
            : RefreshIndicator(
                onRefresh: _load,
                child: ListView(
                  padding: const EdgeInsets.all(16),
                  children: [
                    MilkCalendar(
                      api: _api!,
                      today: widget.today,
                      plans: widget.plans,
                    ),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(4, 4, 4, 8),
                      child: Row(
                        children: [
                          Expanded(
                            child: Text(
                              'Bills',
                              style: Theme.of(context).textTheme.titleMedium
                                  ?.copyWith(fontWeight: FontWeight.bold),
                            ),
                          ),
                          if (bills.isNotEmpty)
                            PeriodFilter(
                              value: _period,
                              options: const [
                                Period.all,
                                Period.months3,
                                Period.months6,
                              ],
                              onChanged: (p) => setState(() => _period = p),
                            ),
                        ],
                      ),
                    ),
                    if (bills.isNotEmpty &&
                        !bills.any((b) => _billShown(b.month)))
                      const Padding(
                        padding: EdgeInsets.all(24),
                        child: Text(
                          'No bills in this period.',
                          textAlign: TextAlign.center,
                        ),
                      ),
                    if (bills.isEmpty)
                      const Padding(
                        padding: EdgeInsets.all(32),
                        child: Text(
                          'No bills yet. Your milk bill comes after the end '
                          'of each month, for the milk delivered that month.',
                          textAlign: TextAlign.center,
                        ),
                      ),
                    for (final bill in bills)
                      if (_billShown(bill.month))
                        _BillCard(bill: bill, onTap: () => _open(bill)),
                  ],
                ),
              ),
      ),
    );
  }
}

/// 1000 → "10%", 250 → "2.5%".
String billPercent(int basisPoints) {
  final value = basisPoints / 100;
  return value == value.roundToDouble()
      ? '${value.toStringAsFixed(0)}%'
      : '${value.toStringAsFixed(basisPoints % 10 == 0 ? 1 : 2)}%';
}

/// Actual amount − discount + GST = total, as on the paper bill.
class _BillAmounts extends StatelessWidget {
  const _BillAmounts({required this.bill});

  final MilkBill bill;

  @override
  Widget build(BuildContext context) {
    Widget row(String label, String value, {bool bold = false}) => Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: [
          Expanded(
            child: Text(
              label,
              style: bold ? const TextStyle(fontWeight: FontWeight.bold) : null,
            ),
          ),
          Text(
            value,
            style: bold ? const TextStyle(fontWeight: FontWeight.bold) : null,
          ),
        ],
      ),
    );
    final percent = bill.discountPercentBp;
    return Container(
      key: const Key('billAmounts'),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFFF5F8F0),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        children: [
          row('Actual amount', billRupees(bill.subtotalPaise)),
          if (bill.discountPaise > 0)
            row(
              percent == null
                  ? 'Discount'
                  : 'Discount (${billPercent(percent)})',
              '− ${billRupees(bill.discountPaise)}',
            ),
          row('GST', '+ ${billRupees(bill.gstPaise)}'),
          const Divider(),
          row('Total', billRupees(bill.totalPaise), bold: true),
        ],
      ),
    );
  }
}

class _StatusPill extends StatelessWidget {
  const _StatusPill(this.bill);

  final MilkBill bill;

  @override
  Widget build(BuildContext context) {
    final (text, color) = _statusLabel(bill);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        text,
        style: TextStyle(
          color: color,
          fontWeight: FontWeight.w600,
          fontSize: 12,
        ),
      ),
    );
  }
}

class _BillCard extends StatelessWidget {
  const _BillCard({required this.bill, required this.onTap});

  final MilkBill bill;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: ListTile(
        title: Text(
          '${billMonthLabel(bill.month)} · ${billRupees(bill.totalPaise)}',
          style: const TextStyle(fontWeight: FontWeight.w600),
        ),
        subtitle: Padding(
          padding: const EdgeInsets.only(top: 4),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                [
                  for (final m in bill.milk) '${m.productName} ${m.amountText}',
                  if (bill.items.isNotEmpty)
                    '${bill.items.length} extra item(s)',
                ].join(', '),
              ),
              const SizedBox(height: 4),
              _StatusPill(bill),
            ],
          ),
        ),
        trailing: const Icon(Icons.chevron_right),
        onTap: onTap,
      ),
    );
  }
}

/// One bill, day by day, with online payment. Whether it is paid is
/// always decided by the server, never by the payment screen.
class MilkBillScreen extends StatefulWidget {
  const MilkBillScreen({
    super.key,
    required this.bill,
    required this.api,
    required this.launcher,
    this.confirmDelay = const Duration(seconds: 2),
  });

  final MilkBill bill;
  final MilkBillApiClient api;
  final PaymentLauncher launcher;

  /// Wait between checks while Cashfree confirms a payment.
  final Duration confirmDelay;

  @override
  State<MilkBillScreen> createState() => _MilkBillScreenState();
}

class _MilkBillScreenState extends State<MilkBillScreen> {
  late MilkBill _bill = widget.bill;
  bool _busy = false;
  bool _sandbox = false;
  bool _checkedOnce = false;
  String? _message;

  /// The server's answer, keeping the lines it leaves out.
  void _apply(MilkBill fresh) {
    setState(() {
      _bill = MilkBill(
        id: fresh.id,
        month: fresh.month,
        status: fresh.status,
        totalPaise: fresh.totalPaise,
        subtotalPaise: fresh.subtotalPaise,
        discountPaise: fresh.discountPaise,
        discountPercentBp: fresh.discountPercentBp,
        gstPaise: fresh.gstPaise,
        dueDate: fresh.dueDate,
        paymentMethod: fresh.paymentMethod,
        overdue: fresh.overdue,
        milk: fresh.milk,
        lines: fresh.lines.isEmpty ? _bill.lines : fresh.lines,
        items: fresh.items.isEmpty ? _bill.items : fresh.items,
        periodEnd: fresh.periodEnd,
      );
    });
  }

  /// The bill as a PDF, like the paper bill, to save or share.
  Future<void> _download() async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      final data = await widget.api.fetchPrint(_bill.id);
      final bytes = await buildBillPdf(data, logo: await billLogo());
      await outputBillPdf(
        bytes,
        'Sudhamrtam milk bill ${_bill.month}',
        share: true,
      );
    } on MilkBillException catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(error.message)));
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not make the PDF. Try again.')),
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _pay() async {
    if (_busy) return;
    // No Cashfree checkout in the Windows app (2026-11-25).
    if (!onlinePaymentWorksHere) {
      setState(() => _message = onlinePaymentNotHere);
      return;
    }
    setState(() {
      _busy = true;
      _message = null;
    });
    try {
      final session = await widget.api.startPayment(_bill.id);
      if (mounted) setState(() => _sandbox = session.isSandbox);

      final result = await widget.launcher.launch(session);
      await _confirm(
        expectPaid: result is PaymentLaunchFinished,
        notPaidMessage: result is PaymentLaunchFailed
            ? result.message
            : 'We have not received the payment confirmation yet. If money '
                  'was deducted, tap Check Payment in a minute.',
      );
    } on MilkBillException catch (error) {
      if (error.isAlreadyPaid) {
        await _confirm(notPaidMessage: error.message);
      } else if (mounted) {
        setState(() => _message = error.message);
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _check() async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _message = null;
    });
    try {
      await _confirm(notPaidMessage: 'This bill has not been paid yet.');
    } on MilkBillException catch (error) {
      if (mounted) setState(() => _message = error.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// After a reported success Cashfree may need a moment, so a few
  /// checks are made.
  Future<void> _confirm({
    bool expectPaid = false,
    required String notPaidMessage,
  }) async {
    var bill = await widget.api.checkPayment(_bill.id);
    for (var i = 0; expectPaid && bill.isUnpaid && i < 3; i++) {
      await Future<void>.delayed(widget.confirmDelay);
      bill = await widget.api.checkPayment(_bill.id);
    }
    if (!mounted) return;
    _apply(bill);
    setState(() {
      _checkedOnce = true;
      _message = bill.isUnpaid ? notPaidMessage : null;
    });
  }

  @override
  Widget build(BuildContext context) {
    final bill = _bill;
    final theme = Theme.of(context);

    return SiteScaffold(
      appBar: PageAppBar(
        title: Text('Bill for ${billMonthLabel(bill.month)}'),
        actions: [
          if (bill.status != 'cancelled')
            IconButton(
              key: const Key('downloadBill'),
              tooltip: 'Download bill (PDF)',
              onPressed: _busy ? null : _download,
              icon: const Icon(Icons.picture_as_pdf_outlined),
            ),
        ],
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            if (_sandbox)
              Container(
                key: const Key('billSandboxBanner'),
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
              billRupees(bill.totalPaise),
              style: theme.textTheme.headlineMedium?.copyWith(
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 4),
            Row(
              children: [
                _StatusPill(bill),
                if (bill.isUnpaid && bill.dueDate != null) ...[
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      '${bill.overdue ? 'Was due by' : 'Due by'} '
                      '${billDateLabel(bill.dueDate!)}',
                    ),
                  ),
                ],
              ],
            ),
            if (bill.periodEnd != null) ...[
              const SizedBox(height: 6),
              Text(
                'Final bill up to ${billDateLabel(bill.periodEnd!)}',
                key: const Key('billPeriodEnd'),
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
            ],
            const SizedBox(height: 12),
            for (final m in bill.milk)
              Text(
                '${m.productName}: ${m.amountText} · '
                '${billRupees(m.amountPaise)}',
              ),
            if (bill.items.isNotEmpty)
              Text(
                'Extra items: '
                '${billRupees(bill.items.fold(0, (s, i) => s + i.amountPaise))}',
                key: const Key('billExtraItems'),
              ),
            const SizedBox(height: 12),
            _BillAmounts(bill: bill),
            const SizedBox(height: 16),
            if (bill.status == 'cancelled')
              const Text('This bill was cancelled by Sudhamrtam.')
            else if (bill.isUnpaid) ...[
              if (_message != null)
                Container(
                  key: const Key('billPaymentMessage'),
                  padding: const EdgeInsets.all(12),
                  margin: const EdgeInsets.only(bottom: 12),
                  decoration: BoxDecoration(
                    color: const Color(0xFFFFF8E1),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(_message!),
                ),
              FilledButton(
                key: const Key('payBillOnline'),
                onPressed: _busy ? null : _pay,
                style: FilledButton.styleFrom(
                  backgroundColor: _brandGreen,
                  minimumSize: const Size.fromHeight(48),
                ),
                child: _busy
                    ? const SizedBox.square(
                        dimension: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : Text('Pay ${billRupees(bill.totalPaise)} online'),
              ),
              if (_checkedOnce || _message != null)
                TextButton(
                  onPressed: _busy ? null : _check,
                  child: const Text('Check Payment'),
                ),
              const SizedBox(height: 4),
              const Text(
                'You can also pay in cash to Sudhamrtam staff.',
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.black54),
              ),
            ] else
              Row(
                key: const Key('billPaid'),
                children: [
                  const Icon(Icons.check_circle, color: _green),
                  const SizedBox(width: 8),
                  const Expanded(child: Text('Thank you! This bill is paid.')),
                ],
              ),
            const SizedBox(height: 24),
            Text(
              'Delivered day by day',
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.bold,
              ),
            ),
            const Divider(),
            for (final line in bill.lines)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 6),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Text(
                        '${billDateLabel(line.deliveryDate)} · '
                        '${billShiftLabel(line.shift)}\n'
                        '${line.productName} ${line.amountText} at '
                        '${billRupees(line.unitPricePaise)} '
                        '${line.isPack ? 'per pack' : 'per litre'}',
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(billRupees(line.amountPaise)),
                  ],
                ),
              ),
            if (bill.items.isNotEmpty) ...[
              const SizedBox(height: 16),
              Text(
                'Extra items you ordered',
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
              ),
              const Divider(),
              for (final item in bill.items)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 6),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: Text(
                          '${billDateLabel(item.deliveryDate)} · '
                          '${billShiftLabel(item.shift)}\n'
                          '${item.quantity} × ${item.productName} '
                          '(${item.unitLabel}) at '
                          '${billRupees(item.unitPricePaise)}',
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(billRupees(item.amountPaise)),
                    ],
                  ),
                ),
            ],
          ],
        ),
      ),
    );
  }
}
