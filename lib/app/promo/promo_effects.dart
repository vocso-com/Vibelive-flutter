import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

import '../api/promo_banner/promo_content.dart';

/// The admin's effect, animated over a banner on a loop: sparkle, rising
/// stars or hearts, falling confetti, a gift whose lid pops open with a
/// burst, or a light sweeping across. Drawn, not images: nothing to download
/// and crisp at any size. The admin preview (BannerPreview.jsx) plays the
/// same six.
///
/// Decoration only: it never takes a tap, and a phone set to reduce motion
/// gets one still frame.
class PromoEffectLayer extends StatefulWidget {
  const PromoEffectLayer({
    super.key,
    required this.effect,
    required this.color,
  });

  final PromoEffect effect;
  final Color color;

  @override
  State<PromoEffectLayer> createState() => _PromoEffectLayerState();
}

class _PromoEffectLayerState extends State<PromoEffectLayer>
    with SingleTickerProviderStateMixin {
  /// Seconds since the layer appeared: one ever-growing clock, so no
  /// particle jumps when a loop starts over.
  final _time = ValueNotifier<double>(_stillAt);
  late final Ticker _ticker = createTicker(
    (elapsed) => _time.value = elapsed.inMicroseconds / 1e6,
  );

  /// The frame shown when the phone asks for less motion.
  static const _stillAt = 1.76;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (MediaQuery.disableAnimationsOf(context)) {
      if (_ticker.isActive) _ticker.stop();
      _time.value = _stillAt;
    } else if (!_ticker.isActive) {
      _ticker.start();
    }
  }

  @override
  void dispose() {
    _ticker.dispose();
    _time.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (widget.effect == PromoEffect.none) return const SizedBox.shrink();
    return IgnorePointer(
      child: RepaintBoundary(
        child: CustomPaint(
          size: Size.infinite,
          painter: PromoEffectPainter(
            effect: widget.effect,
            color: widget.color,
            time: _time,
          ),
        ),
      ),
    );
  }
}

/// Paints one frame of an effect at [time] (seconds). Particles fade in and
/// out on sine ramps and towards the banner's edges, so nothing is chopped
/// off at the border.
class PromoEffectPainter extends CustomPainter {
  PromoEffectPainter({
    required this.effect,
    required this.color,
    required this.time,
  }) : super(repaint: time);

  final PromoEffect effect;
  final Color color;
  final ValueListenable<double> time;

  /// One loop of the slow effects (shine, gift), in seconds.
  static const period = 3.2;

  static const _confetti = [
    Color(0xFFFF4D6D),
    Color(0xFF4DABF7),
    Color(0xFF69DB7C),
    Color(0xFFFFD43B),
    Color(0xFFB197FC),
  ];

  /// Fixed positions (0–1), the same each frame, spread over the banner.
  static Offset _spot(int i) => Offset(
    (((i * 37 + 11) % 92) + 4) / 100,
    (((i * 53 + 17) % 80) + 8) / 100,
  );

