import 'dart:async';

import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:video_player/video_player.dart';

import '../../../../core/utils/log.dart';
import '../../../../core/utils/scale.dart';
import '../../../api/hosthub/training_models.dart';
import '../../../callscreen/helper/call_controller.dart';
import '../../../component/c_image.dart';
import '../../../component/c_text.dart';
import '../../../component/pressable.dart';

/// A video from the onboarding training setup: a training step's video or a
/// clip on an onboarding screen. Streams the admin's link; plays while
/// [active], the app is in front and no call is on; tap to pause or play,
/// a speaker to mute, a progress bar (draggable when [allowSeek]).
///
/// [onProgress] reports the furthest point reached; [onCompleted] fires once
/// the video has played to its end (also on a looping one); [onFailed] when
/// it cannot be played at all (bad link, no network).
class TrainingPlayer extends StatefulWidget {
  const TrainingPlayer({
    super.key,
    required this.video,
    this.autoplay = true,
    this.startMuted = false,
    this.loop = false,
    this.active = true,
    this.allowSeek = true,
    this.compact = false,
    this.onProgress,
    this.onCompleted,
    this.onFailed,
  });

  final TrainingVideo video;
  final bool autoplay;
  final bool startMuted;
  final bool loop;

  /// On screen and wanted: plays (when [autoplay], or after a tap). Off: paused.
  final bool active;
  final bool allowSeek;

  /// A clip on a form: smaller controls.
  final bool compact;
  final void Function(Duration furthest, Duration length)? onProgress;
  final VoidCallback? onCompleted;
  final VoidCallback? onFailed;

  @override
  State<TrainingPlayer> createState() => _TrainingPlayerState();
}

class _TrainingPlayerState extends State<TrainingPlayer> {
  VideoPlayerController? _player;
  bool _failed = false;
  bool _away = false;
  late bool _muted = widget.startMuted;

  /// The host paused it: never restarted on its own.
  bool _heldByUser = false;

  /// The host started it (when autoplay is off).
  bool _startedByUser = false;

  /// Played to the end at least once (reported once).
  bool _completed = false;

  /// Sitting at its end (not looping) until played again.
  bool _ended = false;
  Duration _furthest = Duration.zero;
  Duration _last = Duration.zero;
  late final AppLifecycleListener _lifecycle;

  @override
  void initState() {
    super.initState();
    _lifecycle = AppLifecycleListener(
      onHide: () {
        _away = true;
        _sync();
      },
      onShow: () {
        _away = false;
        _sync();
      },
    );
    CallController.instance.onCall.addListener(_sync);
    unawaited(_load());
  }

  @override
  void didUpdateWidget(TrainingPlayer old) {
    super.didUpdateWidget(old);
    if (old.video.url != widget.video.url) {
      _dispose();
      _failed = false;
      _completed = false;
      _ended = false;
      _furthest = Duration.zero;
      unawaited(_load());
    } else if (old.active != widget.active) {
      _sync();
    }
  }

  @override
  void dispose() {
    _lifecycle.dispose();
    CallController.instance.onCall.removeListener(_sync);
    _dispose();
    super.dispose();
  }

  void _dispose() {
    final p = _player;
    _player = null;
    p?.removeListener(_onTick);
    unawaited(p?.dispose());
  }

  Future<void> _load() async {
    final url = widget.video.url;
    final next = VideoPlayerController.networkUrl(
      Uri.parse(url),
      videoPlayerOptions: VideoPlayerOptions(mixWithOthers: true),
    );
    try {
      await next.initialize();
      await next.setLooping(widget.loop);
      await next.setVolume(_muted ? 0 : 1);
    } catch (e) {
      Log.d('TrainingPlayer', 'video unavailable: $e');
      unawaited(next.dispose());
      if (!mounted || url != widget.video.url) return;
      setState(() => _failed = true);
      widget.onFailed?.call();
      return;
    }
    if (!mounted || url != widget.video.url) {
      unawaited(next.dispose());
      return;
    }
    next.addListener(_onTick);
    setState(() => _player = next);
    _sync();
  }

  bool get _wanted =>
      widget.active &&
      !_away &&
      !CallController.instance.isOnCall &&
      !_heldByUser &&
      (widget.autoplay || _startedByUser) &&
      !_ended;

  void _sync() {
    final p = _player;
    if (p == null || !p.value.isInitialized) return;
    if (_wanted) {
      if (!p.value.isPlaying) unawaited(p.play());
    } else if (p.value.isPlaying) {
      unawaited(p.pause());
    }
  }

  void _onTick() {
    final p = _player;
    if (p == null) return;
    final v = p.value;
    if (v.hasError && !_failed) {
      setState(() => _failed = true);
      widget.onFailed?.call();
      return;
    }
    final length = v.duration;
    final pos = v.position;
    if (pos > _furthest) _furthest = pos;
    // Some phones stop a little short of the length (the player's
    // `isCompleted` covers those); a looping video jumps back to the start
    // instead of ending. The position is read every 100 ms.
    final nearEnd =
        length > Duration.zero &&
        pos >= length - const Duration(milliseconds: 300);
    final wrapped =
        widget.loop &&
        _last > const Duration(milliseconds: 500) &&
        pos < _last - const Duration(milliseconds: 500);
    _last = pos;
    final atEnd = wrapped || nearEnd || v.isCompleted;
    if (atEnd) _furthest = length;
    if (atEnd && !widget.loop && !v.isPlaying) _ended = true;
    widget.onProgress?.call(_furthest, length);
    if (!_completed && atEnd) {
      _completed = true;
      widget.onCompleted?.call();
    }
    if (mounted) setState(() {});
  }

