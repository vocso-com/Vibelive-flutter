import '../../../core/network/api_client.dart';
import '../../../core/network/api_exception.dart';
import '../../../core/network/strapi.dart';
import 'free_call_models.dart';

abstract final class FreeCallApi {
  /// `GET /free-call/status`: whether the signed-in user has a free call now
  /// (docs/free_calls.md). Off on any failure (an older server has no such
  /// route): the app then prices and gates calls exactly as before.
  static Future<FreeCallStatus> fetchStatus() async {
    try {
      final body = Strapi.map(await ApiClient.get('/free-call/status'));
      return body == null ? FreeCallStatus.off : FreeCallStatus.fromJson(body);
    } on ApiException {
      return FreeCallStatus.off;
    }
  }
}
