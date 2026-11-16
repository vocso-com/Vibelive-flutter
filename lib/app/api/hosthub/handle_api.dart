import '../../../core/network/api_client.dart';
import '../../../core/network/api_exception.dart';
import '../../../core/network/strapi.dart';
import '../../../core/session/session_store.dart';
import 'strapi_lookup.dart';

/// Whether a handle is free, and a free one close to it when it is not.
typedef HostHandleCheck = ({bool available, String? suggestion});

/// Profile handle (`expert-profiles.handler`) lookups for the onboarding
/// flow.
abstract final class HostHandleApi {
  /// True when no other host uses [handle]. [ownExpertId] (a host editing
  /// their own profile) is not counted as a clash.
  static Future<bool> isAvailable(String handle, {String? ownExpertId}) async =>
      (await check(handle, ownExpertId: ownExpertId)).available;

  /// `GET /me/handle-check`: every profile counts (approved or not, listed or
  /// hidden), the user's own excepted, with a free [HostHandleCheck.suggestion]
  /// when taken. The public list below sees approved, listed hosts only, so a
  /// handle an unapproved profile holds read as free and the submit failed
  /// with "must be unique"; it is kept for an older backend (404).
  static Future<HostHandleCheck> check(
    String handle, {
    String? ownExpertId,
  }) async {
    try {
      final body = Strapi.map(
        await ApiClient.get(
          '/me/handle-check',
          query: {'handle': handle.trim()},
        ),
      );
      if (body != null && body.containsKey('available')) {
        return (
          available: J.boolean(body['available']),
          suggestion: J.str(body['suggestion']),
        );
      }
    } on ApiException catch (e) {
      if (e.statusCode != 404) rethrow;
    }
    return (
      available: await _listSaysFree(handle, ownExpertId: ownExpertId),
      suggestion: null,
    );
  }

  static Future<bool> _listSaysFree(
    String handle, {
    String? ownExpertId,
  }) async {
    final rows = StrapiLookup.rowsOf(
      await ApiClient.get(
        '/expert-profiles',
        query: {
          'filters[handler][\$eqi]': handle.trim(),
          'fields[0]': 'handler',
          'pagination[page]': 1,
          'pagination[pageSize]': 2,
        },
      ),
    );
    final wanted = handle.trim().toLowerCase();
    final own = {
      (ownExpertId ?? '').trim(),
      SessionStore.instance.value.expertDocumentId ?? '',
      SessionStore.instance.value.expertId ?? '',
    }..remove('');
    // Taken = another host whose handle really equals [handle]. Rows that
    // don't match (an ignored filter returns the viewer's own or any
    // profile) and the viewer's own profile never count.
    return !rows.any(
      (row) =>
          (J.str(row['handler']) ?? '').toLowerCase() == wanted &&
          !own.contains(J.str(row['documentId'])) &&
          !own.contains(J.str(row['id'])),
    );
  }
}
