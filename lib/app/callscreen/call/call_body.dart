import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';

import '../../../core/i18n/i18n.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/utils/scale.dart';
import '../../component/c_text.dart';
import 'call_avatar.dart';
import 'call_pip.dart';
import 'call_summary.dart';
import 'call_video_view.dart';
import 'helper/call_format.dart';
import 'helper/call_select.dart';
import 'helper/call_ui_state.dart';

/// RN `CallBody`: video layer, bottom-left name, PiP self-view, the active
/// summary card and the ended blocker. Each layer listens to the fields it
/// draws only. All video goes the instant the call ends (RN crash
/// workaround); the blocker covers that.
class CallBody extends StatelessWidget {
  const CallBody({super.key});

  @override
  Widget build(BuildContext context) => const Stack(
    fit: StackFit.expand,
    clipBehavior: Clip.hardEdge,
    children: [
      _VideoLayer(),
      _NameLabel(),
      CallPip(),
      _InfoCard(),
      _EndedBlocker(),
    ],
  );
}

class _VideoLayer extends HookWidget {
  const _VideoLayer();

  @override
  Widget build(BuildContext context) {
    final (video, over, remoteName, remoteUrl, channel) = useCallSelect(
      (s) => (
        s.isVideo,
        isCallOver(s.phase),
        nonEmpty(s.shownName),
        s.shownAvatar,
        s.channelName,
      ),
    );
    final m = useMediaSelect(
      (m) => (
        ready: m.engineReady,
        uid: m.remoteUid,
        remoteOff: m.remoteVideoOff,
        localOff: m.localVideoOff,
        front: m.frontCamera,
        localKey: m.localViewKey,
        remoteKey: m.remoteViewKey,
      ),
    );
    final swapped = useValueListenable(CallScope.of(context).ui!.swapped);

    Widget? layer;
    if (video && m.ready && !over) {
      if (m.uid != null && !swapped) {
        layer = m.remoteOff
            ? CallAvatarTile(
                full: true,
                name: remoteName ?? context.t('call:name.user'),
                url: remoteUrl,
                background: DarkColors.splashBackground,
              )
            : callRemoteVideo(
                engineReady: m.ready,
                uid: m.uid,
                viewKey: m.remoteKey,
                channel: channel,
              );
      } else if (m.localOff) {
        final me = localCallUser();
        layer = CallAvatarTile(
          full: true,
          name: me.name ?? context.t('call:name.you'),
          url: me.avatarUrl,
        );
      } else {
        layer = callLocalVideo(
          engineReady: m.ready,
          viewKey: m.localKey,
          front: m.front,
        );
      }
    }
    return ColoredBox(color: AppColors.black, child: layer);
  }
}

/// Whose video is full screen, bottom-left (remote unless swapped).
class _NameLabel extends HookWidget {
  const _NameLabel();

  @override
  Widget build(BuildContext context) {
    final (show, remoteName) = useCallSelect(
      (s) => (
        s.isVideo && !s.phase.isPreConnect && !isCallOver(s.phase),
        nonEmpty(s.remote.name),
      ),
    );
    final ready = useMediaSelect((m) => m.engineReady);
    final swapped = useValueListenable(CallScope.of(context).ui!.swapped);
    if (!show || !ready) return const SizedBox.shrink();
    final name = swapped
        ? (localCallUser().name ?? context.t('call:name.you'))
        : (remoteName ?? context.t('call:name.expert'));
    return Positioned(
      left: 20.sw,
      bottom: 140.vs,
      child: Padding(
        padding: EdgeInsets.all(4.sw),
        child: CText.raw(
          name,
          color: AppColors.whiteA(0.7),
          size: 14,
          weight: FontWeight.w900,
          letterSpacing: 1.5,
          uppercase: true,
          maxLines: 1,
        ),
      ),
    );
  }
}

/// Audio calls, and video calls before the answer: the summary card (over
/// the own camera on video, and then untouchable).
class _InfoCard extends HookWidget {
  const _InfoCard();

  @override
  Widget build(BuildContext context) {
    final (show, video) = useCallSelect(
      (s) => (
        (!s.isVideo || s.phase.isPreConnect) && !isCallOver(s.phase),
        s.isVideo,
      ),
    );
    if (!show) return const SizedBox.shrink();
    return IgnorePointer(
      ignoring: video,
      child: const _SummaryPage(ended: false),
    );
  }
}

/// The call is over: an opaque page (swallows taps) with the final summary.
class _EndedBlocker extends HookWidget {
  const _EndedBlocker();

  @override
  Widget build(BuildContext context) {
    final over = useCallSelect((s) => isCallOver(s.phase));
    if (!over) return const SizedBox.shrink();
    return const ColoredBox(
      color: DarkColors.bg,
      child: _SummaryPage(ended: true),
    );
  }
}

/// RN summary SafeAreaView: top = safe top + vs160, sides 28.
class _SummaryPage extends StatelessWidget {
  const _SummaryPage({required this.ended});
  final bool ended;

  @override
  Widget build(BuildContext context) => Padding(
    padding: EdgeInsets.fromLTRB(
      28,
      MediaQuery.paddingOf(context).top + 160.vs,
      28,
      0,
    ),
    // Clips instead of overflowing on a small phone.
    child: SingleChildScrollView(
      physics: const NeverScrollableScrollPhysics(),
      child: Center(child: CallSummary(ended: ended)),
    ),
  );
}
