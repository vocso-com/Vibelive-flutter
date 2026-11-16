import 'package:flutter_test/flutter_test.dart';
import 'package:vibelive/app/api/hosthub/handle_api.dart';
import 'package:vibelive/app/hosthub/onboarding/host_onboarding_screen.dart';

import 'host_onboarding_support/harness.dart';

/// A handle another profile holds, one the public list never shows (an
/// unapproved host): the server check (`/me/handle-check`) sees it, and a
/// submit the server still refuses says so plainly, with a free handle.
void main() {
  setUpAll(setUpHostHarness);

  test(
    'the server check decides; an older backend falls back to the list',
    () async {
      final backend = await resetHost();
      backend.replies['GET /api/me/handle-check'] = (_) => {
        'valid': true,
        'available': false,
        'suggestion': 'aanyatalks_live',
      };
      final r = await HostHandleApi.check('aanyatalks');
      expect(r.available, isFalse);
      expect(r.suggestion, 'aanyatalks_live');

      // No such route (the harness answers `{data: []}`): the list says free.
      final old = await resetHost();
      expect(old.replies.containsKey('GET /api/me/handle-check'), isFalse);
      expect(await HostHandleApi.isAvailable('aanyatalks'), isTrue);
    },
  );

  testWidgets('Basic: a taken handle is caught there, with a free one', (
    tester,
  ) async {
    final backend = await resetHost();
    backend.replies['GET /api/me/handle-check'] = (_) => {
      'valid': true,
      'available': false,
      'suggestion': 'aanyatalks_live',
    };
    await parkDraft('basic');
    phone(tester, top: 47, bottom: 34);
    await pumpRoutes(tester, const HostOnboardingScreen());
    await pumpFor(tester, 600);
    await tapContinue(tester, settle: 900);
    expect(
      find.text('This handle is already taken. Try @aanyatalks_live.'),
      findsOneWidget,
    );
    expect(savedDraft()!['step'], 'basic');
    await finishHost(tester);
  });

  testWidgets('Submit refused for the handle: a clear message with a free '
      'one, then Basic info (not a silent jump)', (tester) async {
    final backend = await resetHost();
    backend.statuses['POST /api/expert-profiles'] = 400;
    backend.replies['POST /api/expert-profiles'] = (_) => {
      'data': null,
      'error': {
        'status': 400,
        'name': 'ValidationError',
        'message': 'This attribute must be unique',
        'details': {
          'errors': [
            {
              'path': ['handler'],
              'message': 'This attribute must be unique',
              'name': 'ValidationError',
              'value': 'aanyatalks',
            },
          ],
        },
      },
    };
    backend.replies['GET /api/me/handle-check'] = (_) => {
      'valid': true,
      'available': false,
      'suggestion': 'aanyatalks_live',
    };
    await parkDraft('guidelines', extra: {'agreed': true});
    phone(tester, top: 47, bottom: 34);
    await pumpRoutes(tester, const HostOnboardingScreen());
    await pumpFor(tester, 600);
    await tapContinue(tester, settle: 2500);

    expect(find.text('Username taken'), findsOneWidget);
    expect(
      find.text('This handle is already taken. Try @aanyatalks_live.'),
      findsWidgets,
    );
    await tester.tap(find.text('OK'));
    await pumpFor(tester, 900);
    expect(savedDraft()!['step'], 'basic');
    expect(backend.sent('POST', '/expert-profile-approvals'), isEmpty);
    await finishHost(tester);
  });
}
