import 'dart:convert';
import 'dart:io' show Platform;
import 'dart:ui' show PlatformDispatcher;

import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

import '../../../../core/analytics/events/chat_events.dart';
import '../../../../core/i18n/i18n.dart';
import '../../../../core/storage/app_prefs.dart';
import '../../../../core/utils/log.dart';
import '../../../chatscreen/helper/chat_receipts.dart';
import '../../../chatscreen/helper/chat_sync.dart';
import '../call_controller.dart';
import 'local_notifier.dart';
import 'push_envelope.dart';
import 'push_session.dart';

/// Chat pushes (backend docs/chat_api.md §5). `CHAT_MESSAGE` and
/// `CHAT_SYNC` are hints: the open chat re-reads from the API, the badge
/// and the list refresh. A `CHAT_MESSAGE` also posts its delivery receipt
/// (any isolate) and, unless the chat is on screen or the receiver turned
/// chat notifications off (`silent: "1"`), is drawn: on Android one
/// notification per conversation in MessagingStyle, its lines adding up;
/// in the foreground on both platforms (iOS draws its own alert while the
/// app is behind).
abstract final class ChatPush {
  static const _tag = 'ChatPush';
  static const message = 'chat_message';
  static const sync = 'chat_sync';
  static const channelId = 'chat_messages';

  /// Any chat push ([PushEnvelope.type] is lower-cased).
  static bool matches(PushEnvelope m) => m.type.startsWith('chat_');

  static bool isMessage(PushEnvelope m) => m.type == message;

  static bool isSilent(PushEnvelope m) => (m.data['silent'] ?? '') == '1';

  static ChatHint hintOf(PushEnvelope m) => ChatHint(
    conversationId: _text(m.data['conversationId']),
    peerUserId: isMessage(m) ? _text(m.data['senderId']) : null,
    event: isMessage(m) ? 'message' : (_text(m.data['event']) ?? 'message'),
    messageId: _text(m.data['messageId']),
  );

  /// Where a tap goes: the chat with the sender.
  static String? tapRoute(PushEnvelope m) {
    final sender = _text(m.data['senderId']);
    return sender == null ? null : '/chat/${Uri.encodeComponent(sender)}';
  }

  /// UI isolate, app in front.
  static Future<void> onForeground(PushEnvelope m) async {
    final hint = hintOf(m);
    if (isMessage(m)) await ChatReceipts.post(m.data['receipt']);
    ChatSync.instance.onPush(hint);
    if (!isMessage(m)) return;
    final String action;
    if (isSilent(m)) {
      action = 'suppressed_silent';
    } else if (ChatSync.instance.isOnScreen(
      conversationId: hint.conversationId,
      peerUserId: hint.peerUserId,
    )) {
      action = 'suppressed_on_screen';
    } else if (CallController.instance.isOnCall) {
      action = 'suppressed_call';
    } else {
      action = 'drawn';
      await show(m);
    }
    ChatEvents.push(event: m.type, action: action, background: false);
  }

  /// The FCM background isolate (app behind or killed): the receipt, and
  /// the Android notification. Never re-reads (the app does on resume).
  static Future<void> onBackground(
    PushEnvelope m, {
    required bool alreadyShownByOs,
  }) async {
    if (!isMessage(m)) return;
    await ChatReceipts.post(m.data['receipt']);
    if (isSilent(m) || alreadyShownByOs || !PushSession.isSignedIn) return;
    // iOS: the alert is the system's (thread-id = conversation).
    if (!Platform.isAndroid) return;
    await show(m);
    ChatEvents.push(event: m.type, action: 'drawn', background: true);
  }

  /// Draws (or updates) the conversation's notification. Never throws.
  static Future<void> show(PushEnvelope m) async {
    try {
      await LocalNotifier.init();
      await ChatPushStrings.ensure();
      final conversation = _text(m.data['conversationId']) ?? 'chat';
      final key = 'chat_$conversation';
      final id = LocalNotifier.idFor(key);
      final name =
          _text(m.data['senderName']) ??
          m.title ??
          ChatPushStrings.t('new_message');
      final body = previewOf(m);
      final at = m.sentAt ?? DateTime.now();
      final details = Platform.isAndroid
          ? await _android(id, conversation, name, body, at, m)
          : NotificationDetails(
              iOS: DarwinNotificationDetails(
                presentAlert: true,
                presentBanner: true,
                presentList: true,
                presentSound: true,
                threadIdentifier: conversation,
              ),
            );
      await LocalNotifier.plugin.show(
        id: id,
        title: name,
        body: body,
        notificationDetails: details,
        payload: m.copyWith(notificationId: key).toPayload(),
      );
    } catch (e) {
      Log.w(_tag, 'show failed: $e');
    }
  }

