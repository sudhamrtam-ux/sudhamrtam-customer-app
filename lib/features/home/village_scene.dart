import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../core/running_tests.dart';

/// A village morning behind the Home banner (owner request 2026-11-26):
/// the sun rises over green hills with jungle trees and huts, cows walk
/// along the earth path and a bullock cart follows, birds drift by.
/// Drawn in code (no image files). Still when the phone asks for less
/// motion, and in tests.
class VillageScene extends StatefulWidget {
  const VillageScene({super.key, this.animate});

  /// Null: animate except in tests.
  final bool? animate;

  @override
  State<VillageScene> createState() => _VillageSceneState();
}

class _VillageSceneState extends State<VillageScene>
    with TickerProviderStateMixin {
  /// Seconds of walking; long, so the wrap-around is rarely seen.
  static const _loop = 600;

  late final AnimationController _clock = AnimationController(
    vsync: this,
    duration: const Duration(seconds: _loop),
  );

  /// The sun rising once when the page opens.
  late final AnimationController _rise = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 3800),
  );

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final on =
        (widget.animate ?? !runningTests) &&
        !MediaQuery.disableAnimationsOf(context);
    if (on) {
      if (!_clock.isAnimating) _clock.repeat();
      if (_rise.value == 0 && !_rise.isAnimating) _rise.forward();
    } else {
      _clock.stop();
      _clock.value = 0.004; // Cows a little way in.
      _rise.value = 1;
    }
  }

  @override
  void dispose() {
    _clock.dispose();
    _rise.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => RepaintBoundary(
    child: CustomPaint(
      painter: _ScenePainter(clock: _clock, rise: _rise, loop: _loop),
      size: Size.infinite,
    ),
  );
}

class _ScenePainter extends CustomPainter {
  _ScenePainter({required this.clock, required this.rise, required this.loop})
    : super(repaint: Listenable.merge([clock, rise]));

  final Animation<double> clock;
  final Animation<double> rise;
  final int loop;

  // Village and jungle colours.
  static const _skyTop = Color(0xFF2F5A1E);
  static const _skyMid = Color(0xFF6E9440);
  static const _dawn = Color(0xFFF4C57A);
  static const _sun = Color(0xFFFFB13B);
  static const _farHill = Color(0xFF7FAA48);
  static const _midHill = Color(0xFF5F9131);
  static const _ground = Color(0xFF4A7A22);
  static const _path = Color(0xFFC9A46C);
  static const _jungle = Color(0xFF2F5E1A);
  static const _trunk = Color(0xFF6B4423);

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;
    final s = h / 120; // Everything scales with the banner's height.
    final t = clock.value * loop; // Seconds.

