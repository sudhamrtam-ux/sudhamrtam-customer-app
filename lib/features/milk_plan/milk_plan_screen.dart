import 'package:flutter/material.dart';

import '../../app/sudhamrtam_app.dart';
import '../../services/milk_plan_api_client.dart';
import '../account/phone_login_screen.dart';
import '../milk_bills/milk_bills_screen.dart';
import '../../models/milk_subscription.dart';
import '../../models/milk_subscription_manager.dart';
import '../../models/milk_plan_merge.dart';
import 'milk_plan_merge_dialog.dart';
import 'milk_subscription_setup_screen.dart';

// ============================================================
// MILK PLAN SCREEN
// ============================================================

class MilkPlanScreen extends StatelessWidget {
  const MilkPlanScreen({super.key});

  @override
  Widget build(BuildContext context) {
    const brandGreen = Color(0xFF82B440);

    return Scaffold(
      appBar: AppBar(title: const Text('Milk Plan')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            const MilkBillsReminder(),

            // Main heading
            Text(
              'Fresh Milk, Early Morning to Evening',
              style: Theme.of(context).textTheme.headlineSmall
                  ?.copyWith(fontWeight: FontWeight.bold),
            ),

            const SizedBox(height: 8),

            const Text(
              'Choose a convenient milk delivery plan '
              'for your family.',
              style: TextStyle(fontSize: 15, color: Colors.black54),
            ),

            const SizedBox(height: 24),

            // =================================================
            // BUFFALO MILK
            // =================================================
            _MilkProductCard(
              name: 'Buffalo Milk',
              description: 'Rich, creamy farm-fresh buffalo milk.',
              icon: Icons.water_drop,
              onTap: () => openMilkPlanSetup(context, 'Buffalo Milk'),
            ),

            const SizedBox(height: 16),

            // =================================================
            // COW MILK
            // =================================================
            _MilkProductCard(
              name: 'Cow Milk',
              description: 'Fresh, wholesome cow milk.',
              icon: Icons.water_drop_outlined,
              onTap: () => openMilkPlanSetup(context, 'Cow Milk'),
            ),

            const SizedBox(height: 32),

            // =================================================
            // SAVED SUBSCRIPTIONS
            // =================================================
            Text(
              'My Milk Subscriptions',
              style: Theme.of(context).textTheme.titleLarge
                  ?.copyWith(fontWeight: FontWeight.bold),
            ),

            const SizedBox(height: 8),

            const Text(
              'View and manage your saved milk delivery plans.',
              style: TextStyle(color: Colors.black54),
            ),

            const SizedBox(height: 16),

            ListenableBuilder(
              listenable: sudhamrtamMilkSync,
              builder: (context, _) {
                final message = sudhamrtamMilkSync.message;
                if (message == null) return const SizedBox.shrink();
                return Container(
                  key: const Key('milkSyncMessage'),
                  margin: const EdgeInsets.only(bottom: 12),
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: const Color(0xFFFFF8E1),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(message),
                      TextButton(
                        onPressed: sudhamrtamMilkSync.syncNow,
                        child: const Text('Try again'),
                      ),
                    ],
                  ),
                );
              },
            ),

            ListenableBuilder(
              listenable: sudhamrtamMilkSubscriptions,
              builder: (context, child) {
                final subscriptions = sudhamrtamMilkSubscriptions.subscriptions;

                if (subscriptions.isEmpty) {
                  return Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(24),
                    decoration: BoxDecoration(
                      color: const Color(0xFFF5F8F0),
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: const Column(
                      children: [
                        Icon(
                          Icons.event_note_outlined,
                          size: 42,
                          color: brandGreen,
                        ),
                        SizedBox(height: 12),
                        Text(
                          'No Milk Subscriptions Yet',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        SizedBox(height: 8),
                        Text(
                          'Choose Buffalo Milk or Cow Milk '
                          'above to create your first plan.',
                          textAlign: TextAlign.center,
                          style: TextStyle(color: Colors.black54),
                        ),
                      ],
                    ),
                  );
                }

                return Column(
                  children: [
                    for (final group
                        in sudhamrtamMilkSubscriptions.duplicatePlans)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 12),
                        child: DuplicatePlansBanner(group: group),
                      ),
                    // One card per milk, with every shift in it.
                    for (final productId in const ['buffalo_milk', 'cow_milk'])
                      if (sudhamrtamMilkSubscriptions
                          .plansFor(productId)
                          .isNotEmpty)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 12),
                          child: MilkProductCard(
                            key: ValueKey('milk_$productId'),
                            productId: productId,
                            plans: sudhamrtamMilkSubscriptions.plansFor(
                              productId,
                            ),
                          ),
                        ),
                    _CancelledPlans(
                      plans: [
                        for (final plan in subscriptions)
                          if (plan.status == MilkSubscriptionStatus.cancelled)
                            plan,
                      ],
                    ),
                  ],
                );
              },
            ),

            const SizedBox(height: 28),

            // =================================================
            // DELIVERY OPTIONS
            // =================================================
            Text(
              'Flexible Delivery Options',
              style: Theme.of(context).textTheme.titleLarge
                  ?.copyWith(fontWeight: FontWeight.bold),
            ),

            const SizedBox(height: 16),

            const _DeliveryOption(
              icon: Icons.calendar_today_outlined,
              title: 'Daily Delivery',
              subtitle: 'Fresh milk delivered every day.',
            ),

            const _DeliveryOption(
              icon: Icons.date_range_outlined,
              title: 'Alternate Days',
              subtitle: 'Milk delivered every other day.',
            ),

            const _DeliveryOption(
              icon: Icons.event_available_outlined,
              title: 'Selected Days',
              subtitle: 'Choose your preferred weekdays.',
            ),

            const _DeliveryOption(
              icon: Icons.calendar_month_outlined,
              title: 'Random Days',
              subtitle: 'Choose individual delivery dates.',
            ),

            const SizedBox(height: 24),

            // =================================================
            // BRAND VALUES
            // =================================================
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: const Color(0xFFF5F8F0),
                borderRadius: BorderRadius.circular(14),
              ),
              child: const Row(
                children: [
                  Icon(Icons.verified_outlined, color: brandGreen),
                  SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      'Pure • Natural • Delivered Fresh',
                      style: TextStyle(fontWeight: FontWeight.w600),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ============================================================
// SAVED MILK SUBSCRIPTION CARD
// ============================================================

/// One plan inside a milk's card: its shift(s) and its actions.
class _SavedSubscriptionCard extends StatefulWidget {
  final MilkSubscription subscription;

  /// True when the milk has more than one plan (e.g. a separate
  /// morning and evening plan): each gets compact buttons.
  final bool compact;

  const _SavedSubscriptionCard({
    super.key,
    required this.subscription,
    this.compact = false,
  });

  @override
  State<_SavedSubscriptionCard> createState() => _SavedSubscriptionCardState();
}

class _SavedSubscriptionCardState extends State<_SavedSubscriptionCard> {
  bool _isProcessing = false;
  MilkSubscription get subscription => widget.subscription;

  void _showMessage(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), behavior: SnackBarBehavior.floating),
    );
  }

  Future<void> _changeStatus({required bool pause}) async {
    if (_isProcessing) return;
    DateTime? resumeOn;
    if (pause) {
      final choice = await askPauseKind(context);
      if (choice == null || !mounted) return;
      if (choice == PauseKind.vacation) {
        resumeOn = await pickReturnDate(context);
        if (resumeOn == null || !mounted) return;
      }
    }
    setState(() => _isProcessing = true);
    try {
      final success = pause
          ? await sudhamrtamMilkSubscriptions.pauseSubscription(
              subscription.id,
              resumeOn: resumeOn,
            )
          : await sudhamrtamMilkSubscriptions.resumeSubscription(
              subscription.id,
            );
      if (!mounted) return;
      _showMessage(
        success
            ? (pause
                  ? (resumeOn == null
                        ? 'Milk subscription paused.'
                        : 'Enjoy your trip! Milk restarts on '
                              '${planDateText(resumeOn)}.')
                  : 'Milk subscription resumed.')
            : 'Unable to change subscription status. Please try again.',
      );
    } catch (error) {
      debugPrint('Milk subscription status error: $error');
      _showMessage(
        error is MilkPlanSyncException
            ? error.message
            : 'Unable to save subscription status. Please try again.',
      );
    } finally {
      if (mounted) setState(() => _isProcessing = false);
    }
  }

  // ==========================================================
  // PRODUCT NAME
  // ==========================================================

  String get _productName {
    switch (subscription.productId) {
      case 'buffalo_milk':
        return 'Buffalo Milk';

      case 'cow_milk':
        return 'Cow Milk';

      default:
        return subscription.productId;
    }
  }

  // ==========================================================
  // DELIVERY FREQUENCY NAME
  // ==========================================================

  String get _frequencyName {
    switch (subscription.frequency) {
      case MilkDeliveryFrequency.daily:
        return 'Daily Delivery';

      case MilkDeliveryFrequency.alternateDays:
        return 'Alternate Days';

      case MilkDeliveryFrequency.selectedDays:
        return 'Selected Days';

      case MilkDeliveryFrequency.randomDays:
        return 'Random Days';
    }
  }

  // ==========================================================
  // DELIVERY DETAILS
  // ==========================================================

  String get _deliveryDetails {
    if (subscription.frequency == MilkDeliveryFrequency.selectedDays) {
      const weekdayNames = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];

      final days = subscription.selectedWeekdays
          .where((day) => day >= 1 && day <= 7)
          .map((day) => weekdayNames[day - 1])
          .join(', ');

      return days.isEmpty ? 'No weekdays selected' : days;
    }

    if (subscription.frequency == MilkDeliveryFrequency.randomDays) {
      final dates = subscription.selectedRandomDates.toList()..sort();

      if (dates.isEmpty) {
        return 'No dates selected';
      }

      return dates
          .map((date) {
            return '${date.day}/${date.month}/${date.year}';
          })
          .join(', ');
    }

    if (subscription.frequency == MilkDeliveryFrequency.alternateDays) {
      return 'Every other day';
    }

    return 'Every day';
  }

  // ==========================================================
  // STEP 120.3.2 — EDIT SUBSCRIPTION
  // ==========================================================

  void _editSubscription(BuildContext context) {
    // Cancelled subscriptions cannot be edited.
    if (subscription.status == MilkSubscriptionStatus.cancelled) {
      return;
    }

    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (context) => MilkSubscriptionSetupScreen(
          productName: _productName,
          existingSubscription: subscription,
        ),
      ),
    );
  }

  // ==========================================================
  // STEP 119 — CANCEL SUBSCRIPTION
  // ==========================================================

  Future<void> _confirmCancellation(BuildContext context) async {
    final shouldCancel = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: const Text('Cancel Milk Subscription?'),
          content: Text(
            'Are you sure you want to cancel your '
            '$_productName subscription?\n\n'
            'This action cannot be undone. '
            'You can create a new subscription later.',
          ),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.of(dialogContext).pop(false);
              },
              child: const Text('Keep Plan'),
            ),
            TextButton(
              onPressed: () {
                Navigator.of(dialogContext).pop(true);
              },
              style: TextButton.styleFrom(foregroundColor: Colors.red),
              child: const Text('Yes, Cancel'),
            ),
          ],
        );
      },
    );

    if (shouldCancel != true) {
      return;
    }

    if (!context.mounted) {
      return;
    }

    // Check the latest status in the manager.
    final matchingSubscriptions = sudhamrtamMilkSubscriptions.subscriptions
        .where((item) => item.id == subscription.id);

    if (matchingSubscriptions.isEmpty) {
      return;
    }

    if (matchingSubscriptions.first.status ==
        MilkSubscriptionStatus.cancelled) {
      return;
    }

    if (_isProcessing) return;
    setState(() => _isProcessing = true);
    try {
      final success = await sudhamrtamMilkSubscriptions.cancelSubscription(
        subscription.id,
      );
      if (!mounted) return;
      _showMessage(
        success
            ? '$_productName subscription cancelled.'
            : 'Unable to cancel this subscription. Please try again.',
      );
    } catch (error) {
      debugPrint('Milk subscription cancellation error: $error');
      _showMessage(
        error is MilkPlanSyncException
            ? error.message
            : 'Unable to save cancellation. Please try again.',
      );
    } finally {
      if (mounted) setState(() => _isProcessing = false);
    }
  }

  // ==========================================================
  // BUILD SUBSCRIPTION CARD
  // ==========================================================

  @override
  Widget build(BuildContext context) {
    const brandGreen = Color(0xFF82B440);

    final isActive = subscription.status == MilkSubscriptionStatus.active;

    final isCancelled = subscription.status == MilkSubscriptionStatus.cancelled;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // =================================================
        // DELIVERY SCHEDULES, EARLY MORNING TO EVENING
        // =================================================
        if (subscription.isWaitingForApproval) ...[
          Container(
            key: const Key('approvalNote'),
            width: double.infinity,
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: const Color(0xFFF3E5F5),
              borderRadius: BorderRadius.circular(10),
            ),
            child: const Text(
              'Waiting for approval · Sudhamrtam will check your plan. '
              'Milk starts once it is approved.',
              style: TextStyle(
                color: Color(0xFF6A1B9A),
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          const SizedBox(height: 8),
        ],
        if (subscription.isOnVacation(DateTime.now())) ...[
          Container(
            key: const Key('vacationNote'),
            width: double.infinity,
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: const Color(0xFFE3F2FD),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Text(
              'On vacation · milk restarts on '
              '${planDateText(subscription.resumeOn!)}',
              style: const TextStyle(
                color: Color(0xFF1565C0),
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          const SizedBox(height: 8),
        ],
        if (subscription.shiftSchedules.isNotEmpty) ...[
          for (final shift in MilkDeliveryShift.values)
            for (final schedule in subscription.shiftSchedules.where(
              (item) => item.shift == shift,
            )) ...[
              _ShiftScheduleSummary(schedule: schedule, paused: !isActive),
              const SizedBox(height: 8),
            ],
        ] else ...[
          // Plans created before the shift upgrade.
          const Text(
            'Earlier subscription — original delivery schedule',
            style: TextStyle(color: Colors.black54, fontSize: 12),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              const Icon(
                Icons.local_drink_outlined,
                color: brandGreen,
                size: 20,
              ),
              const SizedBox(width: 8),
              Text('${subscription.quantity} unit(s) per delivery'),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              const Icon(
                Icons.calendar_today_outlined,
                color: brandGreen,
                size: 20,
              ),
              const SizedBox(width: 8),
              Expanded(child: Text(_frequencyName)),
            ],
          ),
          const SizedBox(height: 10),
          Padding(
            padding: const EdgeInsets.only(left: 28),
            child: Text(
              _deliveryDetails,
              style: const TextStyle(color: Colors.black54, fontSize: 13),
            ),
          ),
        ],

        if (_isProcessing) ...[
          const SizedBox(height: 12),
          const LinearProgressIndicator(),
        ],

        // =================================================
        // ACTIVE / PAUSED SUBSCRIPTION ACTIONS
        // =================================================
        if (!isCancelled && widget.compact)
          Wrap(
            alignment: WrapAlignment.end,
            children: [
              TextButton.icon(
                onPressed: _isProcessing
                    ? null
                    : () => _editSubscription(context),
                icon: const Icon(Icons.edit_outlined, size: 18),
                label: const Text('Edit'),
                style: TextButton.styleFrom(foregroundColor: brandGreen),
              ),
              TextButton.icon(
                onPressed: _isProcessing
                    ? null
                    : () => _changeStatus(pause: isActive),
                icon: Icon(
                  isActive
                      ? Icons.pause_circle_outline
                      : Icons.play_circle_outline,
                  size: 18,
                ),
                label: Text(isActive ? 'Pause' : 'Resume'),
                style: TextButton.styleFrom(foregroundColor: brandGreen),
              ),
              TextButton.icon(
                onPressed: _isProcessing
                    ? null
                    : () => _confirmCancellation(context),
                icon: const Icon(Icons.cancel_outlined, size: 18),
                label: const Text('Cancel'),
                style: TextButton.styleFrom(foregroundColor: Colors.red),
              ),
            ],
          ),

        if (!isCancelled && !widget.compact) ...[
          const SizedBox(height: 8),

          // ===============================================
          // EDIT SUBSCRIPTION
          // ===============================================
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: _isProcessing
                  ? null
                  : () => _editSubscription(context),
              icon: const Icon(Icons.edit_outlined),
              label: const Text('Edit Subscription'),
              style: FilledButton.styleFrom(
                backgroundColor: brandGreen,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 12),
              ),
            ),
          ),

          const SizedBox(height: 10),

          // ===============================================
          // PAUSE / RESUME SUBSCRIPTION
          // ===============================================
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: _isProcessing
                  ? null
                  : () => _changeStatus(pause: isActive),
              icon: Icon(
                isActive
                    ? Icons.pause_circle_outline
                    : Icons.play_circle_outline,
              ),
              label: Text(
                isActive ? 'Pause Subscription' : 'Resume Subscription',
              ),
              style: OutlinedButton.styleFrom(
                foregroundColor: brandGreen,
                padding: const EdgeInsets.symmetric(vertical: 12),
              ),
            ),
          ),

          const SizedBox(height: 10),

          // ===============================================
          // CANCEL SUBSCRIPTION
          // ===============================================
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: _isProcessing
                  ? null
                  : () => _confirmCancellation(context),
              icon: const Icon(Icons.cancel_outlined),
              label: const Text('Cancel Subscription'),
              style: OutlinedButton.styleFrom(
                foregroundColor: Colors.red,
                side: const BorderSide(color: Colors.red),
                padding: const EdgeInsets.symmetric(vertical: 12),
              ),
            ),
          ),
        ],

        // =================================================
        // CANCELLED SUBSCRIPTION
        // =================================================
        if (isCancelled) ...[
          const SizedBox(height: 16),

          const Row(
            children: [
              Icon(Icons.info_outline, color: Colors.black54, size: 18),
              SizedBox(width: 8),
              Expanded(
                child: Text(
                  'This subscription has been cancelled.',
                  style: TextStyle(color: Colors.black54, fontSize: 13),
                ),
              ),
            ],
          ),
        ],
      ],
    );
  }
}

