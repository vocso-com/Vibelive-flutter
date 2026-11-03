import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../core/analytics/events/discover_events.dart';
import '../../../core/i18n/i18n.dart';
import '../../../core/session/session_store.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/vibe_colors.dart';
import '../../../core/utils/scale.dart';
import '../../api/instant_call/instant_call_queries.dart';
import '../../callscreen/call/helper/call_format.dart';
import '../../callscreen/helper/call_actions.dart';
import '../../callscreen/helper/call_controller.dart';
import '../../component/c_text.dart';
import '../../component/morph_fab.dart';
import '../../component/pressable.dart';
import '../../navbar/bottombar/navbar_collapse.dart';

/// "Talk Now": one tap, the server finds a free host. Shown only while the
/// server has Talk Now on for this user (`/instant-call/config`, which answers
/// per user: the admin gives it to company accounts or to all); off or unset, a
/// tap could only fail. A host never sees it unless the account is a company
/// account.
///
/// HOW IT SITS ON DISCOVER
/// -----------------------
/// It floats just above the navbar ([MorphFab]): the first time per app
/// launch it arrives as a full-width pill, holds three seconds, then folds
/// into a round call button at the right. Scrolling the feed folds it early.
/// ONE tap on the circle places the call — never "tap to open, tap again"
/// (voice when allowed, the cheaper one; video when it is the only type). A
/// long press opens the pill again: with both types, that is where video is.
///
/// WHAT THE CALL COSTS, BEFORE THE TAP
/// -----------------------------------
/// The per-minute rate is on the pill, and on a small badge on the circle's
/// edge for the call its tap places. Talk Now connects whoever is free, so
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
/// allowed type makes the whole pill the button.
///
/// Voice sits first and is the cheaper one, which is the order to offer them
/// in: the person who taps without reading should land on the smaller bill.
/// Talk Now is lime in both themes, with the theme's own dark text on it: in
/// light mode the purple accent sank into the page, and white text on lime
/// would not read. The dark theme's palette is that exact pair.
const _palette = VibeColors.dark;

class TalkNowButton extends HookWidget {
  const TalkNowButton({super.key});

  /// Places the call. Tests swap it to see a tap place one without
  /// starting the call layer.
  @visibleForTesting
  static Future<void> Function({bool video, int? maxRingSeconds}) placeCall =
      CallActions.talkNow;

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
        placeCall(video: asVideo, maxRingSeconds: config.maxRingSeconds),
      );
    }

    // The circle's one tap: voice when allowed (the cheaper), else video.
    final circleVideo = !voice;
    final circleRate = circleVideo
        ? config.callerVideoRate
        : config.callerVoiceRate;
    final price = circleRate == null
        ? null
        : '${context.t('search:results.currency')}${formatRate(circleRate)}'
              '${context.t('search:results.per_min')}';

    const c = _palette;
    return MorphFab(
      key: const ValueKey('talk-now'),
      introOnce: 'talk_now',
      foldWhen: NavbarCollapse.instance,
      onTap: () => place(asVideo: circleVideo),
      onUnfold: DiscoverEvents.talkNowOpened,
      colors: c.primaryGradient,
      iconColor: c.onAccent,
      icon: circleVideo ? LucideIcons.video : LucideIcons.phone,
      badge: price,
      semanticLabel: [context.t('home:talk_now.action'), ?price].join(', '),
      pillHeight: 64.ms,
      pillRadius: 20.ms,
      circleSize: 56.ms,
      pill: _TalkNowPill(
        voice: voice,
        video: video,
        voiceRate: config.callerVoiceRate,
        videoRate: config.callerVideoRate,
        place: (asVideo) => place(asVideo: asVideo),
      ),
    );
  }
}

/// The open pill: a live badge, what it does, and the price of each call.
class _TalkNowPill extends StatelessWidget {
  const _TalkNowPill({
    required this.voice,
    required this.video,
    required this.voiceRate,
    required this.videoRate,
    required this.place,
  });

  final bool voice;
  final bool video;

