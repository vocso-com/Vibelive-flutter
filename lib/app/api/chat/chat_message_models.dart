import 'package:flutter/foundation.dart';

import '../../../core/network/strapi.dart';

/// Messages of the chat API (backend docs/chat_api.md §4), parsed
/// leniently like the rest of `chat_models.dart` (which exports this).

JsonMap _map(Object? v) =>
    v is Map ? Map<String, dynamic>.from(v) : const <String, dynamic>{};

double _money(Object? v) => J.number(v) ?? 0;

DateTime? _date(Object? v) => J.date(v is String ? v : J.str(v));

/// Message types. [unknown]: a type this build does not know (shown as a
/// short "update the app" line instead of breaking the list).
enum ChatMessageType {
  text,
  image,
  audio,
  privateImage,
  unknown;

  static ChatMessageType parse(Object? v) => switch (J.str(v)) {
    'text' => text,
    'image' => image,
    'audio' => audio,
    'private_image' => privateImage,
    _ => unknown,
  };

  /// The API's name.
  String get wire => switch (this) {
    privateImage => 'private_image',
    _ => name,
  };
}

/// `media` of a photo or voice note.
@immutable
class ChatMedia {
  const ChatMedia({
    this.url,
    this.thumb,
    this.width,
    this.height,
    this.durationSec,
  });

  static ChatMedia? fromJson(Object? json) {
    if (json is! Map) return null;
    final j = _map(json);
    return ChatMedia(
      url: Strapi.mediaUrl(J.str(j['url'])),
      thumb: Strapi.mediaUrl(J.str(j['thumb'])),
      width: J.integer(j['width']),
      height: J.integer(j['height']),
      durationSec: J.integer(j['durationSec']),
    );
  }

  final String? url;
  final String? thumb;
  final int? width;
  final int? height;
  final int? durationSec;
}

/// `private` of a private photo: never the photo itself.
@immutable
class ChatPrivatePhoto {
  const ChatPrivatePhoto({
    required this.price,
    this.previewUrl,
    this.previewWidth,
    this.previewHeight,
    this.unlocked = false,
    this.expiresAt,
  });

  static ChatPrivatePhoto? fromJson(Object? json) {
    if (json is! Map) return null;
    final j = _map(json);
    final preview = j['preview'];
    final p = _map(preview);
    return ChatPrivatePhoto(
      price: _money(j['price']),
      previewUrl: Strapi.mediaUrl(
        preview is String ? preview : J.str(p['url']),
      ),
      previewWidth: J.integer(p['width']),
      previewHeight: J.integer(p['height']),
      unlocked: J.boolean(j['unlocked']),
      expiresAt: _date(j['expiresAt']),
    );
  }

  /// Rupees.
  final double price;

  /// The blurred copy: all anyone sees in the chat.
  final String? previewUrl;
  final int? previewWidth;
  final int? previewHeight;
  final bool unlocked;

  /// The buyer can open it until then.
  final DateTime? expiresAt;

  /// Paid for and still openable at [now].
  bool canOpenAt(DateTime now) =>
      unlocked && expiresAt != null && now.isBefore(expiresAt!);

  ChatPrivatePhoto unlockedUntil(DateTime? until) => ChatPrivatePhoto(
    price: price,
    previewUrl: previewUrl,
    previewWidth: previewWidth,
    previewHeight: previewHeight,
    unlocked: true,
    expiresAt: until ?? expiresAt,
  );
}

/// Where an own message is on its way out (server messages are [sent]).
enum ChatSendState {
  sent,

  /// Waiting to go out: offline, or behind an earlier one.
  queued,
  sending,

  /// Refused or failed for good: tap to retry (same clientId).
  failed,
}

/// `Message` (§4), plus the local state of an own message on its way out.
@immutable
class ChatMessage {
  const ChatMessage({
    required this.id,
    required this.senderId,
    required this.type,
    required this.createdAt,
    this.conversationId,
    this.text,
    this.media,
    this.privatePhoto,
    this.clientId,
    this.deliveredAt,
    this.readAt,
    this.localPath,
    this.state = ChatSendState.sent,
    this.errorKey,
  });