// ============================================================
// SHIFT SCHEDULE DISPLAY
// ============================================================

String _formatLitres(int millilitres) {
  final litres = millilitres / 1000;
  final number = litres == litres.roundToDouble()
      ? litres.toStringAsFixed(0)
      : litres.toStringAsFixed(1);
  return '$number L';
}

class _ShiftScheduleSummary extends StatelessWidget {
  final MilkShiftSchedule schedule;
  final bool paused;

  const _ShiftScheduleSummary({required this.schedule, this.paused = false});

  String get _frequencyLabel {
    switch (schedule.frequency) {
      case MilkDeliveryFrequency.daily:
        return 'Daily Delivery';
      case MilkDeliveryFrequency.alternateDays:
        return 'Alternate Days';
      case MilkDeliveryFrequency.selectedDays:
        return 'Selected Days';
      case MilkDeliveryFrequency.randomDays:
        return 'Random Days';
    }
  }

  String get _scheduleDetails {
    switch (schedule.frequency) {
      case MilkDeliveryFrequency.daily:
        return 'Every day';
      case MilkDeliveryFrequency.alternateDays:
        return 'Every other day';
      case MilkDeliveryFrequency.selectedDays:
        const names = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
        final weekdays = schedule.selectedWeekdays.toList()..sort();
        final labels = weekdays
            .where((day) => day >= 1 && day <= 7)
            .map((day) => names[day - 1]);
        return labels.isEmpty ? 'No weekdays selected' : labels.join(', ');
      case MilkDeliveryFrequency.randomDays:
        final dates = schedule.selectedRandomDates.toList()..sort();
        if (dates.isEmpty) return 'No dates selected';
        return dates
            .map((date) => '${date.day}/${date.month}/${date.year}')
            .join(', ');
    }
  }

