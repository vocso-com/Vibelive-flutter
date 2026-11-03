import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';

import '../../../core/i18n/i18n.dart';
import '../../../core/theme/vibe_colors.dart';
import '../../../core/utils/scale.dart';
import '../../api/chat/chat_queries.dart';
import '../../component/c_text.dart';
import '../helper/chat_sync.dart';

/// Builds the dock with or without the Chats tab: shown only once the
/// server said chat is on (the admin's kill switch hides every entry
/// point; an older server without chat never shows it). Needs no query
/// provider: the dock looks and moves exactly as before while chat is off.
/// Reads the config again when the app comes back to the front.
class ChatTabGate extends StatefulWidget {
  const ChatTabGate({super.key, required this.builder});

  final Widget Function(BuildContext context, bool chats) builder;

  /// The tab's name (screen readers).
  static const label = 'chat:nav.chats';

  @override
  State<ChatTabGate> createState() => _ChatTabGateState();
}

class _ChatTabGateState extends State<ChatTabGate> {
  late final AppLifecycleListener _lifecycle;

  @override
  void initState() {
    super.initState();
    unawaited(ChatAvailability.instance.recheck(fresh: false));
    _lifecycle = AppLifecycleListener(
      onResume: () => unawaited(ChatAvailability.instance.recheck()),
    );
  }

  @override
  void dispose() {
    _lifecycle.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => ValueListenableBuilder<bool>(
    valueListenable: ChatAvailability.instance,
    builder: (context, on, _) => widget.builder(context, on),
  );
}

/// The unread count on the Chats tab (`GET /chats/unread`), refreshed by
/// chat pushes and when the app comes back.
class ChatUnreadBadge extends HookWidget {
  const ChatUnreadBadge({super.key});

  @override
  Widget build(BuildContext context) {
    useEffect(() {
      ChatSync.instance.attach();
      return null;
    }, const []);
    final count = useChatUnread(context).data ?? 0;
    if (count <= 0) return const SizedBox.shrink();
    final c = context.colors;
    final text = count > 99 ? '99+' : '$count';
    return Semantics(
      label: context.t('chat:nav.unread', count: count),
      child: ExcludeSemantics(
        child: Container(
          key: const ValueKey('chat-unread-badge'),
          constraints: BoxConstraints(minWidth: 16.ms),
          height: 16.ms,
          padding: EdgeInsets.symmetric(horizontal: 4.ms),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: c.accent,
            borderRadius: BorderRadius.circular(999),
            border: Border.all(color: c.navBg, width: 1.5),
          ),
          child: CText.raw(
            text,
            size: 9,
            weight: FontWeight.w900,
            color: c.onAccent,
            maxLines: 1,
          ),
        ),
      ),
    );
  }
}
