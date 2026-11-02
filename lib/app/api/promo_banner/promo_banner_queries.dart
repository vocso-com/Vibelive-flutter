import 'dart:convert';

import 'package:flutter/widgets.dart';
import 'package:flutter_hooks/flutter_hooks.dart';

import '../../../core/query/query_hooks.dart';
import '../../../core/session/session_store.dart';
import '../../../core/storage/app_prefs.dart';
import 'promo_banner_api.dart';
import 'promo_banner_models.dart';

RawQueryKey _key(PromoPlacement placement, String? user) => [
  'promo-banners',
  placement.name,
  user ?? '',
];

/// One placement's banners. Shown from the last saved copy at once, then
/// refreshed: on mount when stale, whenever the app comes back to the front,
/// and the moment the admin changes something (the silent `BANNERS_UPDATED`
/// push → AppUpdatePush → [invalidatePromoBanners]).
QueryResult<PromoBannerFeed, ApiException> usePromoBanners(
  BuildContext context,
  PromoPlacement placement,
) {
  final session = useValueListenable(SessionStore.instance);
  final result = usePersistedQuery<PromoBannerFeed>(
    _key(placement, session.userDocumentId),
    () => PromoBannerApi.fetch(placement),
    context: context,
    enabled: session.isAuthenticated,
    staleDuration: StaleTime.short,
    toJson: (feed) => feed.toJson(),
    fromJson: PromoBannerFeed.fromJson,
  );
  final refetch = useRef(result.refetch)..value = result.refetch;
  useOnAppLifecycleStateChange((_, state) {
    if (state == AppLifecycleState.resumed && session.isAuthenticated) {
      refetch.value();
    }
  });
  return result;
}

/// Every placement reloads (an admin change, pull-to-refresh).
void invalidatePromoBanners() => queryCache.invalidateAll(const [
  ['promo-banners'],
]);

/// Banners a user closed, kept on this phone (by banner id).
abstract final class PromoDismissed {
  static const _key = 'promo_banners_dismissed';
  static final ValueNotifier<Set<String>> ids = ValueNotifier(_read());

  static Set<String> _read() {
    try {
      final raw = AppPrefs.getString(_key);
      if (raw == null) return const {};
      final list = jsonDecode(raw);
      return list is List ? {for (final v in list) '$v'} : const {};
    } catch (_) {
      return const {};
    }
  }

  /// After the prefs are loaded (tests, sign-in): read again.
  static void reload() => ids.value = _read();

  static Future<void> add(String id) async {
    final next = {...ids.value, id};
    ids.value = next;
    // A closed banner stays closed; the list is trimmed so it cannot grow forever.
    final keep = next.length > 200 ? next.skip(next.length - 200) : next;
    await AppPrefs.setString(_key, jsonEncode(keep.toList()));
  }
}
