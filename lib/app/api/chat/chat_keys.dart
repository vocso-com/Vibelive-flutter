/// Query keys of the chat feature. Same key ⇒ same data type everywhere.
abstract final class ChatKeys {
  static const all = ['chats'];

  /// [ChatConfig].
  static const config = ['chats', 'config'];

  /// int: the dock badge.
  static List<Object> unread(String? userId) => [
    'chats',
    'unread',
    userId ?? '',
  ];

  /// [ChatConversationsPage]: page 1 of a filter (`all` / `unread` /
  /// `online`).
  static List<Object> conversations(String? userId, String filter) => [
    'chats',
    'conversations',
    userId ?? '',
    filter,
  ];

  /// Prefix of every conversations list.
  static const conversationsAll = ['chats', 'conversations'];

  /// [ChatSettings].
  static List<Object> settings(String? userId) => [
    'chats',
    'settings',
    userId ?? '',
  ];
}
