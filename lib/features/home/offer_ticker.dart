import 'package:flutter/material.dart';

const _green = Color(0xFF82B440);
const _separator = '   •   ';

/// A thin green line that scrolls the owner's offers across the top
/// of the Home tab, one after another, without end. Text that fits
/// stays still, and so does everything when the phone asks for
/// fewer animations.
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
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(vsync: this);

  @override
  void dispose() {
    _controller.dispose();
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
      fontWeight: FontWeight.w600,
      fontSize: 14,
    );

    return Semantics(
      label: 'Offers: ${widget.messages.join('. ')}',
      excludeSemantics: true,
      child: Container(
        key: const Key('offer-ticker'),
        height: 36,
        color: _green,
        padding: const EdgeInsets.only(left: 12),
        child: Row(
          children: [
            const Icon(Icons.campaign_outlined, color: Colors.white, size: 20),
            const SizedBox(width: 8),
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
