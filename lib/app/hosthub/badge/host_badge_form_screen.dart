import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../core/analytics/analytics.dart';
import '../../../core/analytics/events/host_events.dart';
import '../../../core/analytics/screen_tracker.dart';
import '../../../core/i18n/i18n.dart';
import '../../../core/network/api_exception.dart';
import '../../../core/router/app_router.dart';
import '../../../core/session/session_store.dart';
import '../../../core/utils/scale.dart';
import '../../api/client/client_queries.dart';
import '../../api/hosthub/eligibility.dart';
import '../../api/hosthub/hosthub_queries.dart';
import '../../api/hosthub/verification_models.dart';
import '../../component/c_alert.dart';
import '../../component/c_state_view.dart';
import '../../component/c_text.dart';
import '../../component/pressable.dart';
import '../common/host_page.dart';
import '../onboarding/helper/host_palette.dart';
import '../onboarding/helper/photo_picker.dart';
import '../onboarding/widgets/continue_bar.dart';
import '../onboarding/widgets/host_field.dart';
import '../onboarding/widgets/select_field.dart';
import '../onboarding/widgets/step_body.dart';
import 'helper/badge_form.dart';
import 'host_badge_screen.dart';
import 'widgets/badge_fields.dart';

/// Verification form (RN VerificationFormScreen): identity (document type,
/// number, both sides, optional LinkedIn), then for influencers the social
/// profile. Each step saves as a draft; the last one submits for review.
class HostBadgeFormScreen extends HookWidget {
  const HostBadgeFormScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final session = useValueListenable(SessionStore.instance);
    final allowed = HostEligibility.canApplyForBadge(session.expert);
    final record = useCurrentVerification(
      context,
      draft: true,
      enabled: allowed,
    );
    final referral = useReferralCode(context);
    final update = useUpdateVerification();
    final form = useMemoized(BadgeFormController.new);
    useEffect(() => form.dispose, [form]);
    final saving = useState(false);
    // Analytics: the form step last shown.
    final viewedStep = useRef<String?>(null);
    useEffect(
      () =>
          () => ScreenTracker.clearSubScreen(AppRoutes.verificationBadgeForm),
      const [],
    );
    final issue = useState<({String key, Map<String, dynamic>? vars})?>(null);
    useListenable(Listenable.merge([form.step, form.influencer]));
    final p = HostPalette.of(context);

    final rec = record.data;
    if (rec != null) form.seed(rec);
    useEffect(() {
      // Unpaid → the fee first; already submitted → the status.
      final step = rec?.nextStep;
      if (step == VerificationStep.fee) {
        context.pushReplacement(AppRoutes.verificationBadgeFee);
      } else if (step == VerificationStep.review ||
          step == VerificationStep.success) {
        context.pushReplacement(AppRoutes.verificationBadge);
      }
      return null;
    }, [rec?.nextStep]);

    if (!allowed) {
      return const HostBadgeLocked(title: 'hostflow:badge.form_title');
    }
    if (rec == null) {
      return HostPage(
        title: 'hostflow:badge.form_title',
        body: record.isError
            ? CStateView.error(context, record.error!, onRetry: record.refetch)
            : const HostPageSkeleton(),
      );
    }

    final steps = form.steps;
    final index = form.step.value.clamp(0, steps.length - 1);
    final last = index == steps.length - 1;
    // Each form step is the page's analytics sub-screen.
    if (viewedStep.value != steps[index]) {
      viewedStep.value = steps[index];
      final name = 'verification_badge_form_${steps[index]}';
      WidgetsBinding.instance.addPostFrameCallback(
        (_) =>
            ScreenTracker.setSubScreen(AppRoutes.verificationBadgeForm, name),
      );
    }

