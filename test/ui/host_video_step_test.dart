import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vibelive/app/hosthub/onboarding/helper/draft_controller.dart';
import 'package:vibelive/app/hosthub/onboarding/helper/draft_models.dart';
import 'package:vibelive/app/hosthub/onboarding/helper/flow_controller.dart';
import 'package:vibelive/app/hosthub/onboarding/helper/host_steps.dart';
import 'package:vibelive/app/hosthub/onboarding/helper/validation.dart';

/// The Video step: after Voice, optional, skipped while video intros are off.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  HostFlowController flowFor(
    HostDraftController draft, {
    required bool videoOn,
  }) => HostFlowController(
    draft: draft,
    pages: PageController(),
    submit: () async => null,
    exit: () {},
    explore: () {},
    rateFloors: () => (0, 0),
    skip: (s) => s == HostStep.video && !videoOn,
  );

  HostDraftController voiceDone() =>
      HostDraftController('v', persist: false)
        ..step.value = HostStep.voice
        ..voiceIntro.value = const HostVoiceIntro(
          savedMediaId: 7,
          savedUrl: 'https://cdn.example/intro.m4a',
        );

  test('the Video step comes right after Voice', () {
    expect(HostStep.voice.next, HostStep.video);
    expect(HostStep.video.next, HostStep.tagline);
    expect(HostStep.total, 13);
    expect(HostStep.pages.indexOf(HostStep.video), HostStep.video.page);
    expect(HostStep.linkable('video'), HostStep.video);
  });

  test('a video intro is optional: Continue never needs one', () {
    final d = HostDraftController('o', persist: false);
    expect(HostValidation.check(HostStep.video, d), isNull);
    d.dispose();
  });

  test('video intros on: Voice → Video → Tagline, and Back walks it', () async {
    final d = voiceDone();
    final flow = flowFor(d, videoOn: true);
    await flow.next();
    expect(d.step.value, HostStep.video);
    await flow.next(); // nothing recorded: still goes on
    expect(d.step.value, HostStep.tagline);
    flow.back();
    expect(d.step.value, HostStep.video);
    flow.dispose();
    d.dispose();
  });

  test('video intros off: Voice → Tagline, and Back skips it too', () async {
    final d = voiceDone();
    final flow = flowFor(d, videoOn: false);
    await flow.next();
    expect(d.step.value, HostStep.tagline);
    flow.back();
    expect(d.step.value, HostStep.voice);
    flow.dispose();
    d.dispose();
  });
}
