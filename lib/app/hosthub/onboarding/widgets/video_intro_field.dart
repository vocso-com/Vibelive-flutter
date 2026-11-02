import 'dart:io';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:vibe_camera/vibe_camera.dart';
import 'package:video_player/video_player.dart';

import '../../../../core/theme/vibe_colors.dart';
import '../../../../core/utils/log.dart';
import '../../../../core/utils/scale.dart';
import '../../../component/c_text.dart';
import '../../../component/c_toast.dart';
import '../../../component/pressable.dart';
import '../../../api/paymentscreen/runtime_config_queries.dart';
import '../../../callscreen/call/helper/call_permission_state.dart';
import '../../approved/widgets/status_capture.dart' show vibeCameraStrings;
import '../helper/draft_controller.dart';
import '../helper/draft_models.dart';
import '../helper/host_palette.dart';

/// The video intro: one tile that opens the app's own camera (the one Vibes
/// use: looks, light, trim, crop, text), then plays back the clip with
/// Re-record and Discard under it.
///
/// Recorded in the app or picked from the phone's gallery: either way it goes
/// through the same editor and is trimmed to the admin's limit there, and a
/// reviewer approves it before any client sees it.
///
/// Optional by construction. [HostValidation] does not ask for a video intro,
/// so a host who skips it is never blocked.
class HostVideoIntroField extends StatefulWidget {
  const HostVideoIntroField({super.key, required this.draft});
  final HostDraftController draft;

  @override
  State<HostVideoIntroField> createState() => _HostVideoIntroFieldState();
}

class _HostVideoIntroFieldState extends State<HostVideoIntroField> {
  /// The server's limit, falling back to the shipped one.
  ///
  /// Read rather than hardcoded because the admin can change it, and the two
  /// drifting apart means either a host is cut off early or records something
  /// the server then rejects for being too long.
  Duration get _max {
    final seconds = currentRuntimeConfig().hostMedia.videoIntroMaxSeconds;
    return seconds > 0
        ? Duration(seconds: seconds.round())
        : const Duration(seconds: HostVideoIntro.maxSeconds);
  }

  VideoPlayerController? _player;

  /// The clip the current [_player] was built for, so a rebuild that has not
  /// changed the clip does not tear down a playing video.
  String? _playerFor;

  @override
  void dispose() {
    _player?.dispose();
    super.dispose();
  }

  /// Builds (or rebuilds) the preview for whatever the draft now holds.
  Future<void> _attach(HostVideoIntro? intro) async {
    final source = intro?.path ?? intro?.savedUrl;
    if (source == _playerFor) return;

    final previous = _player;
    _player = null;
    _playerFor = source;
    await previous?.dispose();

    if (source == null) {
      if (mounted) setState(() {});
      return;
    }

    final next = intro?.path != null
        ? VideoPlayerController.file(File(intro!.path!))
        : VideoPlayerController.networkUrl(Uri.parse(source));
    try {
      await next.initialize();
      await next.setLooping(false);
    } catch (e) {
      Log.d('VideoIntro', 'preview unavailable: $e');
      await next.dispose();
      if (mounted) setState(() {});
      return;
    }
    if (!mounted) {
      await next.dispose();
      return;
    }
    setState(() => _player = next);
  }

  Future<void> _capture() async {
    try {
      final clip = await VibeCamera.open(
        context,
        config: VibeCameraConfig(
          maxDuration: _max,
          // Small files load fast on the profile (see status_capture).
          preferredFps: 30,
          maxOutputFps: 30,
          accent: context.colors.accent,
          strings: vibeCameraStrings(context),
          onOpenSettings: () => openCallSettings(),
          // Unlike a Vibe, an intro may come from the gallery: it is
          // reviewed before anyone sees it.
          pickFromGallery: () async {
            final picked = await ImagePicker().pickVideo(
              source: ImageSource.gallery,
            );
            return picked == null ? null : File(picked.path);
          },
        ),
      );
      // Null: closed without a clip — the host's choice, not an error.
      if (clip == null || !mounted) return;

      final current = widget.draft.videoIntro.value ?? const HostVideoIntro();
      widget.draft.videoIntro.value = current.withRecording(
        clip.file.path,
        clip.duration.inSeconds,
      );
    } catch (e) {
      Log.d('VideoIntro', 'capture failed: $e');
      CToast.show(
        'hostflow:video.failed',
        variant: CToastVariant.error,
      );
    }
  }

