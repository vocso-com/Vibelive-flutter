import 'dart:async';

import 'package:clock/clock.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vibelive/app/callscreen/call/call_pip.dart';
import 'package:vibelive/app/api/free_call/free_call_models.dart';
import 'package:vibelive/app/callscreen/call/call_screen.dart';
import 'package:vibelive/app/callscreen/call/return_to_call_bar.dart';
import 'package:vibelive/app/callscreen/call/call_topup.dart';
import 'package:vibelive/app/callscreen/helper/call_billing.dart';
import 'package:vibelive/app/paymentscreen/wallet/helper/topup_bonus.dart';
import 'package:vibelive/app/paymentscreen/wallet/helper/topup_checkout.dart';
import 'package:vibelive/app/callscreen/call/helper/call_nav.dart';
import 'package:vibelive/app/callscreen/call/helper/pip_clamp.dart';
import 'package:vibelive/app/callscreen/helper/call_controller.dart';
import 'package:vibelive/app/callscreen/helper/call_session.dart';
import 'package:vibelive/app/callscreen/helper/engine/call_engine.dart';
import 'package:vibelive/app/component/pressable.dart';
import 'package:vibelive/core/router/app_router.dart';

import 'call_support/call_harness.dart';

Finder _pressable(String label) =>
    find.byWidgetPredicate((w) => w is Pressable && w.semanticLabel == label);

const _controls = [
  'Microphone',
  'Camera',
  'Speaker',
  'Switch camera',
  'End call',
];

int _shownControls() =>
    _controls.where((l) => _pressable(l).evaluate().isNotEmpty).length;

/// Engine up, remote in the channel (no native views: `rtc` is null).
const _live = CallMedia(engineReady: true, joined: true, remoteUid: 70);

