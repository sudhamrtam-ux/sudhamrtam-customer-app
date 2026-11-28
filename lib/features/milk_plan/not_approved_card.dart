import 'package:flutter/material.dart';

import '../../app/sudhamrtam_app.dart';
import '../../database/milk_database_service.dart';
import '../../models/milk_subscription.dart';
import '../../models/milk_subscription_manager.dart';
import '../support/help_support_screen.dart';
import 'milk_plan_merge_dialog.dart';
import 'milk_plan_screen.dart';

/// How long a "Not approved" answer is shown, from the day it came.
const notApprovedShownDays = 30;

/// The app setting that remembers "OK" for one plan.
String notApprovedSeenKey(String planId) => 'plan_not_approved_seen_$planId';

Future<bool> _isSeen(String planId) async {
  final db = await MilkDatabaseService.instance.database;
  final rows = await db.query(
    MilkDatabaseService.appSettingsTable,
    where: 'key = ?',
    whereArgs: [notApprovedSeenKey(planId)],
    limit: 1,
  );
  return rows.isNotEmpty;
}

Future<void> _markSeen(String planId) async {
  final db = await MilkDatabaseService.instance.database;
  await db.rawInsert(
    'INSERT OR REPLACE INTO ${MilkDatabaseService.appSettingsTable} '
    '(key, value) VALUES (?, ?)',
    [notApprovedSeenKey(planId), DateTime.now().toIso8601String()],
  );
}

/// On Home and Subscriptions (owner decision 2026-11-28): a new
/// subscription Sudhamrtam did not approve, with the reason, so the
/// customer is not left waiting for milk that will not come. It stays
/// for [notApprovedShownDays] days or until they tap OK.
class NotApprovedCard extends StatefulWidget {
  const NotApprovedCard({
    super.key,
    this.manager,
    this.isSeen = _isSeen,
    this.markSeen = _markSeen,
    this.openSetup = openMilkPlanSetup,
    this.openSupport,
    this.clock = DateTime.now,
  });

  /// Defaults to the app's plans.
  final MilkSubscriptionManager? manager;
  final Future<bool> Function(String planId) isSeen;
  final Future<void> Function(String planId) markSeen;

  /// "Change and ask again": the setup for that milk.
  final Future<void> Function(BuildContext, String productId) openSetup;

  /// "Contact us"; defaults to Help & Support.
  final void Function(BuildContext)? openSupport;
  final DateTime Function() clock;

  @override
  State<NotApprovedCard> createState() => _NotApprovedCardState();
}

class _NotApprovedCardState extends State<NotApprovedCard> {
  late final MilkSubscriptionManager _manager =
      widget.manager ?? sudhamrtamMilkSubscriptions;
  List<MilkSubscription> _shown = const [];

  @override
  void initState() {
    super.initState();
    _manager.addListener(_check);
    _check();
  }

  @override
  void dispose() {
    _manager.removeListener(_check);
    super.dispose();
  }

  Future<void> _check() async {
    final from = widget.clock().subtract(
      const Duration(days: notApprovedShownDays),
    );
    final recent = [
      for (final p in _manager.subscriptions)
        if (p.isRejected && (p.cancelledAt?.isAfter(from) ?? false)) p,
    ];
    // Nothing to show: the phone's database is not even opened.
    if (recent.isEmpty) {
      if (mounted && _shown.isNotEmpty) setState(() => _shown = const []);
      return;
    }
    final shown = <MilkSubscription>[];
    for (final p in recent) {
      try {
        if (!await widget.isSeen(p.id)) shown.add(p);
      } catch (_) {
        // Only a notice: never get in the way of the page.
      }
    }
    if (mounted) setState(() => _shown = shown);
  }

  Future<void> _ok(MilkSubscription plan) async {
    setState(() => _shown = [..._shown]..remove(plan));
    try {
      await widget.markSeen(plan.id);
    } catch (_) {}
  }

  void _support() {
    final open = widget.openSupport;
    if (open != null) {
      open(context);
      return;
    }
    Navigator.of(
      context,
    ).push(MaterialPageRoute<void>(builder: (_) => const HelpSupportScreen()));
  }

  @override
  Widget build(BuildContext context) {
    if (_shown.isEmpty) return const SizedBox.shrink();
    return Column(children: [for (final plan in _shown) _card(context, plan)]);
  }

  Widget _card(BuildContext context, MilkSubscription plan) {
    const brandGreen = Color(0xFF82B440);
    final what = [
      for (final s in plan.shiftSchedules)
        '${shiftText(s.shift)} ${quantityTextFor(plan.productId, s.quantityMl)} '
            '${deliveryDaysText(s)}',
    ].join(', ');
    final reason = plan.rejectReason?.trim();
    return Card(
      key: Key('notApproved_${plan.id}'),
      margin: const EdgeInsets.only(bottom: 16),
      color: const Color(0xFFFFF3F0),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: const BorderSide(color: Color(0xFFFFAB91)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.info_outline, color: Color(0xFFD84315)),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    '${milkName(plan.productId)}: subscription not approved',
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 16,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            if (what.isNotEmpty) Text(what),
            if (plan.cancelledAt != null)
              Text(
                'Answered on ${planDateText(plan.cancelledAt!)}',
                style: const TextStyle(color: Colors.black54),
              ),
            const SizedBox(height: 6),
            Text(
              reason == null || reason.isEmpty
                  ? 'No milk will come for this request.'
                  : 'Reason: $reason',
              key: Key('notApprovedReason_${plan.id}'),
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 4,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                FilledButton(
                  key: Key('notApprovedRetry_${plan.id}'),
                  style: FilledButton.styleFrom(backgroundColor: brandGreen),
                  onPressed: () => widget.openSetup(context, plan.productId),
                  child: const Text('Change and ask again'),
                ),
                OutlinedButton(
                  key: Key('notApprovedContact_${plan.id}'),
                  onPressed: _support,
                  child: const Text('Contact us'),
                ),
                TextButton(
                  key: Key('notApprovedOk_${plan.id}'),
                  onPressed: () => _ok(plan),
                  child: const Text('OK'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
