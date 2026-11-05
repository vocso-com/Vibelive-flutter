import 'package:flutter/foundation.dart';

import '../../../core/network/strapi.dart';
import 'chat_message_models.dart';

export 'chat_message_models.dart';

/// Typed views of the chat API (backend docs/chat_api.md §4). Every parser is
/// lenient: numbers may come as strings, nested objects may be missing, and
/// an unknown shape gives safe defaults instead of throwing. Money is rupees
/// with two decimals, as the API sends it; maths happens in paise
/// (`chatscreen/helper/chat_pricing.dart`).

JsonMap _map(Object? v) =>
    v is Map ? Map<String, dynamic>.from(v) : const <String, dynamic>{};

double _money(Object? v) => J.number(v) ?? 0;

int _int(Object? v, int fallback) => J.integer(v) ?? fallback;

bool _flag(Object? v, bool fallback) => v == null ? fallback : J.boolean(v);

DateTime? _date(Object? v) => J.date(v is String ? v : J.str(v));

/// `voice` of [ChatConfig]: the price ladder of a voice note.
@immutable
class ChatVoicePricing {
  const ChatVoicePricing({
    this.shortSec = 10,
    this.shortPrice = 2,
    this.longSec = 30,
    this.longPrice = 4,
    this.stepSec = 20,
    this.stepPrice = 1,
    this.maxSeconds = 120,
  });

  factory ChatVoicePricing.fromJson(Object? json) {
    final j = _map(json);
    return ChatVoicePricing(
      shortSec: _int(j['shortSec'], 10),
      shortPrice: _money(j['shortPrice']),
      longSec: _int(j['longSec'], 30),
      longPrice: _money(j['longPrice']),
      stepSec: _int(j['stepSec'], 20),
      stepPrice: _money(j['stepPrice']),
      maxSeconds: _int(j['maxSeconds'], 120),
    );
  }

  final int shortSec;
  final double shortPrice;
  final int longSec;
  final double longPrice;
  final int stepSec;
  final double stepPrice;
  final int maxSeconds;
}

/// `privatePhotos` of [ChatConfig].
@immutable
class ChatPrivatePhotoRules {
  const ChatPrivatePhotoRules({
    this.enabled = false,
    this.minPrice = 10,
    this.maxPrice = 2000,
    this.hostSharePercent = 70,
    this.accessMinutes = 10,
    this.viewSeconds = 300,
  });

  factory ChatPrivatePhotoRules.fromJson(Object? json) {
    final j = _map(json);
    return ChatPrivatePhotoRules(
      enabled: _flag(j['enabled'], false),
      minPrice: J.number(j['minPrice']) ?? 10,
      maxPrice: J.number(j['maxPrice']) ?? 2000,
      hostSharePercent: _int(j['hostSharePercent'], 70),
      accessMinutes: _int(j['accessMinutes'], 10),
      viewSeconds: _int(j['viewSeconds'], 300),
    );
  }

  final bool enabled;
  final double minPrice;
  final double maxPrice;
  final int hostSharePercent;
  final int accessMinutes;
  final int viewSeconds;
}

/// `GET /chats/config`: the admin's chat settings, as the app reads them.
@immutable
class ChatConfig {
  const ChatConfig({
    this.raw = const {},
    this.enabled = false,
    this.textPrice = 0,
    this.imagePrice = 0,
    this.voice = const ChatVoicePricing(),
    this.minBalanceText = 0,
    this.minBalanceImage = 0,
    this.minBalanceVoice = 0,
    this.maxMessageLength = 1000,
    this.lowBalanceMessages = 10,
    this.pollSeconds = 20,
    this.screenshotProtection = true,
    this.mediaMaxMb = 10,
    this.privatePhotos = const ChatPrivatePhotoRules(),
    this.hostMediaPercent,
    this.hostSharePercent = 50,
    this.audience,
  });

  /// Chat unknown or switched off: every entry point hidden.
  static const off = ChatConfig();

  factory ChatConfig.fromJson(Object? json) {
    final j = Strapi.map(json) ?? const <String, dynamic>{};
    final min = _map(j['minBalance']);
    return ChatConfig(
      raw: j,
      // Only an explicit "on": an answer without the flag (an older
      // backend, an error page) keeps chat hidden.
      enabled: _flag(j['enabled'], false),
      textPrice: _money(j['textPrice']),
      imagePrice: _money(j['imagePrice']),
      voice: ChatVoicePricing.fromJson(j['voice']),
      minBalanceText: _money(min['text']),
      minBalanceImage: _money(min['image']),
      minBalanceVoice: _money(min['voice']),
      maxMessageLength: _int(j['maxMessageLength'], 1000).clamp(50, 4000),
      lowBalanceMessages: _int(j['lowBalanceMessages'], 10),
      pollSeconds: _int(j['pollSeconds'], 20),
      screenshotProtection: _flag(j['screenshotProtection'], true),
      mediaMaxMb: _int(j['mediaMaxMb'], 10),
      privatePhotos: ChatPrivatePhotoRules.fromJson(j['privatePhotos']),
      // Not in contract v1's table; see its Changes section.
      hostMediaPercent: J.integer(j['hostMediaPercent']),
      hostSharePercent: _int(j['hostSharePercent'], 50),
      audience: J.str(j['audience']),
    );
  }

