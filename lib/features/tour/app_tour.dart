import 'package:flutter/material.dart';

import '../../database/milk_database_service.dart';

/// The first-login tour (owner request and decisions 2026-11-28): after
/// signing in, once per phone (existing customers once after updating
/// too), each main option is lit up in turn with a short explanation.
/// Skip ends it; Account → "Show the app tour" plays it again. Phone
/// app only for now (not the wide website layout).

/// The app setting that remembers the tour was seen on this phone.
const appTourSeenKey = 'app_tour_seen';

/// Bumped by Account → "Show the app tour"; the shell plays it.
final appTourRequests = ValueNotifier<int>(0);

Future<bool> appTourSeen() async {
  final db = await MilkDatabaseService.instance.database;
  final rows = await db.query(
    MilkDatabaseService.appSettingsTable,
    where: 'key = ?',
    whereArgs: [appTourSeenKey],
    limit: 1,
  );
  return rows.isNotEmpty;
}

Future<void> markAppTourSeen() async {
  final db = await MilkDatabaseService.instance.database;
  await db.rawInsert(
    'INSERT OR REPLACE INTO ${MilkDatabaseService.appSettingsTable} '
    '(key, value) VALUES (?, ?)',
    [appTourSeenKey, DateTime.now().toIso8601String()],
  );
}

/// One stop: [target] is where the option is on screen now (global
/// coordinates); null for a card in the middle (the welcome). A stop
/// whose option is not on screen is passed over.
class TourStep {
  const TourStep({
    required this.title,
    required this.body,
    this.target,
    this.icon,
  });

  final String title;
  final String body;
  final Rect? Function()? target;
  final IconData? icon;
}

/// Where [key]'s widget is on screen; null when it is not shown.
Rect? rectOf(GlobalKey key) {
  final box = key.currentContext?.findRenderObject();
  if (box is! RenderBox || !box.attached || !box.hasSize) return null;
  if (box.size.isEmpty) return null;
  return box.localToGlobal(Offset.zero) & box.size;
}

/// The tour over the whole screen.
class AppTourOverlay extends StatefulWidget {
  const AppTourOverlay({super.key, required this.steps, required this.onEnd});

  final List<TourStep> steps;

  /// Called once, when Done or Skip is tapped.
  final VoidCallback onEnd;

  @override
  State<AppTourOverlay> createState() => _AppTourOverlayState();
}

class _AppTourOverlayState extends State<AppTourOverlay> {
  int _index = 0;
  bool _ended = false;

  @override
  void initState() {
    super.initState();
    // The first stop may be one whose option is not shown.
    WidgetsBinding.instance.addPostFrameCallback((_) => _passOverHidden());
  }

  /// The stops that can be shown now.
  bool _shown(TourStep step) => step.target == null || step.target!() != null;

  void _passOverHidden() {
    if (!mounted) return;
    while (_index < widget.steps.length && !_shown(widget.steps[_index])) {
      _index++;
    }
    if (_index >= widget.steps.length) {
      _end();
    } else {
      setState(() {});
    }
  }

  void _next() {
    setState(() => _index++);
    _passOverHidden();
  }

  void _end() {
    if (_ended) return;
    _ended = true;
    widget.onEnd();
  }

  @override
  Widget build(BuildContext context) {
    if (_index >= widget.steps.length) return const SizedBox.shrink();
    final step = widget.steps[_index];
    final overlayBox = context.findRenderObject();
    // Option rects are global; this overlay may not start at 0,0.
    final origin = overlayBox is RenderBox && overlayBox.hasSize
        ? overlayBox.localToGlobal(Offset.zero)
        : Offset.zero;
    final target = step.target?.call()?.shift(-origin);
    final hole = target?.inflate(6);
    final visible = [
      for (final s in widget.steps)
        if (_shown(s)) s,
    ];
    // "2 of 5" counts the options lit up, not the welcome card.
    final options = [
      for (final s in visible)
        if (s.target != null) s,
    ];
    final number = options.indexOf(step) + 1;
    final last = identical(visible.last, step);

    return LayoutBuilder(
      builder: (context, constraints) {
        final size = constraints.biggest;
        final cardWidth = (size.width - 32).clamp(0.0, 380.0);
        final card = _TourCard(
          key: Key('tour-step-$_index'),
          step: step,
          number: number,
          count: options.length,
          last: last,
          welcome: target == null,
          onNext: last ? _end : _next,
          onSkip: _end,
        );
        Widget placed;
        if (hole == null) {
          placed = Center(
            child: SizedBox(width: cardWidth, child: card),
          );
        } else if (hole.center.dy > size.height / 2) {
          // The option is low (the bottom bar): the card above it.
          placed = Positioned(
            left: 16,
            right: 16,
            bottom: size.height - hole.top + 12,
            child: Center(
              child: SizedBox(width: cardWidth, child: card),
            ),
          );
        } else {
          placed = Positioned(
            left: 16,
            right: 16,
            top: hole.bottom + 12,
            child: Center(
              child: SizedBox(width: cardWidth, child: card),
            ),
          );
        }
        return Stack(
          key: const Key('app-tour'),
          children: [
            // Taps on the dark part do nothing: the buttons lead.
            Positioned.fill(
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () {},
                child: CustomPaint(painter: _ScrimPainter(hole)),
              ),
            ),
            placed,
          ],
        );
      },
    );
  }
}

