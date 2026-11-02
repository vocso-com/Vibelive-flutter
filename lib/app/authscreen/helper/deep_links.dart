import 'dart:async';
import 'dart:io' show Platform;

import 'package:app_links/app_links.dart';
import 'package:flutter/foundation.dart';
import 'package:play_install_referrer/play_install_referrer.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/analytics/events/app_events.dart';
import '../../../core/analytics/screen_tracker.dart';
import '../../../core/router/app_router.dart';
import '../../../core/router/external_open.dart';
import '../../api/authscreen/push_api.dart';
import '../../api/authscreen/push_queries.dart';
import '../../../core/session/session_store.dart';
import '../../../core/storage/app_prefs.dart';
import '../../../core/utils/log.dart';
import 'auth_credentials.dart';
import 'campaign_links.dart';
import 'link_parser.dart';

/// Every link the OS hands the app (RN `index.js` guards, `_layout.jsx`
/// `handleIncomingUrl`, `pushDeeplinkNavigator.js`).
///
/// Links never become router locations directly: share slugs and campaign
/// presets are not routes. A link that can't open yet (signed out, or still
/// on splash / login / onboarding) is parked, and opens once the signed-in
/// app calls [markAppReady].
class DeepLinks {
  DeepLinks._();
  static final DeepLinks instance = DeepLinks._();

  static const _linkKey = 'pending_deeplink';
  static const _referralKey = 'pending_referral_code';
  static const _openUserKey = 'pending_open_user';

  /// Host Home should open (from a share link, campaign or referrer).
  /// Survives restarts and the age-gate / language detour; Home calls
  /// [takeOpenUser] once it has shown it.
  late final ValueNotifier<String?> openUser = ValueNotifier(
    AppPrefs.getString(_openUserKey),
  );

  StreamSubscription<Uri>? _sub;
  ({String url, bool fromPush, Map<String, dynamic>? data})?
  _campaign; // last one wins, as in RN
  String? _route; // a notification tap's destination (push layer)
  bool _ready = false;

  /// Starts listening; the launch link arrives on the same stream.
  void init() {
    _sub ??= AppLinks().uriLinkStream.listen(
      (uri) => unawaited(handle(uri.toString())),
      onError: (Object e) => Log.w('DeepLinks', e),
    );
    SessionStore.instance.addListener(() {
      if (!SessionStore.instance.value.isAuthenticated) _ready = false;
    });
  }

  /// [fromPush]: a notification's link (its tap is logged as `push_opened`
  /// already; analytics only).
  Future<void> handle(String url, {bool fromPush = false}) async {
    ExternalOpen.mark(fromPush ? 'push' : 'link');
    // Call links belong to the call layer.
    if (url.startsWith('${AuthCredentials.shareScheme}://call/')) return;
    final signedIn = SessionStore.instance.value.isAuthenticated;
    void received(String source, {bool referral = false}) {
      if (fromPush) return;
      AppEvents.deeplinkReceived(
        source: source,
        signedIn: signedIn,
        parked: !signedIn || !_ready,
        hasReferral: referral,
      );
    }

    if (url.toLowerCase().startsWith('${AuthCredentials.campaignScheme}://')) {
      received('scheme');
      return queueCampaign(url);
    }
    // https://<site>/app/<screen>: the same screens as the campaign links.
    if (CampaignLinks.fromWeb(url) case final app?) {
      received('web');
      return queueCampaign(app);
    }
    final link = LinkParser.parse(url);
    if (link == null) return;
    if (!signedIn) {
      final referral = LinkParser.referral(url);
      received('share', referral: referral != null);
      if (referral != null) {
        await AppPrefs.setString(_referralKey, referral.withSuffix);
      }
      await AppPrefs.setString(_linkKey, url);
    } else if (!_ready) {
      received('share');
      await AppPrefs.setString(_linkKey, url);
    } else {
      received('share');
      _openShare(link);
    }
  }

  /// `vibecalling://…` from a link or a push tap. [data]: the push's data
  /// (a webview preset reads its page from `url` / `webUrl` / `web_url` when
  /// the link has none; `clicked` is tracked once the link opened).
  void queueCampaign(
    String url, {
    bool fromPush = false,
    Map<String, dynamic>? data,
  }) {
    _campaign = (url: url, fromPush: fromPush, data: data);
    flush();
  }

  /// A notification tap's destination (wallet, profile, history…): opens
  /// once the signed-in app is ready, like links. Last one wins.
  void queueRoute(String location) {
    _route = location;
    flush();
  }

  /// Login screen, once: a referral code (`CODE-R` / `CODE-I` / `CODE`)
  /// from a link opened while signed out.
  String? takeReferral() => _take(_referralKey);

  /// After login, once: the share link opened while signed out.
  String? takeLink() => _take(_linkKey);

  void setOpenUser(String id) {
    openUser.value = id;
    unawaited(AppPrefs.setString(_openUserKey, id));
  }

  String? takeOpenUser() {
    final id = openUser.value;
    if (id != null) {
      openUser.value = null;
      unawaited(AppPrefs.remove(_openUserKey));
    }
    return id;
  }

