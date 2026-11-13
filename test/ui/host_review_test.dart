import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vibelive/app/api/client/client_models.dart';
import 'package:vibelive/app/api/hosthub/moderation_models.dart';
import 'package:vibelive/app/api/hosthub/profile_models.dart';
import 'package:vibelive/app/hosthub/approved/widgets/moderation_messages_card.dart';
import 'package:vibelive/app/hosthub/common/host_review.dart';
import 'package:vibelive/app/hosthub/onboarding/helper/draft_controller.dart';
import 'package:vibelive/app/hosthub/onboarding/helper/draft_models.dart';
import 'package:vibelive/app/hosthub/onboarding/helper/host_steps.dart';
import 'package:vibelive/app/hosthub/onboarding/steps/photos_step.dart';
import 'package:vibelive/app/hosthub/onboarding/helper/prefill.dart';
import 'package:vibelive/app/hosthub/onboarding/helper/validation.dart';
import 'package:vibelive/app/hosthub/onboarding/steps/tagline_step.dart';
import 'package:vibelive/app/hosthub/onboarding/steps/voice_step.dart';
import 'package:vibelive/app/hosthub/onboarding/widgets/photo_tile.dart';
import 'package:vibelive/core/network/strapi.dart';
import 'package:vibelive/core/router/app_router.dart';

import 'host_onboarding_support/harness.dart';