  @override
  Widget build(BuildContext context) {
    const brandGreen = Color(0xFF82B440);

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFFF5F8F0),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(shiftIcon(schedule.shift), color: brandGreen, size: 22),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  '${shiftText(schedule.shift)} Delivery',
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
              ),
              Text(
                paused
                    ? '${_formatLitres(schedule.quantityMl)} (paused)'
                    : _formatLitres(schedule.quantityMl),
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  color: paused ? Colors.black45 : null,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(_frequencyLabel),
          const SizedBox(height: 4),
          Text(
            _scheduleDetails,
            style: const TextStyle(color: Colors.black54, fontSize: 13),
          ),
        ],
      ),
    );
  }
}

// ============================================================
// REUSABLE MILK PRODUCT CARD
// ============================================================

class _MilkProductCard extends StatelessWidget {
  final String name;
  final String description;
  final IconData icon;
  final VoidCallback onTap;

  const _MilkProductCard({
    required this.name,
    required this.description,
    required this.icon,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    const brandGreen = Color(0xFF82B440);

    return Card(
      elevation: 1,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(18),
          child: Row(
            children: [
              Container(
                width: 64,
                height: 64,
                decoration: BoxDecoration(
                  color: const Color(0xFFF5F8F0),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(icon, color: brandGreen, size: 34),
              ),

              const SizedBox(width: 16),

              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      name,
                      style: const TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.bold,
                      ),
                    ),

                    const SizedBox(height: 6),

                    Text(
                      description,
                      style: const TextStyle(
                        fontSize: 13,
                        color: Colors.black54,
                      ),
                    ),
                  ],
                ),
              ),

              const Icon(Icons.arrow_forward_ios, size: 16, color: brandGreen),
            ],
          ),
        ),
      ),
    );
  }
}

