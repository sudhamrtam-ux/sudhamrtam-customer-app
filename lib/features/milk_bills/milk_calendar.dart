import 'package:flutter/material.dart';

import '../../app/sudhamrtam_app.dart';
import '../../models/milk_subscription.dart';
import '../../models/milk_subscription_manager.dart';
import '../../services/milk_bill_api_client.dart';
import '../milk_plan/vacation_days_screen.dart';
import 'milk_bills_screen.dart';

const _green = Color(0xFF4E8A1E);
const _deliveredFill = Color(0xFFE5F0D7);
const _missedFill = Color(0xFFFDE2E1);
const _missedText = Color(0xFFC62828);
const _pendingFill = Color(0xFFFFF4D6);
const _pausedFill = Color(0xFFECEFF1);
const _pausedText = Color(0xFF607D8B);
const _pendingText = Color(0xFF8A6D00);
const _vacationFill = Color(0xFFE3F2FD);
const _vacationText = Color(0xFF1565C0);

String _milkName(String productId) =>
    productId == 'buffalo_milk' ? 'Buffalo Milk' : 'Cow Milk';

/// "2026-11-15" for [d].
String _dateKey(DateTime d) =>
    '${d.year}-${d.month.toString().padLeft(2, '0')}-'
    '${d.day.toString().padLeft(2, '0')}';

/// Months of history the server keeps for customers.
const _historyMonths = 12;

/// "2026-11" for [date].
String _monthOf(DateTime date) =>
    '${date.year}-${date.month.toString().padLeft(2, '0')}';

/// [month] ("2026-11") moved by [by] months.
String _addMonths(String month, int by) {
  final parts = month.split('-').map(int.parse).toList();
  return _monthOf(DateTime(parts[0], parts[1] + by));
}

/// Why milk was not delivered, in the customer's words.
String missedReasonLabel(String? reason) => switch (reason) {
  'customer_not_available' => 'Nobody was available',
  'customer_refused' => 'Refused at the door',
  'address_not_found' => 'Address not found',
  // Nobody marked it that day: not delivered, not charged.
  _ => 'Not delivered',
};

/// The month's milk as a calendar: each date shows the litres
/// delivered and their amount; tap a date for its deliveries.
/// Below it, the month's totals, as on the paper bill.
///
/// Vacation days the customer chose (owner decision 2026-11-11) show
/// from today on, from their milk plans, so the calendar can go
/// forward to the months they are away.
class MilkCalendar extends StatefulWidget {
  const MilkCalendar({super.key, required this.api, this.today, this.plans});

  final MilkBillApiClient api;

  /// The customer's milk plans; defaults to the app's.
  final MilkSubscriptionManager? plans;

  /// For tests; defaults to now.
  final DateTime Function()? today;

  @override
  State<MilkCalendar> createState() => _MilkCalendarState();
}

class _MilkCalendarState extends State<MilkCalendar> {
  late final String _thisMonth;
  late String _month;
  MilkDeliveryMonth? _data;
  String? _error;
  bool _loading = false;

  DateTime get _today => (widget.today ?? DateTime.now)();

  String get _earliest => _addMonths(_thisMonth, -(_historyMonths - 1));

  MilkSubscriptionManager get _plans =>
      widget.plans ?? sudhamrtamMilkSubscriptions;

  /// Upcoming vacation days: date → the milk not coming that day.
  Map<String, List<String>> get _vacation {
    final days = <String, List<String>>{};
    for (final plan in _plans.subscriptions) {
      if (plan.status != MilkSubscriptionStatus.active) continue;
      for (final d in plan.vacationDaysFrom(_today)) {
        (days[_dateKey(d)] ??= []).add(_milkName(plan.productId));
      }
    }
    return days;
  }

  /// The last month to show: this one, or the last with vacation.
  String get _lastMonth {
    final keys = _vacation.keys.toList()..sort();
    final last = keys.isEmpty ? _thisMonth : keys.last.substring(0, 7);
    return last.compareTo(_thisMonth) > 0 ? last : _thisMonth;
  }

