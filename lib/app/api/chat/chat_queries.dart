import 'dart:async';

import 'package:flutter/widgets.dart';

import 'package:flutter_hooks/flutter_hooks.dart';

import '../../../core/network/api_client.dart';
import '../../../core/query/query_hooks.dart';
import '../../../core/query/query_persist.dart';
import '../../../core/session/session_store.dart';
import 'chat_api.dart';
import 'chat_keys.dart';
import 'chat_models.dart';

String? _me() => SessionStore.instance.value.userId?.toString();

// ── Config ───────────────────────────────────────────────────────────────

/// The admin's chat settings. On disk, so entry points (the Chats tab, the
/// profile's Chat button) appear in the first frame; off until known. A
/// `CONFIG_UPDATED` push with `scope: chat` invalidates it.
///
/// [recheckOnResume]: read again each time the app comes back to the
/// front (the dock does), so chat appears by itself once the server has it.
QueryResult<ChatConfig, ApiException> useChatConfig(
  BuildContext context, {
  bool enabled = true,
  bool recheckOnResume = false,
}) {
  final on = enabled && SessionStore.instance.value.isAuthenticated;
  final result = usePersistedQuery<ChatConfig>(
    ChatKeys.config,
    _fetchConfig,
    context: context,
    enabled: on,
    staleDuration: StaleTime.medium,
    toJson: (c) => c.toJson(),
    fromJson: ChatConfig.fromJson,
  );
  useOnAppLifecycleStateChange((_, state) {
    if (recheckOnResume && on && state == AppLifecycleState.resumed) {
      invalidateChatConfig();
    }
  });
  return result;
}

/// [useChatConfig]'s value; [ChatConfig.off] while unknown.
ChatConfig useChatConfigValue(BuildContext context) =>
    useChatConfig(context).data ?? ChatConfig.off;

/// Outside widgets (push handlers, the chat controller).
Future<ChatConfig> ensureChatConfig({
  Duration staleDuration = StaleTime.medium,
}) => queryCache.fetchQuery<ChatConfig>(
  ChatKeys.config,
  _fetchConfig,
  staleDuration: staleDuration,
);

/// Every read of the config: kept on disk, and tells [ChatAvailability].
Future<ChatConfig> _fetchConfig() async {
  final config = await ChatApi.fetchConfig();
  QueryPersist.write(ChatKeys.config, config.toJson());
  ChatAvailability.instance.value = config.enabled;
  return config;
}

/// Whether chat is on, for the entry points (the dock's Chats tab, the
/// profile's Chat button, the call-log action, the settings card). A plain
/// notifier, so a widget can read it without a query provider: off until
/// a read says `enabled: true` (the last good answer is kept on disk), and
/// a failed read changes nothing.
class ChatAvailability extends ValueNotifier<bool> {
  ChatAvailability._() : super(currentChatConfig().enabled) {
    SessionStore.instance.addListener(_onSession);
  }
  static final ChatAvailability instance = ChatAvailability._();

  /// Signed out: chat is off. The next account reads its own config (chat
  /// answers per account: a company tester's "on" must never show for the
  /// real user who signs in after them on the same phone).
  void _onSession() {
    if (!SessionStore.instance.value.isAuthenticated) value = false;
  }

  /// Reads the config again (app back in front, CONFIG_UPDATED). Never
  /// throws; signed out does nothing.
  Future<void> recheck({bool fresh = true}) async {
    if (!SessionStore.instance.value.isAuthenticated) return;
    try {
      await ensureChatConfig(
        staleDuration: fresh ? StaleTime.none : StaleTime.medium,
      );
    } catch (_) {
      // Chat stays as it was: never an error for a feature the server may
      // not have yet.
    }
  }
}

/// The config in the cache right now (any age), else the disk copy;
/// [ChatConfig.off] when neither.
ChatConfig currentChatConfig() =>
    queryCache.entry<ChatConfig>(ChatKeys.config)?.data ??
    QueryPersist.read<ChatConfig>(ChatKeys.config, ChatConfig.fromJson) ??
    ChatConfig.off;

void invalidateChatConfig() {
  queryCache.invalidateAll(const [ChatKeys.config]);
  unawaited(ChatAvailability.instance.recheck());
}

// ── Badge and lists ──────────────────────────────────────────────────────

/// Unread messages over every chat: the dock badge. Refreshed by pushes
/// and when the app comes back (`ChatSync`).
QueryResult<int, ApiException> useChatUnread(
  BuildContext context, {
  bool enabled = true,
}) {
  final me = _me();
  return useApiQuery<int>(
    ChatKeys.unread(me),
    ChatApi.fetchUnread,
    context: context,
    enabled: enabled && me != null,
    staleDuration: StaleTime.short,
  );
}

/// Page 1 of the chat list for [filter]; on disk for an instant tab.
QueryResult<ChatConversationsPage, ApiException> useChatConversations(
  BuildContext context, {
  required String filter,
  bool enabled = true,
}) {
  final me = _me();
  return usePersistedQuery<ChatConversationsPage>(
    ChatKeys.conversations(me, filter),
    () => ChatApi.fetchConversations(filter: filter),
    context: context,
    enabled: enabled && me != null,
    staleDuration: StaleTime.short,
    toJson: (p) => p.toJson(),
    fromJson: ChatConversationsPage.fromJson,
  );
}

/// Badge and lists are stale (a push, the app back, a chat read).
void invalidateChatLists() => queryCache.invalidateAll([
  ChatKeys.unread(_me()),
  ChatKeys.conversationsAll,
]);

// ── Settings ─────────────────────────────────────────────────────────────

QueryResult<ChatSettings, ApiException> useChatSettings(
  BuildContext context, {
  bool enabled = true,
}) {
  final me = _me();
  return useApiQuery<ChatSettings>(
    ChatKeys.settings(me),
    ChatApi.fetchSettings,
    context: context,
    enabled: enabled && me != null,
    staleDuration: StaleTime.medium,
  );
}

/// Saves [next] (one switch changed). The cache shows it at once
/// (optimistic) and gets the old value back if the save fails.
Future<ChatSettings> saveChatSettings(ChatSettings next) async {
  final key = ChatKeys.settings(_me());
  final before = queryCache.entry<ChatSettings>(key)?.data;
  queryCache.setQueryData<ChatSettings, ApiException>(key, (_) => next);
  try {
    final saved = await ApiClient.guard(
      () => ChatApi.updateSettings(
        acceptChats: next.acceptChats,
        notify: next.notify,
      ),
    );
    queryCache.setQueryData<ChatSettings, ApiException>(key, (_) => saved);
    return saved;
  } on ApiException {
    if (before != null) {
      queryCache.setQueryData<ChatSettings, ApiException>(key, (_) => before);
    }
    rethrow;
  }
}

// ── Report ───────────────────────────────────────────────────────────────

MutationResult<void, ApiException, ChatReportInput> useChatReport({
  void Function()? onSuccess,
  void Function(ApiException error)? onError,
}) => useApiMutation<void, ChatReportInput>(
  ChatApi.report,
  onSuccess: (_, _) => onSuccess?.call(),
  onError: (e, _) => onError?.call(e),
);
