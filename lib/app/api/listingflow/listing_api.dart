import '../../../core/network/api_client.dart';
import '../../../core/network/api_exception.dart';
import '../../../core/network/strapi.dart';
import '../../../core/session/session_store.dart';
import '../hosthub/profile_api.dart';
import '../hosthub/strapi_lookup.dart';
import 'listing_models.dart';

/// Reading other hosts' expert profiles. Single-host reads go through the
/// filtered LIST endpoint: `GET /expert-profiles/:documentId` can 404 on
/// this backend.
abstract final class ListingApi {
  /// Everything [HostCard] reads: the Discover feed, Popular, search and
  /// deep-link profiles all use it. `host_profile_images` feeds the gallery
  /// carousel; without it the card falls back to the single profile pic.
  static const hostCardPopulate = <String, dynamic>{
    'populate[user][populate][profilePic]': 'true',
    'populate[user][populate][district]': 'true',
    'populate[rates]': 'true',
    'populate[language]': 'true',
    'populate[durations]': 'true',
    'populate[expert_verifications]': 'true',
    'populate[service_area_selections]': 'true',
    'populate[audio_intro]': 'true',
    // The server withholds the file itself until a reviewer approves it, so an
    // unapproved clip arrives as null rather than being filtered out here.
    'populate[video_intro]': 'true',
    'populate[host_profile_images][populate][image]': 'true',
  };

  static const _singleRow = <String, dynamic>{
    'pagination[page]': '1',
    'pagination[pageSize]': '1',
  };

  /// Only what this lookup is proven to accept here: extra populate keys
  /// (gallery, categories, service areas) return "400 Invalid key".
  static const _callbackPopulate = <String, dynamic>{
    'populate[rates]': 'true',
    'populate[user][populate][profilePic]': 'true',
    'pagination[pageSize]': '1',
  };

  static const _unavailable = ApiException(
    ApiErrorType.rejected,
    messageKey: 'listing:errors.profile_unavailable',
  );

  /// Host listing with extra Strapi params in [query] (flat bracket keys,
  /// e.g. `{'filters[isActive][\$eq]': 'true'}`).
  static Future<List<HostCard>> fetchHosts({
    Map<String, dynamic> query = const {},
  }) async {
    final body = await ApiClient.get(
      '/expert-profiles',
      query: {
        'populate[user][populate]': 'profilePic',
        'populate[service_area_selections]': 'true',
        ...query,
      },
    );
    final rows = Strapi.list(body);
    return [
      for (var i = 0; i < rows.length; i++)
        HostCard.fromJson(rows[i], index: i),
    ];
  }

  /// Full cards of many hosts in ONE read (never one request per row), by
  /// expert-profile documentIds or, with [byUser], user documentIds: search
  /// hits, call-log counterparts, favourites. Hosts the public list hides
  /// (pending approval) are simply missing.
  static Future<List<HostCard>> fetchCards(
    List<String> ids, {
    bool byUser = false,
  }) async {
    if (ids.isEmpty) return const [];
    final field = byUser ? 'filters[user][documentId]' : 'filters[documentId]';
    final rows = await _rows(
      {for (var i = 0; i < ids.length; i++) '$field[\$in][$i]': ids[i]},
      {...hostCardPopulate, 'pagination[pageSize]': ids.length},
    );
    return [
      for (var i = 0; i < rows.length; i++)
        HostCard.fromJson(rows[i], index: i),
    ];
  }

  /// Full profile for a search hit: by expert-profile documentId (what
  /// `/search` carries), then user documentId, then handler. One of the two
  /// ids is required; [handler] is only the last rung.
  static Future<HostCard> findHost({
    String? expertDocumentId,
    String? userDocumentId,
    String? handler,
  }) {
    // Every row is checked against the id it was looked up by: taking the
    // first row blindly opened a different host whenever the backend
    // ignored a filter (search tapped one host, another one opened).
    return findProfile(
      expertDocumentId: expertDocumentId,
      userDocumentId: userDocumentId,
      handler: handler,
    );
  }

  /// Profile behind a shared link / `openUserId`: [targetId] may be a user
  /// documentId, a numeric user id, an expert-profile documentId or a
  /// handler. See [findProfile].
  static Future<HostCard> findHostByLink(
    String targetId, {
    String? ownUserDocumentId,
  }) {
    final target = targetId.trim();
    if (target.isEmpty) throw _unavailable;
    final numeric = StrapiLookup.isNumericId(target);
    return findProfile(
      userDocumentId: numeric ? null : target,
      userId: numeric ? target : null,
      expertDocumentId: numeric ? null : target,
      handler: target,
      ownUserDocumentId: ownUserDocumentId,
    );
  }

