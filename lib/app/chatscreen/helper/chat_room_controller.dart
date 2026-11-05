import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../../core/network/api_client.dart';
import '../../../core/network/api_exception.dart';
import '../../../core/session/session_store.dart';
import '../../../core/utils/log.dart';
import '../../api/chat/chat_api.dart';
import '../../api/chat/chat_models.dart';
import '../../api/chat/chat_queries.dart';
import '../../api/paymentscreen/payment_queries.dart';
import 'chat_outbox.dart';
import 'chat_rows.dart';
import 'chat_sync.dart';
import 'pending_queue.dart';

/// "Delivered / read up to" of my messages in one conversation.
@immutable
class ChatReceiptMarks {
  const ChatReceiptMarks({this.delivered, this.read});

  final DateTime? delivered;
  final DateTime? read;

  /// The later of each mark (an answer may arrive out of order).
  ChatReceiptMarks merge(DateTime? delivered, DateTime? read) =>
      ChatReceiptMarks(
        delivered: _later(this.delivered, delivered),
        read: _later(this.read, read),
      );

  static DateTime? _later(DateTime? a, DateTime? b) =>
      a == null ? b : (b == null || a.isAfter(b) ? a : b);

  @override
  bool operator ==(Object other) =>
      other is ChatReceiptMarks &&
      other.delivered == delivered &&
      other.read == read;

  @override
  int get hashCode => Object.hash(delivered, read);
}

/// The last state of one open conversation, kept in memory so reopening it
/// paints the messages at once instead of a blank skeleton while the newest
/// page loads again (docs/chat_api.md). Per app session only.
@immutable
class _RoomSnapshot {
  const _RoomSnapshot(this.open, this.server, this.receipts, this.hasMore);
  final ChatOpen? open;
  final List<ChatMessage> server;
  final ChatReceiptMarks receipts;
  final bool hasMore;
}

/// One open conversation, keyed by the other person's public-user id.
///
/// State is split into small notifiers so each part of the screen rebuilds
/// alone: the list listens to [messages], the ticks to [receipts], the bar
/// to [balance]. Sends go through the app-wide [ChatOutbox] (they outlive
/// this screen); this merges what it saved.
///
/// Reads happen when the chat opens, on a push hint or an app resume
/// ([ChatSync]), and once per `pollSeconds` while the chat is visible and
/// the app in front, only if nothing else read meanwhile.
///
/// A chat reopened in the same session paints its last messages at once from
/// [_cache]; the newest page and the prices still refresh in the background.
class ChatRoomController {
  ChatRoomController({required this.peer, ChatOutbox? outbox})
    : _outbox = outbox ?? ChatOutbox.instance {
    _outbox.attach();
    _outbox.entries.addListener(_recompose);
    _outboxSub = _outbox.events.listen(_onOutbox);
    _hintSub = ChatSync.instance.hints.listen(_onHint);
    _seed();
  }

  /// Last-seen state per "me:peer", newest last. Memory only (one session),
  /// bounded; keyed by the signed-in user so the next account never sees it.
  static final Map<String, _RoomSnapshot> _cache = {};
  static const _cacheMax = 15;

  /// Drops every cached conversation (sign-out).
  static void clearCache() => _cache.clear();

  static const _tag = 'ChatRoom';

  /// The other person's public-user id.
  final String peer;
  final ChatOutbox _outbox;

  final open = ValueNotifier<ChatOpen?>(null);

  /// The first read failed with nothing to show.
  final error = ValueNotifier<ApiException?>(null);

  /// Newest first: my unsent messages over the server's.
  final messages = ValueNotifier<List<ChatMessage>>(const []);
  final receipts = ValueNotifier<ChatReceiptMarks>(const ChatReceiptMarks());
  final hasMore = ValueNotifier<bool>(false);
  final loadingOlder = ValueNotifier<bool>(false);

  /// Net cash (paying side), after every paid send.
  final balance = ValueNotifier<double?>(null);

