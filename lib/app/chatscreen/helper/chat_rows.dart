import 'package:flutter/foundation.dart';

import '../../api/chat/chat_models.dart';

/// What the ticks of an own message show.
enum ChatTick { none, queued, failed, sent, delivered, read }

/// One row of the message list, derived once per change so a bubble only
/// reads fields. Two rows are equal when they would draw the same, which
/// lets the list hand back the very same widget (no rebuild) for every
/// row a new message did not touch.
@immutable
class ChatRow {
  const ChatRow({
    required this.message,
    required this.mine,
    this.dayBreak,
    this.joinOlder = false,
    this.joinNewer = false,
  });

  final ChatMessage message;
  final bool mine;

  /// A date separator above this message (its first on that day).
  final DateTime? dayBreak;

  /// The message above (older) is from the same person, close in time:
  /// tighter spacing.
  final bool joinOlder;

  /// The message below (newer) is from the same person, close in time:
  /// no tail on this bubble.
  final bool joinNewer;

  String get key => message.key;

  @override
  bool operator ==(Object other) =>
      other is ChatRow &&
      identical(other.message, message) &&
      other.mine == mine &&
      other.dayBreak == dayBreak &&
      other.joinOlder == joinOlder &&
      other.joinNewer == joinNewer;

  @override
  int get hashCode =>
      Object.hash(message, mine, dayBreak, joinOlder, joinNewer);
}

/// Pure list rules: date separators, grouping, ticks, merge.
abstract final class ChatRows {
  /// Consecutive messages of one person closer than this are grouped.
  static const groupGap = Duration(minutes: 5);

  /// Rows for [newestFirst] (index 0 is drawn at the bottom).
  static List<ChatRow> build(List<ChatMessage> newestFirst, String? me) {
    final rows = <ChatRow>[];
    for (var i = 0; i < newestFirst.length; i++) {
      final m = newestFirst[i];
      final older = i + 1 < newestFirst.length ? newestFirst[i + 1] : null;
      final newer = i > 0 ? newestFirst[i - 1] : null;
      final day = localDay(m.createdAt);
      rows.add(
        ChatRow(
          message: m,
          mine: m.senderId == me,
          dayBreak: older == null || !sameDay(older.createdAt, m.createdAt)
              ? day
              : null,
          joinOlder: older != null && _joined(older, m),
          joinNewer: newer != null && _joined(m, newer),
        ),
      );
    }
    return rows;
  }

  static bool _joined(ChatMessage older, ChatMessage newer) =>
      older.senderId == newer.senderId &&
      sameDay(older.createdAt, newer.createdAt) &&
      newer.createdAt.difference(older.createdAt).abs() < groupGap;

  static bool sameDay(DateTime a, DateTime b) {
    final x = a.toLocal();
    final y = b.toLocal();
    return x.year == y.year && x.month == y.month && x.day == y.day;
  }

  /// The ticks of [m] when [mine]: the message's own times first, then the
  /// conversation's "delivered / read up to" marks.
  static ChatTick tickFor(
    ChatMessage m, {
    required bool mine,
    DateTime? peerDeliveredAt,
    DateTime? peerReadAt,
  }) {
    if (!mine) return ChatTick.none;
    switch (m.state) {
      case ChatSendState.queued || ChatSendState.sending:
        return ChatTick.queued;
      case ChatSendState.failed:
        return ChatTick.failed;
      case ChatSendState.sent:
        break;
    }
    bool upTo(DateTime? mark) => mark != null && !m.createdAt.isAfter(mark);
    if (m.readAt != null || upTo(peerReadAt)) return ChatTick.read;
    if (m.deliveredAt != null || upTo(peerDeliveredAt)) {
      return ChatTick.delivered;
    }
    return ChatTick.sent;
  }

  /// Merges a page into [current] (newest first): a message already there
  /// (same id, or same sender + clientId: the optimistic copy) is replaced,
  /// the rest added; the result is newest first. Local messages on their
  /// way out stay on top.
  static List<ChatMessage> merge(
    List<ChatMessage> current,
    Iterable<ChatMessage> incoming,
  ) {
    final byKey = <String, ChatMessage>{};
    final byId = <String, String>{};
    for (final m in current) {
      byKey[m.key] = m;
      if (!m.isLocal) byId[m.id] = m.key;
    }
    for (final m in incoming) {
      final existing = byId[m.id];
      if (existing != null && existing != m.key) byKey.remove(existing);
      byKey[m.key] = m;
      byId[m.id] = m.key;
    }
    final list = byKey.values.toList()..sort(_newestFirst);
    return list;
  }

  static int _newestFirst(ChatMessage a, ChatMessage b) {
    // Unsent ones are the newest, in the order they were written.
    if (a.isLocal != b.isLocal) return a.isLocal ? -1 : 1;
    final byTime = b.createdAt.compareTo(a.createdAt);
    return byTime != 0 ? byTime : b.id.compareTo(a.id);
  }

  /// What the list shows: my unsent messages (newest first) over the
  /// server's. One already saved (its clientId came back) shows once, as
  /// the server's.
  static List<ChatMessage> compose(
    List<ChatMessage> server,
    List<ChatMessage> local,
  ) {
    if (local.isEmpty) return server;
    final saved = {for (final m in server) m.key};
    final pending = [
      for (final m in local)
        if (!saved.contains(m.key)) m,
    ]..sort((a, b) => b.createdAt.compareTo(a.createdAt));
    return pending.isEmpty ? server : [...pending, ...server];
  }

  /// The newest message that came from the server (the `after` cursor).
  static ChatMessage? newestSent(List<ChatMessage> newestFirst) =>
      newestFirst.where((m) => !m.isLocal).firstOrNull;

  /// The oldest message from the server (the `before` cursor).
  static ChatMessage? oldestSent(List<ChatMessage> newestFirst) {
    for (var i = newestFirst.length - 1; i >= 0; i--) {
      if (!newestFirst[i].isLocal) return newestFirst[i];
    }
    return null;
  }

  /// Messages from the other person on screen that I have not read.
  static bool hasUnreadFrom(List<ChatMessage> messages, String? me) =>
      messages.any((m) => !m.isLocal && m.senderId != me && m.readAt == null);
}

/// Local calendar day of [t] (midnight), for separators.
DateTime localDay(DateTime t) {
  final l = t.toLocal();
  return DateTime(l.year, l.month, l.day);
}
