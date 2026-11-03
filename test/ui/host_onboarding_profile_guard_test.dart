import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vibelive/app/hosthub/onboarding/helper/host_steps.dart';
import 'package:vibelive/app/hosthub/onboarding/host_onboarding_screen.dart';
import 'package:vibelive/core/network/strapi.dart';
import 'package:vibelive/core/session/session_store.dart';
import 'package:vibelive/core/storage/app_prefs.dart';

import 'host_onboarding_support/harness.dart';

/// A host never gets a second profile from this screen.
///
/// 29 Oct: an approved host opened the editor while her access token had
/// expired. Her profile read failed, the screen took that for "no profile",
/// seeded a new-host form, and Submit created a second profile that took the
/// account off the approved one.

JsonMap _host() => {
  'id': 5,
  'documentId': 'exp1',
  'handler': 'aanyatalks',
  'tagline': 'Good conversations, music and everyday stories.',
  'isApproved': true,
  'isActive': true,
  'callAnyTime': true,
  'vocationMode': false,
  'rates': {'voiceCallRate': 25, 'videoCallRate': 35},
};

/// A finished draft on the last step, as a device keeps it.
Future<void> _savedDraft({String? expertId}) => AppPrefs.setString(
  'hostflow_draft_v1:u1',
  jsonEncode({
    'step': 'guidelines',
    'started': true,
    'seeded': true,
    'topicsSeeded': true,
    'languagesSeeded': true,
    'name': 'Aanya Sharma',
    'handle': 'aanyasharma',
    'tagline': 'Good conversations, music and everyday stories.',
    'bio': 'I like long talks about films, food and family.',
    'gender': 'Female',
    'topics': [
      {'value': 'topic_feeling_low', 'label': 'Feeling low', 'emoji': ''},
    ],
    'photos': [
      {'key': 'm77', 'mediaId': 77},
    ],
    'audioOn': true,
    'audioRate': 25,
    'availableNow': true,
    'agreed': true,
    'expertId': expertId,
  }),
);

void main() {
  late HostBackend backend;

  setUpAll(setUpHostHarness);

  testWidgets('a host whose profile cannot be read gets an error and Retry, '
      'never a blank form', (tester) async {
    backend = await resetHost(expert: _host());
    backend.failing.add('GET /api/expert-profiles');
    phone(tester);
    await pumpRoutes(
      tester,
      const HostOnboardingScreen(editStep: HostStep.basic),
    );
    await pumpFor(tester, 3000);

    expect(
      find.byKey(const ValueKey('host-profile-load-error')),
      findsOneWidget,
    );
    expect(find.text("We couldn't load your host profile"), findsOneWidget);
    expect(find.byKey(const ValueKey('hostflow-handle')), findsNothing);

    // Back online: Retry opens the form filled from the real profile, not a
    // handle made up from the name.
    backend.failing.clear();
    await tester.tap(find.text('RETRY'));
    await pumpFor(tester, 1500);
    final handle = tester.widget<TextField>(
      find.byKey(const ValueKey('hostflow-handle')),
    );
    expect(handle.controller!.text, 'aanyatalks');
    expect(backend.sent('POST', '/expert-profiles'), isEmpty);
    await finishHost(tester);
  });

  testWidgets('the same for a host in the whole flow', (tester) async {
    backend = await resetHost(expert: _host());
    backend.failing.add('GET /api/expert-profiles');
    phone(tester);
    await pumpRoutes(tester, const HostOnboardingScreen());
    await pumpFor(tester, 3000);
    expect(
      find.byKey(const ValueKey('host-profile-load-error')),
      findsOneWidget,
    );
    expect(find.byKey(const ValueKey('hostflow-start')), findsNothing);
    await finishHost(tester);
  });

  testWidgets('a host with an old draft and no profile id: Submit refuses to '
      'create, and once the profile loads the draft is theirs', (
    tester,
  ) async {
    backend = await resetHost(expert: _host());
    await _savedDraft();
    backend.failing.add('GET /api/expert-profiles');
    phone(tester);
    await pumpRoutes(tester, const HostOnboardingScreen());
    await pumpFor(tester, 3000);

    // The draft says it is finished, so the flow opens on its last step.
    await tapContinue(tester, settle: 900);
    expect(find.text("We couldn't load your host profile"), findsOneWidget);
    expect(backend.sent('POST', '/expert-profiles'), isEmpty);

    backend.failing.clear();
    await tester.tap(find.text('OK'));
    await pumpFor(tester, 1500);
    // The retry loaded the profile: the draft now belongs to it.
    expect(savedDraft()?['expertId'], 'exp1');
    await tapContinue(tester, settle: 1500);
    expect(backend.sent('POST', '/expert-profiles'), isEmpty);
    await finishHost(tester);
  });

  testWidgets('the server already has a profile (409): nothing more is sent, '
      'the session gets it back and the Host Hub opens', (tester) async {
    backend = await resetHost();
    await _savedDraft();
    backend.statuses['POST /api/expert-profiles'] = 409;
    backend.replies['POST /api/expert-profiles'] = (_) => {
      'data': null,
      'error': {
        'status': 409,
        'name': 'ConflictError',
        'message': 'You already have a host profile. Close this screen and '
            'open your profile again.',
        'details': {'code': 'HOST_PROFILE_EXISTS', 'documentId': 'exp1'},
      },
    };
    // What "my profile" says once re-read: the account is a host.
    backend.user = {...backend.user, 'role': 'Expert', 'expert': _host()};
    phone(tester);
    await pumpRoutes(tester, const HostOnboardingScreen());
    await pumpFor(tester, 900);

    await tapContinue(tester, settle: 1500);
    expect(backend.sent('POST', '/expert-profiles'), hasLength(1));
    expect(find.text('You already have a host profile'), findsOneWidget);
    await tester.tap(find.text('OK'));
    await pumpFor(tester, 900);

    expect(find.text('HOME me'), findsOneWidget);
    expect(SessionStore.instance.value.expertDocumentId, 'exp1');
    expect(savedDraft(), isNull);
    // Nothing was written for a profile that was never made.
    expect(backend.sent('POST', '/profile-images'), isEmpty);
    expect(backend.sent('POST', '/expert-profile-approvals'), isEmpty);
    expect(backend.sent('PUT', '/public-users/u1'), isEmpty);
    await finishHost(tester);
  });
}