  /// Net earnings (host side).
  final earnings = ValueNotifier<double?>(null);

  final _refusals = StreamController<OutboxRefused>.broadcast();

  /// My message was refused (402 low balance, or another refusal): the
  /// screen puts a text back in the box and opens the recharge sheet.
  Stream<OutboxRefused> get refusals => _refusals.stream;

  late final StreamSubscription<OutboxEvent> _outboxSub;
  late final StreamSubscription<ChatHint> _hintSub;

  List<ChatMessage> _server = const [];
  bool _visible = false;
  bool _disposed = false;
  bool _spent = false;
  bool _marking = false;

  /// Who / prices have been read fresh from the server this session (not just
  /// seeded from [_cache]); until then the first full read refreshes them.
  bool _openFresh = false;
  Timer? _poll;
  Future<void>? _sync;
  bool _syncAgain = false;
  bool _syncFull = false;

  String? get me => SessionStore.instance.value.userId?.toString();
  String? get conversationId => open.value?.conversationId;

  String get _cacheKey => '${me ?? '?'}:$peer';

  /// Paints the last state of this chat at once (if it is cached for the
  /// signed-in user), so a reopen never flashes a blank skeleton.
  void _seed() {
    final snap = _cache[_cacheKey];
    if (snap == null) return;
    _server = snap.server;
    if (snap.open != null) _setOpen(snap.open!);
    receipts.value = snap.receipts;
    hasMore.value = snap.hasMore;
    _recompose();
  }

  /// Remembers this chat's state for a reopen, newest-last, bounded.
  void _stash() {
    if (_disposed) return;
    _cache.remove(_cacheKey); // re-insert to mark most-recent (LRU)
    _cache[_cacheKey] = _RoomSnapshot(
      open.value,
      _server,
      receipts.value,
      hasMore.value,
    );
    if (_cache.length > _cacheMax) _cache.remove(_cache.keys.first);
  }

  // ── Reading ────────────────────────────────────────────────────────────

  /// First read: who, prices, then the newest page.
  Future<void> load() => _sync ??= _run(full: true).whenComplete(_drain);

  /// Reads what is new (`after=` the newest message). [full]: the newest
  /// page again, replacing what changed (a photo was unlocked). One at a
  /// time: a request while one runs is run once after it.
  Future<void> sync({bool full = false}) {
    if (_disposed) return Future.value();
    if (_sync != null) {
      _syncAgain = true;
      _syncFull = _syncFull || full;
      return _sync!;
    }
    return _sync = _run(full: full).whenComplete(_drain);
  }

  void _drain() {
    _sync = null;
    if (_disposed || !_syncAgain) return;
    final full = _syncFull;
    _syncAgain = false;
    _syncFull = false;
    unawaited(sync(full: full));
  }

  Future<void> _run({required bool full}) async {
    _poll?.cancel();
    try {
      var info = open.value;
      // No conversation yet (it may exist now — they wrote, or my first
      // message went), or a full read whose who/prices are still only the
      // ones seeded from the cache: read them fresh.
      if (info == null || info.conversationId == null || (full && !_openFresh)) {
        info = await ChatApi.openWith(peer);
        if (_disposed) return;
        _setOpen(info);
        _openFresh = true;
      }
      final id = info.conversationId;
      if (id != null) {
        final newest = ChatRows.newestSent(_server);
        if (full || newest == null) {
          final page = await ChatApi.fetchMessages(id);
          if (_disposed) return;
          _apply(page, first: true);
        } else if (!await _catchUp(id, newest.id)) {
          // Too far behind to page forward: start again from the newest.
          final page = await ChatApi.fetchMessages(id);
          if (_disposed) return;
          _server = const [];
          _apply(page, first: true);
        }
      }
      error.value = null;
      _recompose();
      _afterRead();
    } on ApiException catch (e) {
      if (_disposed) return;
      Log.d(_tag, 'read failed: $e');
      if (open.value == null) error.value = e;
      _schedulePoll();
    }
  }

