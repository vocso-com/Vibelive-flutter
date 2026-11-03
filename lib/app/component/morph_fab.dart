import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' show lerpDouble;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';

/// A floating action that springs in as a full-width rounded pill, holds for
/// [holdFor], then folds into a round button at the trailing edge, which
/// "rings" every few seconds (the icon wiggles, rings ripple out).
///
/// One tap on the circle does [onTap] (no "open first, tap again"); a long
/// press opens the pill again, and it folds back after [holdFor]. Without
/// [onTap] a tap opens the pill. [foldWhen] turning true folds it early (the
/// feed scrolling, say). With
/// [introOnce], only the first appearance per app launch unfolds: later
/// ones arrive as the circle.
///
/// CHEAP BY DESIGN
/// ---------------
/// The pill's content is laid out once, at the open width, and never
/// reflows while folding: it is clipped and faded, so a frame only changes
/// the box's size and corners. The ring (ripples and wiggle) is its own
/// layer, painted, not rebuilt, and plays in short bursts while folded, not
/// for ever. Hidden tabs (TickerMode) pause it all, and "reduce motion"
/// makes every change instant and nothing ring.
class MorphFab extends StatefulWidget {
  const MorphFab({
    super.key,
    required this.pill,
    required this.icon,
    required this.colors,
    this.iconColor = Colors.white,
    this.semanticLabel,
    this.pillHeight = 64,
    this.pillRadius = 20,
    this.circleSize = 56,
    this.holdFor = const Duration(seconds: 3),
    this.introOnce,
    this.foldWhen,
    this.onTap,
    this.badge,
    this.onUnfold,
  });

  /// What the open pill shows (its own taps included).
  final Widget pill;

  /// The folded circle's icon.
  final IconData icon;

  /// One tap on the folded circle. Null: the tap opens the pill.
  final VoidCallback? onTap;

  /// A small chip on the folded circle's bottom edge (a price, say).
  final String? badge;

  /// The background gradient, start to end (one colour: flat). The first
  /// colour also tints the glow and the rings.
  final List<Color> colors;
  final Color iconColor;

  /// What the folded circle says to a screen reader.
  final String? semanticLabel;

  final double pillHeight;
  final double pillRadius;
  final double circleSize;

  /// How long the pill stays open before folding.
  final Duration holdFor;

  /// The intro (arrive open, then fold) plays once per app launch for this
  /// key; later appearances arrive folded. Null: every appearance.
  final String? introOnce;

  /// Folds the pill early when this turns true.
  final ValueListenable<bool>? foldWhen;

  /// The circle was opened back into the pill (a long press, or a tap when
  /// there is no [onTap]).
  final VoidCallback? onUnfold;

  static final Set<String> _introduced = {};

  @visibleForTesting
  static void resetIntros() => _introduced.clear();

  @override
  State<MorphFab> createState() => _MorphFabState();
}

class _MorphFabState extends State<MorphFab> with TickerProviderStateMixin {
  static const _enterTime = Duration(milliseconds: 700);
  static const _foldTime = Duration(milliseconds: 700);
  static const _shineTime = Duration(milliseconds: 1000);
  static const _ringTime = Duration(milliseconds: 1800);
  static const _popTime = Duration(milliseconds: 320);

  /// A ring this often while folded: noticed, never restless.
  static const _ringEvery = Duration(milliseconds: 3800);

  late final AnimationController _enter;

  /// 0 = the pill, 1 = the circle.
  late final AnimationController _fold;
  late final AnimationController _shine;
  late final AnimationController _ring;
  late final AnimationController _pop;

  final List<CurvedAnimation> _curves = [];
  late final Animation<double> _enterFade;
  late final Animation<Offset> _enterSlide;
  late final Animation<double> _enterScale;
  late final Animation<double> _foldCurve;
  late final Animation<double> _pillFade;
  late final Animation<double> _iconIn;
  late final Animation<double> _iconScale;
  late final Animation<double> _wiggle;
  late final Animation<double> _popScale;

  Timer? _hold;
  Timer? _ringTimer;
  final List<Timer> _shines = [];
  bool _still = false;
  bool _started = false;
  late final bool _arriveFolded;

