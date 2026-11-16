import 'dart:convert';

import 'package:firebase_messaging/firebase_messaging.dart';

/// One push, whatever it arrived through: an FCM message, the iOS VoIP relay,
/// a local notification tap payload or a launch-details payload (CE port).
///
/// `data` values are strings, as FCM delivers them; a `notification` block's
/// title/body are folded into [title] / [body].
class PushEnvelope {
  const PushEnvelope({
    required this.data,
    this.title,
    this.body,
    this.messageId,
    this.sentAt,
    this.hasNotification = false,
    this.notificationId,
    this.imageUrl,
  });

  /// FCM message. [sentAt] is the envelope's `sentTime`, else the data's own
  /// timestamp.
  factory PushEnvelope.fromRemote(RemoteMessage message) {
    final data = stringify(message.data);
    return PushEnvelope(
      data: data,
      title: message.notification?.title ?? _text(data['title']),
      body: message.notification?.body ?? _text(data['body']),
      messageId: message.messageId,
      sentAt: message.sentTime ?? timestampOf(data),
      hasNotification: message.notification != null,
      imageUrl:
          _https(message.notification?.android?.imageUrl) ??
          _https(message.notification?.apple?.imageUrl) ??
          _https(data['imageUrl']) ??
          _https(data['image']),
    );
  }

  /// A raw map (VoIP relay body, plugin `extra`, tests).
  factory PushEnvelope.fromMap(
    Map<dynamic, dynamic> raw, {
    String? title,
    String? body,
    String? messageId,
    bool hasNotification = false,
  }) {
    final data = stringify(raw);
    return PushEnvelope(
      data: data,
      title: title ?? _text(data['title']),
      body: body ?? _text(data['body']),
      messageId: messageId,
      sentAt: timestampOf(data),
      hasNotification: hasNotification,
    );
  }

  final Map<String, String> data;
  final String? title;
  final String? body;
  final String? messageId;

  /// When the backend sent it (null = unknown).
  final DateTime? sentAt;

  /// The FCM message carried a `notification` block (the OS may draw it).
  final bool hasNotification;

  /// The local notification id this came from (taps on our own banners).
  final String? notificationId;

  /// The notification's picture (FCM `notification.image`), when it has one:
  /// drawn as a big picture when the app shows the notification itself.
  final String? imageUrl;

  /// `data.type`, lowercased.
  String get type => (data['type'] ?? '').toLowerCase();

  /// `action` / `event` / `eventType` / `notificationType`, lowercased.
  String get signal =>
      (data['action'] ??
              data['event'] ??
              data['eventType'] ??
              data['notificationType'] ??
              '')
          .toLowerCase();

  /// `callStatus` / `status`, lowercased.
  String get status =>
      (data['callStatus'] ?? data['status'] ?? '').toLowerCase();

  /// `callId` / `call_id` / `CallId`, else a Talk Now ring's session id
  /// (its ring's callId; older backends end a ring with only that). Null
  /// when absent or empty.
  String? get callId {
    for (final key in const [
      'callId',
      'call_id',
      'CallId',
      'instantCallSessionId',
    ]) {
      final v = data[key]?.trim();
      if (v != null && v.isNotEmpty && v != 'null') return v;
    }
    return null;
  }

  String? get deeplink => _text(data['deeplink']) ?? _text(data['deepLink']);

  String get titleLower => (title ?? '').toLowerCase();
  String get bodyLower => (body ?? '').toLowerCase();

  /// What the call logic receives: the push data as a plain map.
  Map<String, dynamic> get raw => Map<String, dynamic>.from(data);

  bool flag(String key) {
    final v = (data[key] ?? '').toLowerCase();
    return v == 'true' || v == '1' || v == 'yes';
  }

  PushEnvelope copyWith({
    Map<String, String>? data,
    String? title,
    String? body,
    String? notificationId,
  }) => PushEnvelope(
    data: data ?? this.data,
    title: title ?? this.title,
    body: body ?? this.body,
    messageId: messageId,
    sentAt: sentAt,
    hasNotification: hasNotification,
    notificationId: notificationId ?? this.notificationId,
    imageUrl: imageUrl,
  );

  /// The JSON payload attached to every local notification the app shows.
  String toPayload() => jsonEncode({
    'data': data,
    'title': title,
    'body': body,
    'messageId': messageId,
    'sentAt': sentAt?.millisecondsSinceEpoch,
    'notificationId': notificationId,
  });

  static PushEnvelope? fromPayload(String? payload) {
    if (payload == null || payload.isEmpty) return null;
    try {
      final decoded = jsonDecode(payload);
      if (decoded is! Map) return null;
      final data = decoded['data'];
      final sent = decoded['sentAt'];
      return PushEnvelope(
        data: data is Map ? stringify(data) : const {},
        title: _text(decoded['title']),
        body: _text(decoded['body']),
        messageId: _text(decoded['messageId']),
        sentAt: sent is num
            ? DateTime.fromMillisecondsSinceEpoch(sent.toInt())
            : null,
        notificationId: _text(decoded['notificationId']),
      );
    } on FormatException {
      return null;
    }
  }

  /// Every value as a string (nested maps / lists as JSON), nulls dropped.
  static Map<String, String> stringify(Map<dynamic, dynamic> raw) => {
    for (final e in raw.entries)
      if (e.value != null)
        '${e.key}': e.value is String
            ? e.value as String
            : (e.value is Map || e.value is List)
            ? jsonEncode(e.value)
            : '${e.value}',
  };

  /// `timestampMs` / `timestamp` / `ts` / `sentAt`; seconds are promoted to
  /// milliseconds (RN `ts > 2e10 ? ts : ts * 1000`).
  static DateTime? timestampOf(Map<String, String> data) {
    for (final key in const ['timestampMs', 'timestamp', 'ts', 'sentAt']) {
      final n = num.tryParse(data[key] ?? '');
      if (n == null || n <= 0) continue;
      final ms = n > 2e10 ? n.toInt() : (n * 1000).toInt();
      return DateTime.fromMillisecondsSinceEpoch(ms);
    }
    return null;
  }

  static String? _https(Object? v) {
    final s = _text(v);
    return s != null && s.toLowerCase().startsWith('https://') ? s : null;
  }

  static String? _text(Object? v) {
    final s = v?.toString().trim();
    return s == null || s.isEmpty || s == 'null' ? null : s;
  }
}
