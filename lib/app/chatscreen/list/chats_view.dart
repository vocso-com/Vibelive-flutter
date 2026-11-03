import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../core/analytics/events/chat_events.dart';
import '../../../core/analytics/events/discover_events.dart';
import '../../../core/i18n/i18n.dart';
import '../../../core/network/api_exception.dart';
import '../../../core/router/app_router.dart';
import '../../../core/session/session_store.dart';
import '../../../core/utils/scale.dart';
import '../../api/chat/chat_api.dart';
import '../../api/chat/chat_models.dart';
import '../../api/chat/chat_queries.dart';
import '../../component/c_state_view.dart';
import '../../component/c_text.dart';
import '../../component/c_toast.dart';
import '../../component/infinite_scroll.dart';
import '../../component/pressable.dart';
import '../../component/skeleton.dart';
import '../../homescreen/helper/home_controller.dart';
import '../../navbar/bottombar/navbar_collapse.dart';
import '../../navbar/topbar/top_bar_button.dart';
import '../components/chat_palette.dart';
import '../components/chat_secure_zone.dart';
import 'conversation_row.dart';

const _filters = ['all', 'unread', 'online'];

/// The Chats tab: filters (all / unread / online) and the conversations,
/// newest first. Page 1 renders from disk, refreshes when the tab shows
/// again, on chat pushes and when the app comes back; older pages load on
/// scroll.
class ChatsView extends HookWidget {
  const ChatsView({super.key, required this.home});

  final HomeController home;

  @override
  Widget build(BuildContext context) {
    final config = useChatConfigValue(context);
    final filter = useState('all');
    final first = useChatConversations(
      context,
      filter: filter.value,
      enabled: config.enabled,
    );
    final tab = useValueListenable(home.tab);
    // Chat switched off while this tab shows: back to Discover (the tab
    // itself leaves the dock).
    final wasOn = useRef(ChatAvailability.instance.value);
    useEffect(() {
      void check() {
        final on = ChatAvailability.instance.value;
        if (wasOn.value && !on && home.tab.value == HomeTab.chats) {
          home.select(HomeTab.discover);
        }
        wasOn.value = on;
      }

      ChatAvailability.instance.addListener(check);
      return () => ChatAvailability.instance.removeListener(check);
    }, [home]);
    final older = useState<List<ChatConversation>>(const []);
    final cursor = useState<String?>(null);
    final ended = useState(false);
    final loadingMore = useState(false);
    final moreFailed = useState(false);

    // A new filter starts over.
    useEffect(() {
      older.value = const [];
      cursor.value = null;
      ended.value = false;
      moreFailed.value = false;
      return null;
    }, [filter.value]);

    // Back on this tab: a quiet refresh.
    final refetch = useRef(first.refetch)..value = first.refetch;
    useEffect(() {
      if (tab == HomeTab.chats && first.data != null) {
        unawaited(
          Future.sync(refetch.value).then((_) {}, onError: (Object _) {}),
        );
      }
      return null;
    }, [tab]);

    final page = first.data;
    final items = useMemoized(() {
      final seen = <String>{};
      return [
        for (final c in [...?page?.items, ...older.value])
          if (seen.add(c.id)) c,
      ];
    }, [page, older.value]);
    final next = cursor.value ?? page?.next ?? _lastCursor(page?.items);
    final hasMore =
        page != null &&
        !ended.value &&
        next != null &&
        (cursor.value != null ||
            page.next != null ||
            page.items.length >= ChatApi.listPageSize);

    Future<void> loadMore() async {
      if (loadingMore.value || !hasMore) return;
      loadingMore.value = true;
      moreFailed.value = false;
      try {
        final more = await ChatApi.fetchConversations(
          filter: filter.value,
          before: next,
        );
        if (!context.mounted) return;
        older.value = [...older.value, ...more.items];
        final after =
            more.next ??
            (more.items.length >= ChatApi.listPageSize
                ? _lastCursor(more.items)
                : null);
        cursor.value = after;
        ended.value = after == null;
      } on ApiException {
        if (context.mounted) moreFailed.value = true;
      } finally {
        if (context.mounted) loadingMore.value = false;
      }
    }

    Future<void> refresh() async {
      older.value = const [];
      cursor.value = null;
      ended.value = false;
      try {
        await first.refetch();
        invalidateChatLists();
      } on ApiException catch (e) {
        CToast.error(e);
      }
    }

    final me = SessionStore.instance.value.userId?.toString();
    void open(ChatConversation c) {
      ChatEvents.conversationTapped(peerId: c.peer.userId, unread: c.unread);
      unawaited(context.push(AppRoutes.chatWith(c.peer.userId)));
    }

    final bottom = 120.ms + MediaQuery.viewPaddingOf(context).bottom;
    final Widget body;
    if (!config.enabled) {
      body = const CStateView(
        title: 'chat:notice.disabled',
        icon: LucideIcons.messageCircleOff,
      );
    } else if (page == null && first.isError) {
      body = CStateView.error(
        context,
        first.error!,
        onRetry: () => first.refetch(),
      );
    } else if (page == null) {
      body = const _ListSkeleton();
    } else {
      body = InfiniteScroll(
        padding: EdgeInsets.only(bottom: bottom),
        hasMore: hasMore,
        loadingMore: loadingMore.value,
        loadMoreFailed: moreFailed.value,
        onLoadMore: () => unawaited(loadMore()),
        onRefresh: refresh,
        onScroll: NavbarCollapse.instance.track,
        slivers: [
          SliverToBoxAdapter(
            child: _Filters(
              selected: filter.value,
              onSelect: (f) {
                if (f == filter.value) return;
                ChatEvents.listFilter(f);
                filter.value = f;
              },
            ),
          ),
          if (items.isEmpty)
            SliverFillRemaining(
              hasScrollBody: false,
              child: _Empty(filter: filter.value, home: home),
            )
          else
            SliverFixedExtentList.builder(
              itemExtent: ConversationRow.extent,
              itemCount: items.length,
              itemBuilder: (_, i) => ConversationRow(
                key: ValueKey(items[i].id),
                conversation: items[i],
                me: me,
                onTap: open,
              ),
            ),
        ],
      );
    }
    return ChatSecureZone(
      active:
          config.enabled && config.screenshotProtection && tab == HomeTab.chats,
      child: body,
    );
  }

