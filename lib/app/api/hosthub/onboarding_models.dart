import '../../../core/network/strapi.dart';
import 'approval_models.dart';
import 'catalog_models.dart';
import 'expertise_models.dart';
import 'profile_models.dart';
import 'profile_patch.dart';

/// Everything the "Become a Host" flow writes, in one submit (see
/// `useSubmitHostOnboarding`).
class HostOnboardingInput {
  const HostOnboardingInput({
    required this.userDocumentId,
    this.expertId,
    required this.handler,
    required this.tagline,
    this.gender,
    required this.description,
    required this.languages,
    required this.photoMediaIds,
    this.audioIntro,
    this.videoIntro,
    required this.rates,
    required this.callAnyTime,
    this.vacation = false,
    required this.week,
    required this.expertise,
    this.userPatch = const {},
    this.promoteToExpert = true,
    this.onExpertId,
  });

  /// Owner; becomes the `user` relation when the profile is created.
  final String userDocumentId;

  /// Set when an earlier attempt already created the profile (or a host
  /// resubmits after a rejection): the profile is updated, never duplicated.
  final String? expertId;
  final String handler;
  final String tagline;
  final String? gender;
  final String description;
  final List<HostOption> languages;

  /// Uploaded media ids, slot 1 = primary photo.
  final List<Object> photoMediaIds;

  /// A new voice-intro recording to upload as `audio_intro`.
  final HostMediaRef? audioIntro;

  /// A new video-intro clip to upload as `video_intro`. Optional, and never
  /// required to submit: it is an addition for hosts who want one, not a step.
  final HostMediaRef? videoIntro;

  /// A disabled call type is 0 (CallRatesScreen rule).
  final HostRates rates;

  /// "I'm available now" (`callAnyTime`).
  final bool callAnyTime;

  /// Vacation mode (`vocationMode`); the schedule is then not sent (RN).
  final bool vacation;
  final Map<HostWeekday, List<HostTimeSlot>> week;

  /// Answers for `/me/service-areas`, every required question included.
  final ExpertiseAnswers expertise;

  /// Extra `/public-users` fields (name, location) changed in the flow.
  final JsonMap userPatch;

  /// Writes `role: 'Expert'` on the user (RN ProfessionalDetails rule).
  final bool promoteToExpert;

  /// Called as soon as the profile exists, so a retry after a later failure
  /// updates it instead of creating a second one.
  final void Function(String expertId)? onExpertId;
}

class HostOnboardingResult {
  const HostOnboardingResult({
    required this.expertId,
    required this.status,
    this.profile,
  });

  final String expertId;
  final ApprovalStatus status;
  final HostProfile? profile;
}

/// An approved / submitted host editing Professional Details (RN
/// ProfessionalDetailsScreen save for an existing profile).
class HostProfileEditInput {
  const HostProfileEditInput({
    required this.userDocumentId,
    required this.expertId,
    required this.handler,
    required this.tagline,
    this.gender,
    required this.description,
    required this.languages,
    required this.photoMediaIds,
    this.audioIntro,
    this.videoIntro,
    this.userPatch = const {},
  });

  final String userDocumentId;
  final String expertId;

  /// A new voice-intro recording to upload as `audio_intro` (none: the
  /// profile's stays as it is).
  final HostMediaRef? audioIntro;

  /// A new video-intro clip to upload as `video_intro` (none: the profile's
  /// stays as it is, and keeps whatever moderation state it had).
  final HostMediaRef? videoIntro;
  final String handler;
  final String tagline;
  final String? gender;
  final String description;
  final List<HostOption> languages;

  /// Slot 1 = primary photo.
  final List<Object> photoMediaIds;

  /// Personal Info edited on the same screen (name, location).
  final JsonMap userPatch;
}