  factory ChatMessage.fromJson(Object? json) {
    final j = _map(json);
    return ChatMessage(
      id: J.str(j['id'] ?? j['documentId']) ?? '',
      conversationId: J.str(j['conversationId']),
      senderId: J.str(j['senderId']) ?? '',
      type: ChatMessageType.parse(j['type']),
      text: J.str(j['text']),
      media: ChatMedia.fromJson(j['media']),
      privatePhoto: ChatPrivatePhoto.fromJson(j['private']),
      clientId: J.str(j['clientId']),
      createdAt: _date(j['createdAt']) ?? DateTime.now(),
      deliveredAt: _date(j['deliveredAt']),
      readAt: _date(j['readAt']),
    );
  }

  final String id;
  final String? conversationId;
  final String senderId;
  final ChatMessageType type;
  final String? text;
  final ChatMedia? media;
  final ChatPrivatePhoto? privatePhoto;
  final String? clientId;
  final DateTime createdAt;
  final DateTime? deliveredAt;
  final DateTime? readAt;

  /// The picture or recording on this phone, while it is being sent.
  final String? localPath;
  final ChatSendState state;

  /// i18n key of why a [ChatSendState.failed] message did not go.
  final String? errorKey;

  /// Stable across "sending" → "sent" (the server echoes the clientId), so
  /// the list keeps the same row.
  String get key => '$senderId:${clientId ?? id}';

  bool get isLocal => state != ChatSendState.sent;

  ChatMessage copyWith({
    DateTime? readAt,
    DateTime? deliveredAt,
    ChatPrivatePhoto? privatePhoto,
    ChatSendState? state,
    String? errorKey,
    bool clearError = false,
  }) => ChatMessage(
    id: id,
    conversationId: conversationId,
    senderId: senderId,
    type: type,
    createdAt: createdAt,
    text: text,
    media: media,
    privatePhoto: privatePhoto ?? this.privatePhoto,
    clientId: clientId,
    deliveredAt: deliveredAt ?? this.deliveredAt,
    readAt: readAt ?? this.readAt,
    localPath: localPath,
    state: state ?? this.state,
    errorKey: clearError ? null : (errorKey ?? this.errorKey),
  );
}

/// `GET /chats/conversations/:id/messages`.
@immutable
class ChatMessagesPage {
  const ChatMessagesPage({
    this.items = const [],
    this.peerDeliveredAt,
    this.peerReadAt,
    this.hasMore = false,
  });

  factory ChatMessagesPage.fromJson(Object? json) {
    final j = _map(json);
    final items = j['items'] ?? j['data'];
    return ChatMessagesPage(
      items: [
        if (items is List)
          for (final m in items) ChatMessage.fromJson(m),
      ].where((m) => m.id.isNotEmpty).toList(),
      peerDeliveredAt: _date(j['peerDeliveredAt']),
      peerReadAt: _date(j['peerReadAt']),
      hasMore: J.boolean(j['hasMore']),
    );
  }

  /// Newest first.
  final List<ChatMessage> items;

  /// My messages sent up to then reached / were read by the other person.
  final DateTime? peerDeliveredAt;
  final DateTime? peerReadAt;
  final bool hasMore;
}

/// `POST /chats/messages` (201) and `POST /chats/private-photos`.
@immutable
class ChatSendResult {
  const ChatSendResult({
    required this.message,
    this.charged = 0,
    this.balance,
    this.earnings,
  });

  /// Throws [FormatException] without a saved message (the bubble then
  /// fails and can be sent again with its clientId).
  factory ChatSendResult.fromJson(Object? json) {
    final j = _map(json);
    if (j['message'] is! Map || ChatMessage.fromJson(j['message']).id.isEmpty) {
      throw const FormatException('chat send: no message in the answer');
    }
    return ChatSendResult(
      message: ChatMessage.fromJson(j['message']),
      charged: _money(j['charged']),
      balance: J.number(j['balance']),
      earnings: J.number(j['earnings']),
    );
  }

  final ChatMessage message;
  final double charged;
  final double? balance;
  final double? earnings;
}
