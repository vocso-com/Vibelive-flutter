import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';

import '../../../core/analytics/events/chat_events.dart';
import '../../../core/network/api_exception.dart';
import '../../../core/network/network_status.dart';
import '../../../core/session/session_store.dart';
import '../../../core/utils/log.dart';
import '../../api/chat/chat_api.dart';
import '../../api/chat/chat_models.dart';
import 'pending_queue.dart';

/// Something the outbox did that an open chat screen reacts to.
sealed class OutboxEvent {
  const OutboxEvent(this.entry);
  final OutboxEntry entry;
}

/// Saved: [result] is the server's copy (same clientId).
class OutboxSent extends OutboxEvent {
  const OutboxSent(super.entry, this.result);
  final ChatSendResult result;
}

/// Refused (402 low balance, or any other refusal).
class OutboxRefused extends OutboxEvent {
  const OutboxRefused(super.entry, this.failure, this.error);
  final OutboxFailure failure;
  final ApiException error;

  ChatRefusal get refusal => ChatRefusal.of(error);
}

/// Own messages on their way out, app-wide: they outlive the chat screen,
/// so a message written offline goes out once the network is back even if
/// the chat was closed. One in flight per person, in the order written.
///
/// Sends are tried when a message is written, when the network comes back,
/// when the app comes back, and after any successful chat read; nothing
/// polls on its own.
class ChatOutbox {
  ChatOutbox._();
  static final ChatOutbox instance = ChatOutbox._();

  static const _tag = 'ChatOutbox';

  /// Every entry, all chats.
  final entries = ValueNotifier<List<OutboxEntry>>(const []);
  final _events = StreamController<OutboxEvent>.broadcast();
  Stream<OutboxEvent> get events => _events.stream;

  bool _attached = false;

  /// A fresh id per written message (never per attempt).
  static String newClientId() => const Uuid().v4();

  /// Once: retry when the network is back; empty on sign-out.
  void attach() {
    if (_attached) return;
    _attached = true;
    NetworkStatus.instance.addListener(() {
      if (NetworkStatus.instance.value) pump();
    });
    SessionStore.instance.signedIn.addListener(() {
      if (!SessionStore.instance.value.isAuthenticated) {
        entries.value = const [];
      }
    });
  }

  List<OutboxEntry> forPeer(String peer) => [
    for (final e in entries.value)
      if (e.peerUserId == peer) e,
  ];

  void enqueue(OutboxEntry entry) {
    attach();
    entries.value = [...entries.value, entry];
    pump();
  }

  /// A tap on a failed bubble: the same clientId goes again.
  void retry(String clientId) {
    final e = _find(clientId);
    if (e == null || e.state != ChatSendState.failed) return;
    _put(PendingQueue.retry(e));
    pump();
  }

  /// Dropped (a refused text put back in the box, a deleted failure).
  void discard(String clientId) =>
      entries.value = PendingQueue.remove(entries.value, clientId);

  /// Sends what can go now. Never throws.
  void pump() {
    if (!NetworkStatus.instance.value) return;
    for (final peer in PendingQueue.peersWithQueued(entries.value)) {
      final next = PendingQueue.nextFor(entries.value, peer);
      if (next != null) unawaited(_send(next));
    }
  }

  Future<void> _send(OutboxEntry entry) async {
    _put(entry.copyWith(state: ChatSendState.sending));
    try {
      final result = await _deliver(entry);
      ChatEvents.messageDelivered(
        type: entry.type.wire,
        charged: result.charged,
        attempts: entry.attempts + 1,
      );
      // The screen merges the saved copy before the pending one goes, so
      // the bubble never blinks.
      _events.add(OutboxSent(entry, result));
      discard(entry.clientId);
      pump();
    } on ApiException catch (e) {
      final failure = PendingQueue.classify(e);
      Log.d(_tag, 'send ${entry.clientId} ${failure.name}: $e');
      final current = _find(entry.clientId);
      if (current == null) return;
      _put(PendingQueue.afterFailure(current, failure, e));
      if (failure != OutboxFailure.retryLater) {
        _events.add(OutboxRefused(current, failure, e));
      }
    } catch (e, st) {
      Log.e(_tag, e, st);
      final current = _find(entry.clientId);
      if (current != null) {
        final err = ApiException.from(e, st);
        _put(PendingQueue.afterFailure(current, OutboxFailure.failed, err));
      }
    }
  }

  static Future<ChatSendResult> _deliver(OutboxEntry e) => switch (e.type) {
    ChatMessageType.text => ChatApi.sendText(
      toUserId: e.peerUserId,
      text: e.text ?? '',
      clientId: e.clientId,
    ),
    ChatMessageType.privateImage => ChatApi.sendPrivatePhoto(
      toUserId: e.peerUserId,
      clientId: e.clientId,
      price: e.price ?? 0,
      path: e.localPath!,
    ),
    _ => ChatApi.sendMedia(
      toUserId: e.peerUserId,
      clientId: e.clientId,
      type: e.type,
      path: e.localPath!,
      durationSec: e.durationSec,
      width: e.width,
      height: e.height,
    ),
  };

  OutboxEntry? _find(String clientId) =>
      entries.value.where((e) => e.clientId == clientId).firstOrNull;

  void _put(OutboxEntry entry) =>
      entries.value = PendingQueue.replace(entries.value, entry);

  @visibleForTesting
  void debugReset() => entries.value = const [];
}