    Future<void> pickDoc(ValueNotifier<BadgeDoc?> target) async {
      final side = identical(target, form.front) ? 'front' : 'back';
      final path = await HostPhotoPicker.instance.pick(HostPhotoOrigin.gallery);
      if (path == null) return;
      target.value = BadgeDoc(localPath: path);
      try {
        final media = await HostPhotoPicker.instance.upload(path);
        target.value = BadgeDoc(
          mediaId: media['id'] ?? media['documentId'],
          localPath: path,
        );
        HostEvents.badgeDocUploaded(side: side);
      } catch (e) {
        HostEvents.badgeDocUploadFailed(
          side: side,
          error: Analytics.errorCode(e),
        );
        target.value = BadgeDoc(localPath: path, failed: true);
        await CAlert.error(e);
      }
    }

    Future<bool> saveStep(String id) async {
      final problem = form.validate(id);
      issue.value = problem;
      if (problem != null) {
        HostEvents.badgeFormValidationFailed(id, issue: problem.key);
        return false;
      }
      await update.mutateAsync(
        id == 'identity'
            ? VerificationUpdate.identity(
                rec.key,
                docType: form.docType.value!,
                docNumber: form.docNumber.text,
                frontMediaId: form.front.value?.mediaId,
                backMediaId: form.back.value?.mediaId,
                linkedInUrl: form.linkedIn.text,
              )
            : VerificationUpdate.social(
                rec.key,
                platform: form.platform.value,
                url: form.socialUrl.text,
              ),
      );
      return true;
    }

    Future<void> next() async {
      final platformName = context.t(
        'hostflow:badge.social.${form.platform.value.name}',
      );
      saving.value = true;
      try {
        if (!await saveStep(steps[index])) return;
        HostEvents.badgeFormStepSaved(steps[index]);
        if (!last) {
          form.step.value = index + 1;
          return;
        }
        // A resumed form can open on the last step: re-check every step.
        for (final (i, id) in steps.indexed) {
          final problem = form.validate(id);
          if (problem != null) {
            HostEvents.badgeFormValidationFailed(id, issue: problem.key);
            issue.value = problem;
            form.step.value = i;
            return;
          }
        }
        if (form.influencer.value) {
          final ok = await CAlert.confirm(
            title: 'hostflow:badge.influencer_title',
            message: 'hostflow:badge.influencer_body',
            variables: {'code': referral.data ?? '', 'platform': platformName},
            confirmLabel: 'hostflow:badge.influencer_yes',
            cancelLabel: 'hostflow:badge.influencer_no',
            variant: CAlertVariant.info,
          );
          if (!ok) {
            HostEvents.badgeInfluencerDeclined();
            return;
          }
        }
        await update.mutateAsync(
          VerificationUpdate.submit(
            rec.key,
            platform: form.influencer.value ? form.platform.value : null,
            url: form.influencer.value ? form.socialUrl.text : '',
          ),
        );
        HostEvents.badgeFormSubmitted(
          userId: session.userDocumentId,
          influencer: form.influencer.value,
          platform: form.influencer.value ? form.platform.value.name : null,
        );
        await CAlert.show(
          title: 'hostflow:badge.submitted_title',
          message: 'hostflow:badge.submitted_body',
          variant: CAlertVariant.success,
        );
        if (context.mounted) {
          context.pushReplacement(AppRoutes.verificationBadge);
        }
      } on ApiException catch (e) {
        HostEvents.badgeFormSubmitFailed(error: Analytics.errorCode(e));
        await CAlert.error(e, title: 'hostflow:badge.form_title');
      } finally {
        if (context.mounted) saving.value = false;
      }
    }

