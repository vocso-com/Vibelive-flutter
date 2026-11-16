import 'package:flutter/widgets.dart';

import '../../../api/hosthub/handle_api.dart';
import '../../../api/hosthub/hosthub_queries.dart';
import '../../../../core/utils/log.dart';
import '../../../component/c_toast.dart';
import 'draft_controller.dart';
import 'host_funnel.dart';
import 'host_steps.dart';
import 'validation.dart';

/// Back / Continue for the form steps: validates the current step, waits
/// on the handle check, runs the submit, and moves the page view.
class HostFlowController {
  HostFlowController({
    required this.draft,
    required this.pages,
    required this.submit,
    required this.exit,
    required this.explore,
    required this.rateFloors,
    this.editing = false,
    this.saveAll,
    this.existingHost,
    this.funnel,
    this.skip,
    this.training,
  });

  final HostDraftController draft;
  final PageController pages;

  /// The whole submit: null when the profile went in, else the step to send
  /// the user back to (the one owning the field the server rejected).
  final Future<HostStep?> Function() submit;

  /// Leave the flow (back on the intro / success screen).
  final VoidCallback exit;

  /// "Explore VibeLive" on the success screen.
  final VoidCallback explore;

  /// Pricing floors for the rates check: `(voice, video)`.
  final (double, double) Function() rateFloors;

  /// A host editing one section (opened on its step from the Host Hub).
  final bool editing;

  /// An existing host (approved, live or pending review): the last step
  /// saves every section with [saveAll] (null when saved, else the step to
  /// go back to) and returns to the Host Hub instead of submitting.
  final Future<HostStep?> Function()? saveAll;
  final bool Function()? existingHost;

  /// Analytics: step completions, back, refusals (null in tests).
  final HostFunnel? funnel;

  /// Steps the flow walks past (the Video step while the admin has video
  /// intros off). Null: none.
  final bool Function(HostStep step)? skip;

  /// The admin's onboarding training (docs/host_onboarding.md): shows what is
  /// placed after [from] that is not done yet ([beforeSubmit]: everything not
  /// done). true: carry on; false: the host backed out (stay on [from]).
  /// Null: no training. Never while editing one section. An [existing] host
  /// gets it only when the admin says so, never required, and nothing is
  /// asked before their Save.
  final Future<bool> Function(
    HostStep from, {
    required bool beforeSubmit,
    required bool existing,
  })?
  training;

  /// The step after [step], past any skipped ones.
  HostStep _after(HostStep step) {
    var s = step.next!;
    while (skip?.call(s) == true && s.next != null) {
      s = s.next!;
    }
    return s;
  }

  /// The step before [step], past any skipped ones.
  HostStep _before(HostStep step) {
    var s = step.previous!;
    while (skip?.call(s) == true && s.previous != null) {
      s = s.previous!;
    }
    return s;
  }

  bool get savesInstead => saveAll != null && (existingHost?.call() ?? false);

  /// Back returns to wherever the flow was opened from instead of walking
  /// the steps: editing a section, or an existing host (applied or approved)
  /// going through it again. Only a first application steps back.
  bool get _backLeaves => editing || (existingHost?.call() ?? false);

  /// Continue shows a spinner and ignores taps while true.
  final busy = ValueNotifier(false);

  static const _duration = Duration(milliseconds: 300);

  /// Set by a preview "Edit" link: Continue / Back on the edited step go
  /// straight back to the preview.
  HostStep? returnTo;

  Future<void> goTo(HostStep step) async {
    FocusManager.instance.primaryFocus?.unfocus();
    final from = draft.step.value;
    draft.step.value = step;
    draft.flush();
    if (step == HostStep.intro || !pages.hasClients) return;
    final lo = step.index < from.index ? step.index : from.index;
    final hi = step.index < from.index ? from.index : step.index;
    final between = [for (var i = lo + 1; i < hi; i++) HostStep.values[i]];
    // Next / Back past a skipped step still slide; real jumps (preview
    // edits) don't walk through the steps in between.
    if (between.isNotEmpty && !between.every((s) => skip?.call(s) == true)) {
      pages.jumpToPage(step.page);
      return;
    }
    await pages.animateToPage(
      step.page,
      duration: _duration,
      curve: Curves.easeOutCubic,
    );
  }