  /// Null when the server did not send one — an older backend. The button
  /// still works; it simply does not claim a price it does not know.
  final double? voiceRate;
  final double? videoRate;
  final void Function(bool video) place;

  @override
  Widget build(BuildContext context) {
    const c = _palette;
    final both = voice && video;
    final row = Padding(
      padding: EdgeInsets.symmetric(horizontal: 12.ms),
      child: Row(
        children: [
          _LiveBadge(icon: !voice ? LucideIcons.video : LucideIcons.phone),
          SizedBox(width: 10.ms),
          // Long copy (Hindi, large text) shortens, never overflows.
          Expanded(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                CText(
                  'home:talk_now.action',
                  size: 15,
                  weight: FontWeight.w800,
                  color: c.onAccent,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                SizedBox(height: 1.ms),
                CText(
                  'home:talk_now.subtitle',
                  size: 11,
                  weight: FontWeight.w500,
                  color: c.onAccent.withValues(alpha: 0.85),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          SizedBox(width: 8.ms),
          if (both) ...[
            _RateChip(
              key: const ValueKey('talk-now-voice'),
              icon: LucideIcons.phone,
              label: 'home:talk_now.voice',
              rate: voiceRate,
              onTap: () => place(false),
            ),
            SizedBox(width: 6.ms),
            _RateChip(
              key: const ValueKey('talk-now-video'),
              icon: LucideIcons.video,
              label: 'home:talk_now.video',
              rate: videoRate,
              onTap: () => place(true),
            ),
          ] else
            _RateChip(
              icon: video ? LucideIcons.video : LucideIcons.phone,
              label: video ? 'home:talk_now.video' : 'home:talk_now.voice',
              rate: video ? videoRate : voiceRate,
            ),
        ],
      ),
    );
    if (both) return row;
    // One call type: the whole pill is the button.
    return Pressable(
      key: const ValueKey('talk-now-call'),
      activeOpacity: 0.85,
      onPressed: () => place(video),
      child: row,
    );
  }
}

/// The call icon in a soft disc, with a green "people are free" dot.
class _LiveBadge extends StatelessWidget {
  const _LiveBadge({required this.icon});
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    const c = _palette;
    final size = 40.ms;
    return SizedBox.square(
      dimension: size,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          DecoratedBox(
            decoration: BoxDecoration(
              color: c.onAccent.withValues(alpha: 0.18),
              shape: BoxShape.circle,
            ),
            child: Center(
              child: Icon(icon, size: 19.ms, color: c.onAccent),
            ),
          ),
          Positioned(
            right: 1.ms,
            top: 1.ms,
            child: Container(
              width: 10.ms,
              height: 10.ms,
              decoration: BoxDecoration(
                color: AppColors.green,
                shape: BoxShape.circle,
                border: Border.all(color: c.primaryGradient.first, width: 2),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// A call type with its per-minute price, as a white chip. A button when
/// [onTap] is set (both types offered); a label otherwise.
class _RateChip extends StatelessWidget {
  const _RateChip({
    super.key,
    required this.icon,
    required this.label,
    required this.rate,
    this.onTap,
  });

  final IconData icon;
  final String label;
  final double? rate;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    const c = _palette;
    final style = TextStyle(
      fontSize: 12.ms,
      fontWeight: FontWeight.w800,
      color: c.primaryGradient.first,
    );
    final chip = Container(
      padding: EdgeInsets.symmetric(horizontal: 10.ms, vertical: 7.ms),
      decoration: BoxDecoration(
        color: c.onAccent,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14.ms, color: c.primaryGradient.first),
          SizedBox(width: 4.ms),
          if (rate case final r?)
            Text.rich(
              TextSpan(
                children: [
                  TextSpan(text: context.t('search:results.currency')),
                  TextSpan(text: formatRate(r)),
                  TextSpan(
                    text: context.t('search:results.per_min'),
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                ],
              ),
              maxLines: 1,
              style: style,
            )
          else
            Text(context.t(label), maxLines: 1, style: style),
        ],
      ),
    );
    final tap = onTap;
    if (tap == null) return chip;
    return Pressable(activeOpacity: 0.8, onPressed: tap, child: chip);
  }
}