  /// Persisted form ([ChatConfig.fromJson] maps it back; [off] stays off).
  JsonMap toJson() => {...raw, 'enabled': enabled};

  final JsonMap raw;
  final bool enabled;
  final double textPrice;
  final double imagePrice;
  final ChatVoicePricing voice;
  final double minBalanceText;
  final double minBalanceImage;
  final double minBalanceVoice;
  final int maxMessageLength;
  final int lowBalanceMessages;

  /// An open chat re-reads after this long without a push; 0 = never.
  final int pollSeconds;
  final bool screenshotProtection;
  final int mediaMaxMb;
  final ChatPrivatePhotoRules privatePhotos;

  /// What a host pays, from earnings, for an own photo or voice note, as a
  /// percent of the list price. Null when the server does not say.
  final int? hostMediaPercent;

  /// The host's share of a message the user paid for, once the host replies
  /// (a percent). Used to show the host what they earn (the caller is shown
  /// what they pay).
  final int hostSharePercent;

  /// `company` (company accounts only) or `all`; [enabled] already says
  /// whether this user is in it.
  final String? audience;
}

/// `Peer` (§4): the other person of a conversation.
@immutable
class ChatPeer {
  const ChatPeer({
    required this.userId,
    this.name = '',
    this.avatar,
    this.verified = false,
    this.isHost = false,
    this.expertDocumentId,
    this.online = false,
    this.busy = false,
    this.deleted = false,
  });

  factory ChatPeer.fromJson(Object? json) {
    final j = _map(json);
    final avatar = j['avatar'];
    return ChatPeer(
      userId: J.str(j['userId'] ?? j['id']) ?? '',
      name: (J.str(j['name']) ?? '').trim(),
      avatar: avatar is Map
          ? Strapi.mediaThumbFromAsset(avatar)
          : Strapi.mediaUrl(J.str(avatar)),
      verified: J.boolean(j['verified']),
      isHost: J.boolean(j['isHost']),
      expertDocumentId: J.str(j['expertDocumentId']),
      online: J.boolean(j['online']),
      busy: J.boolean(j['busy']),
      deleted: J.boolean(j['deleted']),
    );
  }

  /// Public-user numeric id, as a string (the `/chat/:userId` key).
  final String userId;
  final String name;
  final String? avatar;
  final bool verified;
  final bool isHost;
  final String? expertDocumentId;

  /// A host's own availability; false for anyone else.
  final bool online;

  /// The host is on a call.
  final bool busy;
  final bool deleted;
}

/// `lastMessage` of a [ChatConversation].
@immutable
class ChatLastMessage {
  const ChatLastMessage({
    required this.type,
    this.text,
    this.senderId,
    this.at,
  });

  static ChatLastMessage? fromJson(Object? json) {
    if (json is! Map) return null;
    final j = _map(json);
    return ChatLastMessage(
      type: ChatMessageType.parse(j['type']),
      text: J.str(j['text']),
      senderId: J.str(j['senderId']),
      at: _date(j['at']),
    );
  }

  final ChatMessageType type;
  final String? text;
  final String? senderId;
  final DateTime? at;
}

/// `Conversation` (§4): one row of the chat list.
@immutable
class ChatConversation {
  const ChatConversation({
    required this.id,
    required this.mySide,
    required this.peer,
    this.lastMessage,
    this.unread = 0,
    this.updatedAt,
  });

  factory ChatConversation.fromJson(Object? json) {
    final j = _map(json);
    return ChatConversation(
      id: J.str(j['id'] ?? j['documentId']) ?? '',
      mySide: ChatSide.parse(j['mySide']),
      peer: ChatPeer.fromJson(j['peer']),
      lastMessage: ChatLastMessage.fromJson(j['lastMessage']),
      unread: J.integer(j['unread']) ?? 0,
      updatedAt:
          _date(j['updatedAt']) ??
          ChatLastMessage.fromJson(j['lastMessage'])?.at,
    );
  }

