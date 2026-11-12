import 'dart:typed_data';

import 'package:dio/dio.dart';

import '../../../core/network/api_client.dart';
import '../../../core/network/api_exception.dart';
import '../../../core/network/strapi.dart';
import 'chat_models.dart';

/// The server's refusal codes (contract §4, `error.details.code`).
abstract final class ChatCodes {
  static const invalidTarget = 'INVALID_TARGET';
  static const validation = 'CHAT_VALIDATION';
  static const priceOutOfRange = 'PRICE_OUT_OF_RANGE';
  static const lowBalance = 'CHAT_LOW_BALANCE';
  static const lowEarnings = 'CHAT_LOW_EARNINGS';
  static const hostsOnly = 'CHAT_HOSTS_ONLY';
  static const blocked = 'CHAT_BLOCKED';
  static const replyOnly = 'CHAT_REPLY_ONLY';
  static const photoPrivate = 'PHOTO_PRIVATE';
  static const photoLocked = 'PHOTO_LOCKED';
  static const notFound = 'NOT_FOUND';
  static const hostOff = 'CHAT_HOST_OFF';
  static const photoExpired = 'PHOTO_EXPIRED';
  static const rateLimited = 'CHAT_RATE_LIMITED';
  static const disabled = 'CHAT_DISABLED';
  static const privatePhotosDisabled = 'PRIVATE_PHOTOS_DISABLED';

  /// Company-only chat and one side is not a company account (403 on send;
  /// `/chats/with` says it as `reason`).
  static const notAvailable = 'CHAT_NOT_AVAILABLE';

  /// Vanish mode (2026-11-12): sent as vanish but it is off on the server
  /// (the other person turned it off) — nothing was stored.
  static const vanishOff = 'CHAT_VANISH_OFF';

  /// The admin switched vanish mode off.
  static const vanishDisabled = 'CHAT_VANISH_DISABLED';

  /// Too many unread vanish texts waiting in this chat.
  static const vanishFull = 'CHAT_VANISH_FULL';

  /// Codes with their own copy in `chat:errors.*`.
  static const _known = {
    invalidTarget,
    validation,
    priceOutOfRange,
    lowBalance,
    lowEarnings,
    hostsOnly,
    blocked,
    replyOnly,
    photoPrivate,
    photoLocked,
    notFound,
    hostOff,
    photoExpired,
    rateLimited,
    disabled,
    privatePhotosDisabled,
    notAvailable,
    vanishOff,
    vanishDisabled,
    vanishFull,
  };

  /// `chat:errors.<code>` for a known code, else null.
  static String? keyFor(String? code) =>
      code != null && _known.contains(code) ? 'chat:errors.$code' : null;
}

/// What a chat refusal carried: its code and the extra numbers.
class ChatRefusal {
  const ChatRefusal({
    this.code,
    this.reason,
    this.required,
    this.balance,
    this.min,
    this.max,
  });

  /// Reads `error.details` (Strapi), then older shapes. Never throws.
  factory ChatRefusal.of(ApiException e) {
    final data = e.data;
    if (data is! Map) return ChatRefusal(code: _byStatus(e.statusCode));
    final error = data['error'];
    final details = error is Map && error['details'] is Map
        ? error['details'] as Map
        : const {};
    Object? read(String k) =>
        details[k] ?? (error is Map ? error[k] : null) ?? data[k];
    final code = J.str(read('code'))?.trim();
    return ChatRefusal(
      code: code == null || code.isEmpty ? _byStatus(e.statusCode) : code,
      reason: J.str(read('reason')),
      required: J.number(read('required')),
      balance: J.number(read('balance')),
      min: J.number(read('min')),
      max: J.number(read('max')),
    );
  }

  /// Codes a status alone settles (a proxy may strip the body).
  static String? _byStatus(int? status) => switch (status) {
    402 => ChatCodes.lowBalance,
    410 => ChatCodes.photoExpired,
    _ => null,
  };

  final String? code;

  /// `CHAT_VALIDATION`'s why (`too_long`, `blocked_text`, …).
  final String? reason;
  final double? required;
  final double? balance;
  final double? min;
  final double? max;

  bool get isLowBalance => code == ChatCodes.lowBalance;
}

/// `/chats/*` (backend docs/chat_api.md §4). Errors carry the server's code
/// in [ApiException.data] ([ChatRefusal.of]) and our own copy as
/// [ApiException.messageKey] for the known ones.
abstract final class ChatApi {
  static const pageSize = 40;
  static const listPageSize = 30;

