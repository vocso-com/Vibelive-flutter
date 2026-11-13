import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';

import '../../../core/i18n/i18n.dart';
import '../../../core/utils/scale.dart';
import '../../api/chat/chat_models.dart';
import '../../component/c_text.dart';
import '../../component/pressable.dart';
import 'chat_palette.dart';

/// Vanish mode, the way Instagram does it (docs/chat_api.md, 2026-11-12):
///  - swipe the conversation up past its newest message: a ring fills under
///    it ("Swipe up to turn on vanish mode" → "Release to turn on");
///  - let go: the whole chat fades into a dark room at once, a few 🤫 fall,
///    and a notice sits at the top of the conversation;
///  - the same swipe, or "Turn off" in the header, turns it off.
/// Nothing here takes layout height of its own, so nothing can overflow.

/// How far past the newest message the list must be pulled (after the
/// list's own rubber-band friction) to switch.
const double kVanishPullThreshold = 72;

/// Reads pulls past the newest message of a reversed list and reports how
/// far ([pull]) and when one was released far enough ([onRelease]).
///
/// One swipe is one switch, never two: a pull only counts when the drag
/// STARTED at the newest message (a fast scroll down that overshoots is not
/// a pull), it fires once, on the finger leaving, and nothing fires again
/// for [cooldown] — the list springing back, being swapped for the vanish
/// one, or the keyboard closing cannot count as another pull.
class VanishPull {
  VanishPull({
    required this.onRelease,
    this.cooldown = const Duration(milliseconds: 1500),
    DateTime Function()? now,
  }) : _now = now ?? DateTime.now;

  final VoidCallback onRelease;
  final Duration cooldown;
  final DateTime Function() _now;
  final pull = ValueNotifier<double>(0);
  bool _dragging = false;
  bool _fromEdge = false;
  bool _armed = false;
  DateTime? _quietUntil;

  bool get _quiet {
    final until = _quietUntil;
    return until != null && _now().isBefore(until);
  }

  /// From the list's [NotificationListener]. Never consumes.
  bool onNotification(ScrollNotification n) {
    if (n.depth != 0) return false;
    final m = n.metrics;
    // Reversed list: the newest message is at the minimum extent; a user
    // pulling up past it drives the offset below it (rubber band).
    final past = math.max(0.0, m.minScrollExtent - m.pixels);
    if (n is ScrollStartNotification) {
      if (n.dragDetails != null) {
        _dragging = true;
        _armed = false;
        _fromEdge = m.pixels <= m.minScrollExtent + 8;
      }
    } else if (n is ScrollUpdateNotification) {
      if (n.dragDetails != null) {
        _dragging = true;
        if (_fromEdge) _set(past);
      } else if (_dragging) {
        _release();
      } else {
        // Springing back: let the ring follow the list down.
        pull.value = math.min(pull.value, past);
      }
    } else if (n is OverscrollNotification && n.dragDetails != null) {
      // A clamping list (no rubber band): add up what it refused.
      _dragging = true;
      if (_fromEdge && n.overscroll < 0) {
        _set(pull.value - n.overscroll * 0.5);
      }
    } else if (n is ScrollEndNotification) {
      if (_dragging) _release();
      pull.value = 0;
    } else if (n is UserScrollNotification &&
        n.direction == ScrollDirection.idle &&
        _dragging) {
      _release();
    }
    return false;
  }

  void _set(double value) {
    if (_quiet) {
      pull.value = 0;
      return;
    }
    pull.value = value;
    final armed = value >= kVanishPullThreshold;
    if (armed && !_armed) HapticFeedback.selectionClick();
    _armed = armed;
  }

  void _release() {
    _dragging = false;
    _fromEdge = false;
    final fire = _armed && !_quiet;
    _armed = false;
    if (!fire) return;
    _quietUntil = _now().add(cooldown);
    HapticFeedback.mediumImpact();
    onRelease();
  }

  void dispose() => pull.dispose();
}

/// The ring under the newest message while it is being pulled. Positioned by
/// the list, over the content (no height of its own).
class VanishPullIndicator extends StatelessWidget {
  const VanishPullIndicator({
    super.key,
    required this.pull,
    required this.on,
    this.tip = false,
  });

  final ValueListenable<double> pull;

  /// Vanish mode is on now (the pull turns it off).
  final bool on;

