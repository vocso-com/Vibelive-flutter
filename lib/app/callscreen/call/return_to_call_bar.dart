import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../core/analytics/events/call_ui_events.dart';
import '../../../core/i18n/i18n.dart';
import '../../../core/router/app_router.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/utils/scale.dart';
import '../../component/c_text.dart';
import '../../component/pressable.dart';
import '../helper/call_actions.dart';
import '../helper/call_controller.dart';
import '../helper/call_session.dart';
import 'helper/call_format.dart';
import 'helper/call_nav.dart';
import 'helper/call_select.dart';
import 'helper/call_track.dart';

/// Slim green "return to call" pill (decision 1: back on the call screen
/// minimizes instead of dropping the call, as RN silently did). Visible
/// while a call is in progress and the call screen is not showing; tap →
/// [CallActions.returnToCall]. A receiver's ring is not "in progress" here:
/// the incoming screen / CallKit own it.
class ReturnToCallBar extends HookWidget {
  const ReturnToCallBar({super.key});

  @override
  Widget build(BuildContext context) {
    final (show, name, phase, search) = useSelect(
      CallController.instance.session,
      (s) => (
        s.phase.isActive && !(s.isReceiver && s.phase == CallPhase.ringing),
        // A Talk Now search names nobody until a host has connected.
        nonEmpty(s.shownName),
        s.phase,
        s.isSearch,
      ),
    );
    final router = GoRouter.maybeOf(context);
    final onCallScreen = useListenableSelector(
      router?.routerDelegate,
      () => callTopLocation(router).startsWith(AppRoutes.call),
    );
    if (!show || onCallScreen) return const SizedBox.shrink();

    return Padding(
      padding: EdgeInsets.fromLTRB(16.ms, 6.ms, 16.ms, 4.ms),
      child: Pressable(
        onPressed: () {
          CallUiEvents.returnTapped(callInfoOf(CallController.instance.value));
          CallActions.returnToCall();
        },
        activeOpacity: 0.85,
        semanticLabel: context.t('call:return_bar.label'),
        child: Container(
          height: 40.ms,
          padding: EdgeInsets.symmetric(horizontal: 14.ms),
          decoration: BoxDecoration(
            color: AppColors.green,
            borderRadius: BorderRadius.circular(999),
          ),
          child: Row(
            children: [
              Icon(
                LucideIcons.phone,
                size: 16.ms,
                color: AppColors.white,
                weight: 600,
              ),
              SizedBox(width: 8.ms),
              Expanded(
                flex: 3,
                child: Row(
                  children: [
                    const Flexible(
                      child: CText(
                        'call:return_bar.label',
                        color: AppColors.white,
                        size: 12,
                        weight: FontWeight.w900,
                        letterSpacing: 0.5,
                        uppercase: true,
                        maxLines: 1,
                      ),
                    ),
                    if (name != null)
                      Flexible(
                        child: CText.raw(
                          ' · $name',
                          color: AppColors.whiteA(0.85),
                          size: 12,
                          weight: FontWeight.w700,
                          maxLines: 1,
                        ),
                      ),
                  ],
                ),
              ),
              SizedBox(width: 8.ms),
              // Shrinks before it overflows (long status in Hindi).
              Flexible(
                flex: 2,
                child: _Status(phase: phase, search: search),
              ),
              SizedBox(width: 4.ms),
              Icon(
                LucideIcons.chevronRight,
                size: 16.ms,
                color: AppColors.white,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Live timer once connected, else what the call is doing.
class _Status extends StatelessWidget {
  const _Status({required this.phase, this.search = false});
  final CallPhase phase;

  /// A Talk Now search: "Ringing" (never "Calling" or "Searching").
  final bool search;

  @override
  Widget build(BuildContext context) {
    Widget label(String text) => CText.raw(
      text,
      color: AppColors.white,
      size: 13,
      weight: FontWeight.w900,
      maxLines: 1,
      style: const TextStyle(fontFeatures: [FontFeature.tabularFigures()]),
    );
    if (phase == CallPhase.ongoing) {
      return ValueListenableBuilder<int>(
        valueListenable: CallController.instance.elapsed,
        builder: (_, s, _) => label(formatCallTime(s)),
      );
    }
    final key =
        callStatusKey(phase, instant: search) ?? 'call:return_bar.connecting';
    return label(context.t(key));
  }
}
