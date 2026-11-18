import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';

import '../../../core/analytics/events/call_ui_events.dart';
import '../../../core/i18n/i18n.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/utils/scale.dart';
import '../../component/c_text.dart';
import 'call_avatar.dart';
import 'call_video_view.dart';
import 'helper/call_format.dart';
import 'helper/call_select.dart';
import 'helper/call_track.dart';
import 'helper/call_ui_state.dart';
import 'helper/pip_clamp.dart';

/// RN PiP self-view: 154×206 tile resting top-right (raw points, as RN),
/// draggable (clamped every frame, no snap, no fling) and tap-to-swap (a
/// press under 250 ms that moved under 8 pt). Video calls once the remote is
/// in the channel. Its position survives swaps.
class CallPip extends HookWidget {
  const CallPip({super.key});

  @override
  Widget build(BuildContext context) {
    final show = useCallSelect(
      (s) => s.isVideo && !s.phase.isPreConnect && !isCallOver(s.phase),
    );
    final (ready, hasRemote) = useMediaSelect(
      (m) => (m.engineReady, m.remoteUid != null),
    );
    if (!show || !ready || !hasRemote) return const SizedBox.shrink();
    final ui = CallScope.of(context).ui!;
    return Positioned(
      right: PipLayout.right,
      top: PipLayout.top,
      width: PipLayout.width,
      height: PipLayout.height,
      child: ValueListenableBuilder<Offset>(
        valueListenable: ui.pipOffset,
        builder: (_, offset, tile) =>
            Transform.translate(offset: offset, child: tile),
        child: _Drag(ui: ui, child: const _Tile()),
      ),
    );
  }
}

/// Raw pointer tracking (RN PanResponder): no gesture-arena delay, so the
/// tile follows the finger from the first move.
class _Drag extends StatefulWidget {
  const _Drag({required this.ui, required this.child});
  final CallUiState ui;
  final Widget child;

  @override
  State<_Drag> createState() => _DragState();
}

class _DragState extends State<_Drag> {
  Offset _start = Offset.zero;
  Offset _down = Offset.zero;
  Duration _downAt = Duration.zero;
  double _moved = 0;
  int? _pointer;

  void _onDown(PointerDownEvent e) {
    if (_pointer != null) return;
    _pointer = e.pointer;
    _start = widget.ui.pipOffset.value;
    _down = e.position;
    _downAt = e.timeStamp;
    _moved = 0;
  }

  void _onMove(PointerMoveEvent e) {
    if (e.pointer != _pointer) return;
    final delta = e.position - _down;
    if (delta.distance > _moved) _moved = delta.distance;
    final mq = MediaQuery.of(context);
    widget.ui.pipOffset.value = clampPipOffset(
      _start + delta,
      window: mq.size,
      safeTop: mq.padding.top,
      safeBottom: mq.padding.bottom,
    );
  }

  void _onUp(PointerUpEvent e) {
    if (e.pointer != _pointer) return;
    _pointer = null;
    final quick = e.timeStamp - _downAt < PipLayout.tapTime;
    if (quick && _moved < PipLayout.tapSlop) {
      final swapped = !widget.ui.swapped.value;
      widget.ui.swapped.value = swapped;
      CallUiEvents.videoSwapped(currentCallInfo(), swapped: swapped);
    }
  }

  void _onCancel(PointerCancelEvent e) {
    if (e.pointer == _pointer) _pointer = null;
  }

  @override
  Widget build(BuildContext context) => Listener(
    behavior: HitTestBehavior.opaque,
    onPointerDown: _onDown,
    onPointerMove: _onMove,
    onPointerUp: _onUp,
    onPointerCancel: _onCancel,
    child: widget.child,
  );
}

class _Tile extends HookWidget {
  const _Tile();

  @override
  Widget build(BuildContext context) {
    final (remoteName, remoteUrl, channel) = useCallSelect(
      (s) => (nonEmpty(s.shownName), s.shownAvatar, s.channelName),
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
    final me = localCallUser();

    final Widget? content;
    final String label;
    if (swapped) {
      label = remoteName ?? context.t('call:name.host');
      content = m.remoteOff
          ? CallAvatarTile(
              name: remoteName ?? context.t('call:name.user'),
              url: remoteUrl,
            )
          : ClipRRect(
              borderRadius: BorderRadius.circular(18.sw),
              child: callRemoteVideo(
                engineReady: m.ready,
                uid: m.uid,
                viewKey: m.remoteKey,
                channel: channel,
                tag: 'pip',
              ),
            );
    } else {
      label = me.name ?? context.t('call:name.you');
      content = m.localOff
          ? CallAvatarTile(
              name: me.name ?? context.t('call:name.you'),
              url: me.avatarUrl,
            )
          : callLocalVideo(
              engineReady: m.ready,
              viewKey: m.localKey,
              front: m.front,
              tag: 'pip',
            );
    }

    return Container(
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: AppColors.black,
        borderRadius: BorderRadius.circular(PipLayout.radius),
        border: Border.all(color: AppColors.whiteA(0.28)),
        boxShadow: [
          BoxShadow(
            color: AppColors.blackA(0.28),
            blurRadius: 16,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Stack(
        fit: StackFit.expand,
        children: [
          ?content,
          Positioned(
            left: 4,
            right: 4,
            bottom: 4,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
              child: CText.raw(
                label,
                color: AppColors.whiteA(0.8),
                weight: FontWeight.w800,
                uppercase: true,
                maxLines: 1,
                style: const TextStyle(fontSize: 10),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
