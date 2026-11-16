import 'dart:math';

import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../../core/analytics/events/host_events.dart';
import '../../../../core/network/api_exception.dart';
import '../../../../core/utils/scale.dart';
import '../../../api/hosthub/training_api.dart';
import '../../../api/hosthub/training_models.dart';
import '../../../component/c_text.dart';
import '../../../component/c_toast.dart';
import '../../../component/pressable.dart';
import '../helper/host_palette.dart';
import '../widgets/continue_bar.dart';
import 'training_screen.dart';

/// A training quiz: every question answered, then marked by the server. The
/// result says how it went (with the right answers when the admin shows
/// them); Try again while attempts are left, Continue once passed, out of
/// attempts, or when passing is not required.
class TrainingQuizStep extends StatefulWidget {
  const TrainingQuizStep({
    super.key,
    required this.step,
    required this.progress,
    required this.onDone,
  });

  final TrainingStep step;
  final TrainingProgress progress;
  final VoidCallback onDone;

  @override
  State<TrainingQuizStep> createState() => _TrainingQuizStepState();
}

class _TrainingQuizStepState extends State<TrainingQuizStep> {
  final _answers = <String, Set<String>>{};
  late List<TrainingQuestion> _order = _arrange();
  QuizResult? _result;
  bool _sending = false;

  /// Nothing more asked of this quiz (from the server).
  late bool _done = widget.progress.done;

  TrainingStep get _step => widget.step;

  /// The questions, and each one's answers, in this attempt's order.
  List<TrainingQuestion> _arrange() {
    final qs = _step.questions;
    if (!_step.shuffle) return qs;
    final rnd = Random();
    return [
      for (final q in [...qs]..shuffle(rnd))
        TrainingQuestion(
          id: q.id,
          text: q.text,
          multi: q.multi,
          options: [...q.options]..shuffle(rnd),
        ),
    ];
  }

  bool get _allAnswered =>
      _order.every((q) => (_answers[q.id] ?? const {}).isNotEmpty);

  void _pick(TrainingQuestion q, String optionId) {
    if (_result != null || _sending) return;
    setState(() {
      final picked = _answers.putIfAbsent(q.id, () => <String>{});
      if (q.multi) {
        picked.contains(optionId)
            ? picked.remove(optionId)
            : picked.add(optionId);
      } else {
        picked
          ..clear()
          ..add(optionId);
      }
    });
  }