  /// Reads who / prices / switches again (a refusal said they changed: the
  /// host turned chats off, a block, chat switched off).
  Future<void> refreshOpen() async {
    try {
      final info = await ChatApi.openWith(peer);
      if (!_disposed) _setOpen(info);
    } on ApiException catch (e) {
      Log.d(_tag, 'reopen failed: $e');
    }
  }

  /// Pages forward from [after] (`hasMore` = still newer ones) until up to
  /// date; false when that would take more than [_catchUpPages] pages.
  Future<bool> _catchUp(String id, String after) async {
    var cursor = after;
    for (var i = 0; i < _catchUpPages; i++) {
      final page = await ChatApi.fetchMessages(id, after: cursor);
      if (_disposed) return true;
      _apply(page, first: false);
      final top = page.items.isEmpty ? null : page.items.first;
      if (!page.hasMore || top == null) return true;
      cursor = top.id;
    }
    return false;
  }

  static const _catchUpPages = 5;

  void _setOpen(ChatOpen info) {
    open.value = info;
    if (info.balance != null) balance.value = info.balance;
    if (info.earnings != null) earnings.value = info.earnings;
    if (_visible) _announce();
  }

  void _apply(ChatMessagesPage page, {required bool first}) {
    _server = ChatRows.merge(_server, page.items);
    if (first) hasMore.value = page.hasMore;
    receipts.value = receipts.value.merge(
      page.peerDeliveredAt,
      page.peerReadAt,
    );
  }

  /// Older messages above the oldest shown.
  Future<void> loadOlder() async {
    final id = conversationId;
    final oldest = ChatRows.oldestSent(_server);
    if (id == null || oldest == null || !hasMore.value || loadingOlder.value) {
      return;
    }
    loadingOlder.value = true;
    try {
      final page = await ChatApi.fetchMessages(id, before: oldest.id);
      if (_disposed) return;
      _server = ChatRows.merge(_server, page.items);
      hasMore.value = page.hasMore;
      _recompose();
    } on ApiException catch (e) {
      Log.d(_tag, 'older page failed: $e');
    } finally {
      if (!_disposed) loadingOlder.value = false;
    }
  }

  void _afterRead() {
    // A read worked: the network is fine, so queued sends can go too.
    _outbox.pump();
    _markRead();
    _schedulePoll();
  }

  void _schedulePoll() {
    _poll?.cancel();
    _poll = null;
    final seconds = currentChatConfig().pollSeconds;
    if (_disposed || !_visible || !ChatSync.instance.foreground) return;
    if (seconds <= 0) return;
    _poll = Timer(Duration(seconds: seconds), () => unawaited(sync()));
  }

  /// Marks the other person's messages read while the chat is on screen.
  void _markRead() {
    final id = conversationId;
    if (!_visible || _marking || id == null) return;
    if (!ChatRows.hasUnreadFrom(_server, me)) return;
    _marking = true;
    final at = DateTime.now();
    // Shown read at once; the server is told below.
    _server = [
      for (final m in _server)
        m.senderId != me && m.readAt == null ? m.copyWith(readAt: at) : m,
    ];
    _recompose();
    unawaited(
      ChatApi.markRead(id)
          .then((_) => invalidateChatLists())
          .catchError((Object e) => Log.d(_tag, 'read mark failed: $e'))
          .whenComplete(() => _marking = false),
    );
  }

  void _recompose() {
    if (_disposed) return;
    _stash();
    final local = [for (final e in _outbox.forPeer(peer)) e.toMessage()];
    final next = ChatRows.compose(_server, local);
    if (!listEquals(next, messages.value)) messages.value = next;
  }

  // ── Visibility ─────────────────────────────────────────────────────────

