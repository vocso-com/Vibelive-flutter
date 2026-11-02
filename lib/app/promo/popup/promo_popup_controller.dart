import 'dart:async';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_hooks/flutter_hooks.dart';

import '../../../core/analytics/events/promo_events.dart';
import '../../../core/router/external_open.dart';
import '../../../core/session/session_store.dart';
import '../../../core/utils/log.dart';
import '../../api/promo_banner/promo_banner_queries.dart';
import '../../api/promo_banner/promo_popup_models.dart';
import '../../callscreen/helper/call_controller.dart';
import '../../callscreen/helper/call_navigator.dart';
import '../../update/update_notice.dart';
import '../promo_banner_actions.dart';
import '../templates/promo_markup.dart';
import 'popup_templates.dart';
import 'promo_popup_presenter.dart';
import 'promo_popup_rules.dart';

/// The admin's app-open popup (admin → Banners & popups → Popups).
///
/// An "app open" is the first Home after a cold start (or a sign-in) and a
/// return to the app after `openGapMinutes` in the background. Each open
/// shows at most one popup: the first one the rules allow
/// ([PromoPopupRulesCheck]), after its delay, and only when nothing else is
/// going on: Home on top with no sheet over it, no call, no update notice,
/// and not an open that came from a notification or a link (the user came
/// for something else). If it is still not free after [safeWait] the popup
/// waits for the next open.
class PromoPopupController {
  PromoPopupController._();
  static final instance = PromoPopupController._();

  /// The clock (tests).
  @visibleForTesting
  static DateTime Function() now = DateTime.now;

  /// The feed (tests).
  @visibleForTesting
  static Future<PromoPopupFeed> Function() load = ensurePromoPopups;

  /// How long a due popup waits for the screen to be free.
  @visibleForTesting
  static Duration safeWait = const Duration(seconds: 8);

  /// How long an image may take to load before its popup is skipped.
  static const imageWait = Duration(seconds: 6);

  BuildContext? _home;
  bool _opened = false;
  bool _showing = false;
  bool _listening = false;
  DateTime? _backgroundAt;
  int _gapMinutes = 30;
  int _seq = 0;
  String _cause = 'launch';

  /// Home is on screen (from [usePromoPopups]).
  void attach(BuildContext home) {
    _home = home;
    if (!_listening) {
      _listening = true;
      SessionStore.instance.signedIn.addListener(_onSession);
    }
    if (_opened) return;
    _opened = true;
    unawaited(_open('launch'));
  }

  void detach(BuildContext home) {
    if (!identical(_home, home)) return;
    _home = null;
    _seq++; // anything still waiting gives up
  }

  void lifecycle(AppLifecycleState state) {
    switch (state) {
      case AppLifecycleState.paused || AppLifecycleState.hidden:
        _backgroundAt ??= now();
      case AppLifecycleState.resumed:
        final away = _backgroundAt;
        _backgroundAt = null;
        if (away == null || _home == null) return;
        if (now().difference(away) >= Duration(minutes: _gapMinutes)) {
          unawaited(_open('resume'));
        }
      case AppLifecycleState.inactive || AppLifecycleState.detached:
        break;
    }
  }

  /// A sign-out: the next sign-in's first Home is an app open again.
  void _onSession() {
    if (SessionStore.instance.signedIn.value) return;
    _opened = false;
    _seq++;
  }

  Future<void> _open(String cause) async {
    if (_showing) return;
    final seq = ++_seq;
    _cause = cause;
    final openedAt = now();
    if (!SessionStore.instance.value.isAuthenticated) return;

    PromoPopupFeed feed;
    try {
      feed = await load();
    } catch (e) {
      Log.w('PromoPopup', 'feed: $e');
      feed = peekPromoPopups() ?? PromoPopupFeed.empty;
    }
    if (seq != _seq || !feed.enabled) return;
    _gapMinutes = feed.openGapMinutes;
    final pick = PromoPopupRulesCheck.pick(
      feed.popups,
      PromoPopupStore.of,
      now(),
    );
    if (pick == null) return;

    final delay =
        Duration(seconds: pick.rules.delaySeconds) - now().difference(openedAt);
    if (delay > Duration.zero) await Future<void>.delayed(delay);
    if (seq != _seq) return;

    // An open from a notification or a link is the user's errand.
    final since = openedAt.subtract(const Duration(seconds: 15));
    final deadline = now().add(safeWait);
    while (true) {
      if (ExternalOpen.since(since)) return _skip(pick, 'external_open');
      final busy = blocker();
      if (busy == null) break;
      if (!now().isBefore(deadline)) return _skip(pick, busy);
      await Future<void>.delayed(const Duration(milliseconds: 500));
      if (seq != _seq) return;
    }

    final ctx = _home;
    if (ctx == null || !ctx.mounted) return;
    if (pick.content.hasImage) {
      final loaded = await _precache(ctx, pick);
      if (seq != _seq) return;
      if (!loaded && pick.template.needsImage) {
        return _skip(pick, 'image_failed');
      }
    }
    final late = blocker();
    if (late != null) return _skip(pick, late);
    if (ExternalOpen.since(since)) return _skip(pick, 'external_open');
    await _present(_home!, pick);
  }