  /// The host profile to open from a call-log row, a link or a nudge. Any
  /// host opens (approved or not: the list is the gate, not the client).
  /// Lookups, in order: user documentId, expert-profile documentId, numeric
  /// user id, handler; each row must match what it was looked up by (a
  /// backend that ignores a filter returns everyone). [ownUserDocumentId]
  /// (the viewer's own profile) goes through the owner lookup first: the
  /// public list hides a profile that is still pending approval.
  static Future<HostCard> findProfile({
    String? userDocumentId,
    String? userId,
    String? expertDocumentId,
    String? handler,
    String? ownUserDocumentId,
  }) async {
    final own = ownUserDocumentId?.trim() ?? '';
    if (own.isNotEmpty) {
      final mine = await _ownProfile(own);
      if (mine != null) return mine;
    }
    String? clean(String? v) => (v?.trim().isEmpty ?? true) ? null : v!.trim();
    final userDoc = clean(userDocumentId), expertDoc = clean(expertDocumentId);
    final handle = clean(handler)?.toLowerCase();
    final user = clean(userId);
    final uid = user != null && StrapiLookup.isNumericId(user) ? user : null;

    String? low(Object? v) => J.str(v)?.toLowerCase();
    JsonMap userOf(JsonMap row) => Strapi.map(row['user']) ?? const {};
    final lookups = <(Map<String, dynamic>, bool Function(JsonMap))>[
      if (userDoc != null)
        (
          {r'filters[user][documentId][$eq]': userDoc},
          (r) => low(userOf(r)['documentId']) == userDoc.toLowerCase(),
        ),
      if (expertDoc != null)
        (
          {r'filters[documentId][$eq]': expertDoc},
          (r) => low(r['documentId']) == expertDoc.toLowerCase(),
        ),
      if (uid != null)
        (
          {r'filters[user][id][$eq]': uid},
          (r) => J.str(userOf(r)['id']) == uid,
        ),
      if (handle != null)
        (
          {r'filters[handler][$eq]': handler!.trim()},
          (r) => low(r['handler']) == handle,
        ),
    ];
    for (final (filter, matches) in lookups) {
      final row = (await _profileRows(filter)).where(matches).firstOrNull;
      if (row == null) continue;
      final host = HostCard.fromJson(row);
      if (host.userDocumentId != null ||
          host.documentId != null ||
          host.receiverId != null) {
        return host;
      }
    }
    throw _unavailable;
  }

  /// The viewer's own profile through the owner lookup (Host Hub's read),
  /// with the session user as its `user` when the row carries none.
  static Future<HostCard?> _ownProfile(String userDocumentId) async {
    final mine = await HostProfileApi.fetchByUser(userDocumentId);
    if (mine == null) return null;
    final row = {...mine.raw};
    if (Strapi.map(row['user']) == null) {
      final user = SessionStore.instance.value.user;
      if (user != null) row['user'] = user;
    }
    return HostCard.fromJson(row);
  }

  /// One profile row for [filter] with everything the sheet reads; a
  /// populate the role may not read ("400 Invalid key") retries with the
  /// minimal one the callback lookup is proven with.
  static Future<List<JsonMap>> _profileRows(Map<String, dynamic> filter) async {
    try {
      return await _rows(filter, const {...hostCardPopulate, ..._singleRow});
    } on ApiException catch (e) {
      if (e.type != ApiErrorType.rejected) rethrow;
      return _rows(filter, _callbackPopulate);
    }
  }

  /// Host of a "call me back" nudge (`PING_CLIENT` push): by expert-profile
  /// documentId, then by user id. The push carries no prices, so callers
  /// read [HostCard.aPrice] / [HostCard.vPrice] here and fall back to the
  /// push values when this fails.
  static Future<HostCard> findCallbackHost({
    String? expertDocumentId,
    String? userId,
  }) =>
      // Validated rows only (a first row taken blindly could be another
      // host when a filter is ignored).
      findProfile(expertDocumentId: expertDocumentId, userId: userId);

  /// Counts a profile open (the sheet renders from list data, so the
  /// server's GET-based counter never saw one). The server drops self-views
  /// and same-day repeats.
  static Future<void> trackProfileView(String expertDocumentId) async {
    await ApiClient.post(
      '/expert-profiles/${Uri.encodeComponent(expertDocumentId)}/view',
    );
  }

  static Future<List<JsonMap>> _rows(
    Map<String, dynamic> filter,
    Map<String, dynamic> query,
  ) async => Strapi.list(
    await ApiClient.get('/expert-profiles', query: {...filter, ...query}),
  );
}
