import 'package:flutter/foundation.dart';

import '../../../core/network/strapi.dart';

/// Host onboarding training (`GET /host-onboarding/config`,
/// docs/host_onboarding.md): steps the admin adds between the app's own
/// onboarding steps (a video to watch, a quiz to pass) and clips shown on any
/// onboarding screen. The app's own steps never change; with this off (or
/// missing), onboarding is exactly what it was.
///
/// Read leniently: anything this build does not understand, or that could not
/// work (no video, a quiz without questions, a position that is not one of the
/// app's steps), is left out rather than shown broken.

/// The app's own screens, in order (`HostStep` names), up to Guidelines: a
/// training step can follow any of them up to `preview`.
const hostTrainingScreens = [
  'intro',
  'basic',
  'interests',
  'photos',
  'voice',
  'video',
  'tagline',
  'bio',
  'rates',
  'availability',
  'preview',
  'guidelines',
];

/// true / false when the value says so; null when it is missing or unclear
/// (so the caller's default applies).
bool? _bool(Object? v) => switch (v) {
  final bool b => b,
  'true' || '1' || 1 => true,
  'false' || '0' || 0 => false,
  _ => null,
};

String? _https(Object? v) {
  final s = J.str(v)?.trim();
  if (s == null || s.isEmpty) return null;
  return s.toLowerCase().startsWith('https://') ? s : null;
}

/// A video the admin uploaded or linked, with its optional cover image.
@immutable
class TrainingVideo {
  const TrainingVideo({required this.url, this.posterUrl, this.durationSec});

  final String url;
  final String? posterUrl;
  final int? durationSec;

  static TrainingVideo? from(Object? raw) {
    final m = Strapi.map(raw);
    final url = _https(m?['url']);
    if (url == null) return null;
    return TrainingVideo(
      url: url,
      posterUrl: _https(m?['posterUrl']),
      durationSec: J.integer(m?['durationSec']),
    );
  }
}

@immutable
class TrainingOption {
  const TrainingOption({required this.id, required this.text});
  final String id;
  final String text;
}

@immutable
class TrainingQuestion {
  const TrainingQuestion({
    required this.id,
    required this.text,
    required this.options,
    this.multi = false,
    this.marks,
  });

  final String id;
  final String text;
  final List<TrainingOption> options;

  /// More than one answer is right: "select all that apply".
  final bool multi;

  /// What a right answer is worth; null when the admin hides marks.
  final int? marks;

  static TrainingQuestion? from(Object? raw) {
    final m = Strapi.map(raw);
    final id = J.str(m?['id']);
    final text = J.str(m?['text'])?.trim() ?? '';
    if (id == null || text.isEmpty) return null;
    final options = [
      for (final o in Strapi.list(m?['options']))
        if (J.str(o['id']) case final oid?)
          if ((J.str(o['text'])?.trim() ?? '').isNotEmpty)
            TrainingOption(id: oid, text: J.str(o['text'])!.trim()),
    ];
    if (options.length < 2) return null;
    return TrainingQuestion(
      id: id,
      text: text,
      options: options,
      multi: _bool(m?['multi']) ?? false,
      marks: J.integer(m?['marks']),
    );
  }
}

enum TrainingKind { video, quiz }

/// One training step. Video fields apply to [TrainingKind.video], quiz fields
/// to [TrainingKind.quiz].
@immutable
class TrainingStep {
  const TrainingStep({
    required this.id,
    required this.kind,
    required this.after,
    required this.title,
    this.subtitle = '',
    this.video,
    this.autoplay = true,
    this.startMuted = false,
    this.loop = false,
    this.skippable = true,
    this.skipAfterSec = 0,
    this.mustWatch = false,
    this.allowSeek = true,
    this.questions = const [],
    this.passPercent = 60,
    this.maxAttempts = 0,
    this.mustPass = true,
    this.showResult = true,
    this.showScore = true,
    this.showAnswers = true,
    this.shuffle = false,
  });

  final String id;
  final TrainingKind kind;

  /// The app step this one comes after (a `HostStep` name).
  final String after;
  final String title;
  final String subtitle;

  final TrainingVideo? video;
  final bool autoplay;
  final bool startMuted;
  final bool loop;
  final bool skippable;
  final int skipAfterSec;
  final bool mustWatch;
  final bool allowSeek;

  final List<TrainingQuestion> questions;
  final int passPercent;

  /// 0: no limit.
  final int maxAttempts;
  final bool mustPass;

  /// Off: the host only learns the answers went in; the team checks them.
  final bool showResult;

