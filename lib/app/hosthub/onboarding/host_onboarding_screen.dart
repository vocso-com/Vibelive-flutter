import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../core/network/api_exception.dart';
import '../../../core/query/query_client.dart';
import '../../../core/router/app_router.dart';
import '../../../core/session/session_store.dart';
import '../../../core/storage/app_prefs.dart';
import '../../../core/utils/log.dart';
import '../../api/paymentscreen/runtime_config_queries.dart';
import '../../api/authscreen/interests_queries.dart';
import '../../api/client/client_models.dart';
import '../../api/client/client_queries.dart';
import '../../api/hosthub/approval_models.dart';
import '../../api/hosthub/hosthub_keys.dart';
import '../../api/hosthub/hosthub_queries.dart';
import '../../api/hosthub/profile_models.dart';
import '../../api/paymentscreen/billing_models.dart';
import '../../api/paymentscreen/payment_queries.dart';
import '../../component/c_alert.dart';
import '../../component/c_state_view.dart';
import '../../component/keyboard_inset.dart';
import '../../component/status_bar_style.dart';
import '../common/host_page.dart';
import '../common/host_review.dart';
import 'helper/draft_controller.dart';
import 'helper/flow_controller.dart';
import 'helper/host_funnel.dart';
import 'helper/host_palette.dart';
import 'helper/host_steps.dart';
import 'helper/intro_image.dart';
import 'helper/prefill.dart';
import 'helper/section_save.dart';
import 'helper/submit_errors.dart';
import 'helper/submit_plan.dart';
import 'helper/topic_catalog.dart';
import 'steps/availability_step.dart';
import 'steps/basic_profile_step.dart';
import 'steps/bio_step.dart';
import 'steps/guidelines_step.dart';
import 'steps/interests_step.dart';
import 'steps/intro_step.dart';
import 'steps/photos_step.dart';
import 'steps/preview_step.dart';
import 'steps/rates_step.dart';
import 'steps/submitted_step.dart';
import 'steps/tagline_step.dart';
import 'steps/video_step.dart';
import 'steps/voice_step.dart';
import 'widgets/continue_bar.dart';
import 'widgets/progress_header.dart';

/// "Become a Host": intro, eight form steps, success. The draft is saved
/// per account as the user goes, so the flow resumes where it was left.
/// Nothing is created on the backend before "Submit for review": a host
/// profile turns the account into a host everywhere in the app.
class HostOnboardingScreen extends HookWidget {
  const HostOnboardingScreen({super.key, this.editStep, this.startStep});

  /// An existing host from the Host Hub: open on this step, prefilled from
  /// the saved profile (nothing saved to prefs), with "Save changes" for
  /// that section next to Continue.
  final HostStep? editStep;

  /// The whole flow, opened on this step instead of where the draft was
  /// left (a link: a push asking for the voice intro, say).
  final HostStep? startStep;

