import 'package:flutter/widgets.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/router/app_router.dart';
import '../../core/utils/log.dart';
import '../api/promo_banner/promo_banner_models.dart';
import '../authscreen/helper/auth_credentials.dart';
import '../authscreen/helper/deep_links.dart';

/// What a banner tap does: an app screen through the same link handling as
/// campaign notifications (so every screen a campaign can open, a banner can
/// too), or a web page in the app's web view or the phone's browser.
abstract final class PromoBannerActions {
  /// App links (swapped in tests).
  @visibleForTesting
  static Future<void> Function(String link) openAppLink = _openAppLink;

  /// Web pages in the browser (swapped in tests).
  @visibleForTesting
  static Future<bool> Function(Uri uri) openBrowser = _openBrowser;

  @visibleForTesting
  static void reset() {
    openAppLink = _openAppLink;
    openBrowser = _openBrowser;
  }

  static Future<void> _openAppLink(String link) =>
      DeepLinks.instance.handle(link);

  static Future<bool> _openBrowser(Uri uri) =>
      launchUrl(uri, mode: LaunchMode.externalApplication);

  static Future<void> open(BuildContext context, PromoBanner banner) =>
      openAction(context, banner.action, title: banner.title);

  /// [action] of a banner or a popup. [title]: the in-app browser's title.
  static Future<void> openAction(
    BuildContext context,
    PromoAction action, {
    String? title,
  }) async {
    try {
      if (action.isApp) {
        final link = action.appLink(AuthCredentials.campaignScheme);
        if (link != null) await openAppLink(link);
        return;
      }
      if (action.isUrl) {
        final url = action.url!;
        if (action.inApp) {
          await context.push(
            Uri(
              path: AppRoutes.webview,
              queryParameters: {
                'url': url,
                if (title != null && title.isNotEmpty) 'title': title,
              },
            ).toString(),
          );
          return;
        }
        await openBrowser(Uri.parse(url));
      }
    } catch (e) {
      Log.w('PromoBanner', 'tap did not open: $e');
    }
  }
}
