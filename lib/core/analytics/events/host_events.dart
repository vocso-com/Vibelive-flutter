import '../analytics.dart';

/// Host events (Firebase + Meta): the "Become a Host" funnel, host hub,
/// approval, verification badge (and its fee), profile QR, availability and
/// the ME tab's host widgets. Catalog: docs/analytics_events.md.
///
/// Funnel: every step has its own `host_ob_<step>_viewed` /
/// `host_ob_<step>_completed` pair, so Firebase funnels AND Meta's event
/// counts show how many people reached each step.
abstract final class HostEvents {
  // ── Funnel ─────────────────────────────────────────────────────────────

  /// The flow opened. [mode]: `new` | `resume` | `edit` | `existing_host`.
  static void onboardingStarted({
    required String mode,
    required String startStep,
    required int stepNumber,
    required String source,
  }) => Analytics.log('host_onboarding_started', {
    'mode': mode,
    'start_step': startStep,
    'step_number': stepNumber,
    'source': source,
  });

  /// [step] (a `HostStep` name) is on screen.
  static void stepViewed(
    String step, {
    required int stepNumber,
    required String mode,
    required String source,
  }) => Analytics.log('host_ob_${step}_viewed', {
    'step': step,
    'step_number': stepNumber,
    'mode': mode,
    'source': source,
  });

  /// Continue on [step] passed its checks and moved on (the guidelines:
  /// the application went in; the intro: "Get started").
  static void stepCompleted(
    String step, {
    required int stepNumber,
    required String mode,
    required String source,
  }) => Analytics.log('host_ob_${step}_completed', {
    'step': step,
    'step_number': stepNumber,
    'mode': mode,
    'source': source,
  });

  static void stepBack(
    String step, {
    required int stepNumber,
    required String mode,
  }) => Analytics.log('host_onboarding_step_back', {
    'step': step,
    'step_number': stepNumber,
    'mode': mode,
  });

  /// Continue / Save refused; [issue] is the i18n key of the notice.
  static void validationFailed(
    String step, {
    required String issue,
    required String mode,
  }) => Analytics.log('host_onboarding_validation_failed', {
    'step': step,
    'issue': issue,
    'mode': mode,
  });

  static void handleTaken({required String mode}) =>
      Analytics.log('host_handle_taken', {'mode': mode});

  /// Left the flow ([completed]: submitted / saved first).
  static void onboardingExited({
    required String lastStep,
    required int stepNumber,
    required bool completed,
    required String mode,
    required String source,
  }) => Analytics.log('host_onboarding_exited', {
    'last_step': lastStep,
    'step_number': stepNumber,
    'completed': completed,
    'mode': mode,
    'source': source,
  });

  /// The application went in: custom event, Meta `SubmitApplication`, and
  /// RN's `expert_signup` once per user ([userKey]).
  static void onboardingSubmitted({
    required String? userKey,
    String? category,
    int? topicsCount,
    int? photosCount,
    bool? hasVoiceIntro,
    int? audioRate,
    int? videoRate,
    required String source,
  }) {
    final params = {
      'category': category,
      'topics_count': topicsCount,
      'photos_count': photosCount,
      'has_voice_intro': hasVoiceIntro,
      'audio_rate': audioRate,
      'video_rate': videoRate,
      'source': source,
    };
    Analytics.log('host_onboarding_submitted', params);
    Analytics.meta('SubmitApplication', {
      'fb_content_type': 'host_application',
      'category': category,
    });
    if (userKey != null && userKey.isNotEmpty) {
      Analytics.logOncePersisted('expert_signup_$userKey', 'expert_signup', {
        'category': category ?? 'expert',
      });
    }
  }

  static void submitFailed({required String error, String? failedStep}) =>
      Analytics.log('host_onboarding_submit_failed', {
        'error': error,
        'failed_step': failedStep,
      });

  /// A preview "Edit" link.
  static void previewEditTapped(String section) =>
      Analytics.log('host_preview_edit_tapped', {'section': section});

