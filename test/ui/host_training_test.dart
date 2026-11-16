import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vibelive/app/api/hosthub/training_models.dart';
import 'package:vibelive/app/hosthub/approved/widgets/training_card.dart';
import 'package:vibelive/app/hosthub/onboarding/helper/host_steps.dart';
import 'package:vibelive/app/hosthub/onboarding/host_onboarding_screen.dart';
import 'package:vibelive/app/hosthub/onboarding/training/onboarding_clips.dart';
import 'package:vibelive/app/hosthub/onboarding/training/training_screen.dart';
import 'package:vibelive/app/hosthub/onboarding/widgets/continue_bar.dart';
import 'package:vibelive/core/network/strapi.dart';
// ignore: depend_on_referenced_packages
import 'package:video_player_platform_interface/video_player_platform_interface.dart';

import 'host_onboarding_support/harness.dart';

/// Host onboarding training (docs/host_onboarding.md): the admin's videos and
/// quizzes between the app's own steps, and clips on any step. The app's own
/// steps are untouched (their own tests run with training off).

/// Every clip "plays" for [clip] in real time: the controller asks for the
/// position every 100 ms, and it is 100 ms further each time while playing.
class _FakeVideo extends VideoPlayerPlatform {
  static const clip = Duration(seconds: 2);
  final _events = <int, StreamController<VideoEvent>>{};
  final _playing = <int>{};
  final _positions = <int, Duration>{};
  final opened = <String>[];
  int _next = 0;

  @override
  Future<void> init() async {}

  @override
  Future<int?> create(DataSource dataSource) async {
    final id = _next++;
    opened.add(dataSource.uri ?? '');
    final events = StreamController<VideoEvent>();
    _events[id] = events;
    scheduleMicrotask(
      () => events.add(
        VideoEvent(
          eventType: VideoEventType.initialized,
          duration: clip,
          size: const Size(1280, 720),
        ),
      ),
    );
    return id;
  }

  @override
  Future<int?> createWithOptions(VideoCreationOptions options) =>
      create(options.dataSource);

  @override
  Stream<VideoEvent> videoEventsFor(int playerId) => _events[playerId]!.stream;

  @override
  Future<void> dispose(int playerId) async {
    _playing.remove(playerId);
    unawaited(_events.remove(playerId)?.close());
  }

  @override
  Future<void> play(int playerId) async => _playing.add(playerId);

  @override
  Future<void> pause(int playerId) async => _playing.remove(playerId);

  bool isPlaying(int playerId) => _playing.contains(playerId);

  @override
  Future<Duration> getPosition(int playerId) async {
    final now = _positions[playerId] ?? Duration.zero;
    if (!_playing.contains(playerId)) return now;
    final next = now + const Duration(milliseconds: 100);
    return _positions[playerId] = next > clip ? clip : next;
  }

  @override
  Future<void> setLooping(int playerId, bool looping) async {}

  @override
  Future<void> setVolume(int playerId, double volume) async {}

  @override
  Future<void> setPlaybackSpeed(int playerId, double speed) async {}

  @override
  Future<void> seekTo(int playerId, Duration position) async =>
      _positions[playerId] = position;

  @override
  Future<void> setMixWithOthers(bool mixWithOthers) async {}

  @override
  Widget buildView(int playerId) => const SizedBox.expand();

  @override
  Widget buildViewWithOptions(VideoViewOptions options) =>
      const SizedBox.expand();
}

const _video = {'url': 'https://media.example/how.mp4'};

JsonMap _videoStep({
  String id = 'vid_one',
  String after = 'tagline',
  bool mustWatch = false,
  bool skippable = true,
  int skipAfterSec = 0,
}) => {
  'id': id,
  'kind': 'video',
  'after': after,
  'title': 'How Vibe Live works',
  'subtitle': 'Two minutes before you go live.',
  'video': _video,
  'autoplay': true,
  'mustWatch': mustWatch,
  'skippable': skippable,
  'skipAfterSec': skipAfterSec,
};