  CurvedAnimation _curve(Animation<double> parent, Curve curve, [Curve? back]) {
    final c = CurvedAnimation(parent: parent, curve: curve, reverseCurve: back);
    _curves.add(c);
    return c;
  }

  @override
  void initState() {
    super.initState();
    final key = widget.introOnce;
    _arriveFolded = key != null && !MorphFab._introduced.add(key);

    _enter = AnimationController(vsync: this, duration: _enterTime);
    _fold = AnimationController(
      vsync: this,
      duration: _foldTime,
      value: _arriveFolded ? 1 : 0,
    )..addStatusListener(_onFoldStatus);
    _shine = AnimationController(vsync: this, duration: _shineTime);
    _ring = AnimationController(vsync: this, duration: _ringTime);
    _pop = AnimationController(vsync: this, duration: _popTime);

    // Springs up from below, a touch past its place, and settles.
    final spring = _curve(_enter, Curves.easeOutBack);
    _enterFade = _curve(_enter, const Interval(0, 0.5, curve: Curves.easeOut));
    _enterSlide = Tween(
      begin: const Offset(0, 0.9),
      end: Offset.zero,
    ).animate(spring);
    _enterScale = Tween(begin: 0.88, end: 1.0).animate(spring);

    // Out with a confident ease, back with a softer one.
    _foldCurve = _curve(
      _fold,
      Curves.easeInOutCubicEmphasized,
      Curves.easeOutCubic,
    );
    // The words leave first, so nothing is seen squeezed; the icon lands
    // last, with a little overshoot.
    _pillFade = ReverseAnimation(_curve(_fold, const Interval(0, 0.4)));
    _iconIn = _curve(_fold, const Interval(0.5, 1, curve: Curves.easeOutBack));
    _iconScale = Tween(begin: 0.4, end: 1.0).animate(_iconIn);

    // A phone ringing: a quick shake at the start of each ring (each swing
    // from where the last one ended), then still while the rings spread.
    _wiggle = _ring.drive(
      TweenSequence<double>([
        for (final (from, to, w) in const [
          (0.0, 0.045, 1.0),
          (0.045, -0.045, 2.0),
          (-0.045, 0.04, 2.0),
          (0.04, -0.04, 2.0),
          (-0.04, 0.03, 2.0),
          (0.03, 0.0, 1.0),
        ])
          TweenSequenceItem(
            tween: Tween(
              begin: from,
              end: to,
            ).chain(CurveTween(curve: Curves.easeInOut)),
            weight: w,
          ),
        TweenSequenceItem(tween: ConstantTween(0.0), weight: 16),
      ]),
    );

    // Lands as a circle with a small pop.
    _popScale = TweenSequence<double>([
      TweenSequenceItem(
        tween: Tween(
          begin: 1.0,
          end: 1.12,
        ).chain(CurveTween(curve: Curves.easeOut)),
        weight: 40,
      ),
      TweenSequenceItem(
        tween: Tween(
          begin: 1.12,
          end: 1.0,
        ).chain(CurveTween(curve: Curves.easeInOut)),
        weight: 60,
      ),
    ]).animate(_pop);

    widget.foldWhen?.addListener(_onFoldWhen);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _still = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
    for (final (c, d) in [
      (_enter, _enterTime),
      (_fold, _foldTime),
      (_pop, _popTime),
    ]) {
      c.duration = _still ? Duration.zero : d;
    }
    if (_still) _stopRinging();
    // Started here, not in initState: "reduce motion" is only known now,
    // and it decides how long the arrival takes.
    if (!_started) {
      _started = true;
      _enter.forward();
      if (_arriveFolded) {
        _startRinging();
      } else {
        final arrival = _enter.duration ?? Duration.zero;
        _scheduleFold(after: arrival + widget.holdFor);
        _glint(after: arrival);
      }
    }
  }

  @override
  void didUpdateWidget(MorphFab old) {
    super.didUpdateWidget(old);
    if (old.foldWhen != widget.foldWhen) {
      old.foldWhen?.removeListener(_onFoldWhen);
      widget.foldWhen?.addListener(_onFoldWhen);
    }
  }

  @override
  void dispose() {
    _hold?.cancel();
    _ringTimer?.cancel();
    for (final t in _shines) {
      t.cancel();
    }
    widget.foldWhen?.removeListener(_onFoldWhen);
    for (final c in _curves) {
      c.dispose();
    }
    for (final c in [_enter, _fold, _shine, _ring, _pop]) {
      c.dispose();
    }
    super.dispose();
  }

