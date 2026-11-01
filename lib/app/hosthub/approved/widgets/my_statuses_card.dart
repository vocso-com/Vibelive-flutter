import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:image_picker/image_picker.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../../core/theme/vibe_colors.dart';
import '../../../../core/utils/log.dart';
import '../../../../core/utils/scale.dart';
import '../../../api/host_status/host_status_models.dart';
import '../../../../core/network/api_exception.dart';
import '../../../api/host_status/host_status_api.dart';
import '../../../api/paymentscreen/runtime_config_queries.dart';
import '../../../api/host_status/host_status_queries.dart';
import '../../../component/c_text.dart';
import '../../../component/c_toast.dart';
import '../../../component/pressable.dart';
import '../../../listingflow/profile/status_viewer.dart';

/// The host's own statuses on the ME tab: post one, and see where each stands.
///
/// WHY THE REVIEW STATE IS THE POINT
/// ---------------------------------
/// A status is screened before anyone sees it, and it stops showing after 24
/// hours. So a host who posts one and is shown nothing but a thumbnail has no
/// way to tell whether it is live, waiting, turned down, or simply over. Every
/// tile says which, because the alternative is a host concluding the feature is
/// broken and never posting again.
///
/// The clip is captured, never chosen from the gallery: [ImageSource.camera] is
/// what makes "recorded in-app" true and what stops a reviewer being handed
/// something downloaded off the internet.
class MyStatusesCard extends HookWidget {
  const MyStatusesCard({super.key, required this.hostName});

  /// Shown as the viewer's title when the host previews their own.
  final String hostName;

  static const _maxDuration = Duration(seconds: 30);

  /// Tiles shown beside the Add tile. Four is what fits a phone without
  /// scrolling, and more than a host accumulates inside one 24-hour window.
  static const _maxTiles = 4;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final statuses = useMyStatuses(context);
    final post = usePostStatus();
    final media = useRuntimeConfig(context).hostMedia;
    final rows = statuses.data ?? const <HostOwnStatus>[];

    // Nothing at all while the server has statuses off, or capped at zero.
    // The card exists to invite a host to post; inviting them to be refused
    // is worse than not asking.
    if (!media.canPostStatus) return const SizedBox.shrink();

    Future<void> capture() async {
      if (post.isPending) return;
      try {
        final file = await ImagePicker().pickVideo(
          source: ImageSource.camera,
          maxDuration: _maxDuration,
        );
        // Null is a cancel or a refused camera permission: the host's choice
        // either way, and not an error worth showing.
        if (file == null) return;
        await post.mutateAsync(
          HostStatusDraft(file.path, recordedAt: DateTime.now()),
        );
        CToast.show('hostflow:my_status.posted');
      } on ApiException catch (e) {
        // The server refuses a status for reasons a host can act on: the
        // feature is not switched on, or they have used today's allowance.
        // Those need different things from them — wait for us, or come back
        // tomorrow — so showing one generic failure for both helps nobody.
        Log.d('MyStatuses', 'post refused: ${e.serverMessage ?? e}');
        CToast.show(
          HostStatusApi.knownErrorKey(e) ?? HostStatusErrorKeys.postFailed,
          variant: CToastVariant.error,
        );
      } catch (e) {
        Log.d('MyStatuses', 'post failed: $e');
        CToast.show(
          HostStatusErrorKeys.postFailed,
          variant: CToastVariant.error,
        );
      }
    }

    return Padding(
      padding: EdgeInsets.fromLTRB(16.ms, 16.ms, 16.ms, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Expanded(
                child: CText(
                  'hostflow:my_status.title',
                  size: 14,
                  weight: FontWeight.w800,
                ),
              ),
              if (post.isPending)
                SizedBox(
                  width: 16.ms,
                  height: 16.ms,
                  child: const CircularProgressIndicator(strokeWidth: 2),
                ),
            ],
          ),
          SizedBox(height: 2.ms),
          CText('hostflow:my_status.hint', size: 11, color: c.textMuted),
          SizedBox(height: 10.ms),
          // A plain row, not a horizontal list. This card sits inside the ME
          // tab's own scroll view, and a nested Scrollable there both confuses
          // scroll-position tooling and buys nothing: statuses expire after 24
          // hours, so a host has a handful at most and four fit on a phone.
          Row(
            children: [
              _AddTile(onTap: capture, busy: post.isPending),
              for (final s in rows.take(_maxTiles))
                _StatusTile(
                  status: s,
                  onTap: () {
                    // Only something with a file can be played. A rejected or
                    // purged clip opens nothing.
                    final url = s.media;
                    if (url == null) return;
                    StatusViewer.open(context, urls: [url], title: hostName);
                  },
                ),
            ],
          ),
        ],
      ),
    );
  }
}

class _AddTile extends StatelessWidget {
  const _AddTile({required this.onTap, required this.busy});
  final VoidCallback onTap;
  final bool busy;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Pressable(
      onPressed: busy ? null : onTap,
      child: Container(
        width: 84.ms,
        margin: EdgeInsets.only(right: 10.ms),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12.ms),
          border: Border.all(color: c.border),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(LucideIcons.plus, size: 22.ms, color: c.accent),
            SizedBox(height: 6.ms),
            CText(
              'hostflow:my_status.add',
              size: 10,
              weight: FontWeight.w700,
              color: c.accent,
              align: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}

class _StatusTile extends StatelessWidget {
  const _StatusTile({required this.status, required this.onTap});
  final HostOwnStatus status;
  final VoidCallback onTap;

  /// One word for where this stands, and the colour to match. Read from the
  /// server's own `state` rather than worked out here, so the tile cannot
  /// disagree with what is actually being served.
  (String, Color) _badge(BuildContext context) {
    final c = context.colors;
    return switch (status.state) {
      'visible' => ('hostflow:my_status.live', const Color(0xFF17A34A)),
      'pending' => ('hostflow:my_status.in_review', const Color(0xFFB45309)),
      'rejected' => ('hostflow:my_status.rejected', const Color(0xFFDC2626)),
      'expired' => ('hostflow:my_status.finished', c.textMuted),
      _ => ('hostflow:my_status.finished', c.textMuted),
    };
  }

  @override
  Widget build(BuildContext context) {
    final (label, tone) = _badge(context);
    final playable = status.media != null;
    return Pressable(
      onPressed: playable ? onTap : null,
      child: Container(
        width: 84.ms,
        margin: EdgeInsets.only(right: 10.ms),
        decoration: BoxDecoration(
          color: Colors.black,
          borderRadius: BorderRadius.circular(12.ms),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              playable ? LucideIcons.play : LucideIcons.eyeOff,
              size: 20.ms,
              color: Colors.white70,
            ),
            SizedBox(height: 8.ms),
            Container(
              padding: EdgeInsets.symmetric(horizontal: 6.ms, vertical: 3.ms),
              decoration: BoxDecoration(
                color: tone,
                borderRadius: BorderRadius.circular(6.ms),
              ),
              child: CText(
                label,
                size: 9,
                weight: FontWeight.w800,
                color: Colors.white,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
