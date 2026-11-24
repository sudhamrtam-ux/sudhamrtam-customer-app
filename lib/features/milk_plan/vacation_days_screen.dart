import 'package:flutter/material.dart';

import '../../core/widgets/site_layout.dart';
import '../../core/widgets/page_app_bar.dart';

const _brandGreen = Color(0xFF82B440);

const _months = [
  'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', //
  'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
];

const _fullMonths = [
  'January', 'February', 'March', 'April', 'May', 'June', //
  'July', 'August', 'September', 'October', 'November', 'December',
];

DateTime _dateOnly(DateTime d) => DateTime(d.year, d.month, d.day);

DateTime _nextDay(DateTime d) => DateTime(d.year, d.month, d.day + 1);

/// "15 Nov, 18 Nov, 22–24 Nov, 30 Nov – 2 Dec": vacation days with
/// days in a row shown as a range.
String vacationDaysText(List<DateTime> days) {
  final sorted = {for (final d in days) _dateOnly(d)}.toList()..sort();
  final parts = <String>[];
  var i = 0;
  while (i < sorted.length) {
    var j = i;
    while (j + 1 < sorted.length && sorted[j + 1] == _nextDay(sorted[j])) {
      j++;
    }
    final a = sorted[i];
    final b = sorted[j];
    String text(DateTime d) => '${d.day} ${_months[d.month - 1]}';
    parts.add(
      i == j
          ? text(a)
          : a.month == b.month
          ? '${a.day}–${text(b)}'
          : '${text(a)} – ${text(b)}',
    );
    i = j + 1;
  }
  return parts.join(', ');
}

/// Picks a date range; tests replace it.
typedef VacationRangePicker = Future<DateTimeRange?> Function(
  BuildContext context,
  DateTime first,
  DateTime last,
);

Future<DateTimeRange?> _showRangePicker(
  BuildContext context,
  DateTime first,
  DateTime last,
) => showDateRangePicker(
  context: context,
  firstDate: first,
  lastDate: last,
  helpText: 'Away from – to',
  saveText: 'Add these days',
);

/// Vacation days for one milk plan (owner decision 2026-11-11): the
/// customer taps each day they are away, or adds a range, in any
/// mix: one day, several separate days or a long trip. Pops the
/// chosen days (sorted), or null when closed without saving.
class VacationDaysScreen extends StatefulWidget {
  const VacationDaysScreen({
    super.key,
    required this.milkName,
    this.initial = const [],
    this.today,
    this.pickRange = _showRangePicker,
  });

  final String milkName;
  final List<DateTime> initial;

  /// Tests set the day; null means now.
  final DateTime? today;
  final VacationRangePicker pickRange;

  /// Days can be chosen up to this far ahead (as the server allows).
  static const maxDaysAhead = 180;

  @override
  State<VacationDaysScreen> createState() => _VacationDaysScreenState();
}

class _VacationDaysScreenState extends State<VacationDaysScreen> {
  late final DateTime _today = _dateOnly(widget.today ?? DateTime.now());
  late final DateTime _first = _nextDay(_today);
  late final DateTime _last = DateTime(
    _today.year,
    _today.month,
    _today.day + VacationDaysScreen.maxDaysAhead,
  );
  late final Set<DateTime> _days = {
    for (final d in widget.initial)
      if (!_dateOnly(d).isBefore(_first)) _dateOnly(d),
  };
  late DateTime _month = () {
    final start = _days.isEmpty ? _first : (_days.toList()..sort()).first;
    return DateTime(start.year, start.month);
  }();

  bool _canPick(DateTime day) => !day.isBefore(_first) && !day.isAfter(_last);

  void _toggle(DateTime day) {
    setState(() {
      if (!_days.remove(day)) _days.add(day);
    });
  }

  Future<void> _addRange() async {
    final range = await widget.pickRange(context, _first, _last);
    if (range == null || !mounted) return;
    setState(() {
      for (
        var d = _dateOnly(range.start);
        !d.isAfter(range.end);
        d = _nextDay(d)
      ) {
        if (_canPick(d)) _days.add(d);
      }
      _month = DateTime(range.start.year, range.start.month);
    });
  }

