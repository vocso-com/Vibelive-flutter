import 'package:flutter/widgets.dart';
import 'package:flutter_hooks/flutter_hooks.dart';

import '../../../core/query/query_hooks.dart';
import '../../../core/session/session_store.dart';
import '../../../core/utils/log.dart';
import 'training_api.dart';
import 'training_models.dart';

/// The training cache key, per signed-in user (it carries their progress).
List<Object> hostTrainingKey([String? userDocumentId]) => [
  'host-training',
  userDocumentId ?? SessionStore.instance.value.userDocumentId ?? '',
];

/// The training setup and this user's progress, for the onboarding screens
/// (clips). Off while unknown, signed out, or unreadable: the flow is then
/// the app's own, as before.
QueryResult<HostTrainingConfig, ApiException> useHostTraining(
  BuildContext context, {
  bool enabled = true,
}) {
  final session = useValueListenable(SessionStore.instance);
  return useApiQuery<HostTrainingConfig>(
    hostTrainingKey(session.userDocumentId),
    HostTrainingApi.fetch,
    context: context,
    enabled: enabled && session.isAuthenticated,
    staleDuration: StaleTime.short,
  );
}

/// The setup outside widgets (the flow's Continue). Never throws: anything
/// unreadable is "no training", so onboarding is never blocked by it.
Future<HostTrainingConfig> ensureHostTraining({
  Duration staleDuration = StaleTime.short,
}) async {
  final session = SessionStore.instance.value;
  if (!session.isAuthenticated) return HostTrainingConfig.none;
  try {
    return await queryCache.fetchQuery<HostTrainingConfig>(
      hostTrainingKey(session.userDocumentId),
      HostTrainingApi.fetch,
      staleDuration: staleDuration,
    );
  } catch (e) {
    Log.w('HostTraining', 'setup unreadable, onboarding goes on without: $e');
    return HostTrainingConfig.none;
  }
}

/// A step's new progress, into the cached setup (so the flow does not ask
/// for it again).
void setHostTrainingProgress(String stepId, TrainingProgress progress) {
  final key = hostTrainingKey();
  final current = queryCache.entry<HostTrainingConfig>(key)?.data;
  if (current == null) return;
  queryCache.setQueryData<HostTrainingConfig, ApiException>(
    key,
    (_) => current.withProgress(stepId, progress),
  );
}

/// Re-read on next use: the admin changed the setup (CONFIG_UPDATED, scope
/// `host_onboarding`).
void invalidateHostTraining() => queryCache.invalidateAll(const [
  ['host-training'],
]);
