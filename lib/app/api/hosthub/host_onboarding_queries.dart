part of 'hosthub_queries.dart';

// ── "Become a Host" onboarding ──────────────────────────────────────────────

/// Whether [handle] is free. Disabled for an empty handle; [ownExpertId]
/// (a host resubmitting) does not count as a clash.
QueryResult<bool, ApiException> useHostHandleCheck(
  BuildContext context,
  String handle, {
  String? ownExpertId,
  bool enabled = true,
}) => useApiQuery<bool>(
  HostHubKeys.handleCheck(handle, ownExpertId ?? ''),
  () => HostHandleApi.isAvailable(handle, ownExpertId: ownExpertId),
  context: context,
  enabled: enabled && handle.isNotEmpty,
  staleDuration: StaleTime.short,
);

/// [useHostHandleCheck] outside widgets (the Continue tap waits on it).
Future<bool> ensureHostHandleCheck(String handle, {String? ownExpertId}) =>
    queryCache.fetchQuery<bool>(
      HostHubKeys.handleCheck(handle, ownExpertId ?? ''),
      () => HostHandleApi.isAvailable(handle, ownExpertId: ownExpertId),
      staleDuration: StaleTime.short,
    );

/// The whole submit, in RN screen order: Professional Details (create or
/// update + photos), the user record, expertise, schedule and rates, then
/// the approval request.
MutationResult<HostOnboardingResult, ApiException, HostOnboardingInput>
useSubmitHostOnboarding({
  void Function(HostOnboardingResult result)? onSuccess,
  void Function(ApiException error)? onError,
}) => useApiMutation<HostOnboardingResult, HostOnboardingInput>(
  _submitHostOnboarding,
  invalidates: [
    HostHubKeys.profileAll,
    ListingKeys.all,
    HostHubKeys.imagesAll,
    HostHubKeys.approvalAll,
    HostHubKeys.expertise,
    HostHubKeys.statsAll,
    ClientKeys.profiles,
  ],
  onSuccess: (result, _) => onSuccess?.call(result),
  onError: (e, _) => onError?.call(e),
);

Future<HostOnboardingResult> _submitHostOnboarding(
  HostOnboardingInput input,
) async {
  final existingId = input.expertId;
  // Rows already on the server decide update vs create per photo slot.
  final existingPhotos = existingId == null
      ? const <HostProfileImage>[]
      : await HostImagesApi.fetchAll(existingId);

  final details = await _saveProfessionalDetails(
    ProfessionalDetailsInput(
      userDocumentId: input.userDocumentId,
      expertId: existingId,
      handler: input.handler,
      tagline: input.tagline,
      gender: input.gender,
      description: input.description,
      languages: input.languages,
      photos: [for (final id in input.photoMediaIds) HostMediaRef.media(id)],
      existingPhotos: existingPhotos,
      audioIntro: input.audioIntro,
      videoIntro: input.videoIntro,
    ),
  );
  final expertId = details.expertId;
  input.onExpertId?.call(expertId);

  // RN: the primary photo becomes the account photo, and the account turns
  // into a host the moment the host profile exists.
  await ProfileApi.updatePublicUser(input.userDocumentId, {
    ...input.userPatch,
    'profilePic': details.primaryMediaId,
    if (input.promoteToExpert) 'role': 'Expert',
  });
  if (input.promoteToExpert) {
    await SessionStore.instance.updateUser({'role': 'Expert'});
  }

  await ExpertiseApi.save(input.expertise, source: 'professional-details');

  // RN ScheduleScreen payload: `schedule` only when neither vacation nor
  // "call any time" is on.
  final schedule = HostProfilePatch.schedule(
    vacation: input.vacation,
    callAnyTime: input.callAnyTime,
    week: input.week,
  ).data;
  final profile = await _updateHostProfile((
    expertId: expertId,
    patch: HostProfilePatch({
      ...schedule,
      ...HostProfilePatch.rates(
        voice: input.rates.voiceCallRate,
        video: input.rates.videoCallRate,
      ).data,
      // `connect` only adds: on a resubmit, `set` drops removed languages.
      if (existingId != null)
        'language': {
          'set': [for (final l in input.languages) ?l.connectRef],
        },
    }),
  ));

  final status = await _requestApproval(expertId);
  // Same marker the Approval Status screen sets after its own request: the
  // server's approval read can come back empty for a fresh request, and
  // the screen must still show "under review" (RN backstop).
  await AppPrefs.setString(
    approvalSentKey(expertId),
    DateTime.now().toIso8601String(),
  );
  return HostOnboardingResult(
    expertId: expertId,
    status: status,
    profile: profile,
  );
}

