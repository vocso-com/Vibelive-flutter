import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vibelive/app/api/promo_banner/promo_banner_models.dart';
import 'package:vibelive/app/api/promo_banner/promo_banner_queries.dart';
import 'package:vibelive/app/promo/promo_banner_actions.dart';
import 'package:vibelive/app/promo/promo_banner_carousel.dart';
import 'package:vibelive/app/promo/promo_effects.dart';
import 'package:vibelive/core/network/strapi.dart';
import 'package:vibelive/core/query/query_persist.dart';
import 'package:vibelive/core/storage/app_prefs.dart';

import 'host_onboarding_support/harness.dart';

JsonMap _banner(String id, {Map<String, Object?> extra = const {}}) => {
  'id': id,
  'title': 'Banner $id',
  'subtitle': 'Sub $id',
  'ctaLabel': 'Go',
  'image': null,
  'layout': 'text_only',
  'colors': {
    'background': '#112233',
    'backgroundEnd': '#445566',
    'text': '#FFFFFF',
    'ctaBackground': '#FFFFFF',
    'ctaText': '#111827',
  },
  'textAlign': 'start',
  'height': 'medium',
  'cornerRadius': 16,
  'overlayOpacity': 35,
  'action': {'type': 'none'},
  'dismissible': false,
  ...extra,
};