  /// Preview "Edit": open [step], come back to the preview after it.
  Future<void> editFrom(HostStep step) {
    funnel?.previewEdit(step);
    returnTo = draft.step.value;
    return goTo(step);
  }

  /// Where Continue / Back lead after an edit, consuming it.
  HostStep? _takeReturn() {
    final r = returnTo;
    returnTo = null;
    return r;
  }

  void back() {
    if (busy.value) return;
    final step = draft.step.value;
    if (step == HostStep.intro ||
        step == HostStep.submitted ||
        (_backLeaves && returnTo == null)) {
      exit();
      return;
    }
    funnel?.back(step);
    goTo(_takeReturn() ?? _before(step));
  }

  Future<void> next() async {
    if (busy.value) return;
    final step = draft.step.value;
    if (step == HostStep.submitted) {
      funnel?.completed(step);
      explore();
      return;
    }
    final (voice, video) = rateFloors();
    final issue = HostValidation.check(
      step,
      draft,
      minVoiceRate: voice,
      minVideoRate: video,
    );
    if (issue != null) {
      draft.notice.value = issue;
      funnel?.invalid(step, issue.key);
      return;
    }
    if (step == HostStep.basic && !await _handleIsFree()) return;
    if (!await _trained(step)) return;
    if (step == HostStep.guidelines) {
      final saving = savesInstead;
      busy.value = true;
      final failedAt = await (saving ? saveAll!() : submit()).whenComplete(
        () => busy.value = false,
      );
      if (failedAt != null) {
        if (failedAt != step) await goTo(failedAt);
        return;
      }
      if (saving) {
        // Saved: no approval request, no "Submitted" step.
        funnel?.completed(step);
        funnel?.saved('all');
        await draft.clear();
        exit();
        return;
      }
    }
    funnel?.completed(step);
    await goTo(_takeReturn() ?? _after(step));
  }

  bool get _trains => training != null && !editing;

  /// The training after [step] (before Submit: all of it still to do). Never
  /// in the way: anything going wrong here lets the host carry on.
  Future<bool> _trained(HostStep step) async {
    if (!_trains) return true;
    final existing = existingHost?.call() ?? false;
    busy.value = true;
    try {
      return await training!(
        step,
        beforeSubmit: step == HostStep.guidelines && !existing,
        existing: existing,
      );
    } catch (e) {
      Log.w('hostflow', 'training skipped: $e');
      return true;
    } finally {
      busy.value = false;
    }
  }

  Future<bool> _handleIsFree() async {
    busy.value = true;
    try {
      final free = await ensureHostHandleCheck(
        draft.handle.text,
        ownExpertId: draft.expertId,
      );
      if (!free) {
        draft.notice.value = await handleTakenNotice(draft.handle.text);
        funnel?.handleTaken();
      }
      return free;
    } catch (e) {
      CToast.error(e);
      return false;
    } finally {
      busy.value = false;
    }
  }

  void dispose() => busy.dispose();
}

/// "This handle is already taken", with a free one close to it when the
/// server offers one ("Try @aanya_talks").
Future<HostIssue> handleTakenNotice(String handle) async {
  String? suggestion;
  try {
    suggestion = (await HostHandleApi.check(handle)).suggestion;
  } catch (_) {
    // The plain message is enough.
  }
  return suggestion == null
      ? (key: 'hostflow:errors.handle_taken', variables: null)
      : (
          key: 'hostflow:errors.handle_taken_try',
          variables: {'handle': suggestion},
        );
}
