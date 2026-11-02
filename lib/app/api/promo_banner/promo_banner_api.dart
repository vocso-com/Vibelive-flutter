import '../../../core/network/api_client.dart';
import 'promo_banner_models.dart';
import 'promo_popup_models.dart';

/// `GET /app-banners?placement=home|wallet`: the live banners for this user.
/// `GET /app-popups`: the live app-open popups for this user.
abstract final class PromoBannerApi {
  static Future<PromoBannerFeed> fetch(PromoPlacement placement) async =>
      PromoBannerFeed.fromJson(
        await ApiClient.get(
          '/app-banners',
          query: {'placement': placement.name},
        ),
      );

  static Future<PromoPopupFeed> popups() async =>
      PromoPopupFeed.fromJson(await ApiClient.get('/app-popups'));
}
