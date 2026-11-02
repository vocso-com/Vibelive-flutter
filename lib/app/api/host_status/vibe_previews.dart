import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart' show Size;
import 'package:path_provider/path_provider.dart';

import '../../../core/utils/log.dart';
import 'vibe_frames.dart';
import 'vibe_video_cache.dart';

/// A still for Home circles whose Vibe came without one (posted before
/// thumbnails existed, or a server that does not send them yet): taken on
/// this phone from the clip itself, the steadiest frame ([VibeFrames]).
///
/// The clip comes from [VibeVideoCache], so making the preview also makes
/// playing it instant — nothing is downloaded twice. Each still is kept on
/// disk by Vibe id and made once; two at a time.
abstract final class VibePreviews {
  /// Stills made so far, by Vibe documentId. Circles listen to this.
  static final ValueNotifier<Map<String, File>> files = ValueNotifier(
    const {},
  );

  /// Tests switch it off (no file system or video decoder there).
  @visibleForTesting
  static bool enabled = true;

  static final _queue = <(String, String)>[];
  static final _busy = <String>{};
  static const _parallel = 2;

  /// The still for Vibe [id], if made.
  static File? of(String id) => files.value[id];

  /// Makes the still for Vibe [id] from [videoUrl], unless it exists or is
  /// underway.
  static void request(String id, String videoUrl) {
    if (!enabled || id.isEmpty || videoUrl.isEmpty) return;
    if (files.value.containsKey(id) || _busy.contains(id)) return;
    if (_queue.any((q) => q.$1 == id)) return;
    _queue.add((id, videoUrl));
    _pump();
  }

  static void _pump() {
    while (_busy.length < _parallel && _queue.isNotEmpty) {
      final (id, url) = _queue.removeAt(0);
      _busy.add(id);
      unawaited(_make(id, url));
    }
  }

  static Future<void> _make(String id, String url) async {
    try {
      final dir = await getTemporaryDirectory();
      final out = File('${dir.path}/vibe_previews/$id.jpg');
      if (!await out.exists()) {
        final video = await VibeVideoCache.file(url);
        if (video == null) return;
        final bytes = await VibeFrames.best(video, size: const Size(160, 284));
        if (bytes == null || bytes.isEmpty) return;
        await out.create(recursive: true);
        await out.writeAsBytes(bytes, flush: true);
      }
      files.value = {...files.value, id: out};
    } catch (e) {
      Log.d('VibePreview', 'no still for $id: $e');
    } finally {
      _busy.remove(id);
      _pump();
    }
  }
}
