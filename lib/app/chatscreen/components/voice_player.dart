import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../core/i18n/i18n.dart';
import '../../../core/utils/scale.dart';
import '../../api/chat/chat_models.dart';
import '../../component/c_text.dart';
import '../../component/pressable.dart';
import '../helper/chat_format.dart';
import '../helper/chat_voice_player.dart';
import 'chat_palette.dart';
import 'bubble_frame.dart';

/// A voice note: play / pause, a waveform that fills while it plays, and
/// its length (the position while playing). One plays at a time
/// ([ChatVoicePlayer]); only the playing bubble listens to the position.
class VoiceBubble extends StatelessWidget {
  const VoiceBubble({
    super.key,
    required this.message,
    required this.mine,
    required this.tail,
    required this.meta,
  });

  final ChatMessage message;
  final bool mine;
  final bool tail;
  final Widget meta;

  @override
  Widget build(BuildContext context) {
    final p = ChatPalette.of(context);
    final m = message;
    final fg = mine ? p.onMine : p.accent;
    final seconds = m.media?.durationSec ?? 0;
    final url = m.media?.url;
    final playable = url != null || m.localPath != null;
    final player = ChatVoicePlayer.instance;
    return BubbleFrame(
      mine: mine,
      tail: tail,
      padding: EdgeInsetsDirectional.fromSTEB(6.ms, 6.ms, 10.ms, 6.ms),
      child: ValueListenableBuilder<String?>(
        valueListenable: player.active,
        builder: (context, active, _) {
          final playing = active == m.key;
          return Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Pressable(
                onPressed: playable
                    ? () => player.toggle(m.key, url: url, path: m.localPath)
                    : null,
                semanticLabel: context.t(
                  playing ? 'chat:bubble.pause' : 'chat:bubble.play',
                ),
                child: Container(
                  width: 38.ms,
                  height: 38.ms,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: mine
                        ? p.onMine.withValues(alpha: 0.14)
                        : p.accent.withValues(alpha: 0.14),
                  ),
                  child: Icon(
                    playing ? LucideIcons.pause : LucideIcons.play,
                    size: 18.ms,
                    color: fg,
                  ),
                ),
              ),
              SizedBox(width: 8.ms),
              // Only the playing one rebuilds with the position.
              RepaintBoundary(
                child: playing
                    ? ValueListenableBuilder<Duration>(
                        valueListenable: player.position,
                        builder: (_, pos, _) => _Wave(
                          seed: m.key.hashCode,
                          progress: seconds <= 0
                              ? 0
                              : (pos.inMilliseconds / (seconds * 1000)).clamp(
                                  0.0,
                                  1.0,
                                ),
                          color: fg,
                          label: ChatFormat.clock(pos.inSeconds),
                          labelColor: mine ? p.mineMeta : p.theirsMeta,
                        ),
                      )
                    : _Wave(
                        seed: m.key.hashCode,
                        progress: 0,
                        color: fg,
                        label: ChatFormat.clock(seconds),
                        labelColor: mine ? p.mineMeta : p.theirsMeta,
                      ),
              ),
              SizedBox(width: 8.ms),
              Padding(
                padding: EdgeInsets.only(top: 14.ms),
                child: meta,
              ),
            ],
          );
        },
      ),
    );
  }
}

/// Static bars (shaped by [seed], the same every time for one note) with
/// the played part solid; the time under them.
class _Wave extends StatelessWidget {
  const _Wave({
    required this.seed,
    required this.progress,
    required this.color,
    required this.label,
    required this.labelColor,
  });

  final int seed;
  final double progress;
  final Color color;
  final String label;
  final Color labelColor;

  static const _bars = 22;

  @override
  Widget build(BuildContext context) {
    final width = 2.6.ms;
    final gap = 1.6.ms;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          height: 24.ms,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              for (var i = 0; i < _bars; i++)
                Container(
                  width: width,
                  height: (6 + ((seed >> (i % 16)) ^ (i * 7)) % 17)
                      .toDouble()
                      .ms,
                  margin: EdgeInsetsDirectional.only(end: gap),
                  decoration: BoxDecoration(
                    color: color.withValues(
                      alpha: (i + 0.5) / _bars <= progress ? 1 : 0.38,
                    ),
                    borderRadius: BorderRadius.circular(width),
                  ),
                ),
            ],
          ),
        ),
        SizedBox(height: 2.ms),
        CText.raw(
          label,
          size: 11,
          weight: FontWeight.w600,
          color: labelColor,
          maxLines: 1,
        ),
      ],
    );
  }
}
