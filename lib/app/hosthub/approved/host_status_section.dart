import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';

import '../../../core/analytics/events/host_events.dart';
import '../../../core/router/app_router.dart';
import '../../../core/utils/scale.dart';
import '../../api/hosthub/approval_models.dart';
import '../../api/hosthub/hosthub_queries.dart';
import '../../api/hosthub/profile_models.dart';
import '../common/moderation_banners.dart';
import 'widgets/moderation_messages_card.dart';
import 'widgets/review_status_card.dart';
import 'widgets/training_card.dart';

/// The host's onboarding state on the ME tab, above the host dashboard:
/// moderation news, then under review / changes needed / finish setup until
/// approved, then the moderation team's messages (any host).
class HostStatusSection extends StatelessWidget {
  const HostStatusSection({super.key, required this.host, required this.open});

  final HostProfile host;

  /// Opens a route (and refreshes ME on return).
  final Future<void> Function(String route) open;

  @override
  Widget build(BuildContext context) {
    // Its own widget: approval-query ticks rebuild only the card.
    final child = host.isApproved
        ? null
        : _ReviewStatus(host: host, open: open);
    final hasNews = hostModerationNotices(host).isNotEmpty;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (child != null || hasNews)
          Padding(
            padding: EdgeInsets.only(top: 12.ms),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // RN MeModule: moderation news above everything else.
                if (hasNews) HostModerationBanners(host: host),
                ?child,
              ],
            ),
          ),
        // Its own padding; nothing when there are no messages.
        HostModerationMessagesCard(open: open, host: host),
        // The admin's training, when shown to existing hosts (optional);
        // nothing when off or done.
        const HostTrainingCard(),
      ],
    );
  }
}

class _ReviewStatus extends HookWidget {
  const _ReviewStatus({required this.host, required this.open});
  final HostProfile host;
  final Future<void> Function(String route) open;

  @override
  Widget build(BuildContext context) {
    final latest = useLatestApproval(
      context,
      expertId: host.key,
      enabled: host.key.isNotEmpty,
    );
    if (latest.data == null && latest.isLoading) {
      return const SizedBox.shrink();
    }
    final status = ApprovalRecord.effective(host, latest.data);
    return HostReviewStatusCard(
      status: status,
      onOpenFlow: () {
        HostEvents.reviewCardTapped(status: status?.name ?? 'not_sent');
        open(AppRoutes.hostOnboarding);
      },
    );
  }
}