  /// An existing host saved [step] (`all`: the last step's "Save").
  static void sectionSaved(String step, {required String mode}) =>
      Analytics.log('host_profile_section_saved', {'step': step, 'mode': mode});

  static void sectionSaveFailed(String step, {required String error}) =>
      Analytics.log('host_profile_section_save_failed', {
        'step': step,
        'error': error,
      });

  // ── RN parity (settings saves) ────────────────────────────────────────

  static void specializationSelected({
    String? expertId,
    required List<String> categoryIds,
    required List<String> categoryNames,
    required String source,
  }) => Analytics.log('specialization_selected', {
    'expert_id': expertId,
    'category_ids': categoryIds.join(','),
    'category_names': categoryNames.join(', '),
    'categories_count': categoryIds.length,
    'source': source,
  });

  static void callRatesUpdated({
    String? expertId,
    required num? audioRate,
    required num? videoRate,
  }) => Analytics.log('call_rates_updated', {
    'expert_id': expertId,
    'audio_rate': audioRate,
    'video_rate': videoRate,
  });

  /// [mode]: `online` | `offline` | `scheduled`.
  static void scheduleUpdated({String? expertId, required String mode}) =>
      Analytics.log('schedule_updated', {'expert_id': expertId, 'mode': mode});

  // ── Step details ───────────────────────────────────────────────────────

  static void topicToggled({
    required String topic,
    required bool selected,
    required int count,
  }) => Analytics.log('host_topic_toggled', {
    'topic': topic,
    'selected': selected,
    'count': count,
  });

  static void topicsCleared({required int count}) =>
      Analytics.log('host_topics_cleared', {'count': count});

  /// [origin]: `gallery` | `camera`.
  static void photoSourceChosen(String origin) =>
      Analytics.log('host_photo_source_chosen', {'origin': origin});

  static void photoAdded({required String origin, required int count}) =>
      Analytics.log('host_photo_added', {'origin': origin, 'count': count});

  static void photoPickFailed({required String origin}) =>
      Analytics.log('host_photo_pick_failed', {'origin': origin});

  static void photoUploaded({required int count}) =>
      Analytics.log('host_photo_uploaded', {'count': count});

  static void photoUploadFailed({required String error}) =>
      Analytics.log('host_photo_upload_failed', {'error': error});

  static void photoRetried() => Analytics.log('host_photo_retried');

  static void photoRemoved({required int count}) =>
      Analytics.log('host_photo_removed', {'count': count});

  static void photoMadePrimary() => Analytics.log('host_photo_made_primary');

  static void voiceRecordStarted() =>
      Analytics.log('host_voice_record_started');

  static void voiceRecorded({required int seconds}) =>
      Analytics.log('host_voice_recorded', {'seconds': seconds});

  static void voiceTooShort({required int seconds}) =>
      Analytics.log('host_voice_too_short', {'seconds': seconds});

  /// [stage]: `start` | `stop`.
  static void voiceRecordFailed({required String stage}) =>
      Analytics.log('host_voice_record_failed', {'stage': stage});

  static void voicePermissionDenied() =>
      Analytics.log('host_voice_permission_denied');

  /// [recording]: `new` | `saved`.
  static void voicePlayed({required String recording}) =>
      Analytics.log('host_voice_played', {'recording': recording});

  static void voicePlayFailed() => Analytics.log('host_voice_play_failed');

  static void voiceDiscarded() => Analytics.log('host_voice_discarded');

  static void voiceUploaded({required int seconds}) =>
      Analytics.log('host_voice_uploaded', {'seconds': seconds});

  static void voiceUploadFailed({required String error}) =>
      Analytics.log('host_voice_upload_failed', {'error': error});

  /// AI enhance on [field] (`tagline` | `bio`); [result] `success` |
  /// `failed` | `empty`.
  static void aiEnhanceUsed(
    String field, {
    required String result,
    String? error,
  }) => Analytics.log('host_ai_enhance_used', {
    'field': field,
    'result': result,
    'error': error,
  });