    final identity = <Widget>[
      const HostLabel('hostflow:badge.doc_type', top: 0),
      ValueListenableBuilder<String?>(
        valueListenable: form.docType,
        builder: (_, type, _) => HostSelectField(
          key: const ValueKey('badge-doc-type'),
          value: type == null
              ? null
              : context.t(BadgeFormController.idTypeKey(type)),
          hint: 'hostflow:badge.doc_type_hint',
          onTap: () async {
            final picked = await showDocTypePicker(context, type);
            if (picked != null) {
              form.docType.value = picked;
              HostEvents.badgeDocTypeSelected(picked);
            }
          },
        ),
      ),
      const HostLabel('hostflow:badge.doc_number'),
      HostField(
        controller: form.docNumber,
        hint: 'hostflow:badge.doc_number_hint',
        capitalization: TextCapitalization.characters,
        fieldKey: const ValueKey('badge-doc-number'),
      ),
      const HostLabel('hostflow:badge.doc_photos'),
      Row(
        children: [
          Expanded(
            child: BadgeDocTile(
              key: const ValueKey('badge-front'),
              label: 'hostflow:badge.front',
              doc: form.front,
              onTap: () => pickDoc(form.front),
            ),
          ),
          SizedBox(width: 10.ms),
          Expanded(
            child: BadgeDocTile(
              key: const ValueKey('badge-back'),
              label: 'hostflow:badge.back',
              doc: form.back,
              onTap: () => pickDoc(form.back),
            ),
          ),
        ],
      ),
      const HostLabel('hostflow:badge.linkedin'),
      HostField(
        controller: form.linkedIn,
        hint: 'hostflow:badge.linkedin_hint',
        capitalization: TextCapitalization.none,
        keyboardType: TextInputType.url,
      ),
      SizedBox(height: 16.ms),
      Pressable(
        onPressed: () {
          form.influencer.value = !form.influencer.value;
          HostEvents.badgeInfluencerToggled(enabled: form.influencer.value);
        },
        child: Row(
          children: [
            Icon(
              form.influencer.value
                  ? LucideIcons.squareCheck
                  : LucideIcons.square,
              size: 22.ms,
              color: form.influencer.value ? p.accent : p.muted,
            ),
            SizedBox(width: 10.ms),
            Expanded(
              child: CText(
                'hostflow:badge.influencer',
                size: 15,
                weight: FontWeight.w600,
                color: p.text,
              ),
            ),
          ],
        ),
      ),
    ];

    final social = <Widget>[
      const HostLabel('hostflow:badge.social_platform', top: 0),
      BadgePlatformChips(platform: form.platform),
      const HostLabel('hostflow:badge.social_url'),
      HostField(
        controller: form.socialUrl,
        hint: 'hostflow:badge.social_url_hint',
        capitalization: TextCapitalization.none,
        keyboardType: TextInputType.url,
        fieldKey: const ValueKey('badge-social-url'),
      ),
    ];

    return HostPage(
      title: 'hostflow:badge.form_title',
      trailing: CText(
        'hostflow:progress',
        variables: {'current': index + 1, 'total': steps.length},
        size: 13,
        weight: FontWeight.w600,
        color: p.muted,
      ),
      bottom: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (issue.value != null)
            Padding(
              padding: EdgeInsets.only(bottom: 10.ms),
              child: CText(
                issue.value!.key,
                variables: issue.value!.vars,
                size: 13,
                weight: FontWeight.w600,
                color: p.danger,
                align: TextAlign.center,
              ),
            ),
          HostButton(
            key: const ValueKey('badge-next'),
            label: last ? 'hostflow:badge.submit' : 'hostflow:badge.save_next',
            arrow: !last,
            loading: saving.value,
            onPressed: next,
          ),
          if (index > 0)
            Pressable(
              onPressed: () {
                HostEvents.badgeFormBack(steps[index]);
                form.step.value = index - 1;
              },
              child: Padding(
                padding: EdgeInsets.only(top: 12.ms),
                child: CText(
                  'hostflow:back',
                  size: 14,
                  weight: FontWeight.w700,
                  color: p.accent,
                  align: TextAlign.center,
                ),
              ),
            ),
        ],
      ),
      body: HostStepBody(
        key: ValueKey(steps[index]),
        title: 'hostflow:badge.step_${steps[index]}',
        subtitle: 'hostflow:badge.step_${steps[index]}_sub',
        children: steps[index] == 'identity' ? identity : social,
      ),
    );
  }
}