// ============================================================
// REUSABLE DELIVERY OPTION ROW
// ============================================================

class _DeliveryOption extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;

  const _DeliveryOption({
    required this.icon,
    required this.title,
    required this.subtitle,
  });

  @override
  Widget build(BuildContext context) {
    const brandGreen = Color(0xFF82B440);

    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Row(
        children: [
          Icon(icon, color: brandGreen, size: 28),

          const SizedBox(width: 16),

          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                  ),
                ),

                const SizedBox(height: 4),

                Text(
                  subtitle,
                  style: const TextStyle(fontSize: 13, color: Colors.black54),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Offers to combine plans for the same milk into one plan.
class DuplicatePlansBanner extends StatefulWidget {
  const DuplicatePlansBanner({super.key, required this.group});

  final DuplicateMilkPlans group;

  @override
  State<DuplicatePlansBanner> createState() => _DuplicatePlansBannerState();
}

class _DuplicatePlansBannerState extends State<DuplicatePlansBanner> {
  bool _working = false;

  Future<void> _combine() async {
    setState(() => _working = true);
    String? failure;
    var ok = false;
    try {
      ok = await sudhamrtamMilkSubscriptions.combinePlans(
        widget.group.productId,
      );
    } on MilkPlanSyncException catch (error) {
      failure = error.message;
    }
    if (!mounted) return;
    setState(() => _working = false);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          ok
              ? 'Merged your ${milkName(widget.group.productId)} deliveries.'
              : failure ?? 'The plans could not be combined. Please try again.',
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final group = widget.group;
    final name = milkName(group.productId);
    final summaries = [
      for (final plan in group.plans)
        plan.shiftSchedules
            .map((s) => '${shiftText(s.shift)} ${litresText(s.quantityMl)}')
            .join(' + '),
    ];

    final shared = {
      for (final outcome in group.changes.shifts)
        shiftText(outcome.shift).toLowerCase(),
    }.join(' and ');

    final detail = group.canCombine
        ? [
            'Merge the $shared deliveries? Each shift keeps one plan.',
            ...mergeLines(group.changes),
          ].join('\n')
        : [
            ...mergeLines(group.changes),
            'Please edit or cancel one of them, so each shift has one '
                '$name plan.',
          ].join('\n');

    return Container(
      key: Key('duplicatePlans_${group.productId}'),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFFFFF8E1),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFFFD54F)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            group.plans.length == 2
                ? 'Two $name plans deliver in the same shift'
                : '${group.plans.length} $name plans deliver in the same shift',
            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
          ),
          const SizedBox(height: 4),
          Text(summaries.join('   |   ')),
          const SizedBox(height: 8),
          Text(detail),
          if (group.canCombine) ...[
            const SizedBox(height: 12),
            FilledButton(
              key: const Key('combinePlans'),
              onPressed: _working ? null : _combine,
              style: FilledButton.styleFrom(
                backgroundColor: const Color(0xFF82B440),
              ),
              child: Text(_working ? 'Merging…' : 'Merge deliveries'),
            ),
          ],
        ],
      ),
    );
  }
}

