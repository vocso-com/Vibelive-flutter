import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

import '../../../core/network/api_client.dart';
import '../../../core/network/api_exception.dart';
import '../../../core/utils/log.dart';
import '../component/upload_api.dart';
import 'host_status_models.dart';
import 'vibe_frames.dart';

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
    final thumbnail = await _uploadThumbnail(path);
    final body = await ApiClient.post(
      '/host-statuses/mine',
      data: {
        'media': file['id'],
        // The still the Home row shows in this host's circle.
        'thumbnail': ?thumbnail,
        // When it was recorded, not when it finished uploading: both windows
        // are measured from this, so a slow upload must not cost the host part
        // of their day. The server clamps a time in the future.
        if (recordedAt != null)
          'recordedAt': recordedAt.toUtc().toIso8601String(),
      },
    );
    final data = body is Map ? body['data'] : null;
    return HostOwnStatus.fromJson(data);
  }

  /// A JPEG still from the clip (swapped in tests). Null when none could be
  /// made.
  @visibleForTesting
  static Future<Uint8List?> Function(String path) makeThumbnail =
      _middleFrame;

  /// The steadiest of three frames (not black, most detail).
  static Future<Uint8List?> _middleFrame(String path) =>
      VibeFrames.best(File(path));

  /// Uploads the still and returns its media id. Never throws: a Vibe
  /// without a thumbnail still posts (Home shows the host's photo instead).
  static Future<Object?> _uploadThumbnail(String path) async {
    File? temp;
    try {
      final bytes = await makeThumbnail(path);
      if (bytes == null || bytes.isEmpty) return null;
      final dir = await getTemporaryDirectory();
      temp = File(
        '${dir.path}/vibe-thumb-${DateTime.now().millisecondsSinceEpoch}.jpg',
      );
      await temp.writeAsBytes(bytes);
      final up = await UploadApi.uploadFile(
        temp.path,
        fileName: 'status-thumb.jpg',
        mimeType: 'image/jpeg',
      );
      return up['id'];
    } catch (e) {
      Log.w('HostStatus', 'no thumbnail for this Vibe: $e');
      return null;
    } finally {
      final t = temp;
      if (t != null) unawaited(t.delete().then((_) {}, onError: (_) {}));
    }
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

  /// `DELETE /host-statuses/mine/:documentId`: the host deletes one of their
  /// own. Gone for everyone at once; the server only accepts the owner's.
  static Future<void> delete(String documentId) async {
    await ApiClient.delete('/host-statuses/mine/$documentId');
  }

  /// `GET /host-statuses/mine`: the host's own, including what is still in
  /// review and what was turned down.
  static Future<List<HostOwnStatus>> mine() async =>
      HostOwnStatus.listFrom(await ApiClient.get('/host-statuses/mine'));

  /// `GET /host-statuses/feed`: the home row, every host with a live status
  /// (never the signed-in user's own, nor a blocked host).
  static Future<List<StatusGroup>> feed() async =>
      StatusGroup.listFrom(await ApiClient.get('/host-statuses/feed'));

  /// `POST /host-media-views` for any host clip: [kind] `video_intro` /
  /// `status`, [action] `view` / `play` / `complete`.
  static Future<void> recordMediaView({
    required String kind,
    required String action,
    required String hostDocumentId,
    String? statusDocumentId,
  }) async {
    await ApiClient.post(
      '/host-media-views',
      data: {
        'kind': kind,
        'action': action,
        'hostDocumentId': hostDocumentId,
        'statusDocumentId': ?statusDocumentId,
      },
    );
  }

  /// `POST /host-media-views`: this status was watched. Drives the grey ring
  /// for this viewer and the host's view count; the server ignores repeats.
  static Future<void> recordView({
    required String hostDocumentId,
    required String statusDocumentId,
  }) async {
    await ApiClient.post(
      '/host-media-views',
      data: {
        'kind': 'status',
        'action': 'view',
        'hostDocumentId': hostDocumentId,
        'statusDocumentId': statusDocumentId,
      },
    );
  }

  /// `GET /host-statuses/host/:documentId`: what a client may watch for this
  /// host — approved, inside its 24 hours, not purged.
  static Future<List<HostStatus>> forHost(String expertDocumentId) async =>
      HostStatus.listFrom(
        await ApiClient.get('/host-statuses/host/$expertDocumentId'),
      );
}
