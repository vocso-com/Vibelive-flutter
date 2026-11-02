import 'package:flutter/material.dart';

import '../../../core/analytics/screen_tracker.dart';
import '../../api/promo_banner/promo_popup_models.dart';
import 'popup_templates.dart';

/// Puts one popup on screen and says how it went away.
///
/// - Cards (offer, poster, celebration, flash sale, spotlight, announcement):
///   over a 60% dim, they grow in with a soft overshoot (0.9 → 1) and fade;
///   they leave fading and settling to 0.96.
/// - Bottom sheet: slides up.
/// - Full screen: fades in while settling from 1.04 to 1.
///
/// Each is a named screen (`promo_popup_<template>`) for analytics. Back
/// closes any of them; a tap outside only when the admin allowed it.
abstract final class PromoPopupPresenter {
  /// A small overshoot (≈ 6%), softer than Curves.easeOutBack.
  static const _grow = Cubic(0.34, 1.32, 0.64, 1);

  static Future<PromoPopupExit> show(
    BuildContext context,
    PromoPopup popup, {
    VoidCallback? onCopied,
  }) async {
    final name = ScreenTracker.sheet('promo_popup_${popup.template.wire}');
    final still = MediaQuery.disableAnimationsOf(context);
    PromoPopupExit? result;
    if (popup.template == PromoPopupTemplate.bottomSheet) {
      result = await showModalBottomSheet<PromoPopupExit>(
        context: context,
        routeSettings: name,
        isScrollControlled: true,
        useSafeArea: false,
        backgroundColor: Colors.transparent,
        barrierColor: Colors.black.withValues(alpha: 0.6),
        isDismissible: popup.rules.closeOnBackdrop,
        enableDrag: popup.rules.closeOnBackdrop,
        builder: (ctx) => PromoPopupSheet(
          popup: popup,
          callbacks: PromoPopupCallbacks(
            onExit: (how) => Navigator.of(ctx).pop(how),
            onCopied: onCopied,
          ),
        ),
      );
      // Swiped down or tapped outside.
      return result ?? PromoPopupExit.backdrop;
    }

    final fullscreen = popup.template == PromoPopupTemplate.fullscreen;
    result = await showGeneralDialog<PromoPopupExit>(
      context: context,
      routeSettings: name,
      barrierDismissible: false,
      barrierColor: fullscreen ? Colors.black : Colors.transparent,
      transitionDuration: Duration(milliseconds: still ? 120 : 380),
      pageBuilder: (ctx, _, _) {
        final callbacks = PromoPopupCallbacks(
          onExit: (how) => Navigator.of(ctx).pop(how),
          onCopied: onCopied,
        );
        if (fullscreen) {
          return PromoPopupFullscreen(popup: popup, callbacks: callbacks);
        }
        return _CenteredPopup(popup: popup, callbacks: callbacks);
      },
      transitionBuilder: (ctx, animation, _, child) {
        if (still) return FadeTransition(opacity: animation, child: child);
        if (fullscreen) {
          return FadeTransition(
            opacity: CurvedAnimation(parent: animation, curve: Curves.easeOut),
            child: ScaleTransition(
              scale: Tween(begin: 1.04, end: 1.0).animate(
                CurvedAnimation(parent: animation, curve: Curves.easeOutCubic),
              ),
              child: child,
            ),
          );
        }
        // The dim fades; the card itself grows in _CenteredPopup.
        return child;
      },
    );
    // Android back (the route popped without a value).
    return result ?? PromoPopupExit.back;
  }
}

/// A card in the middle over its own dim (a tap on the dim closes it when
/// allowed), growing in with the route's animation.
class _CenteredPopup extends StatelessWidget {
  const _CenteredPopup({required this.popup, required this.callbacks});

  final PromoPopup popup;
  final PromoPopupCallbacks callbacks;

  @override
  Widget build(BuildContext context) {
    final route = ModalRoute.of(context);
    final animation = route?.animation ?? kAlwaysCompleteAnimation;
    final still = MediaQuery.disableAnimationsOf(context);
    final size = MediaQuery.sizeOf(context);
    final pad = MediaQuery.viewPaddingOf(context);
    final width = PromoPopupCard.widthFor(size.width);
    final fade = CurvedAnimation(
      parent: animation,
      curve: Curves.easeOut,
      reverseCurve: Curves.easeIn,
    );
    return Stack(
      children: [
        Positioned.fill(
          child: FadeTransition(
            opacity: fade,
            child: GestureDetector(
              key: const ValueKey('promo-popup-backdrop'),
              behavior: HitTestBehavior.opaque,
              onTap: popup.rules.closeOnBackdrop
                  ? () => callbacks.onExit(PromoPopupExit.backdrop)
                  : null,
              child: ColoredBox(color: Colors.black.withValues(alpha: 0.6)),
            ),
          ),
        ),
        Center(
          child: Padding(
            padding: EdgeInsets.only(top: pad.top, bottom: pad.bottom),
            child: AnimatedBuilder(
              animation: animation,
              builder: (_, child) {
                final v = animation.value;
                final leaving = animation.status == AnimationStatus.reverse;
                final scale = still
                    ? 1.0
                    : leaving
                    ? 0.96 + 0.04 * v
                    : 0.9 + 0.1 * PromoPopupPresenter._grow.transform(v);
                return Opacity(
                  opacity: Curves.easeOut.transform(v.clamp(0.0, 1.0)),
                  child: Transform.scale(scale: scale, child: child),
                );
              },
              child: Material(
                type: MaterialType.transparency,
                child: PromoPopupCard(
                  popup: popup,
                  width: width,
                  maxHeight: size.height - pad.vertical - 48,
                  callbacks: callbacks,
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}
