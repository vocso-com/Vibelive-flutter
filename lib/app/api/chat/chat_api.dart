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

  static Future<ChatSendResult> sendText({
    required String toUserId,
    required String text,
    required String clientId,
  }) async => ChatSendResult.fromJson(
    await _guard(
      () => ApiClient.post(
        '/chats/messages',
        data: {'toUserId': toUserId, 'text': text, 'clientId': clientId},
      ),
    ),
  );

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
    this.categoryId,
  });

  final String conversationId;
  final String reason;
  final String? messageId;
  final Object? categoryId;

  JsonMap toJson() => {
    'conversationId': conversationId,
    'messageId': ?messageId,
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
    // Text the community rules refuse gets its own line.
    final key =
        refusal.code == ChatCodes.validation && refusal.reason == 'blocked_text'
        ? 'chat:errors.blocked_text'
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