  static Future<NotificationDetails> _android(
    int id,
    String conversation,
    String name,
    String body,
    DateTime at,
    PushEnvelope m,
  ) async {
    final sender = Person(name: name, key: _text(m.data['senderId']));
    // Lines already in the tray for this chat, then this one.
    MessagingStyleInformation? previous;
    try {
      previous = await LocalNotifier.plugin
          .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin
          >()
          ?.getActiveNotificationMessagingStyle(id: id);
    } catch (_) {}
    final lines = [...?previous?.messages, Message(body, at, sender)];
    final recent = lines.length > 6 ? lines.sublist(lines.length - 6) : lines;
    return NotificationDetails(
      android: AndroidNotificationDetails(
        channelId,
        ChatPushStrings.t('channel'),
        importance: Importance.high,
        priority: Priority.high,
        icon: LocalNotifier.smallIcon,
        color: LocalNotifier.brand,
        category: AndroidNotificationCategory.message,
        styleInformation: MessagingStyleInformation(
          Person(name: ChatPushStrings.t('you')),
          groupConversation: false,
          messages: recent,
        ),
        autoCancel: true,
        showWhen: true,
        when: at.millisecondsSinceEpoch,
        visibility: NotificationVisibility.private,
      ),
    );
  }

  /// The line under the name: the text, or "Photo" / "Voice message" /
  /// "🔒 Private photo" in the app language.
  static String previewOf(PushEnvelope m) {
    switch (m.data['messageType']) {
      case 'image':
        return ChatPushStrings.t('photo');
      case 'audio':
        return ChatPushStrings.t('voice');
      case 'private_image':
        return ChatPushStrings.t('private_photo');
    }
    return _text(m.data['preview']) ??
        m.body ??
        ChatPushStrings.t('new_message');
  }

  /// The chat opened: its notification goes.
  static Future<void> clear(String conversationId) =>
      LocalNotifier.cancel(LocalNotifier.idFor('chat_$conversationId'));

  static String? _text(Object? v) {
    final s = v?.toString().trim();
    return s == null || s.isEmpty || s == 'null' ? null : s;
  }
}

/// `chat:push.*` for code without a `BuildContext` (any isolate), in the
/// saved app language, else the device's, else English.
abstract final class ChatPushStrings {
  static const _localeKey = 'app_locale'; // LocaleController's key
  static Map<String, dynamic>? _table;
  static Map<String, dynamic>? _fallback;
  static String? _lang;

  static Future<void> ensure() async {
    final lang = _language();
    if (_table != null && _lang == lang) return;
    _fallback ??= await _load('en');
    _table = lang == 'en' ? _fallback : (await _load(lang) ?? _fallback);
    _lang = lang;
  }

  static String t(String key) =>
      _table?[key] as String? ??
      _fallback?[key] as String? ??
      _english[key] ??
      key;

  static String _language() {
    final saved = AppPrefs.getString(_localeKey);
    final device = PlatformDispatcher.instance.locale.languageCode;
    for (final c in [saved, device]) {
      if (c != null &&
          AppI18n.supportedLocales.any((l) => l.languageCode == c)) {
        return c;
      }
    }
    return 'en';
  }

  static Future<Map<String, dynamic>?> _load(String lang) async {
    try {
      final raw = await rootBundle.loadString('assets/i18n/$lang/chat.json');
      final json = jsonDecode(raw);
      final push = json is Map ? json['push'] : null;
      return push is Map ? Map<String, dynamic>.from(push) : null;
    } catch (e) {
      Log.w('ChatPushStrings', 'no $lang strings: $e');
      return null;
    }
  }

  static const _english = {
    'photo': 'Photo',
    'voice': 'Voice message',
    'private_photo': '🔒 Private photo',
    'new_message': 'New message',
    'channel': 'Chat messages',
    'you': 'You',
  };
}