  void _scheduleFold({required Duration after}) {
    _hold?.cancel();
    _hold = Timer(after, _foldUp);
  }

  /// Two glints across the open pill: one as it lands, one mid-hold.
  void _glint({required Duration after}) {
    if (_still) return;
    for (final t in _shines) {
      t.cancel();
    }
    _shines
      ..clear()
      ..addAll([
        for (final delay in [after, after + const Duration(milliseconds: 1500)])
          Timer(delay, () {
            if (mounted && _fold.value == 0) _shine.forward(from: 0);
          }),
      ]);
  }

  void _foldUp() {
    _hold?.cancel();
    if (!mounted || _fold.status == AnimationStatus.completed) return;
    _fold.forward();
  }

  void _unfold() {
    if (_fold.status == AnimationStatus.dismissed ||
        _fold.status == AnimationStatus.reverse) {
      return;
    }
    unawaited(HapticFeedback.selectionClick());
    widget.onUnfold?.call();
    _stopRinging();
    _fold.reverse();
  }

  void _onFoldStatus(AnimationStatus status) {
    switch (status) {
      case AnimationStatus.completed:
        if (!_still) _pop.forward(from: 0);
        _startRinging();
      case AnimationStatus.dismissed:
        // Open again: glints, then it folds back by itself.
        _scheduleFold(after: widget.holdFor);
        _glint(after: Duration.zero);
      case AnimationStatus.forward || AnimationStatus.reverse:
        break;
    }
  }

  void _onFoldWhen() {
    if (widget.foldWhen?.value ?? false) _foldUp();
  }

  void _startRinging() {
    if (_still) return;
    _ringTimer?.cancel();
    // The first ring right after landing, then every few seconds.
    _ringTimer = Timer(const Duration(milliseconds: 450), () {
      if (!mounted || _fold.value != 1) return;
      _ring.forward(from: 0);
      _ringTimer = Timer.periodic(_ringEvery, (_) {
        if (mounted && _fold.value == 1) _ring.forward(from: 0);
      });
    });
  }

  void _stopRinging() {
    _ringTimer?.cancel();
    _ringTimer = null;
    _ring.value = 0;
  }

