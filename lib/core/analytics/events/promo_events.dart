import '../analytics.dart';

/// Promo banners (admin → Settings → App banners). Catalog:
/// docs/analytics_events.md. [placement]: `home` / `wallet`.
abstract final class PromoEvents {
  static final _seen = <String>{};

  /// A banner came on screen: once per banner per app session.
  static void bannerViewed({
    required String id,
    required String placement,
    required int position,
  }) {
    if (!_seen.add('$placement|$id')) return;
    Analytics.log('promo_banner_viewed', {
      'banner_id': id,
      'placement': placement,
      'position': position,
    });
  }

  /// A tap. [action]: `app` / `url` / `none`.
  static void bannerTapped({
    required String id,
    required String placement,
    required String action,
  }) => Analytics.log('promo_banner_tapped', {
    'banner_id': id,
    'placement': placement,
    'action': action,
  });

  /// The user closed a closable banner.
  static void bannerDismissed({
    required String id,
    required String placement,
  }) => Analytics.log('promo_banner_dismissed', {
    'banner_id': id,
    'placement': placement,
  });
}
