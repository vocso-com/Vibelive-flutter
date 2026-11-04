import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vibelive/app/api/hosthub/profile_models.dart';
import 'package:vibelive/app/api/listingflow/listing_models.dart';
import 'package:vibelive/app/hosthub/onboarding/helper/draft_controller.dart';
import 'package:vibelive/app/hosthub/onboarding/steps/rates_step.dart';
import 'package:vibelive/app/listingflow/widgets/host_grid_card.dart';

import 'host_onboarding_support/harness.dart';

/// Backend-controlled call pricing on the Rates step (call_pricing §7). When
/// the backend sets pricing for a host their rate screen is read-only and
/// shows only what they earn; otherwise it is the current editable screen.
void main() {
  group('CallPricing (lenient parsing)', () {
    test('absent / inactive reads as inactive', () {
      expect(CallPricing.from(null).active, isFalse);
      expect(CallPricing.from(const {}).active, isFalse);
      expect(CallPricing.from(const {'active': false}).active, isFalse);
    });

    test('active block reads amounts, level and currency', () {
      final p = CallPricing.from(const {
        'active': true,
        'level': 3,
        'voiceEarn': 10,
        'videoEarn': 18,
        'currency': '₹',
      });
      expect(p.active, isTrue);
      expect(p.level, 3);
      expect(p.voiceEarn, 10);
      expect(p.videoEarn, 18);
      expect(p.currency, '₹');
    });

    test('missing / bad numbers read as null, never a throw', () {
      final p = CallPricing.from(const {
        'active': true,
        'voiceEarn': 'oops',
        // videoEarn absent
      });
      expect(p.active, isTrue);
      expect(p.voiceEarn, isNull);
      expect(p.videoEarn, isNull);
      expect(p.currency, '₹'); // default when absent
    });

    test('HostProfile exposes the callPricing block', () {
      final host = HostProfile.from(const {
        'id': 1,
        'documentId': 'e1',
        'callPricing': {'active': true, 'voiceEarn': 9, 'videoEarn': 16},
      });
      expect(host!.callPricing.active, isTrue);
      expect(host.callPricing.voiceEarn, 9);
    });
  });

  group('Rates step: backend-controlled (read-only)', () {
    setUpAll(() async {
      await setUpHostHarness();
    });

    late HostDraftController draft;
    setUp(() async {
      await resetHost();
      draft = HostDraftController('rates', persist: false)
        ..audioOn.value = true
        ..videoOn.value = true
        ..audioRate.value = 10
        ..videoRate.value = 20;
    });

    Future<void> open(
      WidgetTester tester, {
      CallPricing? pricing,
      Size? size,
      Locale? locale,
    }) async {
      phone(tester, size: size ?? const Size(390, 844));
      await pumpRoutes(
        tester,
        Scaffold(
          body: RatesStep(draft: draft, callPricing: pricing),
        ),
        locale: locale ?? const Locale('en'),
      );
      await pumpFor(tester, 400);
    }

    const active = CallPricing(
      active: true,
      level: 3,
      voiceEarn: 10,
      videoEarn: 18,
    );

    testWidgets('active: earnings shown, no stepper, no fee breakdown', (
      tester,
    ) async {
      await open(tester, pricing: active);
      // What they earn, large, from the backend.
      expect(find.text('YOU EARN'), findsNWidgets(2));
      expect(find.text('₹10'), findsOneWidget);
      expect(find.text('₹18'), findsOneWidget);
      expect(find.text('Set by VibeLive'), findsNWidgets(2));
      expect(find.textContaining('Level 3'), findsOneWidget);

      // None of the editable / fee machinery.
      expect(find.bySemanticsLabel('Decrease rate'), findsNothing);
      expect(find.bySemanticsLabel('Increase rate'), findsNothing);
      expect(find.textContaining('Customer pays'), findsNothing);
      expect(find.text('See how earnings work'), findsNothing);
      expect(find.textContaining('Platform fee'), findsNothing);
      expect(find.textContaining('INVITE LINK'), findsNothing);
      expect(find.textContaining('VibeLive keeps'), findsNothing);
      expect(tester.takeException(), isNull);
      await finishHost(tester);
    });

    testWidgets('active: the format on/off switch stays editable', (
      tester,
    ) async {
      await open(tester, pricing: active);
      expect(find.text('₹10'), findsOneWidget);
      await tester.tap(
        find.byKey(const ValueKey('hostflow-switch-hostflow:rates.audio')),
      );
      await pumpFor(tester, 400);
      expect(draft.audioOn.value, isFalse);
      // Audio earning gone; video still there.
      expect(find.text('₹10'), findsNothing);
      expect(find.text('₹18'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await finishHost(tester);
    });

    testWidgets('active: missing amounts show nothing, no crash', (
      tester,
    ) async {
      await open(tester, pricing: const CallPricing(active: true, level: 1));
      expect(find.text('YOU EARN'), findsNWidgets(2));
      expect(find.text('Set by VibeLive'), findsNWidgets(2));
      expect(tester.takeException(), isNull);
      await finishHost(tester);
    });

    testWidgets('active: read-only, 320 wide in Hindi, no overflow', (
      tester,
    ) async {
      await open(
        tester,
        pricing: active,
        size: const Size(320, 700),
        locale: const Locale('hi'),
      );
      expect(find.text('₹10'), findsOneWidget);
      expect(find.bySemanticsLabel('Decrease rate'), findsNothing);
      expect(tester.takeException(), isNull);
      await finishHost(tester);
    });

    testWidgets('inactive: the editable screen is unchanged', (tester) async {
      await open(tester, pricing: CallPricing.inactive);
      // The stepper and the fee breakdown are back; nothing read-only.
      expect(find.bySemanticsLabel('Decrease rate'), findsWidgets);
      expect(find.text('See how earnings work'), findsOneWidget);
      expect(find.textContaining('Customer pays'), findsWidgets);
      expect(find.text('Set by VibeLive'), findsNothing);
      expect(tester.takeException(), isNull);
      await finishHost(tester);
    });

    testWidgets('active is read from the host\'s own profile end-to-end', (
      tester,
    ) async {
      await resetHost(
        expert: {
          'id': 50,
          'documentId': 'exp50',
          'user': {'documentId': 'u1'},
          'isActive': true,
          'rates': {'voiceCallRate': 18, 'videoCallRate': 30},
          'callPricing': {
            'active': true,
            'level': 2,
            'voiceEarn': 9,
            'videoEarn': 16,
            'currency': '₹',
          },
        },
      );
      draft = HostDraftController('rates', persist: false)
        ..audioOn.value = true
        ..videoOn.value = true;
      // No override: RatesStep must read callPricing from the profile query.
      await open(tester);
      expect(find.text('Set by VibeLive'), findsNWidgets(2));
      expect(find.text('₹9'), findsOneWidget);
      expect(find.text('₹16'), findsOneWidget);
      expect(find.bySemanticsLabel('Decrease rate'), findsNothing);
      expect(tester.takeException(), isNull);
      await finishHost(tester);
    });
  });

  group('Discovery price overlay (§7.2)', () {
    setUpAll(() async {
      await setUpHostHarness();
    });
    setUp(resetHost);

    testWidgets(
      'active host shows the global price, an inactive host their own',
      (tester) async {
        phone(tester);
        HostCard card(String docId, String name, double voice) =>
            HostCard.fromJson({
              'documentId': docId,
              'role': 'Expert',
              'name': name,
              'expert': {
                'documentId': docId,
                'rates': {'voiceCallRate': voice, 'videoCallRate': 30},
              },
            });
        await pumpRoutes(
          tester,
          Scaffold(
            body: Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Active host: the backend overlaid the global ₹18.
                  SizedBox(
                    width: 190,
                    height: 270,
                    child: HostGridCard(
                      host: card('h_active', 'Meera', 18),
                      onTap: (_) {},
                    ),
                  ),
                  // Inactive host: their own stored ₹25.
                  SizedBox(
                    width: 190,
                    height: 270,
                    child: HostGridCard(
                      host: card('h_own', 'Riya', 25),
                      onTap: (_) {},
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
        await pumpFor(tester, 400);
        expect(find.text('₹ 18/min'), findsOneWidget);
        expect(find.text('₹ 25/min'), findsOneWidget);
        expect(tester.takeException(), isNull);
        await finishHost(tester);
      },
    );
  });
}