  @override
  Widget build(BuildContext context) {
    final session = useMemoized(() => SessionStore.instance.value);
    final userKey = session.userDocumentId ?? '${session.userId ?? ''}';
    // Analytics: a draft saved before this open means "resume".
    final hadDraft = useMemoized(
      () =>
          editStep == null &&
          AppPrefs.getString(HostDraftController.storageKey(userKey)) != null,
    );
    final draft = useMemoized(() {
      if (editStep case final step?) {
        return HostDraftController('edit', persist: false)
          ..step.value = step
          ..started = true;
      }
      final saved = HostDraftController.load(userKey);
      if (startStep case final step?) {
        saved
          ..step.value = step
          ..started = true;
      }
      return saved;
    });
    useEffect(() => draft.dispose, [draft]);
    final funnel = useMemoized(() {
      final route = _routeOf(context);
      return HostFunnel(
        draft: draft,
        mode: editStep != null
            ? 'edit'
            : session.isExpert
            ? 'existing_host'
            : (hadDraft ? 'resume' : 'new'),
        source: _sourceOf(route, editStep: editStep, startStep: startStep),
        routePath: route?.path ?? AppRoutes.hostOnboarding,
      );
    }, [draft]);
    useEffect(() {
      funnel.start();
      return funnel.dispose;
    }, [funnel]);
    // Entry points precache it already; this covers deep links.
    useEffect(() {
      // After the first frame: precaching reads inherited widgets.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (context.mounted) HostIntroImage.precache(context).ignore();
      });
      return null;
    }, const []);
    final (me, ready, host, loadError, retryLoad) = _usePrefill(
      context,
      draft,
      session,
    );
    // Someone who already has a host profile: the edit screen, or a host in
    // the flow. Their profile must be loaded before anything is shown or
    // saved, and they never create one.
    final ownsProfile = editStep != null || session.isExpert;
    // What review asked to change: marked on the steps it is about.
    final messages = useHostModerationMessages(context, enabled: host != null);
    final review = useMemoized(
      () => HostReview.from(host, messages.data ?? const []),
      [host, messages.data],
    );
    // An approved / live host, or one whose review is pending, saves on the
    // last step instead of filing (another) approval request.
    final latest = useLatestApproval(
      context,
      expertId: host?.key,
      enabled: host != null && !host.isLiveOrApproved,
    );
    final existingHost =
        host != null &&
        (host.isLiveOrApproved ||
            switch (ApprovalRecord.effective(host, latest.data)) {
              ApprovalStatus.pending || ApprovalStatus.approved => true,
              _ => false,
            });

    final submit = useSubmitHostOnboarding();
    final pricing = usePricingConfig(context).data ?? PricingConfig.empty;
    // Only intro <-> flow rebuilds this widget; steps rebuild themselves.
    final onIntro = useListenableSelector(
      draft.step,
      () => draft.step.value == HostStep.intro,
    );

    void exit() {
      if (context.canPop()) {
        context.pop();
      } else {
        context.go('${AppRoutes.home}?tab=me');
      }
    }

    // The server already has a host profile for this account (409
    // HOST_PROFILE_EXISTS: this screen did not know it). The draft was for a
    // profile that exists, so it goes; the session gets the real one back,
    // and the Host Hub opens on it.
    Future<void> openExistingProfile(String user) async {
      await draft.clear();
      try {
        await ensureMyProfile(user, staleDuration: StaleTime.none);
      } on ApiException catch (e) {
        Log.w('hostflow', 'profile reload after 409 failed: $e');
      }
      queryCache.invalidateAll([
        HostHubKeys.profileAll,
        HostHubKeys.imagesAll,
        HostHubKeys.approvalAll,
      ]);
      if (!context.mounted) return;
      await CAlert.show(
        context: context,
        title: 'hostflow:errors.profile_exists_title',
        message: 'hostflow:errors.profile_exists',
      );
      // After this frame: the flow resets its busy state when submit returns.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (context.mounted) context.go('${AppRoutes.home}?tab=me');
      });
    }

    Future<HostStep?> runSubmit() async {
      final user = session.userDocumentId;
      if (user == null) return HostStep.guidelines;
      // Never a second profile: with no id here, theirs was not loaded (the
      // screen waits for it), and a submit would create one that takes the
      // account off the real one.
      if (ownsProfile && draft.expertId == null) {
        Log.w('hostflow', 'submit without the host profile; not creating');
        await CAlert.show(
          context: context,
          title: 'hostflow:errors.profile_load_title',
          message: 'hostflow:errors.profile_load',
          variant: CAlertVariant.error,
        );
        retryLoad();
        return HostStep.guidelines;
      }
      try {
        final form = await ensureInterestForm();
        final input = HostSubmitPlan.build(
          draft,
          userDocumentId: user,
          form: form,
          me: me ?? UserWithExpert(user: session.user ?? const {}),
          onExpertId: (id) {
            draft.expertId = id;
            draft.flush();
          },
        );
        await submit.mutateAsync(input);
        funnel.submitted(user);
        await draft.clear();
        return null;
      } on ApiException catch (e) {
        if (HostSubmitErrors.isProfileExists(e)) {
          funnel.submitFailed(e, HostStep.guidelines);
          await openExistingProfile(user);
          return HostStep.guidelines;
        }
        // A field the server rejected: back to its step with the error
        // shown there (e.g. a handle another profile already owns).
        final target = HostSubmitErrors.stepFor(e);
        funnel.submitFailed(e, target ?? HostStep.guidelines);
        if (target == null) {
          await CAlert.error(e);
          return HostStep.guidelines;
        }
        draft.notice.value = HostSubmitErrors.noticeFor(e, target);
        return target;
      }
    }

    final save = useHostSectionSave(
      draft,
      me: me,
      rateFloors: () => (pricing.minimumVoiceRate, pricing.minimumVideoRate),
    );

    final p = HostPalette.of(context);
    if (ownsProfile && !ready) {
      // Their profile could not be read: say so. Never a blank form, which
      // would save over it or create a second one.
      if (loadError != null) {
        return HostPage(
          title: 'hostflow:hub.pro_details',
          body: CStateView(
            key: const ValueKey('host-profile-load-error'),
            icon: LucideIcons.cloudOff,
            title: 'hostflow:errors.profile_load_title',
            message: 'hostflow:errors.profile_load',
            actionLabel: 'actions.retry',
            onAction: retryLoad,
          ),
        );
      }
      return ThemedStatusBar(
        child: Scaffold(
          backgroundColor: p.bg,
          body: const SafeArea(child: HostPageSkeleton()),
        ),
      );
    }
    return HostReviewScope(
      review: review,
      child: ThemedStatusBar(
        darkBackground: onIntro ? true : null,
        child: Scaffold(
          backgroundColor: onIntro ? IntroStep.deep : p.bg,
          resizeToAvoidBottomInset: false,
          body: AnimatedSwitcher(
            duration: const Duration(milliseconds: 260),
            child: onIntro
                ? IntroStep(
                    key: const ValueKey('intro'),
                    resuming: draft.started,
                    onStart: () {
                      funnel.completed(HostStep.intro);
                      draft.started = true;
                      draft.step.value = HostStep.basic;
                    },
                  )
                : _Flow(
                    key: const ValueKey('flow'),
                    draft: draft,
                    submit: runSubmit,
                    save: editStep == null ? null : save.section,
                    saveAll: save.all,
                    existingHost: existingHost,
                    funnel: funnel,
                    exit: exit,
                    explore: () => context.go('${AppRoutes.home}?tab=discover'),
                    rateFloors: () =>
                        (pricing.minimumVoiceRate, pricing.minimumVideoRate),
                  ),
          ),
        ),
      ),
    );
  }
}

