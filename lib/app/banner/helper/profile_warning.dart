import '../../../core/network/strapi.dart';
import '../../../core/router/app_router.dart';
import '../../../core/session/session_store.dart';
import '../../api/hosthub/profile_models.dart';
import '../../hosthub/common/host_page.dart';
import '../../hosthub/common/moderation_banners.dart';
import '../../hosthub/onboarding/helper/host_steps.dart';

enum ProfileWarningType {
  /// A reviewer turned something down (outranks everything).
  moderationRejected,
  personal,
  professional,
  rates,
  approval,
  availability,

  /// Something is with a reviewer (after the completion steps).
  moderationPending,
}

/// What the user still has to do before they can call / go live.
class ProfileWarning {
  const ProfileWarning(
    this.type,
    this.route, {
    this.missing = const [],
    this.notice,
    this.more = 0,
  });

  final ProfileWarningType type;
  final String route;

  /// i18n keys of missing fields (`banner:fields.*`).
  final List<String> missing;

  /// The review notice behind a moderation warning.
  final HostModerationNotice? notice;

  /// Other review notices besides [notice] (" (+N more)").
  final int more;

  bool get isModeration =>
      type == ProfileWarningType.moderationRejected ||
      type == ProfileWarningType.moderationPending;

  /// Port of RN `TopWarnBar` rules, in the same order. Pure: easy to test.
  /// With [moderation] (Discover) the host's review state joins in, as in
  /// RN: a rejection outranks everything, "awaiting review" comes after the
  /// completion steps. Both apply to a live host too (edits are reviewed).
  static ProfileWarning? from(SessionState s, {bool moderation = false}) {
    final completion = _completion(s);
    if (!moderation) return completion;
    final host = s.isExpert ? HostProfile.from(s.expert) : null;
    final notices = host == null
        ? const <HostModerationNotice>[]
        : hostModerationNotices(host);
    if (notices.isEmpty) return completion;
    final more = notices.length - 1;
    for (final n in notices) {
      if (n.tone == HostTone.danger) {
        return ProfileWarning(
          ProfileWarningType.moderationRejected,
          _noticeRoute(n, host!),
          notice: n,
          more: more,
        );
      }
    }
    if (completion != null) return completion;
    for (final n in notices) {
      if (n.tone == HostTone.warning) {
        return ProfileWarning(
          ProfileWarningType.moderationPending,
          _noticeRoute(n, host!),
          notice: n,
          more: more,
        );
      }
    }
    return null;
  }

  /// The step a review notice is about: photos → Photos; text changes →
  /// the first changed field's step (tagline, about → Bio, handle /
  /// website → Basic); the audio intro → Voice.
  static String _noticeRoute(HostModerationNotice n, HostProfile host) {
    if (n.title.startsWith('hostflow:moderation.photos_')) {
      return AppRoutes.hostStep(HostStep.photos.name);
    }
    if (n.title.startsWith('hostflow:moderation.audio_')) {
      return AppRoutes.hostStep(HostStep.voice.name);
    }
    if (n.title.startsWith('hostflow:moderation.video_')) {
      return AppRoutes.hostStep(HostStep.video.name);
    }
    for (final field in host.pendingChangeFields) {
      final step = _fieldSteps[field];
      if (step != null) return AppRoutes.hostStep(step.name);
    }
    return AppRoutes.hostStep(HostStep.basic.name);
  }

  /// Expert-profile fields → the onboarding step that edits them.
  static const _fieldSteps = {
    'handler': HostStep.basic,
    'name': HostStep.basic,
    'language': HostStep.basic,
    'website': HostStep.basic,
    'host_profile_images': HostStep.photos,
    'tagline': HostStep.tagline,
    'descriptions': HostStep.bio,
  };

  /// Missing professional field (`banner:fields.*`) → its step.
  static const _missingSteps = {
    'banner:fields.handle': HostStep.basic,
    'banner:fields.languages': HostStep.basic,
    'banner:fields.tagline': HostStep.tagline,
    'banner:fields.description': HostStep.bio,
  };