  void _discard() {
    final current = widget.draft.videoIntro.value;
    if (current == null) return;
    // Only ever drops a NEW capture. A clip already saved on the profile cannot
    // be cleared from here, exactly as the voice intro cannot: the patch has no
    // way to send "no video" without taking unrelated edits down with it.
    widget.draft.videoIntro.value = current.withoutRecording();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return ValueListenableBuilder<HostVideoIntro?>(
      valueListenable: widget.draft.videoIntro,
      builder: (context, intro, _) {
        // Keeps the preview in step with the draft without rebuilding it on
        // every unrelated setState.
        _attach(intro);

        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SizedBox(height: 20.ms),
            const CText(
              'hostflow:video.title',
              size: 14,
              weight: FontWeight.w700,
            ),
            SizedBox(height: 4.ms),
            CText(
              'hostflow:video.hint',
              size: 12,
              color: c.textMuted,
            ),
            SizedBox(height: 10.ms),
            if (intro == null) _AddTile(onTap: _capture) else _preview(intro),
          ],
        );
      },
    );
  }

  Widget _preview(HostVideoIntro intro) {
    final player = _player;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(14.ms),
          child: AspectRatio(
            // The clip's own ratio once known; portrait until then, because a
            // phone capture almost always is and the box should not jump.
            aspectRatio: player?.value.isInitialized == true
                ? player!.value.aspectRatio
                : 9 / 16,
            child: ColoredBox(
              color: Colors.black,
              child: player == null
                  ? const Center(child: CircularProgressIndicator())
                  : Stack(
                      alignment: Alignment.center,
                      children: [
                        VideoPlayer(player),
                        Pressable(
                          onPressed: () async {
                            player.value.isPlaying
                                ? await player.pause()
                                : await player.play();
                            if (mounted) setState(() {});
                          },
                          child: Container(
                            padding: EdgeInsets.all(14.ms),
                            decoration: const BoxDecoration(
                              color: Colors.black54,
                              shape: BoxShape.circle,
                            ),
                            child: Icon(
                              player.value.isPlaying
                                  ? LucideIcons.pause
                                  : LucideIcons.play,
                              size: 22.ms,
                              color: Colors.white,
                            ),
                          ),
                        ),
                      ],
                    ),
            ),
          ),
        ),
        SizedBox(height: 8.ms),
        Row(
          children: [
            Expanded(
              child: _TextAction(
                icon: LucideIcons.rotateCcw,
                label: 'hostflow:video.again',
                onTap: _capture,
              ),
            ),
            // Only offered for a capture that has not been saved yet: there is
            // nothing honest to show for "delete the approved one".
            if (intro.isNew)
              Expanded(
                child: _TextAction(
                  icon: LucideIcons.trash2,
                  label: 'hostflow:video.discard',
                  danger: true,
                  onTap: _discard,
                ),
              ),
          ],
        ),
        if (!intro.isNew)
          Padding(
            padding: EdgeInsets.only(top: 6.ms),
            child: CText(
              'hostflow:video.in_review',
              size: 11,
              color: context.colors.textMuted,
            ),
          ),
      ],
    );
  }
}

class _AddTile extends StatelessWidget {
  const _AddTile({required this.onTap});
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Pressable(
      onPressed: onTap,
      child: Container(
        padding: EdgeInsets.symmetric(vertical: 22.ms),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(14.ms),
          border: Border.all(color: c.border),
        ),
        child: Column(
          children: [
            Icon(LucideIcons.video, size: 26.ms, color: c.accent),
            SizedBox(height: 6.ms),
            CText(
              'hostflow:video.add',
              size: 13,
              weight: FontWeight.w700,
              color: c.accent,
            ),
          ],
        ),
      ),
    );
  }
}

class _TextAction extends StatelessWidget {
  const _TextAction({
    required this.icon,
    required this.label,
    required this.onTap,
    this.danger = false,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final bool danger;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final tone = danger ? HostPalette.of(context).danger : c.text;
    return Pressable(
      onPressed: onTap,
      child: Padding(
        padding: EdgeInsets.symmetric(vertical: 10.ms),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 15.ms, color: tone),
            SizedBox(width: 6.ms),
            Flexible(
              child: CText(label, size: 12, weight: FontWeight.w600, color: tone),
            ),
          ],
        ),
      ),
    );
  }
}