  static void aiEnhanceUndone(String field) =>
      Analytics.log('host_ai_enhance_undone', {'field': field});

  /// A prompt suggestion's "Use" on [field].
  static void suggestionUsed(String field, {required int position}) =>
      Analytics.log('host_suggestion_used', {
        'field': field,
        'position': position,
      });

  static void callTypeToggled({
    required String callType,
    required bool enabled,
  }) => Analytics.log('host_call_type_toggled', {
    'call_type': callType,
    'enabled': enabled,
  });

  static void earningsViewed({int? audioRate, int? videoRate}) => Analytics.log(
    'host_earnings_viewed',
    {'audio_rate': audioRate, 'video_rate': videoRate},
  );

  /// [mode]: `online` | `offline` | `scheduled`.
  static void availabilityModeSelected(String mode) =>
      Analytics.log('host_availability_mode_selected', {'mode': mode});

  static void timeSlotSaved({required String day, required bool edited}) =>
      Analytics.log('host_time_slot_saved', {'day': day, 'edited': edited});

  static void guidelinesOpened() => Analytics.log('host_guidelines_opened');

  static void guidelinesAgreed({required bool agreed}) =>
      Analytics.log('host_guidelines_agreed', {'agreed': agreed});

  // ── Host hub / approval / moderation ──────────────────────────────────

  static void hubItemTapped(String item) =>
      Analytics.log('host_hub_item_tapped', {'item': item});

  /// [status]: `pending` | `approved` | `live` | `rejected` | `not_sent`.
  static void approvalViewed({
    required String status,
    required int missingCount,
  }) => Analytics.log('host_approval_viewed', {
    'status': status,
    'missing_count': missingCount,
  });

  static void approvalRequested({required bool resend}) =>
      Analytics.log('host_approval_requested', {'resend': resend});

  static void approvalBlockedIncomplete({required int missingCount}) =>
      Analytics.log('host_approval_blocked_incomplete', {
        'missing_count': missingCount,
      });

  static void approvalRequestSent({required String result}) =>
      Analytics.log('host_approval_request_sent', {'result': result});

  static void approvalRequestFailed({required String error}) =>
      Analytics.log('host_approval_request_failed', {'error': error});

  static void approvalMissingTapped(String section) =>
      Analytics.log('host_approval_missing_tapped', {'section': section});

  static void approvalExploreTapped({required String status}) =>
      Analytics.log('host_approval_explore_tapped', {'status': status});

  static void goLiveTapped() => Analytics.log('host_go_live_tapped');

  static void wentLive() => Analytics.log('host_went_live');

  static void goLiveFailed({required String error}) =>
      Analytics.log('host_go_live_failed', {'error': error});

  /// The ME tab's under-review / changes-needed card CTA.
  static void reviewCardTapped({required String status}) =>
      Analytics.log('host_review_card_tapped', {'status': status});

  static void moderationBannersShown({
    required int count,
    required String kinds,
  }) => Analytics.log('host_moderation_banners_shown', {
    'count': count,
    'kinds': kinds,
  });

  static void moderationMessagesShown({required int count}) =>
      Analytics.log('host_moderation_messages_shown', {'count': count});

  static void moderationMessagesExpanded({required bool expanded}) =>
      Analytics.log('host_moderation_messages_expanded', {
        'expanded': expanded,
      });

  /// [action]: `link` | `fix`.
  static void moderationMessageTapped({required String action}) =>
      Analytics.log('host_moderation_message_tapped', {'action': action});

  // ── Onboarding training (docs/host_onboarding.md) ─────────────────────

  /// The admin's training steps opened from the flow ([beforeSubmit]: the
  /// catch-up before Submit).
  static void trainingShown({required int count, required bool beforeSubmit}) =>
      Analytics.log('host_training_shown', {
        'count': count,
        'before_submit': beforeSubmit,
      });