  /// Off when the server has no chat (an older backend answers 404) or
  /// refuses: every entry point stays hidden. Network trouble is thrown, so
  /// the last known config keeps showing.
  static Future<ChatConfig> fetchConfig() async {
    try {
      return ChatConfig.fromJson(await ApiClient.get('/chats/config'));
    } on ApiException catch (e) {
      if (e.type == ApiErrorType.network ||
          e.type == ApiErrorType.timeout ||
          e.type == ApiErrorType.server ||
          e.isAuthError) {
        rethrow;
      }
      return ChatConfig.off;
    }
  }

  static Future<ChatConversationsPage> fetchConversations({
    String filter = 'all',
    String? before,
    int limit = listPageSize,
  }) async => ChatConversationsPage.fromJson(
    await _guard(
      () => ApiClient.get(
        '/chats/conversations',
        query: {'filter': filter, 'before': ?before, 'limit': limit},
      ),
    ),
  );

  static Future<int> fetchUnread() async {
    final body = await _guard(() => ApiClient.get('/chats/unread'));
    return J.integer(Strapi.map(body)?['unreadTotal']) ?? 0;
  }

  static Future<ChatOpen> openWith(String userId) async => ChatOpen.fromJson(
    await _guard(
      () => ApiClient.get('/chats/with/${Uri.encodeComponent(userId)}'),
    ),
  );

  /// [before]: an older page under that message; [after]: what is newer
  /// than that message (sync). Newest first.
  static Future<ChatMessagesPage> fetchMessages(
    String conversationId, {
    String? before,
    String? after,
    int limit = pageSize,
  }) async => ChatMessagesPage.fromJson(
    await _guard(
      () => ApiClient.get(
        '/chats/conversations/${Uri.encodeComponent(conversationId)}/messages',
        query: {'before': ?before, 'after': ?after, 'limit': limit},
      ),
    ),
  );

  static Future<void> markRead(String conversationId) async {
    await _guard(
      () => ApiClient.post(
        '/chats/conversations/${Uri.encodeComponent(conversationId)}/read',
      ),
    );
  }

  /// [vanish]: written in vanish mode. If the server says vanish mode is
  /// off the send is refused (`CHAT_VANISH_OFF`) instead of being stored.
  static Future<ChatSendResult> sendText({
    required String toUserId,
    required String text,
    required String clientId,
    bool vanish = false,
  }) async => ChatSendResult.fromJson(
    await _guard(
      () => ApiClient.post(
        '/chats/messages',
        data: {
          'toUserId': toUserId,
          'text': text,
          'clientId': clientId,
          if (vanish) 'vanish': true,
        },
      ),
    ),
  );

  /// Vanish mode and its waiting texts. [enter]: the chat screen just opened
  /// (the server first removes what I read before and left).
  static Future<ChatVanishState> fetchVanish(
    String conversationId, {
    bool enter = false,
  }) async => ChatVanishState.fromJson(
    await _guard(
      () => ApiClient.get(
        '/chats/conversations/${Uri.encodeComponent(conversationId)}/vanish',
        query: {if (enter) 'enter': '1'},
      ),
    ),
  );

  /// Turns vanish mode on or off for this chat (both people). Off removes
  /// every vanish text in it.
  static Future<ChatVanishState> setVanish(
    String conversationId, {
    required bool on,
  }) async => ChatVanishState.fromJson(
    await _guard(
      () => ApiClient.post(
        '/chats/conversations/${Uri.encodeComponent(conversationId)}/vanish',
        data: {'on': on},
      ),
    ),
  );

  /// I left the chat: the vanish texts I read are removed, for both of us.
  static Future<void> leaveVanish(String conversationId) async {
    await _guard(
      () => ApiClient.post(
        '/chats/conversations/${Uri.encodeComponent(conversationId)}/vanish/leave',
      ),
    );
  }

  /// A photo ([ChatMessageType.image]) or voice note ([ChatMessageType.audio]).
  static Future<ChatSendResult> sendMedia({
    required String toUserId,
    required String clientId,
    required ChatMessageType type,
    required String path,
    int? durationSec,
    int? width,
    int? height,
  }) async {
    final audio = type == ChatMessageType.audio;
    final form = FormData.fromMap({
      'toUserId': toUserId,
      'clientId': clientId,
      'type': type.wire,
      'durationSec': ?durationSec,
      'width': ?width,
      'height': ?height,
      'file': await MultipartFile.fromFile(
        path,
        filename: '$clientId.${audio ? 'm4a' : 'jpg'}',
        contentType: DioMediaType.parse(audio ? 'audio/mp4' : 'image/jpeg'),
      ),
    });
    return ChatSendResult.fromJson(
      await _guard(() => ApiClient.upload('/chats/messages', form)),
    );
  }

