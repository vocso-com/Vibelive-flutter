import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:go_router/go_router.dart';

import '../../../core/analytics/events/chat_events.dart';
import '../../../core/router/app_router.dart';
import '../../../core/session/session_store.dart';
import '../../api/chat/chat_queries.dart';
import '../../callscreen/history/helper/history_entry.dart';

/// `/chat/:userId` for a call-log row, or null when it can't be a chat:
/// chat off, no public-user id, or neither side a host (two users can't
/// chat; a host replies in the chat a user started).
String? historyChatRoute(HistoryEntry e, {required bool chatOn}) {
  final id = e.item.counterpart?.id;
  if (!chatOn || id == null) return null;
  final meHost = SessionStore.instance.value.isExpert;
  if (!e.isHostRole && !meHost) return null;
  return AppRoutes.chatWith('$id');
}

/// [historyChatRoute], rebuilt when chat turns on or off.
String? useHistoryChatRoute(BuildContext context, HistoryEntry e) =>
    historyChatRoute(e, chatOn: useValueListenable(ChatAvailability.instance));

/// History menu → Message.
void openHistoryChat(BuildContext context, HistoryEntry e) {
  final route = historyChatRoute(e, chatOn: ChatAvailability.instance.value);
  if (route == null) return;
  ChatEvents.entryTapped(source: 'history', peerId: e.counterpartId);
  unawaited(context.push(route));
}
