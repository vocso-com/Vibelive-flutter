import '../analytics.dart';

/// Paid user ↔ host chat. Catalog: docs/analytics_events.md (Chat). Ids,
/// counts and booleans only: never message text. [type]: `text` / `image`
/// / `audio` / `private_image`.
abstract final class ChatEvents {
  // ── Entry and list ─────────────────────────────────────────────────────

  /// A Chat button / action was tapped. [source]: `profile` / `history` /
  /// `push` / `link` / `list`.
  static void entryTapped({required String source, String? peerId}) =>
      Analytics.log('chat_entry_tapped', {'source': source, 'peer_id': peerId});

  /// A chat screen loaded who it is with (once per opening).
  static void opened({
    required String peerId,
    required bool paying,
    required bool peerIsHost,
    required bool hasConversation,
    required bool chatEnabled,
  }) => Analytics.log('chat_opened', {
    'peer_id': peerId,
    'paying': paying,
    'peer_is_host': peerIsHost,
    'has_conversation': hasConversation,
    'chat_enabled': chatEnabled,
  });

  /// A filter of the Chats tab. [filter]: `all` / `unread` / `online`.
  static void listFilter(String filter) =>
      Analytics.log('chat_list_filter', {'filter': filter});

  static void conversationTapped({
    required String peerId,
    required int unread,
  }) => Analytics.log('chat_conversation_tapped', {
    'peer_id': peerId,
    'unread': unread,
  });

  // ── Sending ────────────────────────────────────────────────────────────

  /// Written and queued. [pricePaise]: what it costs this side (null:
  /// unknown host media price). Meta value = rupees.
  static void messageSent({
    required String type,
    required bool paying,
    int? pricePaise,
    int? seconds,
  }) => Analytics.log('chat_message_sent', {
    'type': type,
    'paying': paying,
    'price': pricePaise == null ? null : pricePaise / 100,
    'seconds': seconds,
  });

  /// The server saved it. [charged]: rupees taken now (0 on a retry the
  /// server already had).
  static void messageDelivered({
    required String type,
    required double charged,
    required int attempts,
  }) => Analytics.log('chat_message_saved', {
    'type': type,
    'charged': charged,
    'attempts': attempts,
  });

  /// Refused or failed. [reason]: the server code, or the error type.
  static void messageFailed({required String type, required String reason}) =>
      Analytics.log('chat_message_failed', {'type': type, 'reason': reason});

  /// A failed bubble sent again (same clientId) or removed.
  static void failedAction({required String type, required String action}) =>
      Analytics.log('chat_failed_action', {'type': type, 'action': action});

  static void photoPicked(String source) =>
      Analytics.log('chat_photo_picked', {'source': source});

  /// [outcome]: `sent` / `cancelled` / `too_short` / `denied`.
  static void voiceRecorded({required String outcome, int? seconds}) =>
      Analytics.log('chat_voice_recorded', {
        'outcome': outcome,
        'seconds': seconds,
      });

  // ── Money ──────────────────────────────────────────────────────────────

  /// The low-balance bar came up. [left]: messages the balance still pays.
  static void lowBalanceShown(int left) => Analytics.logOnce(
    'chat_low_balance_$left',
    'chat_low_balance_shown',
    {'messages_left': left},
  );

  /// The wallet opened from a chat (the app's own top-up). [source]:
  /// `send` (a 402: the text is back in the box) / `bar` / `prices` /
  /// `unlock`.
  static void addMoney(String source) =>
      Analytics.log('chat_add_money', {'source': source});

  // ── Private photos ─────────────────────────────────────────────────────

  static void privatePhotoSent(double price) =>
      Analytics.log('chat_private_photo_sent', {'price': price});

  /// [step]: `asked` / `confirmed` / `paid` / `failed`.
  static void privatePhotoUnlock({
    required String step,
    required double price,
    String? error,
  }) => Analytics.log('chat_private_photo_unlock', {
    'step': step,
    'price': price,
    'error': error,
  });

  static void privatePhotoViewed({required int seconds}) =>
      Analytics.log('chat_private_photo_viewed', {'view_seconds': seconds});

  // ── Menu, safety, calls ────────────────────────────────────────────────

  /// [action]: `prices` / `report` / `block` / `dismissed`.
  static void menuAction(String action) =>
      Analytics.log('chat_menu_action', {'action': action});

  static void reported({String? category}) =>
      Analytics.log('chat_reported', {'category': category});

  static void reportFailed({required String error}) =>
      Analytics.log('chat_report_failed', {'error': error});

  /// [step]: `confirmed` / `cancelled` / `success` / `failed`.
  static void blocked(String step) =>
      Analytics.log('chat_block', {'step': step});

  static void callTapped(String callType) =>
      Analytics.log('chat_call_tapped', {'call_type': callType});

  // ── Push and settings ──────────────────────────────────────────────────

  /// A chat push. [action]: `drawn` / `suppressed_on_screen` /
  /// `suppressed_silent` / `hint`.
  static void push({
    required String event,
    required String action,
    required bool background,
  }) => Analytics.log('chat_push', {
    'event': event,
    'action': action,
    'background': background,
  });

  /// [setting]: `notify` / `accept_chats`.
  static void settingChanged({required String setting, required bool on}) =>
      Analytics.log('chat_setting_changed', {'setting': setting, 'on': on});
}
