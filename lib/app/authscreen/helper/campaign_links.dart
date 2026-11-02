import '../../../core/router/app_router.dart';
import '../../hosthub/onboarding/helper/host_steps.dart';
import 'auth_credentials.dart';

/// A query param a campaign screen accepts. [as] renames it to the param
/// the screen reads; [aliases] are accepted on the way in.
class CampaignParam {
  const CampaignParam(
    this.name, {
    this.as,
    this.required = false,
    this.aliases = const [],
  });

  final String name;
  final String? as;
  final bool required;
  final List<String> aliases;
}

/// One admin-panel preset (RN `PUSH_DEEPLINK_ROUTES`). [path] values are
/// referenced by live campaigns: never rename them.
class CampaignRoute {
  const CampaignRoute(
    this.path,
    this.route, {
    this.aliases = const [],
    this.params = const [],
    this.fixed = const {},
    this.hostOnly = false,
    this.public = false,
    this.hostRoute,
  });

  final String path;
  final String route;
  final List<String> aliases;
  final List<CampaignParam> params;

  /// Always sent (e.g. which Home tab to show).
  final Map<String, String> fixed;

  /// Only for users with an expert (host) profile.
  final bool hostOnly;

  /// Reachable signed out (login only).
  final bool public;

  /// Where a host goes instead of [route] (Become a Host: the onboarding
  /// for a client, the profile editor for a host).
  final String? hostRoute;

  /// The screen for the signed-in user.
  String routeFor({required bool isHost}) =>
      isHost && hostRoute != null ? hostRoute! : route;

  bool get isWebview => route == AppRoutes.webview;
}

/// A resolved campaign link: route + params, or what was wrong with it.
class CampaignTarget {
  const CampaignTarget(this.route, this.params, this.missing);

  final CampaignRoute? route;
  final Map<String, String> params;
  final List<String> missing;
}

/// `vibecalling://` campaign / admin-panel links (RN `pushDeeplinks.js`).
/// Adding a screen = one row here + telling the backend the new preset.
abstract final class CampaignLinks {
  static const home = CampaignRoute(
    'home',
    AppRoutes.home,
    aliases: ['', 'discover'],
    fixed: {'tab': 'DISCOVER'},
    // A Discover topic tab (e.g. `topic=Dating advice`). `cat`: the older
    // admin presets' name for it.
    params: [
      CampaignParam('topic', aliases: ['cat']),
    ],
  );
  static const search = CampaignRoute(
    'search',
    AppRoutes.search,
    params: [CampaignParam('q')],
  );

