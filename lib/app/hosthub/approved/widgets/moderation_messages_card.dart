import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:intl/intl.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../../core/analytics/events/host_events.dart';
import '../../../../core/i18n/i18n.dart';
import '../../../../core/network/strapi.dart';
import '../../../../core/router/app_router.dart';
import '../../../../core/utils/scale.dart';
import '../../../api/hosthub/hosthub_queries.dart';
import '../../../api/hosthub/moderation_models.dart';
import '../../../api/hosthub/profile_models.dart';
import '../../../authscreen/helper/deep_links.dart';
import '../../../component/c_alert.dart';
import '../../../component/c_image.dart';
import '../../../component/c_text.dart';
import '../../../component/pressable.dart';
import '../../common/host_review.dart';
import '../../onboarding/helper/host_palette.dart';
import '../../onboarding/widgets/fix_notice.dart';
import '../../onboarding/widgets/step_body.dart';

/// "Messages from the moderation team" on the ME tab: the team's notes and
/// decisions, newest first, each with what it is about (the fields to
/// change, the rejected photo) and a button to the screen the team linked,
/// or to the step to fix. The same messages arrive as pushes. A plain
/// message (no fix asked) has an X that closes it for good; the team can
/// also resolve any message from the admin panel.
class HostModerationMessagesCard extends HookWidget {
  const HostModerationMessagesCard({super.key, required this.open, this.host});

  /// Opens an app route (and refreshes ME on return).
  final Future<void> Function(String route) open;

  /// The profile now: a request it has already fixed (a rejected photo
  /// since deleted, …) is not shown.
  final HostProfile? host;

  /// Shown before "Show more".
  static const _first = 3;

