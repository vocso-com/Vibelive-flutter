import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../app/api/authscreen/auth_models.dart';
import '../../app/authscreen/age_gate_screen.dart';
import '../../app/authscreen/language_screen.dart';
import '../../app/authscreen/login_screen.dart';
import '../../app/callscreen/call/call_screen.dart';
import '../../app/callscreen/call/incoming_call_screen.dart';
import '../../app/client/blocked_users/blocked_users_screen.dart';
import '../../app/client/favourites/favourites_screen.dart';
import '../../app/client/gst_details/gst_details_screen.dart';
import '../../app/client/personal_info/personal_info_screen.dart';
import '../../app/client/referral/referral_screen.dart';
import '../../app/component/app_logo.dart';
import '../../app/homescreen/helper/home_controller.dart';
import '../../app/homescreen/home_screen.dart';
import '../../app/hosthub/approval/host_approval_screen.dart';
import '../../app/hosthub/badge/host_badge_fee_screen.dart';
import '../../app/hosthub/badge/host_badge_form_screen.dart';
import '../../app/hosthub/badge/host_badge_screen.dart';
import '../../app/hosthub/hub/host_profile_qr_screen.dart';
import '../../app/hosthub/onboarding/helper/host_steps.dart';
import '../../app/hosthub/onboarding/host_onboarding_screen.dart';
import '../../app/listingflow/search/search_screen.dart';
import '../../app/resourcesscreen/categories/categories_screen.dart';
import '../../app/resourcesscreen/category_menu/category_menu_screen.dart';
import '../../app/resourcesscreen/dynamic_page/dynamic_page_screen.dart';
import '../../app/resourcesscreen/support/support_screen.dart';
import '../../app/resourcesscreen/webview/webview_screen.dart';
import '../../app/component/vibe_background.dart';
import '../../app/paymentscreen/wallet/wallet_screen.dart';
import '../../app/splashscreen/splash_screen.dart';
import '../analytics/screen_tracker.dart';
import '../session/session_store.dart';

/// Lets non-widget code (push handlers, `CAlert` without a context) reach
/// the navigator.
final GlobalKey<NavigatorState> rootNavigatorKey = GlobalKey<NavigatorState>();
final GlobalKey<ScaffoldMessengerState> scaffoldMessengerKey =
    GlobalKey<ScaffoldMessengerState>();

/// Route paths, same as the RN expo-router tree so deep links keep working.
abstract final class AppRoutes {
  static const splash = '/';
  static const login = '/auth/login';
  static const onboardingAge = '/onboarding/age';
  static const onboardingLanguage = '/onboarding/language';
  static const home = '/home';
  static const explore = '/explore';
  static const profileTab = '/profile';
  static const search = '/search';
  static const call = '/call';
  static const incomingCall = '/call/incoming';
  static const wallet = '/wallet';
  static const webview = '/webview';

  static const profile = '/me/profile';
  static const personalInfo = '/me/personal-info';
  static const professionalDetails = '/me/professional-details';
  static const callRates = '/me/call-rates';
  static const approval = '/me/approval';
  static const categories = '/me/categories';
  static const categoryMenu = '/me/category-menu';
  static const expertise = '/me/expertise';
  static const schedule = '/me/schedule';
  static const favourites = '/me/favourites';
  static const blockedUsers = '/me/blocked-users';
  static const referral = '/me/referral';
  static const gstDetails = '/me/gst-details';
  static const profileQr = '/me/profile-qr';
  static const dynamicPage = '/me/dynamic-page';
  static const aboutApp = '/me/about-app';
  static const support = '/me/support';
  static const verificationBadge = '/me/verification-badge';
  static const verificationBadgeForm = '/me/verification-badge-form';
  static const verificationBadgeFee = '/me/verification-badge-fee';
  static const verificationBadgeStatus = '/me/verification-badge-status';

  /// "Become a Host" (intro → 8 steps → submitted).
  static const hostOnboarding = '/host/onboarding';

  /// An approved host's weekly schedule / call rates (onboarding widgets).
  static const hostSchedule = '/host/schedule';
  static const hostRates = '/host/rates';

  /// Professional Details opened on one onboarding step (`HostStep.name`).
  static String hostStep(String step) => '$professionalDetails?step=$step';
}

/// Reachable signed out; everything else sends a signed-out user to login.
const _publicRoutes = {AppRoutes.splash, AppRoutes.login};

