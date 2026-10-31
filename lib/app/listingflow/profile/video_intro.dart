import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:video_player/video_player.dart';

import '../../../core/theme/vibe_colors.dart';
import '../../../core/utils/log.dart';
import '../../../core/utils/scale.dart';
import '../../component/c_text.dart';
import '../../component/pressable.dart';

/// "Video intro from {name}": the host's approved clip on their profile.
///
/// Named rather than anonymous on purpose. A bare video on a stranger's profile
/// reads as an advert; "Video intro from Priya" reads as a person introducing
/// themselves, which is the whole job this clip is doing — giving someone a
/// reason to trust the call before they pay for it.
///
/// The player lives only while this is mounted, so closing the profile silences
/// it and it can never carry on under a call. It never autoplays: sound
/// starting by itself on a phone is startling, and the tap is also the signal
/// that someone actually wanted to watch.
///
/// Only ever handed an approved clip — the server withholds the file for
/// anything else, and the listing model checks the status again — so this
/// widget has no notion of moderation state.
class VideoIntro extends StatefulWidget {
  const VideoIntro({
    super.key,
    required this.url,
    required this.hostName,
    this.onTalkNow,
  });

  final String url;

  /// Shown in the label. Falls back to a generic line when empty.
  final String hostName;

  /// Offered once the clip finishes, and only when the host can take a call
  /// right now. Null hides the prompt entirely: suggesting a call to someone
  /// who will not pick up is worse than suggesting nothing.
  final VoidCallback? onTalkNow;

  @override
  State<VideoIntro> createState() => _VideoIntroState();
}

class _VideoIntroState extends State<VideoIntro> {
  VideoPlayerController? _player;
  bool _ended = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _player?.removeListener(_onTick);
    _player?.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final player = VideoPlayerController.networkUrl(Uri.parse(widget.url));
    try {
      await player.initialize();
    } catch (e) {
      // A clip that will not load is simply not shown. The profile is still
      // perfectly usable without it, so there is nothing to tell the viewer.
      Log.d('VideoIntro', 'clip unavailable: $e');
      await player.dispose();
      return;
    }
    if (!mounted) {
      await player.dispose();
      return;
    }
    player.addListener(_onTick);
    setState(() => _player = player);
  }

  void _onTick() {
    final p = _player;
    if (p == null || !p.value.isInitialized) return;
    final done =
        !p.value.isPlaying && p.value.position >= p.value.duration &&
        p.value.duration > Duration.zero;
    if (done != _ended && mounted) setState(() => _ended = done);
  }

  Future<void> _toggle() async {
    final p = _player;
    if (p == null) return;
    if (p.value.isPlaying) {
      await p.pause();
    } else {
      // Replay from the start once it has finished, rather than sitting on the
      // last frame doing nothing when tapped.
      if (_ended) await p.seekTo(Duration.zero);
      await p.play();
    }
    if (mounted) setState(() => _ended = false);
  }

  @override
  Widget build(BuildContext context) {
    final player = _player;
    if (player == null) return const SizedBox.shrink();

    final c = context.colors;
    return Padding(
      padding: EdgeInsets.only(top: 12.ms),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          CText(
            widget.hostName.trim().isEmpty
                ? 'listing:video_intro.title_generic'
                : 'listing:video_intro.title',
            variables: {'name': widget.hostName.trim()},
            size: 11,
            weight: FontWeight.w800,
            color: c.textMuted,
          ),
          SizedBox(height: 6.ms),
          ClipRRect(
            borderRadius: BorderRadius.circular(14.ms),
            child: AspectRatio(
              aspectRatio: player.value.aspectRatio,
              child: Stack(
                alignment: Alignment.center,
                children: [
                  VideoPlayer(player),
                  Pressable(
                    onPressed: _toggle,
                    child: Container(
                      padding: EdgeInsets.all(13.ms),
                      decoration: const BoxDecoration(
                        color: Colors.black54,
                        shape: BoxShape.circle,
                      ),
                      child: Icon(
                        player.value.isPlaying
                            ? LucideIcons.pause
                            : LucideIcons.play,
                        size: 20.ms,
                        color: Colors.white,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          // Only after they have watched it, and only when the host is actually
          // reachable: the moment someone has just heard a voice is when a call
          // is worth suggesting, and never before.
          if (_ended && widget.onTalkNow != null)
            Padding(
              padding: EdgeInsets.only(top: 8.ms),
              child: Pressable(
                onPressed: widget.onTalkNow,
                child: Container(
                  padding: EdgeInsets.symmetric(
                    horizontal: 16.ms,
                    vertical: 11.ms,
                  ),
                  decoration: BoxDecoration(
                    color: c.accent,
                    borderRadius: BorderRadius.circular(12.ms),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(LucideIcons.phone, size: 16.ms, color: c.onAccent),
                      SizedBox(width: 8.ms),
                      Flexible(
                        child: CText(
                          'listing:video_intro.talk_now',
                          size: 13,
                          weight: FontWeight.w800,
                          color: c.onAccent,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
