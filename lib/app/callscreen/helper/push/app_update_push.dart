import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';

import '../../../../core/query/query_hooks.dart';
import '../../../../core/utils/log.dart';
import '../../../api/host_status/host_status_queries.dart';
import '../../../api/promo_banner/promo_banner_queries.dart';
import '../../../api/splashscreen/splash_keys.dart';

/// Silent "something the app shows changed" pushes from the admin panel
/// (backend utils/app-silent-push.js), on the `app_config` topic every install
/// subscribes to. An open app reloads at once; nothing is ever shown:
///
///   banners_updated  promo banners (Settings → App banners)
///   config_updated   the runtime config: Host Media (Vibes, video intros)…
///
/// A background isolate does nothing: everything here reloads whenever the
/// app comes back to the front anyway.
abstract final class AppUpdatePush {
  static const topic = 'app_config';
  static const banners = 'banners_updated';
  static const config = 'config_updated';

  /// [type] as PushEnvelope gives it (lowercased).
  static bool matches(String? type) {
    final t = type?.toLowerCase();
    return t == banners || t == config;
  }

  /// Once the FCM token exists (iOS needs APNs first). Idempotent; never throws.
  static Future<void> subscribe() async {
    if (Firebase.apps.isEmpty) return;
    try {
      await FirebaseMessaging.instance.subscribeToTopic(topic);
    } catch (e) {
      Log.w('AppUpdatePush', 'topic subscribe failed: $e');
    }
  }

  /// UI isolate: reload what changed.
  static void onUpdate(String? type) {
    try {
      if (type?.toLowerCase() == banners) {
        invalidatePromoBanners();
        return;
      }
      // The admin's settings: the config itself, then what reads it (the
      // Vibes row is hidden or shown by it; a host's own Vibes may have gone
      // live if review was switched off).
      queryCache.invalidateAll(const [
        SplashKeys.appConfig,
        ['host-statuses'],
      ]);
      invalidateStatusFeed();
    } catch (e) {
      Log.w('AppUpdatePush', 'reload failed: $e');
    }
  }
}
