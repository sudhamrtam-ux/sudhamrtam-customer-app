import 'package:flutter/material.dart';

import '../../models/milk_quantity.dart';
import '../../services/milk_tomorrow_client.dart';

const _green = Color(0xFF82B440);
const _deepGreen = Color(0xFF3F6B17);

const _shiftNames = {
  'early_morning': 'Early morning',
  'morning': 'Morning',
  'evening': 'Evening',
};

const _weekdays = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
const _months = [
  'Jan',
  'Feb',
  'Mar',
  'Apr',
  'May',
  'Jun',
  'Jul',
  'Aug',
  'Sep',
  'Oct',
  'Nov',
  'Dec',
];

String _dayLabel(String isoDate) {
  final d = DateTime.parse(isoDate);
  return '${_weekdays[d.weekday - 1]}, ${d.day} ${_months[d.month - 1]}';
}

/// "until 9:00 PM today" / "until 6:00 AM tomorrow".
String closesText(DateTime closesAt, DateTime now) {
  final at = closesAt.toLocal();
  final hour = at.hour % 12 == 0 ? 12 : at.hour % 12;
  final time =
      '$hour:${at.minute.toString().padLeft(2, '0')} '
      '${at.hour < 12 ? 'AM' : 'PM'}';
  final today = DateTime(now.year, now.month, now.day);
  final day = DateTime(at.year, at.month, at.day);
  final when = switch (day.difference(today).inDays) {
    0 => 'today',
    1 => 'tomorrow',
    _ => _dayLabel(day.toIso8601String().substring(0, 10)),
  };
  return 'until $time $when';
}

/// Home: tomorrow's milk at a glance, with "Skip tomorrow" and a
/// one-day quantity per shift (owner decision 2026-11-15). Hidden
/// when signed out, without a server, or with no milk tomorrow.
class TomorrowMilkCard extends StatefulWidget {
  const TomorrowMilkCard({
    super.key,
    required this.client,
    this.onChanged,
    this.now = DateTime.now,
  });

  final MilkTomorrowClient? client;

  /// After a skip: refresh the plans kept on the phone.
  final Future<void> Function()? onChanged;
  final DateTime Function() now;

  @override
  State<TomorrowMilkCard> createState() => _TomorrowMilkCardState();
}

