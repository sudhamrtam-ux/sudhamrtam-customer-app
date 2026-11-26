import 'dart:math' as math;

import 'package:flutter/material.dart';

/// Combo tiles on Home (owner request and decisions 2026-11-26): the
/// owner's picture, else the products drawn as a gift (photos, a ribbon
/// bow and a hanging tag). The staff app draws the same tiles as a
/// preview (keep the two in step).

/// The tile colour of each occasion; [offerGreen] for any other.
const occasionTileColours = {
  'festive': Color(0xFF8E1B3A),
  'inaugural': Color(0xFFC8641A),
  'seasonal': Color(0xFF3F7A22),
  'month_end': Color(0xFF2A5C9A),
  'year_end': Color(0xFFA8660A),
  'other': Color(0xFF4F7A1F),
};
const offerGreen = Color(0xFF4F7A1F);

/// Colours the owner can choose instead.
const tileSwatches = [
  Color(0xFF8E1B3A), // maroon
  Color(0xFFC8641A), // saffron
  Color(0xFF3F7A22), // leaf green
  Color(0xFF2F5D1E), // forest
  Color(0xFF1F6F6B), // teal
  Color(0xFF2A5C9A), // royal blue
  Color(0xFF5B3A9E), // purple
  Color(0xFFA8660A), // gold
  Color(0xFF3A3A3A), // charcoal
];

/// '#8E1B3A' ↔ Color.
Color? colourFromHex(String? hex) {
  if (hex == null || !RegExp(r'^#[0-9A-Fa-f]{6}$').hasMatch(hex)) return null;
  return Color(0xFF000000 | int.parse(hex.substring(1), radix: 16));
}

String colourToHex(Color c) =>
    '#${(c.toARGB32() & 0xFFFFFF).toRadixString(16).padLeft(6, '0').toUpperCase()}';

/// The tile's colour: the chosen one, else the occasion's.
Color tileColourFor(String? occasion, String? chosen) =>
    colourFromHex(chosen) ?? occasionTileColours[occasion] ?? offerGreen;

/// White words on dark colours, dark words on light ones.
Color tileTextColour(Color background) => background.computeLuminance() > 0.45
    ? const Color(0xFF2B2B2B)
    : Colors.white;

/// One product in the gift.
class GiftItem {
  const GiftItem({
    required this.name,
    required this.quantity,
    required this.pricePaise,
    this.image,
  });

  final String name;
  final int quantity;

  /// One unit's price: the pricier ones (jars) stand at the back.
  final int pricePaise;
  final ImageProvider? image;
}

/// Where each product stands: centre x, bottom y and height, as parts
/// of the picture; drawn in this order (back first).
List<(double, double, double)> _slots(int n) => switch (n) {
  1 => const [(0.5, 0.96, 0.78)],
  2 => const [(0.34, 0.93, 0.72), (0.68, 0.97, 0.6)],
  3 => const [(0.22, 0.9, 0.7), (0.78, 0.9, 0.7), (0.5, 0.98, 0.58)],
  4 => const [
    (0.2, 0.86, 0.66),
    (0.8, 0.86, 0.66),
    (0.5, 0.72, 0.5),
    (0.4, 0.99, 0.36),
  ],
  _ => const [
    (0.18, 0.84, 0.62),
    (0.82, 0.84, 0.62),
    (0.5, 0.7, 0.48),
    (0.3, 0.99, 0.35),
    (0.54, 0.99, 0.33),
  ],
};

/// The products arranged as a gift with a ribbon bow and a tag.
class GiftPicture extends StatelessWidget {
  const GiftPicture({super.key, required this.items, required this.tag});

  final List<GiftItem> items;

  /// The tag's first line, e.g. "Festive offer" or "Varalakshmi Vratham".
  final String tag;