/// One card per milk: every shift (from one or more plans), each
/// plan's actions, and the total.
class MilkProductCard extends StatelessWidget {
  const MilkProductCard({
    super.key,
    required this.productId,
    required this.plans,
  });

  final String productId;

  /// Not cancelled, for this milk.
  final List<MilkSubscription> plans;

  @override
  Widget build(BuildContext context) {
    const brandGreen = Color(0xFF82B440);

    // Morning plan first.
    final ordered = [...plans]
      ..sort(
        (a, b) => a.shiftSchedules.first.shift.index.compareTo(
          b.shiftSchedules.first.shift.index,
        ),
      );

    final active = plans
        .where((p) => p.status == MilkSubscriptionStatus.active)
        .toList();
    final today = DateTime.now();
    final status = plans.every((p) => p.isWaitingForApproval)
        ? 'Waiting for approval'
        : active.length == plans.length
        ? 'Active'
        : active.isEmpty && plans.every((p) => p.isOnVacation(today))
        ? 'On vacation'
        : active.isEmpty
        ? 'Paused'
        : 'Partly paused';

    return Card(
      key: Key('milkCard_$productId'),
      elevation: 1,
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.water_drop, color: brandGreen, size: 30),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    milkName(productId),
                    style: const TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 5,
                  ),
                  decoration: BoxDecoration(
                    color: status == 'Active'
                        ? const Color(0xFFE5F0D7)
                        : const Color(0xFFEEEEEE),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    status,
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                      color: status == 'Active'
                          ? const Color(0xFF4D7726)
                          : Colors.black54,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            for (final plan in ordered)
              _SavedSubscriptionCard(
                key: ValueKey(plan.id),
                subscription: plan,
                compact: plans.length > 1,
              ),
            const Divider(height: 24),
            Row(
              children: [
                const Icon(
                  Icons.local_drink_outlined,
                  color: brandGreen,
                  size: 20,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    milkTotalText(plans),
                    key: Key('milkTotal_$productId'),
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// The milk delivered per day across a milk's plans, counting only
/// deliveries that are not paused, e.g. "Total: 1.5 L every day".
String milkTotalText(List<MilkSubscription> plans) {
  final active = [
    for (final plan in plans)
      if (plan.status == MilkSubscriptionStatus.active) ...plan.shiftSchedules,
  ];
  final paused = [
    for (final plan in plans)
      if (plan.status != MilkSubscriptionStatus.active)
        for (final schedule in plan.shiftSchedules)
          shiftText(schedule.shift).toLowerCase(),
  ];
  final note = paused.isEmpty ? '' : ' (${paused.join(' and ')} paused)';

  if (active.isEmpty) return 'All deliveries are paused';

  final total = active.fold<int>(0, (sum, s) => sum + s.quantityMl);
  if (active.length == 1) {
    return 'Total: ${litresText(total)} ${deliveryDaysText(active.single)}$note';
  }

  final sameDays = active.every((s) => sameDeliveryDays(active.first, s));
  return sameDays
      ? 'Total: ${litresText(total)} ${deliveryDaysText(active.first)}$note'
      : 'Up to ${litresText(total)} on days with both deliveries$note';
}

enum PauseKind { untilResumed, vacation }

/// Asks how to pause: until the customer resumes, or a vacation with
/// a return date.
Future<PauseKind?> askPauseKind(BuildContext context) {
  return showModalBottomSheet<PauseKind>(
    context: context,
    showDragHandle: true,
    builder: (context) => SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ListTile(
            key: const Key('pauseVacation'),
            leading: const Icon(Icons.luggage_outlined),
            title: const Text('Going on vacation'),
            subtitle: const Text(
              'Choose your return date. Milk restarts by itself that day.',
            ),
            onTap: () => Navigator.pop(context, PauseKind.vacation),
          ),
          ListTile(
            key: const Key('pauseUntilResumed'),
            leading: const Icon(Icons.pause_circle_outline),
            title: const Text('Pause until I resume'),
            subtitle: const Text('Milk stops until you tap Resume.'),
            onTap: () => Navigator.pop(context, PauseKind.untilResumed),
          ),
        ],
      ),
    ),
  );
}

/// The first day milk should come again: tomorrow to 180 days ahead.
/// Tests replace it.
Future<DateTime?> Function(BuildContext context) pickReturnDate = (context) {
  final today = DateUtils.dateOnly(DateTime.now());
  return showDatePicker(
    context: context,
    initialDate: today.add(const Duration(days: 7)),
    firstDate: today.add(const Duration(days: 1)),
    lastDate: today.add(const Duration(days: 180)),
    helpText: 'Milk restarts on',
  );
};

/// "8 Nov 2026".
String planDateText(DateTime date) {
  const months = [
    'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', //
    'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
  ];
  return '${date.day} ${months[date.month - 1]} ${date.year}';
}

/// "Started 8 Nov 2026 · Cancelled 10 Nov 2026" for a cancelled plan.
String planDatesText(MilkSubscription plan) {
  final start = plan.shiftSchedules.isEmpty
      ? plan.startDate
      : plan.shiftSchedules
            .map((s) => s.startDate)
            .reduce((a, b) => a.isBefore(b) ? a : b);
  final cancelled = plan.cancelledAt;
  return [
    'Started ${planDateText(start)}',
    if (cancelled != null)
      '${plan.isRejected ? 'Not approved' : 'Cancelled'} '
          '${planDateText(cancelled)}',
  ].join(' · ');
}

/// Cancelled plans, listed briefly at the bottom.
class _CancelledPlans extends StatelessWidget {
  const _CancelledPlans({required this.plans});

  final List<MilkSubscription> plans;

  @override
  Widget build(BuildContext context) {
    if (plans.isEmpty) return const SizedBox.shrink();

    return ExpansionTile(
      key: const Key('cancelledPlans'),
      tilePadding: EdgeInsets.zero,
      title: Text(
        'Cancelled plans (${plans.length})',
        style: const TextStyle(color: Colors.black54),
      ),
      children: [
        for (final plan in plans)
          ListTile(
            dense: true,
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.history, color: Colors.black38),
            title: Text(milkName(plan.productId)),
            subtitle: Text(
              [
                plan.shiftSchedules
                    .map(
                      (s) =>
                          '${shiftText(s.shift)} ${litresText(s.quantityMl)} '
                          '${deliveryDaysText(s)}',
                    )
                    .join(', '),
                planDatesText(plan),
                if (plan.isRejected && plan.rejectReason != null)
                  'Reason: ${plan.rejectReason}',
              ].join('\n'),
            ),
          ),
      ],
    );
  }
}

/// Opens the setup for a new plan. With a server, milk plans belong
/// to the account, so the customer signs in first.
Future<void> openMilkPlanSetup(BuildContext context, String productName) async {
  final auth = sudhamrtamAuth;
  if (sudhamrtamMilkSync.isAvailable &&
      auth != null &&
      auth.currentUser == null) {
    await Navigator.of(context).push<bool>(
      MaterialPageRoute<bool>(builder: (_) => PhoneLoginScreen(auth: auth)),
    );
    if (!context.mounted || auth.currentUser == null) return;
  }
  if (!context.mounted) return;
  await Navigator.of(context).push(
    MaterialPageRoute<void>(
      builder: (context) =>
          MilkSubscriptionSetupScreen(productName: productName),
    ),
  );
}