  void _toggle() {
    final p = _player;
    if (p == null) return;
    if (p.value.isPlaying) {
      _heldByUser = true;
      unawaited(p.pause());
    } else {
      _heldByUser = false;
      _startedByUser = true;
      // Ended (not looping): from the start again.
      if (_ended) {
        _ended = false;
        unawaited(p.seekTo(Duration.zero));
      }
      unawaited(p.play());
    }
    setState(() {});
  }

  void _toggleMute() {
    setState(() => _muted = !_muted);
    unawaited(_player?.setVolume(_muted ? 0 : 1));
  }

  void _retry() {
    setState(() => _failed = false);
    _dispose();
    unawaited(_load());
  }

  @override
  Widget build(BuildContext context) {
    final p = _player;
    final ready = p != null && p.value.isInitialized;
    final ratio = ready && p.value.aspectRatio > 0
        ? p.value.aspectRatio
        : 16 / 9;
    final playing = ready && p.value.isPlaying;
    final poster = widget.video.posterUrl;
    final icon = widget.compact ? 18.ms : 22.ms;
    return AspectRatio(
      aspectRatio: ratio,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(widget.compact ? 12.ms : 16.ms),
        child: ColoredBox(
          color: Colors.black,
          child: Stack(
            fit: StackFit.expand,
            children: [
              if (ready)
                Pressable(
                  key: const ValueKey('training-player-surface'),
                  onPressed: _toggle,
                  activeOpacity: 1,
                  child: VideoPlayer(p),
                ),
              if (!ready || (!playing && p.value.position == Duration.zero))
                IgnorePointer(
                  ignoring: ready,
                  child: poster != null
                      ? CImage(url: poster, fit: BoxFit.cover)
                      : const SizedBox.shrink(),
                ),
              if (_failed)
                _Failed(onRetry: _retry, compact: widget.compact)
              else if (!ready)
                const Center(
                  child: SizedBox.square(
                    dimension: 26,
                    child: CircularProgressIndicator(
                      strokeWidth: 2.5,
                      color: Colors.white,
                    ),
                  ),
                )
              else if (!playing)
                IgnorePointer(
                  child: Center(
                    child: Container(
                      padding: EdgeInsets.all(widget.compact ? 10.ms : 14.ms),
                      decoration: const BoxDecoration(
                        color: Color(0x88000000),
                        shape: BoxShape.circle,
                      ),
                      child: Icon(
                        LucideIcons.play,
                        color: Colors.white,
                        size: widget.compact ? 22.ms : 30.ms,
                      ),
                    ),
                  ),
                ),
              if (ready && !_failed)
                Positioned(
                  left: 0,
                  right: 0,
                  bottom: 0,
                  child: Container(
                    padding: EdgeInsets.fromLTRB(10.ms, 18.ms, 6.ms, 6.ms),
                    decoration: const BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [Color(0x00000000), Color(0x99000000)],
                      ),
                    ),
                    child: Row(
                      children: [
                        Expanded(
                          child: VideoProgressIndicator(
                            p,
                            allowScrubbing: widget.allowSeek,
                            padding: EdgeInsets.symmetric(vertical: 6.ms),
                            colors: const VideoProgressColors(
                              playedColor: Colors.white,
                              bufferedColor: Color(0x66FFFFFF),
                              backgroundColor: Color(0x33FFFFFF),
                            ),
                          ),
                        ),
                        SizedBox(width: 8.ms),
                        CText.raw(
                          _clock(p.value.position, p.value.duration),
                          size: widget.compact ? 10.5 : 11.5,
                          weight: FontWeight.w700,
                          color: Colors.white,
                        ),
                        Pressable(
                          key: const ValueKey('training-player-mute'),
                          onPressed: _toggleMute,
                          hitPadding: EdgeInsets.all(6.ms),
                          semanticLabel: _muted ? 'Unmute' : 'Mute',
                          child: Padding(
                            padding: EdgeInsets.all(6.ms),
                            child: Icon(
                              _muted
                                  ? LucideIcons.volumeX
                                  : LucideIcons.volume2,
                              color: Colors.white,
                              size: icon,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  static String _clock(Duration pos, Duration length) {
    String f(Duration d) =>
        '${d.inMinutes}:${(d.inSeconds % 60).toString().padLeft(2, '0')}';
    return '${f(pos)} / ${f(length)}';
  }
}

class _Failed extends StatelessWidget {
  const _Failed({required this.onRetry, required this.compact});
  final VoidCallback onRetry;
  final bool compact;

  @override
  Widget build(BuildContext context) => Center(
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(LucideIcons.videoOff, color: Colors.white70, size: 26.ms),
        SizedBox(height: 8.ms),
        CText(
          'hosttraining:video_failed',
          size: compact ? 11.5 : 13,
          weight: FontWeight.w600,
          color: Colors.white70,
          align: TextAlign.center,
        ),
        SizedBox(height: 8.ms),
        Pressable(
          key: const ValueKey('training-player-retry'),
          onPressed: onRetry,
          child: Container(
            padding: EdgeInsets.symmetric(horizontal: 14.ms, vertical: 7.ms),
            decoration: BoxDecoration(
              color: Colors.white24,
              borderRadius: BorderRadius.circular(999),
            ),
            child: const CText(
              'actions.retry',
              size: 12,
              weight: FontWeight.w800,
              color: Colors.white,
            ),
          ),
        ),
      ],
    ),
  );
}