// ── Host Hub: Professional Details edit ─────────────────────────────────────

/// Saves the profile like RN ProfessionalDetails (update, photos, the user's
/// `profilePic`); languages are replaced (`set`) so removed ones go away.
MutationResult<HostProfile?, ApiException, HostProfileEditInput>
useSaveHostProfileEdit() => useApiMutation<HostProfile?, HostProfileEditInput>(
  _saveHostProfileEdit,
  invalidates: [
    HostHubKeys.profileAll,
    ListingKeys.all,
    HostHubKeys.imagesAll,
    ClientKeys.profiles,
  ],
);

Future<HostProfile?> _saveHostProfileEdit(HostProfileEditInput input) async {
  final existing = await HostImagesApi.fetchAll(input.expertId);
  final details = await _saveProfessionalDetails(
    ProfessionalDetailsInput(
      userDocumentId: input.userDocumentId,
      expertId: input.expertId,
      handler: input.handler,
      tagline: input.tagline,
      gender: input.gender,
      description: input.description,
      languages: input.languages,
      photos: [for (final id in input.photoMediaIds) HostMediaRef.media(id)],
      existingPhotos: existing,
      audioIntro: input.audioIntro,
      videoIntro: input.videoIntro,
    ),
  );
  await ProfileApi.updatePublicUser(input.userDocumentId, {
    ...input.userPatch,
    'profilePic': details.primaryMediaId,
  });
  return _updateHostProfile((
    expertId: input.expertId,
    patch: HostProfilePatch({
      'language': {
        'set': [for (final l in input.languages) ?l.connectRef],
      },
    }),
  ));
}

// ── Host Hub: approval ──────────────────────────────────────────────────────

/// Sections still missing before approval (RN `getExpertProfileCompletion`,
/// expertise included). Under the profile prefix: profile saves refresh it.
QueryResult<HostProfileCompletion, ApiException> useHostCompletion(
  BuildContext context,
  HostProfile? profile,
) => useApiQuery<HostProfileCompletion>(
  HostHubKeys.completion(profile?.key ?? ''),
  () => checkHostProfileCompletion(profile!),
  context: context,
  enabled: profile != null,
  // Under the profile prefix: every profile / expertise save refreshes it.
  staleDuration: StaleTime.short,
);

// ── Host Hub: badge fee ─────────────────────────────────────────────────────

/// Starts the badge-fee payment (RN `payExpertVerification`, Razorpay).
MutationResult<BadgePaymentStart, ApiException, BadgePaymentRequest>
useStartBadgePayment() =>
    useApiMutation<BadgePaymentStart, BadgePaymentRequest>(_startBadgePayment);

typedef BadgePaymentRequest = ({
  String verificationId,
  double fee,
  PayerInfo payer,
});

Future<BadgePaymentStart> _startBadgePayment(BadgePaymentRequest r) async {
  JsonMap? config;
  try {
    config = (await ensureAppConfig()).raw;
  } on ApiException catch (e) {
    // RN read the public key from app-config only as a fallback.
    Log.w('hosthub', 'app-config unavailable for the Razorpay key: $e');
  }
  return HostBadgePaymentApi.start(
    verificationId: r.verificationId,
    fee: r.fee,
    payer: r.payer,
    appConfig: config,
  );
}

// ── Tagline / bio: "Enhance with AI" ────────────────────────────────────────

typedef HostTextEnhance = ({String text, String kind, int maxLength});

/// Rewrites a tagline / bio draft ([HostTextEnhanceApi]); nothing cached.
MutationResult<String, ApiException, HostTextEnhance> useEnhanceHostText() =>
    useApiMutation<String, HostTextEnhance>(
      (r) => HostTextEnhanceApi.enhance(
        r.text,
        kind: r.kind,
        maxLength: r.maxLength,
      ),
    );
