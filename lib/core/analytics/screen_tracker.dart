import 'package:flutter/widgets.dart';
import 'package:go_router/go_router.dart';

import 'analytics.dart';

/// Logs a screen view for every screen the user sees, to Firebase and Meta:
///
/// - **pages**: every route change of the app router (push, go, pop,
///   redirect), named by [nameFor];
/// - **tabs and steps** inside a page (Home's Discover / History / Me, the
///   host onboarding steps): the page sets its current sub-screen with
///   [setSubScreen], which also names the page when the user comes back to
///   it;
/// - **sheets and dialogs**: opened with `routeSettings: ScreenTracker.sheet(
///   'name')`, seen by [observer]; closing one logs what is under it again;
/// - **in-page views** (a login step, an inline panel): [view].
///
/// A screen is never logged twice in a row.
abstract final class ScreenTracker {
  static GoRouter? _router;
  static String? _pagePath;
  static String? _pageName;
  static String? _last;
  static final _sub = <String, String>{};
  static final _sheets = <Route<dynamic>, String>{};

  /// For `GoRouter.observers`: sheets and dialogs.
  static final NavigatorObserver observer = _SheetObserver();

  /// Starts following [router] (after it is created).
  static void attach(GoRouter router) {
    if (identical(_router, router)) return;
    _router?.routerDelegate.removeListener(_onRoute);
    _router = router;
    router.routerDelegate.addListener(_onRoute);
    _onRoute();
  }

  /// Route settings naming a sheet / dialog for [observer].
  static RouteSettings sheet(String name) => RouteSettings(name: name);

  /// A view inside the current page (no route change).
  static void view(String name, [Map<String, Object?> params = const {}]) =>
      _log(name, params);

  /// The page at [path] now shows [name] (a tab or a step). Logged at once
  /// when that page is on top; remembered for when the user returns to it.
  static void setSubScreen(
    String path,
    String name, [
    Map<String, Object?> params = const {},
  ]) {
    _sub[path] = name;
    if (_pagePath == path && _sheets.isEmpty) {
      _pageName = name;
      _log(name, params);
    }
  }

  /// The page at [path] went away (call from its dispose): its sub-screen
  /// is forgotten.
  static void clearSubScreen(String path) => _sub.remove(path);

  /// Screen name of a route location (snake_case, Firebase-safe).
  static String nameFor(Uri uri) {
    final path = uri.path;
    final q = uri.queryParameters;
    final known = _names[path];
    if (known != null) return known;
    if (path == '/home') return 'home_${_homeTab(q['tab'])}';
    // One chat, whoever it is with (no ids in screen names).
    if (path.startsWith('/chat/')) return 'chat';
    final slug = path
        .replaceAll(RegExp(r'[^a-zA-Z0-9]+'), '_')
        .replaceAll(RegExp(r'^_+|_+$'), '');
    return slug.isEmpty ? 'unknown' : 'route_$slug';
  }

  static String _homeTab(String? tab) => switch (tab?.toLowerCase()) {
    'chats' || 'chat' || 'messages' => 'chats',
    'history' || 'logs' || 'explore' => 'history',
    'me' || 'profile' => 'me',
    _ => 'discover',
  };

  /// Route path → screen name (same paths as `AppRoutes`).
  static const _names = {
    '/': 'splash',
    '/auth/login': 'login',
    '/onboarding/age': 'onboarding_age_gate',
    '/onboarding/language': 'onboarding_language',
    '/search': 'search',
    '/call': 'call',
    '/call/incoming': 'incoming_call',
    '/wallet': 'wallet',
    '/webview': 'webview',
    '/me/profile': 'my_profile',
    '/me/personal-info': 'personal_info',
    '/me/professional-details': 'host_profile_edit',
    '/me/call-rates': 'host_call_rates',
    '/me/approval': 'host_approval_status',
    '/me/categories': 'categories',
    '/me/category-menu': 'category_menu',
    '/me/expertise': 'host_expertise',
    '/me/schedule': 'host_schedule',
    '/me/favourites': 'favourites',
    '/me/blocked-users': 'blocked_users',
    '/me/referral': 'referral',
    '/me/gst-details': 'gst_details',
    '/me/profile-qr': 'host_profile_qr',
    '/me/dynamic-page': 'dynamic_page',
    '/me/about-app': 'about_app',
    '/me/support': 'support',
    '/me/verification-badge': 'verification_badge',
    '/me/verification-badge-form': 'verification_badge_form',
    '/me/verification-badge-fee': 'verification_badge_fee',
    '/me/verification-badge-status': 'verification_badge_status',
    '/host/onboarding': 'host_onboarding',
    '/host/schedule': 'host_schedule',
    '/host/rates': 'host_call_rates',
  };

  /// Extra parameters worth keeping per page (which CMS page, which link).
  static Map<String, Object?> _paramsFor(Uri uri) {
    final q = uri.queryParameters;
    return switch (uri.path) {
      '/me/dynamic-page' => {'slug': q['slug']},
      '/me/category-menu' => {'menu_id': q['id']},
      '/webview' => {'url': q['url']},
      '/me/professional-details' => {'step': q['step']},
      '/host/onboarding' => {'step': q['step']},
      _ => const {},
    };
  }

  static void _onRoute() {
    final router = _router;
    if (router == null) return;
    final Uri uri;
    try {
      uri = router.state.uri;
    } catch (_) {
      return; // no configuration yet
    }
    final path = uri.path;
    final pageChanged = path != _pagePath;
    _pagePath = path;
    _pageName = _sub[path] ?? nameFor(uri);
    if (_sheets.isEmpty || pageChanged) _log(_pageName!, _paramsFor(uri));
  }

  static void _sheetOpened(Route<dynamic> route, String name) {
    _sheets[route] = name;
    _log(name);
  }

  static void _sheetClosed(Route<dynamic> route) {
    if (_sheets.remove(route) == null) return;
    final under = _sheets.isNotEmpty ? _sheets.values.last : _pageName;
    if (under != null) _log(under);
  }

  static void _log(String name, [Map<String, Object?> params = const {}]) {
    if (name == _last) return;
    _last = name;
    Analytics.screen(name, params);
  }

  @visibleForTesting
  static void debugReset() {
    _router?.routerDelegate.removeListener(_onRoute);
    _router = null;
    _pagePath = null;
    _pageName = null;
    _last = null;
    _sub.clear();
    _sheets.clear();
  }
}

/// Named popup routes (sheets, dialogs) as screens.
class _SheetObserver extends NavigatorObserver {
  static String? _nameOf(Route<dynamic> route) {
    if (route is! PopupRoute) return null;
    final name = route.settings.name;
    return name == null || name.isEmpty || name.startsWith('/') ? null : name;
  }

  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) {
    final name = _nameOf(route);
    if (name != null) ScreenTracker._sheetOpened(route, name);
  }

  @override
  void didPop(Route<dynamic> route, Route<dynamic>? previousRoute) =>
      ScreenTracker._sheetClosed(route);

  @override
  void didRemove(Route<dynamic> route, Route<dynamic>? previousRoute) =>
      ScreenTracker._sheetClosed(route);

  @override
  void didReplace({Route<dynamic>? newRoute, Route<dynamic>? oldRoute}) {
    if (oldRoute != null) ScreenTracker._sheetClosed(oldRoute);
    if (newRoute == null) return;
    final name = _nameOf(newRoute);
    if (name != null) ScreenTracker._sheetOpened(newRoute, name);
  }
}
