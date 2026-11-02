import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_cache_manager/flutter_cache_manager.dart';

import '../../../core/utils/log.dart';

/// Vibe clips kept on the phone, so a clip watched once (or fetched ahead)
/// starts at once instead of downloading again every time.
///
/// The viewer plays a cached file when there is one and streams otherwise;
/// meanwhile the clips likely to be watched next are fetched in the
/// background ([prefetch]), two at a time. Vibes live a day, so files go
/// stale after two and the cache never holds more than 60.
abstract final class VibeVideoCache {
  static CacheManager? _manager;

  /// Tests switch the cache off (no file system or database there).
  @visibleForTesting
  static bool enabled = true;

  static CacheManager get _m => _manager ??= CacheManager(
    Config(
      'vibe_videos',
      stalePeriod: const Duration(days: 2),
      maxNrOfCacheObjects: 60,
    ),
  );

  static final _inFlight = <String>{};
  static final _queue = <String>[];
  static const _parallel = 2;

  /// The clip on disk, or null (not fetched yet, or the cache unavailable).
  /// Never throws and never waits long: playback must not hang on it.
  static Future<File?> cached(String url) async {
    if (!enabled) return null;
    try {
      final info = await _m
          .getFileFromCache(url)
          .timeout(const Duration(milliseconds: 600));
      final file = info?.file;
      return file != null && await file.exists() ? file : null;
    } catch (e) {
      Log.d('VibeCache', 'lookup failed: $e');
      return null;
    }
  }

  /// The clip on disk, downloading it first when needed (preview stills);
  /// null when it cannot be had.
  static Future<File?> file(String url) async {
    if (!enabled) return null;
    try {
      return await _m.getSingleFile(url);
    } catch (e) {
      Log.d('VibeCache', 'download failed: $e');
      return null;
    }
  }

  /// Fetches [urls] in the background (skips what is cached or underway).
  static void prefetch(Iterable<String> urls) {
    if (!enabled) return;
    for (final url in urls) {
      if (url.isEmpty || _inFlight.contains(url) || _queue.contains(url)) {
        continue;
      }
      _queue.add(url);
    }
    _pump();
  }

  static void _pump() {
    while (_inFlight.length < _parallel && _queue.isNotEmpty) {
      final url = _queue.removeAt(0);
      _inFlight.add(url);
      unawaited(_fetch(url));
    }
  }

  static Future<void> _fetch(String url) async {
    try {
      if (await cached(url) == null) await _m.downloadFile(url);
    } catch (e) {
      Log.d('VibeCache', 'prefetch failed: $e');
    } finally {
      _inFlight.remove(url);
      _pump();
    }
  }
}
