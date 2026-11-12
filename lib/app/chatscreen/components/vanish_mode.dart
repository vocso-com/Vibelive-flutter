import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../core/i18n/i18n.dart';
import '../../../core/utils/scale.dart';
import '../../api/chat/chat_models.dart';
import '../../component/c_text.dart';
import '../../component/c_toast.dart';
import '../../component/pressable.dart';
import 'chat_palette.dart';

/// Vanish mode's look (docs/chat_api.md, 2026-11-12): a dark room, a banner
/// on top with "Turn off", and the swipe-up handle above the composer.
abstract final class VanishLook {
  /// The chat's background while vanish mode is on (both themes).
  static const backdrop = Color(0xFF0E0E14);
  static const ink = Color(0xFFF4F4F8);
  static const inkMuted = Color(0xFFB4B4C4);
  static const accent = Color(0xFF8B5CF6);
}

/// The thin strip above the composer: drag it up (from the bottom towards the
/// top) far enough and vanish mode switches — on, or off again when it is on.
/// A tap only explains; screen readers get the switch as the tap action.
class VanishSwipeHandle extends StatefulWidget {
  const VanishSwipeHandle({
    super.key,
    required this.on,
    required this.onSwitch,
    this.enabled = true,
  });

  final bool on;
  final VoidCallback onSwitch;

  /// False while the chat has no conversation yet (nothing to switch).
  final bool enabled;

  /// How far up a drag must go to switch (logical pixels).
  static const threshold = 72.0;

  @override
  State<VanishSwipeHandle> createState() => _VanishSwipeHandleState();
}

class _VanishSwipeHandleState extends State<VanishSwipeHandle> {
  double _pulled = 0;
  bool _armed = false;

  void _update(DragUpdateDetails d) {
    final next = (_pulled - d.delta.dy).clamp(0.0, VanishSwipeHandle.threshold * 1.4);
    final armed = next >= VanishSwipeHandle.threshold;
    if (armed && !_armed) HapticFeedback.selectionClick();
    setState(() {
      _pulled = next;
      _armed = armed;
    });
  }

  void _end([DragEndDetails? _]) {
    final fire = _armed;
    setState(() {
      _pulled = 0;
      _armed = false;
    });
    if (!fire) return;
    if (!widget.enabled) {
      CToast.show('chat:vanish.needs_chat');
      return;
    }
    HapticFeedback.mediumImpact();
    widget.onSwitch();
  }

  @override
  Widget build(BuildContext context) {
    final p = ChatPalette.of(context);
    final progress = (_pulled / VanishSwipeHandle.threshold).clamp(0.0, 1.0);
    final color = widget.on ? VanishLook.inkMuted : p.muted;
    final label = widget.on ? 'chat:vanish.swipe_off' : 'chat:vanish.swipe_on';
    return Semantics(
      button: true,
      label: context.t(widget.on ? 'chat:vanish.turn_off' : 'chat:vanish.turn_on'),
      onTap: widget.enabled ? widget.onSwitch : null,
      excludeSemantics: true,
      child: GestureDetector(
        key: const ValueKey('chat-vanish-handle'),
        behavior: HitTestBehavior.opaque,
        onTap: () => CToast.show(label),
        onVerticalDragUpdate: _update,
        onVerticalDragEnd: _end,
        onVerticalDragCancel: _end,
        child: Padding(
          padding: EdgeInsets.only(top: 4.ms, bottom: 2.ms),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Transform.translate(
                offset: Offset(0, -10.ms * progress),
                child: Icon(
                  LucideIcons.chevronsUp,
                  size: 16.ms,
                  color: Color.lerp(color, VanishLook.accent, progress),
                ),
              ),
              AnimatedSwitcher(
                duration: const Duration(milliseconds: 150),
                child: CText(
                  _armed ? 'chat:vanish.release' : label,
                  key: ValueKey(_armed ? 'armed' : label),
                  size: 11.5,
                  weight: FontWeight.w700,
                  color: _armed ? VanishLook.accent : color,
                  maxLines: 1,
                ),
              ),
              SizedBox(height: 3.ms),
              // How far the drag has come.
              ClipRRect(
                borderRadius: BorderRadius.circular(99),
                child: SizedBox(
                  width: 44.ms,
                  height: 3.ms,
                  child: LinearProgressIndicator(
                    value: progress,
                    backgroundColor: color.withValues(alpha: 0.25),
                    valueColor: const AlwaysStoppedAnimation(VanishLook.accent),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// On top of the messages while vanish mode is on: what it means and the way
/// out.
class VanishBanner extends StatelessWidget {
  const VanishBanner({
    super.key,
    required this.info,
    required this.peerName,
    required this.onTurnOff,
    this.busy = false,
  });

  final ChatVanishInfo info;
  final String peerName;
  final VoidCallback onTurnOff;
  final bool busy;

  @override
  Widget build(BuildContext context) {
    return Container(
      key: const ValueKey('chat-vanish-banner'),
      width: double.infinity,
      color: VanishLook.backdrop,
      padding: EdgeInsetsDirectional.fromSTEB(14.ms, 10.ms, 10.ms, 10.ms),
      child: Row(
        children: [
          Container(
            padding: EdgeInsets.all(7.ms),
            decoration: BoxDecoration(
              color: VanishLook.accent.withValues(alpha: 0.2),
              shape: BoxShape.circle,
            ),
            child: Icon(LucideIcons.flame, size: 16.ms, color: VanishLook.accent),
          ),
          SizedBox(width: 10.ms),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                CText(
                  info.byMe ? 'chat:vanish.on_by_me' : 'chat:vanish.on_by_peer',
                  variables: {'name': peerName},
                  size: 13.5,
                  weight: FontWeight.w800,
                  color: VanishLook.ink,
                  maxLines: 1,
                ),
                SizedBox(height: 2.ms),
                const CText(
                  'chat:vanish.explain',
                  size: 11.5,
                  weight: FontWeight.w500,
                  color: VanishLook.inkMuted,
                  maxLines: 2,
                ),
              ],
            ),
          ),
          SizedBox(width: 8.ms),
          Pressable(
            key: const ValueKey('chat-vanish-turn-off'),
            onPressed: busy ? null : onTurnOff,
            child: Container(
              padding: EdgeInsets.symmetric(horizontal: 12.ms, vertical: 7.ms),
              decoration: BoxDecoration(
                border: Border.all(color: VanishLook.inkMuted.withValues(alpha: 0.5)),
                borderRadius: BorderRadius.circular(999),
              ),
              child: CText(
                'chat:vanish.turn_off',
                size: 12,
                weight: FontWeight.w800,
                color: busy ? VanishLook.inkMuted : VanishLook.ink,
                maxLines: 1,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// When vanish mode is on and nothing waits yet.
class VanishEmpty extends StatelessWidget {
  const VanishEmpty({super.key});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: EdgeInsets.symmetric(horizontal: 32.ms),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(LucideIcons.flame, size: 34.ms, color: VanishLook.accent),
            SizedBox(height: 10.ms),
            const CText(
              'chat:vanish.empty_title',
              size: 15,
              weight: FontWeight.w800,
              color: VanishLook.ink,
              align: TextAlign.center,
            ),
            SizedBox(height: 4.ms),
            const CText(
              'chat:vanish.empty',
              size: 12.5,
              weight: FontWeight.w500,
              color: VanishLook.inkMuted,
              align: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}
