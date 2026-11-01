import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:video_player/video_player.dart';

import '../../../core/utils/log.dart';
import '../../../core/utils/scale.dart';
import '../../component/c_text.dart';
import '../../component/pressable.dart';

/// Full-screen status playback: one clip at a time, swipe or auto-advance to
/// the next, tap to pause.
///
/// Shared by the client watching a host's statuses and the host checking their
/// own, because it is the same thing in both cases — the clip, full bleed, with
/// a way out. Only the list differs.
///
/// One controller at a time. Statuses are videos and a handful of initialised
/// players would hold several decoders open on a cheap Android phone, which is
/// the device most of this audience has; the page that is on screen owns the
/// only player and disposes it on the way out.
class StatusViewer extends StatefulWidget {
  const StatusViewer({
    super.key,
    required this.urls,
    required this.title,
    this.initialIndex = 0,
  });

  /// Playable clip URLs, newest first — the order the server returns.
  final List<String> urls;

  /// Whose statuses these are, shown along the top.
  final String title;

  final int initialIndex;

  /// Opens the viewer. Returns when it is closed.
  static Future<void> open(
    BuildContext context, {
    required List<String> urls,
    required String title,
    int initialIndex = 0,
  }) {
    if (urls.isEmpty) return Future.value();
    return Navigator.of(context).push(
      MaterialPageRoute(
        fullscreenDialog: true,
        builder: (_) => StatusViewer(
          urls: urls,
          title: title,
          initialIndex: initialIndex,
        ),
      ),
    );
  }

  @override
  State<StatusViewer> createState() => _StatusViewerState();
}

class _StatusViewerState extends State<StatusViewer> {
  late final PageController _pages = PageController(
    initialPage: widget.initialIndex,
  );
  late int _index = widget.initialIndex;

  VideoPlayerController? _player;
  bool _failed = false;

  @override
  void initState() {
    super.initState();
    _load(_index);
  }

  @override
  void dispose() {
    _pages.dispose();
    _player?.removeListener(_onTick);
    _player?.dispose();
    super.dispose();
  }

  Future<void> _load(int index) async {
    final previous = _player;
    _player = null;
    _failed = false;
    previous?.removeListener(_onTick);
    await previous?.dispose();
    if (!mounted) return;
    setState(() {});

    if (index < 0 || index >= widget.urls.length) return;
    final next = VideoPlayerController.networkUrl(Uri.parse(widget.urls[index]));
    try {
      await next.initialize();
    } catch (e) {
      Log.d('StatusViewer', 'clip unavailable: $e');
      await next.dispose();
      // A clip that will not load does not strand the viewer on a black
      // screen: it says so, and the next one is still a swipe away.
      if (mounted) setState(() => _failed = true);
      return;
    }
    if (!mounted) {
      await next.dispose();
      return;
    }
    next.addListener(_onTick);
    await next.play();
    if (mounted) setState(() => _player = next);
  }

  void _onTick() {
    final p = _player;
    if (p == null || !p.value.isInitialized) return;
    final done =
        p.value.duration > Duration.zero && p.value.position >= p.value.duration;
    if (!done) return;
    // Straight on to the next, like every other status viewer; the last one
    // closes, because sitting on a finished clip is a dead end.
    if (_index < widget.urls.length - 1) {
      _pages.nextPage(
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeOut,
      );
    } else if (mounted) {
      Navigator.of(context).maybePop();
    }
  }

  Future<void> _toggle() async {
    final p = _player;
    if (p == null) return;
    p.value.isPlaying ? await p.pause() : await p.play();
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final player = _player;
    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: Stack(
          children: [
            PageView.builder(
              controller: _pages,
              itemCount: widget.urls.length,
              onPageChanged: (i) {
                setState(() => _index = i);
                _load(i);
              },
              itemBuilder: (_, i) {
                if (i != _index) {
                  // Off-screen pages stay empty: only the visible one holds a
                  // decoder.
                  return const SizedBox.shrink();
                }
                if (_failed) {
                  return const Center(
                    child: CText(
                      'listing:status.unavailable',
                      size: 13,
                      color: Colors.white70,
                    ),
                  );
                }
                if (player == null) {
                  return const Center(
                    child: CircularProgressIndicator(color: Colors.white),
                  );
                }
                return Center(
                  child: Pressable(
                    onPressed: _toggle,
                    child: AspectRatio(
                      aspectRatio: player.value.aspectRatio,
                      child: Stack(
                        alignment: Alignment.center,
                        children: [
                          VideoPlayer(player),
                          if (!player.value.isPlaying)
                            Icon(
                              LucideIcons.play,
                              size: 46.ms,
                              color: Colors.white70,
                            ),
                        ],
                      ),
                    ),
                  ),
                );
              },
            ),
            Positioned(
              top: 8.ms,
              left: 12.ms,
              right: 12.ms,
              child: Row(
                children: [
                  // One segment per clip, the current one filled: the only
                  // cue to how many are left.
                  for (var i = 0; i < widget.urls.length; i++)
                    Expanded(
                      child: Container(
                        height: 3.ms,
                        margin: EdgeInsets.symmetric(horizontal: 2.ms),
                        decoration: BoxDecoration(
                          color: i <= _index ? Colors.white : Colors.white24,
                          borderRadius: BorderRadius.circular(2.ms),
                        ),
                      ),
                    ),
                ],
              ),
            ),
            Positioned(
              top: 20.ms,
              left: 14.ms,
              right: 14.ms,
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      widget.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 13.ms,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  Pressable(
                    onPressed: () => Navigator.of(context).maybePop(),
                    child: Padding(
                      padding: EdgeInsets.all(6.ms),
                      child: Icon(LucideIcons.x, size: 22.ms, color: Colors.white),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
