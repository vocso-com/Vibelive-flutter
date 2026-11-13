part of 'hosthub_queries.dart';

// ── Reference data ──────────────────────────────────────────────────────────

QueryResult<List<HostOption>, ApiException> useHostLanguages(
  BuildContext context, {
  bool enabled = true,
}) => useApiQuery<List<HostOption>>(
  HostHubKeys.languages,
  HostCatalogApi.fetchLanguages,
  context: context,
  enabled: enabled,
  staleDuration: StaleTime.static,
);

Future<List<HostOption>> ensureHostLanguages() =>
    queryCache.fetchQuery<List<HostOption>>(
      HostHubKeys.languages,
      HostCatalogApi.fetchLanguages,
      staleDuration: StaleTime.static,
    );

/// [platform]: the user's (`CategoryPlatform.fromRelation(user['platform'])`),
/// else this app's.
QueryResult<CategoryPage, ApiException> useHostCategoriesPage(
  BuildContext context, {
  int page = 1,
  int pageSize = 45,
  String search = '',
  CategoryPlatform? platform,
  bool enabled = true,
}) {
  final p = platform ?? CategoryPlatform.appDefault;
  final term = search.trim();
  return useApiQuery<CategoryPage>(
    HostHubKeys.categoriesPage(p.cacheKey, page, pageSize, term),
    () => HostCatalogApi.fetchCategoriesPage(
      page: page,
      pageSize: pageSize,
      search: term,
      platform: p,
    ),
    context: context,
    enabled: enabled,
    staleDuration: StaleTime.static,
  );
}

QueryResult<List<HostOption>, ApiException> useAllHostCategories(
  BuildContext context, {
  CategoryPlatform? platform,
  bool enabled = true,
}) {
  final p = platform ?? CategoryPlatform.appDefault;
  return useApiQuery<List<HostOption>>(
    HostHubKeys.allCategories(p.cacheKey),
    () => HostCatalogApi.fetchAllCategories(platform: p),
    context: context,
    enabled: enabled,
    staleDuration: StaleTime.static,
  );
}

QueryResult<List<String>, ApiException> useEducationLevels(
  BuildContext context, {
  bool enabled = true,
}) => useApiQuery<List<String>>(
  HostHubKeys.educationLevels,
  HostVerificationApi.fetchEducationLevels,
  context: context,
  enabled: enabled,
  staleDuration: StaleTime.static,
);

// ── Moderation ──────────────────────────────────────────────────────────────

/// The signed-in host's messages from the moderation team, newest first
/// (notes, and what a rejection was about). Hosts only.
QueryResult<List<HostModerationMessage>, ApiException>
useHostModerationMessages(BuildContext context, {bool enabled = true}) {
  final session = useValueListenable(SessionStore.instance);
  return useApiQuery<List<HostModerationMessage>>(
    HostHubKeys.moderationMessages,
    HostModerationApi.fetchMine,
    context: context,
    enabled: enabled && session.isExpert,
    staleDuration: StaleTime.short,
  );
}

/// Closes [message] (the host's X): gone from the list at once, and back if
/// the server says no. A message the server no longer has stays gone.
Future<void> dismissModerationMessage(HostModerationMessage message) async {
  const key = HostHubKeys.moderationMessages;
  final before = queryCache.entry<List<HostModerationMessage>>(key)?.data;
  if (before != null) {
    queryCache.setQueryData<List<HostModerationMessage>, ApiException>(
      key,
      (_) => [
        for (final m in before)
          if (m.id != message.id) m,
      ],
    );
  }
  try {
    await ApiClient.guard(() => HostModerationApi.dismiss(message.id));
  } on ApiException catch (e) {
    if (e.statusCode == 404) return;
    if (before != null) {
      queryCache.setQueryData<List<HostModerationMessage>, ApiException>(
        key,
        (_) => before,
      );
    }
    rethrow;
  }
}

// ── Approval ────────────────────────────────────────────────────────────────

/// Latest approval request; combine with the profile through
/// `ApprovalRecord.effective`.
QueryResult<ApprovalRecord?, ApiException> useLatestApproval(
  BuildContext context, {
  String? expertId,
  bool enabled = true,
}) {
  final session = useValueListenable(SessionStore.instance);
  final id = expertId ?? _ownExpertId(session);
  return useApiQuery<ApprovalRecord?>(
    HostHubKeys.latestApproval(id ?? ''),
    () => HostApprovalApi.fetchLatest(id!),
    context: context,
    enabled: enabled && id != null,
    staleDuration: StaleTime.short,
  );
}