/// What the moderation team asked a host to change, as the app shows it:
/// the fields a rejection named, rejected photos, a rejected voice intro,
/// and the team's messages on the ME tab.
void main() {
  setUpAll(() async {
    await setUpHostHarness();
  });

  HostProfile host({
    String? status,
    String? note,
    String? audio,
    List<Map<String, Object?>> images = const [],
  }) => HostProfile.from({
    'id': 50,
    'documentId': 'exp50',
    'moderation_status': ?status,
    'moderation_note': ?note,
    'audio_intro_status': ?audio,
    'host_profile_images': images,
  })!;

  group('HostReview', () {
    test('a message reads what the server sends', () {
      final m = HostModerationMessage.from(const {
        'id': 4,
        'kind': 'status_changed',
        'body': ' Bio has a phone number ',
        'fields': ['descriptions'],
        'status': 'rejected',
        'deeplink': 'vibecalling://host-bio',
        'createdAt': '2026-10-29T10:00:00.000Z',
      });
      expect(m.body, 'Bio has a phone number');
      expect(m.fields, ['descriptions']);
      expect(m.isTextRejection, isTrue);
      expect(m.needsAction, isTrue);
      expect(m.deeplink, 'vibecalling://host-bio');
      expect(m.createdAt, isNotNull);
    });

    test('the named fields count while the profile stands rejected', () {
      final messages = [
        HostModerationMessage.from(const {
          'id': 9,
          'kind': 'rejected',
          'body': 'Use your real name',
          'fields': ['name', 'handler'],
        }),
        HostModerationMessage.from(const {
          'id': 3,
          'kind': 'rejected',
          'fields': ['tagline'],
        }),
      ];
      final r = HostReview.from(
        host(status: 'rejected', note: 'Use your real name'),
        messages,
      );
      expect(r.fields, {'name', 'handler'});
      expect(r.note, 'Use your real name');
      expect(r.fieldsOn(HostStep.basic), ['name', 'handler']);
      expect(r.noticeOn(HostStep.basic), isTrue);
      expect(r.noticeOn(HostStep.tagline), isFalse);

      // Fixed and approved since: nothing to show.
      final clear = HostReview.from(host(status: 'clear'), messages);
      expect(clear.fields, isEmpty);
      expect(clear.noticeOn(HostStep.basic), isFalse);
    });

    test('a rejection naming no field points at Basic', () {
      final r = HostReview.from(
        host(status: 'rejected', note: 'Fake'),
        const [],
      );
      expect(r.fields, isEmpty);
      expect(r.noticeOn(HostStep.basic), isTrue);
      expect(r.noticeOn(HostStep.bio), isFalse);
    });

    test('each saved photo keeps its review state; the voice intro too', () {
      final r = HostReview.from(
        host(
          audio: 'rejected',
          images: [
            {
              'id': 1,
              'status_enum': 'rejected',
              'image': {'id': 11, 'url': '/uploads/a.jpg'},
            },
            {
              'id': 2,
              'status_enum': 'pending',
              'image': {'id': 12, 'url': '/uploads/b.jpg'},
            },
          ],
        ),
        const [],
      );
      expect(r.photoStatus(11), 'rejected');
      expect(r.photoStatus(12), 'pending');
      expect(r.photoStatus(99), isNull);
      expect(r.hasRejectedPhoto, isTrue);
      expect(r.audioRejected, isTrue);
    });
  });

  group('on the steps', () {
    late HostDraftController draft;

    setUp(() async {
      await resetHost();
      draft = HostDraftController('review', persist: false);
    });

    Future<void> open(
      WidgetTester tester,
      Widget child, {
      HostReview review = HostReview.none,
    }) async {
      phone(tester);
      await pumpRoutes(
        tester,
        Scaffold(
          body: HostReviewScope(
            review: review,
            child: ListView(
              padding: const EdgeInsets.all(16),
              children: [child],
            ),
          ),
        ),
      );
      await pumpFor(tester, 300);
    }

    testWidgets('a rejected tagline: the notice, the red field, until edited', (
      tester,
    ) async {
      draft.tagline.text = 'Call me on 98765';
      await open(
        tester,
        TaglineStep(draft: draft),
        review: const HostReview(
          fields: {'tagline'},
          note: 'No phone numbers please',
        ),
      );
      expect(find.text('Please change your tagline'), findsOneWidget);
      expect(find.text('No phone numbers please'), findsOneWidget);
      expect(find.text('Needs a change'), findsOneWidget);

      await tester.enterText(
        find.byKey(const ValueKey('hostflow-tagline')),
        'A friendly listener',
      );
      await tester.pump();
      expect(find.text('Needs a change'), findsNothing);
      await finishHost(tester);
    });

    testWidgets('nothing is marked without a rejection', (tester) async {
      draft.tagline.text = 'A friendly listener';
      await open(tester, TaglineStep(draft: draft));
      expect(find.text('Needs a change'), findsNothing);
      expect(find.textContaining('Please change'), findsNothing);
      await finishHost(tester);
    });

    testWidgets('photo tiles say which photo was turned down', (tester) async {
      Widget tile(String? review) => SizedBox(
        width: 110,
        height: 160,
        child: HostPhotoTile(
          photo: const HostDraftPhoto(key: 'm1', mediaId: 1),
          width: 110,
          primary: false,
          review: review,
          onRemove: () {},
          onTap: () {},
        ),
      );
      await open(
        tester,
        Row(children: [tile('rejected'), tile('pending'), tile('approved')]),
      );
      expect(find.text('Not approved'), findsOneWidget);
      expect(find.text('In review'), findsOneWidget);
      // An approved photo can't be deleted: no ✕ on it (rejected and in
      // review keep theirs).
      expect(find.bySemanticsLabel('Remove photo'), findsNWidgets(2));
      expect(tester.takeException(), isNull);
      await finishHost(tester);
    });

    testWidgets('a 4th saved photo (rejected) is shown, removable', (
      tester,
    ) async {
      // The account that hid it: 3 approved photos and a rejected 4th.
      final host = HostProfile.from({
        'id': 50,
        'documentId': 'exp50',
        'host_profile_images': [
          for (final (doc, id, prio, primary, status) in const [
            ('oyo', 33, 99, true, 'approved'),
            ('amx', 11, 1, false, 'approved'),
            ('rr8', 22, 2, false, 'approved'),
            ('jlp', 44, 99, false, 'rejected'),
          ])
            {
              'documentId': doc,
              'priority': prio,
              'isprimary': primary,
              'status_enum': status,
              'image': {'id': id, 'url': '/u/$id.jpg'},
            },
        ],
      })!;
      HostPrefill.apply(
        draft,
        const UserWithExpert(user: {'id': 1, 'documentId': 'u1'}),
        host: host,
      );
      expect(draft.photos.value.map((p) => p.mediaId), [33, 11, 22, 44]);
      await open(
        tester,
        PhotosStep(draft: draft),
        review: HostReview.from(host, const []),
      );
      expect(find.text('Not approved'), findsOneWidget);
      // No "Add photo" while at 3 or more; asked to remove one.
      expect(find.text('Add photo'), findsNothing);
      expect(
        find.text('You can keep up to 3 photos. Remove one to continue.'),
        findsOneWidget,
      );
      expect(
        HostValidation.photos(draft)?.key,
        'hostflow:errors.photos_too_many',
      );
      // Only the rejected one can be removed (approved ones can't).
      expect(find.bySemanticsLabel('Remove photo'), findsOneWidget);
      await tester.tap(find.bySemanticsLabel('Remove photo'));
      await pumpFor(tester, 200);
      expect(draft.photos.value.map((p) => p.mediaId), [33, 11, 22]);
      expect(find.text('Not approved'), findsNothing);
      expect(HostValidation.photos(draft), isNull);
      expect(tester.takeException(), isNull);
      await finishHost(tester);
    });

    testWidgets('a new photo (not reviewed yet) can be removed', (
      tester,
    ) async {
      await open(
        tester,
        SizedBox(
          width: 110,
          height: 160,
          child: HostPhotoTile(
            photo: const HostDraftPhoto(key: 'm2', mediaId: 2),
            width: 110,
            primary: true,
            onRemove: () {},
            onTap: () {},
          ),
        ),
      );
      expect(find.bySemanticsLabel('Remove photo'), findsOneWidget);
      await finishHost(tester);
    });

    testWidgets('a rejected voice intro: asked to record again, until done', (
      tester,
    ) async {
      draft.voiceIntro.value = const HostVoiceIntro(
        savedMediaId: 9,
        savedUrl: 'https://cdn.example/intro.m4a',
      );
      await open(
        tester,
        VoiceStep(draft: draft),
        review: const HostReview(audioRejected: true),
      );
      expect(find.text("Your voice intro wasn't approved"), findsOneWidget);

      await tester.tap(find.text('Re-record'));
      await pumpFor(tester, 2000);
      await tester.tap(find.bySemanticsLabel('Stop recording'));
      await pumpFor(tester, 200);
      expect(find.text("Your voice intro wasn't approved"), findsNothing);
      await finishHost(tester);
    });
  });

  group('messages from the moderation team', () {
    testWidgets('each with what it is about and a way to fix it', (
      tester,
    ) async {
      final backend = await resetHost(
        expert: {'id': 50, 'documentId': 'exp50'},
      );
      backend.moderationNotes = [
        {
          'id': 3,
          'kind': 'rejected',
          'body': 'Please use your real name.',
          'fields': ['name', 'handler'],
          'createdAt': '2026-10-29T10:00:00.000Z',
        },
        {
          'id': 2,
          'kind': 'note',
          'body': 'Add a voice intro to get more calls.',
          'deeplink': 'vibecalling://host-voice',
        },
      ];
      final opened = <String>[];
      phone(tester);
      await pumpRoutes(
        tester,
        Scaffold(
          body: ListView(
            children: [
              HostModerationMessagesCard(
                open: (route) async => opened.add(route),
              ),
            ],
          ),
        ),
      );
      await pumpFor(tester, 300);

      expect(find.text('Messages from the moderation team'), findsOneWidget);
      expect(find.text('Please use your real name.'), findsOneWidget);
      expect(find.text('To change: display name and handle'), findsOneWidget);
      expect(find.text('Add a voice intro to get more calls.'), findsOneWidget);
      expect(find.text('Open'), findsOneWidget);

      await tester.tap(find.text('Fix it'));
      await tester.pump();
      expect(opened, [AppRoutes.hostStep('basic')]);
      await finishHost(tester);
    });

    testWidgets('a request already fixed is not shown', (tester) async {
      final backend = await resetHost(
        expert: {'id': 50, 'documentId': 'exp50'},
      );
      backend.moderationNotes = [
        {
          'id': 5,
          'kind': 'photo_decision',
          'body': 'A photo was not approved.',
          'photo': 'img-gone',
        },
        {
          'id': 4,
          'kind': 'photo_decision',
          'body': 'Another photo was not approved.',
          'photo': 'img-still',
        },
        {'id': 3, 'kind': 'note', 'body': 'Welcome aboard.'},
      ];
      final host = HostProfile.from({
        'id': 50,
        'documentId': 'exp50',
        'host_profile_images': [
          {
            'id': 2,
            'documentId': 'img-still',
            'status_enum': 'rejected',
            'image': {'id': 12, 'url': '/uploads/b.jpg'},
          },
        ],
      })!;
      phone(tester);
      await pumpRoutes(
        tester,
        Scaffold(
          body: ListView(
            children: [
              HostModerationMessagesCard(open: (_) async {}, host: host),
            ],
          ),
        ),
      );
      await pumpFor(tester, 300);
      // The deleted photo's request is gone; the one still rejected stays.
      expect(find.text('A photo was not approved.'), findsNothing);
      expect(find.text('Another photo was not approved.'), findsOneWidget);
      expect(find.text('Welcome aboard.'), findsOneWidget);
      await finishHost(tester);
    });

    test('resolvedFor: photo, voice, text; notes never', () {
      final host = HostProfile.from({
        'id': 50,
        'moderation_status': 'pending',
        'audio_intro_status': 'approved',
        'host_profile_images': const [],
      })!;
      HostModerationMessage m(JsonMap j) =>
          HostModerationMessage.from({'id': 1, ...j});
      expect(
        m({'kind': 'photo_decision', 'photo': 'x'}).resolvedFor(host),
        isTrue,
      );
      expect(
        m({'kind': 'photo_decision', 'audio': 'rejected'}).resolvedFor(host),
        isTrue,
      );
      expect(
        m({
          'kind': 'rejected',
          'fields': ['name'],
        }).resolvedFor(host),
        isTrue,
      );
      expect(m({'kind': 'note', 'body': 'hi'}).resolvedFor(host), isFalse);
      final rejected = HostProfile.from({
        'id': 50,
        'moderation_status': 'rejected',
        'audio_intro_status': 'rejected',
      })!;
      expect(m({'kind': 'rejected'}).resolvedFor(rejected), isFalse);
      expect(
        m({
          'kind': 'photo_decision',
          'audio': 'rejected',
        }).resolvedFor(rejected),
        isFalse,
      );
    });

    testWidgets('a plain message has an X that closes it for good; a '
        'request to fix has none', (tester) async {
      final backend = await resetHost(
        expert: {'id': 50, 'documentId': 'exp50'},
      );
      backend.moderationNotes = [
        {
          'id': 3,
          'kind': 'rejected',
          'body': 'Please use your real name.',
          'fields': ['name'],
          'dismissible': false,
        },
        {
          'id': 2,
          'kind': 'note',
          'body': 'Welcome aboard.',
          'dismissible': true,
        },
        // An older backend says nothing: the same rule in the app.
        {'id': 1, 'kind': 'approved', 'body': 'Your profile is live.'},
      ];
      phone(tester);
      await pumpRoutes(
        tester,
        Scaffold(
          body: ListView(
            children: [HostModerationMessagesCard(open: (_) async {})],
          ),
        ),
      );
      await pumpFor(tester, 300);
      expect(find.byKey(const ValueKey('moderation-dismiss-3')), findsNothing);
      expect(
        find.byKey(const ValueKey('moderation-dismiss-1')),
        findsOneWidget,
      );

      await tester.tap(find.byKey(const ValueKey('moderation-dismiss-2')));
      await pumpFor(tester, 300);
      expect(find.text('Welcome aboard.'), findsNothing);
      expect(
        backend.sent('POST', '/me/moderation-notes/2/dismiss'),
        hasLength(1),
      );
      expect(find.text('Please use your real name.'), findsOneWidget);
      await finishHost(tester);
    });

    testWidgets('the X fails on the server: the message comes back', (
      tester,
    ) async {
      final backend = await resetHost(
        expert: {'id': 50, 'documentId': 'exp50'},
      );
      backend.moderationNotes = [
        {'id': 2, 'kind': 'note', 'body': 'Welcome aboard.'},
      ];
      backend.failing.add('POST /api/me/moderation-notes/2/dismiss');
      phone(tester);
      await pumpRoutes(
        tester,
        Scaffold(
          body: ListView(
            children: [HostModerationMessagesCard(open: (_) async {})],
          ),
        ),
      );
      await pumpFor(tester, 300);
      await tester.tap(find.byKey(const ValueKey('moderation-dismiss-2')));
      await pumpFor(tester, 600);
      expect(find.text('Welcome aboard.'), findsOneWidget);
      await finishHost(tester);
    });

    testWidgets('no messages, no card', (tester) async {
      await resetHost(expert: {'id': 50, 'documentId': 'exp50'});
      phone(tester);
      await pumpRoutes(
        tester,
        Scaffold(body: HostModerationMessagesCard(open: (_) async {})),
      );
      await pumpFor(tester, 300);
      expect(find.text('Messages from the moderation team'), findsNothing);
      await finishHost(tester);
    });
  });
}
