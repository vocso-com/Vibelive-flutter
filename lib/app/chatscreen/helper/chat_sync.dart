import 'dart:async';

import 'package:flutter/widgets.dart';

import '../../api/chat/chat_queries.dart';
import 'chat_outbox.dart';
import 'chat_receipts.dart';

/// Why a chat should read again. Pushes are hints, never data: the screen
/// always re-reads from the API.
@immutable
class ChatHint {
  const ChatHint({
    this.conversationId,
    this.peerUserId,
    this.event = 'message',
    this.messageId,
  });

  /// The app came back to the front: every open chat reads again.
  static const resume = ChatHint(event: 'resume');

  final String? conversationId;

  /// The other person (a `CHAT_MESSAGE`'s sender).
  final String? peerUserId;

  /// `message`, `read`, `delivered`, `unlocked`, `resume`.
  final String event;
  final String? messageId;

  /// For the chat with [peer] (conversation [conversationId], if known).
  bool concerns({required String peer, String? conversationId}) {
    if (event == 'resume') return true;
    final id = this.conversationId;
    if (id != null && conversationId != null) return id == conversationId;
    return peerUserId != null && peerUserId == peer;
  }
}

/// The UI isolate's chat hub: push hints and app resumes go out to the
/// open chat screens and refresh the badge and the list; the screens say
/// which chat is on screen, so its pushes are not drawn as notifications.
class ChatSync {
  ChatSync._();
  static final ChatSync instance = ChatSync._();

  final _hints = StreamController<ChatHint>.broadcast();
  Stream<ChatHint> get hints => _hints.stream;

  final _onScreen = <Object, ({String peer, String? conversationId})>{};
  AppLifecycleListener? _lifecycle;
  var _foreground = true;

  /// The app is in front (resumed).
  bool get foreground => _foreground;

  /// Once per app run (idempotent): resume handling.
  void attach() {
    if (_lifecycle != null) return;
    ChatOutbox.instance.attach();
    _lifecycle = AppLifecycleListener(
      onStateChange: (state) {
        final front = state == AppLifecycleState.resumed;
        if (front && !_foreground) _resumed();
        _foreground = front;
      },
    );
  }

  /// A `CHAT_MESSAGE` / `CHAT_SYNC` push reached the UI isolate.
  void onPush(ChatHint hint) {
    invalidateChatLists();
    _hints.add(hint);
    ChatOutbox.instance.pump();
  }

  void _resumed() {
    invalidateChatLists();
    _hints.add(ChatHint.resume);
    ChatOutbox.instance.pump();
    unawaited(ChatReceipts.flush());
  }

  /// A chat screen with [peer] is visible ([token]: the screen).
  void showing(Object token, {required String peer, String? conversationId}) =>
      _onScreen[token] = (peer: peer, conversationId: conversationId);

  void hidden(Object token) => _onScreen.remove(token);

  /// The chat with [peerUserId] / [conversationId] is on screen now, with
  /// the app in front: its pushes are not drawn.
  bool isOnScreen({String? conversationId, String? peerUserId}) {
    if (!_foreground) return false;
    for (final s in _onScreen.values) {
      if (conversationId != null && s.conversationId == conversationId) {
        return true;
      }
      if (peerUserId != null && s.peer == peerUserId) return true;
    }
    return false;
  }

  @visibleForTesting
  void debugSetForeground(bool value) => _foreground = value;
}