  @override
  Widget build(BuildContext context) {
    final shown = [...items]
      ..sort((a, b) => b.pricePaise.compareTo(a.pricePaise));
    final gift = shown.take(5).toList();
    return LayoutBuilder(
      builder: (context, box) {
        final w = box.maxWidth;
        final h = box.maxHeight;
        if (gift.isEmpty) {
          return Center(
            child: Icon(Icons.redeem, size: h * 0.5, color: Colors.black12),
          );
        }
        final slots = _slots(gift.length);
        // The middle product carries the bow (the first with 1-2).
        final bowIndex = gift.length >= 3 ? 2 : 0;
        Rect rectOf(int i) {
          final (cx, bottom, height) = slots[i];
          final ih = h * height;
          final iw = math.min(ih * 0.82, w * 0.42);
          return Rect.fromLTWH(w * cx - iw / 2, h * bottom - ih, iw, ih);
        }

        final bowRect = rectOf(bowIndex);
        final bow = Offset(
          bowRect.center.dx,
          bowRect.top + bowRect.height * 0.08,
        );
        final bowSize = math.min(w, h) * 0.4;
        final children = <Widget>[];
        for (var i = 0; i < gift.length; i++) {
          // The ribbon tails hang behind the bow's product.
          if (i == bowIndex) {
            children.add(
              Positioned.fill(
                child: CustomPaint(
                  painter: _RibbonTails(knot: bow, size: bowSize, depth: h),
                ),
              ),
            );
          }
          final r = rectOf(i);
          children.add(
            Positioned.fromRect(
              rect: r,
              child: _ProductCard(item: gift[i]),
            ),
          );
        }
        children.add(
          Positioned(
            left: bow.dx - bowSize / 2,
            top: bow.dy - bowSize * 0.42,
            width: bowSize,
            height: bowSize * 0.7,
            child: const CustomPaint(painter: _Bow()),
          ),
        );
        // The tag hangs at the front right, on its string from the bow.
        final tagW = math.min(w * 0.27, 108.0);
        final tagLeft = w - tagW - w * 0.04;
        final tagTop = h * 0.56;
        children.add(
          Positioned.fill(
            child: CustomPaint(
              painter: _TagString(
                from: bow,
                to: Offset(tagLeft + tagW / 2, tagTop + 8),
              ),
            ),
          ),
        );
        children.add(
          Positioned(
            left: tagLeft,
            top: tagTop,
            width: tagW,
            child: _Tag(line: tag),
          ),
        );
        if (items.length > gift.length) {
          children.add(
            Positioned(
              left: 4,
              bottom: 4,
              child: _Badge('+${items.length - gift.length} more'),
            ),
          );
        }
        return Stack(clipBehavior: Clip.none, children: children);
      },
    );
  }
}

class _ProductCard extends StatelessWidget {
  const _ProductCard({required this.item});

  final GiftItem item;

  @override
  Widget build(BuildContext context) {
    final image = item.image;
    return Stack(
      clipBehavior: Clip.none,
      children: [
        Positioned.fill(
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: const Color(0xFFFFF8E8),
              borderRadius: BorderRadius.circular(14),
              boxShadow: const [
                BoxShadow(
                  color: Color(0x40000000),
                  blurRadius: 10,
                  offset: Offset(0, 4),
                ),
              ],
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(14),
              child: image != null
                  ? Image(image: image, fit: BoxFit.cover)
                  : _Placeholder(name: item.name),
            ),
          ),
        ),
        if (item.quantity > 1)
          Positioned(right: -4, top: -4, child: _Badge('×${item.quantity}')),
      ],
    );
  }
}

class _Placeholder extends StatelessWidget {
  const _Placeholder({required this.name});

  final String name;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, box) => Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0xFFFFFBF0), Color(0xFFF3E6C8)],
        ),
      ),
      padding: const EdgeInsets.all(4),
      alignment: Alignment.center,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.eco_outlined,
            size: box.maxWidth * 0.36,
            color: const Color(0xFF8BAA4A),
          ),
          const SizedBox(height: 2),
          Text(
            name,
            maxLines: 2,
            textAlign: TextAlign.center,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: Color(0xFF5A4A2A),
            ),
          ),
        ],
      ),
    ),
  );
}

