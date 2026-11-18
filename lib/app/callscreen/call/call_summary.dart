import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';

import '../../../core/i18n/i18n.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/vibe_colors.dart';
import '../../../core/utils/scale.dart';
import '../../component/c_text.dart';
import 'call_avatar.dart';
import 'call_motion_widgets.dart';
import 'call_pulse.dart';
import 'search_galaxy.dart';
import 'helper/call_format.dart';
import 'helper/call_motion.dart';
import 'helper/call_select.dart';

/// RN `Summary`: ringed photo, name, blinking status, call type and — once
/// [ended] — the talk time (`mm:ss`) or "Declined" for a call that never
/// connected. While active the pulse runs behind the photo and the duration
/// box keeps its space at opacity 0. Accent = `brand.rose` (lime / purple).
class CallSummary extends HookWidget {
  const CallSummary({super.key, required this.ended});

  final bool ended;

  @override
  Widget build(BuildContext context) {
    final (name, url, remoteId, video, phase, instant) = useCallSelect(
      (s) => (
        nonEmpty(s.remote.name),
        s.remote.avatarUrl,
        s.remote.id,
        s.isVideo,
        s.phase,
        // A rolled-over profile call is a normal call to the caller.
        s.isSearch,
      ),
    );
    final accent = context.colors.accent;
    final size = 128.sw;
    final statusKey = ended
        ? 'call:status.ended'
        : callStatusKey(phase, instant: instant);
    final nameKey = instant && name == null
        ? 'call:name.finding'
        : 'call:name.host';

    final avatarAndName = Column(
      key: ValueKey(remoteId ?? url ?? name ?? 'empty'),
      mainAxisSize: MainAxisSize.min,
      children: [
        SizedBox.square(
          dimension: size,
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              if (!ended) CallPulse(size: size, color: accent),
              CallAvatarRing(size: size, color: accent, url: url),
            ],
          ),
        ),
        SizedBox(height: 24.vs),
        name == null
            ? CText(
                nameKey,
                color: AppColors.white,
                weight: FontWeight.w900,
                size: 30,
                letterSpacing: -0.35,
                align: TextAlign.center,
                maxLines: 2,
              )
            : CText.raw(
                name,
                color: AppColors.white,
                weight: FontWeight.w900,
                size: 30,
                letterSpacing: -0.35,
                align: TextAlign.center,
                maxLines: 2,
              ),
      ],
    );

    // The Talk Now search: a galaxy, not the hosts being rung one by one.
    final searching = instant && !ended && phase.isPreConnect;
    // Only the galaxy (and "Ringing" under it): no host's name until one
    // has connected.
    final searchView = SearchGalaxy(
      key: const ValueKey('call-search-view'),
      size: 220.sw,
    );

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (instant && !ended)
          AnimatedSwitcher(
            duration: CallMotion.timing,
            switchInCurve: CallMotion.ease,
            switchOutCurve: CallMotion.ease,
            transitionBuilder: (child, animation) => FadeTransition(
              opacity: animation,
              child: SlideTransition(
                position: animation.drive(
                  Tween(begin: const Offset(0, 0.05), end: Offset.zero),
                ),
                child: child,
              ),
            ),
            child: searching ? searchView : avatarAndName,
          )
        else
          avatarAndName,
        Padding(
          padding: EdgeInsets.only(top: 8.vs),
          child: _Status(labelKey: statusKey, color: accent),
        ),
        if (!searching)
          Padding(
            padding: EdgeInsets.only(top: 16.vs),
            child: CText(
              callTypeKey(video: video),
              color: AppColors.whiteA(0.85),
              weight: FontWeight.w800,
              size: 20,
              align: TextAlign.center,
            ),
          ),
        Padding(
          padding: EdgeInsets.only(top: 32.vs),
          child: ended
              ? const _Duration()
              // Same box, invisible: the summary does not jump at the end.
              : Opacity(opacity: 0, child: _durationText('00:00', accent)),
        ),
      ],
    );
  }
}

Widget _durationText(String text, Color color) => CText.raw(
  text,
  color: color,
  weight: FontWeight.w900,
  size: 21,
  height: 28,
  letterSpacing: 2.1,
  align: TextAlign.center,
);

/// Final talk time (wall clock), "Declined", or "Everyone's busy" (instant).
class _Duration extends HookWidget {
  const _Duration();

  @override
  Widget build(BuildContext context) {
    final (connected, seconds, instant) = useCallSelect(
      (s) => (
        s.everConnected,
        s.everConnected ? s.durationSeconds() : 0,
        s.isSearch,
      ),
    );
    final label = connected
        ? formatCallTime(seconds)
        : context.t(
            instant ? 'call:status.everyone_busy' : 'call:status.declined',
          );
    return _durationText(label, context.colors.accent);
  }
}

/// RN status MotiText: blinks (.4 ↔ 1, 2 s legs) while there is a label,
/// fades to 0 (300 ms) when there is none (connecting / connected).
class _Status extends StatelessWidget {
  const _Status({required this.labelKey, required this.color});

  final String? labelKey;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final key = labelKey;
    final text = CText.raw(
      key == null ? ' ' : context.t(key),
      color: color,
      weight: FontWeight.w900,
      size: 10.5,
      height: 14,
      uppercase: true,
      letterSpacing: 4.2,
      align: TextAlign.center,
      maxLines: 1,
    );
    return AnimatedOpacity(
      opacity: key == null ? 0 : 1,
      duration: CallMotion.timing,
      curve: CallMotion.ease,
      child: key == null
          ? text
          : HoldBlink(
              key: ValueKey(key),
              leg: const Duration(milliseconds: 2000),
              low: 0.4,
              high: 1,
              child: text,
            ),
    );
  }
}
