import 'package:flutter/widgets.dart';
import 'package:flutter_hooks/flutter_hooks.dart';

import '../../../core/query/query_hooks.dart';
import '../../../core/session/session_store.dart';
import 'free_call_api.dart';
import 'free_call_models.dart';

/// The free-call status cache key, per signed-in user.
List<Object> freeCallKey([String? userDocumentId]) => [
  'free-call',
  'status',
  userDocumentId ?? SessionStore.instance.value.userDocumentId ?? '',
];

/// Whether the signed-in user has a free call now (docs/free_calls.md). Off
/// while unknown. Read again when the app comes back to the foreground, when
/// the admin changes the settings (CONFIG_UPDATED, scope `free_call`) and
/// after every call ([invalidateFreeCallStatus]).
QueryResult<FreeCallStatus, ApiException> useFreeCallStatus(
  BuildContext context,
) {
  final session = useValueListenable(SessionStore.instance);
  final result = useApiQuery<FreeCallStatus>(
    freeCallKey(session.userDocumentId),
    FreeCallApi.fetchStatus,
    context: context,
    enabled: session.isAuthenticated,
    staleDuration: StaleTime.short,
  );
  final refetch = useRef(result.refetch)..value = result.refetch;
  useOnAppLifecycleStateChange((_, state) {
    if (state == AppLifecycleState.resumed && session.isAuthenticated) {
      refetch.value();
    }
  });
  return result;
}

/// The status outside widgets (the pre-call check). Cached for a short
/// while; off when signed out or unreadable.
Future<FreeCallStatus> ensureFreeCallStatus({
  Duration staleDuration = StaleTime.short,
}) async {
  final session = SessionStore.instance.value;
  if (!session.isAuthenticated) return FreeCallStatus.off;
  try {
    return await queryCache.fetchQuery<FreeCallStatus>(
      freeCallKey(session.userDocumentId),
      FreeCallApi.fetchStatus,
      staleDuration: staleDuration,
    );
  } catch (_) {
    return FreeCallStatus.off;
  }
}

/// Re-read on next use: the admin changed the settings, or a call ended (it
/// may have used the free call).
void invalidateFreeCallStatus() => queryCache.invalidateAll(const [
  ['free-call'],
]);