  @override
  void initState() {
    super.initState();
    _thisMonth = _monthOf(_today);
    _month = _thisMonth;
    _plans.addListener(_plansChanged);
    _load();
  }

  @override
  void dispose() {
    _plans.removeListener(_plansChanged);
    super.dispose();
  }

  void _plansChanged() {
    if (mounted) setState(() {});
  }

  Future<void> _load() async {
    final month = _month;
    // A month ahead has no deliveries yet: only vacation days.
    if (month.compareTo(_thisMonth) > 0) {
      setState(() {
        _loading = false;
        _error = null;
        _data = null;
      });
      return;
    }
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final data = await widget.api.fetchDeliveries(month);
      if (!mounted || month != _month) return;
      setState(() {
        _data = data;
        _loading = false;
      });
    } on MilkBillException catch (error) {
      if (!mounted || month != _month) return;
      setState(() {
        _error = error.message;
        _loading = false;
      });
    }
  }

  void _go(int by) {
    setState(() {
      _month = _addMonths(_month, by);
      _data = null;
    });
    _load();
  }

  @override
  Widget build(BuildContext context) {
    final data = _data;
    final vacation = _vacation;
    final isFuture = _month.compareTo(_thisMonth) > 0;
    final vacationThisMonth = [
      for (final key in vacation.keys)
        if (key.startsWith(_month)) DateTime.parse(key),
    ];
    return Card(
      margin: const EdgeInsets.only(bottom: 16),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(8, 4, 8, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                IconButton(
                  tooltip: 'Previous month',
                  icon: const Icon(Icons.chevron_left),
                  onPressed: _month.compareTo(_earliest) > 0
                      ? () => _go(-1)
                      : null,
                ),
                Expanded(
                  child: Text(
                    billMonthLabel(_month),
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                IconButton(
                  tooltip: 'Next month',
                  icon: const Icon(Icons.chevron_right),
                  onPressed: _month.compareTo(_lastMonth) < 0
                      ? () => _go(1)
                      : null,
                ),
              ],
            ),
            const _WeekdayHeader(),
            const SizedBox(height: 4),
            _MonthGrid(
              month: _month,
              today: _today,
              data: data,
              vacation: vacation,
              onTapDay: (date) => _showDay(context, date),
            ),
            const SizedBox(height: 8),
            const _Legend(),
            const SizedBox(height: 12),
            if (vacationThisMonth.isNotEmpty)
              Container(
                key: const Key('calendarVacation'),
                margin: const EdgeInsets.only(bottom: 8),
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: _vacationFill,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  'Vacation: no milk on '
                  '${vacationDaysText(vacationThisMonth)}.',
                  style: const TextStyle(
                    color: _vacationText,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            if (isFuture)
              const SizedBox.shrink()
            else if (_loading && data == null)
              const Center(
                child: Padding(
                  padding: EdgeInsets.all(8),
                  child: CircularProgressIndicator(),
                ),
              )
            else if (_error != null)
              Column(
                children: [
                  Text(_error!, textAlign: TextAlign.center),
                  TextButton(onPressed: _load, child: const Text('Try again')),
                ],
              )
            else if (data != null)
              _MonthTotals(data: data, isThisMonth: _month == _thisMonth),
          ],
        ),
      ),
    );
  }

  void _showDay(BuildContext context, String date) {
    final deliveries = _data?.on(date) ?? const <MilkDelivery>[];
    final away = _vacation[date] ?? const <String>[];
    if (deliveries.isEmpty && away.isEmpty) return;
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                billDateLabel(date),
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: 8),
              if (away.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 6),
                  child: Text(
                    'Vacation: no ${away.join(' or ')} this day.',
                    style: const TextStyle(
                      color: _vacationText,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              for (final delivery in deliveries) _DeliveryDetail(delivery),
            ],
          ),
        ),
      ),
    );
  }
}

class _WeekdayHeader extends StatelessWidget {
  const _WeekdayHeader();

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        for (final day in const [
          'Mon',
          'Tue',
          'Wed',
          'Thu',
          'Fri',
          'Sat',
          'Sun',
        ])
          Expanded(
            child: Text(
              day,
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 12,
                color: Colors.black54,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
      ],
    );
  }
}

