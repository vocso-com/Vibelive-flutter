import '../../../../core/analytics/analytics.dart';
import '../../../../core/analytics/events/host_events.dart';
import '../../../../core/network/api_exception.dart';
import '../../../../core/network/strapi.dart';
import '../../../../core/session/session_store.dart';
import '../../../api/authscreen/interests_queries.dart';
import '../../../api/client/client_keys.dart';
import '../../../api/client/client_models.dart';
import '../../../api/hosthub/expertise_models.dart';
import '../../../api/hosthub/hosthub_queries.dart';
import '../../../api/hosthub/onboarding_models.dart';
import '../../../api/hosthub/profile_models.dart';
import '../../../api/hosthub/profile_patch.dart';
import '../../../component/c_alert.dart';
import '../../../component/c_toast.dart';
import 'draft_controller.dart';
import 'host_funnel.dart';
import 'host_steps.dart';
import 'submit_plan.dart';
import 'topic_catalog.dart';
import 'validation.dart';

/// Steps an existing host can save on their own from the Host Hub.
const hostSavableSteps = {
  HostStep.basic,
  HostStep.photos,
  HostStep.voice,
  HostStep.tagline,
  HostStep.bio,
  HostStep.interests,
  HostStep.rates,
  HostStep.availability,
};

/// Saves of an existing host (no approval request is ever filed):
/// [section] is a step's "Save changes"; [all] is the last step's "Save",
/// every section at once. [all] resolves to null when saved, else the step
/// to go back to (its issue shown there).
typedef HostSaver = ({
  Future<bool> Function(HostStep step) section,
  Future<HostStep?> Function() all,
});