  /// Why a popup cannot show right now, or null when the screen is free.
  @visibleForTesting
  String? blocker() {
    final ctx = _home;
    if (ctx == null || !ctx.mounted) return 'busy';
    if (!SessionStore.instance.value.isAuthenticated) return 'busy';
    if (CallController.instance.isOnCall || CallNavigator.onCallRoute) {
      return 'call';
    }
    if (UpdateNoticeHost.isShowing) return 'update_notice';
    final route = ModalRoute.of(ctx);
    if (route == null || !route.isCurrent) return 'busy';
    return null;
  }

  void _skip(PromoPopup p, String reason) => PromoEvents.popupSkipped(
    id: p.id,
    template: p.template.wire,
    reason: reason,
  );

  /// Loads the image at the size the template draws it; false on failure.
  Future<bool> _precache(BuildContext ctx, PromoPopup p) async {
    final url = p.content.imageUrl!;
    final size = MediaQuery.sizeOf(ctx);
    final card = PromoPopupCard.widthFor(size.width);
    final width = switch (p.template) {
      PromoPopupTemplate.fullscreen => size.width,
      PromoPopupTemplate.celebration => 96 * card / PromoPopupCard.designWidth,
      PromoPopupTemplate.spotlight => 128 * card / PromoPopupCard.designWidth,
      PromoPopupTemplate.bottomSheet =>
        72 * (size.width / 360).clamp(0.85, 1.15),
      _ => card,
    };
    final memWidth = (width * MediaQuery.devicePixelRatioOf(ctx)).round();
    var failed = false;
    try {
      await precacheImage(
        ResizeImage.resizeIfNeeded(
          memWidth,
          null,
          CachedNetworkImageProvider(url),
        ),
        ctx,
        onError: (_, _) => failed = true,
      ).timeout(imageWait);
    } catch (_) {
      return false;
    }
    return !failed;
  }

  Future<void> _present(BuildContext ctx, PromoPopup p) async {
    _showing = true;
    final shownAt = now();
    try {
      await PromoPopupStore.shown(p.id, shownAt);
      if (!ctx.mounted) return;
      PromoEvents.popupShown(
        id: p.id,
        template: p.template.wire,
        opens: PromoPopupStore.of(p.id).shown,
        cause: _cause,
      );
      final exit = await PromoPopupPresenter.show(
        ctx,
        p,
        onCopied: () => PromoEvents.codeCopied(
          id: p.id,
          where: 'popup',
          template: p.template.wire,
        ),
      );
      final acted = exit == PromoPopupExit.cta;
      await PromoPopupStore.closed(p.id, now(), acted: acted);
      if (acted) {
        PromoEvents.popupCtaTapped(
          id: p.id,
          template: p.template.wire,
          action: p.content.action.type,
        );
        final home = _home;
        if (home == null || p.content.action.isNone) return;
        if (!home.mounted) return;
        await PromoBannerActions.openAction(
          home,
          p.content.action,
          title: PromoMarkup.plain(p.content.title),
        );
      } else {
        PromoEvents.popupClosed(
          id: p.id,
          template: p.template.wire,
          how: exit.wire,
          secondsOpen: now().difference(shownAt).inSeconds,
        );
      }
    } catch (e) {
      Log.w('PromoPopup', 'show: $e');
    } finally {
      _showing = false;
    }
  }

  @visibleForTesting
  void debugReset() {
    _home = null;
    _opened = false;
    _showing = false;
    _backgroundAt = null;
    _gapMinutes = 30;
    _seq++;
    now = DateTime.now;
    load = ensurePromoPopups;
    safeWait = const Duration(seconds: 8);
  }
}

/// Home's hook: the first Home (and every later app open) may show the
/// admin's popup.
void usePromoPopups(BuildContext context) {
  final controller = PromoPopupController.instance;
  useEffect(() {
    controller.attach(context);
    return () => controller.detach(context);
  }, const []);
  useOnAppLifecycleStateChange((_, state) => controller.lifecycle(state));
}