class _MonthGrid extends StatelessWidget {
  const _MonthGrid({
    required this.month,
    required this.today,
    required this.data,
    required this.onTapDay,
    this.vacation = const {},
  });

  final String month;
  final DateTime today;
  final MilkDeliveryMonth? data;
  final Map<String, List<String>> vacation;
  final void Function(String date) onTapDay;

  @override
  Widget build(BuildContext context) {
    final parts = month.split('-').map(int.parse).toList();
    final first = DateTime(parts[0], parts[1]);
    final days = DateTime(parts[0], parts[1] + 1, 0).day;
    // Monday = column 0.
    final blanks = first.weekday - 1;
    final cells = blanks + days;
    final rows = (cells / 7).ceil();
    final todayText =
        '${today.year}-${today.month.toString().padLeft(2, '0')}-'
        '${today.day.toString().padLeft(2, '0')}';

    return Column(
      children: [
        for (var row = 0; row < rows; row++)
          Row(
            children: [
              for (var col = 0; col < 7; col++)
                Expanded(
                  child: () {
                    final day = row * 7 + col - blanks + 1;
                    if (day < 1 || day > days) {
                      return const SizedBox(height: _DayCell.height);
                    }
                    final date = '$month-${day.toString().padLeft(2, '0')}';
                    return _DayCell(
                      key: Key('day-$date'),
                      day: day,
                      deliveries: data?.on(date) ?? const [],
                      onVacation: vacation.containsKey(date),
                      isToday: date == todayText,
                      onTap: () => onTapDay(date),
                    );
                  }(),
                ),
            ],
          ),
      ],
    );
  }
}

class _DayCell extends StatelessWidget {
  const _DayCell({
    super.key,
    required this.day,
    required this.deliveries,
    required this.isToday,
    required this.onTap,
    this.onVacation = false,
  });

  static const double height = 64;

  final int day;
  final List<MilkDelivery> deliveries;

  /// A vacation day the customer chose (today or later).
  final bool onVacation;
  final bool isToday;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final delivered = deliveries.where((d) => d.isDelivered).toList();
    final missed = deliveries.any((d) => d.isMissed);

    final Color? fill;
    final List<String> lines;
    Color textColor = Colors.black87;
    if (onVacation && delivered.isEmpty && !missed) {
      fill = _vacationFill;
      lines = const ['Vacation'];
      textColor = _vacationText;
    } else if (deliveries.isEmpty) {
      fill = null;
      lines = const [];
    } else if (delivered.isNotEmpty) {
      fill = missed ? _missedFill : _deliveredFill;
      lines = [
        billLitres(delivered.fold(0, (s, d) => s + d.quantityMl)),
        billRupees(delivered.fold(0, (s, d) => s + d.amountPaise)),
      ];
      textColor = _green;
    } else if (missed) {
      fill = _missedFill;
      lines = const ['Missed'];
      textColor = _missedText;
    } else if (deliveries.every((d) => d.isPaused)) {
      fill = _pausedFill;
      lines = const ['Paused'];
      textColor = _pausedText;
    } else {
      fill = _pendingFill;
      lines = const ['Pending'];
      textColor = _pendingText;
    }

