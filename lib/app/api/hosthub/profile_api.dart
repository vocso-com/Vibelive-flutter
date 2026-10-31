import '../../../core/network/api_client.dart';
import '../../../core/network/api_exception.dart';
import '../../../core/network/strapi.dart';
import 'profile_models.dart';
import 'strapi_lookup.dart';

/// The host's own `/expert-profiles` record. Raw calls only: use the hooks
/// in `hosthub_queries.dart`.
abstract final class HostProfileApi {
  /// Relations every host screen reads.
  static const populate = <String, dynamic>{
    'populate[audio_intro]': 'true',
    'populate[video_intro]': 'true',
    'populate[language]': 'true',
    'populate[rates]': 'true',
    'populate[durations]': 'true',
    'populate[schedule][populate][0]': 'timeSlots',
    'populate[expert_profile_approvals]': 'true',
    'populate[expert_verifications]': 'true',
    'populate[service_area_selections]': 'true',
    'populate[host_profile_images][populate][image]': 'true',
  };

  /// Null when the record cannot be found even through the fallbacks.
  /// [ownerUserDocumentId] (the signed-in user) enables the last fallback.
  static Future<HostProfile?> fetchById(
    String expertId, {
    String? ownerUserDocumentId,
  }) async {
    // GET /expert-profiles/:id always answers 404 on this backend, and the
    // list hides unapproved profiles: for the signed-in host, the owner
    // lookup is the one read that finds it, so it goes first (1 request
    // instead of 3).
    final owner = ownerUserDocumentId;
    if (owner != null && owner.isNotEmpty) {
      final mine = await fetchByUser(owner);
      if (mine != null && mine.isSameRecord(expertId)) return mine;
    }
    final row = await StrapiLookup.fetchLatest(
      '/expert-profiles',
      StrapiLookup.ownIdFilters(expertId),
      query: populate,
    );
    final found = HostProfile.from(row);
    // Signed in, the list can answer with the viewer's personalized feed,
    // filter ignored (its first host): never take that for this record.
    return found != null && found.isSameRecord(expertId) ? found : null;
  }

  /// The host profile owned by a user (null for a non-host, or when the
  /// answer is someone else's: see [fetchById]).
  static Future<HostProfile?> fetchByUser(String userDocumentId) async {
    final row = await StrapiLookup.fetchLatest(
      '/expert-profiles',
      StrapiLookup.relationFilters('user', userDocumentId),
      query: {...populate, 'populate[user][fields][0]': 'documentId'},
    );
    final owner = J.str(Strapi.map(Strapi.map(row)?['user'])?['documentId']);
    return owner == userDocumentId ? HostProfile.from(row) : null;
  }

  /// The created record; throws when the response carries none.
  static Future<HostProfile> create(JsonMap data) async {
    final created = HostProfile.fromResponse(
      await ApiClient.post('/expert-profiles', data: {'data': data}),
    );
    if (created == null) {
      throw const ApiException(
        ApiErrorType.parse,
        messageKey: 'hosthub:errors.create_profile_failed',
      );
    }
    return created;
  }

  /// The PUT response (relations not populated).
  static Future<HostProfile?> update(String expertId, JsonMap data) async {
    try {
      return HostProfile.fromResponse(
        await ApiClient.put(
          '/expert-profiles/${Uri.encodeComponent(expertId)}',
          data: {'data': data},
        ),
      );
    } on ApiException catch (e) {
      if (e.statusCode != 404 || StrapiLookup.isNumericId(expertId)) rethrow;
      // Some backend routes accept the numeric id only: resolve it from the
      // documentId and retry once.
      final rows = StrapiLookup.rowsOf(
        await ApiClient.get(
          '/expert-profiles',
          query: {
            'filters[documentId][\$eq]': expertId,
            'pagination[page]': 1,
            'pagination[pageSize]': 1,
          },
        ),
      );
      final numericId = rows.isEmpty ? null : J.str(rows.first['id']);
      if (numericId == null) rethrow;
      return HostProfile.fromResponse(
        await ApiClient.put(
          '/expert-profiles/$numericId',
          data: {'data': data},
        ),
      );
    }
  }
}