  JsonMap toJson() => {
    'id': id,
    'mySide': mySide.name,
    'peer': {
      'userId': peer.userId,
      'name': peer.name,
      'avatar': peer.avatar,
      'verified': peer.verified,
      'isHost': peer.isHost,
      'expertDocumentId': peer.expertDocumentId,
      'online': peer.online,
      'busy': peer.busy,
      'deleted': peer.deleted,
    },
    if (lastMessage case final m?)
      'lastMessage': {
        'type': m.type.wire,
        'text': m.text,
        'senderId': m.senderId,
        'at': m.at?.toUtc().toIso8601String(),
      },
    'unread': unread,
    'updatedAt': updatedAt?.toUtc().toIso8601String(),
  };

  final String id;
  final ChatSide mySide;
  final ChatPeer peer;
  final ChatLastMessage? lastMessage;
  final int unread;
  final DateTime? updatedAt;

  ChatConversation read() => ChatConversation(
    id: id,
    mySide: mySide,
    peer: peer,
    lastMessage: lastMessage,
    updatedAt: updatedAt,
  );
}

/// Who pays in a conversation: [payer] pays per message, [host] earns.
enum ChatSide {
  payer,
  host;

  static ChatSide parse(Object? v) =>
      J.str(v) == 'host' ? ChatSide.host : ChatSide.payer;
}

/// `GET /chats/conversations`.
@immutable
class ChatConversationsPage {
  const ChatConversationsPage({
    this.items = const [],
    this.unreadTotal = 0,
    this.next,
  });

  factory ChatConversationsPage.fromJson(Object? json) {
    final j = _map(json);
    final items = j['items'] ?? j['data'];
    return ChatConversationsPage(
      items: [
        if (items is List)
          for (final c in items) ChatConversation.fromJson(c),
      ].where((c) => c.id.isNotEmpty).toList(),
      unreadTotal: J.integer(j['unreadTotal']) ?? 0,
      next: J.str(j['next']),
    );
  }

  JsonMap toJson() => {
    'items': [for (final c in items) c.toJson()],
    'unreadTotal': unreadTotal,
    'next': next,
  };

  final List<ChatConversation> items;
  final int unreadTotal;

  /// Cursor of the next page; null on the last one.
  final String? next;
}

/// `GET /chats/with/:userId`: everything the chat screen needs before a
/// message.
@immutable
class ChatOpen {
  const ChatOpen({
    required this.mySide,
    required this.peer,
    this.conversationId,
    this.chatEnabled = true,
    this.pricePerMessage = 0,
    this.imagePrice = 0,
    this.balance,
    this.earnings,
    this.reason,
  });

  factory ChatOpen.fromJson(Object? json) {
    final j = Strapi.map(json) ?? const <String, dynamic>{};
    return ChatOpen(
      conversationId: J.str(j['conversationId']),
      mySide: ChatSide.parse(j['mySide']),
      peer: ChatPeer.fromJson(j['peer']),
      chatEnabled: _flag(j['chatEnabled'], true),
      pricePerMessage: _money(j['pricePerMessage']),
      imagePrice: _money(j['imagePrice']),
      balance: J.number(j['balance']),
      earnings: J.number(j['earnings']),
      reason: J.str(j['reason']),
    );
  }

  final String? conversationId;
  final ChatSide mySide;
  final ChatPeer peer;

  /// Can I send? False when the host has "Accept chats" off (payer side).
  final bool chatEnabled;
  final double pricePerMessage;
  final double imagePrice;

  /// Net cash (payer side only).
  final double? balance;

  /// Net earnings (host side only).
  final double? earnings;

  /// Why [chatEnabled] is false, when the server says (`CHAT_NOT_AVAILABLE`:
  /// company-only chat with someone who isn't a company account).
  final String? reason;

  /// Chat can't happen with this person at all (not just "chats off").
  bool get notAvailable => reason == 'CHAT_NOT_AVAILABLE';

  bool get paying => mySide == ChatSide.payer;

  ChatOpen withConversation(String id) => ChatOpen(
    conversationId: id,
    mySide: mySide,
    peer: peer,
    chatEnabled: chatEnabled,
    pricePerMessage: pricePerMessage,
    imagePrice: imagePrice,
    balance: balance,
    earnings: earnings,
    reason: reason,
  );
}

/// `GET|PUT /chats/settings`.
@immutable
class ChatSettings {
  const ChatSettings({this.acceptChats, this.notify = true});

  factory ChatSettings.fromJson(Object? json) {
    final j = Strapi.map(json) ?? const <String, dynamic>{};
    return ChatSettings(
      acceptChats: j['acceptChats'] == null
          ? null
          : J.boolean(j['acceptChats']),
      notify: _flag(j['notify'], true),
    );
  }

  /// Hosts only; null for everyone else.
  final bool? acceptChats;
  final bool notify;

  ChatSettings copyWith({bool? acceptChats, bool? notify}) => ChatSettings(
    acceptChats: acceptChats ?? this.acceptChats,
    notify: notify ?? this.notify,
  );
}
