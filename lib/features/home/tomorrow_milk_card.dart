import 'package:flutter/material.dart';

import '../../app/sudhamrtam_app.dart';
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
    this.compact = false,
  });

  final MilkTomorrowClient? client;

  /// Home (owner request 2026-11-25): one line with what comes
  /// tomorrow and a Change button that opens the full card.
  final bool compact;

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
    if (widget.compact) return _strip(milk, plans);

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

  /// The steps for [s]: the product's pack sizes, or milk in 250 ml.
  ({int? less, int? more, String Function(int) amount}) _steps(
    TomorrowShift s,
  ) {
    final offer = sudhamrtamSubscriptionProducts.offerFor(s.productId);
    final packs = offer != null && offer.isPack
        ? ({...offer.quantities, s.usualMl}.toList()..sort())
        : null;
    return (
      less: packs == null
          ? previousMilkMl(s.quantityMl)
          : packs.where((q) => q < s.quantityMl).lastOrNull,
      more: packs == null
          ? nextMilkMl(s.quantityMl)
          : packs.where((q) => q > s.quantityMl).firstOrNull,
      amount: (q) => packs == null ? milkLitresText(q) : offer!.quantityText(q),
    );
  }

  /// Home (owner request 2026-11-26): tomorrow's deliveries, one line
  /// per delivery time with − and + for tomorrow only; More opens skip.
  Widget _strip(TomorrowMilk milk, Map<String, List<TomorrowShift>> plans) {
    const order = {'early_morning': 0, 'morning': 1, 'evening': 2};
    final shifts = [...milk.shifts]
      ..sort((a, b) => (order[a.shift] ?? 3).compareTo(order[b.shift] ?? 3));
    return Container(
      key: const Key('tomorrowStrip'),
      padding: const EdgeInsets.fromLTRB(14, 8, 8, 8),
      decoration: BoxDecoration(
        color: const Color(0xFFF5F9EE),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0xFFE1EBD3)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(
                Icons.local_drink_outlined,
                size: 18,
                color: _deepGreen,
              ),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  'Tomorrow · ${_dayLabel(milk.date)}',
                  style: const TextStyle(
                    color: _deepGreen,
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              TextButton(
                key: const Key('tomorrowChange'),
                onPressed: _openFull,
                style: TextButton.styleFrom(
                  foregroundColor: _deepGreen,
                  visualDensity: VisualDensity.compact,
                ),
                child: const Text(
                  'Skip / more',
                  style: TextStyle(fontSize: 13),
                ),
              ),
            ],
          ),
          for (final s in shifts) _line(milk.date, s),
        ],
      ),
    );
  }

  /// "Morning   Buffalo Milk   − 1.00 L +".
  Widget _line(String date, TomorrowShift s) {
    final client = widget.client!;
    final steps = _steps(s);
    final canChange = s.open && !_busy && !s.skipped;
    void set(int ml) => _run(
      () => client.setQuantity(
        s.planId,
        date: date,
        shift: s.shift,
        quantityMl: ml,
      ),
    );
    return Padding(
      key: Key('tomorrowLine-${s.planId}-${s.shift}'),
      padding: const EdgeInsets.only(top: 2),
      child: Row(
        children: [
          SizedBox(
            width: 92,
            child: Text(
              _shiftNames[s.shift] ?? s.shift,
              style: const TextStyle(color: Colors.black54, fontSize: 13),
            ),
          ),
          Expanded(
            child: Text(
              s.skipped ? '${s.productName} · skipped' : s.productName,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w500,
                color: s.skipped ? Colors.black45 : const Color(0xFF2B3A1E),
              ),
            ),
          ),
          if (!s.skipped) ...[
            _SoftStep(
              key: Key('tomorrowLess-${s.planId}-${s.shift}'),
              icon: Icons.remove,
              tooltip: 'Less tomorrow',
              onTap: canChange && steps.less != null
                  ? () => set(steps.less!)
                  : null,
            ),
            SizedBox(
              width: 64,
              child: Text(
                steps.amount(s.quantityMl),
                key: Key('tomorrowQty-${s.planId}-${s.shift}'),
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: s.changed ? _deepGreen : const Color(0xFF2B3A1E),
                ),
              ),
            ),
            _SoftStep(
              key: Key('tomorrowMoreLine-${s.planId}-${s.shift}'),
              icon: Icons.add,
              tooltip: 'More tomorrow',
              onTap: canChange && steps.more != null
                  ? () => set(steps.more!)
                  : null,
            ),
          ],
        ],
      ),
    );
  }

  /// The full card (skip, one-day quantity) in a sheet; the strip
  /// shows any change after.
  Future<void> _openFull() async {
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (context) => SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          child: TomorrowMilkCard(
            client: widget.client,
            now: widget.now,
            onChanged: widget.onChanged,
          ),
        ),
      ),
    );
    await _load();
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
                'No milk tomorrow on this subscription.',
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
    // Packs (owner request 2026-11-25): the product's quantities.
    final offer = sudhamrtamSubscriptionProducts.offerFor(s.productId);
    final packs = offer != null && offer.isPack
        ? ({...offer.quantities, s.usualMl}.toList()..sort())
        : null;
    final less = packs == null
        ? previousMilkMl(s.quantityMl)
        : packs.where((q) => q < s.quantityMl).lastOrNull;
    final more = packs == null
        ? nextMilkMl(s.quantityMl)
        : packs.where((q) => q > s.quantityMl).firstOrNull;
    String amount(int q) =>
        packs == null ? milkLitresText(q) : offer!.quantityText(q);
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
                      ? 'Usually ${amount(s.usualMl)} · '
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
              amount(s.quantityMl),
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

/// A small round − or + with a soft outline (Home's Tomorrow lines).
class _SoftStep extends StatelessWidget {
  const _SoftStep({
    super.key,
    required this.icon,
    required this.tooltip,
    this.onTap,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) => Tooltip(
    message: tooltip,
    child: Material(
      color: Colors.white,
      shape: CircleBorder(
        side: BorderSide(
          color: onTap == null ? const Color(0xFFE0E0E0) : _green,
          width: 1.4,
        ),
      ),
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(4),
          child: Icon(
            icon,
            size: 16,
            color: onTap == null ? Colors.black26 : _deepGreen,
          ),
        ),
      ),
    ),
  );
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
