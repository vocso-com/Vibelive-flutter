import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';

import '../../../core/analytics/events/discover_events.dart';
import '../../../core/network/api_exception.dart';
import '../../../core/network/strapi.dart';
import '../../../core/session/session_store.dart';
import '../../../core/theme/vibe_colors.dart';
import '../../../core/utils/scale.dart';
import '../../api/host_status/host_status_models.dart';
import '../../api/host_status/host_status_queries.dart';
import '../../api/listingflow/listing_queries.dart';
import '../../api/paymentscreen/runtime_config_queries.dart';
import '../../component/c_text.dart';
import '../../component/c_toast.dart';
import '../../hosthub/approved/widgets/status_capture.dart';
import '../../listingflow/profile/host_profile_sheet.dart';
import 'status_circle.dart';
import 'status_story_viewer.dart';

/// Statuses on Home, as a row of circles under the topic tabs: a host's own
/// first ("Add status" with a "+", or their live status), then every host
/// with a live status that the selected tab and filters let through, not yet
/// watched first. Tapping one plays it and the ones after it.
///
/// Hidden while the admin has statuses switched off, and for a viewer with
/// nothing to watch and nothing to post: an empty "Statuses" heading would
/// only teach people the row is always empty.
class StatusRow extends HookWidget {
  const StatusRow({super.key, this.include});

  /// Which hosts' circles to show (Home passes its tab and filters); all
  /// when null.
  final bool Function(StatusHost host)? include;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final session = useValueListenable(SessionStore.instance);
    final media = useRuntimeConfig(context).hostMedia;
    final on = media.statusEnabled;
    final feed = useStatusFeed(context, enabled: on);
    final seen = useValueListenable(StatusSeen.ids);
    final user = session.userDocumentId;
    useEffect(() {
      StatusSeen.forUser(user);
      return null;
    }, [user]);

    final canPost = session.isExpert && media.canPostStatus;
    final keep = include;
    final groups = on
        ? [
            for (final g in feed.data ?? const <StatusGroup>[])
              if (keep == null || keep(g.host)) g,
          ]
        : const <StatusGroup>[];
    if (groups.isEmpty && !canPost) return const SizedBox.shrink();

    Future<void> watch(int index) async {
      final group = groups[index];
      DiscoverEvents.statusOpened(
        hostId: group.host.expertDocumentId,
        position: index,
        seen: group.seenWith(seen),
      );
      final visit = await StatusStoryViewer.open(
        context,
        groups: groups,
        initialGroup: index,
      );
      if (visit == null || !context.mounted) return;
      DiscoverEvents.statusVisitProfile(hostId: visit.expertDocumentId);
      try {
        final host = await ensureHostDetail(
          expertDocumentId: visit.expertDocumentId,
        );
        if (context.mounted) {
          await showHostProfile(context, host, source: 'status');
        }
      } on ApiException catch (e) {
        CToast.error(e);
      }
    }

    final circles = <Widget>[
      if (canPost) const _MyStatusCircle(),
      for (var i = 0; i < groups.length; i++)
        StatusCircle(
          key: ValueKey('status-${groups[i].host.expertDocumentId}'),
          ring: groups[i].seenWith(seen) ? StatusRing.seen : StatusRing.fresh,
          avatarUrl: groups[i].host.avatarUrl,
          name: groups[i].host.name,
          label: groups[i].host.name,
          semanticsLabel: groups[i].host.name,
          onTap: () => watch(i),
        ),
    ];

    return Padding(
      padding: EdgeInsets.only(top: 6.ms, bottom: 4.ms),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: EdgeInsets.symmetric(horizontal: 6.ms),
            child: CText(
              'home:statuses.title',
              size: 15,
              weight: FontWeight.w800,
              color: c.text,
            ),
          ),
          SizedBox(height: 8.ms),
          SizedBox(
            height: StatusCircle.photo + 26.ms,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              padding: EdgeInsets.symmetric(horizontal: 6.ms),
              itemCount: circles.length,
              separatorBuilder: (_, _) => SizedBox(width: 10.ms),
              itemBuilder: (_, i) => circles[i],
            ),
          ),
        ],
      ),
    );
  }
}

/// The host's own place, first in the row. With a live status: it in a
/// ring, tap to watch it. Otherwise "Add status" (or "In review" while one
/// waits for a reviewer), tap to record. The "+" always records another.
class _MyStatusCircle extends HookWidget {
  const _MyStatusCircle();

  @override
  Widget build(BuildContext context) {
    final session = useValueListenable(SessionStore.instance);
    final mine = useMyStatuses(context);
    final post = usePostStatus();
    final media = useRuntimeConfig(context).hostMedia;
    final rows = mine.data ?? const <HostOwnStatus>[];
    // Newest first from the server; played oldest first.
    final live = [
      for (final s in rows.reversed)
        if (s.isLive && s.media != null)
          HostStatus(
            documentId: s.documentId,
            media: Strapi.mediaUrl(s.media) ?? s.media!,
            recordedAt: s.recordedAt,
            visibleUntil: s.visibleUntil,
          ),
    ];
    final waiting = rows.any((s) => s.isPending);
    final name = '${session.user?['name'] ?? ''}';
    final avatar = Strapi.mediaFromAsset(session.user?['profilePic']);

    Future<void> record() {
      DiscoverEvents.statusAddTapped(hasLive: live.isNotEmpty);
      return captureStatus(context, post, media: media, mine: rows);
    }

    return StatusCircle(
      key: const ValueKey('status-mine'),
      ring: live.isNotEmpty ? StatusRing.fresh : StatusRing.none,
      avatarUrl: avatar,
      name: name,
      label: live.isNotEmpty
          ? 'home:statuses.mine'
          : waiting
          ? 'home:statuses.in_review'
          : 'home:statuses.add',
      translateLabel: true,
      badge: StatusAddBadge(onTap: record, busy: post.isPending),
      onTap: () {
        if (live.isEmpty) {
          record();
          return;
        }
        StatusStoryViewer.open(
          context,
          own: true,
          groups: [
            StatusGroup(
              host: StatusHost(
                expertDocumentId: session.expertDocumentId ?? '',
                userDocumentId: session.userDocumentId,
                name: name,
                avatarUrl: avatar,
              ),
              statuses: live,
            ),
          ],
        );
      },
    );
  }
}