  static void trainingStepViewed({
    required String stepId,
    required String kind,
    required int number,
  }) => Analytics.log('host_training_step_viewed', {
    'step_id': stepId,
    'kind': kind,
    'number': number,
  });

  /// [result]: watched (to the end), skipped, continued (before the end).
  static void trainingVideoDone({
    required String stepId,
    required String result,
    required int seconds,
  }) => Analytics.log('host_training_video_done', {
    'step_id': stepId,
    'result': result,
    'seconds': seconds,
  });

  /// [passed] / [percent]: null when the admin does not show them to the
  /// host (the app is not told either).
  static void trainingQuizSubmitted({
    required String stepId,
    required int? percent,
    required bool? passed,
    required int attempt,
  }) => Analytics.log('host_training_quiz_submitted', {
    'step_id': stepId,
    'percent': ?percent,
    'passed': ?passed,
    'result_shown': passed != null,
    'attempt': attempt,
  });

  /// Backed out of the training (stays on the step before it).
  static void trainingLeft({required String stepId}) =>
      Analytics.log('host_training_left', {'step_id': stepId});

  /// The clips frame on an onboarding step came on screen.
  static void onboardingClipsShown({
    required String step,
    required int count,
  }) => Analytics.log('host_onboarding_clips_shown', {
    'step': step,
    'count': count,
  });

  // ── Verification badge ────────────────────────────────────────────────

  static void badgeStatusViewed({required String step, required bool review}) =>
      Analytics.log('badge_status_viewed', {'step': step, 'review': review});

  static void badgePrimaryTapped({
    required String step,
    required bool review,
  }) => Analytics.log('badge_primary_tapped', {'step': step, 'review': review});

  /// Not eligible yet (no approved host profile).
  static void badgeLockedViewed({required String screen}) =>
      Analytics.log('badge_locked_viewed', {'screen': screen});

  static void badgeFeeViewed({required double amount}) =>
      Analytics.log('badge_fee_viewed', {'amount': amount});

  /// "Pay now": custom event plus Meta / Firebase checkout events.
  static void badgeFeePayTapped({required double amount}) {
    Analytics.log('badge_fee_pay_tapped', {'amount': amount});
    Analytics.meta('fb_mobile_initiated_checkout', {
      'fb_content_type': 'verification_badge',
      'fb_currency': 'INR',
      'amount': amount,
    }, valueToSum: amount);
    Analytics.firebase('begin_checkout', {
      'currency': 'INR',
      'value': amount,
      'item_name': 'verification_badge',
    });
  }

  static void badgeFeeCheckoutOpened({
    required double amount,
    String? orderId,
  }) => Analytics.log('badge_fee_checkout_opened', {
    'amount': amount,
    'order_id': orderId,
  });

  /// Checkout closed without paying ([reason]: how it ended, e.g.
  /// `userDismissed`, or that it never opened).
  static void badgeFeeCancelled({required double amount, String? reason}) =>
      Analytics.log('badge_fee_cancelled', {
        'amount': amount,
        'reason': reason,
      });

  static void badgeFeeFailed({required double amount, String? error}) =>
      Analytics.log('badge_fee_failed', {'amount': amount, 'error': error});

  /// Paid and confirmed: once per payment, with Meta's Purchase and
  /// Firebase's `purchase` (real money).
  static void badgeFeePaid({
    required double amount,
    required String paymentId,
    String? orderId,
  }) {
    if (!_paid.add(paymentId)) return;
    Analytics.log('badge_fee_paid', {
      'amount': amount,
      'payment_id': paymentId,
      'order_id': orderId,
    });
    Analytics.metaPurchase(amount, {
      'fb_content_type': 'verification_badge',
      'payment_id': paymentId,
      'order_id': orderId,
    });
    Analytics.firebase('purchase', {
      'currency': 'INR',
      'value': amount,
      'transaction_id': paymentId,
      'item_name': 'verification_badge',
    });
  }

  /// Payments already reported by [badgeFeePaid] in this app session.
  static final _paid = <String>{};