  static const routes = <CampaignRoute>[
    home,
    // `amount`: a pre-filled top-up.
    CampaignRoute(
      'wallet',
      AppRoutes.wallet,
      params: [
        CampaignParam('amount', aliases: ['prefillAmount']),
      ],
    ),
    search,
    CampaignRoute('history', AppRoutes.explore),
    CampaignRoute(
      'profile',
      AppRoutes.home,
      aliases: ['me'],
      fixed: {'tab': 'ME'},
    ),
    CampaignRoute('favourites', AppRoutes.favourites, aliases: ['favorites']),
    CampaignRoute('login', AppRoutes.login, public: true),
    CampaignRoute(
      'expert-profile.php',
      AppRoutes.home,
      aliases: ['expert-profile', 'expert'],
      fixed: {'tab': 'DISCOVER'},
      params: [
        CampaignParam(
          'userid',
          as: 'openUserId',
          required: true,
          aliases: ['documentId', 'handler'],
        ),
      ],
    ),
    // Also "Become a Host" for regular users.
    CampaignRoute('professional-account', AppRoutes.professionalDetails),
    CampaignRoute('approval', AppRoutes.approval, hostOnly: true),
    CampaignRoute('referral', AppRoutes.referral, aliases: ['invite']),
    CampaignRoute('personal-info', AppRoutes.personalInfo),
    CampaignRoute('expertise', AppRoutes.expertise, hostOnly: true),
    CampaignRoute('schedule', AppRoutes.schedule, hostOnly: true),
    CampaignRoute('call-rates', AppRoutes.callRates, hostOnly: true),
    CampaignRoute(
      'verification-badge',
      AppRoutes.verificationBadgeFee,
      hostOnly: true,
    ),
    CampaignRoute('profile-qr', AppRoutes.profileQr, hostOnly: true),
    // A host's online / offline sheet over Home (the old Discover banner's
    // "Manage status" / "Go online"); a client just lands on Home.
    // `host-availability` is the onboarding step, not this.
    CampaignRoute(
      'online-status',
      AppRoutes.home,
      aliases: ['go-online', 'availability-sheet'],
      fixed: {'tab': 'DISCOVER', 'sheet': 'availability'},
    ),
    CampaignRoute('gst-details', AppRoutes.gstDetails),
    CampaignRoute('blocked-users', AppRoutes.blockedUsers),
    CampaignRoute('about', AppRoutes.aboutApp),
    CampaignRoute('support', AppRoutes.support),
    CampaignRoute(
      'page',
      AppRoutes.dynamicPage,
      params: [CampaignParam('slug', required: true), CampaignParam('title')],
    ),
    // Become a Host: the onboarding for a client, the profile editor for a
    // host. One step of it: `host-step?step=voice`, or `host-voice`
    // ([hostSteps]).
    CampaignRoute(
      'become-host',
      AppRoutes.hostOnboarding,
      aliases: ['become-a-host', 'host-onboarding'],
      hostRoute: AppRoutes.professionalDetails,
    ),
    CampaignRoute(
      'host-step',
      AppRoutes.hostOnboarding,
      hostRoute: AppRoutes.professionalDetails,
      params: [CampaignParam('step', required: true)],
    ),
    // Where a rejected video intro sends the host. The clip lives on the voice
    // step, next to the recording, so this lands them on the thing they have to
    // redo rather than on Home. The backend's moderation push uses this name
    // (`screen: 'host-video'`); without the route it fell back to Home.
    CampaignRoute(
      'host-video',
      AppRoutes.hostOnboarding,
      hostRoute: AppRoutes.professionalDetails,
      fixed: {'step': 'voice'},
    ),
    CampaignRoute(
      'verification-badge-info',
      AppRoutes.verificationBadge,
      aliases: ['badge'],
      hostOnly: true,
    ),
    CampaignRoute(
      'verification-badge-form',
      AppRoutes.verificationBadgeForm,
      aliases: ['badge-form'],
      hostOnly: true,
    ),
    CampaignRoute(
      'verification-badge-status',
      AppRoutes.verificationBadgeStatus,
      aliases: ['badge-status'],
      hostOnly: true,
    ),
    // `interests`: the older admin preset for the same picker.
    CampaignRoute(
      'categories',
      AppRoutes.categories,
      aliases: ['topics', 'interests'],
    ),
    CampaignRoute(
      'resources',
      AppRoutes.categoryMenu,
      aliases: ['category-menu'],
      params: [CampaignParam('id', required: true)],
    ),
    // In-app browser; the url is validated before opening (see [webUrl]).
    CampaignRoute(
      'webview',
      AppRoutes.webview,
      params: [CampaignParam('url'), CampaignParam('title')],
    ),
  ];

  /// One link per onboarding step: `host-basic` … `host-guidelines`.
  static final hostSteps = [
    for (final s in HostStep.pages)
      if (s != HostStep.submitted)
        CampaignRoute(
          'host-${s.name}',
          AppRoutes.hostOnboarding,
          hostRoute: AppRoutes.professionalDetails,
          fixed: {'step': s.name},
        ),
  ];

  static final _byPath = {
    for (final r in [...routes, ...hostSteps])
      for (final p in [r.path, ...r.aliases]) p: r,
  };

  static final _appWeb = RegExp(
    '^(?:https?://(?:www\\.)?|${AuthCredentials.shareScheme}://)'
    '${RegExp.escape(AuthCredentials.webDomain)}/app/(.*)\$',
    caseSensitive: false,
  );

