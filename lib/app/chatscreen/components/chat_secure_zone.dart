import 'package:flutter/scheduler.dart';
import 'package:flutter/widgets.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/utils/scale.dart';
import '../../component/c_text.dart';
import '../helper/chat_screen_guard.dart';

/// A chat screen's protection (see [ChatScreenGuard]): on while [active]
/// (the admin's `screenshotProtection`, and for a tab, the tab showing) and
/// this zone's route is the top full-screen one. On iOS a recording or
/// mirroring covers the chat.
class ChatSecureZone extends StatefulWidget {
  const ChatSecureZone({super.key, required this.active, required this.child});

  final bool active;
  final Widget child;

  @override
  State<ChatSecureZone> createState() => _ChatSecureZoneState();
}

class _ChatSecureZoneState extends State<ChatSecureZone> {
  final _guard = ChatScreenGuard.instance;
  final _shown = ValueNotifier<bool>(false);
  ModalRoute<dynamic>? _route;
  bool _later = false;

  @override
  void initState() {
    super.initState();
    _guard.observer.top.addListener(_update);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _route = ModalRoute.of(context);
    _update();
  }

  @override
  void didUpdateWidget(ChatSecureZone old) {
    super.didUpdateWidget(old);
    if (old.active != widget.active) _update();
  }

  /// Route changes arrive while the navigator builds: settle after it.
  void _update() {
    if (!mounted) return;
    if (SchedulerBinding.instance.schedulerPhase ==
        SchedulerPhase.persistentCallbacks) {
      if (_later) return;
      _later = true;
      SchedulerBinding.instance.addPostFrameCallback((_) {
        _later = false;
        _update();
      });
      return;
    }
    final top = _guard.observer.top.value;
    // No observer (a widget test without the router): its own route.
    final onTop = top == null ? (_route?.isCurrent ?? true) : top == _route;
    final visible = widget.active && onTop;
    if (visible == _shown.value) return;
    _shown.value = visible;
    _guard.set(this, visible);
  }

  @override
  void dispose() {
    _guard.observer.top.removeListener(_update);
    _guard.set(this, false);
    _shown.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Stack(
    fit: StackFit.passthrough,
    children: [
      widget.child,
      ValueListenableBuilder<bool>(
        valueListenable: _shown,
        builder: (_, shown, _) => !shown
            ? const SizedBox.shrink()
            : ValueListenableBuilder<bool>(
                valueListenable: _guard.captured,
                builder: (_, captured, _) => captured
                    ? const Positioned.fill(child: _Shield())
                    : const SizedBox.shrink(),
              ),
      ),
    ],
  );
}

/// What a recording of a chat shows.
class _Shield extends StatelessWidget {
  const _Shield();

  @override
  Widget build(BuildContext context) => ColoredBox(
    color: AppColors.black,
    child: Center(
      child: Padding(
        padding: EdgeInsets.all(32.ms),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(LucideIcons.shieldCheck, size: 40.ms, color: AppColors.white),
            SizedBox(height: 12.ms),
            const CText(
              'chat:secure.shield',
              size: 14,
              weight: FontWeight.w700,
              color: AppColors.white,
              align: TextAlign.center,
            ),
          ],
        ),
      ),
    ),
  );
}
