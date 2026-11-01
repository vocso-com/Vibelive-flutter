import '../../../core/network/api_client.dart';
import '../../../core/network/api_exception.dart';
import '../component/upload_api.dart';
import 'host_status_models.dart';

/// Translated copy for the refusals a host can actually do something about.
abstract final class HostStatusErrorKeys {
  /// Not switched on yet. Nothing for the host to do but wait.
  static const disabled = 'hostflow:status_errors.disabled';

  /// They have used today's allowance. Different from off: come back tomorrow.
  static const dailyLimit = 'hostflow:status_errors.daily_limit';

  /// The clip runs past the configured limit.
  static const tooLong = 'hostflow:status_errors.too_long';

  /// Anything else that went wrong while posting.
  static const postFailed = 'hostflow:status_errors.post_failed';
}

/// The server's `code`, wherever the error envelope put it.
String? _codeOf(ApiException e) {
  final data = e.data;
  if (data is! Map) return null;
  final error = data['error'];
  final details = error is Map ? error['details'] : null;
  final code =
      (details is Map ? details['code'] : null) ??
      (error is Map ? error['code'] : null) ??
      data['code'];
  return code is String ? code.toLowerCase() : null;
}

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

  /// Our own translated key for a refusal the host can act on, or null when
  /// there is nothing better to say than the generic failure.
  ///
  /// Matched on the server's `code` first and its wording second, because the
  /// mapping shipped after the server did and an older build sends no code.
  /// A server FAULT is deliberately not mapped: a 500 is ours to fix, and
  /// telling a host "not switched on" would send them away from a feature that
  /// is working.
  static String? knownErrorKey(ApiException e) {
    final m = (e.serverMessage ?? '').toLowerCase();
    final code = _codeOf(e) ?? '';

    if (code == 'daily_limit' ||
        m.contains('a day') ||
        m.contains('try again tomorrow')) {
      return HostStatusErrorKeys.dailyLimit;
    }
    if (code == 'too_long' || m.contains('too long')) {
      return HostStatusErrorKeys.tooLong;
    }
    // Everything else forbidden reads as "not switched on", which is both the
    // likeliest reason and the least alarming thing to say.
    if (code == 'disabled' ||
        e.type == ApiErrorType.forbidden ||
        m.contains('not switched on') ||
        m.contains('disabled')) {
      return HostStatusErrorKeys.disabled;
    }
    return null;
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
