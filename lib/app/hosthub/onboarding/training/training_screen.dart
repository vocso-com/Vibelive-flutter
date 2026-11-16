import 'dart:async';

import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../../core/analytics/events/host_events.dart';
import '../../../../core/utils/scale.dart';
import '../../../api/hosthub/training_models.dart';
import '../../../api/hosthub/training_queries.dart';
import '../../../component/c_text.dart';
import '../../../component/pressable.dart';
import '../../../component/status_bar_style.dart';
import '../helper/host_palette.dart';
import '../helper/host_steps.dart';
import 'training_quiz.dart';
import 'training_video.dart';

/// Host onboarding training (docs/host_onboarding.md): the admin's videos and
/// quizzes, shown between the app's own onboarding steps for a NEW host.
///
/// The flow calls [run] when Continue leaves a step (the training placed
/// after it) and before Submit (anything still not done, however the host got
/// there). Nothing is shown when training is off, unreadable, or done. The
/// host leaving the training stays on the step they were on.
abstract final class HostTraining {
  /// Steps an existing host chose "Skip for now" on, this run of the app:
  /// not offered again until the app restarts.
  @visibleForTesting
  static final skipped = <String>{};

  /// Shows what is still to do after [after] (or, [beforeSubmit], everything
  /// still to do). true: carry on; false: the host backed out.
  ///
  /// [existing]: a host who already has a profile. Only when the admin shows
  /// training to them too, and never required: "Skip for now" carries on.
  static Future<bool> run(
    BuildContext context, {
    HostStep? after,
    bool beforeSubmit = false,
    bool existing = false,
  }) async {
    final config = await ensureHostTraining();
    if (!config.reaches(existing: existing)) return true;
    final pending = [
      for (final s
          in beforeSubmit
              ? config.pendingAll()
              : after == null
              ? const <TrainingStep>[]
              : config.pendingAfter(after.name))
        if (!existing || !skipped.contains(s.id)) s,
    ];
    if (pending.isEmpty || !context.mounted) return true;
    HostEvents.trainingShown(count: pending.length, beforeSubmit: beforeSubmit);
    final done = await open(context, pending, config, optional: existing);
    return done;
  }

  /// The training screen on [steps]. [optional]: "Skip for now" in the
  /// header (existing hosts). true when finished or skipped.
  static Future<bool> open(
    BuildContext context,
    List<TrainingStep> steps,
    HostTrainingConfig config, {
    bool optional = false,
  }) async {
    final done = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => HostTrainingScreen(
          steps: steps,
          config: config,
          optional: optional,
        ),
      ),
    );
    return done == true;
  }
}

/// The training steps, one after another, full screen.
class HostTrainingScreen extends StatefulWidget {
  const HostTrainingScreen({
    super.key,
    required this.steps,
    required this.config,
    this.optional = false,
  });

  final List<TrainingStep> steps;
  final HostTrainingConfig config;

  /// Not required (an existing host): "Skip for now" leaves, and carries on.
  final bool optional;

  @override
  State<HostTrainingScreen> createState() => _HostTrainingScreenState();
}

class _HostTrainingScreenState extends State<HostTrainingScreen> {
  int _index = 0;

  TrainingStep get _step => widget.steps[_index];

  @override
  void initState() {
    super.initState();
    _viewed();
  }

  void _viewed() => HostEvents.trainingStepViewed(
    stepId: _step.id,
    kind: _step.kind.name,
    number: _index + 1,
  );

  /// The current step is done: the next one, or back to the flow.
  void _next() {
    if (_index + 1 >= widget.steps.length) {
      Navigator.of(context).pop(true);
      return;
    }
    setState(() => _index += 1);
    _viewed();
  }

  void _leave() {
    HostEvents.trainingLeft(stepId: _step.id);
    Navigator.of(context).pop(false);
  }

  /// Optional training: the rest is skipped for this run of the app.
  void _skipAll() {
    HostEvents.trainingLeft(stepId: _step.id);
    for (final s in widget.steps.skip(_index)) {
      HostTraining.skipped.add(s.id);
    }
    Navigator.of(context).pop(true);
  }

