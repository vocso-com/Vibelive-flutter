import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:video_player/video_player.dart';

import '../../../core/analytics/events/discover_events.dart';
import '../../../core/utils/log.dart';
import '../../api/host_status/vibe_video_cache.dart';
import '../../callscreen/helper/call_controller.dart';
import 'card_video_focus.dart';

/// A Discover card's video intro, over its photo: plays muted and looping
/// while the list's [CardVideoFocus] picks this card (the user stopped with
/// it on screen), fading in over the photo; otherwise the photo shows.
///
/// Also still while Discover is not the tab on screen, a sheet or page covers
/// it, a call is on, or the app is in the background. A player unused for
/// [release] is let go (memory, decoders); the file stays cached on the phone
/// (shared with Vibes and the profile's intro), so the next play starts fast.
/// Never takes a tap: the card under it opens the profile as before.
class DiscoverCardVideo extends StatefulWidget {
  const DiscoverCardVideo({super.key, required this.url, required this.hostId});

  final String url;

  /// Expert-profile documentId (analytics).
  final String hostId;

  static const release = Duration(seconds: 10);

  @override
  State<DiscoverCardVideo> createState() => _DiscoverCardVideoState();
}

class _DiscoverCardVideoState extends State<DiscoverCardVideo> {
  final _token = Object();
  CardVideoFocus? _focus;
  VideoPlayerController? _player;
  bool _loading = false;
  bool _showing = false;
  bool _away = false;
  bool _tabOn = true;
  bool _routeOn = true;
  Timer? _release;
  late final AppLifecycleListener _lifecycle;

  /// Hosts whose card played, this run (analytics once each).
  static final _logged = <String>{};

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
    CallController.instance.onCall.addListener(_onChange);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Discover is the tab on screen (the others are TickerMode-off), and no
    // sheet or page is over it.
    _tabOn = TickerMode.valuesOf(context).enabled;
    _routeOn = ModalRoute.of(context)?.isCurrent ?? true;
    final focus = CardVideoScope.maybeOf(context);
    if (focus != _focus) {
      _focus?.removeListener(_onChange);
      _focus?.unregister(_token);
      _focus = focus;
      focus?.addListener(_onChange);
      focus?.register(_token, _box);
    }
    _sync(building: true);
  }

  RenderBox? _box() {
    if (!mounted) return null;
    final r = context.findRenderObject();
    return r is RenderBox ? r : null;
  }

  @override
  void didUpdateWidget(DiscoverCardVideo old) {
    super.didUpdateWidget(old);
    if (old.url != widget.url) {
      _drop();
      _sync();
    }
  }

  @override
  void dispose() {
    _lifecycle.dispose();
    CallController.instance.onCall.removeListener(_onChange);
    _focus?.removeListener(_onChange);
    _focus?.unregister(_token);
    _release?.cancel();
    _drop();
    super.dispose();
  }

  void _onChange() => _sync();

  bool get _shouldPlay =>
      (_focus?.isActive(_token) ?? false) &&
      _tabOn &&
      _routeOn &&
      !_away &&
      !CallController.instance.isOnCall;

  /// [building]: called on the way into build (no setState there).
  void _sync({bool building = false}) {
    if (!mounted) return;
    final p = _player;
    if (_shouldPlay) {
      _release?.cancel();
      if (p == null) {
        unawaited(_load());
        return;
      }
      if (!p.value.isPlaying) unawaited(p.play());
      _show(true, building: building);
      if (_logged.add(widget.hostId)) {
        DiscoverEvents.cardVideoPlayed(hostId: widget.hostId);
      }
    } else {
      if (p != null && p.value.isPlaying) unawaited(p.pause());
      _show(false, building: building);
      if (p != null) {
        _release?.cancel();
        _release = Timer(DiscoverCardVideo.release, () {
          if (mounted && !_shouldPlay) setState(_drop);
        });
      }
    }
  }

  void _show(bool on, {bool building = false}) {
    if (_showing == on) return;
    if (building) {
      _showing = on;
    } else {
      setState(() => _showing = on);
    }
  }

  Future<void> _load() async {
    if (_loading) return;
    _loading = true;
    final url = widget.url;
    try {
      // From the phone when it was played before; otherwise streamed, and
      // kept for next time.
      final file = await VibeVideoCache.cached(url);
      if (!mounted || url != widget.url) return;
      if (file == null) VibeVideoCache.prefetch([url]);
      // Muted, and never pausing the user's music.
      final options = VideoPlayerOptions(mixWithOthers: true);
      final next = file != null
          ? VideoPlayerController.file(file, videoPlayerOptions: options)
          : VideoPlayerController.networkUrl(
              Uri.parse(url),
              videoPlayerOptions: options,
            );
      try {
        await next.initialize();
        await next.setVolume(0);
        await next.setLooping(true);
      } catch (e) {
        Log.d('DiscoverCardVideo', 'intro unavailable: $e');
        await next.dispose();
        return;
      }
      if (!mounted || url != widget.url || _player != null) {
        await next.dispose();
        return;
      }
      setState(() => _player = next);
    } finally {
      _loading = false;
    }
    _sync();
  }

  void _drop() {
    final p = _player;
    _player = null;
    _showing = false;
    if (p != null) unawaited(p.dispose());
  }

  @override
  Widget build(BuildContext context) {
    final p = _player;
    final ready = p != null && p.value.isInitialized;
    return IgnorePointer(
      child: AnimatedOpacity(
        key: const ValueKey('discover-card-video'),
        opacity: ready && _showing ? 1 : 0,
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeOut,
        child: ready
            ? ClipRect(
                child: FittedBox(
                  // Fills the card like its photo; portraits keep the head.
                  fit: BoxFit.cover,
                  alignment: Alignment.topCenter,
                  child: SizedBox(
                    width: p.value.size.width,
                    height: p.value.size.height,
                    child: VideoPlayer(p),
                  ),
                ),
              )
            : const SizedBox.expand(),
      ),
    );
  }
}
