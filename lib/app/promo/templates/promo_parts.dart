import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../api/promo_banner/promo_content.dart';
import '../../component/c_image.dart';
import '../../component/c_toast.dart';
import '../../component/pressable.dart';
import 'promo_markup.dart';

/// Building blocks every banner and popup template shares: icons, the
/// button pill, the badge, the coupon chip, a cropped image that can drift
/// with the carousel, the fade that melts an image into its card.
///
/// Sizes are passed already scaled ([k] = the template's width / its design
/// width), so a template looks the same on every phone and in the admin
/// preview.

/// The admin's icon keys (docs/promo_templates.md §5) → Lucide.
IconData? promoIcon(String key, {IconData? fallback = LucideIcons.arrowRight}) =>
    switch (key) {
      'none' => null,
      'arrow_right' => LucideIcons.arrowRight,
      'chevron_right' => LucideIcons.chevronRight,
      'phone' => LucideIcons.phone,
      'video' => LucideIcons.video,
      'wallet' => LucideIcons.wallet,
      'gift' => LucideIcons.gift,
      'sparkles' => LucideIcons.sparkles,
      'star' => LucideIcons.star,
      'heart' => LucideIcons.heart,
      'zap' => LucideIcons.zap,
      'crown' => LucideIcons.crown,
      'tag' => LucideIcons.tag,
      'percent' => LucideIcons.percent,
      'bell' => LucideIcons.bell,
      'play' => LucideIcons.play,
      'users' => LucideIcons.users,
      'message' => LucideIcons.messageCircle,
      'power' => LucideIcons.power,
      'sliders' => LucideIcons.slidersHorizontal,
      'trophy' => LucideIcons.trophy,
      'flame' => LucideIcons.flame,
      'rocket' => LucideIcons.rocket,
      'badge_check' => LucideIcons.badgeCheck,
      _ => fallback,
    };

/// A template's own icon (not a button's): never "none".
IconData promoBadgeIcon(String key) =>
    promoIcon(key, fallback: LucideIcons.sparkles) ?? LucideIcons.sparkles;

/// The template background: [palette]'s gradient (flat without an end).
BoxDecoration promoBackground(
  PromoPalette palette, {
  Alignment begin = Alignment.centerLeft,
  Alignment end = Alignment.centerRight,
  BorderRadius? radius,
  BoxBorder? border,
}) => BoxDecoration(
  borderRadius: radius,
  border: border,
  color: palette.backgroundEnd == null ? palette.background : null,
  gradient: palette.backgroundEnd == null
      ? null
      : LinearGradient(begin: begin, end: end, colors: palette.gradient),
);

/// Small pill above a title ("LIMITED TIME").
class PromoBadge extends StatelessWidget {
  const PromoBadge(
    this.text, {
    super.key,
    required this.palette,
    required this.k,
    this.background,
    this.foreground,
    this.size = 9.5,
  });

  final String text;
  final PromoPalette palette;
  final double k;
  final Color? background;
  final Color? foreground;
  final double size;

  @override
  Widget build(BuildContext context) => Container(
    padding: EdgeInsets.symmetric(horizontal: 8 * k, vertical: 3 * k),
    decoration: BoxDecoration(
      color: background ?? palette.accent.withValues(alpha: 0.16),
      borderRadius: BorderRadius.circular(999),
    ),
    child: PromoText(
      text,
      size: size * k,
      weight: FontWeight.w800,
      color: foreground ?? palette.accent,
      accent: foreground ?? palette.accent,
      letterSpacing: 0.6 * k,
      uppercase: true,
      maxLines: 1,
    ),
  );
}

/// The banner button: a pill, the label, then its icon.
class PromoCtaPill extends StatelessWidget {
  const PromoCtaPill({
    super.key,
    required this.label,
    required this.icon,
    required this.palette,
    required this.k,
    this.size = 11.5,
    this.horizontal = 14,
    this.vertical = 7,
    this.iconSize = 13,
  });

