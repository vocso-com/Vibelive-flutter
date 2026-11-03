import 'package:flutter/scheduler.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_hooks/flutter_hooks.dart';

import '../../api/chat/chat_queries.dart';
import '../helper/chat_screen_guard.dart';

/// Routes a chat screen opens on top of itself (they go with it).
const chatOwnRoutes = {'private_photo_viewer', 'chat_photo_viewer'};

/// Chat was switched off for this user while this chat is open (the
/// admin's switch or audience, then CONFIG_UPDATED or a resume): the chat
/// closes, with its sheets and viewers. Only on a change from on to off,
/// so a link opened before the first config read is never bounced. If
/// another feature's page is on top (the wallet mid top-up), the chat
/// closes once it is back on top instead.
void useCloseWhenChatOff(BuildContext context) {
  final route = ModalRoute.of(context);
  final wasOn = useRef(ChatAvailability.instance.value);
  final pending = useRef(false);
  useEffect(() {
    final guard = ChatScreenGuard.instance;
    var scheduled = false;

    void close() {
      scheduled = false;
      final nav = route?.navigator;
      if (route == null || nav == null || !route.isActive) return;
      final top = guard.observer.top.value;
      final ownTop =
          top == null ||
          top == route ||
          chatOwnRoutes.contains(top.settings.name);
      if (!ownTop) return; // closes when it is back on top
      pending.value = false;
      nav.popUntil((r) => r == route);
      if (route.isCurrent) nav.pop();
    }

    void check() {
      final on = ChatAvailability.instance.value;
      if (wasOn.value && !on) pending.value = true;
      wasOn.value = on;
      if (!pending.value || scheduled) return;
      // Never navigate in the middle of a build or a route change.
      scheduled = true;
      SchedulerBinding.instance.addPostFrameCallback((_) => close());
      SchedulerBinding.instance.ensureVisualUpdate();
    }

    ChatAvailability.instance.addListener(check);
    guard.observer.top.addListener(check);
    return () {
      ChatAvailability.instance.removeListener(check);
      guard.observer.top.removeListener(check);
    };
  }, [route]);
}