Future<ApprovalRecord?> ensureLatestApproval(String expertId) =>
    queryCache.fetchQuery<ApprovalRecord?>(
      HostHubKeys.latestApproval(expertId),
      () => HostApprovalApi.fetchLatest(expertId),
    );

/// Files an approval request for [expertId] unless one is already pending
/// or approved; returns the resulting status.
MutationResult<ApprovalStatus, ApiException, String> useRequestApproval({
  List<RawQueryKey> alsoInvalidate = const [],
  void Function(ApprovalStatus status)? onSuccess,
  void Function(ApiException error)? onError,
}) => useApiMutation<ApprovalStatus, String>(
  _requestApproval,
  invalidates: [
    HostHubKeys.approvalAll,
    HostHubKeys.profileAll,
    ...alsoInvalidate,
  ],
  onSuccess: (status, _) => onSuccess?.call(status),
  onError: (e, _) => onError?.call(e),
);

Future<ApprovalStatus> _requestApproval(String expertId) async {
  // Re-check right before creating: a request from another device, an
  // earlier visit or a double tap must not be filed twice.
  final existing = (await HostApprovalApi.fetchLatest(expertId))?.status;
  if (existing == ApprovalStatus.pending ||
      existing == ApprovalStatus.approved) {
    return existing!;
  }
  await HostApprovalApi.create(expertId);
  await _refreshOwnProfile(expertId);
  return ApprovalStatus.pending;
}

// ── Verification badge ──────────────────────────────────────────────────────

/// The host's furthest-along verification record (null before applying).
QueryResult<VerificationRecord?, ApiException> useLatestVerification(
  BuildContext context, {
  String? expertId,
  bool enabled = true,
}) {
  final session = useValueListenable(SessionStore.instance);
  final id = expertId ?? _ownExpertId(session);
  return useApiQuery<VerificationRecord?>(
    HostHubKeys.latestVerification(id ?? ''),
    () => HostVerificationApi.fetchLatest(id!),
    context: context,
    enabled: enabled && id != null,
    staleDuration: StaleTime.short,
  );
}

Future<VerificationRecord?> ensureLatestVerification(String expertId) =>
    queryCache.fetchQuery<VerificationRecord?>(
      HostHubKeys.latestVerification(expertId),
      () => HostVerificationApi.fetchLatest(expertId),
    );

/// The record the fee/form screens work on, documents populated. CREATES it
/// when missing (RN `ensureVerificationRecord`), so enable it only when
/// `HostEligibility.canApplyForBadge` holds. [draft]: read the draft
/// version (the form saves drafts).
QueryResult<VerificationRecord, ApiException> useCurrentVerification(
  BuildContext context, {
  String? expertId,
  bool draft = false,
  bool enabled = true,
}) {
  final session = useValueListenable(SessionStore.instance);
  final id = expertId ?? _ownExpertId(session);
  return useApiQuery<VerificationRecord>(
    HostHubKeys.currentVerification(id ?? '', draft: draft),
    () => _currentVerification(id!, draft: draft),
    context: context,
    enabled: enabled && id != null,
    staleDuration: StaleTime.none,
  );
}

Future<VerificationRecord> _currentVerification(
  String expertId, {
  required bool draft,
}) async {
  final record = await HostVerificationApi.ensure(expertId);
  final full = await HostVerificationApi.fetchById(
    record.key,
    status: draft ? 'draft' : null,
  );
  return full ?? record;
}

/// Saves a form step / submit / "fee is 0, mark paid".
MutationResult<VerificationRecord?, ApiException, VerificationUpdate>
useUpdateVerification({
  void Function(VerificationRecord? record)? onSuccess,
  void Function(ApiException error)? onError,
}) => useApiMutation<VerificationRecord?, VerificationUpdate>(
  (u) async {
    final record = await HostVerificationApi.update(u);
    if (u.changesBadgeStep) await _refreshSessionExpert();
    return record;
  },
  invalidates: [HostHubKeys.verificationAll, HostHubKeys.profileAll],
  onSuccess: (record, _) => onSuccess?.call(record),
  onError: (e, _) => onError?.call(e),
);