  final String label;
  final String icon;
  final PromoPalette palette;
  final double k;
  final double size;
  final double horizontal;
  final double vertical;
  final double iconSize;

  @override
  Widget build(BuildContext context) {
    final glyph = promoIcon(icon);
    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: horizontal * k,
        vertical: vertical * k,
      ),
      decoration: BoxDecoration(
        color: palette.ctaBackground,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Flexible(
            child: PromoText(
              label,
              size: size * k,
              weight: FontWeight.w800,
              color: palette.ctaText,
              accent: palette.ctaText,
              maxLines: 1,
            ),
          ),
          if (glyph != null) ...[
            SizedBox(width: 5 * k),
            Icon(glyph, size: iconSize * k, color: palette.ctaText),
          ],
        ],
      ),
    );
  }
}

/// The popup's main button: full width, the label, then its icon.
class PromoMainButton extends StatelessWidget {
  const PromoMainButton({
    super.key,
    required this.label,
    required this.icon,
    required this.palette,
    required this.k,
    required this.onTap,
    this.height = 48,
  });

  final String label;
  final String icon;
  final PromoPalette palette;
  final double k;
  final VoidCallback onTap;
  final double height;

  @override
  Widget build(BuildContext context) {
    final glyph = promoIcon(icon);
    return Pressable(
      key: const ValueKey('promo-popup-cta'),
      activeOpacity: 0.85,
      onPressed: onTap,
      child: Container(
        height: height * k,
        width: double.infinity,
        alignment: Alignment.center,
        padding: EdgeInsets.symmetric(horizontal: 16 * k),
        decoration: BoxDecoration(
          color: palette.ctaBackground,
          borderRadius: BorderRadius.circular(14 * k),
          boxShadow: [
            BoxShadow(
              color: palette.ctaBackground.withValues(alpha: 0.35),
              blurRadius: 16 * k,
              offset: Offset(0, 6 * k),
            ),
          ],
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Flexible(
              child: PromoText(
                label,
                size: 15 * k,
                weight: FontWeight.w800,
                color: palette.ctaText,
                accent: palette.ctaText,
                maxLines: 1,
              ),
            ),
            if (glyph != null) ...[
              SizedBox(width: 6 * k),
              Icon(glyph, size: 16 * k, color: palette.ctaText),
            ],
          ],
        ),
      ),
    );
  }
}

/// A popup's "Maybe later": text that closes.
class PromoSecondaryButton extends StatelessWidget {
  const PromoSecondaryButton({
    super.key,
    required this.label,
    required this.color,
    required this.k,
    required this.onTap,
  });

  final String label;
  final Color color;
  final double k;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Pressable(
    key: const ValueKey('promo-popup-secondary'),
    onPressed: onTap,
    child: Padding(
      padding: EdgeInsets.symmetric(vertical: 10 * k, horizontal: 16 * k),
      child: PromoText(
        label,
        size: 13 * k,
        weight: FontWeight.w700,
        color: color.withValues(alpha: 0.7),
        accent: color,
        maxLines: 1,
        align: TextAlign.center,
      ),
    ),
  );
}

/// A coupon code in a dashed box; a tap copies it.
class PromoCouponChip extends StatelessWidget {
  const PromoCouponChip({
    super.key,
    required this.code,
    required this.palette,
    required this.k,
    this.large = false,
    this.onCopied,
  });

  final String code;
  final PromoPalette palette;
  final double k;

  /// The popup's big chip (accent border, copy icon) instead of the
  /// banner's small one.
  final bool large;
  final VoidCallback? onCopied;

  Future<void> _copy() async {
    try {
      await Clipboard.setData(ClipboardData(text: code));
    } catch (_) {}
    unawaited(HapticFeedback.selectionClick());
    CToast.show('common:promo.code_copied', variant: CToastVariant.success);
    onCopied?.call();
  }

