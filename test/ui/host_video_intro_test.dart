import 'package:flutter_test/flutter_test.dart';
import 'package:vibelive/app/api/hosthub/profile_patch.dart';
import 'package:vibelive/app/hosthub/onboarding/helper/draft_controller.dart';
import 'package:vibelive/app/hosthub/onboarding/helper/draft_models.dart';

import 'host_onboarding_support/harness.dart';

void main() {
  setUpAll(() async {
    await setUpHostHarness();
  });

  setUp(() async {
    await resetHost();
  });

  group('HostVideoIntro', () {
    test('a clip recorded now is what the save uploads', () {
      const intro = HostVideoIntro(path: '/tmp/clip.mp4', seconds: 12);
      expect(intro.upload, isNotNull);
      expect(intro.isNew, isTrue);
    });

    test('once uploaded it is sent by id rather than re-uploaded', () {
      const intro = HostVideoIntro(path: '/tmp/clip.mp4', uploadedId: 77);
      expect(intro.upload, isNotNull);
      expect(intro.uploadedId, 77);
    });

    test('a saved clip with nothing new sends nothing', () {
      // Re-saving an unchanged profile must not re-post the same clip.
      const intro = HostVideoIntro(savedMediaId: 5, savedUrl: '/uploads/a.mp4');
      expect(intro.upload, isNull);
      expect(intro.isNew, isFalse);
      expect(intro.isEmpty, isFalse);
    });

    test('nothing at all is empty', () {
      expect(const HostVideoIntro().isEmpty, isTrue);
      expect(HostVideoIntro.fromJson(null), isNull);
      expect(HostVideoIntro.fromJson(const {}), isNull);
    });

    test('dropping a new clip falls back to the saved one', () {
      const intro = HostVideoIntro(
        path: '/tmp/clip.mp4',
        savedMediaId: 5,
        savedUrl: '/uploads/a.mp4',
      );
      final back = intro.withoutRecording();
      expect(back, isNotNull);
      expect(back!.path, isNull);
      expect(back.savedUrl, '/uploads/a.mp4');
    });

    test('dropping a new clip with no saved one leaves nothing', () {
      expect(
        const HostVideoIntro(path: '/tmp/c.mp4').withoutRecording(),
        isNull,
      );
    });

    test('it survives a round trip through the draft json', () {
      const intro = HostVideoIntro(
        path: '/tmp/clip.mp4',
        seconds: 9,
        uploadedId: 3,
        savedMediaId: 5,
        savedUrl: '/uploads/a.mp4',
      );
      final back = HostVideoIntro.fromJson(intro.toJson());
      expect(back!.seconds, 9);
      expect(back.uploadedId, 3);
      expect(back.savedUrl, '/uploads/a.mp4');
    });
  });

  group('the draft carries it', () {
    test('a video intro is persisted and restored with the draft', () {
      final a = HostDraftController('video', persist: false);
      a.videoIntro.value = const HostVideoIntro(
        savedMediaId: 5,
        savedUrl: '/uploads/a.mp4',
      );
      final json = a.toJson();

      final b = HostDraftController('video', persist: false);
      b.restore(json);
      expect(b.videoIntro.value?.savedUrl, '/uploads/a.mp4');
    });
  });

  group('the patch', () {
    test('a video intro media id is sent under video_intro', () {
      final patch = HostProfilePatch.professional(
        handler: 'someone',
        tagline: 'hello',
        description: 'bio',
        languages: const [],
        videoIntroMediaId: 42,
      );
      expect(patch.data['video_intro'], 42);
    });

    test('no video intro means the key is absent, never null', () {
      // The backend rejects a null for this key, and sending one took
      // unrelated edits down with it - the same trap as audio_intro.
      final patch = HostProfilePatch.professional(
        handler: 'someone',
        tagline: 'hello',
        description: 'bio',
        languages: const [],
      );
      expect(patch.data.containsKey('video_intro'), isFalse);
    });
  });
}