/// Prefill from Personal Info (and, for a host resubmitting, the saved host
/// profile and topics) once the reads are in. Returns "my profile",
/// whether the prefill (topics included, for a host) is done, the saved
/// host profile (null for a new host), and for a host whose reads failed the
/// error and a retry.
///
/// A host's failed read is NOT "no profile". It used to count as done: on
/// 29 Oct a 401 here seeded a new-host draft (no profile id, a handle from
/// the name), and Submit created a second profile that took the account off
/// the approved one. Their topics the same: seeded empty, a save would wipe
/// them.
(UserWithExpert?, bool, HostProfile?, ApiException?, VoidCallback)
_usePrefill(
  BuildContext context,
  HostDraftController draft,
  SessionState session,
) {
  final me = useMyProfile(context);
  final isHost = session.isExpert;
  final host = useHostProfile(context, enabled: isHost);
  final expertise = useMyExpertise(context, enabled: isHost);
  final form = useInterestForm(context, enabled: isHost);
  final answers = useMyInterests(context, enabled: !isHost);

  final hostReady = !isHost || host.data != null;
  final meReady = me.data != null || me.isError;
  useEffect(() {
    if (!meReady || !hostReady || draft.seeded) return null;
    HostPrefill.apply(
      draft,
      me.data ??
          UserWithExpert(
            user: session.user ?? const {},
            expert: session.expert,
          ),
      host: host.data,
      answers: answers.data?.selections ?? const {},
    );
    return null;
  }, [meReady, hostReady]);

  // A draft seeded without the host's profile (older builds did that when the
  // read failed) has no profile id and is never seeded again. It is this
  // host's own, so Submit updates their profile instead of being refused.
  final hostKey = host.data?.key;
  useEffect(() {
    if (hostKey != null &&
        hostKey.isNotEmpty &&
        draft.seeded &&
        draft.expertId == null) {
      draft.expertId = hostKey;
      draft.flush();
    }
    return null;
  }, [hostKey]);

  // The client's "How do you identify?" answer, if it arrives later.
  useEffect(() {
    final sel = answers.data?.selections;
    if (sel != null && draft.gender.value == null) {
      draft.gender.value = HostPrefill.genderFromAnswers(sel);
    }
    return null;
  }, [answers.data]);

  useEffect(() {
    final saved = expertise.data?.selections;
    if (saved == null || form.data == null || draft.topicsSeeded) return null;
    if (draft.topics.value.isEmpty) {
      draft.topics.value = HostTopicCatalog.selected(
        HostTopicCatalog.question(form.data),
        saved,
      );
    }
    draft.topicsSeeded = true;
    draft.flush();
    return null;
  }, [expertise.data, form.data]);
  final topicsReady = !isHost || draft.topicsSeeded;
  final ApiException? loadError = !isHost
      ? null
      : (host.data == null ? host.error : null) ??
            (draft.topicsSeeded ? null : expertise.error ?? form.error);
  void retry() {
    if (host.isError) host.refetch();
    if (expertise.isError) expertise.refetch();
    if (form.isError) form.refetch();
  }

  return (me.data, draft.seeded && topicsReady, host.data, loadError, retry);
}