  /// Off: passed or not, no numbers.
  final bool showScore;
  final bool showAnswers;
  final bool shuffle;

  bool get isVideo => kind == TrainingKind.video;

  static TrainingStep? from(Object? raw) {
    final m = Strapi.map(raw);
    final id = J.str(m?['id']);
    final kind = switch (J.str(m?['kind'])) {
      'video' => TrainingKind.video,
      'quiz' => TrainingKind.quiz,
      _ => null,
    };
    final after = J.str(m?['after']);
    final title = J.str(m?['title'])?.trim() ?? '';
    if (id == null ||
        kind == null ||
        title.isEmpty ||
        after == null ||
        !hostTrainingScreens.contains(after) ||
        after == 'guidelines') {
      return null;
    }
    int count(String key, int fallback, {int min = 0, int max = 1 << 20}) {
      final n = J.integer(m?[key]);
      return n == null || n < min || n > max ? fallback : n;
    }

    bool flag(String key, bool fallback) => _bool(m?[key]) ?? fallback;
    final step = TrainingStep(
      id: id,
      kind: kind,
      after: after,
      title: title,
      subtitle: J.str(m?['subtitle'])?.trim() ?? '',
      video: TrainingVideo.from(m?['video']),
      autoplay: flag('autoplay', true),
      startMuted: flag('startMuted', false),
      loop: flag('loop', false),
      skippable: flag('skippable', true),
      skipAfterSec: count('skipAfterSec', 0, max: 600),
      mustWatch: flag('mustWatch', false),
      allowSeek: flag('allowSeek', true),
      questions: [
        for (final q in Strapi.list(m?['questions'])) ?TrainingQuestion.from(q),
      ],
      passPercent: count('passPercent', 60, max: 100),
      maxAttempts: count('maxAttempts', 0, max: 20),
      mustPass: flag('mustPass', true),
      showResult: flag('showResult', true),
      showScore: flag('showScore', true),
      showAnswers: flag('showAnswers', true),
      shuffle: flag('shuffle', false),
    );
    if (step.isVideo && step.video == null) return null;
    if (!step.isVideo && step.questions.isEmpty) return null;
    return step;
  }
}

/// A clip on one of the app's onboarding screens.
@immutable
class TrainingClip {
  const TrainingClip({
    required this.id,
    required this.screen,
    required this.video,
    this.title = '',
    this.autoplay = true,
    this.startMuted = true,
    this.loop = false,
  });

  final String id;

  /// A `HostStep` name.
  final String screen;
  final TrainingVideo video;
  final String title;
  final bool autoplay;
  final bool startMuted;
  final bool loop;

  static TrainingClip? from(Object? raw) {
    final m = Strapi.map(raw);
    final id = J.str(m?['id']);
    final screen = J.str(m?['screen']);
    final video = TrainingVideo.from(m?['video']);
    if (id == null ||
        video == null ||
        screen == null ||
        !hostTrainingScreens.contains(screen)) {
      return null;
    }
    return TrainingClip(
      id: id,
      screen: screen,
      video: video,
      title: J.str(m?['title'])?.trim() ?? '',
      autoplay: _bool(m?['autoplay']) ?? true,
      startMuted: _bool(m?['startMuted']) ?? true,
      loop: _bool(m?['loop']) ?? false,
    );
  }
}

/// Where this user stands on one step.
@immutable
class TrainingProgress {
  const TrainingProgress({
    this.status,
    this.done = false,
    this.attempts = 0,
    this.attemptsLeft,
    this.percent,
    this.bestPercent,
  });

  /// watched / skipped (video), passed / failed (quiz); null: not yet.
  final String? status;

  /// Nothing more is asked of this step.
  final bool done;
  final int attempts;

  /// null: no limit.
  final int? attemptsLeft;
  final int? percent;
  final int? bestPercent;

  static const none = TrainingProgress();

  factory TrainingProgress.from(Object? raw) {
    final m = Strapi.map(raw);
    if (m == null) return none;
    return TrainingProgress(
      status: J.str(m['status']),
      done: _bool(m['done']) ?? false,
      attempts: J.integer(m['attempts']) ?? 0,
      attemptsLeft: J.integer(m['attemptsLeft']),
      percent: J.integer(m['percent']),
      bestPercent: J.integer(m['bestPercent']),
    );
  }
}

/// The whole setup for this user.
@immutable
class HostTrainingConfig {
  const HostTrainingConfig({
    this.enabled = false,
    this.existingHosts = false,
    this.version = '',
    this.steps = const [],
    this.clips = const [],
    this.progress = const {},
  });

  final bool enabled;

