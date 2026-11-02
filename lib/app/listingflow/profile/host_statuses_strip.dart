import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../core/theme/vibe_colors.dart';
import '../../../core/utils/scale.dart';
import '../../api/host_status/host_status_models.dart';
import '../../api/host_status/host_status_queries.dart';
import '../../api/host_status/vibe_previews.dart';
import '../../api/listingflow/listing_models.dart';
import '../../api/paymentscreen/runtime_config_queries.dart';
import '../../component/c_image.dart';
import '../../component/c_text.dart';
import '../../component/pressable.dart';
import '../../homescreen/statuses/status_story_viewer.dart';

/// "Today" on a host's profile: their Vibes from the last 24 hours, as
/// preview tiles (a still from each clip, ringed in colour until watched,
/// grey after). A tap opens the same WhatsApp-style viewer as Home (bars,
/// tap / hold / swipe, auto-next, ⋮ Report, Call), starting on that clip.
///
/// Renders nothing when there are none, which is most profiles: an empty
/// heading on every profile would teach people the section is always empty.
/// Only ever shows what the server returns — approved clips inside their
/// day.
class HostStatusesStrip extends HookWidget {
  const HostStatusesStrip({super.key, required this.host, this.onCall});

  final HostCard host;

  /// Audio / Video Call through the profile's own call path (balance gate,
  /// safety notice). Null hides them in the viewer (the host's own profile).
  final void Function(bool video)? onCall;

  /// Tiles shown; the viewer plays the whole set.
  static const _maxTiles = 4;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    // The admin's master switch hides Vibes on profiles too.
    final visible = useRuntimeConfig(context).hostMedia.statusVisible;
    final expertId = host.expertProfileDocumentId;
    final statuses = useHostStatuses(context, visible ? expertId : null);
    final seen = useValueListenable(StatusSeen.ids);
    final made = useValueListenable(VibePreviews.files);
    // The server sends newest first; shown and played in posting order
    // (first posted first), exactly as on Home.
    final rows = (statuses.data ?? const <HostStatus>[]).reversed.toList();
    final shown = rows.take(_maxTiles).toList();
    useEffect(() {
      for (final s in shown) {
        if (s.thumbnail == null) VibePreviews.request(s.documentId, s.media);
      }
      return null;
    }, [shown.map((s) => s.documentId).join('|')]);
    if (!visible || rows.isEmpty || expertId == null) {
      return const SizedBox.shrink();
    }

    // Same order as the tiles.
    final group = StatusGroup(
      host: StatusHost(
        expertDocumentId: expertId,
        userDocumentId: host.userDocumentId,
        name: host.name,
        avatarUrl: host.cardImage,
        verified: host.verified,
      ),
      statuses: rows,
    );

    Future<void> watch(int index) async {
      final exit = await StatusStoryViewer.open(
        context,
        groups: [group],
        initialItem: index,
        showCall: onCall != null,
        // Already on this profile.
        showVisit: false,
        // This profile's own rates: the call buttons show at once.
        hostCards: {expertId: host},
      );
      if (exit != null && exit.call) onCall?.call(exit.video);
    }

    return Padding(
      padding: EdgeInsets.only(top: 12.ms),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          CText(
            'listing:status.today',
            size: 11,
            weight: FontWeight.w800,
            color: c.textMuted,
          ),
          SizedBox(height: 6.ms),
          // A plain row: this sits inside the profile's own scroll view, and
          // only a few fit on a phone anyway.
          SizedBox(
            height: 96.ms,
            child: Row(
              children: [
                for (var i = 0; i < shown.length; i++)
                  _Tile(
                    key: ValueKey('profile-vibe-${shown[i].documentId}'),
                    status: shown[i],
                    preview: made[shown[i].documentId],
                    fallback: host.cardImage,
                    seen: seen.contains(shown[i].documentId),
                    onTap: () => watch(i),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// One Vibe: its still in a rounded frame, a coloured ring until watched,
/// a small play mark.
class _Tile extends StatelessWidget {
  const _Tile({
    super.key,
    required this.status,
    required this.seen,
    required this.onTap,
    this.preview,
    this.fallback,
  });

  final HostStatus status;

  /// Made on this phone when the server sent no still.
  final File? preview;

  /// The host's photo when there is no still at all.
  final String? fallback;
  final bool seen;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final radius = BorderRadius.circular(12.ms);
    final Widget still = status.thumbnail != null
        ? CImage(url: status.thumbnail, fit: BoxFit.cover)
        : preview != null
        ? Image.file(preview!, fit: BoxFit.cover, gaplessPlayback: true)
        : fallback != null
        ? CImage(url: fallback, fit: BoxFit.cover)
        : const ColoredBox(color: Colors.black);
    return Pressable(
      onPressed: onTap,
      child: Container(
        width: 68.ms,
        margin: EdgeInsets.only(right: 8.ms),
        padding: EdgeInsets.all(2.5.ms),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(14.ms),
          gradient: seen
              ? null
              : LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [c.accent, c.darkRose],
                ),
          color: seen ? c.textMuted.withValues(alpha: 0.45) : null,
        ),
        child: ClipRRect(
          borderRadius: radius,
          child: Stack(
            fit: StackFit.expand,
            children: [
              still,
              const DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [Colors.transparent, Colors.black38],
                  ),
                ),
              ),
              Center(
                child: Icon(
                  LucideIcons.play,
                  size: 18.ms,
                  color: Colors.white.withValues(alpha: 0.9),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