/// The dark layer with a lit-up hole around the option.
class _ScrimPainter extends CustomPainter {
  _ScrimPainter(this.hole);

  final Rect? hole;

  @override
  void paint(Canvas canvas, Size size) {
    final scrim = Path()..addRect(Offset.zero & size);
    final hole = this.hole;
    if (hole != null) {
      final rounded = RRect.fromRectAndRadius(hole, const Radius.circular(16));
      canvas.drawPath(
        Path.combine(
          PathOperation.difference,
          scrim,
          Path()..addRRect(rounded),
        ),
        Paint()..color = Colors.black.withValues(alpha: 0.72),
      );
      canvas.drawRRect(
        rounded,
        Paint()
          ..color = const Color(0xFFFFD54F)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 3,
      );
    } else {
      canvas.drawPath(
        scrim,
        Paint()..color = Colors.black.withValues(alpha: 0.72),
      );
    }
  }

  @override
  bool shouldRepaint(_ScrimPainter old) => old.hole != hole;
}

class _TourCard extends StatelessWidget {
  const _TourCard({
    super.key,
    required this.step,
    required this.number,
    required this.count,
    required this.last,
    required this.welcome,
    required this.onNext,
    required this.onSkip,
  });

  final TourStep step;
  final int number;
  final int count;
  final bool last;
  final bool welcome;
  final VoidCallback onNext;
  final VoidCallback onSkip;

  @override
  Widget build(BuildContext context) {
    const brandGreen = Color(0xFF82B440);
    final theme = Theme.of(context);
    return Material(
      color: Colors.white,
      elevation: 8,
      borderRadius: BorderRadius.circular(16),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(18, 16, 12, 8),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                if (step.icon != null) ...[
                  Icon(step.icon, color: brandGreen),
                  const SizedBox(width: 8),
                ],
                Expanded(
                  child: Text(
                    step.title,
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                if (!welcome)
                  Text(
                    '$number of $count',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: Colors.black54,
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 8),
            Text(step.body, style: theme.textTheme.bodyMedium),
            const SizedBox(height: 4),
            Row(
              children: [
                if (!last)
                  TextButton(
                    key: const Key('tour-skip'),
                    onPressed: onSkip,
                    child: const Text('Skip'),
                  ),
                const Spacer(),
                FilledButton(
                  key: const Key('tour-next'),
                  style: FilledButton.styleFrom(backgroundColor: brandGreen),
                  onPressed: onNext,
                  child: Text(
                    last
                        ? 'Done'
                        : welcome
                        ? 'Show me'
                        : 'Next',
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

/// The stops on the phone app, in order. [slot] gives the rect of a
/// bottom-bar tab (0 Home … 4 Account); [bell] the Messages bell.
List<TourStep> customerTourSteps({
  required Rect? Function(int tab) slot,
  required Rect? Function() bell,
}) => [
  const TourStep(
    title: 'Welcome to Sudhamrtam',
    body:
        'Fresh milk and more from our farm to your door. Here is a quick '
        'look around: it takes less than a minute.',
    icon: Icons.waving_hand_outlined,
  ),
  TourStep(
    title: 'Shop',
    body:
        'Milk, curd, paneer, ghee, honey and wood-pressed oils. Order by '
        '9 PM and it comes the next morning. Minimum order ₹200, with free '
        'delivery.',
    icon: Icons.storefront_outlined,
    target: () => slot(1),
  ),
  TourStep(
    title: 'Subscriptions',
    body:
        'Daily milk: set it up once and it comes every day. Pause it when '
        'you travel. We check each new subscription and tell you when it '
        'is approved.',
    icon: Icons.calendar_month_outlined,
    target: () => slot(2),
  ),
  TourStep(
    title: 'Cart',
    body:
        'Your items before you order. Check them, choose your address and '
        'how to pay, and place the order.',
    icon: Icons.shopping_cart_outlined,
    target: () => slot(3),
  ),
  TourStep(
    title: 'Messages',
    body: 'News, offers and delivery updates from Sudhamrtam come here.',
    icon: Icons.notifications_outlined,
    target: bell,
  ),
  TourStep(
    title: 'Account',
    body:
        'Your addresses, orders, milk bills and Help & Support. You can '
        'see this tour again from here.',
    icon: Icons.person_outline,
    target: () => slot(4),
  ),
];