  /// Hosts who already have a profile get the clips on their form and the
  /// steps as optional (never required).
  final bool existingHosts;
  final String version;
  final List<TrainingStep> steps;
  final List<TrainingClip> clips;
  final Map<String, TrainingProgress> progress;

  /// Nothing set up (or an older backend): onboarding as it always was.
  static const none = HostTrainingConfig();

  factory HostTrainingConfig.from(Object? raw) {
    final m = Strapi.map(raw);
    if (m == null || _bool(m['enabled']) != true) return none;
    final progress = Strapi.map(m['progress']) ?? const {};
    return HostTrainingConfig(
      enabled: true,
      existingHosts: _bool(m['existingHosts']) ?? false,
      version: J.str(m['version']) ?? '',
      steps: [for (final s in Strapi.list(m['steps'])) ?TrainingStep.from(s)],
      clips: [for (final c in Strapi.list(m['clips'])) ?TrainingClip.from(c)],
      progress: {
        for (final e in progress.entries) e.key: TrainingProgress.from(e.value),
      },
    );
  }

  TrainingProgress progressOf(String stepId) =>
      progress[stepId] ?? TrainingProgress.none;

  bool isDone(TrainingStep step) => progressOf(step.id).done;

  /// The steps placed after [screen] that are not done yet, in order.
  List<TrainingStep> pendingAfter(String screen) => enabled
      ? [
          for (final s in steps)
            if (s.after == screen && !isDone(s)) s,
        ]
      : const [];

  /// For an existing host ([existing]): only when the admin shows them
  /// training at all.
  bool reaches({required bool existing}) =>
      enabled && (!existing || existingHosts);

  /// Every step not done yet, in the order the flow meets them: what is
  /// asked before Submit when the host reached it another way (resumed past
  /// the step, a link, a step added since).
  List<TrainingStep> pendingAll() {
    if (!enabled) return const [];
    final out = <TrainingStep>[];
    for (final screen in hostTrainingScreens) {
      out.addAll(pendingAfter(screen));
    }
    return out;
  }

  /// The clips on [screen], in the admin's order.
  List<TrainingClip> clipsOn(String screen) => enabled
      ? [
          for (final c in clips)
            if (c.screen == screen) c,
        ]
      : const [];

  HostTrainingConfig withProgress(String stepId, TrainingProgress p) =>
      HostTrainingConfig(
        enabled: enabled,
        existingHosts: existingHosts,
        version: version,
        steps: steps,
        clips: clips,
        progress: {...progress, stepId: p},
      );
}

/// One question of a graded attempt.
@immutable
class QuizAnswerResult {
  const QuizAnswerResult({
    required this.questionId,
    required this.right,
    this.picked = const [],
    this.correct,
    this.explanation = '',
    this.marks,
  });

  final String questionId;
  final bool right;
  final List<String> picked;

  /// The question's marks; null when hidden.
  final int? marks;

  /// The right options; null when the admin hides answers.
  final List<String>? correct;
  final String explanation;
}

/// `POST /host-onboarding/steps/:id/quiz`: the graded attempt, as much of it
/// as the admin shows the host.
@immutable
class QuizResult {
  const QuizResult({
    required this.score,
    required this.total,
    required this.percent,
    required this.passed,
    required this.attempts,
    required this.results,
    required this.progress,
  });

  /// Marks (null when the admin hides them).
  final int? score;
  final int? total;
  final int? percent;

  /// null: the result is not shown to the host ("answers submitted").
  final bool? passed;

  bool get hidden => passed == null;
  final int attempts;
  final List<QuizAnswerResult> results;
  final TrainingProgress progress;

  factory QuizResult.from(Object? raw) {
    final m = Strapi.map(raw) ?? const {};
    return QuizResult(
      score: J.integer(m['score']),
      total: J.integer(m['total']),
      percent: J.integer(m['percent']),
      passed: _bool(m['passed']),
      attempts: J.integer(m['attempts']) ?? 0,
      results: [
        for (final r in Strapi.list(m['results']))
          if (J.str(r['questionId']) case final id?)
            QuizAnswerResult(
              questionId: id,
              right: _bool(r['right']) ?? false,
              picked: [
                for (final p in r['picked'] is List ? r['picked'] as List : [])
                  ?J.str(p),
              ],
              correct: r['correct'] is List
                  ? [for (final c in r['correct'] as List) ?J.str(c)]
                  : null,
              explanation: J.str(r['explanation'])?.trim() ?? '',
              marks: J.integer(r['marks']),
            ),
      ],
      progress: TrainingProgress.from(m['progress']),
    );
  }
}