  /// No `isLive` shortcut: that field does not exist on expert-profile and
  /// nothing ever wrote it (RN removed it too).
  static ProfileWarning? _completion(SessionState s) {
    final user = s.user;
    if (user == null) return null;
    final expert = Strapi.map(s.expert);

    final personal = [
      if (J.str(user['name']) == null) 'banner:fields.name',
      if (J.str(user['email']) == null) 'banner:fields.email',
      if (J.str(user['mobile']) == null) 'banner:fields.mobile',
    ];
    if (personal.isNotEmpty) {
      return ProfileWarning(
        ProfileWarningType.personal,
        AppRoutes.personalInfo,
        missing: personal,
      );
    }

    final isExpert =
        expert != null &&
        (expert['id'] != null || expert['documentId'] != null);
    if (!isExpert) return null;

    final handler = J.str(expert['handler']) ?? '';
    final professional = [
      if (handler.length < 3) 'banner:fields.handle',
      if (J.str(expert['tagline']) == null) 'banner:fields.tagline',
      if (Strapi.list(expert['language']).isEmpty) 'banner:fields.languages',
      if (J.str(expert['descriptions']) == null) 'banner:fields.description',
    ];
    if (professional.isNotEmpty) {
      // The first missing field's step (RN order: handle, tagline,
      // languages, description).
      return ProfileWarning(
        ProfileWarningType.professional,
        AppRoutes.hostStep(_missingSteps[professional.first]!.name),
        missing: professional,
      );
    }

    final rates = Strapi.map(expert['rates']) ?? const {};
    final voice =
        J.number(rates['voiceCallRate'] ?? expert['voiceCallRate']) ?? 0;
    final video =
        J.number(rates['videoCallRate'] ?? expert['videoCallRate']) ?? 0;
    if (voice == 0 && video == 0) {
      return const ProfileWarning(
        ProfileWarningType.rates,
        AppRoutes.callRates,
      );
    }

    final approvals = Strapi.list(expert['expert_profile_approvals']);
    if (HostCompletion.needsApprovalSubmission(expert, approvals)) {
      return const ProfileWarning(
        ProfileWarningType.approval,
        AppRoutes.approval,
      );
    }

    // Last: hours are only worth setting once the profile is through review.
    if (HostCompletion.isApproved(expert, approvals) &&
        HostCompletion.needsAvailability(expert)) {
      return const ProfileWarning(
        ProfileWarningType.availability,
        AppRoutes.schedule,
      );
    }
    return null;
  }
}

/// RN `shared/utils/host-completion`: which step a host still has to do.
abstract final class HostCompletion {
  /// `isApproved` on the profile is the authority (the server lists on it;
  /// the moderation panel writes it and not the row). An approved row still
  /// counts, for the older flow. Only a strict `true` approves.
  static bool isApproved(JsonMap? expert, List<JsonMap> approvals) =>
      expert?['isApproved'] == true ||
      approvals.any((a) => a['is_approved'] == true);

  /// A submission is with a reviewer: a row EXISTS and none is approved.
  /// The flag alone cannot tell "submitted, waiting" from "not submitted".
  static bool isApprovalPending(JsonMap? expert, List<JsonMap> approvals) =>
      approvals.isNotEmpty && !isApproved(expert, approvals);

  /// Neither approved nor submitted: prompt to submit.
  static bool needsApprovalSubmission(
    JsonMap? expert,
    List<JsonMap> approvals,
  ) => !isApproved(expert, approvals) && !isApprovalPending(expert, approvals);

  /// The server answers whether any hours are set (`availability_unset`; a
  /// break counts as set). Absent means it could not tell: say nothing.
  static bool needsAvailability(JsonMap? expert) =>
      expert?['availability_unset'] == true;
}