class _Badge extends StatelessWidget {
  const _Badge(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
    decoration: BoxDecoration(
      color: const Color(0xFFB3202E),
      borderRadius: BorderRadius.circular(10),
    ),
    child: Text(
      text,
      style: const TextStyle(
        color: Colors.white,
        fontSize: 11,
        fontWeight: FontWeight.bold,
      ),
    ),
  );
}

const _red = Color(0xFFB3202E);
const _blue = Color(0xFF1F3F8F);
const _gold = Color(0xFFE2B33C);

/// Two loops of red, blue and gold ribbon with a knot.
class _Bow extends CustomPainter {
  const _Bow();

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;
    final knot = Offset(w / 2, h * 0.6);
    void loop(double dir, Color colour, double lift, double width) {
      final tip = Offset(knot.dx + dir * w * 0.46, knot.dy - h * lift);
      final path = Path()
        ..moveTo(knot.dx, knot.dy)
        ..cubicTo(
          knot.dx + dir * w * 0.12,
          knot.dy - h * (lift + 0.55),
          tip.dx,
          tip.dy - h * 0.35,
          tip.dx,
          tip.dy,
        )
        ..cubicTo(
          tip.dx,
          tip.dy + h * 0.32,
          knot.dx + dir * w * 0.14,
          knot.dy + h * 0.15,
          knot.dx,
          knot.dy,
        );
      canvas.drawPath(
        path,
        Paint()
          ..color = colour
          ..style = PaintingStyle.stroke
          ..strokeWidth = width
          ..strokeJoin = StrokeJoin.round,
      );
    }

    final s = w / 100;
    for (final dir in const [-1.0, 1.0]) {
      loop(dir, _blue, 0.18, 7 * s);
      loop(dir, _red, 0.1, 6 * s);
      loop(dir, _gold, 0.02, 3.5 * s);
    }
    canvas.drawOval(
      Rect.fromCenter(center: knot, width: 14 * s, height: 11 * s),
      Paint()..color = _red,
    );
    canvas.drawOval(
      Rect.fromCenter(
        center: knot - Offset(0, 1.5 * s),
        width: 7 * s,
        height: 4 * s,
      ),
      Paint()..color = const Color(0x55FFFFFF),
    );
  }

  @override
  bool shouldRepaint(_Bow old) => false;
}

/// Ribbon tails falling from the knot, behind the middle product.
class _RibbonTails extends CustomPainter {
  _RibbonTails({required this.knot, required this.size, required this.depth});

  final Offset knot;
  final double size;
  final double depth;

  @override
  void paint(Canvas canvas, Size box) {
    final s = size / 100;
    void tail(double dir, Color colour, double spread, double width) {
      final end = Offset(knot.dx + dir * size * spread, depth * 0.98);
      canvas.drawPath(
        Path()
          ..moveTo(knot.dx, knot.dy)
          ..cubicTo(
            knot.dx + dir * size * 0.5,
            knot.dy + (end.dy - knot.dy) * 0.3,
            knot.dx - dir * size * 0.15,
            knot.dy + (end.dy - knot.dy) * 0.7,
            end.dx,
            end.dy,
          ),
        Paint()
          ..color = colour
          ..style = PaintingStyle.stroke
          ..strokeWidth = width
          ..strokeCap = StrokeCap.butt,
      );
    }

    tail(-1, _blue, 0.55, 6 * s);
    tail(-1, _red, 0.4, 5 * s);
    tail(1, _red, 0.5, 5 * s);
    tail(1, _gold, 0.35, 4 * s);
  }

