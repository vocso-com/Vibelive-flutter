import 'dart:async';

import 'package:flutter/material.dart';

import '../../../core/i18n/i18n.dart';
import '../../api/promo_banner/promo_content.dart';
import 'promo_markup.dart';

/// A live timer to [endsAt]: boxes of two digits with a label under each.
/// Each digit change slides in from above and fades (still on reduce-motion).
/// [onEnded] runs once when it reaches zero.
class PromoCountdown extends StatefulWidget {
  const PromoCountdown({
    super.key,
    required this.endsAt,
    required this.palette,
    required this.k,
    this.boxWidth = 34,
    this.boxHeight = 30,
    this.radius = 8,
    this.digitSize = 15,
    this.labelSize = 8.5,
    this.gap = 6,
    this.boxAlpha = 0.14,
    this.daysFromHours = 100,
    this.showSecondsWithDays = false,
    this.onEnded,
  });

  final DateTime endsAt;
  final PromoPalette palette;
  final double k;
  final double boxWidth;
  final double boxHeight;
  final double radius;
  final double digitSize;
  final double labelSize;
  final double gap;
  final double boxAlpha;

  /// From this many hours left, the first box counts days.
  final int daysFromHours;

  /// With days showing: DAYS HRS MIN SEC (popup) instead of DAYS HRS MIN.
  final bool showSecondsWithDays;
  final VoidCallback? onEnded;

  /// The boxes for [left]: (value, i18n label key) pairs.
  @visibleForTesting
  static List<(int, String)> units(
    Duration left, {
    int daysFromHours = 100,
    bool showSecondsWithDays = false,
  }) {
    final d = left.isNegative ? Duration.zero : left;
    final secs = d.inSeconds;
    if (d.inHours >= daysFromHours) {
      return [
        (d.inDays, 'common:promo.days'),
        (d.inHours % 24, 'common:promo.hrs'),
        (d.inMinutes % 60, 'common:promo.min'),
        if (showSecondsWithDays) (secs % 60, 'common:promo.sec'),
      ];
    }
    return [
      (d.inHours, 'common:promo.hrs'),
      (d.inMinutes % 60, 'common:promo.min'),
      (secs % 60, 'common:promo.sec'),
    ];
  }

  @override
  State<PromoCountdown> createState() => _PromoCountdownState();
}

class _PromoCountdownState extends State<PromoCountdown> {
  Timer? _tick;
  bool _ended = false;

  Duration get _left => widget.endsAt.difference(DateTime.now());

  @override
  void initState() {
    super.initState();
    _tick = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      if (_left <= Duration.zero) {
        _tick?.cancel();
        if (!_ended) {
          _ended = true;
          widget.onEnded?.call();
        }
      }
      setState(() {});
    });
  }

  @override
  void dispose() {
    _tick?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final k = widget.k;
    final p = widget.palette;
    final still = MediaQuery.disableAnimationsOf(context);
    final units = PromoCountdown.units(
      _left,
      daysFromHours: widget.daysFromHours,
      showSecondsWithDays: widget.showSecondsWithDays,
    );
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (var i = 0; i < units.length; i++) ...[
          if (i > 0) SizedBox(width: widget.gap * k),
          Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: widget.boxWidth * k,
                height: widget.boxHeight * k,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: p.text.withValues(alpha: widget.boxAlpha),
                  borderRadius: BorderRadius.circular(widget.radius * k),
                ),
                child: ClipRect(
                  child: AnimatedSwitcher(
                    duration: still
                        ? Duration.zero
                        : const Duration(milliseconds: 320),
                    switchInCurve: Curves.easeOutCubic,
                    switchOutCurve: Curves.easeInCubic,
                    transitionBuilder: (child, anim) => FadeTransition(
                      opacity: anim,
                      child: SlideTransition(
                        position: Tween(
                          begin: const Offset(0, -0.45),
                          end: Offset.zero,
                        ).animate(anim),
                        child: child,
                      ),
                    ),
                    child: PromoText(
                      units[i].$1.toString().padLeft(2, '0'),
                      key: ValueKey('${units[i].$2}-${units[i].$1}'),
                      size: widget.digitSize * k,
                      weight: FontWeight.w900,
                      color: p.text,
                      accent: p.accent,
                      tabular: true,
                      maxLines: 1,
                    ),
                  ),
                ),
              ),
              SizedBox(height: 3 * k),
              PromoText(
                context.t(units[i].$2),
                size: widget.labelSize * k,
                weight: FontWeight.w800,
                color: p.text.withValues(alpha: 0.7),
                accent: p.accent,
                uppercase: true,
                maxLines: 1,
              ),
            ],
          ),
        ],
      ],
    );
  }
}