  /// The signed-in app (Home) is on screen: parked links open now.
  void markAppReady() {
    _ready = true;
    flush();
  }

  void flush() {
    if (!_ready || !SessionStore.instance.value.isAuthenticated) return;
    final campaign = _campaign;
    _campaign = null;
    if (campaign != null) {
      _route = null; // the campaign is where that tap meant to go
      return _openCampaign(campaign.url, campaign.fromPush, campaign.data);
    }
    final route = _route;
    _route = null;
    if (route != null) {
      // Tabs of the Home shell are a `go`; any other screen stacks on Home.
      const tabs = [AppRoutes.home, AppRoutes.explore, AppRoutes.profileTab];
      return _go(route, push: !tabs.any(route.startsWith));
    }
    final url = takeLink();
    final link = url == null ? null : LinkParser.parse(url);
    if (link != null) _openShare(link);
  }

  /// Android Play install referrer (first install from a shared link).
  Future<ReferralCapture?> installReferrer() async {
    if (!Platform.isAndroid) return null;
    try {
      final details = await PlayInstallReferrer.installReferrer;
      return LinkParser.installReferrer(details.installReferrer);
    } catch (e) {
      Log.d('DeepLinks', 'install referrer unavailable: $e');
      return null;
    }
  }

  void _openShare(ShareLink link) {
    final open = link.openUserId;
    if (open != null) {
      AppEvents.deeplinkOpened(
        screen: 'host_profile',
        source: 'share',
        linkType: link.path,
      );
      setOpenUser(open);
      return _go(AppRoutes.home);
    }
    final route = switch (link.path) {
      'invite' || 'referral' => AppRoutes.referral,
      'wallet' => AppRoutes.wallet,
      'profile' || 'me' => AppRoutes.profile,
      'history' => AppRoutes.explore,
      'login' => null, // already signed in
      _ => AppRoutes.home,
    };
    if (route != null) {
      AppEvents.deeplinkOpened(
        screen: ScreenTracker.nameFor(Uri.parse(route)),
        source: 'share',
        linkType: link.path.isEmpty ? 'home' : link.path,
      );
      _go(route, push: route != AppRoutes.home);
    }
  }

  void _openCampaign(String url, bool fromPush, [Map<String, dynamic>? data]) {
    var target = CampaignLinks.resolve(url);
    final route = target.route;
    final isHost = SessionStore.instance.value.isExpert;
    final source = fromPush ? 'push' : 'campaign';
    final linkType = route?.path;
    var fallback = false;
    if (route == null ||
        target.missing.isNotEmpty ||
        (route.hostOnly && !isHost) ||
        route.public) {
      fallback = true;
      Log.w('DeepLinks', 'campaign link opens Home instead: $url');
      target = const CampaignTarget(CampaignLinks.home, {
        'tab': 'DISCOVER',
      }, []);
    }
    var params = target.params;
    if (target.route!.isWebview) {
      final web = CampaignLinks.webUrl(params['url'] ?? _pushWebUrl(data));
      if (web == null) {
        fallback = true;
        params = const {'tab': 'DISCOVER'};
        target = CampaignTarget(CampaignLinks.home, params, const []);
      } else if (!fromPush && !CampaignLinks.isTrustedHost(web)) {
        AppEvents.deeplinkOpened(
          screen: 'external_browser',
          source: source,
          linkType: linkType,
          external: true,
        );
        // A link from outside may only frame our own hosts.
        unawaited(
          launchUrl(Uri.parse(web), mode: LaunchMode.externalApplication),
        );
        if (data != null) trackPushEvent(PushEvent.clicked, data);
        return;
      } else {
        params = {
          'url': web,
          if (params['title'] != null) 'title': params['title']!,
        };
      }
    }
    final open = params['openUserId'];
    if (open != null) setOpenUser(open);
    final path = target.route!.routeFor(isHost: isHost);
    AppEvents.deeplinkOpened(
      screen: ScreenTracker.nameFor(Uri(path: path, queryParameters: params)),
      source: source,
      linkType: linkType,
      fallbackHome: fallback,
    );
    _go(
      Uri(
        path: path,
        queryParameters: params.isEmpty ? null : params,
      ).toString(),
      push: path != AppRoutes.home,
    );
    if (data != null) trackPushEvent(PushEvent.clicked, data);
  }

  /// A push's own page for the webview preset.
  static String? _pushWebUrl(Map<String, dynamic>? data) {
    for (final key in const ['url', 'webUrl', 'web_url']) {
      final v = data?[key]?.toString().trim();
      if (v != null && v.isNotEmpty) return v;
    }
    return null;
  }

  void _go(String location, {bool push = false}) {
    try {
      push ? appRouter.push(location) : appRouter.go(location);
    } catch (e) {
      Log.w('DeepLinks', 'navigation to $location failed: $e');
    }
  }

  String? _take(String key) {
    final value = AppPrefs.getString(key);
    if (value != null) unawaited(AppPrefs.remove(key));
    return value;
  }
}
