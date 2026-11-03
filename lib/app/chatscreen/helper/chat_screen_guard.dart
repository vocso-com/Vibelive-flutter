import 'dart:async';
import 'dart:io' show Platform;

import 'package:flutter/widgets.dart';
import 'package:screen_protector/screen_protector.dart';

import '../../../core/utils/log.dart';
import '../../callscreen/helper/call_controller.dart';

/// Screenshot protection for chat screens (contract §6), only while one is
/// visible and `screenshotProtection` is on:
///
/// - Android: `FLAG_SECURE` (screenshots refused, recordings black).
/// - iOS: no app can refuse a screenshot; while the screen is recorded or
///   mirrored, [captured] is true and `ChatSecureZone` covers the chat.
///
/// "Visible" is decided by [observer] (the router's): a zone's route must be
/// the top full-screen route. A sheet over a chat keeps it protected; a
/// page pushed over it (the wallet, a call) does not.
///
/// The call layer also owns `FLAG_SECURE` during a video call: this never
/// clears it while one runs, and sets it again once a call ends with a chat
/// still on screen.
class ChatScreenGuard {
  ChatScreenGuard._();
  static final ChatScreenGuard instance = ChatScreenGuard._();

  static const _tag = 'ChatGuard';

  /// Add to the router's observers: tracks the top full-screen route.
  final observer = ChatRouteObserver();

  /// iOS: the screen is being recorded / mirrored while a chat shows.
  final captured = ValueNotifier<bool>(false);

  /// Platform calls; swapped in tests.
  @visibleForTesting
  static ChatSecurePlatform platform = const _DevicePlatform();

  final _wanting = <Object>{};
  bool _secure = false;
  bool _listening = false;

  bool get isSecure => _secure;

  /// [token]'s chat zone is visible with protection on ([want]) or not.
  void set(Object token, bool want) {
    final changed = want ? _wanting.add(token) : _wanting.remove(token);
    if (changed) _apply();
  }

  bool get _callHoldsFlag {
    final s = CallController.instance.value;
    return s.phase.isActive && s.isVideo;
  }

  void _apply() {
    final want = _wanting.isNotEmpty;
    if (want == _secure) return;
    _secure = want;
    if (want) {
      unawaited(platform.secure(true));
      _listen(true);
    } else {
      // A video call keeps its own flag.
      if (!_callHoldsFlag) unawaited(platform.secure(false));
      _listen(false);
    }
  }

  void _listen(bool on) {
    if (on == _listening) return;
    _listening = on;
    if (on) {
      CallController.instance.session.addListener(_onCall);
      unawaited(
        platform.watchCapture((value) => captured.value = _secure && value),
      );
    } else {
      CallController.instance.session.removeListener(_onCall);
      unawaited(platform.unwatchCapture());
      captured.value = false;
    }
  }

  /// A call ended under a chat that is still on screen: the call layer
  /// cleared the flag, so set it again (after it did).
  void _onCall() {
    if (!_secure || _callHoldsFlag) return;
    Future<void>.delayed(const Duration(milliseconds: 300), () {
      if (_secure && !_callHoldsFlag) unawaited(platform.secure(true));
    });
  }

  @visibleForTesting
  void debugReset() {
    _wanting.clear();
    _secure = false;
    if (_listening) {
      CallController.instance.session.removeListener(_onCall);
      _listening = false;
    }
    captured.value = false;
  }

  static void log(Object e) => Log.w(_tag, e);
}

/// The native side, behind a seam.
abstract class ChatSecurePlatform {
  const ChatSecurePlatform();

  /// Android FLAG_SECURE on / off (no-op elsewhere).
  Future<void> secure(bool on);

  /// iOS: [onChange] with the capture state now and on every change.
  Future<void> watchCapture(void Function(bool captured) onChange);
  Future<void> unwatchCapture();
}

class _DevicePlatform extends ChatSecurePlatform {
  const _DevicePlatform();

  @override
  Future<void> secure(bool on) async {
    if (!Platform.isAndroid) return;
    try {
      on
          ? await ScreenProtector.preventScreenshotOn()
          : await ScreenProtector.preventScreenshotOff();
    } catch (e) {
      ChatScreenGuard.log('secure($on): $e');
    }
  }

  @override
  Future<void> watchCapture(void Function(bool captured) onChange) async {
    if (!Platform.isIOS) return;
    // The plugin's listener calls are fire-and-forget: catch their errors
    // in a zone, never as an uncaught error.
    runZonedGuarded(
      () => ScreenProtector.addListener(null, onChange),
      (e, _) => ChatScreenGuard.log('watchCapture: $e'),
    );
    try {
      onChange(await ScreenProtector.isRecording());
    } catch (e) {
      ChatScreenGuard.log('isRecording: $e');
    }
  }

  @override
  Future<void> unwatchCapture() async {
    if (!Platform.isIOS) return;
    runZonedGuarded(
      ScreenProtector.removeListener,
      (e, _) => ChatScreenGuard.log('unwatchCapture: $e'),
    );
  }
}

/// The root navigator's routes, to know which full-screen route is on top.
class ChatRouteObserver extends NavigatorObserver {
  final _routes = <Route<dynamic>>[];

  /// The top route that covers the screen (sheets and dialogs don't).
  final top = ValueNotifier<Route<dynamic>?>(null);

  void _changed() {
    // A navigator torn down without popping (tests, a hot restart) leaves
    // its routes behind, inactive.
    _routes.removeWhere((r) => r.navigator == null);
    Route<dynamic>? cover;
    for (final r in _routes.reversed) {
      if (r is ModalRoute && r.opaque) {
        cover = r;
        break;
      }
    }
    if (!identical(top.value, cover)) top.value = cover;
  }

  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) {
    _routes.add(route);
    _changed();
  }

  @override
  void didPop(Route<dynamic> route, Route<dynamic>? previousRoute) {
    _routes.remove(route);
    _changed();
  }

  @override
  void didRemove(Route<dynamic> route, Route<dynamic>? previousRoute) {
    _routes.remove(route);
    _changed();
  }

  @override
  void didReplace({Route<dynamic>? newRoute, Route<dynamic>? oldRoute}) {
    final i = oldRoute == null ? -1 : _routes.indexOf(oldRoute);
    if (i >= 0 && newRoute != null) {
      _routes[i] = newRoute;
    } else {
      if (oldRoute != null) _routes.remove(oldRoute);
      if (newRoute != null) _routes.add(newRoute);
    }
    _changed();
  }
}
