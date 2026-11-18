import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:go_router/go_router.dart';

import '../../../core/analytics/events/call_ui_events.dart';
import '../../../core/analytics/screen_tracker.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/utils/scale.dart';
import '../../component/status_bar_style.dart';
import '../../component/vibe_background.dart';
import '../helper/call_actions.dart';
import '../helper/call_controller.dart';
import '../helper/call_session.dart';
import '../helper/engine/call_engine.dart';
import 'call_body.dart';
import 'call_controls.dart';
import 'call_header.dart';
import 'call_permission_bar.dart';
import 'call_safety_panel.dart';
import 'call_topup.dart';
import 'feedback_sheet.dart';
import 'helper/call_format.dart';
import 'helper/call_nav.dart';
import 'helper/call_select.dart';
import 'helper/call_track.dart';
import 'helper/call_ui_state.dart';
import 'helper/post_call.dart';

/// `/call` (RN `CallingScreen`): outgoing calling / ringing, connecting,
/// the live call and the ended summary. Always dark with light status-bar
/// icons, no swipe-back. Back minimizes (the call keeps running; Home shows
/// the return-to-call bar). Once ended: the caller of a connected call
/// rates it, everyone else sees the summary for 1.2 s, then Home.
class CallScreen extends HookWidget {
  const CallScreen({super.key});

  @override
  Widget build(BuildContext context) {
    // Everything per call is keyed on the callId: a screen still mounted for
    // a finished call never shows (or rates) it for the next one (U5).
    final callKey = useCallKey();
    final sticky = useMemoized(
      () => StickySession(CallController.instance.session),
      [callKey],
    );
    useEffect(() => sticky.dispose, [sticky]);
    final ui = useMemoized(CallUiState.new, [callKey]);
    useEffect(() => ui.dispose, [ui]);
    final runner = useMemoized(
      () => PostCallRunner(
        onFeedback: () => _rate(context, sticky.value),
        onExit: () => CallActions.exitToHome(callId: callKey),
        isOnTop: () => callScreenOnTop(context),
      ),
      [callKey],
    );
    _useCallLifecycle(context, runner, callKey);
    _useSwapReset(ui);

    return PopScope(
      canPop: false,
      // System back (Android) = the header's back: close the safety panel,
      // else minimise a live call (RN left the screen and kept the call).
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) return;
        if (ui.safetyOpen.value) {
          _toggleSafety(ui);
        } else {
          _back(callKey);
        }
      },
      child: ThemedStatusBar(
        darkBackground: true,
        child: Material(
          color: AppColors.black,
          child: CallScope(
            session: sticky,
            ui: ui,
            child: Stack(
              fit: StackFit.expand,
              children: [
                const VibeBackground(dark: true),
                const CallBody(),
                // RN: absolute top (U1: a bare Stack child would centre).
                Positioned(
                  top: 0,
                  left: 0,
                  right: 0,
                  child: CallHeader(
                    onBack: () => _back(callKey),
                    onFlag: () => _toggleSafety(ui),
                  ),
                ),
                const _PermissionLayer(),
                // "Add money" when the balance or free minutes run out soon;
                // the post-call step waits while it is in use.
                CallTopUpLayer(onHold: runner.hold),
                ValueListenableBuilder<bool>(
                  valueListenable: ui.safetyOpen,
                  builder: (_, open, _) => open
                      ? CallSafetyPanel(onHold: runner.hold)
                      : const SizedBox.shrink(),
                ),
                const CallControls(),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// Decision 1: back never drops a live call.
  static void _back(String? callId) {
    final s = CallController.instance.value;
    if (s.phase.isActive) {
      CallUiEvents.minimized(callInfoOf(s));
      CallActions.minimize();
    } else {
      CallActions.exitToHome(callId: callId);
    }
  }

  /// Header flag: the "Something wrong?" panel.
  static void _toggleSafety(CallUiState ui) {
    final open = !ui.safetyOpen.value;
    ui.safetyOpen.value = open;
    final call = currentCallInfo();
    if (open) {
      CallUiEvents.safetyPanelOpened(call);
      ScreenTracker.view('call_safety_panel');
    } else {
      CallUiEvents.safetyPanelClosed(call);
    }
  }

  /// RN `FeedBackModal` for the caller; every way out of it leaves (unless
  /// something else already took the user away from the call screen).
  static Future<void> _rate(BuildContext context, CallSession call) async {
    if (!context.mounted) return;
    final remote = call.remote;
    final target = remote.id ?? call.callerId ?? call.receiverId;
    await showFeedbackSheet(
      context,
      name: nonEmpty(remote.name),
      canBlock: target != null,
    );
    if (context.mounted && callScreenOnTop(context)) {
      CallActions.exitToHome(callId: call.callId);
    }
  }
}

/// Ended → the post-call step (once per call). Reset to idle without an
/// ended step (e.g. a cancel push while calling), or mounted with no call →
/// Home now. Neither acts while another page is pushed over `/call` (U4):
/// they run when the call screen is back on top, except that a call the
/// logic reset meanwhile just leaves (no summary, no rating).
void _useCallLifecycle(
  BuildContext context,
  PostCallRunner runner,
  String? callId,
) {
  useEffect(() {
    final session = CallController.instance.session;
    final router = GoRouter.maybeOf(context);
    void check() {
      if (!context.mounted) return;
      final phase = session.value.phase;
      if (phase == CallPhase.ended) {
        runner.start();
      } else if (phase == CallPhase.idle &&
          !runner.started &&
          callScreenOnTop(context)) {
        CallActions.exitToHome(callId: callId);
      }
    }

    // Router notifications come mid-navigation (the navigator is locked):
    // act after the frame.
    void onRoute() {
      if (!callScreenOnTop(context)) return;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!callScreenOnTop(context)) return;
        final now = session.value;
        runner.resume(
          quietly: now.phase == CallPhase.idle || now.callId != callId,
        );
        check();
      });
    }

    session.addListener(check);
    router?.routerDelegate.addListener(onRoute);
    WidgetsBinding.instance.addPostFrameCallback((_) => check());
    return () {
      session.removeListener(check);
      router?.routerDelegate.removeListener(onRoute);
      runner.dispose();
    };
  }, [runner]);
}

/// The remote left the channel: swap back (RN resets the layout).
void _useSwapReset(CallUiState ui) {
  useEffect(() {
    final media = CallEngine.instance.media;
    void onMedia() {
      if (media.value.remoteUid == null) ui.swapped.value = false;
    }

    media.addListener(onMedia);
    return () => media.removeListener(onMedia);
  }, [ui]);
}

/// RN: absolute left/right ms16, top = safe top + ms72 (+ the bar's own
/// ms8 margin).
class _PermissionLayer extends HookWidget {
  const _PermissionLayer();

  @override
  Widget build(BuildContext context) {
    final video = useCallSelect((s) => s.isVideo);
    return Positioned(
      left: 16.ms,
      right: 16.ms,
      top: MediaQuery.paddingOf(context).top + 72.ms,
      child: CallPermissionBar(needsCamera: video, floating: true),
    );
  }
}