  /// 0 at the banner's edge, 1 a little inside it (smooth).
  static double edge(Offset at, Size size) {
    double ramp(double d, double m) {
      if (m <= 0) return 1;
      final x = (d / m).clamp(0.0, 1.0);
      return x * x * (3 - 2 * x);
    }

    final mx = size.width * 0.08;
    final my = size.height * 0.14;
    return ramp(at.dx, mx) *
        ramp(size.width - at.dx, mx) *
        ramp(at.dy, my) *
        ramp(size.height - at.dy, my);
  }

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty) return;
    // Loop phase for the slow effects; the particle effects use the
    // seconds directly (each at its own pace, never reset).
    final t = (time.value / period) % 1;
    switch (effect) {
      case PromoEffect.none:
        return;
      case PromoEffect.sparkle:
        _sparkle(canvas, size, time.value);
      case PromoEffect.stars:
        _rising(canvas, size, time.value, _starPath);
      case PromoEffect.hearts:
        _rising(canvas, size, time.value, _heartPath);
      case PromoEffect.confetti:
        _confettiFall(canvas, size, time.value);
      case PromoEffect.shine:
        _shine(canvas, size, t);
      case PromoEffect.gift:
        _gift(canvas, size, t);
    }
  }

  Paint _fill(Color c, double opacity) =>
      Paint()..color = c.withValues(alpha: opacity.clamp(0.0, 1.0));

  void _sparkle(Canvas canvas, Size size, double seconds) {
    for (var i = 0; i < 12; i++) {
      final p = (seconds / 1.6 + i * 0.137) % 1;
      final at = Offset(_spot(i).dx * size.width, _spot(i).dy * size.height);
      final s = math.sin(p * math.pi);
      final alpha = s * s * edge(at, size);
      final r = (3.5 + (i % 3) * 2.5) * (0.4 + 0.6 * s);
      final glow = _fill(color, alpha * 0.5)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 3);
      canvas.drawCircle(at, r * 0.8, glow);
      canvas.drawPath(_twinklePath(at, r, p * math.pi), _fill(color, alpha));
    }
  }

  /// Stars or hearts drifting up from the bottom, swaying, fading out.
  void _rising(
    Canvas canvas,
    Size size,
    double seconds,
    Path Function(Offset c, double r) shape,
  ) {
    for (var i = 0; i < 10; i++) {
      final speed = 1 + (i % 3) * 0.18;
      final p = (seconds / period * speed + i * 0.1) % 1;
      final r = 4.0 + (i % 3) * 2;
      final x = _spot(i).dx * size.width + math.sin(p * math.pi * 2 + i) * 8;
      final y = size.height * (0.98 - p * 0.96);
      final at = Offset(x, y);
      final alpha = math.sin(p * math.pi) * edge(at, size);
      canvas.drawPath(shape(at, r), _fill(color, alpha * 0.95));
    }
  }

  void _confettiFall(Canvas canvas, Size size, double seconds) {
    for (var i = 0; i < 18; i++) {
      final speed = 1 + (i % 3) * 0.35;
      final p = (seconds / period * speed + i * 0.071) % 1;
      final x =
          (((i * 29 + 5) % 96) / 100) * size.width +
          math.sin(p * math.pi * 4 + i) * 6;
      final y = p * size.height;
      final c = i % 3 == 0 ? color : _confetti[i % _confetti.length];
      final alpha = 0.95 * edge(Offset(x, y), size);
      if (alpha <= 0.01) continue;
      canvas
        ..save()
        ..translate(x, y)
        ..rotate(p * math.pi * 2 * (1 + i % 3))
        ..drawRRect(
          RRect.fromRectAndRadius(
            const Rect.fromLTWH(-2.5, -4.5, 5, 9),
            const Radius.circular(1),
          ),
          _fill(c, alpha),
        )
        ..restore();
    }
  }

  /// A soft, wide light band gliding across, then a rest.
  void _shine(Canvas canvas, Size size, double t) {
    const sweep = 0.45;
    if (t >= sweep) return;
    final phase = Curves.easeInOutCubic.transform(t / sweep);
    final band = size.width * 0.4;
    final x = -band + phase * (size.width + band * 2);
    final rect = Rect.fromLTWH(
      x - band / 2,
      -size.height,
      band,
      size.height * 3,
    );
    // Brightest mid-sweep: it comes in and leaves softly.
    final peak = 0.35 * math.sin(phase * math.pi);
    final paint = Paint()
      ..shader = LinearGradient(
        colors: [
          Colors.white.withValues(alpha: 0),
          Colors.white.withValues(alpha: peak * 0.45),
          Colors.white.withValues(alpha: peak),
          Colors.white.withValues(alpha: peak * 0.45),
          Colors.white.withValues(alpha: 0),
        ],
        stops: const [0, 0.3, 0.5, 0.7, 1],
      ).createShader(rect);
    canvas
      ..save()
      ..translate(x, size.height / 2)
      ..transform(Matrix4.skewX(-0.35).storage)
      ..translate(-x, -size.height / 2)
      ..drawRect(rect, paint)
      ..restore();
  }

  /// A gift box in the corner: the lid pops up and tilts, a burst of
  /// sparkles flies out, the lid settles back. Every loop.
  void _gift(Canvas canvas, Size size, double t) {
    final s = (size.height * 0.34).clamp(26.0, 46.0);
    final base = Offset(size.width - s * 0.9 - 10, size.height - 10);
    double ease(double a, double b) =>
        Curves.easeOut.transform(((t - a) / (b - a)).clamp(0.0, 1.0));
    final open = t < 0.75 ? ease(0.28, 0.42) : 1 - ease(0.75, 0.9);

    // Burst, while the lid is up.
    if (t > 0.36 && t < 0.82) {
      final p = (t - 0.36) / 0.46;
      final alpha = math.sin(p * math.pi);
      final from = base + Offset(s * 0.45, -s * 0.75);
      for (var i = 0; i < 7; i++) {
        final angle = -math.pi / 2 + (i - 3) * 0.42;
        final d = s * (0.4 + 1.1 * p);
        final at = from + Offset(math.cos(angle) * d, math.sin(angle) * d);
        canvas.drawPath(
          _twinklePath(at, 3.5 + (i % 2) * 2, p * 3),
          _fill(color, alpha),
        );
      }
    }

    final box = _fill(color, 1);
    final ribbon = _fill(Colors.white, 0.9);
    final body = Rect.fromLTWH(
      base.dx + s * 0.08,
      base.dy - s * 0.62,
      s * 0.84,
      s * 0.62,
    );
    canvas
      ..drawRRect(RRect.fromRectAndRadius(body, const Radius.circular(3)), box)
      ..drawRect(
        Rect.fromCenter(
          center: body.center,
          width: s * 0.13,
          height: body.height,
        ),
        ribbon,
      );

    // The lid, hinged on its left edge.
    final lid = Rect.fromLTWH(base.dx, body.top - s * 0.22, s, s * 0.24);
    canvas
      ..save()
      ..translate(lid.left, lid.bottom - open * s * 0.35)
      ..rotate(-0.45 * open)
      ..translate(-lid.left, -lid.bottom)
      ..drawRRect(
        RRect.fromRectAndRadius(lid, const Radius.circular(3)),
        _fill(Color.lerp(color, Colors.white, 0.18)!, 1),
      )
      ..drawRect(
        Rect.fromCenter(
          center: lid.center,
          width: s * 0.13,
          height: lid.height,
        ),
        ribbon,
      )
      ..restore();
  }

  /// A four-point twinkle, turned by [spin].
  static Path _twinklePath(Offset c, double r, double spin) {
    final path = Path();
    for (var k = 0; k < 8; k++) {
      final a = spin + k * math.pi / 4;
      final d = k.isEven ? r : r * 0.28;
      final p = c + Offset(math.cos(a) * d, math.sin(a) * d);
      k == 0 ? path.moveTo(p.dx, p.dy) : path.lineTo(p.dx, p.dy);
    }
    return path..close();
  }

  static Path _starPath(Offset c, double r) {
    final path = Path();
    for (var k = 0; k < 10; k++) {
      final a = -math.pi / 2 + k * math.pi / 5;
      final d = k.isEven ? r : r * 0.45;
      final p = c + Offset(math.cos(a) * d, math.sin(a) * d);
      k == 0 ? path.moveTo(p.dx, p.dy) : path.lineTo(p.dx, p.dy);
    }
    return path..close();
  }

  static Path _heartPath(Offset c, double r) {
    final w = r * 2.1;
    final top = c.dy - r * 0.55;
    return Path()
      ..moveTo(c.dx, c.dy + r)
      ..cubicTo(c.dx - w, c.dy, c.dx - w * 0.55, top - r, c.dx, top)
      ..cubicTo(c.dx + w * 0.55, top - r, c.dx + w, c.dy, c.dx, c.dy + r)
      ..close();
  }

  @override
  bool shouldRepaint(PromoEffectPainter old) =>
      old.effect != effect || old.color != color || old.time != time;
}
