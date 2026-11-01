import '../../../core/network/api_client.dart';
import '../component/upload_api.dart';
import 'host_status_models.dart';

/// Host statuses: a host's own, and what a client may see for one host.
///
/// Three endpoints, and deliberately not the generic Strapi collection. The
/// server decides visibility per caller — it withholds the file for anything
/// unapproved and leaves expired clips out of the client list — and a
/// `/host-statuses?filters[…]` read from the app would put that decision in
/// the client's hands, where it does not belong.
abstract final class HostStatusApi {
  /// `POST /host-statuses/mine`: post a captured clip.
  ///
  /// Uploads the file first, then records it. Two steps rather than a
  /// multipart post because that is how every other media field in this app
  /// works — the upload returns a media id the record then refers to.
  ///
  /// The server stamps the 24-hour and 7-day windows and forces the review
  /// state; nothing here is trusted to set them.
  static Future<HostOwnStatus?> post({
    required String path,
    DateTime? recordedAt,
  }) async {
    final file = await UploadApi.uploadFile(
      path,
      fileName: 'status-${DateTime.now().millisecondsSinceEpoch}.mp4',
      mimeType: 'video/mp4',
    );
    final body = await ApiClient.post(
      '/host-statuses/mine',
      data: {
        'media': file['id'],
        // When it was recorded, not when it finished uploading: both windows
        // are measured from this, so a slow upload must not cost the host part
        // of their day. The server clamps a time in the future.
        if (recordedAt != null) 'recordedAt': recordedAt.toUtc().toIso8601String(),
      },
    );
    final data = body is Map ? body['data'] : null;
    return HostOwnStatus.fromJson(data);
  }

  /// `GET /host-statuses/mine`: the host's own, including what is still in
  /// review and what was turned down.
  static Future<List<HostOwnStatus>> mine() async =>
      HostOwnStatus.listFrom(await ApiClient.get('/host-statuses/mine'));

  /// `GET /host-statuses/host/:documentId`: what a client may watch for this
  /// host — approved, inside its 24 hours, not purged.
  static Future<List<HostStatus>> forHost(String expertDocumentId) async =>
      HostStatus.listFrom(
        await ApiClient.get('/host-statuses/host/$expertDocumentId'),
      );
}