void main() {
  setUpAll(callSetUpAll);
  setUp(callSetUp);

  Future<void> openCall(
    WidgetTester tester,
    CallSession call, {
    CallMedia media = CallMedia.initial,
    Size size = se,
    EdgeInsets safeArea = seInsets,
    Locale locale = const Locale('en'),
  }) async {
    CallEngine.instance.debugSetMedia(media);
    CallController.instance.debugSet(call);
    await pumpCallApp(tester, size: size, safeArea: safeArea, locale: locale);
  }

  testWidgets('calling → ringing: summary, no pill, 3 audio controls', (
    tester,
  ) async {
    await openCall(
      tester,
      callOf(phase: CallPhase.calling, role: CallRole.caller),
    );

    expect(find.byType(CallScreen), findsOneWidget);
    expect(find.text('CALLING'), findsOneWidget);
    expect(find.text('Audio Call'), findsOneWidget);
    expect(find.text('Ananya'), findsOneWidget); // summary
    expect(find.text('ANANYA'), findsOneWidget); // header
    expect(find.textContaining('...'), findsNothing); // no status pill
    expect(_shownControls(), 3);

    await setCall(
      tester,
      callOf(phase: CallPhase.ringing, role: CallRole.caller),
    );
    expect(find.text('RINGING'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await finishCall(tester);
  });

  testWidgets('accepted: "..." pill, status hidden', (tester) async {
    await openCall(tester, callOf(phase: CallPhase.accepted));
    expect(find.text('...'), findsOneWidget);
    expect(find.text('CALLING'), findsNothing);
    expect(find.text('RINGING'), findsNothing);
    await finishCall(tester);
  });

  testWidgets('ongoing: the pill ticks, and only the pill rebuilds', (
    tester,
  ) async {
    final start = clock.now().subtract(const Duration(seconds: 65));
    await openCall(
      tester,
      callOf(phase: CallPhase.ongoing, connectedAt: start),
    );
    expect(find.text('01:05'), findsOneWidget);

    // The controller reads `clock`: fake time drives the tick.
    final rebuilt = await countRebuilds(() async {
      await tester.pump(const Duration(seconds: 1));
    });
    expect(find.text('01:06'), findsOneWidget);
    // A tick rebuilds the pill's timer text only: never the screen, its
    // header, body, summary or controls (animations repaint on their own).
    expect(rebuilt['ValueListenableBuilder<int>'], 1);
    for (final type in const [
      'CallScreen',
      'CallHeader',
      '_Centre',
      '_StatusPill',
      'CallBody',
      '_VideoLayer',
      '_InfoCard',
      'CallSummary',
      'CallControls',
      '_Toggle',
    ]) {
      expect(rebuilt[type], isNull, reason: type);
    }
    await finishCall(tester);
  });

  testWidgets('ended without connecting: "Declined", no controls', (
    tester,
  ) async {
    await openCall(
      tester,
      callOf(phase: CallPhase.calling, role: CallRole.caller),
    );
    await setCall(
      tester,
      callOf(
        phase: CallPhase.ended,
        role: CallRole.caller,
        endedAt: DateTime.now(),
      ),
    );

    expect(find.text('Declined'), findsOneWidget);
    expect(find.text('CALL ENDED'), findsOneWidget); // summary
    expect(find.text('CALL ENDED...'), findsOneWidget); // header pill
    expect(_shownControls(), 0);
    await pumpMs(tester, 1300); // post-call exit (logic's) fires quietly
    await finishCall(tester);
  });

  testWidgets('ended after talking: mm:ss, minutes uncapped', (tester) async {
    final end = DateTime(2026, 10, 21, 12);
    await openCall(
      tester,
      callOf(
        phase: CallPhase.ended,
        connectedAt: end.subtract(const Duration(minutes: 61, seconds: 5)),
        endedAt: end,
      ),
    );
    expect(find.text('61:05'), findsOneWidget);
    expect(find.text('Declined'), findsNothing);
    await finishCall(tester);
  });

  testWidgets('video: 5 controls, own name label, PiP swap and clamp', (
    tester,
  ) async {
    await openCall(
      tester,
      callOf(
        phase: CallPhase.ongoing,
        video: true,
        connectedAt: DateTime.now(),
      ),
      media: _live,
    );

    expect(_shownControls(), 5);
    expect(find.text('Video Call'), findsNothing); // no info card on video
    // Remote full screen (bottom-left label), own tile in the PiP.
    expect(find.text('ANANYA'), findsNWidgets(2)); // header + label
    expect(find.text('ASHA'), findsOneWidget); // PiP

    final pip = find.text('ASHA');
    await tester.tap(pip); // quick tap = swap
    await pumpMs(tester, 100);
    expect(find.text('ASHA'), findsOneWidget); // now bottom-left
    expect(find.text('ANANYA'), findsNWidgets(2)); // header + PiP

    // Dragging far away keeps the tile on screen, above the controls.
    final pipLabel = find.descendant(
      of: find.byType(CallPip),
      matching: find.text('ANANYA'),
    );
    final before = tester.getRect(pipLabel);
    await tester.timedDrag(
      pipLabel,
      const Offset(-1000, 1000),
      const Duration(milliseconds: 400),
    );
    await pumpMs(tester, 100);
    final after = tester.getRect(pipLabel);
    expect(after.left, lessThan(before.left));
    expect(after.left, greaterThanOrEqualTo(PipLayout.edgeMargin));
    expect(
      after.bottom,
      lessThanOrEqualTo(se.height - PipLayout.controlsClearance),
    );
    // A drag is not a tap: still swapped.
    expect(find.text('ASHA'), findsOneWidget);
    await finishCall(tester);
  });

  testWidgets('hang-up is held 2.5 s per phase', (tester) async {
    await openCall(
      tester,
      callOf(phase: CallPhase.calling, role: CallRole.caller),
    );
    Pressable hangup() => tester.widget<Pressable>(_pressable('End call'));

    expect(hangup().onPressed, isNull);
    await pumpMs(tester, 2500);
    expect(hangup().onPressed, isNotNull);

    // Connecting swaps the UI: held again.
    await setCall(
      tester,
      callOf(
        phase: CallPhase.ongoing,
        role: CallRole.caller,
        connectedAt: DateTime.now(),
      ),
    );
    expect(hangup().onPressed, isNull);
    await pumpMs(tester, 2500);
    expect(hangup().onPressed, isNotNull);
    await finishCall(tester);
  });

  testWidgets('flag opens the safety panel, X closes it', (tester) async {
    await openCall(
      tester,
      callOf(phase: CallPhase.ongoing, connectedAt: DateTime.now()),
    );

    expect(find.text('SOMETHING WRONG?'), findsNothing);
    await tester.tap(_pressable('SOMETHING WRONG?'));
    await pumpMs(tester, 100);
    expect(find.text('SOMETHING WRONG?'), findsNWidgets(1));
    expect(find.text('Report this call'), findsOneWidget);
    expect(find.text('Block Ananya'), findsOneWidget);
    // Above the control bar.
    expect(
      tester.getRect(find.text('Block Ananya')).bottom,
      lessThan(tester.getRect(_pressable('End call')).top),
    );

    await tester.tap(_pressable('Close'));
    await pumpMs(tester, 100);
    expect(find.text('Report this call'), findsNothing);
    await finishCall(tester);
  });

  for (final (label, locale, name) in const [
    ('long name', Locale('en'), 'Venkata Lakshmi Narasimha Subrahmanyam'),
    ('Hindi', Locale('hi'), 'अनन्या कृष्णमूर्ति शर्मा'),
  ]) {
    testWidgets('320 wide, $label: every phase without overflow', (
      tester,
    ) async {
      await openCall(
        tester,
        callOf(
          phase: CallPhase.calling,
          role: CallRole.caller,
          name: name,
          callerCompany: true,
        ),
        size: narrow,
        locale: locale,
      );
      for (final phase in [CallPhase.ringing, CallPhase.ongoing]) {
        await setCall(
          tester,
          callOf(
            phase: phase,
            role: CallRole.caller,
            name: name,
            video: phase == CallPhase.ongoing,
            callerCompany: true,
            connectedAt: DateTime.now(),
          ),
          media: _live,
        );
        expect(tester.takeException(), isNull);
      }
      await tester.tap(
        _pressable(
          locale.languageCode == 'hi' ? 'कुछ गड़बड़ है?' : 'SOMETHING WRONG?',
        ),
      );
      await setCall(
        tester,
        callOf(
          phase: CallPhase.ended,
          role: CallRole.caller,
          name: name,
          connectedAt: DateTime.now().subtract(const Duration(seconds: 3)),
          endedAt: DateTime.now(),
        ),
      );
      expect(tester.takeException(), isNull);
      await finishCall(tester);
    });
  }

  for (final (label, size, insets) in const [
    ('iPhone SE', se, seInsets),
    ('Pro Max', proMax, proMaxInsets),
  ]) {
    testWidgets('$label: the header sits at the top (U1)', (tester) async {
      await openCall(
        tester,
        callOf(phase: CallPhase.ongoing, connectedAt: DateTime.now()),
        size: size,
        safeArea: insets,
      );
      for (final l in const ['Back', 'SOMETHING WRONG?']) {
        final at = tester.getTopLeft(_pressable(l));
        expect(at.dy, greaterThanOrEqualTo(insets.top), reason: l);
        expect(at.dy, lessThanOrEqualTo(insets.top + 20), reason: l);
      }
      expect(
        tester.getTopLeft(find.text('ANANYA')).dy,
        lessThan(insets.top + 100),
      );
      await finishCall(tester);
    });
  }

  testWidgets('company badges follow the role (U6)', (tester) async {
    // The company's receiver: "App Official" only.
    await openCall(
      tester,
      callOf(
        phase: CallPhase.ongoing,
        company: true,
        callerCompany: true,
        connectedAt: DateTime.now(),
      ),
    );
    expect(find.text('App Official'), findsOneWidget);
    expect(find.text('Company Account'), findsNothing);

    // The company calling: "Company Account" only.
    await setCall(
      tester,
      callOf(
        phase: CallPhase.ongoing,
        role: CallRole.caller,
        callerCompany: true,
        connectedAt: DateTime.now(),
      ),
    );
    expect(find.text('Company Account'), findsOneWidget);
    expect(find.text('App Official'), findsNothing);
    await finishCall(tester);
  });

  testWidgets('hang-up guard counts from the phase start, not mount (U10)', (
    tester,
  ) async {
    Pressable hangup() => tester.widget<Pressable>(_pressable('End call'));

    // Back from Home 3 s into the call: armed at once.
    await openCall(
      tester,
      callOf(
        phase: CallPhase.ongoing,
        connectedAt: clock.now().subtract(const Duration(seconds: 3)),
        phaseSince: clock.now().subtract(const Duration(seconds: 3)),
      ),
    );
    expect(hangup().onPressed, isNotNull);
    await finishCall(tester);

    // Back 1 s in: held only for the 1.5 s left.
    await openCall(
      tester,
      callOf(
        phase: CallPhase.ongoing,
        connectedAt: clock.now().subtract(const Duration(seconds: 1)),
        phaseSince: clock.now().subtract(const Duration(seconds: 1)),
      ),
    );
    // pumpCallApp already pumped 300 ms: armed 1.5 s after mount.
    expect(hangup().onPressed, isNull);
    await pumpMs(tester, 1000);
    expect(hangup().onPressed, isNull);
    await pumpMs(tester, 300);
    expect(hangup().onPressed, isNotNull);
    await finishCall(tester);
  });

  testWidgets('a new call re-keys the screen: no stale rating, own step (U5)', (
    tester,
  ) async {
    await openCall(
      tester,
      callOf(
        phase: CallPhase.ongoing,
        role: CallRole.caller,
        connectedAt: DateTime.now(),
      ),
    );
    final connected = DateTime.now().subtract(const Duration(seconds: 5));
    await setCall(
      tester,
      callOf(
        phase: CallPhase.ended,
        role: CallRole.caller,
        connectedAt: connected,
        endedAt: DateTime.now(),
      ),
    );
    // A new call takes the screen before the old rating step came due.
    await setCall(
      tester,
      callOf(
        callId: '502',
        phase: CallPhase.calling,
        role: CallRole.caller,
        name: 'Meera',
      ),
    );
    await pumpMs(tester, 600);
    expect(find.text('RATE YOUR CALL EXPERIENCE'), findsNothing);
    expect(find.text('MEERA'), findsOneWidget);
    expect(find.text('CALLING'), findsOneWidget);

    // The new call gets its own post-call step.
    await setCall(
      tester,
      callOf(
        callId: '502',
        phase: CallPhase.ended,
        role: CallRole.caller,
        name: 'Meera',
        connectedAt: connected,
        endedAt: DateTime.now(),
      ),
    );
    await pumpMs(tester, 800);
    expect(find.text('RATE YOUR CALL EXPERIENCE'), findsOneWidget);
    expect(find.text('How was your session with Meera?'), findsOneWidget);
    await finishCall(tester);
  });

  for (final reset in const [true, false]) {
    final how = reset ? 'call reset meanwhile' : 'call still ended';
    testWidgets('a page pushed over /call, $how: no step until back (U4)', (
      tester,
    ) async {
      CallEngine.instance.debugSetMedia(CallMedia.initial);
      CallController.instance.debugSet(
        callOf(
          phase: CallPhase.ongoing,
          role: CallRole.caller,
          connectedAt: DateTime.now(),
        ),
      );
      final router = await pumpCallApp(tester);
      final screen = tester.element(find.byType(CallScreen));
      expect(callScreenOnTop(screen), isTrue);

      // A deep link opens over the call screen.
      unawaited(router.push(AppRoutes.home));
      await pumpMs(tester, 200);
      expect(callScreenOnTop(screen), isFalse);

      await setCall(
        tester,
        callOf(
          phase: CallPhase.ended,
          role: CallRole.caller,
          connectedAt: DateTime.now().subtract(const Duration(seconds: 5)),
          endedAt: DateTime.now(),
        ),
      );
      // The logic's `_onOver` resets a call whose screen is covered.
      if (reset) await setCall(tester, CallSession.idle);
      await pumpMs(tester, 800);
      // Nothing covered the other page.
      expect(find.text('RATE YOUR CALL EXPERIENCE'), findsNothing);
      expect(find.text('HOME PAGE'), findsOneWidget);

      // Back on the call screen: a reset call just leaves quietly (no
      // rating); one still ended gets its step now.
      router.pop();
      await pumpMs(tester, 400);
      expect(
        find.text('RATE YOUR CALL EXPERIENCE'),
        reset ? findsNothing : findsOneWidget,
      );
      expect(tester.takeException(), isNull);
      await finishCall(tester);
    });
  }

  group('searching vs a normal call (caller)', () {
    CallSession instant({required bool rollover, CallPhase? phase}) => callOf(
      phase: phase ?? CallPhase.calling,
      role: CallRole.caller,
    ).copyWith(isInstantCall: true, rollover: rollover);

    testWidgets('Talk Now button: only the galaxy and "Ringing" — no '
        '"Searching", no name of whoever is being rung', (tester) async {
      await openCall(tester, instant(rollover: false));
      expect(find.byKey(const ValueKey('search-galaxy')), findsOneWidget);
      expect(find.text('RINGING'), findsOneWidget);
      expect(find.textContaining('SEARCHING'), findsNothing);
      expect(find.textContaining('Finding someone'), findsNothing);
      expect(find.text('Audio Call'), findsNothing);
      expect(find.text('Ananya'), findsNothing);
      // Not up top either (the header's name line).
      expect(find.text('ANANYA'), findsNothing);
      await setCall(tester, instant(rollover: false, phase: CallPhase.ringing));
      expect(find.text('RINGING'), findsOneWidget);
      expect(find.text('Ananya'), findsNothing);
      expect(tester.takeException(), isNull);

      // The search moves on to another host (host-changed push): still
      // nobody named, anywhere on the screen.
      await setCall(
        tester,
        instant(rollover: false, phase: CallPhase.ringing).copyWith(
          remote: const CallPeer(id: '71', name: 'Divya'),
        ),
      );
      expect(find.textContaining('Divya'), findsNothing);
      expect(find.textContaining('DIVYA'), findsNothing);
      // A host accepted (connected push), not joined yet: still nobody.
      await setCall(
        tester,
        instant(rollover: false, phase: CallPhase.ringing).copyWith(
          remote: const CallPeer(id: '72', name: 'Ananya'),
          serverCallId: '901',
        ),
      );
      expect(find.text('Ananya'), findsNothing);
      expect(find.text('ANANYA'), findsNothing);

      // A host joined: their photo and name, and only theirs.
      await setCall(
        tester,
        instant(
          rollover: false,
          phase: CallPhase.ongoing,
        ).copyWith(connectedAt: DateTime.now()),
        media: _live,
      );
      await pumpMs(tester, 600);
      expect(find.byKey(const ValueKey('search-galaxy')), findsNothing);
      expect(find.text('Ananya'), findsOneWidget);
      expect(find.text('ANANYA'), findsOneWidget, reason: 'header, connected');
      await finishCall(tester);
    });

    test('only the caller\'s search hides the other side: a host being '
        'rung by Talk Now still sees who calls', () {
      final caller = instant(rollover: false);
      expect(caller.hidesPeer, isTrue);
      expect(caller.shownName, isNull);
      expect(caller.shownAvatar, isNull);
      final host = callOf(
        phase: CallPhase.ringing,
      ).copyWith(isInstantCall: true);
      expect(host.hidesPeer, isFalse);
      expect(host.shownName, 'Ananya');
      // A profile call (rolls over) names its host from the start.
      expect(instant(rollover: true).shownName, 'Ananya');
      // Connected: the host who answered.
      expect(
        instant(rollover: false, phase: CallPhase.ongoing).shownName,
        'Ananya',
      );
    });

    testWidgets('minimised while it searches: the bar names nobody', (
      tester,
    ) async {
      CallEngine.instance.debugSetMedia(CallMedia.initial);
      CallController.instance.debugSet(instant(rollover: false));
      final router = await pumpCallApp(tester);
      unawaited(router.push(AppRoutes.home));
      await pumpMs(tester, 300);
      expect(find.text('HOME PAGE'), findsOneWidget);
      final bar = find.byType(ReturnToCallBar);
      Finder inBar(String s) =>
          find.descendant(of: bar, matching: find.textContaining(s));
      expect(inBar('Ananya'), findsNothing);
      expect(inBar('RINGING'), findsOneWidget);
      expect(inBar('CALLING'), findsNothing);
      await finishCall(tester);
    });

    testWidgets('320 wide: the galaxy fits with everything else', (
      tester,
    ) async {
      await openCall(tester, instant(rollover: false), size: narrow);
      await pumpMs(tester, 300);
      expect(find.byKey(const ValueKey('search-galaxy')), findsOneWidget);
      expect(tester.takeException(), isNull);
      await finishCall(tester);
    });

    testWidgets('a call from a host\'s profile (rolls over): a normal call, '
        'no "Searching"', (tester) async {
      await openCall(tester, instant(rollover: true));
      expect(find.textContaining('SEARCHING'), findsNothing);
      expect(find.byKey(const ValueKey('search-galaxy')), findsNothing);
      expect(find.text('Ananya'), findsOneWidget);
      expect(find.text('CALLING'), findsOneWidget);
      await setCall(tester, instant(rollover: true, phase: CallPhase.ringing));
      expect(find.textContaining('SEARCHING'), findsNothing);
      expect(find.text('RINGING'), findsOneWidget);

      // Nobody took it: said like a normal call, not a search.
      await setCall(
        tester,
        instant(
          rollover: true,
          phase: CallPhase.ended,
        ).copyWith(endedAt: DateTime.now()),
      );
      expect(find.textContaining("Everyone's busy"), findsNothing);
      expect(find.text('Declined'), findsOneWidget);
      // A normal call keeps naming its host at the end.
      expect(find.text('Ananya'), findsOneWidget);
      expect(find.byKey(const ValueKey('search-galaxy')), findsNothing);
      await pumpMs(tester, 1300);
      await finishCall(tester);
    });

    testWidgets('the caller hangs up the search (nobody joined): the end '
        'screen names nobody, not the last host it rang', (tester) async {
      await openCall(
        tester,
        instant(rollover: false, phase: CallPhase.ringing),
      );
      await setCall(
        tester,
        instant(rollover: false, phase: CallPhase.ended).copyWith(
          remote: const CallPeer(id: '71', name: 'Divya'),
          endedAt: DateTime.now(),
        ),
      );
      expect(find.text('CALL ENDED'), findsOneWidget);
      expect(find.textContaining('Divya'), findsNothing);
      expect(find.textContaining('DIVYA'), findsNothing);
      expect(find.byKey(const ValueKey('search-galaxy')), findsOneWidget);
      expect(tester.takeException(), isNull);
      await pumpMs(tester, 1300);
      await finishCall(tester);
    });

    testWidgets('a search a host joined, then ended: that host is named', (
      tester,
    ) async {
      final connected = DateTime.now().subtract(const Duration(seconds: 30));
      await openCall(
        tester,
        instant(
          rollover: false,
          phase: CallPhase.ongoing,
        ).copyWith(connectedAt: connected),
        media: _live,
      );
      await setCall(
        tester,
        instant(
          rollover: false,
          phase: CallPhase.ended,
        ).copyWith(connectedAt: connected, endedAt: DateTime.now()),
      );
      expect(find.text('Ananya'), findsOneWidget);
      expect(find.byKey(const ValueKey('search-galaxy')), findsNothing);
      await pumpMs(tester, 1300);
      await finishCall(tester);
    });
  });

  group('"Add money" during a call', () {
    final holds = <String>[];
    setUp(() {
      holds.clear();
      InCallTopUp.serverHold = (record, {required active}) async {
        holds.add('$record:$active');
        return true;
      };
      InCallTopUp.bonus = () async => null;
    });
    tearDown(() {
      CallBilling.debugReset();
      InCallTopUp.debugReset();
      CallEngine.instance.debugSetAudioRoute(null);
    });

    final card = find.byKey(const ValueKey('call-topup-card'));
    final pill = find.byKey(const ValueKey('call-topup-pill'));
    bool speaker() => CallEngine.instance.media.value.speakerOn;

    /// A live paid call 100 s from its end, with "Add money" due.
    Future<void> openDue(
      WidgetTester tester, {
      bool video = false,
      bool free = false,
    }) async {
      final now = DateTime.now();
      await openCall(
        tester,
        callOf(
          phase: CallPhase.ongoing,
          role: CallRole.caller,
          video: video,
          connectedAt: now.subtract(const Duration(seconds: 20)),
        ),
        media: _live,
      );
      CallBilling.limit.value = CallLimit(
        callId: '501',
        endsAt: now.add(const Duration(seconds: 100)),
        freeLimit: free,
        extendable: true,
      );
      CallBilling.topUpDue.value = '501';
      await pumpMs(tester, 400);
    }

    for (final video in const [false, true]) {
      testWidgets('${video ? 'video' : 'voice'}: the card over the call; Add '
          'money pays on the speaker, then back to the earpiece', (
        tester,
      ) async {
        final during = <bool>[];
        InCallTopUp.pay = (_, _) async {
          during.add(speaker());
          return TopUpResult.success;
        };
        await openDue(tester, video: video);
        expect(card, findsOneWidget);
        expect(find.textContaining('of talk time left'), findsOneWidget);
        expect(find.textContaining('01:3'), findsOneWidget); // ~1:39 left
        expect(speaker(), isFalse);

        await tester.tap(find.byKey(const ValueKey('call-topup-add')));
        await pumpMs(tester, 300);
        expect(during, [true], reason: 'talking on while paying');
        expect(speaker(), isFalse, reason: 'back to the earpiece');
        // The call goes on.
        expect(CallController.instance.value.phase, CallPhase.ongoing);
        await finishCall(tester);
      });
    }

    testWidgets('paid: the strip goes the moment the gateway says so (the '
        'status dialog is still up), the server hold is taken and let go', (
      tester,
    ) async {
      final dialogOpen = Completer<void>();
      InCallTopUp.pay = (_, onPaid) async {
        onPaid(TopUpResult.success);
        // The status dialog: still on screen until this completes.
        await dialogOpen.future;
        return TopUpResult.success;
      };
      await openDue(tester);
      await tester.tap(find.byKey(const ValueKey('call-topup-add')));
      await pumpMs(tester, 400);
      // The dialog is still up: the strip is already gone.
      expect(CallBilling.topUpDue.value, isNull);
      expect(card, findsNothing);
      expect(holds, ['501:true'], reason: 'held while paying');
      dialogOpen.complete();
      await pumpMs(tester, 300);
      expect(holds, ['501:true', '501:false']);
      expect(CallController.instance.value.phase, CallPhase.ongoing);
      await finishCall(tester);
    });

    testWidgets('free call paid into: the green free-time strip goes too', (
      tester,
    ) async {
      final now = DateTime.now();
      CallBilling.rememberFree('501', const FreeCallTerms(minutes: 3));
      InCallTopUp.pay = (_, onPaid) async {
        onPaid(TopUpResult.success);
        return TopUpResult.success;
      };
      await openDue(tester, free: true);
      CallController.instance.debugSet(
        callOf(
          phase: CallPhase.ongoing,
          role: CallRole.caller,
          connectedAt: now.subtract(const Duration(seconds: 20)),
        ),
      );
      await pumpMs(tester, 1200);
      final freePill = find.byKey(const ValueKey('call-free-pill'));
      expect(freePill, findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('call-topup-add')));
      await pumpMs(tester, 1200);
      expect(freePill, findsNothing);
      expect(card, findsNothing);
      await finishCall(tester);
    });

    testWidgets('a headset or Bluetooth carries the call: left alone', (
      tester,
    ) async {
      final during = <bool>[];
      InCallTopUp.pay = (_, _) async {
        during.add(speaker());
        return null;
      };
      CallEngine.instance.debugSetAudioRoute(5); // Bluetooth
      await openDue(tester);
      await tester.tap(find.byKey(const ValueKey('call-topup-add')));
      await pumpMs(tester, 300);
      expect(during, [false]);
      expect(speaker(), isFalse);
      await finishCall(tester);
    });

    testWidgets('already on the speaker: it stays on after', (tester) async {
      InCallTopUp.pay = (_, _) async => null;
      await openDue(tester);
      CallEngine.instance.debugSetMedia(_live.copyWith(speakerOn: true));
      await tester.tap(find.byKey(const ValueKey('call-topup-add')));
      await pumpMs(tester, 300);
      expect(speaker(), isTrue);
      await finishCall(tester);
    });

    testWidgets('closed: a pill with the time left, which opens it again', (
      tester,
    ) async {
      var paid = 0;
      InCallTopUp.pay = (_, _) async {
        paid++;
        return null;
      };
      await openDue(tester);
      await tester.tap(find.byKey(const ValueKey('call-topup-close')));
      await pumpMs(tester, 400);
      expect(card, findsNothing);
      expect(pill, findsOneWidget);
      expect(find.textContaining('left · Add money'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('call-topup-pill-add')));
      await pumpMs(tester, 300);
      expect(paid, 1);
      await finishCall(tester);
    });

    // Tamil, Kannada and Bengali are not here: their larger strings never
    // finish loading in widget tests (decoded off the main isolate).
    for (final lang in const ['hi', 'ur', 'en']) {
      testWidgets('320 wide, $lang, video: card and pill fit', (tester) async {
        final now = DateTime.now();
        await openCall(
          tester,
          callOf(
            phase: CallPhase.ongoing,
            role: CallRole.caller,
            video: true,
            connectedAt: now,
          ),
          media: _live,
          size: narrow,
          locale: Locale(lang),
        );
        CallBilling.limit.value = CallLimit(
          callId: '501',
          endsAt: now.add(const Duration(seconds: 100)),
          freeLimit: true,
          extendable: true,
        );
        // The most text there is: with the first-top-up line.
        InCallTopUp.bonus = () async =>
            const TopUpBonus(TopUpBonusKind.firstTopup, 100);
        CallBilling.topUpDue.value = '501';
        void noError() {
          final e = tester.takeException();
          expect(
            e,
            isNull,
            reason: e is FlutterError ? e.toStringDeep() : '$e',
          );
        }

        await pumpMs(tester, 400);
        noError();
        expect(card, findsOneWidget);
        await tester.tap(find.byKey(const ValueKey('call-topup-close')));
        await pumpMs(tester, 400);
        noError();
        expect(pill, findsOneWidget);
        await finishCall(tester);
      });
    }

    testWidgets('a first top-up bonus: said on the card, and on the pill', (
      tester,
    ) async {
      InCallTopUp.bonus = () async =>
          const TopUpBonus(TopUpBonusKind.firstTopup, 100);
      await openDue(tester);
      expect(find.byKey(const ValueKey('call-topup-bonus')), findsOneWidget);
      expect(
        find.textContaining('100% extra on your first top-up'),
        findsOneWidget,
      );
      await tester.tap(find.byKey(const ValueKey('call-topup-close')));
      await pumpMs(tester, 400);
      expect(find.text('+100%'), findsOneWidget);
      await finishCall(tester);
    });

    testWidgets('no bonus: nothing about one', (tester) async {
      await openDue(tester);
      expect(find.byKey(const ValueKey('call-topup-bonus')), findsNothing);
      await tester.tap(find.byKey(const ValueKey('call-topup-close')));
      await pumpMs(tester, 400);
      expect(find.byKey(const ValueKey('call-topup-pill-bonus')), findsNothing);
      await finishCall(tester);
    });

    testWidgets('free minutes running out: their own words', (tester) async {
      await openDue(tester, free: true);
      expect(find.textContaining('Free minutes end in'), findsOneWidget);
      await finishCall(tester);
    });

    testWidgets('not due, not extendable, or the receiver: nothing', (
      tester,
    ) async {
      await openDue(tester);
      CallBilling.topUpDue.value = null;
      await pumpMs(tester, 400);
      expect(card, findsNothing);
      expect(pill, findsNothing);

      CallBilling.topUpDue.value = '501';
      CallBilling.limit.value = CallLimit(
        callId: '501',
        endsAt: DateTime.now().add(const Duration(seconds: 60)),
        freeLimit: true,
        extendable: false,
      );
      await pumpMs(tester, 400);
      expect(card, findsNothing);
      await finishCall(tester);

      await openCall(
        tester,
        callOf(phase: CallPhase.ongoing, connectedAt: DateTime.now()),
        media: _live,
      );
      CallBilling.limit.value = CallLimit(
        callId: '501',
        endsAt: DateTime.now().add(const Duration(seconds: 60)),
        freeLimit: false,
        extendable: true,
      );
      CallBilling.topUpDue.value = '501';
      await pumpMs(tester, 400);
      expect(card, findsNothing, reason: 'the receiver pays nothing');
      await finishCall(tester);
    });

    testWidgets('the call ends while paying: the rating waits until Add money '
        'is done, and nothing is pulled from under it', (tester) async {
      final paying = Completer<TopUpResult?>();
      InCallTopUp.pay = (_, _) => paying.future;
      await openDue(tester);
      await tester.tap(find.byKey(const ValueKey('call-topup-add')));
      await pumpMs(tester, 200);

      await setCall(
        tester,
        callOf(
          phase: CallPhase.ended,
          role: CallRole.caller,
          connectedAt: DateTime.now().subtract(const Duration(seconds: 90)),
          endedAt: DateTime.now(),
        ),
      );
      await pumpMs(tester, 2000);
      expect(find.text('RATE YOUR CALL EXPERIENCE'), findsNothing);
      expect(find.byType(CallScreen), findsOneWidget);
      expect(card, findsNothing, reason: 'nothing to add to an ended call');

      paying.complete(TopUpResult.success);
      await pumpMs(tester, 800);
      expect(find.text('RATE YOUR CALL EXPERIENCE'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await finishCall(tester);
    });
  });
}