  String _key(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, '0')}-'
      '${d.day.toString().padLeft(2, '0')}';

  Widget _calendar() {
    final firstMonth = DateTime(_first.year, _first.month);
    final lastMonth = DateTime(_last.year, _last.month);
    final daysInMonth = DateTime(_month.year, _month.month + 1, 0).day;
    // Monday first.
    final blanks = DateTime(_month.year, _month.month).weekday - 1;

    return Column(
      children: [
        Row(
          children: [
            IconButton(
              key: const Key('vacationPrevMonth'),
              tooltip: 'Previous month',
              onPressed: _month.isAfter(firstMonth)
                  ? () => setState(
                      () => _month = DateTime(_month.year, _month.month - 1),
                    )
                  : null,
              icon: const Icon(Icons.chevron_left),
            ),
            Expanded(
              child: Text(
                '${_fullMonths[_month.month - 1]} ${_month.year}',
                key: const Key('vacationMonth'),
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
            IconButton(
              key: const Key('vacationNextMonth'),
              tooltip: 'Next month',
              onPressed: _month.isBefore(lastMonth)
                  ? () => setState(
                      () => _month = DateTime(_month.year, _month.month + 1),
                    )
                  : null,
              icon: const Icon(Icons.chevron_right),
            ),
          ],
        ),
        Row(
          children: [
            for (final name in ['M', 'T', 'W', 'T', 'F', 'S', 'S'])
              Expanded(
                child: Center(
                  child: Text(
                    name,
                    style: const TextStyle(
                      color: Colors.black54,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ),
          ],
        ),
        const SizedBox(height: 4),
        GridView.count(
          crossAxisCount: 7,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          children: [
            for (var i = 0; i < blanks; i++) const SizedBox.shrink(),
            for (var n = 1; n <= daysInMonth; n++)
              _dayCell(DateTime(_month.year, _month.month, n)),
          ],
        ),
      ],
    );
  }

  Widget _dayCell(DateTime day) {
    final enabled = _canPick(day);
    final chosen = _days.contains(day);
    return Padding(
      padding: const EdgeInsets.all(3),
      child: Material(
        color: chosen ? _brandGreen : Colors.transparent,
        shape: CircleBorder(
          side: day == _today
              ? const BorderSide(color: _brandGreen)
              : BorderSide.none,
        ),
        child: InkWell(
          key: Key('vacationDay-${_key(day)}'),
          customBorder: const CircleBorder(),
          onTap: enabled ? () => _toggle(day) : null,
          child: Center(
            child: Text(
              '${day.day}',
              style: TextStyle(
                color: chosen
                    ? Colors.white
                    : enabled
                    ? Colors.black87
                    : Colors.black26,
                fontWeight: chosen ? FontWeight.bold : FontWeight.normal,
              ),
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final sorted = _days.toList()..sort();
    return SiteScaffold(
      appBar: PageAppBar(title: Text('Vacation · ${widget.milkName}')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const Text(
            'Tap each day you are away: one day, several days, or use '
            '"Add a date range" for a longer trip. No milk comes on '
            'these days and you pay nothing for them. Milk comes as '
            'usual on the other days.',
          ),
          const SizedBox(height: 6),
          const Text(
            'Choose from tomorrow. Early morning milk for a day stops '
            'only if you save by 9 PM the evening before.',
            style: TextStyle(fontSize: 12, color: Colors.black54),
          ),
          const SizedBox(height: 12),
          _calendar(),
          const SizedBox(height: 8),
          OutlinedButton.icon(
            key: const Key('vacationRange'),
            onPressed: _addRange,
            icon: const Icon(Icons.date_range),
            label: const Text('Add a date range'),
            style: OutlinedButton.styleFrom(foregroundColor: _brandGreen),
          ),
          const SizedBox(height: 16),
          Container(
            key: const Key('vacationSummary'),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: const Color(0xFFE3F2FD),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Text(
              sorted.isEmpty
                  ? 'No vacation days chosen.'
                  : 'No milk on ${sorted.length} '
                        '${sorted.length == 1 ? 'day' : 'days'}: '
                        '${vacationDaysText(sorted)}',
              style: const TextStyle(color: Color(0xFF1565C0)),
            ),
          ),
          if (sorted.isNotEmpty)
            Align(
              alignment: Alignment.centerRight,
              child: TextButton(
                key: const Key('vacationClear'),
                onPressed: () => setState(_days.clear),
                child: const Text('Clear all'),
              ),
            ),
        ],
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
          child: FilledButton(
            key: const Key('vacationSave'),
            style: FilledButton.styleFrom(
              backgroundColor: _brandGreen,
              padding: const EdgeInsets.symmetric(vertical: 14),
            ),
            onPressed: () => Navigator.of(context).pop(sorted),
            child: const Text('Save vacation days'),
          ),
        ),
      ),
    );
  }
}
