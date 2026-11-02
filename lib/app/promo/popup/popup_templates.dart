import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../core/i18n/i18n.dart';
import '../../api/promo_banner/promo_popup_models.dart';
import '../../component/pressable.dart';
import '../promo_effects.dart';
import '../templates/promo_countdown.dart';
import '../templates/promo_markup.dart';
import '../templates/promo_parts.dart';

/// How a popup went away.
enum PromoPopupExit {
  cta,
  closeButton,
  secondary,
  backdrop,
  back,
  expired;

  /// The analytics name (`close_button`…).
  String get wire => switch (this) {
    cta => 'cta',
    closeButton => 'close_button',
    secondary => 'secondary',
    backdrop => 'backdrop',
    back => 'back',
    expired => 'expired',
  };
}

/// What a template can do: the main button, closing, copying the code.
class PromoPopupCallbacks {
  const PromoPopupCallbacks({
    required this.onExit,
    this.onCopied,
  });

  /// Closes the popup with how it went away.
  final void Function(PromoPopupExit how) onExit;
  final VoidCallback? onCopied;
}

/// The admin's popup templates (docs/promo_templates.md §4), drawn at any
/// width from their 320-wide design. Centred cards: offer_card,
/// celebration, countdown, spotlight, announcement; and poster (just the
/// image). [PromoPopupSheet] and [PromoPopupFullscreen] are the other two.
class PromoPopupCard extends StatelessWidget {
  const PromoPopupCard({
    super.key,
    required this.popup,
    required this.width,
    required this.callbacks,
    this.maxHeight = double.infinity,
  });

  final PromoPopup popup;

  /// min(screen width − 48, 340).
  final double width;
  final PromoPopupCallbacks callbacks;

  /// The card scrolls inside this height on a short phone.
  final double maxHeight;

  static const designWidth = 320.0;

  static double widthFor(double screenWidth) =>
      math.min(screenWidth - 48, 340).toDouble();

