import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/widgets.dart';

/// The Talk Now search, drawn: a small galaxy instead of the hosts being
/// rung one after another. Three glowing ribbons (purple into lime), each a
/// mesh of fine strands, breathe and turn around a dark core; a spark runs
/// along the brightest one; motes orbit on faint rings.
///
/// One painter and one ticker: nothing rebuilds per frame, it only repaints
/// (at the screen's own rate: 120 Hz where the phone has it). Still when
/// animations are off (accessibility) or the screen is not shown.
class SearchGalaxy extends StatefulWidget {
  const SearchGalaxy({super.key, required this.size});

  final double size;

  @override
  State<SearchGalaxy> createState() => _SearchGalaxyState();
}

class _SearchGalaxyState extends State<SearchGalaxy>
    with SingleTickerProviderStateMixin {
  final _time = ValueNotifier<double>(0);
  late final Ticker _ticker;
  Duration _last = Duration.zero;
  double _base = 0;

  @override
  void initState() {
    super.initState();
    // Seconds since it started; carried over a pause (TickerMode), so the
    // motion picks up where it left off instead of jumping.
    _ticker = createTicker((elapsed) {
      _last = elapsed;
      _time.value = _base + elapsed.inMicroseconds / 1e6;
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final still = MediaQuery.disableAnimationsOf(context);
    if (still && _ticker.isActive) {
      _base += _last.inMicroseconds / 1e6;
      _ticker.stop();
    } else if (!still && !_ticker.isActive) {
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
  Widget build(BuildContext context) => IgnorePointer(
    child: RepaintBoundary(
      child: CustomPaint(
        key: const ValueKey('search-galaxy'),
        size: Size.square(widget.size),
        painter: _GalaxyPainter(_time),
      ),
    ),
  );
}

/// Colours: the brand's purple, a lighter violet, lime, and a white-violet
/// for the brightest light.
const _deep = Color(0xFF561DE2);
const _violet = Color(0xFF8B5CF6);
const _lime = Color(0xFFA8EC4A);
const _glow = Color(0xFFE9D5FF);

/// The colour wheels a ribbon turns through (stops below).
const _purpleWheel = [_violet, _deep, _lime, _lime, _violet, _deep, _violet];
const _limeWheel = [_lime, _violet, _lime, _lime, _deep, _lime, _lime];

/// One ribbon: how many lobes, how far they swing, how fast it all moves.
class _Ribbon {
  const _Ribbon({
    required this.lobes,
    required this.swing,
    required this.speed,
    required this.turn,
    required this.phase,
    required this.width,
    required this.hue,
    this.scale = 1,
    this.limeLed = false,
  });

  final int lobes;
  final double swing;
  final double speed;
  final double turn;
  final double phase;
  final double width;

  /// Where on the purple→lime wheel it starts.
  final double hue;

  /// Its size against the core: the ribbons sit apart, not on one line.
  final double scale;

  /// Mostly lime (one ribbon is, as in the brand's look), else purple.
  final bool limeLed;
}

const _ribbons = [
  _Ribbon(
    lobes: 5,
    swing: 0.13,
    speed: 0.55,
    turn: 0.10,
    phase: 0,
    width: 0.30,
    hue: 0,
  ),
  _Ribbon(
    lobes: 4,
    swing: 0.12,
    speed: -0.45,
    turn: -0.07,
    phase: 1.9,
    width: 0.24,
    hue: 0.4,
    scale: 0.93,
    limeLed: true,
  ),
  _Ribbon(
    lobes: 6,
    swing: 0.08,
    speed: 0.35,
    turn: 0.05,
    phase: 3.7,
    width: 0.16,
    hue: 0.75,
    scale: 1.07,
  ),
];

/// Motes: orbit radius (× core), speed (rad/s), start angle, size, lime?
const _motes = [
  (1.42, 0.30, 0.4, 3.6, false),
  (1.58, -0.22, 2.1, 3.0, true),
  (1.30, 0.42, 3.3, 2.6, false),
  (1.66, 0.18, 4.6, 3.4, false),
  (1.50, -0.35, 5.5, 2.6, true),
  (1.22, 0.26, 1.2, 2.2, false),
  (1.74, -0.15, 2.9, 2.8, false),
];

class _GalaxyPainter extends CustomPainter {
  _GalaxyPainter(this.time) : super(repaint: time);

  final ValueListenable<double> time;

  /// Points around each ribbon, and fine strands across it.
  static const _steps = 160;
  static const _strands = 12;

  @override
  void paint(Canvas canvas, Size size) {
    final t = time.value;
    final c = size.center(Offset.zero);
    final core = size.shortestSide * 0.30;

    // The halo behind it all.
    canvas.drawCircle(
      c,
      size.shortestSide * 0.5,
      Paint()
        ..shader = ui.Gradient.radial(
          c,
          size.shortestSide * 0.5,
          [
            _deep.withValues(alpha: 0.30),
            _deep.withValues(alpha: 0.08),
            _deep.withValues(alpha: 0),
          ],
          [0, 0.55, 1],
        ),
    );

    // Faint orbits.
    final orbit = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 0.7
      ..color = _violet.withValues(alpha: 0.10);
    for (final r in const [1.22, 1.46, 1.70]) {
      canvas.drawCircle(c, core * r, orbit);
    }

    // The ribbons, with their glow underneath, added light on light.
    final wheel = t * 0.25;
    for (var i = 0; i < _ribbons.length; i++) {
      final rb = _ribbons[i];
      final (strands, spine) = _ribbonPaths(rb, c, core, t);
      final turn = Matrix4.rotationZ((wheel + rb.hue) * math.pi * 2).storage;
      // The purple→lime wheel at [alpha] (baked into the colours: a paint's
      // own opacity is not applied to a shader on every renderer).
      Shader wheelAt(double alpha) => ui.Gradient.sweep(
        c,
        [
          for (final col in rb.limeLed ? _limeWheel : _purpleWheel)
            col.withValues(alpha: alpha),
        ],
        const [0, 0.2, 0.36, 0.46, 0.64, 0.84, 1],
        TileMode.clamp,
        0,
        math.pi * 2,
        turn,
      );
      // Glow: the spine, wide and blurred.
      canvas.drawPath(
        spine,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = core * rb.width * 0.9
          ..shader = wheelAt(0.28)
          ..blendMode = BlendMode.plus
          ..maskFilter = MaskFilter.blur(BlurStyle.normal, core * 0.09),
      );
      // The mesh: fine strands.
      canvas.drawPath(
        strands,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 0.8
          ..shader = wheelAt(0.38)
          ..blendMode = BlendMode.plus,
      );
      // A bright edge along the spine.
      canvas.drawPath(
        spine,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.4
          ..shader = wheelAt(0.6)
          ..blendMode = BlendMode.plus,
      );
    }

    // The dark core.
    canvas.drawCircle(
      c,
      core * 0.86,
      Paint()
        ..shader = ui.Gradient.radial(
          c,
          core * 0.86,
          [
            const Color(0xE6070512),
            const Color(0x99070512),
            const Color(0x00070512),
          ],
          [0, 0.7, 1],
        ),
    );

    // A spark running along the first ribbon.
    final sparkAngle = t * 0.9;
    final sparkR = _radius(_ribbons.first, sparkAngle, core, t);
    final spark =
        c + Offset(math.cos(sparkAngle), math.sin(sparkAngle)) * sparkR;
    canvas.drawCircle(
      spark,
      core * 0.16,
      Paint()
        ..color = _glow.withValues(alpha: 0.55)
        ..blendMode = BlendMode.plus
        ..maskFilter = MaskFilter.blur(BlurStyle.normal, core * 0.12),
    );
    canvas.drawCircle(spark, 2.6, Paint()..color = const Color(0xFFFFFFFF));

    // Motes on their orbits, each with a little glow.
    for (final (r, speed, start, dot, lime) in _motes) {
      final a = start + t * speed;
      final p = c + Offset(math.cos(a), math.sin(a)) * core * r;
      final color = lime ? _lime : _violet;
      final twinkle = 0.65 + 0.35 * math.sin(t * 2.2 + start * 3);
      canvas.drawCircle(
        p,
        dot * 3,
        Paint()
          ..color = color.withValues(alpha: 0.35 * twinkle)
          ..maskFilter = MaskFilter.blur(BlurStyle.normal, dot * 2),
      );
      canvas.drawCircle(
        p,
        dot,
        Paint()..color = color.withValues(alpha: 0.95 * twinkle),
      );
    }
  }

  /// The ribbon's radius at [angle]: a few slow lobes that swing and turn.
  static double _radius(_Ribbon rb, double angle, double core, double t) {
    final a = angle - t * rb.turn;
    final wave =
        rb.swing * math.sin(rb.lobes * a + rb.phase + t * rb.speed) +
        rb.swing *
            0.45 *
            math.sin((rb.lobes + 1) * a - rb.phase - t * rb.speed * 1.3);
    return core * (rb.scale + wave);
  }

  /// The strands (one sub-path each) and the spine of one ribbon. The
  /// strands spread across its width and twist, which gives the mesh.
  static (Path, Path) _ribbonPaths(
    _Ribbon rb,
    Offset c,
    double core,
    double t,
  ) {
    final strands = Path();
    final spine = Path();
    final half = core * rb.width / 2;
    final radii = List<double>.filled(_steps + 1, 0);
    final twist = List<double>.filled(_steps + 1, 0);
    final cosA = List<double>.filled(_steps + 1, 0);
    final sinA = List<double>.filled(_steps + 1, 0);
    for (var k = 0; k <= _steps; k++) {
      final a = k / _steps * math.pi * 2;
      radii[k] = _radius(rb, a, core, t);
      twist[k] = math.cos(a * 2 + t * rb.speed * 1.7 + rb.phase);
      cosA[k] = math.cos(a);
      sinA[k] = math.sin(a);
    }
    for (var s = 0; s < _strands; s++) {
      final across = (s / (_strands - 1)) * 2 - 1; // -1 … 1
      for (var k = 0; k <= _steps; k++) {
        final r = radii[k] + across * half * twist[k];
        final x = c.dx + cosA[k] * r;
        final y = c.dy + sinA[k] * r;
        if (k == 0) {
          strands.moveTo(x, y);
        } else {
          strands.lineTo(x, y);
        }
      }
    }
    for (var k = 0; k <= _steps; k++) {
      final x = c.dx + cosA[k] * radii[k];
      final y = c.dy + sinA[k] * radii[k];
      if (k == 0) {
        spine.moveTo(x, y);
      } else {
        spine.lineTo(x, y);
      }
    }
    return (strands, spine);
  }

  @override
  bool shouldRepaint(_GalaxyPainter old) => old.time != time;
}