  /// The website form of any screen link: `https://<site>/app/wallet?amount=99`
  /// → `vibecalling://wallet?amount=99`. Null for every other link (a bare
  /// `/{slug}` stays a host's share link: handles may be any word).
  static String? fromWeb(String url) {
    final rest = _appWeb.firstMatch(url.trim())?[1];
    return rest == null ? null : '${AuthCredentials.campaignScheme}://$rest';
  }

  /// `vibecalling://wallet?x=1`, `https://x.com/wallet` or `/wallet` → target.
  /// The scheme is never trusted: only the path picks the screen.
  static CampaignTarget resolve(String url) {
    final rest = url
        .trim()
        .replaceFirst(RegExp(r'^https?://[^/?#]+', caseSensitive: false), '')
        .replaceFirst(
          RegExp(r'^[a-z][a-z0-9+.-]*://', caseSensitive: false),
          '',
        )
        .replaceFirst(RegExp(r'^/+'), '')
        .split('#')
        .first;
    final q = rest.indexOf('?');
    final path = (q == -1 ? rest : rest.substring(0, q))
        .replaceAll(RegExp(r'/+$'), '')
        .toLowerCase();
    final query = q == -1
        ? const <String, String>{}
        : Uri.splitQueryString(rest.substring(q + 1));

    final route = _byPath[path];
    if (route == null) return const CampaignTarget(null, {}, []);
    // home?q=… is a search: Home has no search box of its own.
    if (route == home && (query['q'] ?? '').isNotEmpty) {
      return CampaignTarget(search, {'q': query['q']!}, const []);
    }
    final params = {...route.fixed};
    final missing = <String>[];
    for (final spec in route.params) {
      final value = [spec.name, ...spec.aliases]
          .map((n) => query[n]?.trim())
          .firstWhere((v) => v != null && v.isNotEmpty, orElse: () => null);
      if (value != null) {
        params[spec.as ?? spec.name] = value;
      } else if (spec.required) {
        missing.add(spec.name);
      }
    }
    return CampaignTarget(route, params, missing);
  }

  // ── In-app browser rules (RN `webUrl.js`) ──────────────────────────────

  /// Hosts a link from OUTSIDE the app may show inside our frame. Anything
  /// else opens in the system browser, where the real address is visible.
  static const _trustedHosts = ['angrymamba.com', 'vibelive.angrymamba.com'];

  /// `https://x.com`, `https%3A%2F%2Fx.com` or `x.com/page` → loadable
  /// http(s) URL, or null.
  static String? webUrl(String? raw) {
    var value = (raw ?? '').trim();
    for (
      var i = 0;
      i < 3 && RegExp(r'^https?%(25)*3A', caseSensitive: false).hasMatch(value);
      i++
    ) {
      try {
        value = Uri.decodeComponent(value);
      } catch (_) {
        return null;
      }
    }
    if (value.isEmpty ||
        RegExp(r'^https?%', caseSensitive: false).hasMatch(value)) {
      return null;
    }
    final scheme = RegExp(
      r'^([a-z][a-z0-9+.-]*):',
      caseSensitive: false,
    ).firstMatch(value)?[1]?.toLowerCase();
    if (scheme != null && scheme != 'http' && scheme != 'https') return null;
    if (scheme == null) {
      value = 'https://${value.replaceFirst(RegExp(r'^/+'), '')}';
    }
    final host = hostOf(value);
    return host == null || !host.contains('.') ? null : value;
  }

  static String? hostOf(String url) => RegExp(
    r'^https?://([^/?#:]+)',
    caseSensitive: false,
  ).firstMatch(url)?[1]?.toLowerCase().replaceFirst(RegExp(r'^www\.'), '');

  static bool isTrustedHost(String url) {
    final host = hostOf(url);
    return host != null &&
        _trustedHosts.any((s) => host == s || host.endsWith('.$s'));
  }
}
