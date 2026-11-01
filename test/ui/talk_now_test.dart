import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vibelive/app/api/instant_call/instant_call_api.dart';
import 'package:vibelive/app/homescreen/discover/talk_now_button.dart';
import 'package:vibelive/core/network/api_exception.dart';

import 'host_onboarding_support/harness.dart';

/// Talk Now: shown only while the server has it on for this user, and its
/// refusals in the user's own words.
void main() {
  setUpAll(() async {
    await setUpHostHarness();
  });

  Future<void> open(WidgetTester tester) async {
    phone(tester);
    await pumpRoutes(
      tester,
      const Scaffold(body: Column(children: [TalkNowButton()])),
    );
    await pumpFor(tester, 400);
  }

  Finder button() => find.byType(GestureDetector);

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
  // that video existed at all.
  testWidgets('both call types get a button each, with their own rates', (
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
    expect(button(), findsNWidgets(2));
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
    expect(button(), findsOneWidget);
    expect(find.textContaining('25'), findsWidgets);
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