    // Dawn sky: deep green at the top (white text stays readable),
    // warm near the horizon.
    canvas.drawRect(
      Offset.zero & size,
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [_skyTop, _skyMid, _dawn],
          stops: [0, 0.45, 0.78],
        ).createShader(Offset.zero & size),
    );

    // The rising sun with its glow.
    final up = Curves.easeOutCubic.transform(rise.value);
    final sun = Offset(w * 0.62, h * (0.92 - 0.5 * up));
    canvas.drawCircle(
      sun,
      34 * s,
      Paint()
        ..shader = RadialGradient(
          colors: [_sun.withValues(alpha: 0.55), _sun.withValues(alpha: 0)],
        ).createShader(Rect.fromCircle(center: sun, radius: 34 * s)),
    );
    final rays = Paint()
      ..color = _sun.withValues(alpha: 0.35 * up)
      ..strokeWidth = 1.6 * s
      ..strokeCap = StrokeCap.round;
    final turn = t * 0.08;
    for (var i = 0; i < 12; i++) {
      final a = turn + i * math.pi / 6;
      canvas.drawLine(
        sun + Offset(math.cos(a), math.sin(a)) * 16 * s,
        sun + Offset(math.cos(a), math.sin(a)) * 23 * s,
        rays,
      );
    }
    canvas.drawCircle(sun, 12 * s, Paint()..color = _sun);

    // Birds drifting over.
    final bird = Paint()
      ..color = const Color(0xFF24401A).withValues(alpha: 0.7)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.3 * s
      ..strokeCap = StrokeCap.round;
    for (var i = 0; i < 3; i++) {
      final x = (w * 0.35 + 11 * s * t + i * 22 * s) % (w + 40 * s) - 20 * s;
      final y = h * 0.30 + i * 5 * s + math.sin(t * 1.5 + i) * 2 * s;
      final flap = math.sin(t * 7 + i * 1.7) * 2.2 * s;
      canvas.drawPath(
        Path()
          ..moveTo(x - 4 * s, y - flap)
          ..quadraticBezierTo(x - 2 * s, y - 1.5 * s, x, y)
          ..quadraticBezierTo(x + 2 * s, y - 1.5 * s, x + 4 * s, y - flap),
        bird,
      );
    }

    // Far hills, with jungle trees and huts on them.
    double farY(double x) =>
        h * 0.64 + math.sin(x / w * math.pi * 2.6 + 0.4) * h * 0.045;
    canvas.drawPath(_hill(w, h, farY), Paint()..color = _farHill);
    for (final (f, palm) in const [
      (0.03, false),
      (0.11, true),
      (0.19, false),
      (0.27, false),
      (0.40, true),
      (0.50, false),
      (0.74, false),
      (0.93, true),
      (0.98, false),
    ]) {
      final x = w * f;
      palm
          ? _palm(canvas, Offset(x, farY(x) + 2 * s), s)
          : _roundTree(canvas, Offset(x, farY(x) + 2 * s), s);
    }
    for (final f in const [0.81, 0.86]) {
      final x = w * f;
      _hut(canvas, Offset(x, farY(x) + 3 * s), s);
    }

    // Nearer hill and the ground.
    double midY(double x) =>
        h * 0.76 + math.sin(x / w * math.pi * 1.6 + 1.2) * h * 0.03;
    canvas.drawPath(_hill(w, h, midY), Paint()..color = _midHill);
    canvas.drawRect(
      Rect.fromLTRB(0, h * 0.84, w, h),
      Paint()..color = _ground,
    );
    // The earth path the animals walk on.
    canvas.drawRect(
      Rect.fromLTRB(0, h * 0.87, w, h * 0.95),
      Paint()..color = _path,
    );
    final ruts = Paint()
      ..color = const Color(0xFFB08A55)
      ..strokeWidth = 1 * s;
    canvas.drawLine(Offset(0, h * 0.905), Offset(w, h * 0.905), ruts);
    canvas.drawLine(Offset(0, h * 0.935), Offset(w, h * 0.935), ruts);

    // Cows walking, then the bullock cart further back.
    final groundY = h * 0.94;
    final a = s * 1.3; // Animals a little larger than the scenery.
    final span = w + 160 * a;
    const cows = [
      (0.0, Color(0xFFFFFFFF), true),
      (34.0, Color(0xFF9A6A43), false),
      (62.0, Color(0xFFF2E8DA), true),
    ];
    for (final (gap, colour, patches) in cows) {
      final x = (w * 0.15 + 13 * a * t - gap * a) % span - 60 * a;
      _cow(canvas, Offset(x, groundY), a, t * 5 + gap, colour, patches);
    }
    final cartX = (w * 0.15 + 8 * a * t - w * 0.55) % span - 80 * a;
    _bullockCart(canvas, Offset(cartX, groundY), a, t, 8 * a * t);
  }

  Path _hill(double w, double h, double Function(double) y) {
    final path = Path()..moveTo(0, h);
    for (double x = 0; x <= w; x += 4) {
      path.lineTo(x, y(x));
    }
    return path
      ..lineTo(w, y(w))
      ..lineTo(w, h)
      ..close();
  }

  void _roundTree(Canvas canvas, Offset base, double s) {
    canvas.drawRect(
      Rect.fromLTWH(base.dx - 1.2 * s, base.dy - 9 * s, 2.4 * s, 9 * s),
      Paint()..color = _trunk,
    );
    final leaf = Paint()..color = _jungle;
    canvas.drawCircle(base + Offset(0, -13 * s), 6.5 * s, leaf);
    canvas.drawCircle(base + Offset(-4 * s, -10 * s), 4.5 * s, leaf);
    canvas.drawCircle(base + Offset(4 * s, -10 * s), 4.5 * s, leaf);
  }

  void _palm(Canvas canvas, Offset base, double s) {
    final top = base + Offset(2 * s, -20 * s);
    canvas.drawPath(
      Path()
        ..moveTo(base.dx - 1.2 * s, base.dy)
        ..quadraticBezierTo(base.dx, base.dy - 10 * s, top.dx - 1 * s, top.dy)
        ..lineTo(top.dx + 1 * s, top.dy)
        ..quadraticBezierTo(base.dx + 2 * s, base.dy - 10 * s, base.dx + 1.2 * s, base.dy)
        ..close(),
      Paint()..color = _trunk,
    );
    final frond = Paint()
      ..color = _jungle
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.2 * s
      ..strokeCap = StrokeCap.round;
    for (final (dx, dy) in const [(-9.0, 3.0), (9.0, 3.0), (-6.0, -4.0), (6.0, -4.0), (0.0, -6.0)]) {
      canvas.drawPath(
        Path()
          ..moveTo(top.dx, top.dy)
          ..quadraticBezierTo(
            top.dx + dx * 0.6 * s,
            top.dy + (dy - 4) * s,
            top.dx + dx * s,
            top.dy + dy * s,
          ),
        frond,
      );
    }
  }

  void _hut(Canvas canvas, Offset base, double s) {
    canvas.drawRect(
      Rect.fromLTWH(base.dx - 6 * s, base.dy - 8 * s, 12 * s, 8 * s),
      Paint()..color = const Color(0xFFE2C29A),
    );
    canvas.drawRect(
      Rect.fromLTWH(base.dx - 1.5 * s, base.dy - 5 * s, 3 * s, 5 * s),
      Paint()..color = const Color(0xFF6B4423),
    );
    canvas.drawPath(
      Path()
        ..moveTo(base.dx - 8.5 * s, base.dy - 7.5 * s)
        ..lineTo(base.dx, base.dy - 15 * s)
        ..lineTo(base.dx + 8.5 * s, base.dy - 7.5 * s)
        ..close(),
      Paint()..color = const Color(0xFF9A6A2F),
    );
  }

  /// A cow facing right, its feet at [foot]; [phase] moves the legs.
  void _cow(
    Canvas canvas,
    Offset foot,
    double s,
    double phase,
    Color colour,
    bool patches,
  ) {
    canvas.save();
    canvas.translate(foot.dx, foot.dy);
    canvas.scale(s);
    final body = Paint()..color = colour;
    final dark = Paint()..color = const Color(0xFF3A2A1E);
    final legs = Paint()
      ..color = const Color(0xFF5A4330)
      ..strokeWidth = 2
      ..strokeCap = StrokeCap.round;
    final swing = math.sin(phase) * 2.2;
    // Legs, front and back pairs out of step.
    for (final (x, sign) in const [(-8.0, 1.0), (-5.0, -1.0), (6.0, -1.0), (9.0, 1.0)]) {
      canvas.drawLine(Offset(x, -6), Offset(x + swing * sign, 0), legs);
    }
    // Tail.
    canvas.drawPath(
      Path()
        ..moveTo(-11, -12)
        ..quadraticBezierTo(-14, -9 + swing * 0.4, -13, -5),
      Paint()
        ..color = const Color(0xFF5A4330)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.2,
    );
    canvas.drawRRect(
      RRect.fromLTRBR(-12, -15, 12, -5, const Radius.circular(5)),
      body,
    );
    if (patches) {
      canvas.drawOval(const Rect.fromLTWH(-7, -14, 7, 5), dark);
      canvas.drawOval(const Rect.fromLTWH(3, -11, 5, 4), dark);
    }
    // Head, nodding a little as it walks.
    final nod = math.sin(phase * 0.5) * 0.8;
    canvas.drawRRect(
      RRect.fromLTRBR(10, -18 + nod, 18, -10 + nod, const Radius.circular(3)),
      body,
    );
    canvas.drawRRect(
      RRect.fromLTRBR(15, -13.5 + nod, 19, -10 + nod, const Radius.circular(2)),
      Paint()..color = const Color(0xFFE7B9A0),
    );
    final horn = Paint()
      ..color = const Color(0xFFF3E6C8)
      ..strokeWidth = 1.3
      ..strokeCap = StrokeCap.round;
    canvas.drawLine(Offset(12, -18 + nod), Offset(11, -21 + nod), horn);
    canvas.drawLine(Offset(15, -18 + nod), Offset(16, -21 + nod), horn);
    canvas.drawCircle(Offset(15.5, -15.5 + nod), 0.9, dark);
    canvas.restore();
  }

  /// Two bullocks pulling a cart with a farmer, facing right.
  void _bullockCart(Canvas canvas, Offset foot, double s, double t, double moved) {
    // Cart behind the bullocks.
    canvas.save();
    canvas.translate(foot.dx, foot.dy);
    canvas.scale(s);
    final wood = Paint()..color = const Color(0xFF8B5A2B);
    // Yoke pole.
    canvas.drawLine(
      const Offset(-6, -10),
      const Offset(22, -13),
      Paint()
        ..color = const Color(0xFF6B4423)
        ..strokeWidth = 1.6,
    );
    // Cart bed and sides.
    canvas.drawRect(const Rect.fromLTRB(-30, -16, -4, -9), wood);
    canvas.drawRect(
      const Rect.fromLTRB(-30, -20, -4, -16),
      Paint()..color = const Color(0xFFA9743E),
    );
    // Farmer with a saffron turban.
    canvas.drawRect(
      const Rect.fromLTRB(-14, -28, -9, -20),
      Paint()..color = const Color(0xFFF5F0E6),
    );
    canvas.drawCircle(const Offset(-11.5, -30), 2.6, Paint()..color = const Color(0xFF8D5B3A));
    canvas.drawOval(
      const Rect.fromLTRB(-14.5, -34, -8.5, -30.5),
      Paint()..color = const Color(0xFFF28C28),
    );
    // Wheel with turning spokes.
    const hub = Offset(-17, -7);
    const r = 7.0;
    canvas.drawCircle(
      hub,
      r,
      Paint()
        ..color = const Color(0xFF5A3A1E)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.8,
    );
    final spokes = Paint()
      ..color = const Color(0xFF5A3A1E)
      ..strokeWidth = 1;
    final angle = moved / s / r;
    for (var i = 0; i < 6; i++) {
      final a = angle + i * math.pi / 3;
      canvas.drawLine(hub, hub + Offset(math.cos(a), math.sin(a)) * r, spokes);
    }
    canvas.restore();

    // The two bullocks, one a little behind the other.
    _cow(canvas, foot + Offset(26 * s, -1.5 * s), s * 0.95, t * 4 + 1, const Color(0xFFD8CBB8), false);
    _cow(canvas, foot + Offset(22 * s, 0), s, t * 4, const Color(0xFFEDE4D6), false);
  }

  @override
  bool shouldRepaint(_ScenePainter old) => false;
}