  @override
  Widget build(BuildContext context) {
    final k = width / designWidth;
    final c = popup.content;
    if (popup.template == PromoPopupTemplate.poster) {
      return _Poster(popup: popup, w: width, k: k, cb: callbacks);
    }
    final body = switch (popup.template) {
      PromoPopupTemplate.offerCard => _offerCard(context, k),
      PromoPopupTemplate.celebration => _celebration(context, k),
      PromoPopupTemplate.countdown => _countdown(context, k),
      PromoPopupTemplate.spotlight => _spotlight(context, k),
      _ => _announcement(context, k),
    };
    final vertical = popup.template == PromoPopupTemplate.offerCard ||
        popup.template == PromoPopupTemplate.spotlight ||
        popup.template == PromoPopupTemplate.announcement;
    final onImage =
        c.hasImage &&
        (popup.template == PromoPopupTemplate.offerCard ||
            popup.template == PromoPopupTemplate.countdown ||
            popup.template == PromoPopupTemplate.announcement);
    final effect = c.effect != PromoEffect.none;
    return Container(
      width: width,
      constraints: BoxConstraints(maxHeight: maxHeight),
      clipBehavior: Clip.antiAlias,
      decoration: promoBackground(
        c.palette,
        begin: vertical ? Alignment.topCenter : Alignment.topLeft,
        end: vertical ? Alignment.bottomCenter : Alignment.bottomRight,
        radius: BorderRadius.circular(28 * k),
      ).copyWith(
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.35),
            blurRadius: 40 * k,
            offset: Offset(0, 16 * k),
          ),
        ],
      ),
      child: Stack(
        children: [
          if (effect)
            Positioned.fill(
              child: PromoEffectLayer(effect: c.effect, color: c.effectColor),
            ),
          SingleChildScrollView(
            physics: const ClampingScrollPhysics(),
            child: body,
          ),
          PositionedDirectional(
            top: 12 * k,
            end: 12 * k,
            child: PromoCloseButton(
              palette: c.palette,
              k: k,
              onImage: onImage,
              onTap: () => callbacks.onExit(PromoPopupExit.closeButton),
            ),
          ),
        ],
      ),
    );
  }

  // ── Shared bits ────────────────────────────────────────────────────────

  Widget _actions(BuildContext context, double k, {bool button = true}) {
    final c = popup.content;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (button && c.ctaLabel.isNotEmpty)
          PromoMainButton(
            label: c.ctaLabel,
            icon: c.ctaIcon,
            palette: c.palette,
            k: k,
            onTap: () => callbacks.onExit(PromoPopupExit.cta),
          ),
        if (popup.secondaryLabel.isNotEmpty)
          Padding(
            padding: EdgeInsets.only(top: 4 * k),
            child: PromoSecondaryButton(
              label: popup.secondaryLabel,
              color: c.palette.text,
              k: k,
              onTap: () => callbacks.onExit(PromoPopupExit.secondary),
            ),
          ),
      ],
    );
  }

  Widget _title(double k, double size, {int lines = 2}) {
    final c = popup.content;
    return PromoText(
      c.title,
      size: size * k,
      weight: FontWeight.w900,
      color: c.palette.text,
      accent: c.palette.accent,
      maxLines: lines,
      align: TextAlign.center,
      lineHeight: size * 1.2 * k,
    );
  }

  Widget? _subtitle(double k, double size, double alpha, int lines) {
    final c = popup.content;
    if (c.subtitle.isEmpty) return null;
    return PromoText(
      c.subtitle,
      size: size * k,
      weight: FontWeight.w500,
      color: c.palette.text.withValues(alpha: alpha),
      accent: c.palette.accent,
      maxLines: lines,
      align: TextAlign.center,
      lineHeight: size * 1.4 * k,
    );
  }

  Widget? _badge(double k) {
    final c = popup.content;
    return c.badge.isEmpty
        ? null
        : PromoBadge(c.badge, palette: c.palette, k: k);
  }

  /// A full-width image on top that melts into the card at its bottom.
  Widget _topImage(double k, double height) {
    final c = popup.content;
    return SizedBox(
      height: height * k,
      width: double.infinity,
      child: Stack(
        fit: StackFit.expand,
        children: [
          PromoImage(
            url: c.imageUrl,
            focus: c.imageFocus,
            drift: false,
            decodeWidth: width,
          ),
          PromoImageFade(
            color: Color.lerp(c.palette.background, c.palette.end, 0.3)!,
            towards: Alignment.bottomCenter,
            clearAt: 0.45,
          ),
        ],
      ),
    );
  }

  Widget _iconCircle(double k, double size, double iconSize) {
    final p = popup.content.palette;
    return Container(
      width: size * k,
      height: size * k,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: p.accent.withValues(alpha: 0.18),
      ),
      child: Icon(
        promoBadgeIcon(popup.content.icon),
        size: iconSize * k,
        color: p.accent,
      ),
    );
  }

  List<Widget> _gap(double v, double k, Widget? child) =>
      child == null ? const [] : [SizedBox(height: v * k), child];

  // ── 1. Offer ───────────────────────────────────────────────────────────

  Widget _offerCard(BuildContext context, double k) {
    final c = popup.content;
    final p = c.palette;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (c.hasImage)
          _topImage(k, 180)
        else ...[
          SizedBox(height: 28 * k),
          _iconCircle(k, 72, 34),
        ],
        Padding(
          padding: EdgeInsets.fromLTRB(20 * k, (c.hasImage ? 4 : 14) * k, 20 * k, 16 * k),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ?_badge(k),
              if (c.offerValue.isNotEmpty) ...[
                SizedBox(height: (c.badge.isEmpty ? 0 : 8) * k),
                FittedBox(
                  fit: BoxFit.scaleDown,
                  child: PromoText(
                    c.offerValue,
                    size: 40 * k,
                    weight: FontWeight.w900,
                    color: p.accent,
                    accent: p.accent,
                    lineHeight: 44 * k,
                    maxLines: 1,
                  ),
                ),
              ],
              if (c.offerCaption.isNotEmpty) ...[
                SizedBox(height: 2 * k),
                PromoText(
                  c.offerCaption,
                  size: 12 * k,
                  weight: FontWeight.w800,
                  color: p.text.withValues(alpha: 0.75),
                  accent: p.accent,
                  letterSpacing: 1.2 * k,
                  uppercase: true,
                  maxLines: 1,
                  align: TextAlign.center,
                ),
              ],
              SizedBox(height: 8 * k),
              _title(k, 19),
              ..._gap(6, k, _subtitle(k, 13, 0.75, 3)),
              if (c.couponCode.isNotEmpty) ...[
                SizedBox(height: 14 * k),
                PromoCouponChip(
                  code: c.couponCode,
                  palette: p,
                  k: k,
                  large: true,
                  onCopied: callbacks.onCopied,
                ),
              ],
              SizedBox(height: 16 * k),
              _actions(context, k),
            ],
          ),
        ),
      ],
    );
  }

  // ── 3. Celebration ─────────────────────────────────────────────────────

  Widget _celebration(BuildContext context, double k) {
    final c = popup.content;
    final p = c.palette;
    final size = 96 * k;
    return Padding(
      padding: EdgeInsets.fromLTRB(20 * k, 28 * k, 20 * k, 16 * k),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: size,
            height: size,
            clipBehavior: Clip.antiAlias,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: c.hasImage
                  ? null
                  : LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [p.accent, p.accent.withValues(alpha: 0.7)],
                    ),
              border: c.hasImage
                  ? Border.all(color: p.accent, width: 4 * k)
                  : null,
              boxShadow: [
                BoxShadow(
                  color: p.accent.withValues(alpha: 0.45),
                  blurRadius: 24 * k,
                ),
              ],
            ),
            child: c.hasImage
                ? PromoImage(
                    url: c.imageUrl,
                    focus: c.imageFocus,
                    drift: false,
                    decodeWidth: size,
                  )
                : Icon(promoBadgeIcon(c.icon), size: 44 * k, color: Colors.white),
          ),
          SizedBox(height: 14 * k),
          if (c.badge.isNotEmpty) ...[_badge(k)!, SizedBox(height: 8 * k)],
          _title(k, 22),
          ..._gap(6, k, _subtitle(k, 13.5, 0.8, 3)),
          SizedBox(height: 18 * k),
          _actions(context, k),
        ],
      ),
    );
  }

  // ── 5. Flash sale (countdown) ──────────────────────────────────────────

  Widget _countdown(BuildContext context, double k) {
    final c = popup.content;
    final p = c.palette;
    final ends = c.endsAt;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (c.hasImage) _topImage(k, 150) else SizedBox(height: 26 * k),
        Padding(
          padding: EdgeInsets.fromLTRB(20 * k, 4 * k, 20 * k, 16 * k),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ?_badge(k),
              if (c.offerValue.isNotEmpty) ...[
                SizedBox(height: (c.badge.isEmpty ? 0 : 8) * k),
                FittedBox(
                  fit: BoxFit.scaleDown,
                  child: PromoText(
                    c.offerValue,
                    size: 36 * k,
                    weight: FontWeight.w900,
                    color: p.accent,
                    accent: p.accent,
                    maxLines: 1,
                  ),
                ),
              ],
              SizedBox(height: 6 * k),
              _title(k, 19),
              ..._gap(6, k, _subtitle(k, 13, 0.75, 3)),
              if (ends != null) ...[
                SizedBox(height: 14 * k),
                FittedBox(
                  fit: BoxFit.scaleDown,
                  child: PromoCountdown(
                    endsAt: ends,
                    palette: p,
                    k: k,
                    boxWidth: 52,
                    boxHeight: 50,
                    radius: 12,
                    digitSize: 22,
                    labelSize: 9.5,
                    gap: 8,
                    boxAlpha: 0.12,
                    daysFromHours: 24,
                    showSecondsWithDays: true,
                    onEnded: () => callbacks.onExit(PromoPopupExit.expired),
                  ),
                ),
              ],
              SizedBox(height: 16 * k),
              _actions(context, k),
            ],
          ),
        ),
      ],
    );
  }

  // ── 6. Host spotlight ──────────────────────────────────────────────────

  Widget _spotlight(BuildContext context, double k) {
    final c = popup.content;
    final p = c.palette;
    final size = 128 * k;
    return Padding(
      padding: EdgeInsets.fromLTRB(20 * k, 28 * k, 20 * k, 16 * k),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Stack(
            clipBehavior: Clip.none,
            alignment: Alignment.bottomCenter,
            children: [
              Container(
                width: size,
                height: size,
                clipBehavior: Clip.antiAlias,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(color: p.accent, width: 3 * k),
                  boxShadow: [
                    BoxShadow(
                      color: p.accent.withValues(alpha: 0.4),
                      blurRadius: 28 * k,
                      spreadRadius: 2 * k,
                    ),
                  ],
                ),
                child: PromoImage(
                  url: c.imageUrl,
                  focus: c.imageFocus,
                  drift: false,
                  decodeWidth: size,
                ),
              ),
              if (c.badge.isNotEmpty)
                Positioned(
                  bottom: -10 * k,
                  child: PromoBadge(
                    c.badge,
                    palette: p,
                    k: k,
                    background: p.accent,
                    foreground: p.ctaText,
                    size: 10,
                  ),
                ),
            ],
          ),
          SizedBox(height: (c.badge.isEmpty ? 14 : 24) * k),
          _title(k, 21),
          ..._gap(6, k, _subtitle(k, 13, 0.75, 3)),
          SizedBox(height: 18 * k),
          _actions(context, k),
        ],
      ),
    );
  }

  // ── 7. Announcement ────────────────────────────────────────────────────

  Widget _announcement(BuildContext context, double k) {
    final c = popup.content;
    final p = c.palette;
    final darker = Color.lerp(p.accent, Colors.black, 0.2)!;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (c.hasImage)
          _topImage(k, 160)
        else ...[
          SizedBox(height: 28 * k),
          Container(
            width: 64 * k,
            height: 64 * k,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(20 * k),
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [p.accent, darker],
              ),
              boxShadow: [
                BoxShadow(
                  color: p.accent.withValues(alpha: 0.35),
                  blurRadius: 18 * k,
                  offset: Offset(0, 6 * k),
                ),
              ],
            ),
            child: Icon(
              promoBadgeIcon(c.icon),
              size: 30 * k,
              color: Colors.white,
            ),
          ),
        ],
        Padding(
          padding: EdgeInsets.fromLTRB(20 * k, 12 * k, 20 * k, 16 * k),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (c.badge.isNotEmpty) ...[_badge(k)!, SizedBox(height: 8 * k)],
              _title(k, 20),
              ..._gap(8, k, _subtitle(k, 13.5, 0.75, 6)),
              SizedBox(height: 18 * k),
              _actions(context, k),
            ],
          ),
        ),
      ],
    );
  }
}

