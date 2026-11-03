import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:just_audio/just_audio.dart';

import '../../../core/utils/log.dart';

/// One voice note playing at a time, app-wide. A bubble shows "playing"
/// only when [active] is its message; only that bubble listens to
/// [position], so a playing note repaints one bubble, never the list.
class ChatVoicePlayer {
  ChatVoicePlayer._();
  static final ChatVoicePlayer instance = ChatVoicePlayer._();

  /// Swapped in tests (no platform player there).
  @visibleForTesting
  static ChatAudioEngine Function() engine = _JustAudioEngine.new;

  /// Key of the message playing (or loading), null when silent.
  final active = ValueNotifier<String?>(null);
  final position = ValueNotifier<Duration>(Duration.zero);

  ChatAudioEngine? _engine;
  StreamSubscription<Duration>? _pos;
  StreamSubscription<void>? _done;

  /// Plays [key]'s note from [url] or the local [path]; tapping the one
  /// playing stops it. Never throws.
  Future<void> toggle(String key, {String? url, String? path}) async {
    if (active.value == key) return stop();
    await stop();
    if (url == null && path == null) return;
    active.value = key;
    position.value = Duration.zero;
    try {
      final e = _engine ??= engine();
      _pos ??= e.positions.listen((p) => position.value = p);
      _done ??= e.completed.listen((_) => stop());
      await e.play(url: url, path: path);
    } catch (err) {
      Log.w('ChatVoice', 'play failed: $err');
      if (active.value == key) await stop();
    }
  }

  Future<void> stop() async {
    if (active.value == null) return;
    active.value = null;
    position.value = Duration.zero;
    try {
      await _engine?.stop();
    } catch (_) {}
  }

  /// The chat closed: nothing keeps playing behind it.
  Future<void> release() async {
    await stop();
    await _pos?.cancel();
    await _done?.cancel();
    _pos = null;
    _done = null;
    final e = _engine;
    _engine = null;
    try {
      await e?.dispose();
    } catch (_) {}
  }
}

/// The audio player, behind a seam.
abstract class ChatAudioEngine {
  Stream<Duration> get positions;
  Stream<void> get completed;
  Future<void> play({String? url, String? path});
  Future<void> stop();
  Future<void> dispose();
}

class _JustAudioEngine implements ChatAudioEngine {
  final _player = AudioPlayer();

  @override
  Stream<Duration> get positions => _player.positionStream;

  @override
  Stream<void> get completed => _player.playerStateStream
      .where((s) => s.processingState == ProcessingState.completed)
      .map((_) {});

  @override
  Future<void> play({String? url, String? path}) async {
    if (path != null) {
      await _player.setFilePath(path);
    } else {
      await _player.setUrl(url!);
    }
    unawaited(_player.play());
  }

  @override
  Future<void> stop() => _player.stop();

  @override
  Future<void> dispose() => _player.dispose();
}