JsonMap _quizStep({String id = 'quiz_one', String after = 'tagline'}) => {
  'id': id,
  'kind': 'quiz',
  'after': after,
  'title': 'Quick check',
  'passPercent': 100,
  'mustPass': true,
  'questions': [
    {
      'id': 'q_one',
      'text': 'Can you share your phone number on a call?',
      'options': [
        {'id': 'opt_yes', 'text': 'Yes'},
        {'id': 'opt_no', 'text': 'No'},
      ],
      'multi': false,
    },
  ],
};

const JsonMap _approvedHost = {
  'id': 5,
  'documentId': 'exp1',
  'handler': 'aanyatalks',
  'isApproved': true,
  'isActive': true,
  'callAnyTime': false,
  'vocationMode': false,
  'rates': {'voiceCallRate': 25, 'videoCallRate': 35},
};

void _trainingOn(
  HostBackend backend, {
  List<JsonMap> steps = const [],
  List<JsonMap> clips = const [],
  Map<String, Object?> progress = const {},
  bool enabled = true,
  bool existingHosts = false,
}) {
  backend.replies['GET /api/host-onboarding/config'] = (_) => {
    'enabled': enabled,
    'existingHosts': existingHosts,
    'version': 'v1',
    'steps': steps,
    'clips': clips,
    'progress': progress,
  };
  for (final s in steps) {
    backend.replies['POST /api/host-onboarding/steps/${s['id']}/watched'] =
        (_) => {
          'progress': {'status': 'watched', 'done': true},
        };
  }
}

void _quizReply(HostBackend backend, {required bool passed, int? left}) {
  backend.replies['POST /api/host-onboarding/steps/quiz_one/quiz'] = (_) => {
    'score': passed ? 1 : 0,
    'total': 1,
    'percent': passed ? 100 : 0,
    'passed': passed,
    'attempts': 1,
    'results': [
      {
        'questionId': 'q_one',
        'right': passed,
        'picked': [passed ? 'opt_no' : 'opt_yes'],
        'correct': ['opt_no'],
        'explanation': 'Never share contact details.',
      },
    ],
    'progress': {
      'status': passed ? 'passed' : 'failed',
      'done': passed || left == 0,
      'attempts': 1,
      'attemptsLeft': left,
    },
  };
}

Future<void> _openOn(
  WidgetTester tester,
  String step, {
  Map<String, Object?> extra = const {},
}) async {
  await parkDraft(step, extra: extra);
  phone(tester, top: 47, bottom: 34);
  await pumpRoutes(tester, const HostOnboardingScreen());
  await pumpFor(tester, 600);
}

bool _enabled(WidgetTester tester, String key) =>
    tester.widget<HostButton>(find.byKey(ValueKey(key))).onPressed != null;