/// 2. Poster: just the image (4:5), tappable, an optional button under it.
class _Poster extends StatelessWidget {
  const _Poster({
    required this.popup,
    required this.w,
    required this.k,
    required this.cb,
  });

  final PromoPopup popup;
  final double w;
  final double k;
  final PromoPopupCallbacks cb;

  @override
  Widget build(BuildContext context) {
    final c = popup.content;
    return SizedBox(
      width: w,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Stack(
            children: [
              Pressable(
                key: const ValueKey('promo-poster-image'),
                activeOpacity: 0.92,
                onPressed: () => cb.onExit(PromoPopupExit.cta),
                child: Container(
                  clipBehavior: Clip.antiAlias,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(24 * k),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.4),
                        blurRadius: 40 * k,
                        offset: Offset(0, 16 * k),
                      ),
                    ],
                  ),
                  child: AspectRatio(
                    aspectRatio: 4 / 5,
                    child: PromoImage(
                      url: c.imageUrl,
                      focus: c.imageFocus,
                      drift: false,
                      decodeWidth: w,
                    ),
                  ),
                ),
              ),
              PositionedDirectional(
                top: 12 * k,
                end: 12 * k,
                child: PromoCloseButton(
                  palette: c.palette,
                  k: k,
                  onImage: true,
                  onTap: () => cb.onExit(PromoPopupExit.closeButton),
                ),
              ),
            ],
          ),
          if (c.ctaLabel.isNotEmpty) ...[
            SizedBox(height: 14 * k),
            Pressable(
              key: const ValueKey('promo-popup-cta'),
              activeOpacity: 0.85,
              onPressed: () => cb.onExit(PromoPopupExit.cta),
              child: PromoCtaPill(
                label: c.ctaLabel,
                icon: c.ctaIcon,
                palette: c.palette,
                k: k,
                size: 14,
                horizontal: 22,
                vertical: 11,
                iconSize: 15,
              ),
            ),
          ],
          if (popup.secondaryLabel.isNotEmpty) ...[
            SizedBox(height: 6 * k),
            PromoSecondaryButton(
              label: popup.secondaryLabel,
              color: Colors.white,
              k: k,
              onTap: () => cb.onExit(PromoPopupExit.secondary),
            ),
          ],
        ],
      ),
    );
  }
}

