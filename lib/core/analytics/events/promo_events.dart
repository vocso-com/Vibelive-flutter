import '../analytics.dart';

/// Promo banners and app-open popups (admin → Banners & popups). Catalog:
/// docs/analytics_events.md. [placement]: `home` / `wallet`; [template]: the
/// admin's template key (`spotlight`, `offer_card`…, `custom`).
abstract final class PromoEvents {
  static final _seen = <String>{};

  // ── Banners ────────────────────────────────────────────────────────────

  /// A banner came on screen: once per banner per app session.
  static void bannerViewed({
    required String id,
    required String placement,
    required int position,
    String? template,
  }) {
    if (!_seen.add('$placement|$id')) return;
    Analytics.log('promo_banner_viewed', {
      'banner_id': id,
      'placement': placement,
      'position': position,
      'template': _template(template),
    });
  }

  /// A tap. [action]: `app` / `url` / `none`.
  static void bannerTapped({
    required String id,
    required String placement,
    required String action,
    String? template,
  }) => Analytics.log('promo_banner_tapped', {
    'banner_id': id,
    'placement': placement,
    'action': action,
    'template': _template(template),
  });

  /// The user closed a closable banner.
  static void bannerDismissed({
    required String id,
    required String placement,
  }) => Analytics.log('promo_banner_dismissed', {
    'banner_id': id,
    'placement': placement,
  });

  /// A coupon code was copied. [where]: `home` / `wallet` / `popup`.
  static void codeCopied({
    required String id,
    required String where,
    String? template,
  }) => Analytics.log(
    where == 'popup' ? 'promo_popup_code_copied' : 'promo_code_copied',
    {
      where == 'popup' ? 'popup_id' : 'banner_id': id,
      if (where != 'popup') 'placement': where,
      'template': _template(template),
    },
  );

  // ── App-open popups ────────────────────────────────────────────────────

  /// A popup came on screen. [opens]: how many times it has now been shown
  /// on this phone; [cause]: `launch` / `resume`.
  static void popupShown({
    required String id,
    required String template,
    required int opens,
    required String cause,
  }) => Analytics.log('promo_popup_shown', {
    'popup_id': id,
    'template': template,
    'show_count': opens,
    'cause': cause,
  });

  /// The main button. [action]: `app` / `url` / `none`.
  static void popupCtaTapped({
    required String id,
    required String template,
    required String action,
  }) => Analytics.log('promo_popup_cta_tapped', {
    'popup_id': id,
    'template': template,
    'action': action,
  });

  /// Closed without the main button. [how]: `close_button` / `secondary` /
  /// `backdrop` / `back` / `expired`.
  static void popupClosed({
    required String id,
    required String template,
    required String how,
    required int secondsOpen,
  }) => Analytics.log('promo_popup_closed', {
    'popup_id': id,
    'template': template,
    'how': how,
    'seconds_open': secondsOpen,
  });

  /// One was due but did not show this app open. [reason]: `busy` (a sheet,
  /// another screen or a call), `external_open` (a push / link opened the
  /// app), `image_failed`, `update_notice`.
  static void popupSkipped({
    required String id,
    required String template,
    required String reason,
  }) => Analytics.log('promo_popup_skipped', {
    'popup_id': id,
    'template': template,
    'reason': reason,
  });

  static String _template(String? t) =>
      t == null || t.isEmpty ? 'custom' : t;
}
