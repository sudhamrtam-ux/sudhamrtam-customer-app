import 'package:flutter/material.dart';

/// How far back a list goes (owner request 2026-11-26): orders,
/// messages, help queries and milk bills.
enum Period {
  all('All time'),
  days7('Last 7 days'),
  days15('Last 15 days'),
  days30('Last 30 days'),
  months3('Last 3 months'),
  months6('Last 6 months');

  const Period(this.label);

  final String label;

  /// The first day shown, from [now]; null for all time. "Last 7 days"
  /// is today and the 6 days before it.
  DateTime? since(DateTime now) {
    final today = DateTime(now.year, now.month, now.day);
    return switch (this) {
      Period.all => null,
      Period.days7 => DateTime(today.year, today.month, today.day - 6),
      Period.days15 => DateTime(today.year, today.month, today.day - 14),
      Period.days30 => DateTime(today.year, today.month, today.day - 29),
      Period.months3 => DateTime(today.year, today.month - 3, today.day),
      Period.months6 => DateTime(today.year, today.month - 6, today.day),
    };
  }

  /// Whether something from [at] is in this period.
  bool includes(DateTime at, DateTime now) {
    final from = since(now);
    return from == null || !at.toLocal().isBefore(from);
  }
}

/// A small "Last 30 days ▾" button that opens the choice of periods.
class PeriodFilter extends StatelessWidget {
  const PeriodFilter({
    super.key,
    required this.value,
    required this.onChanged,
    this.options = Period.values,
  });

  final Period value;
  final ValueChanged<Period> onChanged;
  final List<Period> options;

  static const _green = Color(0xFF4F7A1F);

  @override
  Widget build(BuildContext context) {
    final on = value != Period.all;
    return PopupMenuButton<Period>(
      key: const Key('period-filter'),
      tooltip: 'Show a period',
      initialValue: value,
      onSelected: onChanged,
      itemBuilder: (context) => [
        for (final p in options)
          PopupMenuItem(
            key: Key('period-${p.name}'),
            value: p,
            child: Text(p.label),
          ),
      ],
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
        decoration: BoxDecoration(
          color: on ? const Color(0xFFE5F0D7) : Colors.white,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: on ? _green : Colors.black26),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.date_range, size: 18, color: _green),
            const SizedBox(width: 6),
            Text(
              value.label,
              key: const Key('period-label'),
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
            const Icon(Icons.arrow_drop_down),
          ],
        ),
      ),
    );
  }
}