/// 4. Bottom sheet: slides up; a small image or icon, text and a button.
class PromoPopupSheet extends StatelessWidget {
  const PromoPopupSheet({
    super.key,
    required this.popup,
    required this.callbacks,
  });

  final PromoPopup popup;
  final PromoPopupCallbacks callbacks;

  @override
  Widget build(BuildContext context) {
    final c = popup.content;
    final p = c.palette;
    final screen = MediaQuery.sizeOf(context).width;
    final k = (screen / 360).clamp(0.85, 1.15);
    final bottom = MediaQuery.viewPaddingOf(context).bottom;
    return Container(
      width: double.infinity,
      decoration: promoBackground(
        p,
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        radius: BorderRadius.vertical(top: Radius.circular(28 * k)),
      ),
      child: Stack(
        children: [
          Padding(
            padding: EdgeInsets.fromLTRB(20 * k, 10 * k, 20 * k, 12 * k + bottom),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 40 * k,
                  height: 4 * k,
                  decoration: BoxDecoration(
                    color: p.text.withValues(alpha: 0.25),
                    borderRadius: BorderRadius.circular(2 * k),
                  ),
                ),
                SizedBox(height: 22 * k),
                Row(
                  children: [
                    if (c.hasImage)
                      Container(
                        width: 72 * k,
                        height: 72 * k,
                        clipBehavior: Clip.antiAlias,
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(18 * k),
                        ),
                        child: PromoImage(
                          url: c.imageUrl,
                          focus: c.imageFocus,
                          drift: false,
                          decodeWidth: 72 * k,
                        ),
                      )
                    else
                      Container(
                        width: 60 * k,
                        height: 60 * k,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: p.accent.withValues(alpha: 0.15),
                        ),
                        child: Icon(
                          promoBadgeIcon(c.icon),
                          size: 28 * k,
                          color: p.accent,
                        ),
                      ),
                    SizedBox(width: 14 * k),
                    Expanded(
                      child: Padding(
                        padding: EdgeInsetsDirectional.only(end: 28 * k),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            if (c.badge.isNotEmpty) ...[
                              PromoBadge(c.badge, palette: p, k: k),
                              SizedBox(height: 6 * k),
                            ],
                            PromoText(
                              c.title,
                              size: 17 * k,
                              weight: FontWeight.w900,
                              color: p.text,
                              accent: p.accent,
                              maxLines: 2,
                              lineHeight: 21 * k,
                            ),
                            if (c.subtitle.isNotEmpty) ...[
                              SizedBox(height: 4 * k),
                              PromoText(
                                c.subtitle,
                                size: 12.5 * k,
                                weight: FontWeight.w500,
                                color: p.text.withValues(alpha: 0.7),
                                accent: p.accent,
                                maxLines: 3,
                                lineHeight: 17 * k,
                              ),
                            ],
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
                SizedBox(height: 18 * k),
                if (c.ctaLabel.isNotEmpty)
                  PromoMainButton(
                    label: c.ctaLabel,
                    icon: c.ctaIcon,
                    palette: p,
                    k: k,
                    onTap: () => callbacks.onExit(PromoPopupExit.cta),
                  ),
                if (popup.secondaryLabel.isNotEmpty)
                  Padding(
                    padding: EdgeInsets.only(top: 4 * k),
                    child: PromoSecondaryButton(
                      label: popup.secondaryLabel,
                      color: p.text,
                      k: k,
                      onTap: () => callbacks.onExit(PromoPopupExit.secondary),
                    ),
                  ),
              ],
            ),
          ),
          PositionedDirectional(
            top: 14 * k,
            end: 14 * k,
            child: PromoCloseButton(
              palette: p,
              k: k,
              onImage: false,
              onTap: () => callbacks.onExit(PromoPopupExit.closeButton),
            ),
          ),
        ],
      ),
    );
  }
}

