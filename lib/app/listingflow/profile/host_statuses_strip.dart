import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../core/theme/vibe_colors.dart';
import '../../../core/utils/scale.dart';
import '../../api/host_status/host_status_queries.dart';
import '../../component/c_text.dart';
import '../../component/pressable.dart';
import 'status_viewer.dart';

/// "Today" on a host's profile: their statuses from the last 24 hours, if any.
///
/// Renders nothing at all when there are none, which is most of the time and
/// especially at the start. An empty "Statuses" heading on every profile would
/// teach people the section is always empty and train them to stop looking —
/// the opposite of what a feature meant to build familiarity needs.
///
/// Only ever shows what the server returns, which is approved clips inside
/// their 24 hours. There is no "pending" or "expired" here: those are the
/// host's business, and are on the host's own card.
class HostStatusesStrip extends HookWidget {
  const HostStatusesStrip({
    super.key,
    required this.expertDocumentId,
    required this.hostName,
  });

  final String? expertDocumentId;
  final String hostName;

  /// Tiles shown. The viewer plays the whole set regardless, so this is only
  /// how many fit across a phone.
  static const _maxTiles = 4;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final statuses = useHostStatuses(context, expertDocumentId);
    final rows = statuses.data ?? const [];
    if (rows.isEmpty) return const SizedBox.shrink();

    final urls = [for (final s in rows) s.media];

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
          // A plain row rather than a horizontal list: this sits inside the
          // profile's own scroll view, and the server returns at most ten
          // clips while only a few fit on a phone anyway. Tapping any of them
          // opens the viewer, which runs through the whole set.
          SizedBox(
            height: 96.ms,
            child: Row(
              children: [
                for (var i = 0; i < rows.length && i < _maxTiles; i++)
                  Pressable(
                    onPressed: () => StatusViewer.open(
                      context,
                      urls: urls,
                      title: hostName,
                      initialIndex: i,
                    ),
                    child: Container(
                      width: 68.ms,
                      margin: EdgeInsets.only(right: 8.ms),
                      decoration: BoxDecoration(
                        color: Colors.black,
                        borderRadius: BorderRadius.circular(12.ms),
                        border: Border.all(color: c.accent, width: 2),
                      ),
                      child: Icon(
                        LucideIcons.play,
                        size: 18.ms,
                        color: Colors.white70,
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