  @override
  bool shouldRepaint(_RibbonTails old) =>
      old.knot != knot || old.size != size || old.depth != depth;
}

/// The tag's string, from the bow's knot.
class _TagString extends CustomPainter {
  _TagString({required this.from, required this.to});

  final Offset from;
  final Offset to;

  @override
  void paint(Canvas canvas, Size size) {
    final mid = Offset((from.dx + to.dx) / 2, math.max(from.dy, to.dy) + 6);
    canvas.drawPath(
      Path()
        ..moveTo(from.dx, from.dy)
        ..quadraticBezierTo(mid.dx, mid.dy, to.dx, to.dy),
      Paint()
        ..color = const Color(0xFF8A6A1A)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.2,
    );
  }

  @override
  bool shouldRepaint(_TagString old) => old.from != from || old.to != to;
}

/// The hanging yellow tag: the occasion and "COMBO OFFER".
class _Tag extends StatelessWidget {
  const _Tag({required this.line});

  final String line;

  /// Up to two lines of whole words, the halves about even.
  static List<String> lines(String text) {
    final words = text.toUpperCase().split(RegExp(r'\s+'))
      ..removeWhere((w) => w.isEmpty);
    if (words.length < 2) return words;
    var best = 1;
    var bestDiff = 1 << 30;
    for (var i = 1; i < words.length; i++) {
      final diff =
          (words.take(i).join(' ').length - words.skip(i).join(' ').length)
              .abs();
      if (diff < bestDiff) {
        bestDiff = diff;
        best = i;
      }
    }
    return [words.take(best).join(' '), words.skip(best).join(' ')];
  }

  @override
  Widget build(BuildContext context) => Transform.rotate(
    angle: -0.12,
    child: Container(
      padding: const EdgeInsets.fromLTRB(6, 10, 6, 8),
      decoration: BoxDecoration(
        color: const Color(0xFFF6C343),
        border: Border.all(color: const Color(0xFFC0392B), width: 1.5),
        borderRadius: BorderRadius.circular(6),
        boxShadow: const [
          BoxShadow(
            color: Color(0x33000000),
            blurRadius: 6,
            offset: Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 7,
            height: 7,
            decoration: BoxDecoration(
              color: Colors.white,
              shape: BoxShape.circle,
              border: Border.all(color: const Color(0xFF8A6A1A)),
            ),
          ),
          const SizedBox(height: 4),
          for (final l in lines(line))
            FittedBox(
              fit: BoxFit.scaleDown,
              child: Text(
                l,
                maxLines: 1,
                style: const TextStyle(
                  fontSize: 10,
                  height: 1.15,
                  fontWeight: FontWeight.w700,
                  color: Color(0xFFB3202E),
                ),
              ),
            ),
          const SizedBox(height: 2),
          const FittedBox(
            child: Text(
              'COMBO\nOFFER',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 14,
                height: 1.0,
                fontWeight: FontWeight.w900,
                color: Color(0xFF2B2B2B),
              ),
            ),
          ),
        ],
      ),
    ),
  );
}

/// The size to make a combo's picture (owner request 2026-11-26): the
/// tile shows it at 4:3, never cropped when made at this shape.
const comboPictureWidth = 1200;
const comboPictureHeight = 900;
const comboPictureRatio = comboPictureWidth / comboPictureHeight;

/// A combo's tile: occasion badge, discount, title, products, saving,
/// price and its picture (the owner's, else the drawn gift). Wide
/// tiles put the words on the left and the picture on the right; tall
/// ones the picture in the middle.
class ComboTile extends StatelessWidget {
  const ComboTile({
    super.key,
    required this.colour,
    required this.headline,
    required this.title,
    required this.tag,
    required this.items,
    this.badge,
    this.chips = const [],
    this.saving,
    this.picture,
    this.price,
    this.fullPrice,
    this.footnote,
    this.action,
    this.priceKey,
  });

  final Color colour;