  @override
  Widget build(BuildContext context) {
    final size = widget.circleSize;
    final glow = widget.colors.first;
    final colors = widget.colors.length > 1
        ? widget.colors
        : [widget.colors.first, widget.colors.first];

    return SizedBox(
      height: math.max(widget.pillHeight, size),
      // Runs when the width changes, not per frame: the content is built
      // here once and handed to the per-frame builder below as-is.
      child: LayoutBuilder(
        builder: (context, box) {
          final full = box.maxWidth;
          final content = Stack(
            fit: StackFit.expand,
            children: [
              _OpenWidth(
                width: full,
                height: widget.pillHeight,
                child: ValueListenableBuilder<double>(
                  valueListenable: _fold,
                  // Untouchable as soon as it starts folding.
                  builder: (_, t, inner) =>
                      IgnorePointer(ignoring: t > 0.02, child: inner),
                  child: FadeTransition(opacity: _pillFade, child: widget.pill),
                ),
              ),
              _Shine(animation: _shine),
              _CircleLayer(
                fold: _fold,
                iconIn: _iconIn,
                iconScale: _iconScale,
                wiggle: _wiggle,
                icon: widget.icon,
                color: widget.iconColor,
                size: size,
                semanticLabel: widget.semanticLabel,
                // One tap does the action; the pill opens on a long press.
                onTap: widget.onTap ?? _unfold,
                onLongPress: widget.onTap == null ? null : _unfold,
              ),
            ],
          );
          // Built once here, not per frame: only its opacity changes.
          final text = widget.badge;
          final badge = text == null
              ? null
              : IgnorePointer(
                  child: FadeTransition(
                    opacity: _iconIn,
                    child: Center(
                      child: _Badge(
                        key: const ValueKey('morph-fab-badge'),
                        text: text,
                        background: widget.iconColor,
                        foreground: glow,
                        size: size,
                      ),
                    ),
                  ),
                );
          return FadeTransition(
            opacity: _enterFade,
            child: SlideTransition(
              position: _enterSlide,
              child: ScaleTransition(
                alignment: Alignment.bottomRight,
                scale: _enterScale,
                child: AnimatedBuilder(
                  animation: _foldCurve,
                  child: content,
                  builder: (context, child) {
                    final t = _foldCurve.value;
                    final radius = BorderRadius.circular(
                      lerpDouble(widget.pillRadius, size / 2, t)!,
                    );
                    return Align(
                      alignment: Alignment.bottomRight,
                      child: ScaleTransition(
                        scale: _popScale,
                        child: SizedBox(
                          width: lerpDouble(full, size, t),
                          height: lerpDouble(widget.pillHeight, size, t),
                          child: Stack(
                            clipBehavior: Clip.none,
                            children: [
                              // Behind the button, outside its clip.
                              Positioned.fill(
                                child: IgnorePointer(
                                  child: FadeTransition(
                                    opacity: _iconIn,
                                    child: RepaintBoundary(
                                      child: CustomPaint(
                                        painter: _RipplePainter(_ring, glow),
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                              Positioned.fill(
                                child: DecoratedBox(
                                  decoration: BoxDecoration(
                                    borderRadius: radius,
                                    gradient: LinearGradient(
                                      begin: Alignment.topLeft,
                                      end: Alignment.bottomRight,
                                      colors: colors,
                                    ),
                                    boxShadow: [
                                      BoxShadow(
                                        color: glow.withValues(alpha: 0.4),
                                        blurRadius: lerpDouble(22, 16, t)!,
                                        offset: Offset(
                                          0,
                                          lerpDouble(10, 6, t)!,
                                        ),
                                      ),
                                    ],
                                  ),
                                  child: ClipRRect(
                                    borderRadius: radius,
                                    child: child,
                                  ),
                                ),
                              ),
                              // On the circle's bottom edge, half outside it
                              // (so outside the clip); with the folded icon.
                              if (badge != null)
                                Positioned(
                                  left: 0,
                                  right: 0,
                                  bottom: -size * 0.16,
                                  child: badge,
                                ),
                            ],
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

/// Lays its child out at the open pill's size whatever the box's width now,
/// right-aligned like the box, so a narrowing box clips it instead of
/// re-laying it out (the same constraints every frame: laid out once).
class _OpenWidth extends SingleChildRenderObjectWidget {
  const _OpenWidth({required this.width, required this.height, super.child});
  final double width;
  final double height;

  @override
  RenderObject createRenderObject(BuildContext context) =>
      _RenderOpenWidth(width, height);

  @override
  void updateRenderObject(BuildContext context, _RenderOpenWidth r) => r
    ..openWidth = width
    ..openHeight = height;
}

class _RenderOpenWidth extends RenderProxyBox {
  _RenderOpenWidth(this._width, this._height);

  double _width;
  set openWidth(double v) {
    if (v == _width) return;
    _width = v;
    markNeedsLayout();
  }

  double _height;
  set openHeight(double v) {
    if (v == _height) return;
    _height = v;
    markNeedsLayout();
  }

  @override
  void performLayout() {
    size = constraints.biggest;
    child?.layout(BoxConstraints.tightFor(width: _width, height: _height));
  }

  Offset get _shift {
    final c = child!;
    return Offset(size.width - c.size.width, (size.height - c.size.height) / 2);
  }

  @override
  void paint(PaintingContext context, Offset offset) {
    if (child != null) context.paintChild(child!, offset + _shift);
  }

  @override
  bool hitTestChildren(BoxHitTestResult result, {required Offset position}) {
    final c = child;
    if (c == null) return false;
    return result.addWithPaintOffset(
      offset: _shift,
      position: position,
      hitTest: (result, p) => c.hitTest(result, position: p),
    );
  }

  @override
  void applyPaintTransform(RenderBox child, Matrix4 transform) {
    final s = _shift;
    transform.translateByDouble(s.dx, s.dy, 0, 1);
  }
}

/// The folded circle's icon (it shakes when the circle rings), the tap, and
/// the long press that opens the pill.
class _CircleLayer extends StatelessWidget {
  const _CircleLayer({
    required this.fold,
    required this.iconIn,
    required this.iconScale,
    required this.wiggle,
    required this.icon,
    required this.color,
    required this.size,
    required this.onTap,
    this.onLongPress,
    this.semanticLabel,
  });
  final AnimationController fold;
  final Animation<double> iconIn;
  final Animation<double> iconScale;
  final Animation<double> wiggle;
  final IconData icon;
  final Color color;
  final double size;
  final VoidCallback onTap;
  final VoidCallback? onLongPress;
  final String? semanticLabel;

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<double>(
      valueListenable: fold,
      // Only the (nearly) folded circle takes the tap; the open pill's own
      // buttons take theirs.
      builder: (_, t, inner) => IgnorePointer(ignoring: t < 0.6, child: inner),
      child: Semantics(
        button: true,
        label: semanticLabel,
        child: GestureDetector(
          key: const ValueKey('morph-fab-circle'),
          behavior: HitTestBehavior.opaque,
          onTap: onTap,
          onLongPress: onLongPress,
          child: Align(
            alignment: Alignment.centerRight,
            child: SizedBox(
              width: size,
              child: Center(
                child: FadeTransition(
                  opacity: iconIn,
                  child: ScaleTransition(
                    scale: iconScale,
                    child: RotationTransition(
                      turns: wiggle,
                      child: Icon(icon, color: color, size: size * 0.44),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// A small chip on the circle's bottom edge (a price): readable at a glance,
/// and the icon keeps the whole circle. Colours inverted from the circle's.
class _Badge extends StatelessWidget {
  const _Badge({
    super.key,
    required this.text,
    required this.background,
    required this.foreground,
    required this.size,
  });
  final String text;
  final Color background;
  final Color foreground;

  /// The circle's diameter: the badge is sized from it.
  final double size;

  @override
  Widget build(BuildContext context) {
    return ConstrainedBox(
      // Never wider than the circle plus a little: a long price shrinks.
      constraints: BoxConstraints(maxWidth: size * 1.25),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: background,
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: foreground, width: 1.2),
        ),
        child: Padding(
          padding: EdgeInsets.symmetric(
            horizontal: size * 0.1,
            vertical: size * 0.025,
          ),
          child: FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(
              text,
              maxLines: 1,
              style: TextStyle(
                color: foreground,
                fontSize: size * 0.165,
                fontWeight: FontWeight.w800,
                height: 1.15,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// A bright glint sweeping across the open pill. Draws nothing between
/// glints.
class _Shine extends StatelessWidget {
  const _Shine({required this.animation});
  final AnimationController animation;

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: AnimatedBuilder(
        animation: animation,
        builder: (context, _) {
          final v = animation.value;
          if (v == 0 || v == 1) return const SizedBox.shrink();
          final x = lerpDouble(-1.9, 1.9, Curves.easeInOut.transform(v))!;
          return Align(
            alignment: Alignment(x, 0),
            child: FractionallySizedBox(
              widthFactor: 0.3,
              heightFactor: 1.4,
              child: Transform(
                alignment: Alignment.center,
                transform: Matrix4.skewX(-0.4),
                child: const DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [
                        Color(0x00FFFFFF),
                        Color(0x66FFFFFF),
                        Color(0x00FFFFFF),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

/// Three rings leaving the circle, one after another.
class _RipplePainter extends CustomPainter {
  _RipplePainter(this.animation, this.color) : super(repaint: animation);
  final Animation<double> animation;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final v = animation.value;
    if (v == 0 || v == 1) return;
    final center = Offset(size.width - size.height / 2, size.height / 2);
    final base = size.height / 2;
    final paint = Paint()..style = PaintingStyle.stroke;
    for (final lag in const [0.0, 0.22, 0.44]) {
      final p = ((v - lag) / (1 - lag)).clamp(0.0, 1.0);
      if (p == 0 || p == 1) continue;
      final eased = Curves.easeOutCubic.transform(p);
      paint
        ..strokeWidth = 3 * (1 - eased) + 0.6
        ..color = color.withValues(alpha: 0.55 * (1 - eased));
      canvas.drawCircle(center, base + eased * base * 0.9, paint);
    }
  }

  @override
  bool shouldRepaint(_RipplePainter old) =>
      old.animation != animation || old.color != color;
}
