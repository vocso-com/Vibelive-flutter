import 'dart:async';

import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:video_player/video_player.dart';

import '../../../core/analytics/events/discover_events.dart';
import '../../../core/utils/log.dart';
import '../../../core/utils/scale.dart';
import '../../api/host_status/host_status_api.dart';
import '../../api/host_status/vibe_video_cache.dart';
import '../../callscreen/helper/call_controller.dart';

/// The host's video intro as the first slide of the profile carousel: plays
/// by itself, loops, with one control — sound on / off. Plays only while it
/// is the slide on screen ([active]), never during a call or with the app in
/// the background. [poster] shows until the first frame is ready.
///
/// Sound starts on (an intro is someone talking); muting is remembered for
/// the rest of the session ([muted]).
class GalleryVideo extends StatefulWidget {
  const GalleryVideo({
    super.key,
    required this.url,
    required this.hostId,
    required this.active,
    this.poster,
  });

  final String url;

  /// Expert-profile documentId (view counts, analytics).
  final String hostId;
  final bool active;
  final Widget? poster;

  /// Sound off, for every profile until the app restarts.
  static final muted = ValueNotifier(false);

  @override
  State<GalleryVideo> createState() => _GalleryVideoState();
}

class _GalleryVideoState extends State<GalleryVideo> {
  VideoPlayerController? _player;
  bool _away = false;
  bool _played = false; // reported once
  bool _completed = false; // first full play reported once
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
    GalleryVideo.muted.addListener(_applyVolume);
    CallController.instance.onCall.addListener(_sync);
    _load();
  }

  @override
  void didUpdateWidget(GalleryVideo old) {
    super.didUpdateWidget(old);
    if (old.url != widget.url) {
      _dispose();
      _load();
    } else if (old.active != widget.active) {
      _sync();
    }
  }

  @override
  void dispose() {
    _lifecycle.dispose();
    GalleryVideo.muted.removeListener(_applyVolume);
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
    final url = widget.url;
    // From the phone when it was played before (shared with Vibes);
    // otherwise streamed, and kept for next time.
    final file = await VibeVideoCache.cached(url);
    if (!mounted || url != widget.url) return;
    if (file == null) VibeVideoCache.prefetch([url]);
    final next = file != null
        ? VideoPlayerController.file(file)
        : VideoPlayerController.networkUrl(Uri.parse(url));
    try {
      await next.initialize();
      await next.setLooping(true);
      await next.setVolume(GalleryVideo.muted.value ? 0 : 1);
    } catch (e) {
      Log.d('GalleryVideo', 'intro unavailable: $e');
      await next.dispose();
      return;
    }
    if (!mounted || url != widget.url) {
      await next.dispose();
      return;
    }
    next.addListener(_onTick);
    setState(() => _player = next);
    _sync();
  }

  bool get _shouldPlay =>
      widget.active && !_away && !CallController.instance.isOnCall;

  void _sync() {
    final p = _player;
    if (p == null || !p.value.isInitialized) return;
    if (_shouldPlay) {
      if (!p.value.isPlaying) unawaited(p.play());
      if (!_played) {
        _played = true;
        _report('play');
        DiscoverEvents.videoIntroAutoplayed(hostId: widget.hostId);
      }
    } else if (p.value.isPlaying) {
      unawaited(p.pause());
    }
  }

  /// One full play: the position jumped back to the start (looped).
  void _onTick() {
    final p = _player;
    if (p == null) return;
    final pos = p.value.position;
    if (!_completed &&
        _last > const Duration(milliseconds: 500) &&
        pos < _last - const Duration(milliseconds: 500)) {
      _completed = true;
      _report('complete');
    }
    _last = pos;
  }

  void _applyVolume() {
    unawaited(_player?.setVolume(GalleryVideo.muted.value ? 0 : 1));
  }

  void _report(String action) {
    unawaited(
      HostStatusApi.recordMediaView(
        kind: 'video_intro',
        action: action,
        hostDocumentId: widget.hostId,
      ).catchError((Object e) => Log.d('GalleryVideo', 'not sent: $e')),
    );
  }

  @override
  Widget build(BuildContext context) {
    final p = _player;
    final ready = p != null && p.value.isInitialized;
    return Stack(
      fit: StackFit.expand,
      children: [
        ?widget.poster,
        AnimatedOpacity(
          opacity: ready ? 1 : 0,
          duration: const Duration(milliseconds: 250),
          child: ready
              ? ClipRect(
                  child: FittedBox(
                    // Fills the slide like the photos; portraits keep the
                    // head.
                    fit: BoxFit.cover,
                    alignment: Alignment.topCenter,
                    child: SizedBox(
                      width: p.value.size.width,
                      height: p.value.size.height,
                      child: VideoPlayer(p),
                    ),
                  ),
                )
              : const SizedBox.shrink(),
        ),
      ],
    );
  }
}

/// Sound on / off: the only control on the video slide.
class GalleryMuteButton extends StatelessWidget {
  const GalleryMuteButton({super.key, required this.hostId});

  final String hostId;

  @override
  Widget build(BuildContext context) => ValueListenableBuilder<bool>(
    valueListenable: GalleryVideo.muted,
    builder: (_, muted, _) => Semantics(
      button: true,
      label: muted ? 'Unmute' : 'Mute',
      child: GestureDetector(
        key: const ValueKey('gallery-video-mute'),
        behavior: HitTestBehavior.opaque,
        onTap: () {
          GalleryVideo.muted.value = !muted;
          DiscoverEvents.videoIntroMuteToggled(hostId: hostId, muted: !muted);
        },
        child: Container(
          width: 38.ms,
          height: 38.ms,
          decoration: const BoxDecoration(
            color: Colors.black45,
            shape: BoxShape.circle,
          ),
          child: Icon(
            muted ? LucideIcons.volumeX : LucideIcons.volume2,
            size: 18.ms,
            color: Colors.white,
          ),
        ),
      ),
    ),
  );
}
