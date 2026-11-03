import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:pretty_dio_logger/pretty_dio_logger.dart';
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';
import 'package:vibelive/app/api/listingflow/filter_models.dart';
import 'package:vibelive/app/component/morph_fab.dart';
import 'package:vibelive/app/homescreen/discover/active_filters.dart';
import 'package:vibelive/app/listingflow/widgets/host_grid_card.dart';
import 'package:vibelive/app/navbar/bottombar/bottom_navbar.dart';
import 'package:vibelive/app/navbar/bottombar/navbar_collapse.dart';
import 'package:vibelive/app/navbar/topbar/home_top_bar.dart';
import 'package:vibelive/core/i18n/i18n.dart';
import 'package:vibelive/core/network/api_client.dart';
import 'package:vibelive/core/query/query_client.dart';
import 'package:vibelive/core/router/app_router.dart';
import 'package:vibelive/core/session/session_store.dart';
import 'package:vibelive/core/storage/app_prefs.dart';
import 'package:vibelive/core/theme/app_theme.dart';
import 'package:vibelive/core/theme/theme_controller.dart';
import 'package:vibelive/core/utils/scale.dart';
import 'package:vibelive/main.dart';
import 'package:vibelive/app/api/homescreen/feed_shuffle.dart';

/// Feed of 2 pages x 6 hosts, a support-topic form and a wallet. [rich]:
/// hosts with a long rate and a rating, no district, and a huge balance.
class _Backend implements HttpClientAdapter {
  _Backend({this.rich = false});

  final bool rich;
  final feedPages = <int>[];

  /// `/instant-call/config`: Talk Now on (both call types) or off.
  bool talkNow = false;

  @override
  Future<ResponseBody> fetch(
    RequestOptions o,
    Stream<Uint8List>? _,
    Future<void>? _,
  ) async {
    return ResponseBody.fromString(
      jsonEncode(_reply(o)),
      200,
      headers: {
        Headers.contentTypeHeader: ['application/json'],
      },
    );
  }

  Object _reply(RequestOptions o) {
    final q = o.queryParameters;
    switch (o.path) {
      case '/api/expert-profiles':
        if (q['popular'] == 'true') {
          return {
            'data': [_host(90)],
          };
        }
        final page = int.parse('${q['pagination[page]'] ?? 1}');
        feedPages.add(page);
        return {
          'data': [
            for (var i = 1; i <= 6; i++)
              rich ? _richHost((page - 1) * 6 + i) : _host((page - 1) * 6 + i),
          ],
          'meta': {
            'pagination': {'page': page, 'pageCount': 2},
          },
        };
      case '/api/interests/form':
        return {
          'data': {
            'questions': [
              {
                'key': 'support_topic',
                'title': 'Support',
                'options': [
                  {'value': 'breakup', 'label': 'Breakup'},
                  {'value': 'dating', 'label': 'Dating'},
                ],
              },
            ],
          },
        };
      case '/api/wallets':
        return {
          'data': [
            {'id': 1, 'balance': rich ? 98765432.5 : 120.5},
          ],
        };
      case '/api/instant-call/config':
        return talkNow
            ? {
                'enabled': true,
                'allowedCallTypes': 'both',
                'callerVoiceRate': 10,
                'callerVideoRate': 25,
              }
            : {'enabled': false};
      default:
        return {'data': <Object>[]};
    }
  }

  static Map<String, Object?> _host(int id) => {
    'id': id,
    'documentId': 'exp$id',
    'tagline': 'Tagline $id',
    'user': {'id': id * 10, 'documentId': 'usr$id', 'name': 'Host $id'},
  };

  static Map<String, Object?> _richHost(int id) => {
    'id': id,
    'documentId': 'exp$id',
    'averageRating': 4.6,
    'rates': {'voiceCallRate': 1250.75},
    'user': {
      'id': id * 10,
      'documentId': 'usr$id',
      'name': 'Host with a rather long display name $id',
    },
  };

  @override
  void close({bool force = false}) {}
}

Future<void> _pump(WidgetTester tester, int ms) async {
  for (var t = 0; t < ms; t += 50) {
    await tester.pump(const Duration(milliseconds: 50));
  }
}

