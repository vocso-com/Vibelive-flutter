import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:vibelive/app/paymentscreen/wallet/helper/first_topup_launch.dart';
import 'package:vibelive/app/paymentscreen/wallet/helper/first_topup_offer.dart';
import 'package:vibelive/app/paymentscreen/wallet/widgets/first_topup_popup.dart';
import 'package:vibelive/app/promo/popup/promo_popup_controller.dart';
import 'package:vibelive/app/promo/popup/promo_popup_rules.dart';
import 'package:vibelive/core/router/external_open.dart';
import 'package:vibelive/core/storage/app_prefs.dart';
import 'package:vibelive/core/utils/scale.dart';

import 'host_onboarding_support/harness.dart';

/// The first-top-up offer: the app-open popup for someone who never paid in,
/// with every amount the wallet sells (the admin's presets).
void main() {
  setUpAll(setUpHostHarness);

  final realPrepare = FirstTopupLaunch.prepare;
  setUp(() async {
    await PromoPopupStore.clear();
    ExternalOpen.reset();
    PromoPopupController.instance.debugReset();
    FirstTopupOffer.debugResetSession();
    await AppPrefs.remove('wallet:first_topup_offer_shown');
    await AppPrefs.remove('wallet:first_topup_offer_dismissed');
  });
  tearDown(() {
    PromoPopupController.instance.debugReset();
    FirstTopupLaunch.prepare = realPrepare;
  });

  const plan = FirstTopupPlan(
    percent: 50,
    amounts: [99, 199, 299, 499, 999, 1999],
    voiceRate: 4,
  );

  /// A button that opens the popup and keeps what it returned.
  Future<List<int?>> openPopup(
    WidgetTester tester, {
    FirstTopupPlan with_ = plan,
    Locale locale = const Locale('en'),
    ThemeMode theme = ThemeMode.light,
  }) async {
    final results = <int?>[];
    await pumpRoutes(
      tester,
      Builder(
        builder: (context) => Scaffold(
          body: Center(
            child: TextButton(
              onPressed: () async =>
                  results.add(await showFirstTopupPopup(context, with_)),
              child: const Text('OPEN'),
            ),
          ),
        ),
      ),
      locale: locale,
      theme: theme,
    );
    await tester.tap(find.text('OPEN'));
    await pumpFor(tester, 700);
    return results;
  }

  testWidgets('every wallet amount, the middle one popular and picked', (
    tester,
  ) async {
    await resetHost();
    phone(tester);
    final results = await openPopup(tester);

    for (final a in plan.amounts) {
      expect(find.byKey(ValueKey('first-topup-amount-$a')), findsOneWidget);
    }
    expect(find.text('POPULAR'), findsOneWidget);
    expect(find.text('+50% EXTRA'), findsOneWidget);
    // 299 is picked for them: + ₹150 free.
    expect(find.text('Add ₹299 & get ₹150'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('first-topup-amount-999')));
    await pumpFor(tester, 600);
    expect(find.text('Add ₹999 & get ₹500'), findsOneWidget);
    expect(find.text('+₹500 FREE'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('first-topup-cta')));
    await pumpFor(tester, 600);
    expect(results, [999]);
    expect(find.byKey(const ValueKey('first-topup-popup')), findsNothing);
    await finishHost(tester);
  });

  testWidgets('the X and "not now" both close it with nothing chosen', (
    tester,
  ) async {
    await resetHost();
    phone(tester);
    final results = await openPopup(tester);
    await tester.tap(find.byKey(const ValueKey('first-topup-close')));
    await pumpFor(tester, 600);
    await tester.tap(find.text('OPEN'));
    await pumpFor(tester, 700);
    await tester.tap(find.byKey(const ValueKey('first-topup-later')));
    await pumpFor(tester, 600);
    expect(results, [null, null]);
    await finishHost(tester);
  });

  for (final lang in ['en', 'hi', 'bn', 'mr', 'ta', 'gu', 'ur', 'kn', 'or']) {
    testWidgets('$lang: a small phone with big text never overflows', (
      tester,
    ) async {
      await resetHost();
      tester.view
        ..physicalSize = const Size(320, 600) * 3
        ..devicePixelRatio = 3;
      tester.platformDispatcher.textScaleFactorTestValue = 1.4;
      addTearDown(tester.view.reset);
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      Scale.update(const Size(320, 600));
      await pumpRoutes(
        tester,
        Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: TextButton(
                onPressed: () => showFirstTopupPopup(context, plan),
                child: const Text('OPEN'),
              ),
            ),
          ),
        ),
        locale: Locale(lang),
        theme: ThemeMode.dark,
      );
      // The language's files load from disk (real time, not the test clock).
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 300)),
      );
      await pumpFor(tester, 100);
      await tester.tap(find.text('OPEN'));
      await pumpFor(tester, 700);
      expect(find.byKey(const ValueKey('first-topup-popup')), findsOneWidget);
      expect(tester.takeException(), isNull, reason: lang);
      await finishHost(tester);
    });
  }

  group('on app open', () {
    Future<GoRouter> openHome(WidgetTester tester) async {
      phone(tester);
      return pumpRoutes(
        tester,
        HookBuilder(
          builder: (context) {
            usePromoPopups(context);
            return const Scaffold(body: Text('HOME SCREEN'));
          },
        ),
      );
    }

    /// What the app asked `/transactions` (the "ever paid in" check).
    final asked = <Map<String, dynamic>>[];

    void serverSays(
      HostBackend backend, {
      bool bonusOn = true,
      bool paid = false,
    }) {
      asked.clear();
      backend.replies['GET /api/app-config'] = (_) => {
        'data': {
          'bonus': {
            'firstTopupBonusEnabled': bonusOn,
            'firstTopupBonusPercent': 50,
          },
          'presetAmounts': [149, 299, 499, 999],
        },
      };
      backend.replies['GET /api/transactions'] = (o) {
        asked.add(o.queryParameters);
        return {
          'data': paid
              ? [
                  {'id': 5, 'transactionType': 'topup', 'method': 'Razorpay'},
                ]
              : <Object>[],
        };
      };
      // The admin's popup, which the offer goes ahead of.
      backend.replies['GET /api/app-popups'] = (_) => {
        'enabled': true,
        'openGapMinutes': 30,
        'popups': <Object>[],
      };
    }

    testWidgets('never paid in: it grows in on Home and opens the wallet', (
      tester,
    ) async {
      final backend = await resetHost();
      serverSays(backend);
      PromoPopupController.firstTopup = FirstTopupLaunch.prepare;
      final router = await openHome(tester);
      await pumpFor(tester, 1800);
      expect(find.byKey(const ValueKey('first-topup-popup')), findsOneWidget);
      // The wallet's own amounts, all of them.
      for (final a in [149, 299, 499, 999]) {
        expect(find.byKey(ValueKey('first-topup-amount-$a')), findsOneWidget);
      }
      // Asked of the server: a successful Razorpay / PayU top-up.
      expect(asked, hasLength(1));
      expect(asked.single[r'filters[transactionType][$eq]'], 'topup');
      expect(asked.single[r'filters[paymentStatus][$eq]'], 'success');
      expect(asked.single[r'filters[method][$in][0]'], 'Razorpay');

      await tester.tap(find.byKey(const ValueKey('first-topup-cta')));
      await pumpFor(tester, 800);
      expect(find.text('ROUTE /wallet'), findsOneWidget);
      final top = router.routerDelegate.currentConfiguration.last;
      expect(top.matchedLocation, '/wallet');
      // A pushed route keeps its own address, query and all.
      final at = (top as ImperativeRouteMatch).matches.uri;
      expect(at.queryParameters['amount'], '299');
      expect(at.queryParameters['reason'], 'first_topup_offer');
      await finishHost(tester);
    });

    testWidgets('already paid in, or the bonus off: no offer', (tester) async {
      final backend = await resetHost();
      serverSays(backend, paid: true);
      PromoPopupController.firstTopup = FirstTopupLaunch.prepare;
      await openHome(tester);
      await pumpFor(tester, 2500);
      expect(find.byKey(const ValueKey('first-topup-popup')), findsNothing);
      await finishHost(tester);

      final off = await resetHost();
      serverSays(off, bonusOn: false);
      FirstTopupOffer.debugResetSession();
      PromoPopupController.instance.debugReset();
      PromoPopupController.firstTopup = FirstTopupLaunch.prepare;
      await openHome(tester);
      await pumpFor(tester, 2500);
      expect(find.byKey(const ValueKey('first-topup-popup')), findsNothing);
      await finishHost(tester);
    });

    testWidgets('a company account or a host never gets it', (tester) async {
      final backend = await resetHost(
        user: {
          'id': 1,
          'documentId': 'u1',
          'name': 'Asha',
          'role': 'Client',
          'is_company_account': true,
        },
      );
      serverSays(backend);
      expect(await FirstTopupLaunch.prepare(), isNull);
      await finishHost(tester);
    });

    test('caps: once a session, never after two "not now"s', () async {
      expect(FirstTopupOffer.mayShow(percent: 50), isTrue);
      expect(FirstTopupOffer.claimShow(enabled: true, percent: 50), isTrue);
      expect(FirstTopupOffer.mayShow(percent: 50), isFalse, reason: 'session');
      FirstTopupOffer.debugResetSession();
      FirstTopupOffer.recordDismissal();
      FirstTopupOffer.recordDismissal();
      await Future<void>.delayed(Duration.zero);
      expect(FirstTopupOffer.mayShow(percent: 50), isFalse);
    });
  });

  // FIRST_TOPUP_RENDER_DIR=<dir> flutter test test/ui/first_topup_popup_test.dart
  final renderDir = Platform.environment['FIRST_TOPUP_RENDER_DIR'];
  group('renders', skip: renderDir == null, () {
    setUpAll(() async {
      Future<void> load(String family, List<String> files) async {
        final loader = FontLoader(family);
        for (final f in files) {
          final bytes = File(f).readAsBytesSync();
          loader.addFont(Future.value(ByteData.view(bytes.buffer)));
        }
        await loader.load();
      }

      const sdk =
          '/Users/devloper/Dev/flutter/bin/cache/artifacts/material_fonts';
      final home = Platform.environment['HOME'];
      await load('Roboto', [
        for (final w in ['Regular', 'Medium', 'Bold', 'Black'])
          '$sdk/Roboto-$w.ttf',
      ]);
      await load('MaterialIcons', ['$sdk/MaterialIcons-Regular.otf']);
      await load('packages/lucide_icons_flutter/Lucide', [
        '$home/.pub-cache/hosted/pub.dev/lucide_icons_flutter-4.0.0/assets/lucide.ttf',
      ]);
    });

    for (final dark in [false, true]) {
      testWidgets('popup ${dark ? 'dark' : 'light'}', (tester) async {
        await resetHost();
        phone(tester, size: const Size(375, 812));
        await openPopup(tester, theme: dark ? ThemeMode.dark : ThemeMode.light);
        await pumpFor(tester, 900);
        final view = tester.binding.renderViews.first;
        await tester.runAsync(() async {
          final layer = view.debugLayer! as OffsetLayer;
          // The root layer is in physical pixels.
          final image = await layer.toImage(
            Offset.zero & (view.size * 3),
            pixelRatio: 2 / 3,
          );
          final png = await image.toByteData(format: ui.ImageByteFormat.png);
          File('$renderDir/first_topup_${dark ? 'dark' : 'light'}.png')
            ..createSync(recursive: true)
            ..writeAsBytesSync(png!.buffer.asUint8List());
        });
        await finishHost(tester);
      });
    }
  });

  test('amounts: every preset, lowest first, once; the middle suggested', () {
    expect(FirstTopupOffer.amounts([499, 99, 0, 199, 99]), [99, 199, 499]);
    expect(FirstTopupOffer.suggested([99, 199, 499]), 199);
    expect(FirstTopupOffer.suggested([99, 199]), 199);
    expect(FirstTopupOffer.suggested([99]), 99);
    expect(FirstTopupOffer.suggested(const []), isNull);
    expect(FirstTopupOffer.suggested([1, 2, 3, 4, 5, 6]), 3);
  });
}
