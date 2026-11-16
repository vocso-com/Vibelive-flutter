import 'package:flutter/widgets.dart';
import 'package:flutter_hooks/flutter_hooks.dart';

import '../../../core/network/api_client.dart';
import '../../../core/query/query_hooks.dart';
import '../../../core/session/session_store.dart';
import 'profile_models.dart';

/// `GET /call-pricing/mine` (docs/call_pricing.md §5.2): the signed-in
/// user's own fixed earning when backend call pricing applies to them.
///
/// A host reads the same block on their own profile. This is for someone who
/// is not a host yet (onboarding: no profile), so the Call rates step shows
/// the fixed price instead of "set your own rate". An older backend (404) or
/// anything unreadable is [CallPricing.inactive]: the editable step as before.
abstract final class MyCallPricingApi {
  static Future<CallPricing> fetch() async {
    try {
      return CallPricing.from(await ApiClient.get('/call-pricing/mine'));
    } on ApiException catch (e) {
      if (e.statusCode == 404) return CallPricing.inactive;
      rethrow;
    }
  }
}

List<Object> myCallPricingKey([String? userDocumentId]) => [
  'call-pricing',
  'mine',
  userDocumentId ?? SessionStore.instance.value.userDocumentId ?? '',
];

/// [MyCallPricingApi.fetch], cached briefly. Re-read when the admin changes
/// call pricing (CONFIG_UPDATED, scope `call_pricing`) and on resume.
QueryResult<CallPricing, ApiException> useMyCallPricing(
  BuildContext context, {
  bool enabled = true,
}) {
  final session = useValueListenable(SessionStore.instance);
  return useApiQuery<CallPricing>(
    myCallPricingKey(session.userDocumentId),
    MyCallPricingApi.fetch,
    context: context,
    enabled: enabled && session.isAuthenticated,
    staleDuration: StaleTime.short,
  );
}

void invalidateMyCallPricing() => queryCache.invalidateAll(const [
  ['call-pricing', 'mine'],
]);