/// The update calls the Host Hub always used (profile edit with moderation
/// and `language {set}`, expertise, rates, schedule / vacation).
HostSaver useHostSectionSave(
  HostDraftController draft, {
  required UserWithExpert? me,
  required (double, double) Function() rateFloors,
}) {
  final profile = useSaveHostProfileEdit();
  final expertise = useSaveMyExpertise();
  final update = useUpdateHostProfile(
    alsoInvalidate: const [ClientKeys.profiles],
  );
  const profileSteps = [
    HostStep.basic,
    HostStep.photos,
    HostStep.voice,
    HostStep.tagline,
    HostStep.bio,
  ];

  /// The first of [steps] with an issue (shown as the notice), or null.
  HostStep? invalid(Iterable<HostStep> steps, {required String mode}) {
    final (voice, video) = rateFloors();
    for (final s in steps) {
      final issue = HostValidation.check(
        s,
        draft,
        minVoiceRate: voice,
        minVideoRate: video,
      );
      if (issue != null) {
        draft.notice.value = issue;
        HostEvents.validationFailed(s.name, issue: issue.key, mode: mode);
        return s;
      }
    }
    return null;
  }

  Future<void> saveTopics() async {
    // Independent reads: in parallel (errors stay ApiException).
    final mine = ensureMyExpertise()..ignore();
    final form = await ensureInterestForm();
    final saved = (await mine).selections;
    final all = [for (final q in form.questions) q.toJson()];
    final question = HostTopicCatalog.question(form);
    final selections = ExpertiseQuestions.draft(all, saved);
    if (question != null) {
      selections[question.key] = [for (final t in draft.topics.value) t.value];
    }
    await expertise.mutateAsync((selections: selections, source: 'settings'));
  }

  JsonMap ratesPatch() {
    final rates = HostValidation.ratesOf(draft);
    return HostProfilePatch.rates(
      voice: rates.voiceCallRate,
      video: rates.videoCallRate,
    ).data;
  }

  // RN ScheduleScreen payload: `schedule` only in the weekly mode.
  JsonMap schedulePatch() {
    final mode = draft.mode;
    return HostProfilePatch.schedule(
      vacation: mode == HostAvailability.vacation,
      callAnyTime: mode == HostAvailability.available,
      week: HostSubmitPlan.week(draft),
    ).data;
  }

  /// Basic, photos, tagline and bio in one save; false when the handle is
  /// taken (the notice says so).
  Future<bool> saveProfile(String expertId, String user) async {
    final free = await ensureHostHandleCheck(
      draft.handle.text,
      ownExpertId: expertId,
    );
    if (!free) {
      draft.notice.value = (
        key: 'hostflow:errors.handle_taken',
        variables: null,
      );
      HostEvents.handleTaken(mode: 'edit');
      return false;
    }
    await profile.mutateAsync(
      HostProfileEditInput(
        userDocumentId: user,
        expertId: expertId,
        handler: draft.handle.text.trim(),
        tagline: draft.tagline.text.trim(),
        gender: draft.gender.value,
        description: draft.bio.text.trim(),
        languages: draft.languages.value,
        photoMediaIds: [
          for (final p in draft.photos.value)
            if (p.mediaId != null) p.mediaId!,
        ],
        audioIntro: draft.voiceIntro.value?.upload,
        videoIntro: draft.videoIntro.value?.upload,
        userPatch: me == null ? const {} : HostSubmitPlan.userPatch(draft, me),
      ),
    );
    return true;
  }

  ({String expertId, String user})? ids() {
    final expertId = draft.expertId;
    final user = SessionStore.instance.value.userDocumentId;
    return expertId == null || user == null
        ? null
        : (expertId: expertId, user: user);
  }

  /// RN's settings events for the sections that had them.
  void logSaved(HostStep step, String expertId) {
    switch (step) {
      case HostStep.interests:
        final topics = draft.topics.value;
        HostEvents.specializationSelected(
          expertId: expertId,
          categoryIds: [for (final t in topics) t.value],
          categoryNames: [for (final t in topics) t.label],
          source: 'settings',
        );
      case HostStep.rates:
        final rates = HostValidation.ratesOf(draft);
        HostEvents.callRatesUpdated(
          expertId: expertId,
          audioRate: rates.voiceCallRate,
          videoRate: rates.videoCallRate,
        );
      case HostStep.availability:
        HostEvents.scheduleUpdated(
          expertId: expertId,
          mode: hostStatusName(draft.mode),
        );
      case _:
        break;
    }
  }

  Future<bool> section(HostStep step) async {
    final id = ids();
    if (id == null) return false;
    // One profile save sends all the profile steps: check them all, except
    // the voice intro, which only its own step insists on (a live host
    // without one can still fix their bio).
    final checks = profileSteps.contains(step)
        ? [
            for (final s in profileSteps)
              if (s != HostStep.voice || step == HostStep.voice) s,
          ]
        : [step];
    if (invalid(checks, mode: 'edit') != null) {
      return false;
    }
    try {
      switch (step) {
        case HostStep.interests:
          await saveTopics();
        case HostStep.rates:
          await update.mutateAsync((
            expertId: id.expertId,
            patch: HostProfilePatch(ratesPatch()),
          ));
        case HostStep.availability:
          await update.mutateAsync((
            expertId: id.expertId,
            patch: HostProfilePatch(schedulePatch()),
          ));
        case _:
          if (!await saveProfile(id.expertId, id.user)) return false;
      }
      logSaved(step, id.expertId);
      CToast.show('hostflow:edit.saved', variant: CToastVariant.success);
      return true;
    } on ApiException catch (e) {
      HostEvents.sectionSaveFailed(step.name, error: Analytics.errorCode(e));
      await CAlert.error(e);
      return false;
    }
  }

  Future<HostStep?> all() async {
    final id = ids();
    if (id == null) return HostStep.guidelines;
    final bad = invalid([
      for (final s in HostStep.pages)
        if (hostSavableSteps.contains(s)) s,
    ], mode: 'existing_host');
    if (bad != null) return bad;
    try {
      if (!await saveProfile(id.expertId, id.user)) return HostStep.basic;
      await saveTopics();
      await update.mutateAsync((
        expertId: id.expertId,
        patch: HostProfilePatch({...ratesPatch(), ...schedulePatch()}),
      ));
      for (final s in const [
        HostStep.interests,
        HostStep.rates,
        HostStep.availability,
      ]) {
        logSaved(s, id.expertId);
      }
      CToast.show('hostflow:edit.saved', variant: CToastVariant.success);
      return null;
    } on ApiException catch (e) {
      HostEvents.sectionSaveFailed('all', error: Analytics.errorCode(e));
      await CAlert.error(e);
      return HostStep.guidelines;
    }
  }

  return (section: section, all: all);
}