  /// Played as the first-time tip: the label sits in a pill with "NEW".
  final bool tip;

  @override
  Widget build(BuildContext context) {
    final p = ChatPalette.of(context);
    return IgnorePointer(
      child: ValueListenableBuilder<double>(
        valueListenable: pull,
        builder: (context, value, _) {
          if (value <= 2) return const SizedBox.shrink();
          final progress = (value / kVanishPullThreshold).clamp(0.0, 1.0);
          final armed = progress >= 1;
          final label = armed
              ? (on ? 'chat:vanish.release_off' : 'chat:vanish.release_on')
              : (on ? 'chat:vanish.swipe_off' : 'chat:vanish.swipe_on');
          return Opacity(
            opacity: Curves.easeOut.transform(math.min(1, progress * 1.6)),
            child: Padding(
              padding: EdgeInsets.only(bottom: 6.ms),
              child: Column(
                key: const ValueKey('chat-vanish-pull'),
                mainAxisSize: MainAxisSize.min,
                children: [
                  SizedBox.square(
                    dimension: 34.ms,
                    child: Stack(
                      alignment: Alignment.center,
                      children: [
                        Positioned.fill(
                          child: CircularProgressIndicator(
                            value: progress,
                            strokeWidth: 2.4,
                            backgroundColor: p.muted.withValues(alpha: 0.2),
                            valueColor: AlwaysStoppedAnimation(
                              armed ? ChatPalette.vanish.accent : p.muted,
                            ),
                          ),
                        ),
                        AnimatedScale(
                          scale: armed ? 1.15 : 0.9,
                          duration: const Duration(milliseconds: 160),
                          curve: Curves.easeOutBack,
                          child: Text('🤫', style: TextStyle(fontSize: 15.ms)),
                        ),
                      ],
                    ),
                  ),
                  SizedBox(height: 6.ms),
                  Padding(
                    padding: EdgeInsets.symmetric(horizontal: 20.ms),
                    child: tip
                        ? _TipPill(label: label)
                        : CText(
                            label,
                            size: 12,
                            weight: FontWeight.w700,
                            color: armed ? p.text : p.muted,
                            align: TextAlign.center,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}

/// The first-time tip's label: "NEW" and the hint, in a soft pill.
class _TipPill extends StatelessWidget {
  const _TipPill({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    final p = ChatPalette.of(context);
    const violet = Color(0xFF8B5CF6);
    return Container(
      key: const ValueKey('chat-vanish-tip'),
      padding: EdgeInsetsDirectional.fromSTEB(5.ms, 4.ms, 11.ms, 4.ms),
      decoration: BoxDecoration(
        color: p.bar,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: violet.withValues(alpha: 0.45)),
        boxShadow: [
          BoxShadow(color: violet.withValues(alpha: 0.18), blurRadius: 12),
        ],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            padding: EdgeInsets.symmetric(horizontal: 7.ms, vertical: 2.ms),
            decoration: BoxDecoration(
              color: violet,
              borderRadius: BorderRadius.circular(999),
            ),
            child: const CText(
              'chat:vanish.new',
              size: 10,
              weight: FontWeight.w900,
              color: Color(0xFFFFFFFF),
              maxLines: 1,
            ),
          ),
          SizedBox(width: 7.ms),
          Flexible(
            child: CText(
              label,
              size: 12,
              weight: FontWeight.w700,
              color: p.text,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }
}

/// Where the call buttons sit when vanish mode is off: one small "Turn off".
class VanishOffPill extends StatelessWidget {
  const VanishOffPill({super.key, required this.onTap, this.busy = false});

  final VoidCallback onTap;
  final bool busy;

  @override
  Widget build(BuildContext context) {
    final p = ChatPalette.of(context);
    return ConstrainedBox(
      constraints: BoxConstraints(maxWidth: 120.ms),
      child: Pressable(
        key: const ValueKey('chat-vanish-turn-off'),
        onPressed: busy ? null : onTap,
        semanticLabel: context.t('chat:vanish.turn_off'),
        child: Container(
          height: 32.ms,
          margin: EdgeInsetsDirectional.only(end: 2.ms),
          padding: EdgeInsets.symmetric(horizontal: 11.ms),
          decoration: BoxDecoration(
            color: p.accent.withValues(alpha: 0.16),
            borderRadius: BorderRadius.circular(999),
            border: Border.all(color: p.accent.withValues(alpha: 0.45)),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('🤫', style: TextStyle(fontSize: 12.ms)),
              SizedBox(width: 5.ms),
              Flexible(
                child: CText(
                  'chat:vanish.turn_off',
                  size: 12,
                  weight: FontWeight.w800,
                  color: p.text,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// At the top of the conversation in vanish mode (it scrolls with the
/// messages): who turned it on and what it means.
class VanishNotice extends StatelessWidget {
  const VanishNotice({super.key, required this.info, required this.peerName});

  final ChatVanishInfo info;
  final String peerName;

  @override
  Widget build(BuildContext context) {
    final p = ChatPalette.of(context);
    return Padding(
      key: const ValueKey('chat-vanish-notice'),
      padding: EdgeInsets.fromLTRB(32.ms, 18.ms, 32.ms, 14.ms),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text('🤫', style: TextStyle(fontSize: 30.ms)),
          SizedBox(height: 8.ms),
          CText(
            info.byMe ? 'chat:vanish.on_by_me' : 'chat:vanish.on_by_peer',
            variables: {'name': peerName},
            size: 14,
            weight: FontWeight.w800,
            color: p.text,
            align: TextAlign.center,
          ),
          SizedBox(height: 4.ms),
          CText(
            'chat:vanish.explain',
            size: 12.5,
            weight: FontWeight.w500,
            color: p.muted,
            align: TextAlign.center,
          ),
        ],
      ),
    );
  }
}

/// A short fall of 🤫 from the top when vanish mode comes on (once per
/// [trigger] change). Paints only itself; never takes a touch.
class VanishBurst extends StatefulWidget {
  const VanishBurst({super.key, required this.trigger});

  /// Bumped to play it.
  final ValueListenable<int> trigger;

  @override
  State<VanishBurst> createState() => _VanishBurstState();
}

class _VanishBurstState extends State<VanishBurst>
    with SingleTickerProviderStateMixin {
  // Made up front (not lazily): a lazy one would first be created in
  // dispose(), when this element can no longer look up its ticker mode.
  late final AnimationController _anim;
  List<_Drop> _drops = const [];

  @override
  void initState() {
    super.initState();
    _anim = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1700),
    );
    widget.trigger.addListener(_play);
  }

  @override
  void dispose() {
    widget.trigger.removeListener(_play);
    _anim.dispose();
    super.dispose();
  }

  void _play() {
    final r = math.Random();
    setState(() {
      _drops = [
        for (var i = 0; i < 9; i++)
          _Drop(
            x: 0.06 + r.nextDouble() * 0.88,
            delay: r.nextDouble() * 0.35,
            size: 20 + r.nextDouble() * 14,
            drift: (r.nextDouble() - 0.5) * 0.12,
            spin: (r.nextDouble() - 0.5) * 0.9,
          ),
      ];
    });
    _anim.forward(from: 0);
  }

  @override
  Widget build(BuildContext context) {
    if (_drops.isEmpty) return const SizedBox.shrink();
    return IgnorePointer(
      child: RepaintBoundary(
        child: AnimatedBuilder(
          animation: _anim,
          builder: (context, _) {
            if (_anim.isDismissed || _anim.isCompleted) {
              return const SizedBox.shrink();
            }
            return LayoutBuilder(
              builder: (context, box) => Stack(
                children: [
                  for (final d in _drops) _drop(d, box),
                ],
              ),
            );
          },
        ),
      ),
    );
  }

  Widget _drop(_Drop d, BoxConstraints box) {
    final t = ((_anim.value - d.delay) / (1 - d.delay)).clamp(0.0, 1.0);
    final y = Curves.easeIn.transform(t) * (box.maxHeight * 0.75) - 40;
    final fade = t < 0.75 ? 1.0 : (1 - (t - 0.75) / 0.25);
    return Positioned(
      left: (d.x + d.drift * t) * box.maxWidth,
      top: y,
      child: Opacity(
        opacity: t == 0 ? 0 : fade,
        child: Transform.rotate(
          angle: d.spin * t,
          child: Text('🤫', style: TextStyle(fontSize: d.size.ms)),
        ),
      ),
    );
  }
}

@immutable
class _Drop {
  const _Drop({
    required this.x,
    required this.delay,
    required this.size,
    required this.drift,
    required this.spin,
  });

  final double x;
  final double delay;
  final double size;
  final double drift;
  final double spin;
}