  /// Host side: a private photo at [price] rupees.
  static Future<ChatSendResult> sendPrivatePhoto({
    required String toUserId,
    required String clientId,
    required double price,
    required String path,
  }) async {
    final form = FormData.fromMap({
      'toUserId': toUserId,
      'clientId': clientId,
      'price': price.toStringAsFixed(2),
      'file': await MultipartFile.fromFile(
        path,
        filename: '$clientId.jpg',
        contentType: DioMediaType.parse('image/jpeg'),
      ),
    });
    return ChatSendResult.fromJson(
      await _guard(() => ApiClient.upload('/chats/private-photos', form)),
    );
  }

  /// Pays for a private photo; never charged twice by the server.
  static Future<ChatSendResult> unlock(String messageId) async =>
      ChatSendResult.fromJson(
        await _guard(
          () => ApiClient.post(
            '/chats/messages/${Uri.encodeComponent(messageId)}/unlock',
          ),
        ),
      );

  /// The bought photo's bytes, held in memory only (`no-store`).
  static Future<Uint8List> fetchPrivatePhoto(String messageId) => _guard(
    () => ApiClient.getBytes(
      '/chats/messages/${Uri.encodeComponent(messageId)}/photo',
    ),
  );

  /// Delivery receipts from pushes. No sign-in: callable from the
  /// background isolate.
  static Future<void> postReceipts(List<String> receipts) async {
    if (receipts.isEmpty) return;
    await ApiClient.post(
      '/chats/receipts',
      data: {'receipts': receipts},
      skipAuth: true,
    );
  }

  static Future<ChatSettings> fetchSettings() async => ChatSettings.fromJson(
    await _guard(() => ApiClient.get('/chats/settings')),
  );

  static Future<ChatSettings> updateSettings({
    bool? acceptChats,
    bool? notify,
  }) async => ChatSettings.fromJson(
    await _guard(
      () => ApiClient.put(
        '/chats/settings',
        data: {'acceptChats': ?acceptChats, 'notify': ?notify},
      ),
    ),
  );

  static Future<void> report(ChatReportInput input) async {
    await _guard(() => ApiClient.post('/chats/report', data: input.toJson()));
  }
}

/// `POST /chats/report`.
class ChatReportInput {
  const ChatReportInput({
    required this.conversationId,
    required this.reason,
    this.messageId,
    this.vanishMessageId,
    this.categoryId,
  });

  final String conversationId;
  final String reason;
  final String? messageId;

  /// A reported vanish text: the server copies it into the report.
  final String? vanishMessageId;
  final Object? categoryId;

  JsonMap toJson() => {
    'conversationId': conversationId,
    'messageId': ?messageId,
    'vanishMessageId': ?vanishMessageId,
    'categoryId': ?categoryId,
    'reason': reason,
  };
}

/// Puts our copy on a known refusal; the code stays readable from `data`.
Future<T> _guard<T>(Future<T> Function() body) async {
  try {
    return await body();
  } on ApiException catch (e, st) {
    final refusal = ChatRefusal.of(e);
    // A validation refusal with its own why (community rules, shared contact details) gets
    // its own line; everything else falls back to the code's copy.
    final key = refusal.code == ChatCodes.validation
        ? switch (refusal.reason) {
            'blocked_text' => 'chat:errors.blocked_text',
            'contact_info' => 'chat:errors.contact_info',
            'vanish_text_only' => 'chat:errors.vanish_text_only',
            'duration' => 'chat:errors.voice_too_long',
            _ => ChatCodes.keyFor(refusal.code),
          }
        : ChatCodes.keyFor(refusal.code);
    if (key == null || e.messageKey != null) rethrow;
    Error.throwWithStackTrace(
      ApiException(
        e.type == ApiErrorType.unknown ? ApiErrorType.rejected : e.type,
        statusCode: e.statusCode,
        messageKey: key,
        data: e.data,
        cause: e.cause,
        stackTrace: e.stackTrace,
      ),
      st,
    );
  }
}