void main() {
  final opened = <String>[];
  final browsed = <Uri>[];

  setUpAll(() async {
    await setUpHostHarness();
  });

  setUp(() async {
    opened.clear();
    browsed.clear();
    PromoBannerActions.openAppLink = (link) async => opened.add(link);
    PromoBannerActions.openBrowser = (uri) async {
      browsed.add(uri);
      return true;
    };
    await QueryPersist.clearAll();
    await AppPrefs.remove('promo_banners_dismissed');
    PromoDismissed.reload();
  });

  tearDown(PromoBannerActions.reset);

  Future<void> open(
    WidgetTester tester, {
    PromoPlacement placement = PromoPlacement.home,
  }) async {
    phone(tester);
    await pumpRoutes(
      tester,
      Scaffold(
        body: Column(children: [PromoBannerCarousel(placement: placement)]),
      ),
    );
    await pumpFor(tester, 600);
  }

  group('models', () {
    test('off, or nothing showable, is an empty feed', () {
      expect(
        PromoBannerFeed.fromJson(const {'enabled': false}).banners,
        isEmpty,
      );
      final feed = PromoBannerFeed.fromJson({
        'enabled': true,
        'rotateSeconds': 99,
        'banners': [
          _banner('a'),
          _banner('b', extra: {'layout': 'image_only'}), // no image
          _banner('c', extra: {'title': ''}), // text with no title
          const {'title': 'no id'},
        ],
      });
      expect(feed.banners.map((b) => b.id), ['a']);
      expect(feed.rotateSeconds, 30);
      final a = feed.banners.single;
      expect(a.background, const Color(0xFF112233));
      expect(a.backgroundEnd, const Color(0xFF445566));
      expect(
        feed.toJson()['enabled'],
        isTrue,
        reason: 'kept for the disk copy',
      );
    });

    test('colours: #RGB, #RRGGBB, #AARRGGBB; anything else is no colour', () {
      expect(PromoBanner.parseHex('#fff'), const Color(0xFFFFFFFF));
      expect(PromoBanner.parseHex('#7C3AED'), const Color(0xFF7C3AED));
      expect(PromoBanner.parseHex('#807C3AED'), const Color(0x807C3AED));
      expect(PromoBanner.parseHex('purple'), isNull);
      expect(PromoBanner.parseHex('#12'), isNull);
    });

    test('a tap: an app path gets this app scheme; a full link stays', () {
      final path = PromoAction.fromJson(const {
        'type': 'app',
        'path': '/wallet?amount=50',
      });
      expect(path.appLink('vibecalling'), 'vibecalling://wallet?amount=50');
      final link = PromoAction.fromJson(const {
        'type': 'app',
        'link': 'other://x',
      });
      expect(link.appLink('vibecalling'), 'other://x');
      final url = PromoAction.fromJson(const {
        'type': 'url',
        'url': 'https://x.com/a',
        'openIn': 'app',
      });
      expect(url.isUrl, isTrue);
      expect(url.inApp, isTrue);
      expect(
        PromoAction.fromJson(const {'type': 'url', 'url': 'ftp://x'}).isNone,
        isTrue,
      );
      expect(PromoAction.fromJson(const {'type': 'app'}).isNone, isTrue);
    });
  });

  testWidgets('shows the live banner; a tap opens its app screen', (
    tester,
  ) async {
    final backend = await resetHost();
    backend.replies['GET /api/app-banners'] = (o) => {
      'enabled': true,
      'rotateSeconds': 5,
      'banners': [
        _banner(
          'a',
          extra: {
            'action': {'type': 'app', 'path': 'wallet?amount=50'},
          },
        ),
      ],
    };
    await open(tester);
    expect(find.text('Banner a'), findsOneWidget);
    expect(find.text('Go'), findsOneWidget);
    expect(
      backend.calls
          .where((c) => c.path == '/api/app-banners')
          .first
          .query['placement'],
      'home',
    );
    await tester.tap(find.text('Banner a'));
    await pumpFor(tester, 200);
    expect(opened, ['vibecalling://wallet?amount=50']);
    await finishHost(tester);
  });

  testWidgets('a web page opens in the browser', (tester) async {
    final backend = await resetHost();
    backend.replies['GET /api/app-banners'] = (_) => {
      'enabled': true,
      'banners': [
        _banner(
          'w',
          extra: {
            'action': {
              'type': 'url',
              'url': 'https://vibelive.app/offer',
              'openIn': 'browser',
            },
          },
        ),
      ],
    };
    await open(tester, placement: PromoPlacement.wallet);
    expect(
      backend.calls
          .where((c) => c.path == '/api/app-banners')
          .first
          .query['placement'],
      'wallet',
    );
    await tester.tap(find.text('Banner w'));
    await pumpFor(tester, 200);
    expect(browsed, [Uri.parse('https://vibelive.app/offer')]);
    expect(opened, isEmpty);
    await finishHost(tester);
  });

  testWidgets('several banners slide on their own; a closed one stays closed', (
    tester,
  ) async {
    final backend = await resetHost();
    backend.replies['GET /api/app-banners'] = (_) => {
      'enabled': true,
      'rotateSeconds': 2,
      'banners': [
        _banner('a', extra: {'dismissible': true}),
        _banner('b'),
      ],
    };
    await open(tester);
    expect(find.text('Banner a'), findsOneWidget);
    await pumpFor(tester, 3200);
    expect(find.text('Banner b'), findsOneWidget, reason: 'slid to the next');
    // Two seconds a slide: back to the first one a moment later.
    await pumpFor(tester, 1000);
    expect(find.text('Banner a'), findsOneWidget, reason: 'and round again');

    await tester.tap(find.byKey(const ValueKey('promo-dismiss-a')));
    await pumpFor(tester, 600);
    expect(find.text('Banner a'), findsNothing);
    expect(find.text('Banner b'), findsOneWidget);
    expect(AppPrefs.getString('promo_banners_dismissed'), contains('a'));
    await finishHost(tester);
  });

  testWidgets('banners off: nothing drawn', (tester) async {
    final backend = await resetHost();
    backend.replies['GET /api/app-banners'] = (_) => {
      'enabled': false,
      'banners': [],
    };
    await open(tester);
    expect(find.byType(PageView), findsNothing);
    expect(find.textContaining('Banner'), findsNothing);
    await finishHost(tester);
  });

  testWidgets('a silent update reloads at once', (tester) async {
    final backend = await resetHost();
    var title = 'Before';
    backend.replies['GET /api/app-banners'] = (_) => {
      'enabled': true,
      'banners': [
        _banner('a', extra: {'title': title}),
      ],
    };
    await open(tester);
    expect(find.text('Before'), findsOneWidget);
    title = 'After';
    invalidatePromoBanners();
    await pumpFor(tester, 600);
    expect(find.text('After'), findsOneWidget);
    await finishHost(tester);
  });

  group('effects', () {
    test('the admin effect and its colour; unknown is none', () {
      final b = PromoBanner.fromJson(
        _banner(
          'e',
          extra: {
            'effect': {'type': 'gift', 'color': '#FF0066'},
          },
        ),
      )!;
      expect(b.effect, PromoEffect.gift);
      expect(b.effectColor, const Color(0xFFFF0066));
      final none = PromoBanner.fromJson(
        _banner(
          'n',
          extra: {
            'effect': {'type': 'fireworks'},
          },
        ),
      )!;
      expect(none.effect, PromoEffect.none);
    });

    for (final effect in PromoEffect.values.where(
      (e) => e != PromoEffect.none,
    )) {
      testWidgets('${effect.name} animates over the banner', (tester) async {
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: Center(
                child: SizedBox(
                  width: 340,
                  height: 132,
                  child: PromoEffectLayer(
                    effect: effect,
                    color: const Color(0xFFFFD54F),
                  ),
                ),
              ),
            ),
          ),
        );
        for (var i = 0; i < 40; i++) {
          await tester.pump(const Duration(milliseconds: 100));
        }
        expect(tester.takeException(), isNull);
        expect(
          find.descendant(
            of: find.byType(PromoEffectLayer),
            matching: find.byType(CustomPaint),
          ),
          findsOneWidget,
        );
        await tester.pumpWidget(const SizedBox());
      });
    }

    testWidgets('reduce motion: one still frame', (tester) async {
      await tester.pumpWidget(
        const MediaQuery(
          data: MediaQueryData(disableAnimations: true),
          child: Directionality(
            textDirection: TextDirection.ltr,
            child: SizedBox(
              width: 340,
              height: 132,
              child: PromoEffectLayer(
                effect: PromoEffect.sparkle,
                color: Color(0xFFFFD54F),
              ),
            ),
          ),
        ),
      );
      final painter =
          tester
                  .widget<CustomPaint>(
                    find.descendant(
                      of: find.byType(PromoEffectLayer),
                      matching: find.byType(CustomPaint),
                    ),
                  )
                  .painter!
              as PromoEffectPainter;
      final before = painter.time.value;
      await tester.pump(const Duration(seconds: 2));
      expect(painter.time.value, before);
      expect(tester.hasRunningAnimations, isFalse);
    });
  });
}