  Future<void> _submit() async {
    if (_sending || !_allAnswered) return;
    setState(() => _sending = true);
    try {
      final result = await HostTrainingApi.submitQuiz(_step.id, {
        for (final e in _answers.entries) e.key: e.value.toList(),
      });
      HostEvents.trainingQuizSubmitted(
        stepId: _step.id,
        percent: result.percent,
        passed: result.passed,
        attempt: result.attempts,
      );
      recordTrainingProgress(_step, result.progress);
      if (!mounted) return;
      setState(() {
        _result = result;
        _done = result.progress.done;
      });
    } on ApiException catch (e) {
      // Out of attempts, or the quiz was removed meanwhile: nothing more to
      // ask, the host goes on.
      if (e.statusCode == 403 || e.statusCode == 404) {
        recordTrainingProgress(_step, const TrainingProgress(done: true));
        if (!mounted) return;
        setState(() => _done = true);
        widget.onDone();
        return;
      }
      CToast.error(e);
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  void _retry() => setState(() {
    _answers.clear();
    _result = null;
    _order = _arrange();
  });

  @override
  Widget build(BuildContext context) {
    final p = HostPalette.of(context);
    final result = _result;
    final canRetry =
        result != null &&
        result.passed == false &&
        (result.progress.attemptsLeft == null ||
            result.progress.attemptsLeft! > 0);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(
          child: ListView(
            key: const ValueKey('training-quiz'),
            padding: EdgeInsets.fromLTRB(20.ms, 18.ms, 20.ms, 16.ms),
            children: [
              TrainingHeading(step: _step),
              if (result != null) ...[
                SizedBox(height: 16.ms),
                _Verdict(step: _step, result: result),
              ],
              for (final (i, q) in _order.indexed) ...[
                SizedBox(height: 16.ms),
                _QuestionCard(
                  number: i + 1,
                  question: q,
                  picked: _answers[q.id] ?? const {},
                  marked: result?.results
                      .where((r) => r.questionId == q.id)
                      .firstOrNull,
                  onPick: (id) => _pick(q, id),
                ),
              ],
            ],
          ),
        ),
        Padding(
          padding: EdgeInsets.fromLTRB(20.ms, 8.ms, 20.ms, 16.ms),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (result == null && !_allAnswered)
                Padding(
                  padding: EdgeInsets.only(bottom: 10.ms),
                  child: CText(
                    'hosttraining:quiz_answer_all',
                    size: 12.5,
                    weight: FontWeight.w600,
                    color: p.muted,
                    align: TextAlign.center,
                  ),
                ),
              if (result == null)
                HostButton(
                  key: const ValueKey('training-quiz-submit'),
                  label: 'hosttraining:quiz_submit',
                  loading: _sending,
                  onPressed: _allAnswered ? _submit : null,
                )
              else ...[
                if (canRetry && !_done) ...[
                  HostButton(
                    key: const ValueKey('training-quiz-retry'),
                    label: 'hosttraining:quiz_retry',
                    arrow: false,
                    onPressed: _retry,
                  ),
                ] else if (canRetry && _done) ...[
                  // Passing is not required: another go is offered, not asked.
                  Pressable(
                    key: const ValueKey('training-quiz-retry'),
                    onPressed: _retry,
                    hitPadding: EdgeInsets.all(8.ms),
                    child: Padding(
                      padding: EdgeInsets.only(bottom: 10.ms),
                      child: CText(
                        'hosttraining:quiz_retry',
                        size: 14,
                        weight: FontWeight.w700,
                        color: p.accent,
                        align: TextAlign.center,
                      ),
                    ),
                  ),
                ],
                if (_done)
                  HostButton(
                    key: const ValueKey('training-continue'),
                    label: 'hosttraining:continue',
                    onPressed: widget.onDone,
                  ),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

class _Verdict extends StatelessWidget {
  const _Verdict({required this.step, required this.result});
  final TrainingStep step;
  final QuizResult result;

  @override
  Widget build(BuildContext context) {
    final p = HostPalette.of(context);
    // The admin keeps the result for the team: only that it went in.
    if (result.passed == null) {
      return Container(
        key: const ValueKey('training-quiz-submitted'),
        padding: EdgeInsets.all(14.ms),
        decoration: BoxDecoration(
          color: p.tint,
          borderRadius: BorderRadius.circular(14.ms),
        ),
        child: Row(
          children: [
            Icon(LucideIcons.circleCheck, color: p.accent, size: 22.ms),
            SizedBox(width: 10.ms),
            Expanded(
              child: CText(
                'hosttraining:quiz_submitted',
                size: 14,
                weight: FontWeight.w700,
                color: p.text,
              ),
            ),
          ],
        ),
      );
    }
    final passed = result.passed!;
    final left = result.progress.attemptsLeft;
    // Marks hidden: passed or not, no numbers.
    final numbers = result.score != null && result.total != null;
    final (fg, bg) = passed
        ? (p.success, p.successTint)
        : (p.danger, p.dangerTint);
    return Container(
      key: ValueKey(passed ? 'training-quiz-passed' : 'training-quiz-failed'),
      padding: EdgeInsets.all(14.ms),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(14.ms),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            passed ? LucideIcons.partyPopper : LucideIcons.circleAlert,
            color: fg,
            size: 22.ms,
          ),
          SizedBox(width: 10.ms),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                CText(
                  switch ((passed, numbers)) {
                    (true, true) => 'hosttraining:quiz_passed',
                    (false, true) => 'hosttraining:quiz_failed',
                    (true, false) => 'hosttraining:quiz_passed_plain',
                    (false, false) => 'hosttraining:quiz_failed_plain',
                  },
                  variables: {
                    'score': result.score,
                    'total': result.total,
                    'pass': step.passPercent,
                  },
                  size: 14.5,
                  weight: FontWeight.w800,
                  color: fg,
                ),
                if (!passed && left != null) ...[
                  SizedBox(height: 4.ms),
                  CText(
                    left > 0
                        ? 'hosttraining:quiz_attempts_left'
                        : 'hosttraining:quiz_no_attempts',
                    variables: {'count': left},
                    size: 12.5,
                    weight: FontWeight.w600,
                    color: p.muted,
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _QuestionCard extends StatelessWidget {
  const _QuestionCard({
    required this.number,
    required this.question,
    required this.picked,
    required this.marked,
    required this.onPick,
  });

  final int number;
  final TrainingQuestion question;
  final Set<String> picked;

  /// After submitting: how this question went.
  final QuizAnswerResult? marked;
  final ValueChanged<String> onPick;

  @override
  Widget build(BuildContext context) {
    final p = HostPalette.of(context);
    final m = marked;
    final correct = m?.correct;
    return Container(
      key: ValueKey('training-question-${question.id}'),
      padding: EdgeInsets.all(14.ms),
      decoration: BoxDecoration(
        color: p.card,
        borderRadius: BorderRadius.circular(16.ms),
        border: Border.all(
          color: m == null ? p.cardBorder : (m.right ? p.success : p.danger),
          width: m == null ? 1 : 1.5,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 24.ms,
                height: 24.ms,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: p.tint,
                  shape: BoxShape.circle,
                ),
                child: CText.raw(
                  '$number',
                  size: 12,
                  weight: FontWeight.w800,
                  color: p.accent,
                ),
              ),
              SizedBox(width: 10.ms),
              Expanded(
                child: CText.raw(
                  question.text,
                  size: 15,
                  height: 21,
                  weight: FontWeight.w700,
                  color: p.text,
                ),
              ),
              if (m != null) ...[
                SizedBox(width: 8.ms),
                Icon(
                  m.right ? LucideIcons.circleCheck : LucideIcons.circleX,
                  color: m.right ? p.success : p.danger,
                  size: 20.ms,
                ),
              ],
            ],
          ),
          SizedBox(height: 6.ms),
          Padding(
            padding: EdgeInsets.only(left: 34.ms),
            child: Wrap(
              spacing: 8.ms,
              children: [
                CText(
                  question.multi
                      ? 'hosttraining:quiz_select_all'
                      : 'hosttraining:quiz_select_one',
                  size: 12,
                  weight: FontWeight.w600,
                  color: p.muted,
                ),
                // The question's marks, when the admin shows them.
                if (question.marks case final marks?)
                  CText(
                    'hosttraining:quiz_marks',
                    key: ValueKey('training-marks-${question.id}'),
                    variables: {'count': marks},
                    size: 12,
                    weight: FontWeight.w700,
                    color: p.accent,
                  ),
              ],
            ),
          ),
          SizedBox(height: 10.ms),
          for (final o in question.options) ...[
            _OptionTile(
              key: ValueKey('training-option-${o.id}'),
              text: o.text,
              multi: question.multi,
              selected: picked.contains(o.id),
              // After submitting, with answers shown: right ones in green,
              // wrong picks in red.
              state: correct == null
                  ? null
                  : correct.contains(o.id)
                  ? true
                  : (picked.contains(o.id) ? false : null),
              onTap: m == null ? () => onPick(o.id) : null,
            ),
            SizedBox(height: 8.ms),
          ],
          if (m != null && m.explanation.isNotEmpty)
            Container(
              margin: EdgeInsets.only(top: 2.ms),
              padding: EdgeInsets.all(10.ms),
              decoration: BoxDecoration(
                color: p.soft,
                borderRadius: BorderRadius.circular(10.ms),
              ),
              child: CText.raw(
                m.explanation,
                size: 12.5,
                height: 18,
                weight: FontWeight.w500,
                color: p.text,
              ),
            ),
        ],
      ),
    );
  }
}

class _OptionTile extends StatelessWidget {
  const _OptionTile({
    super.key,
    required this.text,
    required this.multi,
    required this.selected,
    required this.state,
    required this.onTap,
  });

  final String text;
  final bool multi;
  final bool selected;

  /// After submitting with answers shown: true = a right answer, false = a
  /// wrong pick, null = neither.
  final bool? state;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final p = HostPalette.of(context);
    final (border, fill) = switch (state) {
      true => (p.success, p.successTint),
      false => (p.danger, p.dangerTint),
      null when selected => (p.accent, p.tint),
      null => (p.fieldBorder, p.field),
    };
    final icon = multi
        ? (selected ? LucideIcons.squareCheck : LucideIcons.square)
        : (selected ? LucideIcons.circleDot : LucideIcons.circle);
    return Pressable(
      onPressed: onTap,
      activeOpacity: 0.85,
      semanticLabel: text,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: EdgeInsets.symmetric(horizontal: 12.ms, vertical: 11.ms),
        decoration: BoxDecoration(
          color: fill,
          borderRadius: BorderRadius.circular(12.ms),
          border: Border.all(color: border, width: selected ? 1.5 : 1),
        ),
        child: Row(
          children: [
            Icon(
              icon,
              size: 18.ms,
              color: selected || state != null ? border : p.muted,
            ),
            SizedBox(width: 10.ms),
            Expanded(
              child: CText.raw(
                text,
                size: 14,
                weight: FontWeight.w600,
                color: p.text,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
