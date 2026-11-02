import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../core/utils/scale.dart';
import '../api/promo_banner/promo_banner_models.dart';
import '../component/c_image.dart';
import '../component/c_text.dart';
import '../component/pressable.dart';
import 'promo_effects.dart';

/// One promo banner, drawn from the admin's design: layout, height, colours
/// (or a gradient), image, darkening, text alignment, button. The admin's
/// preview (BannerPreview.jsx) draws the same thing.
class PromoBannerCard extends StatelessWidget {
  const PromoBannerCard({
    super.key,
    required this.banner,
    required this.width,
    this.onTap,
    this.onDismiss,
  });

  final PromoBanner banner;

  /// The card's width; its height scales with it (designed at 340).
  final double width;
  final VoidCallback? onTap;
  final VoidCallback? onDismiss;

  static double heightFor(PromoBanner b, double width) =>
      b.height.dp * (width / 340);

  @override
  Widget build(BuildContext context) {
    final b = banner;
    final height = heightFor(b, width);
    final radius = BorderRadius.circular(b.cornerRadius);
    final image = b.imageUrl == null
        ? const SizedBox.shrink()
        : CImage(url: b.imageUrl, fit: BoxFit.cover);
    final text = _Text(banner: b, compact: b.height == PromoHeight.small);

    final body = switch (b.layout) {
      PromoLayout.imageOnly => SizedBox.expand(child: image),
      PromoLayout.imageBackground => Stack(
        fit: StackFit.expand,
        children: [
          image,
          if (b.hasText) ...[
            ColoredBox(
              color: Colors.black.withValues(alpha: b.overlayOpacity / 100),
            ),
            text,
          ],
        ],
      ),
      PromoLayout.imageLeft => Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(width: width * 0.38, child: image),
          Expanded(child: text),
        ],
      ),
      PromoLayout.imageRight => Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(child: text),
          SizedBox(width: width * 0.38, child: image),
        ],
      ),
      PromoLayout.textOnly => text,
    };

    final card = Semantics(
      button: !b.action.isNone,
      label: [
        b.title,
        b.subtitle,
        b.ctaLabel,
      ].where((s) => s.isNotEmpty).join('. '),
      child: Container(
        width: width,
        height: height,
        clipBehavior: Clip.antiAlias,
        decoration: BoxDecoration(
          borderRadius: radius,
          color: b.backgroundEnd == null ? b.background : null,
          gradient: b.backgroundEnd == null
              ? null
              : LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [b.background, b.backgroundEnd!],
                ),
        ),
        child: b.effect == PromoEffect.none
            ? body
            : Stack(
                fit: StackFit.expand,
                children: [
                  body,
                  PromoEffectLayer(effect: b.effect, color: b.effectColor),
                ],
              ),
      ),
    );

    return Stack(
      children: [
        if (b.action.isNone || onTap == null)
          card
        else
          Pressable(onPressed: onTap, child: card),
        if (b.dismissible && onDismiss != null)
          PositionedDirectional(
            top: 6.ms,
            end: 6.ms,
            child: Pressable(
              key: ValueKey('promo-dismiss-${b.id}'),
              onPressed: onDismiss,
              child: Container(
                width: 24.ms,
                height: 24.ms,
                decoration: const BoxDecoration(
                  color: Colors.black38,
                  shape: BoxShape.circle,
                ),
                child: Icon(LucideIcons.x, size: 14.ms, color: Colors.white),
              ),
            ),
          ),
      ],
    );
  }
}

class _Text extends StatelessWidget {
  const _Text({required this.banner, required this.compact});
  final PromoBanner banner;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final b = banner;
    final align = b.centered ? TextAlign.center : TextAlign.start;
    return Padding(
      padding: EdgeInsets.symmetric(
        horizontal: (compact ? 14 : 16).ms,
        vertical: (compact ? 8 : 12).ms,
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: b.centered
            ? CrossAxisAlignment.center
            : CrossAxisAlignment.start,
        children: [
          if (b.title.isNotEmpty)
            Flexible(
              child: CText.raw(
                b.title,
                size: compact ? 15 : 17,
                weight: FontWeight.w800,
                color: b.text,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                align: align,
              ),
            ),
          if (b.subtitle.isNotEmpty) ...[
            SizedBox(height: 3.ms),
            Flexible(
              child: CText.raw(
                b.subtitle,
                size: 12.5,
                weight: FontWeight.w500,
                color: b.text.withValues(alpha: 0.9),
                maxLines: compact ? 1 : 2,
                overflow: TextOverflow.ellipsis,
                align: align,
              ),
            ),
          ],
          if (b.ctaLabel.isNotEmpty) ...[
            SizedBox(height: (compact ? 5 : 8).ms),
            Container(
              padding: EdgeInsets.symmetric(horizontal: 14.ms, vertical: 6.ms),
              decoration: BoxDecoration(
                color: b.ctaBackground,
                borderRadius: BorderRadius.circular(999),
              ),
              child: CText.raw(
                b.ctaLabel,
                size: 12,
                weight: FontWeight.w700,
                color: b.ctaText,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ],
      ),
    );
  }
}
