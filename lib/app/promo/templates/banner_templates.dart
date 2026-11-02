import 'package:flutter/material.dart';

import '../../api/promo_banner/promo_banner_models.dart';
import 'promo_countdown.dart';
import 'promo_markup.dart';
import 'promo_parts.dart';

/// The admin's banner templates (docs/promo_templates.md §3), drawn at any
/// width from their 340-wide design. The admin preview
/// (admin-pannel components/banners/templates/) draws the same keys.
///
/// A template draws its own background; the card around it
/// ([PromoBannerCard]) clips it to [PromoBannerTemplateView.clipperFor],
/// lays the effect over it and owns the tap.
class PromoBannerTemplateView extends StatelessWidget {
  const PromoBannerTemplateView({
    super.key,
    required this.template,
    required this.content,
    required this.width,
    this.onCopied,
    this.onEnded,
  });

  final PromoBannerTemplate template;
  final PromoContent content;
  final double width;

  /// The coupon code was copied (analytics).
  final VoidCallback? onCopied;

  /// A countdown reached zero.
  final VoidCallback? onEnded;

  static const designWidth = 340.0;
  static const radius = 24.0;

  static double heightFor(PromoBannerTemplate t, double width) =>
      t.baseHeight * width / designWidth;

  /// The outline: a rounded card; the offer ticket adds its two notches.
  static CustomClipper<Path> clipperFor(
    PromoBannerTemplate t,
    double width,
  ) {
    final k = width / designWidth;
    if (t == PromoBannerTemplate.offer) {
      return PromoTicketClipper(
        notchX: width * _Offer.split,
        notchRadius: 9 * k,
        radius: radius * k,
      );
    }
    return _RoundedClipper(radius * k);
  }

  @override
  Widget build(BuildContext context) {
    final k = width / designWidth;
    return switch (template) {
      PromoBannerTemplate.spotlight => _Spotlight(c: content, w: width, k: k),
      PromoBannerTemplate.offer => _Offer(
        c: content,
        w: width,
        k: k,
        onCopied: onCopied,
      ),
      PromoBannerTemplate.fullImage => _FullImage(c: content, w: width, k: k),
      PromoBannerTemplate.glass => _Glass(c: content, w: width, k: k),
      PromoBannerTemplate.minimal => _Minimal(c: content, w: width, k: k),
      PromoBannerTemplate.countdown => _Countdown(
        c: content,
        w: width,
        k: k,
        onEnded: onEnded,
      ),
    };
  }
}

class _RoundedClipper extends CustomClipper<Path> {
  const _RoundedClipper(this.radius);
  final double radius;

  @override
  Path getClip(Size size) => Path()
    ..addRRect(
      RRect.fromRectAndRadius(Offset.zero & size, Radius.circular(radius)),
    );

  @override
  bool shouldReclip(_RoundedClipper old) => old.radius != radius;
}

/// Badge · title · subtitle, the text block most templates share.
class _Copy extends StatelessWidget {
  const _Copy({
    required this.c,
    required this.k,
    required this.titleSize,
    this.titleLines = 2,
    this.titleHeight,
    this.subtitleSize = 10.5,
    this.subtitleLines = 2,
    this.subtitleHeight,
    this.subtitleAlpha = 0.85,
    this.badgeGap = 5,
    this.subtitleGap = 4,
  });

  final PromoContent c;
  final double k;
  final double titleSize;
  final int titleLines;
  final double? titleHeight;
  final double subtitleSize;
  final int subtitleLines;
  final double? subtitleHeight;
  final double subtitleAlpha;
  final double badgeGap;
  final double subtitleGap;

  @override
  Widget build(BuildContext context) {
    final p = c.palette;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (c.badge.isNotEmpty) ...[
          PromoBadge(c.badge, palette: p, k: k),
          SizedBox(height: badgeGap * k),
        ],
        if (c.title.isNotEmpty)
          PromoText(
            c.title,
            size: titleSize * k,
            weight: FontWeight.w900,
            color: p.text,
            accent: p.accent,
            maxLines: titleLines,
            lineHeight: titleHeight == null ? null : titleHeight! * k,
          ),
        if (c.subtitle.isNotEmpty) ...[
          SizedBox(height: subtitleGap * k),
          PromoText(
            c.subtitle,
            size: subtitleSize * k,
            weight: FontWeight.w600,
            color: p.text.withValues(alpha: subtitleAlpha),
            accent: p.accent,
            maxLines: subtitleLines,
            lineHeight: subtitleHeight == null ? null : subtitleHeight! * k,
          ),
        ],
      ],
    );
  }
}