  @override
  Widget build(BuildContext context) {
    final border = large
        ? palette.accent.withValues(alpha: 0.7)
        : palette.text.withValues(alpha: 0.6);
    final radius = (large ? 12 : 8) * k;
    return Pressable(
      key: const ValueKey('promo-coupon'),
      onPressed: _copy,
      child: CustomPaint(
        painter: _DashedRRect(
          color: border,
          stroke: (large ? 1.5 : 1.2) * k,
          radius: radius,
        ),
        child: Container(
          padding: EdgeInsets.symmetric(
            horizontal: (large ? 14 : 8) * k,
            vertical: (large ? 10 : 4) * k,
          ),
          decoration: BoxDecoration(
            color: large
                ? palette.accent.withValues(alpha: 0.10)
                : palette.text.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(radius),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Flexible(
                child: PromoText(
                  code,
                  size: (large ? 15 : 11) * k,
                  weight: FontWeight.w900,
                  color: large ? palette.accent : palette.text,
                  accent: palette.accent,
                  letterSpacing: (large ? 2 : 1) * k,
                  maxLines: 1,
                ),
              ),
              if (large) ...[
                SizedBox(width: 8 * k),
                Icon(LucideIcons.copy, size: 14 * k, color: palette.accent),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _DashedRRect extends CustomPainter {
  _DashedRRect({required this.color, required this.stroke, required this.radius});

  final Color color;
  final double stroke;
  final double radius;

  @override
  void paint(Canvas canvas, Size size) {
    final rrect = RRect.fromRectAndRadius(
      Offset.zero & size,
      Radius.circular(radius),
    ).deflate(stroke / 2);
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke;
    final dash = stroke * 3.2;
    final gap = stroke * 2.6;
    for (final metric in (Path()..addRRect(rrect)).computeMetrics()) {
      var d = 0.0;
      while (d < metric.length) {
        canvas.drawPath(metric.extractPath(d, d + dash), paint);
        d += dash + gap;
      }
    }
  }

  @override
  bool shouldRepaint(_DashedRRect old) =>
      old.color != color || old.stroke != stroke || old.radius != radius;
}

/// A vertical dashed line (the offer ticket's tear line).
class PromoDashedLine extends StatelessWidget {
  const PromoDashedLine({super.key, required this.color, required this.width});

  final Color color;
  final double width;

  @override
  Widget build(BuildContext context) => CustomPaint(
    size: Size(width, double.infinity),
    painter: _DashedLine(color: color, width: width),
  );
}

class _DashedLine extends CustomPainter {
  _DashedLine({required this.color, required this.width});
  final Color color;
  final double width;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = width
      ..strokeCap = StrokeCap.round;
    final dash = width * 2.7;
    var y = 0.0;
    while (y < size.height) {
      canvas.drawLine(
        Offset(size.width / 2, y),
        Offset(size.width / 2, math.min(y + dash, size.height)),
        paint,
      );
      y += dash * 2;
    }
  }

  @override
  bool shouldRepaint(_DashedLine old) =>
      old.color != color || old.width != width;
}

/// The carousel tells each card how far it is from the centre (−1…1), so
/// images can drift a little while a card slides (parallax).
class PromoParallax extends InheritedWidget {
  const PromoParallax({super.key, required this.offset, required super.child});

  final double offset;

  static double of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<PromoParallax>()?.offset ??
      0;

  @override
  bool updateShouldNotify(PromoParallax old) => old.offset != offset;
}

/// A cropped image ([focus] keeps the face), drifting with the carousel.
/// The image is zoomed just enough while it drifts that no edge shows.
class PromoImage extends StatelessWidget {
  const PromoImage({
    super.key,
    required this.url,
    required this.focus,
    this.drift = true,
    this.decodeWidth,
  });

  final String? url;
  final PromoImageFocus focus;

  /// Moves with [PromoParallax] (carousel cards).
  final bool drift;
  final double? decodeWidth;

  @override
  Widget build(BuildContext context) {
    final image = CImage(
      url: url,
      fit: BoxFit.cover,
      alignment: focus.alignment,
      width: decodeWidth,
    );
    if (!drift) return SizedBox.expand(child: image);
    final d = PromoParallax.of(context).clamp(-1.0, 1.0);
    if (d == 0) return SizedBox.expand(child: image);
    return ClipRect(
      child: LayoutBuilder(
        builder: (_, box) => Transform.translate(
          offset: Offset(-d * 0.09 * box.maxWidth, 0),
          child: Transform.scale(
            scale: 1 + 0.2 * d.abs(),
            child: SizedBox.expand(child: image),
          ),
        ),
      ),
    );
  }
}

/// A gradient over an image so it melts into [color] towards [towards]
/// (the image's inner edge): opaque there, clear at [clearAt] (0–1).
class PromoImageFade extends StatelessWidget {
  const PromoImageFade({
    super.key,
    required this.color,
    this.towards = Alignment.centerLeft,
    this.clearAt = 0.55,
  });

  final Color color;
  final Alignment towards;
  final double clearAt;

  @override
  Widget build(BuildContext context) => IgnorePointer(
    child: DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: towards,
          end: Alignment(-towards.x, -towards.y),
          colors: [color, color.withValues(alpha: 0)],
          stops: [0, clearAt],
        ),
      ),
    ),
  );
}

/// A soft frosted panel (glass banner).
class PromoGlass extends StatelessWidget {
  const PromoGlass({
    super.key,
    required this.tint,
    required this.radius,
    required this.child,
    this.blur = 14,
  });

  final Color tint;
  final double radius;
  final double blur;
  final Widget child;

  @override
  Widget build(BuildContext context) => ClipRRect(
    borderRadius: BorderRadius.circular(radius),
    child: BackdropFilter(
      filter: ui.ImageFilter.blur(sigmaX: blur, sigmaY: blur),
      child: Container(
        decoration: BoxDecoration(
          color: tint,
          borderRadius: BorderRadius.circular(radius),
          border: Border.all(color: Colors.white.withValues(alpha: 0.25)),
        ),
        child: child,
      ),
    ),
  );
}

/// Shrinks [child] (laid out [width] wide) when it does not fit, never clips:
/// long copy (Hindi, a narrow phone) gets smaller instead of cut.
class PromoFit extends StatelessWidget {
  const PromoFit({
    super.key,
    required this.width,
    required this.child,
    this.alignment = AlignmentDirectional.centerStart,
  });

  final double width;
  final Widget child;
  final AlignmentGeometry alignment;

  @override
  Widget build(BuildContext context) => FittedBox(
    fit: BoxFit.scaleDown,
    alignment: alignment,
    child: SizedBox(width: math.max(1, width), child: child),
  );
}

/// The offer ticket's outline: a rounded card with two half-circle notches
/// at [notchX] on the top and bottom edges.
class PromoTicketClipper extends CustomClipper<Path> {
  const PromoTicketClipper({
    required this.notchX,
    required this.notchRadius,
    required this.radius,
  });

  final double notchX;
  final double notchRadius;
  final double radius;

  @override
  Path getClip(Size size) {
    final card = Path()
      ..addRRect(
        RRect.fromRectAndRadius(Offset.zero & size, Radius.circular(radius)),
      );
    final notches = Path()
      ..addOval(
        Rect.fromCircle(center: Offset(notchX, 0), radius: notchRadius),
      )
      ..addOval(
        Rect.fromCircle(
          center: Offset(notchX, size.height),
          radius: notchRadius,
        ),
      );
    return Path.combine(PathOperation.difference, card, notches);
  }

  @override
  bool shouldReclip(PromoTicketClipper old) =>
      old.notchX != notchX ||
      old.notchRadius != notchRadius ||
      old.radius != radius;
}