class _TomorrowMilkCardState extends State<TomorrowMilkCard> {
  TomorrowMilk? _milk;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final client = widget.client;
    if (client == null || !client.isSignedIn) return;
    try {
      final milk = await client.fetch();
      if (mounted) setState(() => _milk = milk);
    } on MilkTomorrowException {
      // A convenience: the Milk Plan tab still works.
    }
  }

  Future<void> _run(
    Future<TomorrowMilk> Function() action, {
    bool refreshPlans = false,
  }) async {
    setState(() => _busy = true);
    try {
      final milk = await action();
      if (!mounted) return;
      setState(() => _milk = milk);
      if (refreshPlans) await widget.onChanged?.call();
    } on MilkTomorrowException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(e.message)));
      await _load();
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final milk = _milk;
    final client = widget.client;
    if (milk == null || client == null || milk.shifts.isEmpty) {
      return const SizedBox.shrink();
    }
    final plans = <String, List<TomorrowShift>>{};
    for (final s in milk.shifts) {
      plans.putIfAbsent(s.planId, () => []).add(s);
    }

    return Container(
      key: const Key('tomorrowMilk'),
      margin: const EdgeInsets.only(top: 12),
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 8),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFFF7FAF2), Color(0xFFEAF4DC)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFFDDE8CC)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.local_drink_outlined, color: _deepGreen),
              const SizedBox(width: 8),
              const Text(
                "Tomorrow's milk",
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
              ),
              const Spacer(),
              Text(
                _dayLabel(milk.date),
                style: const TextStyle(
                  color: _deepGreen,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
          for (final entry in plans.entries)
            _plan(client, milk.date, entry.key, entry.value),
        ],
      ),
    );
  }

  Widget _plan(
    MilkTomorrowClient client,
    String date,
    String planId,
    List<TomorrowShift> shifts,
  ) {
    final skipped = shifts.first.skipped;
    final canSkip = shifts.any((s) => s.open) && !_busy;
    return Padding(
      padding: const EdgeInsets.only(top: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  shifts.first.productName,
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
              ),
              TextButton.icon(
                key: Key('tomorrowSkip-$planId'),
                style: TextButton.styleFrom(
                  foregroundColor: skipped ? _deepGreen : Colors.black87,
                  visualDensity: VisualDensity.compact,
                ),
                onPressed: canSkip
                    ? () => _run(
                        () => client.skip(planId, date: date, skip: !skipped),
                        refreshPlans: true,
                      )
                    : null,
                icon: Icon(
                  skipped ? Icons.undo : Icons.event_busy_outlined,
                  size: 18,
                ),
                label: Text(skipped ? 'Undo skip' : 'Skip tomorrow'),
              ),
            ],
          ),
          if (skipped)
            const Padding(
              padding: EdgeInsets.only(bottom: 6),
              child: Text(
                'No milk tomorrow on this plan.',
                style: TextStyle(color: Colors.black54),
              ),
            )
          else
            for (final s in shifts) _shiftRow(client, date, s),
        ],
      ),
    );
  }

  Widget _shiftRow(MilkTomorrowClient client, String date, TomorrowShift s) {
    final less = previousMilkMl(s.quantityMl);
    final more = nextMilkMl(s.quantityMl);
    final canChange = s.open && !_busy;
    void set(int? ml) => _run(
      () => client.setQuantity(
        s.planId,
        date: date,
        shift: s.shift,
        quantityMl: ml,
      ),
    );

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(_shiftNames[s.shift] ?? s.shift),
                Text(
                  !s.open
                      ? 'Changes closed'
                      : s.changed
                      ? 'Usually ${milkLitresText(s.usualMl)} · '
                            '${closesText(s.closesAt, widget.now())}'
                      : 'Change ${closesText(s.closesAt, widget.now())}',
                  style: const TextStyle(color: Colors.black54, fontSize: 12),
                ),
                if (s.changed && s.open)
                  GestureDetector(
                    key: Key('tomorrowUsual-${s.planId}-${s.shift}'),
                    onTap: canChange ? () => set(null) : null,
                    child: const Text(
                      'Back to usual',
                      style: TextStyle(
                        color: _deepGreen,
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        decoration: TextDecoration.underline,
                      ),
                    ),
                  ),
              ],
            ),
          ),
          _StepButton(
            key: Key('tomorrowLess-${s.planId}-${s.shift}'),
            icon: Icons.remove,
            onTap: canChange && less != null ? () => set(less) : null,
          ),
          SizedBox(
            width: 64,
            child: Text(
              milkLitresText(s.quantityMl),
              key: Key('tomorrowQty-${s.planId}-${s.shift}'),
              textAlign: TextAlign.center,
              style: TextStyle(
                fontWeight: FontWeight.bold,
                color: s.changed ? _deepGreen : Colors.black87,
              ),
            ),
          ),
          _StepButton(
            key: Key('tomorrowMore-${s.planId}-${s.shift}'),
            icon: Icons.add,
            onTap: canChange && more != null ? () => set(more) : null,
          ),
        ],
      ),
    );
  }
}

class _StepButton extends StatelessWidget {
  const _StepButton({super.key, required this.icon, this.onTap});

  final IconData icon;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) => Material(
    color: onTap == null ? const Color(0xFFEDEDED) : _green,
    shape: const CircleBorder(),
    child: InkWell(
      customBorder: const CircleBorder(),
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.all(6),
        child: Icon(
          icon,
          size: 18,
          color: onTap == null ? Colors.black26 : Colors.white,
        ),
      ),
    ),
  );
}