void main() {
  late _FakeVideo video;

  setUpAll(setUpHostHarness);
  setUp(() {
    video = _FakeVideo();
    VideoPlayerPlatform.instance = video;
    HostStepWithClips.hidden.clear();
    HostTraining.skipped.clear();
  });

  group('the setup, read leniently', () {
    test('off, missing or unknown: no training at all', () {
      expect(HostTrainingConfig.from(null).enabled, isFalse);
      expect(HostTrainingConfig.from(const {'data': []}).enabled, isFalse);
      expect(
        HostTrainingConfig.from({
          'enabled': false,
          'steps': [_videoStep()],
        }).pendingAll(),
        isEmpty,
      );
    });

    test('what could not work is left out', () {
      final cfg = HostTrainingConfig.from({
        'enabled': true,
        'steps': [
          _videoStep(),
          {
            ..._videoStep(id: 'vid_bad'),
            'video': const {'url': 'http://insecure/a.mp4'},
          },
          {..._videoStep(id: 'vid_after_submit'), 'after': 'guidelines'},
          {..._videoStep(id: 'vid_nowhere'), 'after': 'somewhere'},
          {..._quizStep(id: 'quiz_empty'), 'questions': const []},
          const {
            'id': 'poll_one',
            'kind': 'poll',
            'after': 'basic',
            'title': 'x',
          },
          _quizStep(),
        ],
        'clips': const [
          {'id': 'clip_a', 'screen': 'photos', 'video': _video},
          {'id': 'clip_b', 'screen': 'nowhere', 'video': _video},
        ],
      });
      expect(cfg.steps.map((s) => s.id), ['vid_one', 'quiz_one']);
      expect(cfg.clips.map((c) => c.id), ['clip_a']);
    });

    test('pending: after a step in order, and everything in flow order', () {
      final cfg = HostTrainingConfig.from({
        'enabled': true,
        'steps': [
          _quizStep(after: 'preview'),
          _videoStep(after: 'basic'),
          _videoStep(id: 'vid_two', after: 'preview'),
        ],
        'progress': const {
          'vid_two': {'status': 'watched', 'done': true},
        },
      });
      expect(cfg.pendingAfter('preview').map((s) => s.id), ['quiz_one']);
      expect(cfg.pendingAll().map((s) => s.id), ['vid_one', 'quiz_one']);
    });
  });

  group('in the flow', () {
    testWidgets('Continue on the step it follows opens the video, then the '
        'quiz; then the flow goes on', (tester) async {
      final backend = await resetHost();
      _trainingOn(backend, steps: [_videoStep(), _quizStep()]);
      _quizReply(backend, passed: true);
      await _openOn(tester, 'tagline');

      await tapContinue(tester, settle: 900);
      expect(find.byKey(const ValueKey('host-training')), findsOneWidget);
      expect(find.text('How Vibe Live works'), findsOneWidget);
      expect(find.text('1 of 2'), findsOneWidget);
      expect(video.opened, ['https://media.example/how.mp4']);

      // Not a must-watch: Continue at once.
      expect(_enabled(tester, 'training-continue'), isTrue);
      await tester.tap(find.byKey(const ValueKey('training-continue')));
      await pumpFor(tester, 600);
      final watched = backend
          .sent('POST', '/host-onboarding/steps/vid_one/watched')
          .single;
      expect(Strapi.map(watched.data)?['skipped'], isFalse);

      // The quiz: every question answered before Submit.
      expect(find.text('Quick check'), findsOneWidget);
      expect(_enabled(tester, 'training-quiz-submit'), isFalse);
      await tester.tap(find.byKey(const ValueKey('training-option-opt_no')));
      await pumpFor(tester, 200);
      await tester.tap(find.byKey(const ValueKey('training-quiz-submit')));
      await pumpFor(tester, 600);
      final quiz = backend
          .sent('POST', '/host-onboarding/steps/quiz_one/quiz')
          .single;
      expect(Strapi.map(quiz.data)?['answers'], {
        'q_one': ['opt_no'],
      });
      expect(
        find.byKey(const ValueKey('training-quiz-passed')),
        findsOneWidget,
      );

      await tester.tap(find.byKey(const ValueKey('training-continue')));
      await pumpFor(tester, 900);
      expect(find.byKey(const ValueKey('host-training')), findsNothing);
      expect(savedDraft()!['step'], 'bio');
      await finishHost(tester);
    });

    testWidgets('backing out stays on the step; Continue asks again', (
      tester,
    ) async {
      final backend = await resetHost();
      _trainingOn(backend, steps: [_videoStep()]);
      await _openOn(tester, 'tagline');
      await tapContinue(tester, settle: 900);
      await tester.tap(find.byKey(const ValueKey('host-training-back')));
      await pumpFor(tester, 600);
      expect(find.byKey(const ValueKey('host-training')), findsNothing);
      expect(savedDraft()!['step'], 'tagline');
      await tapContinue(tester, settle: 900);
      expect(find.byKey(const ValueKey('host-training')), findsOneWidget);
      await finishHost(tester);
    });

    testWidgets('done steps are not asked again', (tester) async {
      final backend = await resetHost();
      _trainingOn(
        backend,
        steps: [_videoStep(), _quizStep()],
        progress: {
          'vid_one': {'status': 'watched', 'done': true},
          'quiz_one': {'status': 'passed', 'done': true},
        },
      );
      await _openOn(tester, 'tagline');
      await tapContinue(tester, settle: 900);
      expect(find.byKey(const ValueKey('host-training')), findsNothing);
      expect(savedDraft()!['step'], 'bio');
      await finishHost(tester);
    });

    testWidgets('training off: Continue is the app flow as before', (
      tester,
    ) async {
      final backend = await resetHost();
      _trainingOn(backend, steps: [_videoStep()], enabled: false);
      await _openOn(tester, 'tagline');
      await tapContinue(tester, settle: 900);
      expect(find.byKey(const ValueKey('host-training')), findsNothing);
      expect(savedDraft()!['step'], 'bio');
      await finishHost(tester);
    });

    testWidgets('before Submit, anything still to do comes first; then the '
        'application goes in', (tester) async {
      final backend = await resetHost();
      // Placed after Basic, which this host passed before it was set up.
      _trainingOn(backend, steps: [_videoStep(after: 'basic')]);
      await _openOn(tester, 'guidelines', extra: {'agreed': true});
      await tapContinue(tester, settle: 900);
      expect(find.byKey(const ValueKey('host-training')), findsOneWidget);
      expect(backend.sent('POST', '/expert-profile-approvals'), isEmpty);

      await tester.tap(find.byKey(const ValueKey('training-continue')));
      await pumpFor(tester, 2500);
      expect(find.byKey(const ValueKey('host-training')), findsNothing);
      expect(backend.sent('POST', '/expert-profile-approvals'), hasLength(1));
      await finishHost(tester);
    });

    testWidgets('an existing host gets nothing unless the admin says so', (
      tester,
    ) async {
      final backend = await resetHost(expert: _approvedHost);
      _trainingOn(
        backend,
        steps: [_videoStep()],
        clips: [
          {'id': 'clip_a', 'screen': 'tagline', 'video': _video},
        ],
      );
      phone(tester, top: 47, bottom: 34);
      await pumpRoutes(
        tester,
        const HostOnboardingScreen(editStep: HostStep.tagline),
      );
      await pumpFor(tester, 900);
      expect(
        find.byKey(const ValueKey('onboarding-clips-tagline')),
        findsNothing,
      );
      await finishHost(tester);
    });

    testWidgets('existing hosts switched on: clips on their form, training '
        'never required ("Skip for now")', (tester) async {
      final backend = await resetHost(expert: _approvedHost);
      _trainingOn(
        backend,
        existingHosts: true,
        steps: [_videoStep(mustWatch: true, skippable: false)],
        clips: [
          {'id': 'clip_a', 'screen': 'tagline', 'video': _video},
        ],
      );
      // Editing one section: the clips, no training.
      phone(tester, top: 47, bottom: 34);
      await pumpRoutes(
        tester,
        const HostOnboardingScreen(editStep: HostStep.tagline),
      );
      await pumpFor(tester, 900);
      expect(
        find.byKey(const ValueKey('onboarding-clips-tagline')),
        findsOneWidget,
      );
      await finishHost(tester);

      // The whole form again: the step after Tagline, with Skip for now.
      final again = await resetHost(expert: _approvedHost);
      _trainingOn(
        again,
        existingHosts: true,
        steps: [_videoStep(mustWatch: true, skippable: false)],
      );
      await _openOn(tester, 'tagline');
      await tapContinue(tester, settle: 900);
      expect(find.byKey(const ValueKey('host-training')), findsOneWidget);
      expect(_enabled(tester, 'training-continue'), isFalse);
      await tester.tap(find.byKey(const ValueKey('host-training-skip-all')));
      await pumpFor(tester, 900);
      expect(find.byKey(const ValueKey('host-training')), findsNothing);
      expect(savedDraft()!['step'], 'bio');
      await finishHost(tester);
    });
  });

  group('the video', () {
    testWidgets('must watch: Continue opens at the end; Skip after its '
        'seconds', (tester) async {
      final backend = await resetHost();
      _trainingOn(
        backend,
        steps: [_videoStep(mustWatch: true, skipAfterSec: 1)],
      );
      await _openOn(tester, 'tagline');
      await tapContinue(tester, settle: 300);
      expect(find.byKey(const ValueKey('host-training')), findsOneWidget);
      expect(_enabled(tester, 'training-continue'), isFalse);
      expect(find.byKey(const ValueKey('training-watch-hint')), findsOneWidget);
      expect(find.byKey(const ValueKey('training-skip')), findsNothing);

      // A second in: Skip shows. Played out: Continue opens.
      await pumpFor(tester, 1200);
      expect(find.byKey(const ValueKey('training-skip')), findsOneWidget);
      await pumpFor(tester, 2500);
      expect(_enabled(tester, 'training-continue'), isTrue);
      expect(find.byKey(const ValueKey('training-skip')), findsNothing);

      await tester.tap(find.byKey(const ValueKey('training-continue')));
      await pumpFor(tester, 900);
      final body = Strapi.map(
        backend
            .sent('POST', '/host-onboarding/steps/vid_one/watched')
            .single
            .data,
      );
      expect(body?['completed'], isTrue);
      await finishHost(tester);
    });

    testWidgets('Skip is recorded as skipped', (tester) async {
      final backend = await resetHost();
      _trainingOn(backend, steps: [_videoStep(mustWatch: true)]);
      await _openOn(tester, 'tagline');
      await tapContinue(tester, settle: 400);
      await tester.tap(find.byKey(const ValueKey('training-skip')));
      await pumpFor(tester, 900);
      final body = Strapi.map(
        backend
            .sent('POST', '/host-onboarding/steps/vid_one/watched')
            .single
            .data,
      );
      expect(body?['skipped'], isTrue);
      expect(find.byKey(const ValueKey('host-training')), findsNothing);
      await finishHost(tester);
    });
  });

  group('the quiz', () {
    testWidgets('not passed with attempts left: Try again, no Continue', (
      tester,
    ) async {
      final backend = await resetHost();
      _trainingOn(backend, steps: [_quizStep()]);
      _quizReply(backend, passed: false, left: 1);
      await _openOn(tester, 'tagline');
      await tapContinue(tester, settle: 900);
      await tester.tap(find.byKey(const ValueKey('training-option-opt_yes')));
      await pumpFor(tester, 200);
      await tester.tap(find.byKey(const ValueKey('training-quiz-submit')));
      await pumpFor(tester, 600);
      expect(
        find.byKey(const ValueKey('training-quiz-failed')),
        findsOneWidget,
      );
      expect(find.text('Never share contact details.'), findsOneWidget);
      expect(find.byKey(const ValueKey('training-continue')), findsNothing);

      await tester.tap(find.byKey(const ValueKey('training-quiz-retry')));
      await pumpFor(tester, 300);
      expect(
        _enabled(tester, 'training-quiz-submit'),
        isFalse,
        reason: 'answers cleared',
      );
      await finishHost(tester);
    });

    testWidgets('marks shown: each question says its marks', (tester) async {
      final backend = await resetHost();
      _trainingOn(
        backend,
        steps: [
          {
            ..._quizStep(),
            'questions': [
              {
                ...(_quizStep()['questions']! as List).first as JsonMap,
                'marks': 3,
              },
            ],
          },
        ],
      );
      await _openOn(tester, 'tagline');
      await tapContinue(tester, settle: 900);
      expect(
        find.byKey(const ValueKey('training-marks-q_one')),
        findsOneWidget,
      );
      expect(find.text('Marks: 3'), findsOneWidget);
      await finishHost(tester);
    });

    testWidgets('marks hidden: passed or not, no numbers', (tester) async {
      final backend = await resetHost();
      _trainingOn(
        backend,
        steps: [
          {..._quizStep(), 'showScore': false},
        ],
      );
      backend.replies['POST /api/host-onboarding/steps/quiz_one/quiz'] = (_) =>
          {
            'submitted': true,
            'passed': true,
            'attempts': 1,
            'results': [
              {
                'questionId': 'q_one',
                'right': true,
                'picked': ['opt_no'],
              },
            ],
            'progress': {'status': 'passed', 'done': true, 'attempts': 1},
          };
      await _openOn(tester, 'tagline');
      await tapContinue(tester, settle: 900);
      await tester.tap(find.byKey(const ValueKey('training-option-opt_no')));
      await pumpFor(tester, 200);
      await tester.tap(find.byKey(const ValueKey('training-quiz-submit')));
      await pumpFor(tester, 600);
      expect(find.text('Passed!'), findsOneWidget);
      expect(find.textContaining('of 1 right'), findsNothing);
      await finishHost(tester);
    });

    testWidgets('result hidden: only "submitted", then the host goes on', (
      tester,
    ) async {
      final backend = await resetHost();
      _trainingOn(
        backend,
        steps: [
          {..._quizStep(), 'showResult': false, 'mustPass': false},
        ],
      );
      backend.replies['POST /api/host-onboarding/steps/quiz_one/quiz'] = (_) =>
          {
            'submitted': true,
            'attempts': 1,
            'progress': {'status': 'submitted', 'done': true, 'attempts': 1},
          };
      await _openOn(tester, 'tagline');
      await tapContinue(tester, settle: 900);
      await tester.tap(find.byKey(const ValueKey('training-option-opt_yes')));
      await pumpFor(tester, 200);
      await tester.tap(find.byKey(const ValueKey('training-quiz-submit')));
      await pumpFor(tester, 600);
      expect(
        find.byKey(const ValueKey('training-quiz-submitted')),
        findsOneWidget,
      );
      expect(find.byKey(const ValueKey('training-quiz-failed')), findsNothing);
      expect(find.byKey(const ValueKey('training-quiz-retry')), findsNothing);
      await tester.tap(find.byKey(const ValueKey('training-continue')));
      await pumpFor(tester, 900);
      expect(savedDraft()!['step'], 'bio');
      await finishHost(tester);
    });

    testWidgets('out of attempts: the host goes on', (tester) async {
      final backend = await resetHost();
      _trainingOn(backend, steps: [_quizStep()]);
      _quizReply(backend, passed: false, left: 0);
      await _openOn(tester, 'tagline');
      await tapContinue(tester, settle: 900);
      await tester.tap(find.byKey(const ValueKey('training-option-opt_yes')));
      await pumpFor(tester, 200);
      await tester.tap(find.byKey(const ValueKey('training-quiz-submit')));
      await pumpFor(tester, 600);
      expect(find.byKey(const ValueKey('training-quiz-retry')), findsNothing);
      await tester.tap(find.byKey(const ValueKey('training-continue')));
      await pumpFor(tester, 900);
      expect(savedDraft()!['step'], 'bio');
      await finishHost(tester);
    });
  });

  group('clips', () {
    testWidgets('a frame of clips above its step; Hide keeps it small', (
      tester,
    ) async {
      final backend = await resetHost();
      _trainingOn(
        backend,
        clips: [
          {
            'id': 'clip_a',
            'screen': 'tagline',
            'video': _video,
            'title': 'A good tagline',
          },
          {'id': 'clip_b', 'screen': 'tagline', 'video': _video},
          {'id': 'clip_c', 'screen': 'bio', 'video': _video},
        ],
      );
      await _openOn(tester, 'tagline');
      expect(
        find.byKey(const ValueKey('onboarding-clips-tagline')),
        findsOneWidget,
      );
      expect(find.text('A good tagline'), findsOneWidget);
      expect(tester.takeException(), isNull);

      await tester.tap(find.byKey(const ValueKey('onboarding-clips-hide')));
      await pumpFor(tester, 300);
      expect(
        find.byKey(const ValueKey('onboarding-clips-show')),
        findsOneWidget,
      );
      expect(find.text('Watch 2 videos'), findsOneWidget);
      await finishHost(tester);
    });

    testWidgets('the frame scrolls with the page, never pinned over it', (
      tester,
    ) async {
      final backend = await resetHost();
      _trainingOn(
        backend,
        clips: [
          {'id': 'clip_a', 'screen': 'basic', 'video': _video},
        ],
      );
      await parkDraft('basic');
      phone(tester, size: const Size(360, 640), top: 20);
      await pumpRoutes(tester, const HostOnboardingScreen());
      await pumpFor(tester, 600);
      final frame = find.byKey(const ValueKey('onboarding-clips-basic'));
      final page = find.ancestor(
        of: frame,
        matching: find.byType(SingleChildScrollView),
      );
      expect(page, findsOneWidget, reason: 'inside the step\'s own scroll');
      final top = tester.getTopLeft(frame).dy;
      await tester.drag(page, const Offset(0, -300));
      await pumpFor(tester, 400);
      expect(tester.getTopLeft(frame).dy, lessThan(top - 200));
      await finishHost(tester);
    });

    testWidgets('320 wide, every step with a clip: no overflow', (
      tester,
    ) async {
      final backend = await resetHost();
      _trainingOn(
        backend,
        clips: [
          for (final s in hostTrainingScreens)
            {
              'id': 'clip_$s',
              'screen': s,
              'video': _video,
              'title': 'How to do $s well',
            },
        ],
      );
      for (final s in [
        'intro',
        'basic',
        'photos',
        'tagline',
        'rates',
        'guidelines',
      ]) {
        await parkDraft(s);
        phone(tester, size: const Size(320, 568), top: 20);
        await pumpRoutes(tester, HostOnboardingScreen(key: ValueKey(s)));
        await pumpFor(tester, 600);
        expect(tester.takeException(), isNull, reason: s);
        expect(
          find.byKey(ValueKey('onboarding-clips-$s')),
          findsOneWidget,
          reason: s,
        );
        await finishHost(tester);
      }
    });
  });

  testWidgets('320 wide, Hindi: the training screens fit (Skip for now '
      'included)', (tester) async {
    final backend = await resetHost(expert: _approvedHost);
    _trainingOn(
      backend,
      existingHosts: true,
      steps: [_videoStep(mustWatch: true), _quizStep()],
    );
    phone(tester, size: const Size(320, 568), top: 20);
    await pumpRoutes(
      tester,
      const Scaffold(body: HostTrainingCard()),
      locale: const Locale('hi'),
    );
    await pumpFor(tester, 600);
    expect(tester.takeException(), isNull, reason: 'card');
    await tester.tap(find.byKey(const ValueKey('host-training-card')));
    await pumpFor(tester, 900);
    expect(tester.takeException(), isNull, reason: 'video step');
    await tester.tap(find.byKey(const ValueKey('training-skip')));
    await pumpFor(tester, 900);
    expect(find.byKey(const ValueKey('training-quiz')), findsOneWidget);
    expect(tester.takeException(), isNull, reason: 'quiz step');
    await finishHost(tester);
  });

  group('Host Hub card (existing hosts)', () {
    testWidgets('shown when the admin includes existing hosts; opens the '
        'training with Skip for now', (tester) async {
      final backend = await resetHost(expert: _approvedHost);
      _trainingOn(backend, existingHosts: true, steps: [_videoStep()]);
      phone(tester);
      await pumpRoutes(tester, const Scaffold(body: HostTrainingCard()));
      await pumpFor(tester, 600);
      expect(find.byKey(const ValueKey('host-training-card')), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('host-training-card')));
      await pumpFor(tester, 900);
      expect(find.byKey(const ValueKey('host-training')), findsOneWidget);
      expect(
        find.byKey(const ValueKey('host-training-skip-all')),
        findsOneWidget,
      );
      await finishHost(tester);
    });

    testWidgets('nothing when existing hosts are not included', (tester) async {
      final backend = await resetHost(expert: _approvedHost);
      _trainingOn(backend, steps: [_videoStep()]);
      phone(tester);
      await pumpRoutes(tester, const Scaffold(body: HostTrainingCard()));
      await pumpFor(tester, 600);
      expect(find.byKey(const ValueKey('host-training-card')), findsNothing);
      await finishHost(tester);
    });
  });
}