  @override
  Widget build(BuildContext context) {
    final p = HostPalette.of(context);
    final step = _step;
    final total = widget.steps.length;
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _leave();
      },
      child: ThemedStatusBar(
        child: Scaffold(
          key: const ValueKey('host-training'),
          backgroundColor: p.bg,
          body: SafeArea(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Padding(
                  padding: EdgeInsets.fromLTRB(8.ms, 6.ms, 16.ms, 0),
                  child: Row(
                    children: [
                      Pressable(
                        key: const ValueKey('host-training-back'),
                        onPressed: _leave,
                        hitPadding: EdgeInsets.all(8.ms),
                        child: Padding(
                          padding: EdgeInsets.all(8.ms),
                          child: Icon(
                            LucideIcons.chevronLeft,
                            size: 24.ms,
                            color: p.text,
                          ),
                        ),
                      ),
                      SizedBox(width: 4.ms),
                      // Long translations shrink the badge, never overflow.
                      Flexible(
                        child: Container(
                          padding: EdgeInsets.symmetric(
                            horizontal: 10.ms,
                            vertical: 4.ms,
                          ),
                          decoration: BoxDecoration(
                            color: p.tint,
                            borderRadius: BorderRadius.circular(999),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                step.isVideo
                                    ? LucideIcons.clapperboard
                                    : LucideIcons.listChecks,
                                size: 13.ms,
                                color: p.accent,
                              ),
                              SizedBox(width: 6.ms),
                              Flexible(
                                child: CText(
                                  'hosttraining:badge',
                                  size: 11.5,
                                  weight: FontWeight.w800,
                                  color: p.accent,
                                  maxLines: 1,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                      const Spacer(),
                      if (total > 1)
                        CText(
                          'hosttraining:progress',
                          variables: {'current': _index + 1, 'total': total},
                          size: 12.5,
                          weight: FontWeight.w700,
                          color: p.muted,
                        ),
                    ],
                  ),
                ),
                if (total > 1)
                  Padding(
                    padding: EdgeInsets.fromLTRB(16.ms, 10.ms, 16.ms, 0),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(999),
                      child: LinearProgressIndicator(
                        value: (_index + 1) / total,
                        minHeight: 4.ms,
                        backgroundColor: p.track,
                        color: p.accent,
                      ),
                    ),
                  ),
                Expanded(
                  child: KeyedSubtree(
                    key: ValueKey('training-step-${step.id}'),
                    child: step.isVideo
                        ? TrainingVideoStep(step: step, onDone: _next)
                        : TrainingQuizStep(
                            step: step,
                            progress: widget.config.progressOf(step.id),
                            onDone: _next,
                          ),
                  ),
                ),
                // Not required (an existing host): leave, and carry on.
                if (widget.optional)
                  Padding(
                    padding: EdgeInsets.only(bottom: 12.ms),
                    child: Center(
                      child: Pressable(
                        key: const ValueKey('host-training-skip-all'),
                        onPressed: _skipAll,
                        hitPadding: EdgeInsets.all(8.ms),
                        child: CText(
                          'hosttraining:skip_for_now',
                          size: 14,
                          weight: FontWeight.w700,
                          color: p.muted,
                          maxLines: 1,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// The title and the admin's short line, at the top of a training step.
class TrainingHeading extends StatelessWidget {
  const TrainingHeading({super.key, required this.step});
  final TrainingStep step;

  @override
  Widget build(BuildContext context) {
    final p = HostPalette.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        CText.raw(step.title, size: 22, weight: FontWeight.w800, color: p.text),
        if (step.subtitle.isNotEmpty) ...[
          SizedBox(height: 6.ms),
          CText.raw(
            step.subtitle,
            size: 14,
            height: 20,
            weight: FontWeight.w500,
            color: p.muted,
          ),
        ],
      ],
    );
  }
}

/// Records a step's new progress in the cached setup, so the flow does not
/// ask for it again.
void recordTrainingProgress(TrainingStep step, TrainingProgress progress) {
  setHostTrainingProgress(step.id, progress);
}

/// A fire-and-forget future that never throws (analytics, saves the host
/// must not wait on).
void quietly(Future<void> f) => unawaited(f.catchError((Object _) {}));