/// 8. Full screen: the image across the whole screen, fading into colour
/// where the text and button sit.
class PromoPopupFullscreen extends StatelessWidget {
  const PromoPopupFullscreen({
    super.key,
    required this.popup,
    required this.callbacks,
  });

  final PromoPopup popup;
  final PromoPopupCallbacks callbacks;

  @override
  Widget build(BuildContext context) {
    final c = popup.content;
    final p = c.palette;
    final size = MediaQuery.sizeOf(context);
    final pad = MediaQuery.viewPaddingOf(context);
    final k = (size.width / 360).clamp(0.85, 1.2);
    return ColoredBox(
      color: p.background,
      child: Stack(
        fit: StackFit.expand,
        children: [
          PromoImage(
            url: c.imageUrl,
            focus: c.imageFocus,
            drift: false,
            decodeWidth: size.width,
          ),
          IgnorePointer(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [p.background.withValues(alpha: 0), p.background],
                  stops: const [0.4, 1],
                ),
              ),
            ),
          ),
          if (c.effect != PromoEffect.none)
            PromoEffectLayer(effect: c.effect, color: c.effectColor),
          Positioned(
            left: 24 * k,
            right: 24 * k,
            bottom: 24 * k + pad.bottom,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (c.badge.isNotEmpty) ...[
                  PromoBadge(c.badge, palette: p, k: k),
                  SizedBox(height: 10 * k),
                ],
                if (c.title.isNotEmpty)
                  PromoText(
                    c.title,
                    size: 28 * k,
                    weight: FontWeight.w900,
                    color: p.text,
                    accent: p.accent,
                    maxLines: 3,
                    lineHeight: 32 * k,
                  ),
                if (c.subtitle.isNotEmpty) ...[
                  SizedBox(height: 8 * k),
                  PromoText(
                    c.subtitle,
                    size: 14 * k,
                    weight: FontWeight.w500,
                    color: p.text.withValues(alpha: 0.85),
                    accent: p.accent,
                    maxLines: 3,
                    lineHeight: 20 * k,
                  ),
                ],
                SizedBox(height: 20 * k),
                if (c.ctaLabel.isNotEmpty)
                  PromoMainButton(
                    label: c.ctaLabel,
                    icon: c.ctaIcon,
                    palette: p,
                    k: k,
                    height: 52,
                    onTap: () => callbacks.onExit(PromoPopupExit.cta),
                  ),
                if (popup.secondaryLabel.isNotEmpty)
                  Center(
                    child: PromoSecondaryButton(
                      label: popup.secondaryLabel,
                      color: p.text,
                      k: k,
                      onTap: () => callbacks.onExit(PromoPopupExit.secondary),
                    ),
                  ),
              ],
            ),
          ),
          PositionedDirectional(
            top: pad.top + 12 * k,
            end: 16 * k,
            child: PromoCloseButton(
              palette: p,
              k: k,
              onImage: true,
              onTap: () => callbacks.onExit(PromoPopupExit.closeButton),
            ),
          ),
        ],
      ),
    );
  }
}

/// The popup's X: dark glass over an image, a soft tint of the text colour
/// on the card.
class PromoCloseButton extends StatelessWidget {
  const PromoCloseButton({
    super.key,
    required this.palette,
    required this.k,
    required this.onImage,
    required this.onTap,
  });

  final PromoPalette palette;
  final double k;
  final bool onImage;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Semantics(
    button: true,
    label: context.t('common:promo.close'),
    child: Pressable(
      key: const ValueKey('promo-popup-close'),
      onPressed: onTap,
      child: Container(
        width: 32 * k,
        height: 32 * k,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: onImage
              ? Colors.black.withValues(alpha: 0.35)
              : palette.text.withValues(alpha: 0.10),
        ),
        child: Icon(
          LucideIcons.x,
          size: 16 * k,
          color: onImage ? Colors.white : palette.text,
        ),
      ),
    ),
  );
}
