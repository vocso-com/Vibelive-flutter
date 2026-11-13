import '../../../core/network/api_client.dart';
import '../../../core/network/api_exception.dart';
import '../../../core/network/strapi.dart';
import 'moderation_models.dart';

/// The signed-in host's messages from the moderation team, newest first.
abstract final class HostModerationApi {
  static Future<List<HostModerationMessage>> fetchMine() async {
    final dynamic body;
    try {
      body = await ApiClient.get('/me/moderation-notes');
    } on ApiException catch (e) {
      // A backend without the endpoint yet, or no host profile: no messages.
      if (e.statusCode == 404) return const [];
      rethrow;
    }
    return [
      for (final row in Strapi.list(Strapi.map(body)?['results']))
        HostModerationMessage.from(row),
    ];
  }

  /// The host's X on a plain message: closed for good, on every device.
  static Future<void> dismiss(int id) =>
      ApiClient.post('/me/moderation-notes/$id/dismiss');
}