  static String? _lastCursor(List<ChatConversation>? items) {
    final at = items == null || items.isEmpty ? null : items.last.updatedAt;
    return at?.toUtc().toIso8601String();
  }
}

/// CHATS header, built like the History one: back to Discover, the title.
class ChatsTopBar extends StatelessWidget {
  const ChatsTopBar({super.key, required this.home});

  final HomeController home;

  @override
  Widget build(BuildContext context) {
    final p = ChatPalette.of(context);
    return Padding(
      padding: EdgeInsets.fromLTRB(20.ms, 8.ms, 20.ms, 10.ms),
      child: Row(
        children: [
          TopBarButton(
            icon: LucideIcons.chevronLeft,
            semanticLabel: context.t('actions.back'),
            onPressed: () {
              DiscoverEvents.topBarTapped(button: 'back', tab: 'chats');
              home.select(HomeTab.discover);
            },
          ),
          Expanded(
            child: CText(
              'chat:list.title',
              size: 22,
              weight: FontWeight.w800,
              color: p.text,
              align: TextAlign.center,
              maxLines: 1,
            ),
          ),
          SizedBox(width: 44.ms),
        ],
      ),
    );
  }
}

class _Filters extends StatelessWidget {
  const _Filters({required this.selected, required this.onSelect});

  final String selected;
  final ValueChanged<String> onSelect;

  @override
  Widget build(BuildContext context) {
    final p = ChatPalette.of(context);
    return Padding(
      padding: EdgeInsets.fromLTRB(20.ms, 2.ms, 20.ms, 10.ms),
      child: Row(
        children: [
          for (final f in _filters) ...[
            Pressable(
              key: ValueKey('chat-filter-$f'),
              onPressed: () => onSelect(f),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 160),
                height: 34.ms,
                padding: EdgeInsets.symmetric(horizontal: 14.ms),
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: f == selected ? p.accent : p.chip,
                  borderRadius: BorderRadius.circular(999),
                ),
                child: CText(
                  'chat:list.filter.$f',
                  size: 13,
                  weight: FontWeight.w800,
                  color: f == selected ? p.onAccent : p.text,
                  maxLines: 1,
                ),
              ),
            ),
            SizedBox(width: 8.ms),
          ],
        ],
      ),
    );
  }
}

class _Empty extends StatelessWidget {
  const _Empty({required this.filter, required this.home});

  final String filter;
  final HomeController home;

  @override
  Widget build(BuildContext context) => CStateView(
    title: switch (filter) {
      'unread' => 'chat:list.empty_unread',
      'online' => 'chat:list.empty_online',
      _ => 'chat:list.empty_title',
    },
    message: filter == 'all' ? 'chat:list.empty_message' : null,
    icon: LucideIcons.messagesSquare,
    actionLabel: filter == 'all' ? 'chat:list.discover' : null,
    onAction: filter == 'all' ? () => home.select(HomeTab.discover) : null,
  );
}

class _ListSkeleton extends StatelessWidget {
  const _ListSkeleton();

  @override
  Widget build(BuildContext context) => Shimmer(
    child: ListView(
      physics: const NeverScrollableScrollPhysics(),
      padding: EdgeInsets.only(top: 50.ms),
      children: [
        for (var i = 0; i < 7; i++)
          SizedBox(
            height: ConversationRow.extent,
            child: Padding(
              padding: EdgeInsets.symmetric(horizontal: 20.ms),
              child: Row(
                children: [
                  SkeletonBox(width: 52.ms, height: 52.ms, circle: true),
                  SizedBox(width: 12.ms),
                  Expanded(child: SkeletonLines(lines: 2, height: 11.ms)),
                ],
              ),
            ),
          ),
      ],
    ),
  );
}
