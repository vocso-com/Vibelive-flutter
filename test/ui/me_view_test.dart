import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:pretty_dio_logger/pretty_dio_logger.dart';
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';
import 'package:vibelive/app/authscreen/login_screen.dart';
import 'package:vibelive/app/client/personal_info/personal_info_screen.dart';
import 'package:vibelive/app/client/me/helper/host_availability_controller.dart';
import 'package:vibelive/app/client/me/widgets/me_skeleton.dart';
import 'package:vibelive/app/component/infinite_scroll.dart';
import 'package:vibelive/app/navbar/bottombar/bottom_navbar.dart';
import 'package:vibelive/app/authscreen/helper/link_parser.dart';
import 'package:vibelive/core/app_scope.dart';
import 'package:vibelive/core/i18n/i18n.dart';
import 'package:vibelive/core/network/api_client.dart';
import 'package:vibelive/core/query/query_client.dart';
import 'package:vibelive/core/router/app_router.dart';
import 'package:vibelive/core/session/session_store.dart';
import 'package:vibelive/core/storage/app_prefs.dart';
import 'package:vibelive/core/theme/theme_controller.dart';
import 'package:vibelive/main.dart';
import 'package:vibelive/app/hosthub/hub/hub_list.dart';

/// A client and a host, the host's stats and referral code; the expert's
/// vacation flag follows the last PUT.
class _Backend implements HttpClientAdapter {
  final requests = <String>[];
  bool vacation = false;

  /// Stats with every figure in the crores.
  bool big = false;

  @override
  Future<ResponseBody> fetch(
    RequestOptions o,
    Stream<Uint8List>? _,
    Future<void>? _,
  ) async {
    requests.add('${o.method} ${o.path}');
    return ResponseBody.fromString(
      jsonEncode(_reply(o)),
      200,
      headers: {
        Headers.contentTypeHeader: ['application/json'],
      },
    );
  }

  Object _reply(RequestOptions o) {
    if (o.method == 'PUT' && o.path == '/api/expert-profiles/exp1') {
      final data = (o.data as Map)['data'] as Map;
      vacation = data['vocationMode'] == true;
      return {'data': expert()};
    }
    return switch (o.path) {
      '/api/public-users/u-client' => {'data': client},
      '/api/public-users/u-ready' => {'data': readyClient},
      '/api/public-users/u-host' => {'data': hostUser()},
      '/api/expert-profiles/exp1' => {'data': expert()},
      '/api/user-statistics' when big => {
        'data': [
          {
            'id': 1,
            for (final k in const [
              'total_earnings',
              'total_incoming_calls',
              'total_profile_views',
              'total_referrals',
              'total_amount_withdrawal',
              'total_earnings_from_video_calls',
              'total_earnings_from_audio_calls',
              'total_earnings_from_referrals',
              'total_incoming_audio_calls',
              'total_incoming_video_minutes',
              'total_repeat_incoming_calls',
              'total_repeat_callers',
              'avg_incoming_call_minutes',
              'avg_outgoing_call_minutes',
            ])
              k: 987654321.75,
            'missed_call_percentage': 100,
            'average_rating': 4.95,
          },
        ],
      },
      '/api/user-statistics' => {
        'data': [
          {
            'id': 1,
            'total_earnings': 1500,
            'total_incoming_calls': 12,
            'total_profile_views': 1234,
            'average_rating': 4.5,
            'avg_incoming_call_minutes': 3.5,
          },
        ],
      },
      '/api/wallets' => {
        'data': [
          {'id': 1, 'balance': 120.5},
        ],
      },
      _ => {'data': <Object>[]},
    };
  }

  static const client = {
    'id': 1,
    'documentId': 'u-client',
    'name': 'Asha',
    'email': 'a@b.co',
    'mobile': '9999999999',
  };