  @override
  Widget build(BuildContext context) {
    final all = useHostModerationMessages(context).data ?? const [];
    final host = this.host;
    final messages = host == null
        ? all
        : [
            for (final m in all)
              if (!m.resolvedFor(host)) m,
          ];
    final expanded = useState(false);
    // Once per message count shown.
    useEffect(() {
      if (messages.isNotEmpty) {
        HostEvents.moderationMessagesShown(count: messages.length);
      }
      return null;
    }, [messages.length]);
    if (messages.isEmpty) return const SizedBox.shrink();
    final p = HostPalette.of(context);
    final shown = expanded.value ? messages : messages.take(_first).toList();
    return Padding(
      padding: EdgeInsets.only(top: 12.ms),
      child: HostCard(
        padding: EdgeInsets.fromLTRB(14.ms, 14.ms, 14.ms, 6.ms),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Icon(
                  LucideIcons.messageSquareText,
                  size: 18.ms,
                  color: p.accent,
                ),
                SizedBox(width: 8.ms),
                Expanded(
                  child: CText(
                    'hosthub:messages.title',
                    size: 15,
                    weight: FontWeight.w800,
                    color: p.text,
                  ),
                ),
              ],
            ),
            for (final (i, m) in shown.indexed) ...[
              if (i > 0) Divider(height: 1, color: p.cardBorder),
              _Message(message: m, open: open),
            ],
            if (messages.length > _first)
              Align(
                alignment: Alignment.centerLeft,
                child: Pressable(
                  onPressed: () {
                    expanded.value = !expanded.value;
                    HostEvents.moderationMessagesExpanded(
                      expanded: expanded.value,
                    );
                  },
                  hitPadding: EdgeInsets.all(6.ms),
                  child: Padding(
                    padding: EdgeInsets.symmetric(vertical: 8.ms),
                    child: CText(
                      expanded.value
                          ? 'hosthub:messages.less'
                          : 'hosthub:messages.more',
                      variables: {'count': messages.length - _first},
                      size: 13,
                      weight: FontWeight.w700,
                      color: p.accent,
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _Message extends StatelessWidget {
  const _Message({required this.message, required this.open});
  final HostModerationMessage message;
  final Future<void> Function(String route) open;

  static final _when = DateFormat('d MMM, h:mm a', 'en_US');

  /// The step that fixes what a rejection was about; null for a plain note.
  static String? fixRoute(HostModerationMessage m) {
    for (final f in m.fields) {
      if (HostReview.fieldSteps[f] case final step?) {
        return AppRoutes.hostStep(step.name);
      }
    }
    if (m.photo != null) return AppRoutes.hostStep('photos');
    if (m.audio == 'rejected') return AppRoutes.hostStep('voice');
    if (m.isTextRejection) return AppRoutes.hostStep('basic');
    return null;
  }

  /// The team's link, opened the way a push's link is (any app scheme:
  /// the path picks the screen).
  static void openLink(String link) {
    if (link.toLowerCase().startsWith('https://')) {
      unawaited(DeepLinks.instance.handle(link));
    } else {
      DeepLinks.instance.queueCampaign(link);
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = HostPalette.of(context);
    final m = message;
    final (icon, color, bg) = m.needsAction
        ? (LucideIcons.circleAlert, p.danger, p.dangerTint)
        : m.isApproval
        ? (LucideIcons.circleCheck, p.success, p.successTint)
        : (LucideIcons.messageCircle, p.accent, p.tint);
    final link = m.deeplink;
    final fix = link == null && m.needsAction ? fixRoute(m) : null;
    final photo = Strapi.mediaUrl(m.photoUrl);
    return Padding(
      padding: EdgeInsets.symmetric(vertical: 12.ms),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 30.ms,
            height: 30.ms,
            alignment: Alignment.center,
            decoration: BoxDecoration(color: bg, shape: BoxShape.circle),
            child: Icon(icon, size: 16.ms, color: color),
          ),
          SizedBox(width: 10.ms),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (m.body.isEmpty)
                  CText(
                    'hosthub:messages.empty_note',
                    size: 14,
                    height: 20,
                    weight: FontWeight.w600,
                    color: p.text,
                  )
                else
                  CText.raw(
                    m.body,
                    size: 14,
                    height: 20,
                    weight: FontWeight.w600,
                    color: p.text,
                  ),
                if (m.fields.isNotEmpty) ...[
                  SizedBox(height: 4.ms),
                  CText(
                    'hosthub:messages.fields',
                    variables: {
                      'fields': HostFixNotice.fieldNames(context, [
                        for (final f in m.fields)
                          if (HostReview.fieldSteps.containsKey(f)) f,
                      ]),
                    },
                    size: 13,
                    weight: FontWeight.w700,
                    color: p.danger,
                  ),
                ],
                if (photo != null) ...[
                  SizedBox(height: 8.ms),
                  Semantics(
                    label: context.t('hosthub:messages.photo'),
                    image: true,
                    child: Container(
                      width: 56.ms,
                      height: 56.ms,
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(10.ms),
                        border: Border.all(color: p.danger, width: 2),
                      ),
                      child: CImage(url: photo, width: 56.ms, radius: 8.ms),
                    ),
                  ),
                ],
                if (m.createdAt case final at?) ...[
                  SizedBox(height: 6.ms),
                  CText.raw(
                    _when.format(at),
                    size: 11.5,
                    weight: FontWeight.w500,
                    color: p.muted,
                  ),
                ],
              ],
            ),
          ),
          if (link != null || fix != null) ...[
            SizedBox(width: 8.ms),
            Pressable(
              activeOpacity: 0.85,
              onPressed: () {
                HostEvents.moderationMessageTapped(
                  action: link != null ? 'link' : 'fix',
                );
                link != null ? openLink(link) : unawaited(open(fix!));
              },
              child: Container(
                height: 32.ms,
                padding: EdgeInsets.symmetric(horizontal: 12.ms),
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: m.needsAction ? p.danger : p.accent,
                  borderRadius: BorderRadius.circular(999),
                ),
                child: CText(
                  link != null
                      ? 'hosthub:messages.open'
                      : 'hosthub:messages.fix',
                  size: 12.5,
                  weight: FontWeight.w800,
                  color: p.onAccent,
                ),
              ),
            ),
          ],
          if (m.dismissible) ...[
            SizedBox(width: 4.ms),
            Pressable(
              key: ValueKey('moderation-dismiss-${m.id}'),
              semanticLabel: context.t('actions.close'),
              hitPadding: EdgeInsets.all(8.ms),
              onPressed: () {
                HostEvents.moderationMessageTapped(action: 'dismiss');
                unawaited(
                  dismissModerationMessage(m).catchError((Object e) {
                    unawaited(CAlert.error(e));
                  }),
                );
              },
              child: Padding(
                padding: EdgeInsets.all(2.ms),
                child: Icon(LucideIcons.x, size: 16.ms, color: p.muted),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
