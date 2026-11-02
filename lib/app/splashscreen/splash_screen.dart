import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:go_router/go_router.dart';

import '../../core/analytics/events/app_events.dart';
import '../../core/analytics/screen_tracker.dart';
import '../../core/query/query_client.dart';
import '../../core/session/session_store.dart';
import '../../core/utils/scale.dart';
import '../authscreen/helper/auth_navigation.dart';
import '../authscreen/login_screen.dart';
import '../api/splashscreen/splash_api.dart';
import '../api/splashscreen/splash_keys.dart';
import '../api/splashscreen/startup_queries.dart';
import '../component/app_logo.dart';
import '../component/exit_on_double_back.dart';
import 'launch_logo.dart';
import 'onboarding_view.dart';
import 'splash_motion.dart';
import 'splash_palette.dart';
import '../callscreen/helper/call_controller.dart';

/// First screen (RN `app/index.jsx`): logo + load bar for at least 2.5 s.
/// Signed-in users then go straight to their route; everyone else sees the
/// onboarding slides first.
class SplashScreen extends HookWidget {
  const SplashScreen({super.key});

  static const minDuration = Duration(milliseconds: 2500);

  static bool _firstFrameHeld = false;

  /// Called from `main`: keeps the native splash up until the logo is
  /// decoded, so the hand-over shows a complete screen (no logo pop-in).
  static void holdFirstFrame() {
    WidgetsBinding.instance.deferFirstFrame();
    _firstFrameHeld = true;
    Timer(const Duration(seconds: 2), _releaseFirstFrame); // never stuck
  }

  static void _releaseFirstFrame() {
    if (!_firstFrameHeld) return;
    _firstFrameHeld = false;
    WidgetsBinding.instance.allowFirstFrame();
  }

  @override
  Widget build(BuildContext context) {
    final signedIn = useMemoized(
      () => SessionStore.instance.value.isAuthenticated,
    );
    final route = useState<String?>(null);
    final minElapsed = useState(false);
    final left = useRef(false);
    final logoSize = 302.ms;
    final logoKey = useMemoized(GlobalKey.new);

    useEffect(() {
      var alive = true;
      // After the (held) first layout: hooks can't read inherited widgets here.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!context.mounted) return _releaseFirstFrame();
        precacheImage(
          AppLogo.provider(context, logoSize),
          context,
        ).whenComplete(_releaseFirstFrame);
        precacheImage(AppLogo.provider(context, 120.ms), context);
        // The login wordmark: decoded before its fade-in, not during it.
        if (!signedIn) {
          precacheImage(
            AppLogo.provider(context, LoginScreen.logoWidth),
            context,
          );
        }
      });
      // Shown on the first slide; the fallback covers a slow or offline start.
      queryCache.prefetchQuery<List<String>>(
        SplashKeys.hostTopics,
        SplashApi.fetchHostTopics,
        staleDuration: StaleTime.long,
      );
      // Signed in: Home's data loads during the splash's 2.5 s.
      if (signedIn) prefetchStartup();
      nextAuthRoute(confirmAgeGate: true).then((r) {
        final session = SessionStore.instance.value;
        AppEvents.appLaunched(
          signedIn: signedIn,
          role: !signedIn ? null : (session.isExpert ? 'host' : 'client'),
          nextScreen: ScreenTracker.nameFor(Uri.parse(r)),
          onCall: CallController.instance.isOnCall,
        );
        if (alive) route.value = r;
      });
      final timer = Timer(minDuration, () {
        if (!alive) return;
        // Signed out: the logo flies up into the onboarding slides.
        if (!signedIn) LaunchLogo.handOffFrom(logoKey);
        minElapsed.value = true;
      });
      return () {
        alive = false;
        timer.cancel();
      };
    }, const []);

    // Replaces the whole stack: nothing to go back to. Never while a call
    // routed in over the splash (cold-start accept / ring, RN E-62): the
    // call screens leave for Home themselves when it ends.
    void leave() {
      final target = route.value;
      if (target == null || left.value || !context.mounted) return;
      if (CallController.instance.isOnCall) return;
      left.value = true;
      // The logo flies up into the next screen's (Discover's top bar).
      LaunchLogo.handOffFrom(logoKey);
      context.go(target);
    }

    // A call that ended without leaving the splash: go on from here.
    final onCall = useValueListenable(CallController.instance.onCall);
    useEffect(() {
      if (signedIn && !onCall && minElapsed.value && route.value != null) {
        WidgetsBinding.instance.addPostFrameCallback((_) => leave());
      }
      return null;
    }, [minElapsed.value, route.value, onCall]);

    // Follows the app theme (RN light splash palette).
    final palette = SplashPalette.of(context);
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: palette.overlay,
      child: ExitOnDoubleBack(
        child: Material(
          color: palette.bg,
          child: AnimatedSwitcher(
            duration: const Duration(milliseconds: 300),
            child: minElapsed.value && !signedIn
                ? OnboardingView(ready: route.value != null, onFinish: leave)
                : _SplashView(logoSize: logoSize, logoKey: logoKey),
          ),
        ),
      ),
    );
  }
}

class _SplashView extends StatelessWidget {
  const _SplashView({required this.logoSize, required this.logoKey});

  final double logoSize;
  final GlobalKey logoKey;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: EdgeInsets.symmetric(horizontal: 24.ms),
        child: SplashLogo(key: logoKey, size: logoSize),
      ),
    );
  }
}