  /// The chat is on screen (top route, app in front) or not.
  void setVisible(bool visible) {
    if (_disposed || visible == _visible) return;
    _visible = visible;
    if (visible) {
      _announce();
      _markRead();
      _schedulePoll();
    } else {
      ChatSync.instance.hidden(this);
      _poll?.cancel();
      _poll = null;
    }
  }

  void _announce() => ChatSync.instance.showing(
    this,
    peer: peer,
    conversationId: conversationId,
  );

  void _onHint(ChatHint hint) {
    if (!hint.concerns(peer: peer, conversationId: conversationId)) return;
    unawaited(sync(full: hint.event == 'unlocked'));
  }

  // ── Sending ────────────────────────────────────────────────────────────

  OutboxEntry _entry(
    ChatMessageType type, {
    String? text,
    String? path,
    int? seconds,
    int? width,
    int? height,
    double? price,
  }) => OutboxEntry(
    clientId: ChatOutbox.newClientId(),
    peerUserId: peer,
    senderId: me ?? '',
    type: type,
    createdAt: DateTime.now(),
    text: text,
    localPath: path,
    durationSec: seconds,
    width: width,
    height: height,
    price: price,
  );

  void sendText(String text) {
    final t = text.trim();
    if (t.isEmpty) return;
    _outbox.enqueue(_entry(ChatMessageType.text, text: t));
  }

  void sendPhoto(String path, {int? width, int? height}) => _outbox.enqueue(
    _entry(ChatMessageType.image, path: path, width: width, height: height),
  );

  void sendVoice(String path, int seconds) => _outbox.enqueue(
    _entry(ChatMessageType.audio, path: path, seconds: seconds),
  );

  void sendPrivatePhoto(String path, double price) => _outbox.enqueue(
    _entry(ChatMessageType.privateImage, path: path, price: price),
  );

  /// A failed bubble tapped: the same clientId goes again.
  void retry(ChatMessage m) {
    final id = m.clientId;
    if (id != null) _outbox.retry(id);
  }

  /// A failed bubble removed.
  void discard(ChatMessage m) {
    final id = m.clientId;
    if (id != null) _outbox.discard(id);
  }

  void _onOutbox(OutboxEvent event) {
    if (_disposed || event.entry.peerUserId != peer) return;
    switch (event) {
      case OutboxSent(:final result):
        final saved = result.message;
        final info = open.value;
        final convId = saved.conversationId;
        if (info != null && info.conversationId == null && convId != null) {
          _setOpen(info.withConversation(convId));
        }
        _server = ChatRows.merge(_server, [saved]);
        if (result.balance != null) balance.value = result.balance;
        if (result.earnings != null) earnings.value = result.earnings;
        if (result.charged > 0) _spent = true;
        _recompose();
        invalidateChatLists();
      case OutboxRefused():
        _refusals.add(event);
    }
  }

  // ── Private photos ─────────────────────────────────────────────────────

  /// Pays for a private photo; throws [ApiException] (402: recharge).
  Future<ChatMessage> unlock(ChatMessage m) async {
    final result = await ApiClient.guard(() => ChatApi.unlock(m.id));
    if (_disposed) return result.message;
    _server = ChatRows.merge(_server, [result.message]);
    if (result.balance != null) balance.value = result.balance;
    _spent = true;
    _recompose();
    return result.message;
  }

  void dispose() {
    _disposed = true;
    _poll?.cancel();
    ChatSync.instance.hidden(this);
    _outbox.entries.removeListener(_recompose);
    unawaited(_outboxSub.cancel());
    unawaited(_hintSub.cancel());
    unawaited(_refusals.close());
    // The wallet shown elsewhere is net of this chat's spending: read it
    // again once, not after every message.
    if (_spent) invalidateWalletQueries();
    open.dispose();
    error.dispose();
    messages.dispose();
    receipts.dispose();
    hasMore.dispose();
    loadingOlder.dispose();
    balance.dispose();
    earnings.dispose();
  }
}