void main() {
  // These check paging and rendering in the server's order.
  FeedShuffle.enabled = false;
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

  setUp(() async {
    rootBundle.clear();
    queryCache.clear();
    ApiClient.dio.httpClientAdapter = backend = _Backend();
    await SessionStore.instance.signIn(
      user: {
        'id': 1,
        'documentId': 'u1',
        'name': 'Asha',
        'email': 'a@b.co',
        'mobile': '9999999999',
      },
      accessToken: 'access',
    );
  });

  Future<void> openHome(
    WidgetTester tester, {
    Size size = const Size(390, 844),
    double bottomInset = 0,
  }) async {
    final inset = FakeViewPadding(bottom: bottomInset * 3);
    tester.view
      ..physicalSize = size * 3
      ..devicePixelRatio = 3
      ..padding = inset
      ..viewPadding = inset;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      VibeLiveApp(
        themeController: ThemeController(ThemeMode.dark),
        localeController: LocaleController(const Locale('en')),
      ),
    );
    appRouter.go(AppRoutes.home);
    await tester.pump();
    await tester.pump();
  }

  Future<void> finish(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(minutes: 6));
  }

  testWidgets('skeleton, then the feed, topics and wallet', (tester) async {
    await openHome(tester);
    expect(find.byType(HostGridCardSkeleton), findsWidgets);

    await _pump(tester, 600);
    expect(find.byType(HostGridCardSkeleton), findsNothing);
    expect(backend.feedPages, [1]);
    // Names are upper-cased by the host mapper (as in RN).
    expect(find.textContaining('HOST 1'), findsOneWidget); // featured
    expect(find.byType(HostGridCard), findsWidgets);
    expect(find.text('Breakup'), findsOneWidget); // topic tab from the form
    expect(find.text('₹ 120.5'), findsOneWidget); // wallet chip
    await finish(tester);
  });

  testWidgets('scrolling to the end loads the next page', (tester) async {
    await openHome(tester);
    await _pump(tester, 600);
    await tester.fling(
      find.byType(CustomScrollView).last,
      const Offset(0, -3000),
      3000,
    );
    await _pump(tester, 1500);
    expect(backend.feedPages, [1, 2]);
    await finish(tester);
  });

  testWidgets('navbar switches tabs and keeps Discover alive', (tester) async {
    await openHome(tester);
    await _pump(tester, 600);
    expect(find.byType(DiscoverTopBar), findsOneWidget);
    // Light / dark moved to Me → Settings.
    expect(find.bySemanticsLabel('Switch theme'), findsNothing);

    await tester.tap(find.bySemanticsLabel('Profile'));
    await _pump(tester, 400);
    expect(find.byType(MeTopBar), findsOneWidget);
    expect(find.byType(DiscoverTopBar), findsNothing);

    // History has a top bar like the other tabs.
    await tester.tap(find.bySemanticsLabel('History'));
    await _pump(tester, 400);
    expect(find.byType(HistoryTopBar), findsOneWidget);
    expect(find.text('Call History'), findsOneWidget);

    await tester.tap(find.bySemanticsLabel('Discover'));
    await _pump(tester, 400);
    expect(find.byType(DiscoverTopBar), findsOneWidget);
    expect(backend.feedPages, [1]); // kept alive: no refetch on tab switch
    await finish(tester);
  });

  testWidgets('320 px: price + rating cards and a huge balance fit', (
    tester,
  ) async {
    ApiClient.dio.httpClientAdapter = backend = _Backend(rich: true);
    await openHome(tester, size: const Size(320, 568));
    await _pump(tester, 600);
    expect(tester.takeException(), isNull); // no RenderFlex overflow
    expect(find.byType(HostGridCard), findsWidgets);
    expect(find.text('₹ 1250.75/min'), findsWidgets); // price as stored (RN)
    // No tagline, no district: RN's "INDIA" fallback and "STAR".
    expect(find.text('INDIA  •  4.6 STAR'), findsWidgets);
    expect(find.text('₹ 98765.4k'), findsOneWidget); // shrinks, not cut
    final chip = tester.getRect(find.text('₹ 98765.4k'));
    expect(chip.right, lessThanOrEqualTo(320));
    await finish(tester);
  });

  testWidgets('Android back: other tab → Discover, then twice to exit', (
    tester,
  ) async {
    final exits = <String>[];
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async {
        if (call.method == 'SystemNavigator.pop') exits.add(call.method);
        return null;
      },
    );
    addTearDown(
      () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        null,
      ),
    );
    await openHome(tester);
    await _pump(tester, 600);
    await tester.tap(find.bySemanticsLabel('Profile'));
    await _pump(tester, 400);
    expect(find.byType(MeTopBar), findsOneWidget);

    await tester.binding.handlePopRoute();
    await _pump(tester, 400);
    expect(find.byType(DiscoverTopBar), findsOneWidget);
    expect(exits, isEmpty);

    await tester.binding.handlePopRoute();
    await _pump(tester, 300);
    expect(find.text('Press back again to exit'), findsOneWidget);
    // The toast floats above the navbar, not over it.
    final toast = tester.getRect(find.text('Press back again to exit'));
    final nav = tester.getRect(find.byType(BottomNavbar));
    expect(toast.bottom, lessThanOrEqualTo(nav.top + 1));
    expect(exits, isEmpty);

    await tester.binding.handlePopRoute();
    await tester.pump();
    expect(exits, ['SystemNavigator.pop']);
    await finish(tester);
  });

  testWidgets('Talk Now floats above the navbar on Discover only: the pill, '
      'then the circle at the navbar\'s right edge; none in the header', (
    tester,
  ) async {
    MorphFab.resetIntros();
    backend.talkNow = true;
    // A phone with a gesture bar / home indicator: the Scaffold strips that
    // inset from its body, which once sank the button under the navbar.
    await openHome(tester, bottomInset: 34);
    await _pump(tester, 1000);

    final nav = tester.getRect(find.byType(BottomNavbar));
    final dock = find.byKey(const ValueKey('morph-fab-circle'));
    expect(dock, findsOneWidget, reason: 'one Talk Now, the floating one');
    final pill = tester.getRect(dock);
    expect(pill.bottom, lessThanOrEqualTo(nav.top), reason: 'not under it');
    expect(nav.top - pill.bottom, closeTo(12.ms, 1.5), reason: 'just above');
    expect(pill.width, greaterThan(300));
    expect(find.text('Talk Now'), findsOneWidget);

    // Folded, and the landing pop settled.
    await _pump(tester, 4400);
    final circle = tester.getRect(dock);
    expect(circle.width, lessThan(100));
    expect(circle.bottom, lessThanOrEqualTo(nav.top));
    // The dock's own right edge (the navbar widget includes its margins).
    expect((circle.right - (nav.right - 16.ms)).abs(), lessThan(1.5));

    // Other tabs: no Talk Now.
    await tester.tap(find.bySemanticsLabel('Profile'));
    await _pump(tester, 400);
    expect(dock, findsNothing);
    await finish(tester);
  });

  test('NavbarCollapse: after a tab switch the first sample is a baseline', () {
    ScrollMetrics at(double y) => FixedScrollMetrics(
      minScrollExtent: 0,
      maxScrollExtent: 5000,
      pixels: y,
      viewportDimension: 800,
      axisDirection: AxisDirection.down,
      devicePixelRatio: 3,
    );
    final bar = NavbarCollapse.instance..reset();
    bar.track(at(500)); // Discover kept its offset while hidden
    expect(bar.value, isFalse);
    bar.track(at(470)); // scrolling up: stays open
    expect(bar.value, isFalse);
    bar.track(at(540)); // down 70: collapses
    expect(bar.value, isTrue);
    bar.reset();
  });

  testWidgets('320 px: a very long filter chip ellipsizes', (tester) async {
    tester.view
      ..physicalSize = const Size(320, 568) * 3
      ..devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    Scale.update(const Size(320, 568));
    addTearDown(() => Scale.update(const Size(390, 844)));
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.dark(),
        supportedLocales: AppI18n.supportedLocales,
        localizationsDelegates: [AppI18n.delegate],
        home: Scaffold(
          body: ActiveFilters(
            filter: HostFilter(
              languages: const ['Hindi'],
              topic: 'Relationship and family counselling ' * 3,
            ),
            onChanged: (_) {},
          ),
        ),
      ),
    );
    await tester.pump();
    expect(tester.takeException(), isNull);
    expect(find.text('🌐 Hindi'), findsOneWidget);
  });
}
