import 'package:flutter/widgets.dart';
import 'package:flutter_hooks/flutter_hooks.dart';

import '../../../core/query/query_hooks.dart';
import '../../../core/session/session_store.dart';
import 'host_status_api.dart';
import 'host_status_models.dart';

/// Query keys, in one place so the post mutation invalidates exactly the lists
/// a new clip changes and nothing else.
RawQueryKey _mineKey(String? user) => ['host-statuses', 'mine', user ?? ''];
RawQueryKey _hostKey(String id) => ['host-statuses', 'host', id];

/// The signed-in host's own statuses: live, in review and turned down.
///
/// Short stale time: a host who has just posted one comes back to this screen
/// expecting to see it, and a reviewer may have decided in the meantime.
QueryResult<List<HostOwnStatus>, ApiException> useMyStatuses(
  BuildContext context,
) {
  final session = useValueListenable(SessionStore.instance);
  return useApiQuery<List<HostOwnStatus>>(
    _mineKey(session.userDocumentId),
    HostStatusApi.mine,
    context: context,
    enabled: session.isAuthenticated && session.isExpert,
    staleDuration: StaleTime.short,
  );
}

/// What a client may watch for one host.
///
/// Statuses expire 24 hours after they were recorded, so this is not worth
/// caching for long: a stale list would offer a clip the server has already
/// stopped serving, and the player would simply fail.
QueryResult<List<HostStatus>, ApiException> useHostStatuses(
  BuildContext context,
  String? expertDocumentId,
) {
  final id = expertDocumentId ?? '';
  return useApiQuery<List<HostStatus>>(
    _hostKey(id),
    () => HostStatusApi.forHost(id),
    context: context,
    enabled: id.isNotEmpty,
    staleDuration: StaleTime.short,
  );
}

/// Post a captured clip.
///
/// Invalidates the host's own list only. A new status is `pending` until a
/// reviewer approves it, so no client list can have changed yet — refreshing
/// those would be work for nothing.
MutationResult<HostOwnStatus?, ApiException, HostStatusDraft> usePostStatus() {
  final session = useValueListenable(SessionStore.instance);
  return useApiMutation<HostOwnStatus?, HostStatusDraft>(
    (draft) => HostStatusApi.post(
      path: draft.path,
      recordedAt: draft.recordedAt,
    ),
    invalidates: [_mineKey(session.userDocumentId)],
  );
}

/// What the post mutation needs: the captured file, and when it was taken.
@immutable
class HostStatusDraft {
  const HostStatusDraft(this.path, {this.recordedAt});
  final String path;
  final DateTime? recordedAt;
}
