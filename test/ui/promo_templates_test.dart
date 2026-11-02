import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vibelive/app/api/promo_banner/promo_banner_models.dart';
import 'package:vibelive/app/api/promo_banner/promo_popup_models.dart';
import 'package:vibelive/app/promo/popup/popup_templates.dart';
import 'package:vibelive/app/promo/popup/promo_popup_controller.dart';
import 'package:vibelive/app/promo/popup/promo_popup_rules.dart';
import 'package:vibelive/app/promo/promo_banner_actions.dart';
import 'package:vibelive/app/promo/promo_banner_card.dart';
import 'package:vibelive/app/promo/templates/promo_countdown.dart';
import 'package:vibelive/app/promo/templates/promo_markup.dart';
import 'package:vibelive/core/i18n/i18n.dart';
import 'package:vibelive/core/network/strapi.dart';
import 'package:vibelive/core/router/external_open.dart';
import 'package:vibelive/core/storage/app_prefs.dart';
import 'package:vibelive/core/theme/app_theme.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

import 'host_onboarding_support/harness.dart';

const _accent = Color(0xFFFFD54F);

const _colors = {
  'background': '#2A0B4F',
  'backgroundEnd': '#12052A',
  'text': '#FFFFFF',
  'accent': '#FFD54F',
  'ctaBackground': '#FFD54F',
  'ctaText': '#2A0B4F',
};

/// Every field filled: the longest copy each template allows.
JsonMap _full(String template, {Map<String, Object?> extra = const {}}) => {
  'id': 'p-$template',
  'template': template,
  'badge': 'Limited time',
  'title': 'Recharge and get 50% extra talk time today',
  'titleRich': 'Recharge and get {50% extra} talk time {#FF4D6D|today}',
  'subtitleRich':
      'On your first recharge above ₹199. Valid for new users only, '
      'once per account, until Sunday midnight.',
  'offerValue': '₹100',
  'offerCaption': 'Free talk time',
  'couponCode': 'WELCOME100',
  'ctaLabel': 'Claim now',
  'ctaIcon': 'gift',
  'secondaryLabel': 'Maybe later',
  'icon': 'trophy',
  'image': 'https://cdn.test/promo.jpg',
  'imageFocus': 'top',
  'imageSide': 'right',
  'colors': _colors,
  'effect': {'type': 'sparkle', 'color': '#FFD54F'},
  'action': {'type': 'app', 'path': 'wallet?amount=199'},
  'endsAt': DateTime.now().add(const Duration(hours: 30)).toIso8601String(),
  'rules': {'frequency': 'after_close', 'reshowAfterHours': 24},
  'placement': 'home',
  'layout': 'image_right',
  ...extra,
};

PromoPopup _popup({
  String id = 'p1',
  String template = 'offer_card',
  Map<String, Object?> rules = const {},
  Map<String, Object?> extra = const {},
}) => PromoPopup.fromJson({
  ..._full(template, extra: extra),
  'id': id,
  'image': null,
  'rules': rules,
})!;

