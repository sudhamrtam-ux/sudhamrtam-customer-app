import 'package:flutter/material.dart';

/// Warm offer colours (owner request 2026-11-15: easier to notice).
const _offerDeep = Color(0xFFD84315);
const _offerBright = Color(0xFFFF8F00);
const _separator = '   •   ';

/// A warm orange ribbon that scrolls the owner's offers across the top
/// of the Home tab, one after another, without end, with an OFFERS tag
/// and a gentle glow that pulses so it is noticed. Text that fits
/// stays still, and so does everything when the phone asks for fewer
/// animations.
class OfferTicker extends StatefulWidget {
  const OfferTicker({
    super.key,
    required this.messages,
    this.pixelsPerSecond = 40,
  });

  final List<String> messages;
  final double pixelsPerSecond;

  @override
  State<OfferTicker> createState() => _OfferTickerState();
}

class _OfferTickerState extends State<OfferTicker>
    with TickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(vsync: this);

  /// The mild pulse of the ribbon's glow (a few times, then steady).
  late final AnimationController _pulse = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1400),
  );

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (MediaQuery.disableAnimationsOf(context)) {
      _pulse.stop();
      _pulse.value = 0;
    } else if (!_pulse.isAnimating && _pulse.value == 0) {
      // A few mild flashes when the ribbon appears, then it glows.
      _pulse.repeat(reverse: true, count: 5);
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    _pulse.dispose();
    super.dispose();
  }

  /// Runs one cycle in [duration] (null: stays still). Called after
  /// layout, because the duration depends on the text's width.
  void _run(Duration? duration) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (duration == null) {
        if (_controller.isAnimating) _controller.stop();
        _controller.value = 0;
      } else if (_controller.duration != duration || !_controller.isAnimating) {
        _controller.duration = duration;
        _controller.repeat();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final text = widget.messages.join(_separator);
    const style = TextStyle(
      color: Colors.white,
      fontWeight: FontWeight.w700,
      fontSize: 14,
    );

    return Semantics(
      label: 'Offers: ${widget.messages.join('. ')}',
      excludeSemantics: true,
      child: AnimatedBuilder(
        animation: _pulse,
        builder: (context, child) {
          final t = Curves.easeInOut.transform(_pulse.value);
          return Container(
            key: const Key('offer-ticker'),
            height: 42,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  _offerDeep,
                  Color.lerp(_offerBright, const Color(0xFFFFB300), t)!,
                ],
              ),
              boxShadow: [
                BoxShadow(
                  color: _offerBright.withValues(alpha: 0.25 + 0.35 * t),
                  blurRadius: 6 + 8 * t,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            padding: const EdgeInsets.only(left: 10),
            child: child,
          );
        },
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(20),
              ),
              child: const Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.local_offer, color: _offerDeep, size: 14),
                  SizedBox(width: 4),
                  Text(
                    'OFFERS',
                    style: TextStyle(
                      color: _offerDeep,
                      fontWeight: FontWeight.w800,
                      fontSize: 11.5,
                      letterSpacing: 0.6,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final painter = TextPainter(
                    text: TextSpan(text: text + _separator, style: style),
                    textDirection: TextDirection.ltr,
                    textScaler: MediaQuery.textScalerOf(context),
                    maxLines: 1,
                  )..layout();
                  final textOnly = TextPainter(
                    text: TextSpan(text: text, style: style),
                    textDirection: TextDirection.ltr,
                    textScaler: MediaQuery.textScalerOf(context),
                    maxLines: 1,
                  )..layout();
                  final still =
                      textOnly.width <= constraints.maxWidth ||
                      MediaQuery.disableAnimationsOf(context);

                  if (still) {
                    _run(null);
                    return Align(
                      alignment: Alignment.centerLeft,
                      child: Padding(
                        padding: const EdgeInsets.only(right: 12),
                        child: Text(
                          text,
                          style: style,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    );
                  }

                  // One cycle moves the text and its separator once,
                  // where the second copy takes over seamlessly.
                  final cycle = painter.width;
                  _run(
                    Duration(
                      milliseconds: (cycle / widget.pixelsPerSecond * 1000)
                          .round(),
                    ),
                  );
                  return ClipRect(
                    child: AnimatedBuilder(
                      animation: _controller,
                      builder: (context, child) => Transform.translate(
                        offset: Offset(-_controller.value * cycle, 0),
                        child: child,
                      ),
                      child: OverflowBox(
                        alignment: Alignment.centerLeft,
                        minWidth: 0,
                        maxWidth: double.infinity,
                        child: Text(
                          '$text$_separator$text$_separator',
                          style: style,
                          maxLines: 1,
                          softWrap: false,
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}