  /// Personal Info complete: "Become a Host" is unlocked.
  static const readyClient = {
    'id': 3,
    'documentId': 'u-ready',
    'name': 'Meera',
    'email': 'm@b.co',
    'mobile': '9999999997',
    'address_JSON': {'state': 'Delhi', 'district': 'New Delhi'},
  };

  Map<String, Object?> expert() => {
    'id': 5,
    'documentId': 'exp1',
    'handler': 'riya',
    'isApproved': true,
    'isActive': true,
    'user_status': 'online',
    'vocationMode': vacation,
    'callAnyTime': !vacation,
    'schedule': <Object>[],
    'expert_verifications': <Object>[],
  };

  Map<String, Object?> hostUser() => {
    'id': 2,
    'documentId': 'u-host',
    'name': 'Riya',
    'email': 'r@b.co',
    'mobile': '9999999998',
    'user_referral': {'referralCode': 'vibe42'},
    'expert': expert(),
  };

  @override
  void close({bool force = false}) {}
}

Future<void> _pump(WidgetTester tester, int ms) async {
  for (var t = 0; t < ms; t += 50) {
    await tester.pump(const Duration(milliseconds: 50));
  }
}

final _meScrollable = find.descendant(
  of: find.byType(InfiniteScroll),
  matching: find.byType(Scrollable),
);

/// Scrolls [text] to the middle (clear of the floating navbar), then taps.
Future<void> _tap(WidgetTester tester, String text) async {
  final f = find.text(text);
  await Scrollable.ensureVisible(tester.element(f), alignment: 0.4);
  await tester.pump();
  await tester.tap(f);
}