    return Padding(
      padding: const EdgeInsets.all(2),
      child: Material(
        color: fill ?? Colors.transparent,
        borderRadius: BorderRadius.circular(8),
        child: InkWell(
          borderRadius: BorderRadius.circular(8),
          onTap: deliveries.isEmpty && !onVacation ? null : onTap,
          child: Container(
            height: height,
            padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 3),
            decoration: isToday
                ? BoxDecoration(
                    border: Border.all(color: _green, width: 2),
                    borderRadius: BorderRadius.circular(8),
                  )
                : null,
            child: Column(
              children: [
                Text(
                  '$day',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: isToday ? FontWeight.bold : FontWeight.w500,
                    color: deliveries.isEmpty && !onVacation
                        ? Colors.black45
                        : Colors.black87,
                  ),
                ),
                const Spacer(),
                for (final line in lines)
                  FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Text(
                      line,
                      maxLines: 1,
                      style: TextStyle(
                        fontSize: 11,
                        height: 1.2,
                        color: textColor,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _Legend extends StatelessWidget {
  const _Legend();

  @override
  Widget build(BuildContext context) {
    Widget item(Color color, String text) => Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 12,
          height: 12,
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(3),
          ),
        ),
        const SizedBox(width: 4),
        Text(text, style: const TextStyle(fontSize: 12, color: Colors.black54)),
      ],
    );
    return Wrap(
      alignment: WrapAlignment.center,
      spacing: 14,
      runSpacing: 4,
      children: [
        item(_deliveredFill, 'Delivered'),
        item(_missedFill, 'Missed'),
        item(_pausedFill, 'Paused'),
        item(_vacationFill, 'Vacation'),
        item(_pendingFill, 'Not marked yet'),
      ],
    );
  }
}

/// The month's totals, like the paper bill: litres, rate, amount.
class _MonthTotals extends StatelessWidget {
  const _MonthTotals({required this.data, required this.isThisMonth});

  final MilkDeliveryMonth data;
  final bool isThisMonth;

  @override
  Widget build(BuildContext context) {
    if (data.deliveries.isEmpty) {
      return const Padding(
        padding: EdgeInsets.symmetric(horizontal: 8),
        child: Text(
          'No milk deliveries this month.',
          textAlign: TextAlign.center,
          style: TextStyle(color: Colors.black54),
        ),
      );
    }

    final rates = data.rates.toList()..sort();
    final counts = [
      '${data.deliveredCount} delivered',
      if (data.missedCount > 0) '${data.missedCount} missed',
      if (data.pausedCount > 0) '${data.pausedCount} paused',
      if (data.notMarkedCount > 0) '${data.notMarkedCount} not marked yet',
    ].join(' · ');

    Widget row(String label, String value, {bool bold = false}) => Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        children: [
          Expanded(child: Text(label)),
          Text(
            value,
            style: TextStyle(
              fontWeight: bold ? FontWeight.bold : FontWeight.w600,
              fontSize: bold ? 17 : null,
              color: bold ? _green : null,
            ),
          ),
        ],
      ),
    );

    final billTotal = data.billTotalPaise;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFFF5F8F0),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(counts, style: const TextStyle(color: Colors.black54)),
          const SizedBox(height: 6),
          row('Total litres', billLitres(data.deliveredMl)),
          if (rates.isNotEmpty)
            row('Rate', '${rates.map(billRupees).join(', ')} per litre'),
          row(
            billTotal != null
                ? 'Amount'
                : (isThisMonth ? 'Amount so far' : 'Amount'),
            billRupees(data.amountPaise),
            bold: true,
          ),
          const SizedBox(height: 4),
          Text(
            billTotal != null
                ? 'Your bill for ${billMonthLabel(data.month)} has been '
                      'sent: ${billRupees(billTotal)}.'
                : 'Only delivered milk is charged. Your bill comes after '
                      'the month ends.',
            style: const TextStyle(fontSize: 12, color: Colors.black54),
          ),
        ],
      ),
    );
  }
}

class _DeliveryDetail extends StatelessWidget {
  const _DeliveryDetail(this.delivery);

  final MilkDelivery delivery;

  @override
  Widget build(BuildContext context) {
    final (status, color) = switch (delivery.outcome) {
      'delivered' => ('Delivered', _green),
      'not_delivered' => (missedReasonLabel(delivery.reason), _missedText),
      'paused' => ('Paused', _pausedText),
      _ => ('Not marked yet', _pendingText),
    };
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  billShiftLabel(delivery.shift),
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
              ),
              Text(
                status,
                style: TextStyle(color: color, fontWeight: FontWeight.w600),
              ),
            ],
          ),
          for (final item in delivery.items)
            Text(
              [
                '${item.productName} ${billLitres(item.quantityMl)}',
                if (item.unitPricePaise != null)
                  '× ${billRupees(item.unitPricePaise!)}/L',
                if (delivery.isDelivered) '= ${billRupees(item.amountPaise)}',
              ].join(' '),
            ),
        ],
      ),
    );
  }
}
