import 'package:flutter/material.dart';

import '../../app/sudhamrtam_app.dart';
import '../../models/milk_subscription.dart';
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
            // Main heading
            Text(
              'Fresh Milk, Morning & Evening',
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
              onTap: () {
                Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (context) => const MilkSubscriptionSetupScreen(
                      productName: 'Buffalo Milk',
                    ),
                  ),
                );
              },
            ),

            const SizedBox(height: 16),

            // =================================================
            // COW MILK
            // =================================================
            _MilkProductCard(
              name: 'Cow Milk',
              description: 'Fresh, wholesome cow milk.',
              icon: Icons.water_drop_outlined,
              onTap: () {
                Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (context) => const MilkSubscriptionSetupScreen(
                      productName: 'Cow Milk',
                    ),
                  ),
                );
              },
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
                  children: subscriptions.map((subscription) {
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: _SavedSubscriptionCard(
                        key: ValueKey(subscription.id),
                        subscription: subscription,
                      ),
                    );
                  }).toList(),
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

class _SavedSubscriptionCard extends StatefulWidget {
  final MilkSubscription subscription;

  const _SavedSubscriptionCard({super.key, required this.subscription});

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
    setState(() => _isProcessing = true);
    try {
      final success = pause
          ? await sudhamrtamMilkSubscriptions.pauseSubscription(subscription.id)
          : await sudhamrtamMilkSubscriptions.resumeSubscription(
              subscription.id,
            );
      if (!mounted) return;
      _showMessage(
        success
            ? (pause
                  ? 'Milk subscription paused.'
                  : 'Milk subscription resumed.')
            : 'Unable to change subscription status. Please try again.',
      );
    } catch (error) {
      debugPrint('Milk subscription status error: $error');
      _showMessage('Unable to save subscription status. Please try again.');
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
  // SUBSCRIPTION STATUS
  // ==========================================================

  String get _statusName {
    switch (subscription.status) {
      case MilkSubscriptionStatus.active:
        return 'Active';

      case MilkSubscriptionStatus.paused:
        return 'Paused';

      case MilkSubscriptionStatus.cancelled:
        return 'Cancelled';
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
      _showMessage('Unable to save cancellation. Please try again.');
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

    return Card(
      elevation: 1,
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // =================================================
            // PRODUCT NAME AND STATUS
            // =================================================

            Row(
              children: [
                const Icon(Icons.water_drop, color: brandGreen, size: 30),

                const SizedBox(width: 12),

                Expanded(
                  child: Text(
                    _productName,
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
                    color: isActive
                        ? const Color(0xFFE5F0D7)
                        : const Color(0xFFEEEEEE),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    _statusName,
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                      color: isActive
                          ? const Color(0xFF4D7726)
                          : Colors.black54,
                    ),
                  ),
                ),
              ],
            ),

            const SizedBox(height: 16),

            // =================================================
            // MORNING / EVENING DELIVERY SCHEDULES
            // =================================================
            if (subscription.shiftSchedules.isNotEmpty) ...[
              for (final shift in MilkDeliveryShift.values)
                for (final schedule in subscription.shiftSchedules.where(
                  (item) => item.shift == shift,
                )) ...[
                  _ShiftScheduleSummary(schedule: schedule),
                  const SizedBox(height: 12),
                ],
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
                      'Combined quantity when both shifts deliver: '
                      '${_formatLitres(subscription.combinedQuantityMl)}',
                      style: const TextStyle(fontWeight: FontWeight.w600),
                    ),
                  ),
                ],
              ),
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
            if (!isCancelled) ...[
              const SizedBox(height: 16),

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
        ),
      ),
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

  const _ShiftScheduleSummary({required this.schedule});

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
    final isMorning = schedule.shift == MilkDeliveryShift.morning;

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
              Icon(
                isMorning
                    ? Icons.wb_sunny_outlined
                    : Icons.nights_stay_outlined,
                color: brandGreen,
                size: 22,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  isMorning ? 'Morning Delivery' : 'Evening Delivery',
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
              ),
              Text(
                _formatLitres(schedule.quantityMl),
                style: const TextStyle(fontWeight: FontWeight.bold),
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
