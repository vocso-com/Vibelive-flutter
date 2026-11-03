import 'package:flutter/foundation.dart';

import '../../../core/network/api_exception.dart';
import '../../api/chat/chat_api.dart';
import '../../api/chat/chat_models.dart';

/// One own message on its way out. Its [clientId] is made once, when the
/// message is written, and every retry sends that same id: a send whose
/// answer was lost is never saved or charged twice (Tivroo gap 1).
@immutable
class OutboxEntry {
  const OutboxEntry({
    required this.clientId,
    required this.peerUserId,
    required this.senderId,
    required this.type,
    required this.createdAt,
    this.text,
    this.localPath,
    this.durationSec,
    this.width,
    this.height,
    this.price,
    this.state = ChatSendState.queued,
    this.errorKey,
    this.attempts = 0,
  });

  final String clientId;
  final String peerUserId;
  final String senderId;
  final ChatMessageType type;
  final DateTime createdAt;
  final String? text;

  /// Photo or recording on this phone.
  final String? localPath;
  final int? durationSec;
  final int? width;
  final int? height;

  /// A private photo's price (rupees).
  final double? price;
  final ChatSendState state;
  final String? errorKey;

  /// Sends tried so far.
  final int attempts;

  OutboxEntry copyWith({
    ChatSendState? state,
    String? errorKey,
    bool clearError = false,
    int? attempts,
  }) => OutboxEntry(
    clientId: clientId,
    peerUserId: peerUserId,
    senderId: senderId,
    type: type,
    createdAt: createdAt,
    text: text,
    localPath: localPath,
    durationSec: durationSec,
    width: width,
    height: height,
    price: price,
    state: state ?? this.state,
    errorKey: clearError ? null : (errorKey ?? this.errorKey),
    attempts: attempts ?? this.attempts,
  );

  /// The optimistic bubble.
  ChatMessage toMessage() => ChatMessage(
    id: 'local:$clientId',
    senderId: senderId,
    type: type,
    createdAt: createdAt,
    text: text,
    clientId: clientId,
    localPath: localPath,
    media: localPath == null
        ? null
        : ChatMedia(width: width, height: height, durationSec: durationSec),
    privatePhoto: type == ChatMessageType.privateImage
        ? ChatPrivatePhoto(price: price ?? 0)
        : null,
    state: state,
    errorKey: errorKey,
  );
}

/// What a failed send means for its entry.
enum OutboxFailure {
  /// No connection: stays queued, goes when the network is back.
  retryLater,

  /// 402 CHAT_LOW_BALANCE: nothing was saved; the text goes back in the
  /// box and the recharge sheet opens.
  lowBalance,

  /// Refused or failed: shown as failed, tap to retry (same clientId).
  failed,
}

/// The queue's pure rules (`ChatOutbox` does the sending).
abstract final class PendingQueue {
  /// The next entry to send to [peer]: the oldest queued one, and none
  /// while one is already in flight (one at a time keeps the order).
  /// Failed ones are skipped: they wait for a tap.
  static OutboxEntry? nextFor(List<OutboxEntry> entries, String peer) {
    OutboxEntry? next;
    for (final e in entries) {
      if (e.peerUserId != peer) continue;
      if (e.state == ChatSendState.sending) return null;
      if (e.state == ChatSendState.queued &&
          (next == null || e.createdAt.isBefore(next.createdAt))) {
        next = e;
      }
    }
    return next;
  }

  /// Peers with something queued.
  static Set<String> peersWithQueued(List<OutboxEntry> entries) => {
    for (final e in entries)
      if (e.state == ChatSendState.queued) e.peerUserId,
  };

  static OutboxFailure classify(ApiException e) {
    if (e.type == ApiErrorType.network || e.type == ApiErrorType.timeout) {
      return OutboxFailure.retryLater;
    }
    if (ChatRefusal.of(e).isLowBalance) return OutboxFailure.lowBalance;
    return OutboxFailure.failed;
  }

  /// [entry] after a failure of kind [failure].
  static OutboxEntry afterFailure(
    OutboxEntry entry,
    OutboxFailure failure,
    ApiException e,
  ) => switch (failure) {
    OutboxFailure.retryLater => entry.copyWith(
      state: ChatSendState.queued,
      attempts: entry.attempts + 1,
      clearError: true,
    ),
    OutboxFailure.lowBalance || OutboxFailure.failed => entry.copyWith(
      state: ChatSendState.failed,
      attempts: entry.attempts + 1,
      errorKey: e.messageKey ?? ApiException.defaultKeyFor(e.type),
    ),
  };

  /// A tap on a failed bubble: queued again with the SAME clientId.
  static OutboxEntry retry(OutboxEntry entry) =>
      entry.copyWith(state: ChatSendState.queued, clearError: true);

  /// [entries] with [entry] put in place of the one with its clientId.
  static List<OutboxEntry> replace(
    List<OutboxEntry> entries,
    OutboxEntry entry,
  ) => [for (final e in entries) e.clientId == entry.clientId ? entry : e];

  static List<OutboxEntry> remove(List<OutboxEntry> entries, String clientId) =>
      [
        for (final e in entries)
          if (e.clientId != clientId) e,
      ];
}