class _Flow extends HookWidget {
  const _Flow({
    super.key,
    required this.draft,
    required this.submit,
    required this.exit,
    required this.explore,
    required this.rateFloors,
    required this.saveAll,
    required this.funnel,
    this.save,
    this.existingHost = false,
  });

  final HostDraftController draft;
  final Future<HostStep?> Function() submit;

  /// Edit mode: saves the current step's section; null in the flow.
  final Future<bool> Function(HostStep step)? save;

  /// The last step's "Save" for an [existingHost] (every section).
  final Future<HostStep?> Function() saveAll;
  final bool existingHost;
  final HostFunnel funnel;
  final VoidCallback exit;
  final VoidCallback explore;
  final (double, double) Function() rateFloors;

  @override
  Widget build(BuildContext context) {
    // The controller lives across rebuilds; these read this build's values
    // (the profile and the approval status arrive after the first frame).
    final latest = useRef(this)..value = this;
    final pages = usePageController(
      initialPage: draft.step.value.page.clamp(0, HostStep.pages.length - 1),
    );
    final flow = useMemoized(
      () => HostFlowController(
        draft: draft,
        pages: pages,
        submit: () => latest.value.submit(),
        exit: exit,
        explore: explore,
        rateFloors: rateFloors,
        editing: save != null,
        saveAll: () => latest.value.saveAll(),
        existingHost: () => latest.value.existingHost,
        funnel: funnel,
        // No video step while the admin has video intros off: a clip the
        // server would drop must not be asked for.
        skip: (s) =>
            s == HostStep.video &&
            !currentRuntimeConfig().hostMedia.canRecordIntro,
      ),
      [pages],
    );

    Future<void> saveSection() async {
      final step = draft.step.value;
      if (flow.busy.value || save == null) return;
      flow.busy.value = true;
      final ok = await save!(step).whenComplete(() => flow.busy.value = false);
      if (ok) {
        funnel.saved(step.name);
        exit();
      }
    }

    useEffect(() => flow.dispose, [flow]);

    final steps = <Widget>[
      for (final s in HostStep.pages)
        KeyedSubtree(key: ValueKey(s), child: _page(s, flow)),
    ];
    // Back gesture / Android back = the chevron (one step back).
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) flow.back();
      },
      child: KeyboardInset(
        child: Column(
          children: [
            SafeArea(
              bottom: false,
              child: HostProgressHeader(
                step: draft.step,
                onBack: flow.back,
                skip: flow.skip,
              ),
            ),
            Expanded(
              child: PageView(
                controller: pages,
                physics: const NeverScrollableScrollPhysics(),
                children: steps,
              ),
            ),
            HostContinueBar(
              step: draft.step,
              busy: flow.busy,
              notice: draft.notice,
              agreed: draft.agreed,
              onPressed: flow.next,
              onSave: save == null ? null : saveSection,
              savesInstead: existingHost,
            ),
          ],
        ),
      ),
    );
  }

  Widget _page(HostStep s, HostFlowController flow) => switch (s) {
    HostStep.basic => BasicProfileStep(draft: draft),
    HostStep.interests => InterestsStep(draft: draft),
    HostStep.photos => PhotosStep(draft: draft),
    HostStep.voice => VoiceStep(draft: draft),
    HostStep.video => VideoStep(draft: draft),
    HostStep.tagline => TaglineStep(draft: draft),
    HostStep.bio => BioStep(draft: draft),
    HostStep.rates => RatesStep(draft: draft),
    HostStep.availability => AvailabilityStep(draft: draft),
    HostStep.preview => PreviewStep(draft: draft, onEdit: flow.editFrom),
    HostStep.guidelines => GuidelinesStep(draft: draft),
    _ => const SubmittedStep(),
  };
}

/// This screen's route, or null outside the app router (tests).
Uri? _routeOf(BuildContext context) {
  try {
    return GoRouterState.of(context).uri;
  } catch (_) {
    return null;
  }
}

/// Analytics `source` of an open: `?source=` when an entry point passed
/// one, else from how it was opened.
String _sourceOf(Uri? route, {HostStep? editStep, HostStep? startStep}) {
  final given = route?.queryParameters['source'];
  if (given != null && given.isNotEmpty) return given;
  if (editStep != null) return 'host_hub';
  if (route != null && route.path != AppRoutes.hostOnboarding) {
    return 'host_hub';
  }
  return startStep != null ? 'deeplink' : 'become_host';
}
