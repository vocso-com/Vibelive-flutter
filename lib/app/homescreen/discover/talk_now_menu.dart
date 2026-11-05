import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../core/i18n/i18n.dart';
import '../../../core/theme/vibe_colors.dart';
import '../../../core/utils/scale.dart';
import '../../callscreen/call/helper/call_format.dart';
import '../../component/c_text.dart';
import '../../component/pressable.dart';

/// The bubble menu that springs up from the Talk Now button when both call
/// types are offered: one bubble per type (voice, then video), each with its
/// per-minute rate, revealed bottom-first in a quick staggered pop. Tapping a
/// bubble places that call; tapping outside dismisses it. Lime, like the
/// button, with dark text (the dark palette's pair reads in both themes).
const _palette = VibeColors.dark;

Future<void> showTalkNowMenu(
  BuildContext context, {
  required Rect anchor,
  required double? voiceRate,
  required double? videoRate,
  required void Function({required bool video}) onPick,
}) {
  return showGeneralDialog<void>(
    context: context,
    barrierDismissible: true,
    barrierLabel: MaterialLocalizations.of(context).modalBarrierDismissLabel,
    barrierColor: const Color(0x59000000),
    transitionDuration: const Duration(milliseconds: 420),
    pageBuilder: (_, _, _) => const SizedBox.shrink(),
    transitionBuilder: (ctx, anim, _, _) => _TalkNowMenu(
      animation: anim,
      anchor: anchor,
      voiceRate: voiceRate,
      videoRate: videoRate,
      onPick: onPick,
    ),
  );
}

class _TalkNowMenu extends StatelessWidget {
  const _TalkNowMenu({
    required this.animation,
    required this.anchor,
    required this.voiceRate,
    required this.videoRate,
    required this.onPick,
  });

  final Animation<double> animation;
  final Rect anchor;
  final double? voiceRate;
  final double? videoRate;
  final void Function({required bool video}) onPick;

  void _pick(BuildContext context, {required bool video}) {
    unawaitedHaptic();
    Navigator.of(context).pop();
    onPick(video: video);
  }

  @override
  Widget build(BuildContext context) {
    final mq = MediaQuery.of(context);
    // Top to bottom: video, then voice — so voice sits nearest the button.
    final items = <({bool video, double? rate})>[
      (video: true, rate: videoRate),
      (video: false, rate: voiceRate),
    ];
    final gap = 12.ms;
    // Above the button when there is room (the usual bottom-right fab); below it
    // when the button sits high on the screen, so the bubbles never overflow.
    final placeAbove = anchor.top >= (mq.size.height - anchor.bottom);
    return Stack(
      children: [
        PositionedDirectional(
          end: (mq.size.width - anchor.right).clamp(12.0, mq.size.width - 12),
          top: placeAbove ? null : (anchor.bottom + gap).clamp(0.0, mq.size.height),
          bottom: placeAbove
              ? (mq.size.height - anchor.top + gap).clamp(0.0, mq.size.height)
              : null,
          child: ConstrainedBox(
            constraints: BoxConstraints(maxWidth: 240.ms),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                for (var i = 0; i < items.length; i += 1)
                  Padding(
                    padding: EdgeInsets.only(bottom: i == items.length - 1 ? 0 : 10.ms),
                    child: _Bubble(
                      // Reveal bottom-first: the last item leads.
                      animation: animation,
                      order: items.length - 1 - i,
                      total: items.length,
                      video: items[i].video,
                      rate: items[i].rate,
                      onTap: () => _pick(context, video: items[i].video),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

/// One staggered call bubble. Its reveal is driven by the route [animation]
/// (so it plays in reverse on dismiss too): a small rise, scale and fade, in
/// [order] after the others.
class _Bubble extends StatelessWidget {
  const _Bubble({
    required this.animation,
    required this.order,
    required this.total,
    required this.video,
    required this.rate,
    required this.onTap,
  });

  final Animation<double> animation;
  final int order;
  final int total;
  final bool video;
  final double? rate;
  final VoidCallback onTap;

  double _staged(Curve curve) {
    const span = 0.6;
    final step = total > 1 ? (1 - span) / (total - 1) : 0.0;
    final start = order * step;
    final t = ((animation.value - start) / span).clamp(0.0, 1.0);
    return curve.transform(t);
  }

  @override
  Widget build(BuildContext context) {
    const c = _palette;
    final label = context.t(video ? 'home:talk_now.video_call' : 'home:talk_now.voice_call');
    final priceText = rate == null
        ? null
        : '${context.t('search:results.currency')}${formatRate(rate!)}'
              '${context.t('search:results.per_min')}';
    return AnimatedBuilder(
      animation: animation,
      builder: (context, child) {
        final grow = _staged(Curves.easeOutBack);
        final fade = _staged(Curves.easeOut).clamp(0.0, 1.0);
        return Opacity(
          opacity: fade,
          child: Transform.translate(
            offset: Offset(0, (1 - grow) * 14.ms),
            child: Transform.scale(
              scale: 0.6 + 0.4 * grow,
              alignment: Alignment.bottomRight,
              child: child,
            ),
          ),
        );
      },
      child: Pressable(
        key: ValueKey(video ? 'talk-now-menu-video' : 'talk-now-menu-voice'),
        activeOpacity: 0.85,
        onPressed: onTap,
        child: Container(
          padding: EdgeInsetsDirectional.fromSTEB(8.ms, 8.ms, 16.ms, 8.ms),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: c.primaryGradient.length > 1
                  ? c.primaryGradient
                  : [c.primaryGradient.first, c.primaryGradient.first],
            ),
            borderRadius: BorderRadius.circular(999),
            boxShadow: [
              BoxShadow(
                color: c.primaryGradient.first.withValues(alpha: 0.4),
                blurRadius: 16,
                offset: const Offset(0, 6),
              ),
            ],
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 38.ms,
                height: 38.ms,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: c.onAccent.withValues(alpha: 0.18),
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  video ? LucideIcons.video : LucideIcons.phone,
                  size: 19.ms,
                  color: c.onAccent,
                ),
              ),
              SizedBox(width: 10.ms),
              Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  CText.raw(
                    label,
                    size: 14.5,
                    weight: FontWeight.w800,
                    color: c.onAccent,
                    maxLines: 1,
                  ),
                  if (priceText != null) ...[
                    SizedBox(height: 1.ms),
                    CText.raw(
                      priceText,
                      size: 11.5,
                      weight: FontWeight.w600,
                      color: c.onAccent.withValues(alpha: 0.85),
                      maxLines: 1,
                    ),
                  ],
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// A light tap when a bubble is chosen; never throws.
void unawaitedHaptic() {
  HapticFeedback.selectionClick();
}