void main() {
  setUpAll(setUpHostHarness);

  group('colour markup (same as the server)', () {
    List<(String, Color?)> runs(String s) => [
      for (final r in PromoMarkup.parse(s, _accent)) (r.text, r.color),
    ];

    test('{words} → accent; {#hex|words} → that colour', () {
      expect(runs('Talk to {real people}!'), [
        ('Talk to ', null),
        ('real people', _accent),
        ('!', null),
      ]);
      expect(runs('{#FF4D6D|50% off}'), [('50% off', const Color(0xFFFF4D6D))]);
      expect(runs('{#f00|red}'), [('red', const Color(0xFFFF0000))]);
      expect(runs('{#80FFFFFF|soft}'), [('soft', const Color(0x80FFFFFF))]);
    });

    test('a bad hex is the accent; {} is nothing; stray braces stay', () {
      expect(runs('{#zz|words}'), [('words', _accent)]);
      expect(runs('a{}b'), [('a', null), ('b', null)]);
      expect(runs('{broken'), [('{broken', null)]);
      expect(runs('a}b'), [('a}b', null)]);
      expect(runs('{#tag}'), [('#tag', _accent)]);
      expect(PromoMarkup.plain('Get {50%} {#fff|now}'), 'Get 50% now');
    });
  });

  group('models', () {
    test('banner templates: known ones keep their content', () {
      final b = PromoBanner.fromJson(_full('spotlight'))!;
      expect(b.template, PromoBannerTemplate.spotlight);
      expect(b.content.title, contains('{50% extra}'), reason: 'titleRich');
      expect(b.content.palette.accent, _accent);
      expect(b.content.imageFocus, PromoImageFocus.top);
      expect(b.content.ctaIcon, 'gift');
      expect(b.title, 'Recharge and get 50% extra talk time today');
    });

    test('custom / unknown templates draw with the legacy look', () {
      final custom = PromoBanner.fromJson(_full('custom'))!;
      expect(custom.template, isNull);
      expect(custom.layout, PromoLayout.imageRight);
      final future = PromoBanner.fromJson(_full('hologram'))!;
      expect(future.template, isNull, reason: 'forward compatible');
    });

    test(
      'a template without what it needs, or an ended countdown, is dropped',
      () {
        expect(
          PromoBanner.fromJson(_full('spotlight', extra: {'image': null})),
          isNull,
        );
        expect(
          PromoBanner.fromJson(_full('offer', extra: {'offerValue': ''})),
          isNull,
        );
        expect(
          PromoBanner.fromJson(
            _full('countdown', extra: {'endsAt': '2020-01-01T00:00:00Z'}),
          ),
          isNull,
        );
        expect(
          PromoBanner.fromJson(_full('minimal', extra: {'image': null})),
          isNotNull,
        );
      },
    );

    test(
      'popups: rules with defaults and limits; unknown templates fall back',
      () {
        final p = PromoPopup.fromJson({
          ..._full('offer_card'),
          'rules': {
            'frequency': 'daily',
            'reshowAfterHours': 9999,
            'maxShows': -3,
            'delaySeconds': 99,
            'stopAfterAction': false,
          },
        })!;
        expect(p.template, PromoPopupTemplate.offerCard);
        expect(p.rules.frequency, PromoPopupFrequency.daily);
        expect(p.rules.reshowAfterHours, 720);
        expect(p.rules.maxShows, 0);
        expect(p.rules.delaySeconds, 30);
        expect(p.rules.stopAfterAction, isFalse);
        expect(p.rules.closeOnBackdrop, isTrue);
        expect(p.secondaryLabel, 'Maybe later');
        expect(
          PromoPopup.fromJson(_full('hologram'))!.template,
          PromoPopupTemplate.announcement,
        );
        expect(
          PromoPopup.fromJson(_full('poster', extra: {'image': null})),
          isNull,
          reason: 'a poster needs its image',
        );
        final feed = PromoPopupFeed.fromJson({
          'enabled': true,
          'openGapMinutes': 1,
          'popups': [
            _full('poster'),
            const {'title': 'no id'},
          ],
        });
        expect(feed.openGapMinutes, 5);
        expect(feed.popups.length, 1);
        expect(
          PromoPopupFeed.fromJson(const {'enabled': false}).enabled,
          isFalse,
        );
      },
    );
  });

  group('popup rules', () {
    final now = DateTime(2026, 11, 2, 21);
    bool ok(PromoPopup p, PromoPopupHistory h, [DateTime? at]) =>
        PromoPopupRulesCheck.eligible(p, h, at ?? now);

    test('every open: always, until max shows', () {
      final p = _popup(rules: {'frequency': 'every_open', 'maxShows': 3});
      expect(ok(p, PromoPopupHistory.none), isTrue);
      expect(ok(p, PromoPopupHistory(shown: 2, lastShownAt: now)), isTrue);
      expect(ok(p, PromoPopupHistory(shown: 3, lastShownAt: now)), isFalse);
    });

    test('after close: back once the hours have passed', () {
      final p = _popup(
        rules: {'frequency': 'after_close', 'reshowAfterHours': 6},
      );
      final h = PromoPopupHistory(
        shown: 1,
        lastShownAt: now.subtract(const Duration(hours: 5)),
        lastClosedAt: now.subtract(const Duration(hours: 5)),
      );
      expect(ok(p, h), isFalse);
      expect(ok(p, h, now.add(const Duration(hours: 1))), isTrue);
      // Shown but never closed (the app was killed): it may come back.
      expect(ok(p, PromoPopupHistory(shown: 1, lastShownAt: now)), isTrue);
    });

    test('daily: once per local day, again after midnight', () {
      final p = _popup(rules: {'frequency': 'daily'});
      final h = PromoPopupHistory(
        shown: 1,
        lastShownAt: DateTime(2026, 11, 2, 0, 5),
      );
      expect(ok(p, h, DateTime(2026, 11, 2, 23, 59)), isFalse);
      expect(ok(p, h, DateTime(2026, 11, 3, 0, 1)), isTrue);
    });

    test('once: never again', () {
      final p = _popup(rules: {'frequency': 'once'});
      expect(ok(p, PromoPopupHistory.none), isTrue);
      expect(ok(p, PromoPopupHistory(shown: 1, lastShownAt: now)), isFalse);
    });

    test('stop after action, and an ended popup', () {
      final p = _popup(rules: {'frequency': 'every_open'});
      expect(ok(p, const PromoPopupHistory(shown: 1, acted: true)), isFalse);
      final keep = _popup(
        rules: {'frequency': 'every_open', 'stopAfterAction': false},
      );
      expect(ok(keep, const PromoPopupHistory(shown: 1, acted: true)), isTrue);
      final ending = _popup(
        extra: {
          'endsAt': now.add(const Duration(minutes: 1)).toIso8601String(),
        },
        rules: {'frequency': 'every_open'},
      );
      expect(ok(ending, PromoPopupHistory.none), isTrue);
      expect(
        ok(ending, PromoPopupHistory.none, now.add(const Duration(minutes: 2))),
        isFalse,
      );
    });

    test('the first eligible one in the admin order', () {
      final a = _popup(id: 'a', rules: {'frequency': 'once'});
      final b = _popup(id: 'b', rules: {'frequency': 'once'});
      final seen = {'a': PromoPopupHistory(shown: 1, lastShownAt: now)};
      final pick = PromoPopupRulesCheck.pick(
        [a, b],
        (id) => seen[id] ?? PromoPopupHistory.none,
        now,
      );
      expect(pick?.id, 'b');
    });

    test('the phone remembers shows and closes (and trims to 100)', () async {
      await PromoPopupStore.clear();
      final at = DateTime(2026, 11, 2, 10);
      await PromoPopupStore.shown('x', at);
      await PromoPopupStore.closed(
        'x',
        at.add(const Duration(minutes: 1)),
        acted: true,
      );
      final h = PromoPopupStore.of('x');
      expect(h.shown, 1);
      expect(h.acted, isTrue);
      expect(h.lastClosedAt, at.add(const Duration(minutes: 1)));
      for (var i = 0; i < 105; i++) {
        await PromoPopupStore.shown('p$i', at.add(Duration(minutes: i)));
      }
      expect(PromoPopupStore.of('p104').shown, 1);
      expect(PromoPopupStore.of('x').shown, 0, reason: 'the oldest went');
      await PromoPopupStore.clear();
    });
  });

  test('countdown units: hours, then days', () {
    expect(
      PromoCountdown.units(
        const Duration(hours: 5, minutes: 7, seconds: 9),
      ).map((u) => u.$1),
      [5, 7, 9],
    );
    expect(
      PromoCountdown.units(
        const Duration(days: 5, hours: 3, minutes: 2),
      ).map((u) => u.$1),
      [5, 3, 2],
    );
    expect(
      PromoCountdown.units(
        const Duration(hours: 30, minutes: 1, seconds: 4),
        daysFromHours: 24,
        showSecondsWithDays: true,
      ).map((u) => u.$1),
      [1, 6, 1, 4],
    );
  });

  group('every template draws', () {
    Future<void> host(
      WidgetTester tester,
      Widget child, {
      required double width,
      required ThemeMode theme,
    }) async {
      tester.view
        ..physicalSize = Size(width, 800) * 3
        ..devicePixelRatio = 3;
      addTearDown(tester.view.reset);
      // A cached asset read from an earlier test never completes in this one.
      rootBundle.clear();
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light(),
          darkTheme: AppTheme.dark(),
          themeMode: theme,
          supportedLocales: AppI18n.supportedLocales,
          localizationsDelegates: [
            AppI18n.delegate,
            ...GlobalMaterialLocalizations.delegates,
          ],
          home: Scaffold(body: Center(child: child)),
        ),
      );
      // The translations load from the asset bundle (real I/O).
      for (var i = 0; i < 6; i++) {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 20)),
        );
        await tester.pump(const Duration(milliseconds: 200));
      }
    }

    for (final width in [320.0, 412.0]) {
      for (final theme in [ThemeMode.light, ThemeMode.dark]) {
        for (final t in PromoBannerTemplate.values) {
          for (final side in ['right', 'left']) {
            testWidgets(
              'banner ${t.wire} $side ${width.toInt()} ${theme.name}',
              (tester) async {
                // No network in tests: the template with its image box
                // empty (the layout is the same).
                final b = PromoBanner(
                  id: 'b',
                  template: t,
                  content: PromoContent.fromJson(
                    _full(t.wire, extra: {'imageSide': side, 'image': null}),
                  ),
                );
                final cardWidth = width - 24;
                await host(
                  tester,
                  PromoBannerCard(banner: b, width: cardWidth, onTap: () {}),
                  width: width,
                  theme: theme,
                );
                expect(tester.takeException(), isNull);
                expect(
                  tester.getSize(find.byType(PromoBannerCard)).height,
                  closeTo(t.baseHeight * cardWidth / 340, 0.5),
                );
                await tester.pumpWidget(const SizedBox());
              },
            );
          }
        }
        for (final t in PromoPopupTemplate.values) {
          testWidgets('popup ${t.wire} ${width.toInt()} ${theme.name}', (
            tester,
          ) async {
            final json = _full(t.wire, extra: {'image': null});
            final p = PromoPopup(
              id: 'p',
              template: t,
              content: PromoContent.fromJson(json),
              secondaryLabel: 'Maybe later',
            );
            final callbacks = PromoPopupCallbacks(onExit: (_) {});
            final Widget view = switch (t) {
              PromoPopupTemplate.bottomSheet => Align(
                alignment: Alignment.bottomCenter,
                child: PromoPopupSheet(popup: p, callbacks: callbacks),
              ),
              PromoPopupTemplate.fullscreen => PromoPopupFullscreen(
                popup: p,
                callbacks: callbacks,
              ),
              _ => PromoPopupCard(
                popup: p,
                width: PromoPopupCard.widthFor(width),
                maxHeight: 760,
                callbacks: callbacks,
              ),
            };
            await host(tester, view, width: width, theme: theme);
            expect(tester.takeException(), isNull);
            await tester.pumpWidget(const SizedBox());
          });
        }
      }
    }
  });

  group('app-open popup', () {
    final opened = <String>[];

    setUp(() async {
      opened.clear();
      PromoBannerActions.openAppLink = (link) async => opened.add(link);
      await PromoPopupStore.clear();
      ExternalOpen.reset();
      PromoPopupController.instance.debugReset();
    });

    tearDown(() {
      PromoBannerActions.reset();
      PromoPopupController.instance.debugReset();
    });

    Future<void> openHome(WidgetTester tester) async {
      phone(tester);
      await pumpRoutes(
        tester,
        HookBuilder(
          builder: (context) {
            usePromoPopups(context);
            return const Scaffold(body: Text('HOME SCREEN'));
          },
        ),
      );
    }

    JsonMap feed(
      Map<String, Object?> rules, {
      String template = 'offer_card',
    }) => {
      'enabled': true,
      'openGapMinutes': 30,
      'popups': [
        {
          ..._full(template),
          'id': 'pop',
          'image': null,
          'rules': {'delaySeconds': 1, ...rules},
        },
      ],
    };

    testWidgets('shows after its delay; X closes it; it waits for its hours', (
      tester,
    ) async {
      final backend = await resetHost();
      backend.replies['GET /api/app-popups'] = (_) =>
          feed({'frequency': 'after_close', 'reshowAfterHours': 24});
      await openHome(tester);
      expect(find.text('Claim now'), findsNothing, reason: 'its delay first');
      await pumpFor(tester, 1600);
      expect(find.text('Claim now'), findsOneWidget);
      expect(find.text('WELCOME100'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('promo-popup-close')));
      await pumpFor(tester, 600);
      expect(find.text('Claim now'), findsNothing);
      final h = PromoPopupStore.of('pop');
      expect(h.shown, 1);
      expect(h.lastClosedAt, isNotNull);
      expect(h.acted, isFalse);
      // Back after a long time away, but inside its 24 h: not again.
      final controller = PromoPopupController.instance;
      PromoPopupController.now = () =>
          DateTime.now().add(const Duration(hours: 2));
      controller.lifecycle(AppLifecycleState.paused);
      PromoPopupController.now = () =>
          DateTime.now().add(const Duration(hours: 3));
      controller.lifecycle(AppLifecycleState.resumed);
      await pumpFor(tester, 1600);
      expect(find.text('Claim now'), findsNothing);
      await finishHost(tester);
    });

    testWidgets('the button runs the action and stops it for good', (
      tester,
    ) async {
      final backend = await resetHost();
      backend.replies['GET /api/app-popups'] = (_) =>
          feed({'frequency': 'every_open'});
      await openHome(tester);
      await pumpFor(tester, 1600);
      await tester.tap(find.byKey(const ValueKey('promo-popup-cta')));
      await pumpFor(tester, 600);
      expect(opened, ['vibecalling://wallet?amount=199']);
      expect(PromoPopupStore.of('pop').acted, isTrue);
      await finishHost(tester);
    });

    testWidgets('an open from a link or a notification gets no popup', (
      tester,
    ) async {
      final backend = await resetHost();
      backend.replies['GET /api/app-popups'] = (_) =>
          feed({'frequency': 'every_open'});
      ExternalOpen.mark('push');
      await openHome(tester);
      await pumpFor(tester, 2000);
      expect(find.text('Claim now'), findsNothing);
      expect(PromoPopupStore.of('pop').shown, 0);
      await finishHost(tester);
    });

    testWidgets('popups off: nothing', (tester) async {
      final backend = await resetHost();
      backend.replies['GET /api/app-popups'] = (_) => {
        'enabled': false,
        'popups': [],
      };
      await openHome(tester);
      await pumpFor(tester, 2000);
      expect(find.text('Claim now'), findsNothing);
      await finishHost(tester);
    });

    testWidgets('a sheet over Home holds it, then it gives up', (tester) async {
      final backend = await resetHost();
      backend.replies['GET /api/app-popups'] = (_) =>
          feed({'frequency': 'every_open'});
      PromoPopupController.safeWait = const Duration(seconds: 2);
      await openHome(tester);
      final ctx = tester.element(find.text('HOME SCREEN'));
      unawaited(
        showModalBottomSheet<void>(
          context: ctx,
          builder: (_) =>
              const SizedBox(height: 200, child: Text('OTHER SHEET')),
        ),
      );
      await pumpFor(tester, 4500);
      expect(find.text('OTHER SHEET'), findsOneWidget);
      expect(find.text('Claim now'), findsNothing);
      expect(PromoPopupStore.of('pop').shown, 0);
      await finishHost(tester);
    });
  });

  test('AppPrefs is ready', () => expect(AppPrefs.getString('nope'), isNull));
}