PromoCtaPill? _cta(PromoContent c, double k) => c.ctaLabel.isEmpty
    ? null
    : PromoCtaPill(label: c.ctaLabel, icon: c.ctaIcon, palette: c.palette, k: k);

/// 1. Spotlight (the old Discover hero): the photo on one side melts into
/// the card; a two-colour title, a line, a button with an icon.
class _Spotlight extends StatelessWidget {
  const _Spotlight({required this.c, required this.w, required this.k});
  final PromoContent c;
  final double w;
  final double k;

  @override
  Widget build(BuildContext context) {
    final p = c.palette;
    final left = c.imageLeft;
    final imageWidth = w * 0.48;
    final cta = _cta(c, k);
    return DecoratedBox(
      decoration: promoBackground(
        p,
        begin: left ? Alignment.centerRight : Alignment.centerLeft,
        end: left ? Alignment.centerLeft : Alignment.centerRight,
      ),
      position: DecorationPosition.background,
      child: DecoratedBox(
        position: DecorationPosition.foreground,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(PromoBannerTemplateView.radius * k),
          border: Border.all(color: p.accent.withValues(alpha: 0.22)),
        ),
        child: Stack(
          fit: StackFit.expand,
          children: [
            Positioned(
              top: 0,
              bottom: 0,
              right: left ? null : 0,
              left: left ? 0 : null,
              width: imageWidth,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  PromoImage(
                    url: c.imageUrl,
                    focus: c.imageFocus,
                    decodeWidth: imageWidth,
                  ),
                  // The photo melts into the card behind the copy.
                  PromoImageFade(
                    color: p.fade,
                    towards: left ? Alignment.centerRight : Alignment.centerLeft,
                  ),
                ],
              ),
            ),
            Padding(
              padding: EdgeInsets.all(18 * k),
              child: PromoFit(
                width: w * 0.6,
                alignment: left
                    ? Alignment.centerRight
                    : Alignment.centerLeft,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _Copy(
                      c: c,
                      k: k,
                      titleSize: 18,
                      titleLines: 3,
                      titleHeight: 18 * 1.15,
                      subtitleSize: 11,
                      subtitleLines: 3,
                      subtitleHeight: 15,
                      subtitleAlpha: 0.7,
                      badgeGap: 6,
                      subtitleGap: 5,
                    ),
                    if (cta != null) ...[SizedBox(height: 10 * k), cta],
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 2. Offer ticket: big offer left of a dashed tear line with notches; title,
/// code and button on the right.
class _Offer extends StatelessWidget {
  const _Offer({
    required this.c,
    required this.w,
    required this.k,
    this.onCopied,
  });
  final PromoContent c;
  final double w;
  final double k;
  final VoidCallback? onCopied;

  /// The tear line's place along the width.
  static const split = 0.34;

  @override
  Widget build(BuildContext context) {
    final p = c.palette;
    final leftWidth = w * split;
    final rightWidth = w - leftWidth;
    final cta = _cta(c, k);
    return DecoratedBox(
      decoration: promoBackground(
        p,
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(
            width: leftWidth,
            child: Padding(
              padding: EdgeInsets.symmetric(horizontal: 10 * k),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  FittedBox(
                    fit: BoxFit.scaleDown,
                    child: PromoText(
                      c.offerValue,
                      size: 30 * k,
                      weight: FontWeight.w900,
                      color: p.accent,
                      accent: p.accent,
                      lineHeight: 30 * k,
                      maxLines: 1,
                    ),
                  ),
                  if (c.offerCaption.isNotEmpty) ...[
                    SizedBox(height: 4 * k),
                    PromoText(
                      c.offerCaption,
                      size: 10 * k,
                      weight: FontWeight.w800,
                      color: p.text.withValues(alpha: 0.85),
                      accent: p.accent,
                      letterSpacing: 0.8 * k,
                      uppercase: true,
                      maxLines: 2,
                      align: TextAlign.center,
                    ),
                  ],
                ],
              ),
            ),
          ),
          Padding(
            padding: EdgeInsets.symmetric(vertical: 13 * k),
            child: PromoDashedLine(
              color: p.text.withValues(alpha: 0.4),
              width: 1.5 * k,
            ),
          ),
          Expanded(
            child: Padding(
              padding: EdgeInsets.all(14 * k),
              child: PromoFit(
                width: rightWidth - 28 * k - 1.5 * k,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _Copy(c: c, k: k, titleSize: 16),
                    if (c.couponCode.isNotEmpty || cta != null) ...[
                      SizedBox(height: 9 * k),
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          if (c.couponCode.isNotEmpty)
                            Flexible(
                              child: PromoCouponChip(
                                code: c.couponCode,
                                palette: p,
                                k: k,
                                onCopied: onCopied,
                              ),
                            ),
                          if (c.couponCode.isNotEmpty && cta != null)
                            SizedBox(width: 8 * k),
                          ?cta,
                        ],
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// 3. Full image: the picture edge to edge, melting into colour at the
/// bottom where the text and button sit.
class _FullImage extends StatelessWidget {
  const _FullImage({required this.c, required this.w, required this.k});
  final PromoContent c;
  final double w;
  final double k;

  @override
  Widget build(BuildContext context) {
    final p = c.palette;
    final cta = _cta(c, k);
    return ColoredBox(
      color: p.background,
      child: Stack(
        fit: StackFit.expand,
        children: [
          PromoImage(url: c.imageUrl, focus: c.imageFocus, decodeWidth: w),
          IgnorePointer(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    p.background.withValues(alpha: 0),
                    p.background.withValues(alpha: 0.95),
                  ],
                  stops: const [0.25, 1],
                ),
              ),
            ),
          ),
          Positioned(
            left: 16 * k,
            right: 16 * k,
            bottom: 16 * k,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Expanded(
                  child: _Copy(
                    c: c,
                    k: k,
                    titleSize: 18,
                    subtitleSize: 11,
                    subtitleLines: 1,
                    badgeGap: 4,
                    subtitleGap: 3,
                  ),
                ),
                if (cta != null) ...[SizedBox(width: 10 * k), cta],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// 4. Frosted glass: the picture behind a frosted panel with the copy.
class _Glass extends StatelessWidget {
  const _Glass({required this.c, required this.w, required this.k});
  final PromoContent c;
  final double w;
  final double k;

  @override
  Widget build(BuildContext context) {
    final p = c.palette;
    final panel = w * 0.62;
    final cta = _cta(c, k);
    return ColoredBox(
      color: p.background,
      child: Stack(
        fit: StackFit.expand,
        children: [
          PromoImage(url: c.imageUrl, focus: c.imageFocus, decodeWidth: w),
          Positioned(
            top: 10 * k,
            bottom: 10 * k,
            left: c.imageLeft ? null : 10 * k,
            right: c.imageLeft ? 10 * k : null,
            width: panel,
            child: PromoGlass(
              tint: p.background.withValues(alpha: 0.35),
              radius: 18 * k,
              child: Padding(
                padding: EdgeInsets.all(14 * k),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Flexible(
                      child: PromoFit(
                        width: panel - 28 * k,
                        alignment: AlignmentDirectional.topStart,
                        child: _Copy(c: c, k: k, titleSize: 16),
                      ),
                    ),
                    if (cta != null)
                      Padding(padding: EdgeInsets.only(top: 6 * k), child: cta),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// 5. Compact: a slim strip, an icon or round photo, one line, a button.
class _Minimal extends StatelessWidget {
  const _Minimal({required this.c, required this.w, required this.k});
  final PromoContent c;
  final double w;
  final double k;

  @override
  Widget build(BuildContext context) {
    final p = c.palette;
    final circle = 52 * k;
    final ctaIcon = promoIcon(c.ctaIcon, fallback: Icons.chevron_right);
    final Widget? cta = c.ctaLabel.isNotEmpty
        ? _cta(c, k)
        : ctaIcon == null
        ? null
        : Container(
            width: 34 * k,
            height: 34 * k,
            decoration: BoxDecoration(
              color: p.ctaBackground,
              shape: BoxShape.circle,
            ),
            child: Icon(ctaIcon, size: 17 * k, color: p.ctaText),
          );
    return DecoratedBox(
      decoration: promoBackground(p),
      child: Padding(
        padding: EdgeInsets.all(14 * k),
        child: Row(
          children: [
            Container(
              width: circle,
              height: circle,
              clipBehavior: Clip.antiAlias,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: p.accent.withValues(alpha: 0.15),
              ),
              child: c.hasImage
                  ? PromoImage(
                      url: c.imageUrl,
                      focus: c.imageFocus,
                      drift: false,
                      decodeWidth: circle,
                    )
                  : Icon(
                      promoBadgeIcon(c.icon),
                      size: 24 * k,
                      color: p.accent,
                    ),
            ),
            SizedBox(width: 12 * k),
            Expanded(
              child: LayoutBuilder(
                builder: (_, box) => PromoFit(
                  width: box.maxWidth,
                  child: _Copy(
                    c: c,
                    k: k,
                    titleSize: 15,
                    subtitleSize: 11,
                    subtitleAlpha: 0.7,
                    subtitleGap: 3,
                  ),
                ),
              ),
            ),
            if (cta != null) ...[SizedBox(width: 10 * k), cta],
          ],
        ),
      ),
    );
  }
}

/// 6. Countdown: a live timer to the end date; gone when time is up.
class _Countdown extends StatelessWidget {
  const _Countdown({
    required this.c,
    required this.w,
    required this.k,
    this.onEnded,
  });
  final PromoContent c;
  final double w;
  final double k;
  final VoidCallback? onEnded;

  @override
  Widget build(BuildContext context) {
    final p = c.palette;
    final image = c.hasImage;
    final left = c.imageLeft;
    final textWidth = (image ? w * 0.62 : w) - 32 * k;
    final cta = _cta(c, k);
    final ends = c.endsAt;
    return DecoratedBox(
      decoration: promoBackground(
        p,
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
      ),
      child: Stack(
        fit: StackFit.expand,
        children: [
          if (image)
            Positioned(
              top: 0,
              bottom: 0,
              right: left ? null : 0,
              left: left ? 0 : null,
              width: w * 0.4,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  PromoImage(
                    url: c.imageUrl,
                    focus: c.imageFocus,
                    decodeWidth: w * 0.4,
                  ),
                  PromoImageFade(
                    color: p.fade,
                    towards: left ? Alignment.centerRight : Alignment.centerLeft,
                  ),
                ],
              ),
            ),
          // Badge and title keep to the text side; the timer and the button
          // use the full width (the button may sit over the faded photo).
          Padding(
            padding: EdgeInsets.all(16 * k),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Flexible(
                  child: Align(
                    alignment: image && left
                        ? Alignment.topRight
                        : Alignment.topLeft,
                    child: PromoFit(
                      width: textWidth,
                      alignment: AlignmentDirectional.topStart,
                      child: _Copy(c: c, k: k, titleSize: 17),
                    ),
                  ),
                ),
                PromoFit(
                  width: w - 32 * k,
                  child: Row(
                    children: [
                      if (ends != null)
                        PromoCountdown(
                          endsAt: ends,
                          palette: p,
                          k: k,
                          onEnded: onEnded,
                        ),
                      const Spacer(),
                      if (cta != null) ...[SizedBox(width: 8 * k), cta],
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Plain title text of [c] for screen readers.
String promoSemantics(PromoContent c) => [
  c.badge,
  if (c.offerValue.isNotEmpty) '${c.offerValue} ${c.offerCaption}'.trim(),
  PromoMarkup.plain(c.title),
  PromoMarkup.plain(c.subtitle),
  c.couponCode,
  c.ctaLabel,
].where((s) => s.isNotEmpty).join('. ');
