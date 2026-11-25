import 'package:flutter/material.dart';

import '../../app/sudhamrtam_app.dart';
import '../../models/milk_subscription.dart';
import '../../models/milk_subscription_manager.dart';

/// The customer's milk account at a glance (owner decision
/// 2026-11-10), so a paused customer sees it on Home.
enum AccountState { active, waiting, vacation, paused, inactive }

class AccountStatus {
  const AccountStatus(this.state, this.label, this.detail);

  final AccountState state;

  /// "Active", "Waiting for approval", "On vacation", "Paused",
  /// "Inactive".
  final String label;
  final String detail;

  Color get color => switch (state) {
    AccountState.active => const Color(0xFF2E7D32),
    AccountState.waiting => const Color(0xFF6A1B9A),
    AccountState.vacation => const Color(0xFF1565C0),
    AccountState.paused => const Color(0xFFEF6C00),
    AccountState.inactive => const Color(0xFF757575),
  };

  IconData get icon => switch (state) {
    AccountState.active => Icons.check_circle,
    AccountState.waiting => Icons.hourglass_top,
    AccountState.vacation => Icons.luggage,
    AccountState.paused => Icons.pause_circle,
    AccountState.inactive => Icons.do_not_disturb_on_outlined,
  };
}

String _milk(String productId) =>
    productId == 'buffalo_milk' ? 'Buffalo Milk' : 'Cow Milk';

String _date(DateTime d) {
  const months = [
    'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', //
    'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
  ];
  return '${d.day} ${months[d.month - 1]}';
}

/// The status from the customer's plans on [today].
///
/// - Active: some milk is coming (a plan back from vacation counts).
/// - Waiting for approval: only new plans Sudhamrtam has not approved.
/// - On vacation: every open plan is paused with a return date, or
///   has today as a vacation day.
/// - Paused: open plans, none delivering.
/// - Inactive: no open plan.
AccountStatus accountStatusFor(List<MilkSubscription> plans, DateTime today) {
  final open = [
    for (final p in plans)
      if (p.status != MilkSubscriptionStatus.cancelled) p,
  ];
  if (open.isEmpty) {
    return const AccountStatus(
      AccountState.inactive,
      'Inactive',
      'No subscription yet. Start one for fresh milk at your door.',
    );
  }
  final waiting = [
    for (final p in open)
      if (p.isWaitingForApproval) p,
  ];
  final decided = [
    for (final p in open)
      if (!p.isWaitingForApproval) p,
  ];
  if (decided.isEmpty) {
    return const AccountStatus(
      AccountState.waiting,
      'Waiting for approval',
      'Sudhamrtam will check your new subscription. Milk starts once it '
          'is approved.',
    );
  }
  // Active plans with today as a vacation day.
  final awayToday = [
    for (final p in decided)
      if (p.status == MilkSubscriptionStatus.active && p.isVacationDay(today))
        p,
  ];
  final delivering = [
    for (final p in decided)
      if ((p.status == MilkSubscriptionStatus.active &&
              !awayToday.contains(p)) ||
          (p.status == MilkSubscriptionStatus.paused &&
              p.resumeOn != null &&
              !p.isOnVacation(today)))
        p,
  ];
  final away = [
    for (final p in decided)
      if (p.isOnVacation(today) || awayToday.contains(p)) p,
  ];
  // The first day milk comes again after a vacation.
  DateTime backOn(MilkSubscription p) {
    if (p.resumeOn != null && p.status == MilkSubscriptionStatus.paused) {
      return p.resumeOn!;
    }
    var day = DateTime(today.year, today.month, today.day + 1);
    while (p.isVacationDay(day)) {
      day = DateTime(day.year, day.month, day.day + 1);
    }
    return day;
  }

  final stopped = [
    for (final p in decided)
      if (!delivering.contains(p) && !away.contains(p)) p,
  ];

  if (delivering.isNotEmpty) {
    final names = {for (final p in delivering) _milk(p.productId)};
    final notes = [
      for (final p in away)
        '${_milk(p.productId)} on vacation until ${_date(backOn(p).subtract(const Duration(days: 1)))}',
      for (final p in stopped) '${_milk(p.productId)} paused',
      for (final p in waiting) '${_milk(p.productId)} waiting for approval',
    ];
    return AccountStatus(
      AccountState.active,
      'Active',
      ['${names.join(' and ')} on the way', ...notes].join(' · '),
    );
  }
  if (stopped.isEmpty) {
    final back = away.map(backOn).reduce((a, b) => a.isBefore(b) ? a : b);
    return AccountStatus(
      AccountState.vacation,
      'On vacation',
      'Milk restarts on ${_date(back)}. Enjoy your trip!',
    );
  }
  return const AccountStatus(
    AccountState.paused,
    'Paused',
    'No milk is coming. Tap to resume in Subscriptions.',
  );
}

/// The status card on Home; tap to open the Milk Plan tab.
class AccountStatusCard extends StatelessWidget {
  const AccountStatusCard({
    super.key,
    this.plans,
    this.onOpen,
    this.today = DateTime.now,
    this.compact = false,
  });

  /// A small badge for a corner of Home (owner, 2026-11-17): "Milk
  /// plan" over the status, details in the Milk Plan tab it opens.
  final bool compact;

  /// Defaults to the app's milk plans.
  final MilkSubscriptionManager? plans;
  final VoidCallback? onOpen;
  final DateTime Function() today;

  @override
  Widget build(BuildContext context) {
    final manager = plans ?? sudhamrtamMilkSubscriptions;
    return ListenableBuilder(
      listenable: manager,
      builder: (context, _) {
        final status = accountStatusFor(manager.subscriptions, today());
        if (compact) {
          return Tooltip(
            message: status.detail,
            child: Material(
              key: const Key('accountStatus'),
              color: status.color.withValues(alpha: 0.10),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
                side: BorderSide(color: status.color.withValues(alpha: 0.45)),
              ),
              child: InkWell(
                borderRadius: BorderRadius.circular(14),
                onTap: onOpen,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(10, 6, 10, 7),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        'Subscription',
                        style: TextStyle(
                          fontSize: 11,
                          color: status.color,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(status.icon, color: status.color, size: 16),
                          const SizedBox(width: 4),
                          Text(
                            status.label,
                            key: const Key('accountStatusLabel'),
                            style: TextStyle(
                              fontSize: 13,
                              color: status.color,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ),
          );
        }
        // A small button with text (owner, 2026-11-17); the details
        // are in the Milk Plan tab it opens.
        return Align(
          alignment: Alignment.centerLeft,
          child: Tooltip(
            message: status.detail,
            child: Material(
              key: const Key('accountStatus'),
              color: status.color.withValues(alpha: 0.10),
              shape: StadiumBorder(
                side: BorderSide(color: status.color.withValues(alpha: 0.45)),
              ),
              child: InkWell(
                customBorder: const StadiumBorder(),
                onTap: onOpen,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(10, 6, 8, 6),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(status.icon, color: status.color, size: 18),
                      const SizedBox(width: 6),
                      Text(
                        'Subscription: ',
                        style: TextStyle(
                          color: status.color,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      Text(
                        status.label,
                        key: const Key('accountStatusLabel'),
                        style: TextStyle(
                          color: status.color,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      if (onOpen != null)
                        Icon(
                          Icons.chevron_right,
                          color: status.color,
                          size: 18,
                        ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}