void main() {
  late _Backend backend;

  setUpAll(() async {
    SharedPreferencesAsyncPlatform.instance =
        InMemorySharedPreferencesAsync.empty();
    FlutterSecureStorage.setMockInitialValues({});
    PackageInfo.setMockInitialValues(
      appName: 'Vibe Live',
      packageName: 'com.angrymamba.vibelive',
      version: '1.0.0',
      buildNumber: '1',
      buildSignature: '',
    );
    await AppPrefs.init();
    ApiClient.dio.interceptors.removeWhere((i) => i is PrettyDioLogger);
  });

  setUp(() {
    addTearDown(HostAvailabilityController.reset);
    rootBundle.clear();
    queryCache.clear();
    ApiClient.dio.httpClientAdapter = backend = _Backend();
  });

  /// [size] is the phone in logical pixels; [bottomInset] its home
  /// indicator.
  Future<void> openMe(
    WidgetTester tester, {
    required Map<String, Object?> user,
    Map<String, Object?>? expert,
    ThemeMode theme = ThemeMode.dark,
    Size size = const Size(390, 844),
    Locale locale = const Locale('en'),
    double bottomInset = 0,
  }) async {
    await SessionStore.instance.signIn(
      user: {...user}..remove('expert'),
      expert: expert,
      accessToken: 'access',
    );
    tester.view
      ..physicalSize = size * 3
      ..devicePixelRatio = 3
      ..padding = FakeViewPadding(bottom: bottomInset * 3)
      ..viewPadding = FakeViewPadding(bottom: bottomInset * 3);
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      VibeLiveApp(
        themeController: ThemeController(theme),
        localeController: LocaleController(locale),
      ),
    );
    appRouter.go('${AppRoutes.home}?tab=me');
    await tester.pump();
    await tester.pump();
  }

  Future<void> finish(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(minutes: 6));
  }

  testWidgets('client: skeleton, profile card and settings list', (
    tester,
  ) async {
    await openMe(tester, user: _Backend.client);
    expect(find.byType(MeSkeleton), findsOneWidget);

    await _pump(tester, 600);
    expect(find.byType(MeSkeleton), findsNothing);
    expect(backend.requests, contains('GET /api/public-users/u-client'));
    expect(find.text('Asha'), findsOneWidget);
    expect(find.text('General User'), findsOneWidget);
    expect(find.text('MY WALLET'), findsOneWidget);
    expect(find.text('IDENTITY'), findsOneWidget);
    expect(find.text('Personal Info'), findsOneWidget);
    expect(find.text('Share Profile'), findsNothing); // hosts only
    expect(find.text('Dashboard'), findsNothing);
    expect(find.text('HOST HUB'), findsNothing);
    expect(find.text('RESOURCES'), findsOneWidget);

    // Personal Info incomplete: Become a Host explains what is missing.
    await _tap(tester, 'Become a Host');
    await _pump(tester, 300);
    expect(find.text('Complete Personal Info'), findsOneWidget);
    expect(find.textContaining('Missing: State, District'), findsOneWidget);
    await tester.tap(find.text('CANCEL'));
    await _pump(tester, 300);
    expect(find.text('Complete Personal Info'), findsNothing);

    // Rows open their screen.
    await _tap(tester, 'Personal Info');
    await _pump(tester, 600);
    expect(find.byType(PersonalInfoScreen), findsOneWidget);
    appRouter.pop();
    await _pump(tester, 600);
    expect(find.text('Asha'), findsOneWidget);
    await finish(tester);
  });

  testWidgets('host: profile card, dashboard figures and settings', (
    tester,
  ) async {
    await openMe(tester, user: backend.hostUser(), expert: backend.expert());
    await _pump(tester, 800);

    expect(find.text('Riya'), findsOneWidget);
    expect(find.text('@riya'), findsOneWidget);
    expect(find.text('Available for calls'), findsOneWidget);
    // Availability lives in the dock's sheet, not on this screen.
    expect(find.text('AVAILABILITY MODES'), findsNothing);
    expect(find.text('₹1,500'), findsOneWidget); // lifetime earnings
    expect(find.text('VIBE42'), findsOneWidget); // invite card code

    // INVITE ALL opens the OS share sheet with the invite message.
    String? shared;
    const shareChannel = MethodChannel('dev.fluttercommunity.plus/share');
    final messenger = tester.binding.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(shareChannel, (call) async {
      if (call.method == 'share') {
        shared = (call.arguments as Map)['text'] as String?;
      }
      return 'dev.fluttercommunity.plus/share/unavailable';
    });
    addTearDown(() => messenger.setMockMethodCallHandler(shareChannel, null));
    await _tap(tester, 'INVITE ALL');
    await _pump(tester, 300);
    expect(shared, contains('Use my code VIBE42'));
    expect(shared, contains('/VIBE42?r=i')); // link not HTML-escaped
    expect(backend.requests, contains('GET /api/referral/VIBE42/copy'));
    // Tiles are built lazily: scroll down to them, then back up.
    for (final value in ['1,234', '3m 30s']) {
      // profile views, avg incoming duration
      await tester.scrollUntilVisible(
        find.text(value),
        300,
        scrollable: _meScrollable,
      );
    }
    expect(find.text('AVG DURATION (IN)'), findsOneWidget);

    // Offline from the dock: saved, re-read into the session, on the card.
    HostAvailabilityController.goOffline(null).ignore();
    await _pump(tester, 800);
    expect(backend.requests, contains('PUT /api/expert-profiles/exp1'));
    expect(backend.vacation, isTrue);
    await tester.scrollUntilVisible(
      find.text('On vacation'), // the profile card's pill
      -300,
      scrollable: _meScrollable,
    );
    expect(find.text('Available for calls'), findsNothing);

    // Settings: Host Hub with the badge prompt (approved, not applied).
    await tester.tap(find.text('Settings'));
    await _pump(tester, 400);
    expect(find.text('INSIGHTS'), findsNothing);
    expect(find.text('Share Profile'), findsOneWidget);
    expect(find.text('Become a Host'), findsNothing); // clients only
    await Scrollable.ensureVisible(
      tester.element(find.text('HOST HUB')),
      alignment: 0.3,
    );
    await _pump(tester, 100);
    expect(find.text('✨ APPLY FOR BADGE'), findsNWidgets(2));
    expect(find.text('Verification Badge'), findsOneWidget);
    await finish(tester);
  });

  testWidgets('a complete profile celebrates Become a Host once', (
    tester,
  ) async {
    await openMe(tester, user: _Backend.readyClient, theme: ThemeMode.light);
    await _pump(tester, 800);
    expect(find.text('🎉 Profile complete!'), findsOneWidget);
    expect(find.text('🎁 WANT TO BECOME A HOST?'), findsOneWidget);

    await Scrollable.ensureVisible(
      tester.element(find.text('🎉 Profile complete!')),
      alignment: 0.4,
    );
    await tester.pump();
    await tester.tap(find.bySemanticsLabel('Dismiss'));
    await _pump(tester, 200);
    expect(find.text('🎉 Profile complete!'), findsNothing);
    expect(
      AppPrefs.getString('@has_seen_become_host_unlock_1:u-ready'),
      'true',
    );
    await finish(tester);
  });

  testWidgets('menu: options for a client, logout returns to login', (
    tester,
  ) async {
    await openMe(tester, user: _Backend.client);
    await _pump(tester, 600);

    await tester.tap(find.bySemanticsLabel('More'));
    await _pump(tester, 400);
    expect(find.text('OPTIONS'), findsOneWidget);
    expect(find.text('Become a Host'), findsWidgets);
    expect(find.text('View Public Profile'), findsNothing); // hosts only

    await tester.tap(find.text('Logout Session'));
    await _pump(tester, 1500);
    expect(SessionStore.instance.value.isAuthenticated, isFalse);
    expect(backend.requests, contains('POST /api/session-auth/logout'));
    expect(find.byType(LoginScreen), findsOneWidget);
    await finish(tester);
  });

  testWidgets('host menu: Share Profile (RN link), no extra options', (
    tester,
  ) async {
    await openMe(tester, user: backend.hostUser(), expert: backend.expert());
    await _pump(tester, 800);

    String? shared;
    const shareChannel = MethodChannel('dev.fluttercommunity.plus/share');
    final messenger = tester.binding.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(shareChannel, (call) async {
      if (call.method == 'share') {
        shared = (call.arguments as Map)['text'] as String?;
      }
      return 'dev.fluttercommunity.plus/share/unavailable';
    });
    addTearDown(() => messenger.setMockMethodCallHandler(shareChannel, null));

    await tester.tap(find.bySemanticsLabel('More'));
    await _pump(tester, 400);
    final sheet = find.ancestor(
      of: find.text('OPTIONS'),
      matching: find.byType(Column),
    );
    expect(
      find.descendant(of: sheet.first, matching: find.text('Share Profile')),
      findsOneWidget,
    );
    expect(find.text('View Public Profile'), findsNothing);
    expect(find.text('Logout Session'), findsOneWidget);

    await tester.tap(
      find.descendant(of: sheet.first, matching: find.text('Share Profile')),
    );
    await _pump(tester, 600);
    expect(
      shared,
      'Check out my profile on Vibe: ${LinkParser.shareLink('riya')}',
    );
    await finish(tester);
  });

  testWidgets('the end of the list clears the navbar and home indicator', (
    tester,
  ) async {
    await openMe(tester, user: _Backend.client, bottomInset: 34);
    await _pump(tester, 600);
    final navTop = tester.getRect(find.byType(BottomNavbar)).top;

    await tester.fling(_meScrollable, const Offset(0, -3000), 3000);
    await _pump(tester, 1200);
    final resources = find.ancestor(
      of: find.text('RESOURCES'),
      matching: find.byType(HubListCard),
    );
    expect(tester.getRect(resources.first).bottom, lessThan(navTop));
    await finish(tester);
  });

  testWidgets('320 wide, Hindi host with big numbers: no overflow', (
    tester,
  ) async {
    backend.big = true;
    await openMe(
      tester,
      user: {
        ...backend.hostUser(),
        'name': 'Venkata Lakshmi Narasimha Subrahmanyam Chakravarthy',
      },
      expert: backend.expert(),
      size: const Size(320, 667),
      locale: const Locale('hi'),
      theme: ThemeMode.light,
    );
    await _pump(tester, 800);
    expect(tester.takeException(), isNull);

    // Every dashboard tile, then the settings list.
    await tester.fling(_meScrollable, const Offset(0, -3000), 3000);
    await _pump(tester, 800);
    expect(tester.takeException(), isNull);
    await tester.fling(_meScrollable, const Offset(0, 3000), 3000);
    await _pump(tester, 800);
    await tester.tap(find.text('सेटिंग्स'));
    await _pump(tester, 400);
    await tester.fling(_meScrollable, const Offset(0, -3000), 3000);
    await _pump(tester, 800);
    expect(tester.takeException(), isNull);

    await tester.tap(find.bySemanticsLabel('और विकल्प'));
    await _pump(tester, 400);
    expect(find.text('विकल्प'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await finish(tester);
  });

  testWidgets('320 wide, Hindi client with the host celebration: no overflow', (
    tester,
  ) async {
    await openMe(
      tester,
      user: _Backend.readyClient,
      size: const Size(320, 667),
      locale: const Locale('hi'),
    );
    await _pump(tester, 800);
    expect(tester.takeException(), isNull);
    await tester.fling(_meScrollable, const Offset(0, -3000), 3000);
    await _pump(tester, 800);
    expect(tester.takeException(), isNull);
    await finish(tester);
  });

  testWidgets('Theme: Device follows the phone; Light / Dark stick', (
    tester,
  ) async {
    tester.platformDispatcher.platformBrightnessTestValue = Brightness.dark;
    addTearDown(tester.platformDispatcher.clearPlatformBrightnessTestValue);
    await openMe(tester, user: _Backend.client, theme: ThemeMode.system);
    await _pump(tester, 600);
    final title = find.text('Theme');
    await tester.dragUntilVisible(
      title,
      find.byType(CustomScrollView).last,
      const Offset(0, -200),
    );
    await _pump(tester, 200);
    final theme = AppScope.of(tester.element(title)).theme;
    Brightness shown() => Theme.of(tester.element(title)).brightness;

    // Device (the default): the phone is dark, so is the app, and it follows
    // the phone when that changes.
    expect(theme.value, ThemeMode.system);
    expect(shown(), Brightness.dark);
    tester.platformDispatcher.platformBrightnessTestValue = Brightness.light;
    await _pump(tester, 400);
    expect(shown(), Brightness.light);

    await tester.tap(find.text('Dark'));
    await _pump(tester, 400);
    expect(theme.value, ThemeMode.dark);
    expect(shown(), Brightness.dark); // the phone is light: Dark sticks

    await tester.tap(find.text('Device'));
    await _pump(tester, 400);
    expect(theme.value, ThemeMode.system);
    expect(shown(), Brightness.light);
    await finish(tester);
  });

  testWidgets('host: status pill in the dock opens Host Availability', (
    tester,
  ) async {
    await openMe(
      tester,
      user: backend.hostUser(),
      expert: backend.expert(),
      size: const Size(320, 568),
    );
    appRouter.go(AppRoutes.home);
    await _pump(tester, 800);
    expect(tester.takeException(), isNull); // dock + header fit 320 px
    final pill = find.bySemanticsLabel(RegExp('Change availability'));
    expect(pill, findsOneWidget);
    expect(find.text('Online'), findsOneWidget);
    // Discover has no built-in banner any more (admin banners replace it).
    expect(find.text("You're Live! Someone May Call Soon."), findsNothing);

    await tester.tap(pill);
    await _pump(tester, 400);
    expect(find.text('Host Availability'), findsOneWidget);
    expect(find.text('Online & Ready for Calls'), findsOneWidget);
    expect(tester.takeException(), isNull);

    // A choice closes the sheet at once; the pill shows it while it saves.
    final offline = find.textContaining('Go Offline');
    await tester.ensureVisible(offline); // a small phone scrolls the sheet
    await _pump(tester, 200);
    await tester.tap(offline);
    await tester.pump();
    expect(find.text('Offline'), findsOneWidget);
    await _pump(tester, 400);
    expect(find.text('Host Availability'), findsNothing);
    expect(backend.requests, contains('PUT /api/expert-profiles/exp1'));
    expect(backend.vacation, isTrue);

    // Back online from the sheet.
    await tester.tap(pill);
    await _pump(tester, 400);
    await tester.tap(find.text('Online & Ready for Calls'));
    await _pump(tester, 600);
    expect(backend.vacation, isFalse);
    expect(find.text('Online'), findsOneWidget);

    // Offline for 30 min: the pill counts down.
    await tester.tap(pill);
    await _pump(tester, 400);
    await tester.ensureVisible(find.text('30 min'));
    await _pump(tester, 200);
    await tester.tap(find.text('30 min'));
    await _pump(tester, 1500);
    expect(find.text('Host Availability'), findsNothing);
    expect(find.textContaining(RegExp(r'^29m \d+s left$')), findsOneWidget);
    expect(HostAvailabilityController.offlineUntil.value, isNotNull);

    // Back online by hand ends the timer.
    await tester.tap(pill);
    await _pump(tester, 400);
    expect(find.textContaining('Back online in 29m'), findsOneWidget);
    await tester.tap(find.text('Online & Ready for Calls'));
    await _pump(tester, 600);
    expect(find.text('Online'), findsOneWidget);
    expect(backend.vacation, isFalse);
    expect(HostAvailabilityController.offlineUntil.value, isNull);
    expect(HostAvailabilityController.remaining.value, isNull);

    // Working hours open the schedule step; nothing saved from the sheet.
    final puts = backend.requests.length;
    await tester.tap(pill);
    await _pump(tester, 400);
    await tester.tap(find.text('Follow My Working Hours'));
    await _pump(tester, 800);
    final top = appRouter.routerDelegate.currentConfiguration.last;
    expect(
      top is ImperativeRouteMatch ? top.matches.uri.path : null,
      AppRoutes.hostSchedule,
    );
    expect(
      backend.requests.skip(puts).where((r) => r.startsWith('PUT')),
      isEmpty,
    );
    await finish(tester);
  });

  testWidgets('an offline timer never acts for another account', (
    tester,
  ) async {
    await openMe(tester, user: backend.hostUser(), expert: backend.expert());
    await _pump(tester, 600);
    // Host A: offline for 30 min.
    HostAvailabilityController.goOffline(const Duration(minutes: 30)).ignore();
    await _pump(tester, 600);
    expect(HostAvailabilityController.offlineUntil.value, isNotNull);

    // Host B (on a break) signs in on the same phone after A's timer ended.
    await SessionStore.instance.signIn(
      user: {...backend.hostUser(), 'id': 7, 'documentId': 'u-other'}
        ..remove('expert'),
      expert: {
        ...backend.expert(),
        'id': 9,
        'documentId': 'exp2',
        'vocationMode': true,
        'callAnyTime': false,
      },
      accessToken: 'access',
    );
    HostAvailabilityController.clock = () =>
        DateTime.now().add(const Duration(hours: 1));
    HostAvailabilityController.attach();
    await _pump(tester, 1500);
    // B stays offline: nothing is saved for B, and A's timer is dropped.
    expect(
      backend.requests.where((r) => r.contains('/expert-profiles/exp2')),
      isEmpty,
    );
    expect(HostAvailabilityController.offlineUntil.value, isNull);
    await finish(tester);
  });

  test('offline timer ends at the next 9 AM', () {
    expect(
      HostAvailabilityController.untilMorning(DateTime(2026, 1, 1, 7)),
      const Duration(hours: 2),
    );
    expect(
      HostAvailabilityController.untilMorning(DateTime(2026, 1, 1, 22)),
      const Duration(hours: 11),
    );
    expect(formatOfflineLeft(const Duration(minutes: 80)), '1h 20m');
    expect(formatOfflineLeft(const Duration(seconds: 1750)), '29m 10s');
    expect(formatOfflineLeft(const Duration(seconds: 45)), '45s');
  });

  testWidgets('client: no status pill in the dock', (tester) async {
    await openMe(tester, user: _Backend.client);
    appRouter.go(AppRoutes.home);
    await _pump(tester, 800);
    expect(find.bySemanticsLabel(RegExp('Change availability')), findsNothing);
    expect(
      find.text('Start Talking'),
      findsNothing,
      reason: 'no built-in hero',
    );
    await finish(tester);
  });

  testWidgets('Language: picked in Settings, the app switches and keeps it', (
    tester,
  ) async {
    await openMe(tester, user: _Backend.client, theme: ThemeMode.light);
    await _pump(tester, 600);
    final row = find.text('Language');
    await tester.dragUntilVisible(
      row,
      find.byType(CustomScrollView).last,
      const Offset(0, -200),
    );
    await _pump(tester, 200);
    expect(find.text('English'), findsOneWidget, reason: 'the current one');
    await tester.tap(row);
    await _pump(tester, 600);
    expect(find.text('Choose language'), findsOneWidget);
    expect(find.text('हिन्दी'), findsOneWidget);
    expect(find.text('Hindi'), findsOneWidget, reason: 'English name too');

    await tester.tap(find.byKey(const ValueKey('language_ta')));
    await _pump(tester, 400);
    // The Tamil files load from disk (real time, not the test clock).
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 300)),
    );
    await _pump(tester, 400);
    final locale = AppScope.of(
      tester.element(find.byType(Scaffold).first),
    ).locale;
    expect(locale.value, const Locale('ta'));
    expect(AppPrefs.getString('app_locale'), 'ta', reason: 'kept');
    final ta = _strings('ta', 'client')['me']['language'];
    final taTitle = find.text(ta['title'] as String);
    await tester.dragUntilVisible(
      taTitle,
      find.byType(CustomScrollView).last,
      const Offset(0, -200),
    );
    await _pump(tester, 200);
    expect(taTitle, findsOneWidget);
    expect(find.text('தமிழ்'), findsOneWidget);
    expect(find.text('Language'), findsNothing);
    expect(tester.takeException(), isNull);
    await finish(tester);
  });

  // Every language at the narrowest phone: the profile, the dashboard and
  // the settings list (Urdu right to left).
  testWidgets('every language, 320 wide host: no overflow', (tester) async {
    for (final lang in AppI18n.languages) {
      await openMe(
        tester,
        user: backend.hostUser(),
        expert: backend.expert(),
        size: const Size(320, 667),
        locale: lang.locale,
        theme: ThemeMode.light,
      );
      // The language's files load from disk (real time, not the test clock).
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 300)),
      );
      await _pump(tester, 800);
      expect(tester.takeException(), isNull, reason: lang.code);
      await tester.fling(_meScrollable, const Offset(0, -3000), 3000);
      await _pump(tester, 800);
      expect(tester.takeException(), isNull, reason: '${lang.code} dashboard');
      await tester.fling(_meScrollable, const Offset(0, 3000), 3000);
      await _pump(tester, 800);
      final settings =
          _strings(lang.code, 'client')['me']['section']['settings'] as String;
      await tester.tap(find.text(settings).first);
      await _pump(tester, 400);
      await tester.fling(_meScrollable, const Offset(0, -3000), 3000);
      await _pump(tester, 800);
      expect(tester.takeException(), isNull, reason: '${lang.code} settings');
      await finish(tester);
    }
  });
}

/// One namespace of a language, as bundled.
Map<String, dynamic> _strings(String lang, String ns) =>
    jsonDecode(File('assets/i18n/$lang/$ns.json').readAsStringSync())
        as Map<String, dynamic>;