  /// For tests: the price text's key.
  final Key? priceKey;

  /// e.g. "10% off".
  final String headline;

  /// The combo's title.
  final String title;

  /// The drawn gift's tag (used without [picture]).
  final String tag;
  final List<GiftItem> items;

  /// e.g. "Festive offer".
  final String? badge;

  /// e.g. "2 × Curd 500 g".
  final List<String> chips;

  /// e.g. "You save ₹19.50".
  final String? saving;

  /// The owner's picture for the combo; null = the drawn gift.
  final ImageProvider? picture;

  /// e.g. "₹175.50" and the struck-through "₹195".
  final String? price;
  final String? fullPrice;

  /// e.g. "Ends 2 Dec".
  final String? footnote;

  /// e.g. an Add to cart button.
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    final ink = tileTextColour(colour);
    final soft = ink.withValues(alpha: 0.85);

    final badgeChip = badge == null
        ? null
        : Container(
            padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
            decoration: BoxDecoration(
              color: const Color(0xFFF6C343),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.redeem, size: 13, color: Color(0xFF5A3A00)),
                const SizedBox(width: 4),
                Text(
                  badge!.toUpperCase(),
                  style: const TextStyle(
                    fontSize: 10.5,
                    letterSpacing: 0.6,
                    fontWeight: FontWeight.w800,
                    color: Color(0xFF5A3A00),
                  ),
                ),
              ],
            ),
          );
    final headlineText = Text(
      headline,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: TextStyle(
        color: ink,
        fontSize: 30,
        height: 1.05,
        fontWeight: FontWeight.w900,
        letterSpacing: -0.3,
      ),
    );
    Text titleText(int lines) => Text(
      title,
      maxLines: lines,
      overflow: TextOverflow.ellipsis,
      style: TextStyle(
        color: ink,
        fontSize: 16,
        height: 1.25,
        fontWeight: FontWeight.w600,
      ),
    );
    final chipRow = chips.isEmpty
        ? null
        : Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              for (final c in chips)
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 9,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: ink.withValues(alpha: 0.12),
                    border: Border.all(color: ink.withValues(alpha: 0.22)),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Text(c, style: TextStyle(color: ink, fontSize: 12)),
                ),
            ],
          );
    final picturePanel = ClipRRect(
      borderRadius: BorderRadius.circular(14),
      child: AspectRatio(
        aspectRatio: comboPictureRatio,
        child: picture != null
            ? Image(
                image: picture!,
                fit: BoxFit.cover,
                errorBuilder: (_, _, _) => _GiftPanel(items: items, tag: tag),
              )
            : _GiftPanel(items: items, tag: tag),
      ),
    );
    final bottom = Row(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Wrap(
                spacing: 8,
                crossAxisAlignment: WrapCrossAlignment.end,
                children: [
                  if (price != null)
                    Text(
                      price!,
                      key: priceKey,
                      style: TextStyle(
                        color: ink,
                        fontSize: 22,
                        height: 1.1,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  if (fullPrice != null)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 2),
                      child: Text(
                        fullPrice!,
                        style: TextStyle(
                          color: soft,
                          fontSize: 13,
                          decoration: TextDecoration.lineThrough,
                          decorationColor: soft,
                        ),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 4),
              Wrap(
                spacing: 8,
                runSpacing: 4,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  if (saving != null)
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 2,
                      ),
                      decoration: BoxDecoration(
                        color: const Color(0xFFE3F1D3),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Text(
                        saving!,
                        style: const TextStyle(
                          fontSize: 11.5,
                          fontWeight: FontWeight.w800,
                          color: Color(0xFF2F5D12),
                        ),
                      ),
                    ),
                  if (footnote != null)
                    Text(
                      footnote!,
                      style: TextStyle(color: soft, fontSize: 11.5),
                    ),
                ],
              ),
            ],
          ),
        ),
        if (action != null) ...[const SizedBox(width: 8), action!],
      ],
    );

    return Container(
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(18),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Color.lerp(colour, Colors.white, 0.08)!,
            colour,
            Color.lerp(colour, Colors.black, 0.28)!,
          ],
        ),
        boxShadow: [
          BoxShadow(
            color: colour.withValues(alpha: 0.28),
            blurRadius: 16,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: CustomPaint(
        painter: _FestiveBackground(ink: ink),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: LayoutBuilder(
            builder: (context, box) {
              // Wide (one or two in a row on a computer): words left,
              // picture right at its full height.
              if (box.maxWidth > box.maxHeight * 1.5) {
                // At most about half the tile, so the words keep room.
                final pictureWidth = math.min(
                  box.maxHeight * comboPictureRatio,
                  box.maxWidth * 0.5,
                );
                return Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          ?badgeChip,
                          const SizedBox(height: 8),
                          headlineText,
                          const SizedBox(height: 4),
                          titleText(2),
                          if (chipRow != null) ...[
                            const SizedBox(height: 10),
                            Flexible(child: ClipRect(child: chipRow)),
                          ],
                          const Spacer(),
                          bottom,
                        ],
                      ),
                    ),
                    const SizedBox(width: 16),
                    SizedBox(
                      width: pictureWidth,
                      child: Center(child: picturePanel),
                    ),
                  ],
                );
              }
              // Tall: the picture between the words and the price.
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(children: [?badgeChip, const Spacer()]),
                  const SizedBox(height: 6),
                  headlineText,
                  const SizedBox(height: 2),
                  titleText(1),
                  const SizedBox(height: 10),
                  Expanded(child: Center(child: picturePanel)),
                  const SizedBox(height: 10),
                  bottom,
                ],
              );
            },
          ),
        ),
      ),
    );
  }
}