final GoRouter appRouter = GoRouter(
  navigatorKey: rootNavigatorKey,
  initialLocation: AppRoutes.splash,
  // Named sheets / dialogs as analytics screens (pages: ScreenTracker).
  observers: [ScreenTracker.observer],
  // Logout, a failed token refresh, or "Not you?" → login, from any screen.
  refreshListenable: SessionStore.instance.signedIn,
  redirect: (context, state) {
    final session = SessionStore.instance.value;
    final at = state.matchedLocation;
    if (!session.isAuthenticated) {
      return _publicRoutes.contains(at) ? null : AppRoutes.login;
    }
    // RN root guard: a known "needs a date" / "blocked" verdict holds the
    // user on the 18+ gate, whichever way they got in (deep link, push…).
    // Splash and login decide for themselves; a live call is never cut.
    final gated =
        session.ageGateStatus.gates &&
        !_publicRoutes.contains(at) &&
        at != AppRoutes.onboardingAge &&
        !at.startsWith(AppRoutes.call);
    return gated ? AppRoutes.onboardingAge : null;
  },
  routes: [
    GoRoute(
      path: AppRoutes.splash,
      builder: (context, state) => const SplashScreen(),
    ),
    GoRoute(
      path: AppRoutes.login,
      builder: (context, state) =>
          LoginScreen(params: state.uri.queryParameters),
    ),
    GoRoute(
      path: AppRoutes.home,
      // Fades in instead of sliding: the splash's logo flies into its top
      // bar meanwhile (LaunchLogo) and must find it in place.
      pageBuilder: (context, state) => _FadeInPage(
        key: state.pageKey,
        child: HomeScreen(
          initialTab: HomeTab.fromParam(state.uri.queryParameters['tab']),
          topic: state.uri.queryParameters['topic'],
          sheet: state.uri.queryParameters['sheet'],
        ),
      ),
    ),
    // RN tab routes: same shell, other tab.
    GoRoute(
      path: AppRoutes.explore,
      redirect: (_, _) => '${AppRoutes.home}?tab=history',
    ),
    GoRoute(
      path: AppRoutes.profileTab,
      redirect: (_, _) => '${AppRoutes.home}?tab=me',
    ),
    GoRoute(
      path: AppRoutes.search,
      builder: (context, state) => const SearchScreen(),
    ),
    // Resources: profile-menu categories, CMS pages, in-app browser.
    GoRoute(
      path: AppRoutes.categoryMenu,
      builder: (context, state) =>
          CategoryMenuScreen(id: state.uri.queryParameters['id']),
    ),
    GoRoute(
      path: AppRoutes.dynamicPage,
      builder: (context, state) => DynamicPageScreen(
        slug: state.uri.queryParameters['slug'],
        title: state.uri.queryParameters['title'],
      ),
    ),
    GoRoute(
      path: AppRoutes.aboutApp,
      builder: (context, state) => const DynamicPageScreen.about(),
    ),
    GoRoute(
      path: AppRoutes.support,
      builder: (context, state) => const SupportScreen(),
    ),
    GoRoute(
      path: AppRoutes.categories,
      builder: (context, state) => const CategoriesScreen(),
    ),
    GoRoute(
      path: AppRoutes.webview,
      builder: (context, state) => WebviewScreen(
        url: state.uri.queryParameters['url'],
        title: state.uri.queryParameters['title'],
      ),
    ),
    GoRoute(
      path: AppRoutes.personalInfo,
      builder: (context, state) => const PersonalInfoScreen(),
    ),
    GoRoute(
      path: AppRoutes.gstDetails,
      builder: (context, state) => const GstDetailsScreen(),
    ),
    GoRoute(
      path: AppRoutes.favourites,
      builder: (context, state) => const FavouritesScreen(),
    ),
    GoRoute(
      path: AppRoutes.blockedUsers,
      builder: (context, state) => const BlockedUsersScreen(),
    ),
    GoRoute(
      path: AppRoutes.referral,
      builder: (context, state) => const ReferralScreen(),
    ),
    GoRoute(
      path: AppRoutes.wallet,
      // `?amount=` (or RN's `?prefillAmount=`): a pre-filled top-up.
      builder: (context, state) {
        final q = state.uri.queryParameters;
        return WalletScreen(
          prefillAmount: double.tryParse(
            q['amount'] ?? q['prefillAmount'] ?? '',
          ),
        );
      },
    ),
    GoRoute(
      path: AppRoutes.onboardingAge,
      builder: (context, state) => const AgeGateScreen(),
    ),
    GoRoute(
      path: AppRoutes.onboardingLanguage,
      builder: (context, state) => const LanguageScreen(),
    ),
    GoRoute(
      path: AppRoutes.hostOnboarding,
      // `?step=`: open on that step (a link from a push or a campaign).
      builder: (context, state) => HostOnboardingScreen(
        startStep: HostStep.linkable(state.uri.queryParameters['step']),
      ),
    ),
    GoRoute(
      path: AppRoutes.hostSchedule,
      builder: (context, state) =>
          const HostOnboardingScreen(editStep: HostStep.availability),
    ),
    // Host Hub (RN menu-data `hub` + profile QR). Profile sections open the
    // onboarding flow itself on their step, in edit mode.
    GoRoute(
      path: AppRoutes.professionalDetails,
      // `?step=`: a warning or a link opens the step it is about. Form
      // steps open on their own ("Save changes"); the preview and the
      // guidelines open the whole flow there.
      builder: (context, state) {
        final name = state.uri.queryParameters['step'];
        final step = HostStep.fromName(name);
        final form =
            step.index >= HostStep.basic.index &&
            step.index <= HostStep.availability.index;
        final flow = form ? null : HostStep.linkable(name);
        if (flow != null) return HostOnboardingScreen(startStep: flow);
        return HostOnboardingScreen(editStep: form ? step : HostStep.basic);
      },
    ),
    GoRoute(
      path: AppRoutes.expertise,
      builder: (context, state) =>
          const HostOnboardingScreen(editStep: HostStep.interests),
    ),
    GoRoute(
      path: AppRoutes.schedule,
      builder: (context, state) =>
          const HostOnboardingScreen(editStep: HostStep.availability),
    ),
    GoRoute(
      path: AppRoutes.callRates,
      builder: (context, state) =>
          const HostOnboardingScreen(editStep: HostStep.rates),
    ),
    GoRoute(
      path: AppRoutes.approval,
      builder: (context, state) => const HostApprovalScreen(),
    ),
    GoRoute(
      path: AppRoutes.verificationBadge,
      builder: (context, state) => const HostBadgeScreen(),
    ),
    GoRoute(
      path: AppRoutes.verificationBadgeStatus,
      builder: (context, state) => const HostBadgeScreen(review: true),
    ),
    GoRoute(
      path: AppRoutes.verificationBadgeFee,
      builder: (context, state) => const HostBadgeFeeScreen(),
    ),
    GoRoute(
      path: AppRoutes.verificationBadgeForm,
      builder: (context, state) => const HostBadgeFormScreen(),
    ),
    GoRoute(
      path: AppRoutes.profileQr,
      builder: (context, state) => const HostProfileQrScreen(),
    ),
    GoRoute(
      path: AppRoutes.hostRates,
      builder: (context, state) =>
          const HostOnboardingScreen(editStep: HostStep.rates),
    ),
    // Call screens: no transition (RN `animation: 'none'`) and no
    // swipe-back (the screens hold a `PopScope`).
    GoRoute(
      path: AppRoutes.call,
      pageBuilder: (context, state) =>
          NoTransitionPage(key: state.pageKey, child: const CallScreen()),
    ),
    GoRoute(
      path: AppRoutes.incomingCall,
      pageBuilder: (context, state) => NoTransitionPage(
        key: state.pageKey,
        child: const IncomingCallScreen(),
      ),
    ),
  ],
  // Screens not built yet land here instead of an error page.
  errorBuilder: (context, state) => const _PlaceholderScreen(),
);

/// Comes in with a fade; covered by a pushed page it moves like any other
/// (the platform's transition, e.g. the iOS parallax).
class _FadeInPage extends CustomTransitionPage<void> {
  _FadeInPage({super.key, required super.child})
    : super(
        transitionDuration: const Duration(milliseconds: 320),
        reverseTransitionDuration: const Duration(milliseconds: 220),
        transitionsBuilder: (context, animation, secondary, child) =>
            FadeTransition(
              opacity: CurvedAnimation(
                parent: animation,
                curve: Curves.easeOut,
              ),
              child: Theme.of(context).pageTransitionsTheme.buildTransitions(
                ModalRoute.of(context)! as PageRoute<void>,
                context,
                kAlwaysCompleteAnimation,
                secondary,
                child,
              ),
            ),
      );
}

class _PlaceholderScreen extends StatelessWidget {
  const _PlaceholderScreen();

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      body: Stack(
        children: [
          VibeBackground(),
          Center(child: AppLogo(size: 200)),
        ],
      ),
    );
  }
}
