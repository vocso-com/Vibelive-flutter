import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../core/analytics/events/discover_events.dart';
import '../../../core/i18n/i18n.dart';
import '../../../core/session/session_store.dart';
import '../../../core/theme/vibe_colors.dart';
import '../../../core/utils/scale.dart';
import '../../api/instant_call/instant_call_queries.dart';
import '../../callscreen/call/helper/call_format.dart';
import '../../callscreen/helper/call_actions.dart';
import '../../callscreen/helper/call_controller.dart';
import '../../component/c_text.dart';
import '../../component/pressable.dart';

/// "Talk Now": one tap, the server finds a free host. Shown only while the
/// server has Talk Now on for this user (`/instant-call/config`, which answers
/// per user: the admin gives it to company accounts or to all); off or unset, a
/// tap could only fail. A host never sees it unless the account is a company
/// account.
///
/// WHAT THE CALL COSTS, BEFORE THE TAP
/// -----------------------------------
/// The per-minute rate is on the button. Talk Now connects whoever is free, so
/// the caller never sees a host's own price first the way they would from a
/// profile — without this the only way to learn the cost was to be charged it.
/// The server sends these rates (`callerVoiceRate` / `callerVideoRate`); they
/// are the instant-call rates, not any one host's.
///
/// CHOOSING VOICE OR VIDEO
/// -----------------------
/// `allowedCallTypes` has always had three values, and `both` used to place a
/// voice call with no way to ask for video and no sign that video existed. Now
/// `both` shows one button per type, each with its own rate, and a single
/// allowed type stays a single full-width button.
///
/// Voice sits first and is the cheaper one, which is the order to offer them
/// in: the person who taps without reading should land on the smaller bill.
class TalkNowButton extends HookWidget {
  const TalkNowButton({super.key});

  @override
  Widget build(BuildContext context) {
    final config = useInstantCallConfig(context).data;
    final session = useValueListenable(SessionStore.instance);
    // A host never sees it unless the account is a company account: Talk Now
    // finds somebody to talk TO, and a host taking one would be calling their
    // own side of the marketplace.
    final host = session.isExpert && !session.isCompanyAccount;
    if (host || config == null || !config.enabled) {
      return const SizedBox.shrink();
    }

    final voice = config.allows(video: false);
    final video = config.allows(video: true);
    if (!voice && !video) return const SizedBox.shrink();

    void place({required bool asVideo}) {
      final onCall = CallController.instance.isOnCall;
      DiscoverEvents.talkNowTapped(blockedByCall: onCall);
      if (onCall) return;
      unawaited(HapticFeedback.mediumImpact());
      unawaited(
        CallActions.talkNow(
          video: asVideo,
          maxRingSeconds: config.maxRingSeconds,
        ),
      );
    }

    return Padding(
      padding: EdgeInsets.symmetric(horizontal: 16.ms, vertical: 6.ms),
      child: voice && video
          ? Row(
              children: [
                Expanded(
                  child: _TalkNowTile(
                    icon: LucideIcons.phone,
                    label: 'home:talk_now.voice',
                    rate: config.callerVoiceRate,
                    onTap: () => place(asVideo: false),
                  ),
                ),
                SizedBox(width: 10.ms),
                Expanded(
                  child: _TalkNowTile(
                    icon: LucideIcons.video,
                    label: 'home:talk_now.video',
                    rate: config.callerVideoRate,
                    onTap: () => place(asVideo: true),
                  ),
                ),
              ],
            )
          : _TalkNowTile(
              icon: video ? LucideIcons.video : LucideIcons.phone,
              label: 'home:talk_now.action',
              subtitle: 'home:talk_now.subtitle',
              rate: video ? config.callerVideoRate : config.callerVoiceRate,
              onTap: () => place(asVideo: video),
            ),
    );
  }
}

class _TalkNowTile extends StatelessWidget {
  const _TalkNowTile({
    required this.icon,
    required this.label,
    required this.rate,
    required this.onTap,
    this.subtitle,
  });

  final IconData icon;
  final String label;
  final String? subtitle;

  /// Null when the server did not send one — an older backend. The button
  /// still works; it simply does not claim a price it does not know.
  final double? rate;

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Pressable(
      activeOpacity: 0.85,
      onPressed: onTap,
      child: Container(
        padding: EdgeInsets.symmetric(horizontal: 16.ms, vertical: 12.ms),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [c.accent, c.accent.withValues(alpha: 0.85)],
          ),
          borderRadius: BorderRadius.circular(16.ms),
          boxShadow: [
            BoxShadow(
              color: c.accent.withValues(alpha: 0.3),
              blurRadius: 12,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(icon, size: 18.ms, color: c.onAccent),
                SizedBox(width: 8.ms),
                // Long copy (Hindi, large text) shortens, never overflows.
                Flexible(
                  child: CText(
                    label,
                    size: 14,
                    weight: FontWeight.w800,
                    color: c.onAccent,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                if (subtitle case final s?) ...[
                  SizedBox(width: 6.ms),
                  Flexible(
                    flex: 2,
                    child: CText(
                      s,
                      size: 11,
                      weight: FontWeight.w500,
                      color: c.onAccent.withValues(alpha: 0.8),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ],
            ),
            if (rate case final r?) ...[
              SizedBox(height: 3.ms),
              Text.rich(
                TextSpan(
                  children: [
                    TextSpan(text: context.t('search:results.currency')),
                    TextSpan(
                      text: formatRate(r),
                      style: const TextStyle(fontWeight: FontWeight.w800),
                    ),
                    TextSpan(text: context.t('search:results.per_min')),
                  ],
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 11.ms,
                  color: c.onAccent.withValues(alpha: 0.9),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