  static void badgeFeePending({required double amount}) =>
      Analytics.log('badge_fee_pending', {'amount': amount});

  static void badgeFeeAlreadyPaid() => Analytics.log('badge_fee_already_paid');

  /// Nothing to pay (fee 0): marked paid without checkout.
  static void badgeFeeWaived() => Analytics.log('badge_fee_waived');

  static void badgeFeeError({required String error}) =>
      Analytics.log('badge_fee_error', {'error': error});

  static void badgeFormStepSaved(String step) =>
      Analytics.log('badge_form_step_saved', {'step': step});

  static void badgeFormValidationFailed(String step, {required String issue}) =>
      Analytics.log('badge_form_validation_failed', {
        'step': step,
        'issue': issue,
      });

  static void badgeFormBack(String step) =>
      Analytics.log('badge_form_back', {'step': step});

  static void badgeDocTypeSelected(String docType) =>
      Analytics.log('badge_doc_type_selected', {'doc_type': docType});

  /// [side]: `front` | `back`.
  static void badgeDocUploaded({required String side}) =>
      Analytics.log('badge_doc_uploaded', {'side': side});

  static void badgeDocUploadFailed({
    required String side,
    required String error,
  }) =>
      Analytics.log('badge_doc_upload_failed', {'side': side, 'error': error});

  static void badgeInfluencerToggled({required bool enabled}) =>
      Analytics.log('badge_influencer_toggled', {'enabled': enabled});

  static void badgeInfluencerDeclined() =>
      Analytics.log('badge_influencer_declined');

  /// The badge application went in: custom event plus RN's
  /// `verification_submitted`.
  static void badgeFormSubmitted({
    required String? userId,
    required bool influencer,
    String? platform,
  }) {
    Analytics.log('badge_form_submitted', {
      'influencer': influencer,
      'platform': platform,
    });
    Analytics.log('verification_submitted', {
      'user_id': userId,
      'category': influencer ? 'influencer' : 'identity',
    });
  }

  static void badgeFormSubmitFailed({required String error}) =>
      Analytics.log('badge_form_submit_failed', {'error': error});

  // ── Profile QR ────────────────────────────────────────────────────────

  static void qrOpened({required bool hasLink}) =>
      Analytics.log('host_qr_opened', {'has_link': hasLink});

  // ── Availability (online / offline) ───────────────────────────────────

  static void availabilitySheetOpened({
    required String source,
    required String current,
  }) => Analytics.log('host_availability_sheet_opened', {
    'source': source,
    'current': current,
  });

  /// A host picked a status. [status]: `online` | `offline` |
  /// `scheduled`; [duration]: `30m` | `1h` | `2h` | `till_9am` |
  /// `indefinite`.
  static void statusChanged({
    required String status,
    required String duration,
    required String source,
  }) => Analytics.log('host_status_changed', {
    'status': status,
    'duration': duration,
    'source': source,
  });

  static void statusSaved({required String status}) =>
      Analytics.log('host_status_saved', {'status': status});

  static void statusSaveFailed({
    required String status,
    required String error,
  }) => Analytics.log('host_status_save_failed', {
    'status': status,
    'error': error,
  });

  /// The offline timer ran out: back online on its own.
  static void autoBackOnline() => Analytics.log('host_auto_back_online');

  static void workingHoursTapped() =>
      Analytics.log('host_working_hours_tapped');

  static void statusPillTapped({required String status}) =>
      Analytics.log('host_status_pill_tapped', {'status': status});

  // ── ME tab host widgets ───────────────────────────────────────────────

  static void earningsCardTapped() =>
      Analytics.log('host_earnings_card_tapped');

  static void dashboardReferralTapped() =>
      Analytics.log('host_dashboard_referral_tapped');

  /// The one-time "Become a Host — unlocked" celebration.
  static void unlockPromoShown() => Analytics.log('host_unlock_promo_shown');

  static void unlockPromoDismissed() =>
      Analytics.log('host_unlock_promo_dismissed');
}
