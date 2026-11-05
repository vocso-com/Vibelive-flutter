import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vibelive/app/api/instant_call/instant_call_api.dart';
import 'package:vibelive/app/component/morph_fab.dart';
import 'package:vibelive/app/homescreen/discover/talk_now_button.dart';
import 'package:vibelive/app/navbar/bottombar/navbar_collapse.dart';
import 'package:vibelive/core/network/api_exception.dart';
import 'package:vibelive/core/theme/app_colors.dart';

import 'host_onboarding_support/harness.dart';

/// Talk Now: shown only while the server has it on for this user, and its
/// refusals in the user's own words. On Discover it floats as a pill that
/// folds into a round call button.
void main() {
  setUpAll(() async {
    await setUpHostHarness();
  });
  // Each test is a fresh app launch: the intro (pill, then fold) plays.
  // Calls placed by a tap: (video?), without starting the call layer.
  final placed = <bool>[];
  final realPlace = TalkNowButton.placeCall;
  setUp(() {
    MorphFab.resetIntros();
    placed.clear();
    TalkNowButton.placeCall =
        ({bool video = false, int? maxRingSeconds}) async => placed.add(video);
  });
  tearDown(() {
    NavbarCollapse.instance.value = false;
    TalkNowButton.placeCall = realPlace;
  });

  Future<void> open(
    WidgetTester tester, {
    bool reduceMotion = false,
    ThemeMode theme = ThemeMode.light,
  }) async {
    phone(tester);
    const button = Scaffold(body: Column(children: [TalkNowButton()]));
    await pumpRoutes(
      tester,
      reduceMotion
          ? Builder(
              builder: (context) => MediaQuery(
                data: MediaQuery.of(context).copyWith(disableAnimations: true),
                child: button,
              ),
            )
          : button,
      theme: theme,
    );
    await pumpFor(tester, 400);
  }

  Finder button() => find.byKey(const ValueKey('talk-now'));

  /// The morphing box (the circle's tap target fills it).
  Size box(WidgetTester tester) =>
      tester.getSize(find.byKey(const ValueKey('morph-fab-circle')));

  bool folded(WidgetTester tester) {
    final s = box(tester);
    return s.width < 100 && (s.width - s.height).abs() < 0.5;
  }

  testWidgets('hidden while the server has Talk Now off', (tester) async {
    await resetHost();
    await open(tester);
    expect(button(), findsNothing);
    await finishHost(tester);
  });

  testWidgets('shown once the server has it on', (tester) async {
    final backend = await resetHost();
    backend.instantConfig = {
      'enabled': true,
      'allowedCallTypes': 'voice_only',
      'callerVoiceRate': 10,
    };
    await open(tester);
    expect(button(), findsWidgets);
    await finishHost(tester);
  });

  // Talk Now connects whoever is free, so the caller never sees a host's own
  // price first. Without the rate on the button the only way to learn what it
  // costs was to be charged it.
  testWidgets('the per-minute rate is on the button', (tester) async {
    final backend = await resetHost();
    backend.instantConfig = {
      'enabled': true,
      'allowedCallTypes': 'voice_only',
      'callerVoiceRate': 12,
    };
    await open(tester);
    expect(find.textContaining('12'), findsWidgets);
    await finishHost(tester);
  });

  testWidgets('an older backend that sends no rate still shows the button', (
    tester,
  ) async {
    // Better a button with no price than no way to call at all.
    final backend = await resetHost();
    backend.instantConfig = {'enabled': true, 'allowedCallTypes': 'voice_only'};
    await open(tester);
    expect(button(), findsWidgets);
    await finishHost(tester);
  });

  // `both` used to place a voice call with no way to ask for video and no sign
  // that video existed at all. Now the pill shows both with their rates and a
  // tap opens a bubble menu to choose.
  testWidgets('both call types: the pill shows voice and video with rates', (
    tester,
  ) async {
    final backend = await resetHost();
    backend.instantConfig = {
      'enabled': true,
      'allowedCallTypes': 'both',
      'callerVoiceRate': 10,
      'callerVideoRate': 25,
    };
    await open(tester);
    expect(find.byKey(const ValueKey('talk-now-voice')), findsOneWidget);
    expect(find.byKey(const ValueKey('talk-now-video')), findsOneWidget);
    expect(find.textContaining('10'), findsWidgets);
    expect(find.textContaining('25'), findsWidgets);
    await finishHost(tester);
  });

  testWidgets('one allowed type stays one button', (tester) async {
    final backend = await resetHost();
    backend.instantConfig = {
      'enabled': true,
      'allowedCallTypes': 'video_only',
      'callerVideoRate': 25,
    };
    await open(tester);
    expect(find.byKey(const ValueKey('talk-now-call')), findsOneWidget);
    expect(find.byKey(const ValueKey('talk-now-voice')), findsNothing);
    expect(find.byKey(const ValueKey('talk-now-video')), findsNothing);
    expect(find.textContaining('25'), findsWidgets);
    await finishHost(tester);
  });

  // ── The pill that folds into a call button ──────────────────────────────

  const voiceOnly = {
    'enabled': true,
    'allowedCallTypes': 'voice_only',
    'callerVoiceRate': 12,
  };

  testWidgets('arrives as the full pill, folds into the circle after 3 s; '
      'ONE tap on the circle places the call; a long press opens the pill, '
      'and it folds back by itself', (tester) async {
    final backend = await resetHost();
    backend.instantConfig = voiceOnly;
    await open(tester);

    expect(box(tester).width, greaterThan(300));
    expect(find.text('Talk Now'), findsOneWidget);
    await pumpFor(tester, 2000);
    expect(folded(tester), isFalse, reason: 'still within the 3 s');

    await pumpFor(tester, 2800);
    expect(folded(tester), isTrue);

    // The price is on the circle itself, so one tap is enough: a badge on
    // its bottom edge, centred, the icon keeping the whole circle.
    final circle = tester.getRect(
      find.byKey(const ValueKey('morph-fab-circle')),
    );
    final badge = find.byKey(const ValueKey('morph-fab-badge'));
    expect(
      find.descendant(of: badge, matching: find.text('₹12/MIN')),
      findsOneWidget,
    );
    final chip = tester.getRect(badge);
    expect((chip.center.dx - circle.center.dx).abs(), lessThan(1.5));
    expect((chip.center.dy - circle.bottom).abs(), lessThan(circle.height / 4));
    await tester.tap(find.byKey(const ValueKey('morph-fab-circle')));
    await pumpFor(tester, 300);
    expect(placed, [false], reason: 'one tap, one voice call');
    expect(folded(tester), isTrue, reason: 'no "open first" step');

    // A long press opens the pill again; it folds back by itself.
    await tester.longPress(find.byKey(const ValueKey('morph-fab-circle')));
    await pumpFor(tester, 900);
    expect(box(tester).width, greaterThan(300));
    expect(placed, [false], reason: 'opening it places nothing');
    await pumpFor(tester, 4200);
    expect(folded(tester), isTrue);
    await finishHost(tester);
  });

  testWidgets('both types: a tap opens the bubble menu; each bubble places its '
      'own call type', (tester) async {
    final backend = await resetHost();
    backend.instantConfig = {
      'enabled': true,
      'allowedCallTypes': 'both',
      'callerVoiceRate': 10,
      'callerVideoRate': 25,
    };
    await open(tester);

    // Folds to the circle; one tap opens the bubble menu (voice + video).
    await pumpFor(tester, 5000);
    expect(folded(tester), isTrue);
    await tester.tap(find.byKey(const ValueKey('morph-fab-circle')));
    await pumpFor(tester, 500);
    expect(find.byKey(const ValueKey('talk-now-menu-voice')), findsOneWidget);
    expect(find.byKey(const ValueKey('talk-now-menu-video')), findsOneWidget);

    // Picking video places a video call and closes the menu.
    await tester.tap(find.byKey(const ValueKey('talk-now-menu-video')));
    await pumpFor(tester, 500);
    expect(placed, [true]);
    expect(find.byKey(const ValueKey('talk-now-menu-video')), findsNothing);

    // Open again and pick voice.
    await tester.tap(find.byKey(const ValueKey('morph-fab-circle')));
    await pumpFor(tester, 500);
    await tester.tap(find.byKey(const ValueKey('talk-now-menu-voice')));
    await pumpFor(tester, 500);
    expect(placed, [true, false]);
    await finishHost(tester);
  });

  testWidgets('video only: the circle shows video and places video', (
    tester,
  ) async {
    final backend = await resetHost();
    backend.instantConfig = {
      'enabled': true,
      'allowedCallTypes': 'video_only',
      'callerVideoRate': 25,
    };
    await open(tester);
    await pumpFor(tester, 5000);
    expect(folded(tester), isTrue);
    await tester.tap(find.byKey(const ValueKey('morph-fab-circle')));
    await pumpFor(tester, 300);
    expect(placed, [true]);
    await finishHost(tester);
  });

  testWidgets('lime with dark text in light mode and dark mode alike', (
    tester,
  ) async {
    for (final theme in [ThemeMode.light, ThemeMode.dark]) {
      MorphFab.resetIntros();
      final backend = await resetHost();
      backend.instantConfig = voiceOnly;
      await open(tester, theme: theme);
      final gradients = [
        for (final box in tester.widgetList<DecoratedBox>(
          find.descendant(of: button(), matching: find.byType(DecoratedBox)),
        ))
          if (box.decoration case BoxDecoration(
            gradient: final LinearGradient g,
          ))
            g.colors.first,
      ];
      expect(gradients, contains(BrandColors.lime), reason: '$theme');
      final title = tester.widget<Text>(find.text('Talk Now'));
      expect(title.style?.color, AppColors.black, reason: '$theme');
      await finishHost(tester);
    }
  });

  testWidgets('scrolling the feed folds it early', (tester) async {
    final backend = await resetHost();
    backend.instantConfig = voiceOnly;
    await open(tester);
    expect(folded(tester), isFalse);
    NavbarCollapse.instance.value = true;
    await pumpFor(tester, 900);
    expect(folded(tester), isTrue);
    await finishHost(tester);
  });

  testWidgets('the intro plays once per launch: later it arrives folded', (
    tester,
  ) async {
    final backend = await resetHost();
    backend.instantConfig = voiceOnly;
    await open(tester);
    expect(folded(tester), isFalse);
    await finishHost(tester);

    // Discover built again in the same launch (no reset in between).
    final again = await resetHost();
    again.instantConfig = voiceOnly;
    await open(tester);
    expect(folded(tester), isTrue);
    await finishHost(tester);
  });

  testWidgets('"reduce motion": the fold lands at once', (tester) async {
    final backend = await resetHost();
    backend.instantConfig = voiceOnly;
    await open(tester, reduceMotion: true);
    expect(folded(tester), isFalse);
    await pumpFor(tester, 3050);
    expect(folded(tester), isTrue);
    await finishHost(tester);
  });

  // The server answers per user (company accounts or all, as the admin
  // set it); a host still never sees it unless a company account.
  testWidgets('hidden from a host, shown to a company account', (tester) async {
    const on = {
      'enabled': true,
      'allowedCallTypes': 'voice_only',
      'callerVoiceRate': 10,
    };
    const expert = {'id': 9, 'documentId': 'e9'};
    var backend = await resetHost(expert: expert);
    backend.instantConfig = on;
    await open(tester);
    expect(button(), findsNothing, reason: 'a host');
    await finishHost(tester);

    backend = await resetHost(
      user: {'id': 1, 'documentId': 'u1', 'is_company_account': true},
      expert: expert,
    );
    backend.instantConfig = on;
    await open(tester);
    expect(button(), findsWidgets, reason: 'a company account (a host too)');
    await finishHost(tester);
  });

  test('nobody free: "no one is free", not "invalid response"', () async {
    await resetHost();
    await expectLater(
      InstantCallApi.initiate(callerId: 1),
      throwsA(
        isA<ApiException>().having(
          (e) => e.messageKey,
          'messageKey',
          InstantCallErrorKeys.noHosts,
        ),
      ),
    );
  });

  test("the server's refusals map to our own translated copy", () {
    ApiException e(ApiErrorType t, String msg, [Object? data]) =>
        ApiException(t, serverMessage: msg, data: data);
    expect(
      InstantCallApi.knownErrorKey(
        e(ApiErrorType.rejected, 'Insufficient balance.', {
          'code': 'LOW_BALANCE',
        }),
      ),
      InstantCallErrorKeys.lowBalance,
    );
    expect(
      InstantCallApi.knownErrorKey(
        e(ApiErrorType.rejected, 'Talk Now is currently disabled.'),
      ),
      InstantCallErrorKeys.disabled,
    );
    expect(
      InstantCallApi.knownErrorKey(e(ApiErrorType.forbidden, 'Forbidden')),
      InstantCallErrorKeys.disabled,
    );
    expect(
      InstantCallApi.knownErrorKey(
        e(
          ApiErrorType.rejected,
          'You already have an active Talk Now session.',
        ),
      ),
      InstantCallErrorKeys.alreadyActive,
    );
    expect(
      InstantCallApi.knownErrorKey(e(ApiErrorType.server, 'boom')),
      isNull,
    );
  });
}