/// PayU checkout data (or `alreadyPaid`). Razorpay checkout is the payment
/// feature's (`payExpertVerification`).
MutationResult<VerificationPaymentInit, ApiException, VerificationPaymentStart>
useInitiateVerificationPayment({
  void Function(VerificationPaymentInit init)? onSuccess,
  void Function(ApiException error)? onError,
}) => useApiMutation<VerificationPaymentInit, VerificationPaymentStart>(
  (v) => HostVerificationApi.initiatePayment(
    userId: v.userId,
    verificationId: v.verificationId,
  ),
  invalidates: [HostHubKeys.verificationAll],
  onSuccess: (init, _) => onSuccess?.call(init),
  onError: (e, _) => onError?.call(e),
);

/// After the gateway: forwards its result, then waits until the backend
/// marks the record paid. False = still unconfirmed ("refresh in a few
/// seconds").
MutationResult<bool, ApiException, VerificationPaymentResult>
useConfirmVerificationPayment({
  void Function(bool paid)? onSuccess,
  void Function(ApiException error)? onError,
}) => useApiMutation<bool, VerificationPaymentResult>(
  _confirmVerificationPayment,
  invalidates: [HostHubKeys.verificationAll, HostHubKeys.profileAll],
  onSuccess: (paid, _) => onSuccess?.call(paid),
  onError: (e, _) => onError?.call(e),
);

Future<bool> _confirmVerificationPayment(VerificationPaymentResult v) async {
  try {
    await HostVerificationApi.postPaymentResponse(v.payload);
  } on ApiException catch (e) {
    // RN ignored this failure and let the poll decide whether the payment
    // landed.
    Log.w('hosthub', 'payment-response failed: $e');
  }
  final paid = await HostVerificationApi.waitForPayment(v.verificationId);
  if (paid) await _refreshSessionExpert();
  return paid;
}

// ── Stats ───────────────────────────────────────────────────────────────────

/// Host dashboard figures, kept on disk so they paint instantly. Defaults to
/// the signed-in user and only runs for hosts. A failed refresh keeps the
/// last figures: render `data ?? HostStats.empty` and don't surface the
/// error (stats must never take the profile screen down).
QueryResult<HostStats, ApiException> useHostStats(
  BuildContext context, {
  String? userDocumentId,
  bool enabled = true,
}) {
  final session = useValueListenable(SessionStore.instance);
  final id = userDocumentId ?? session.userDocumentId;
  return usePersistedQuery<HostStats>(
    HostHubKeys.stats(id ?? ''),
    () => HostStatsApi.fetch(id!),
    context: context,
    enabled:
        enabled && id != null && (userDocumentId != null || session.isExpert),
    staleDuration: StaleTime.short,
    toJson: (s) => s.toJson(),
    fromJson: HostStats.fromJson,
  );
}

/// Startup prefetch / pull-to-refresh outside widgets; also updates the disk
/// copy.
Future<HostStats> ensureHostStats(String userDocumentId) {
  final key = HostHubKeys.stats(userDocumentId);
  return queryCache.fetchQuery<HostStats>(key, () async {
    final stats = await HostStatsApi.fetch(userDocumentId);
    QueryPersist.write(key, stats.toJson());
    return stats;
  }, staleDuration: StaleTime.short);
}

// ── Expertise (service areas) ───────────────────────────────────────────────

/// The host's saved answers. Titles need the interests form (authscreen):
/// `data.titlesFor(questions)`.
QueryResult<ExpertiseSelections, ApiException> useMyExpertise(
  BuildContext context, {
  bool enabled = true,
}) => useApiQuery<ExpertiseSelections>(
  HostHubKeys.expertise,
  ExpertiseApi.fetchMine,
  context: context,
  enabled: enabled,
  staleDuration: StaleTime.short,
);

Future<ExpertiseSelections> ensureMyExpertise() =>
    queryCache.fetchQuery<ExpertiseSelections>(
      HostHubKeys.expertise,
      ExpertiseApi.fetchMine,
    );

/// Build [ExpertiseSave.selections] with `ExpertiseQuestions.draft` so the
/// hidden-but-required questions carry their default answer.
MutationResult<ExpertiseSaveResult, ApiException, ExpertiseSave>
useSaveMyExpertise({
  void Function(ExpertiseSaveResult result)? onSuccess,
  void Function(ApiException error)? onError,
}) => useApiMutation<ExpertiseSaveResult, ExpertiseSave>(
  (v) => ExpertiseApi.save(v.selections, source: v.source),
  // service_area_selections is populated on the profile.
  invalidates: [HostHubKeys.expertise, HostHubKeys.profileAll],
  onSuccess: (result, _) => onSuccess?.call(result),
  onError: (e, _) => onError?.call(e),
);