/// The drawn gift on a light panel, when there is no picture.
class _GiftPanel extends StatelessWidget {
  const _GiftPanel({required this.items, required this.tag});

  final List<GiftItem> items;
  final String tag;

  @override
  Widget build(BuildContext context) => Container(
    color: Colors.white.withValues(alpha: 0.94),
    padding: const EdgeInsets.fromLTRB(8, 18, 8, 6),
    child: GiftPicture(items: items, tag: tag),
  );
}

/// A soft glow and a faint rangoli dot pattern, so a large tile is not
/// one flat colour.
class _FestiveBackground extends CustomPainter {
  const _FestiveBackground({required this.ink});

  final Color ink;

  @override
  void paint(Canvas canvas, Size size) {
    final glow = Offset(size.width * 0.12, size.height * 0.1);
    canvas.drawCircle(
      glow,
      size.shortestSide * 0.9,
      Paint()
        ..shader =
            RadialGradient(
              colors: [
                Colors.white.withValues(alpha: 0.16),
                Colors.white.withValues(alpha: 0),
              ],
            ).createShader(
              Rect.fromCircle(center: glow, radius: size.shortestSide * 0.9),
            ),
    );
    // Rangoli: small dots in a diamond grid, fading towards the right.
    const step = 22.0;
    final dot = Paint();
    for (double y = step / 2; y < size.height; y += step) {
      final row = (y / step).floor();
      for (
        double x = (row.isEven ? 0 : step / 2) + step / 2;
        x < size.width;
        x += step
      ) {
        final fade = 1 - (x / size.width);
        dot.color = ink.withValues(alpha: 0.07 * fade);
        canvas.drawCircle(Offset(x, y), 1.4, dot);
      }
    }
    // A thin gold line along the bottom, like a festive border.
    canvas.drawRect(
      Rect.fromLTWH(0, size.height - 4, size.width, 4),
      Paint()..color = const Color(0xFFF6C343).withValues(alpha: 0.9),
    );
  }

  @override
  bool shouldRepaint(_FestiveBackground old) => old.ink != ink;
}
