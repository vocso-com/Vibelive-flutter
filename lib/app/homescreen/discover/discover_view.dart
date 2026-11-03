import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../core/analytics/analytics.dart';
import '../../../core/analytics/events/discover_events.dart';
import '../../../core/network/api_exception.dart';
import '../../../core/utils/scale.dart';
import '../../api/authscreen/interests_models.dart';
import '../../api/authscreen/interests_queries.dart';
import '../../api/homescreen/home_models.dart';
import '../../api/homescreen/home_queries.dart';
import '../../api/listingflow/filter_models.dart';
import '../../api/listingflow/listing_models.dart';
import '../../api/paymentscreen/payment_queries.dart';
import '../../component/c_button.dart';
import '../../component/c_image.dart';
import '../../component/c_state_view.dart';
import '../../component/infinite_scroll.dart';
import '../../component/skeleton.dart';
import '../../listingflow/profile/host_profile_sheet.dart';
import '../../listingflow/widgets/host_grid_card.dart';
import '../../navbar/bottombar/navbar_collapse.dart';
import '../helper/discover_layout.dart';
import '../helper/home_controller.dart';
import 'active_filters.dart';
import '../../api/host_status/host_status_models.dart';
import '../../api/host_status/host_status_queries.dart';
import '../../api/listingflow/host_index.dart';
import '../../api/promo_banner/promo_banner_models.dart';
import '../../api/promo_banner/promo_banner_queries.dart';
import '../../promo/promo_banner_carousel.dart';
import '../statuses/status_row.dart';
import 'talk_now_button.dart';
import 'topic_tabs.dart';

/// The Discover tab (RN `VibeScreen`): topic strip, active filters, and the
/// paged host grid with skeleton, pull-to-refresh and infinite loading.
class DiscoverView extends HookWidget {
  const DiscoverView({super.key, required this.home, this.initialTopic});

  final HomeController home;

  /// `?topic=` pins a topic tab right after Popular.
  final String? initialTopic;

  @override
  Widget build(BuildContext context) {
    final pinned = useMemoized(() => DiscoverTab.fromParam(initialTopic), [
      initialTopic,
    ]);
    final tab = useState(pinned ?? DiscoverTab.all);
    final feed = useDiscoverFeed(context);
    // Loaded with the feed (RN), so the first tap on Popular is instant.
    final popular = usePopularHosts(context);
    final form = useInterestForm(context);
    final filter = useValueListenable(home.filter);
    final scroll = useScrollController();

    final formTopics = useMemoized(() => _topicsOf(form.data), [form.data]);
    final topics = useMemoized(
      () => formTopics.isNotEmpty || form.isLoading
          ? formTopics
          : SupportTopic.fromHosts(feed.hosts),
      [formTopics, form.isLoading, feed.hosts],
    );
    final tabs = useMemoized(() {
      final out = <DiscoverTab>[DiscoverTab.all, DiscoverTab.popular];
      void add(DiscoverTab? t) {
        if (t != null &&
            !out.any((x) => sameText(x.label, t.label) && x.kind == t.kind)) {
          out.add(t);
        }
      }

      add(pinned);
      for (final t in topics) {
        add(DiscoverTab.topic(t.label));
      }
      add(tab.value); // the selected chip never disappears
      return out;
    }, [topics, tab.value, pinned]);

    final hosts = useDiscoverHosts(
      feed: feed,
      popular: popular.data,
      tab: tab.value,
      filter: filter,
      topics: topics,
    );
    final plain = tab.value.isAll && !filter.isActive;
    // The status row follows the tab and filters: everyone on plain "All";
    // otherwise a host on the list below, or one the app already knows that
    // the tab and filters would let through (the list loads in pages).
    final listed = {for (final h in hosts) ?h.expertProfileDocumentId};
    final selectedTab = tab.value;
    bool statusInclude(StatusHost s) {
      if (plain || listed.contains(s.expertDocumentId)) return true;
      if (selectedTab.isPopular) return false;
      final known = HostIndex.find(
        expertDocumentId: s.expertDocumentId,
        userDocumentId: s.userDocumentId,
      )?.card;
      return known != null &&
          selectedTab.matches(known, topics) &&
          filter.matches(known);
    }

    // Rows already on screen stay the same objects when a page lands, and
    // so do their widgets (below): only new or changed rows build.
    final lastRows = useRef(const <DiscoverRow>[]);
    final plan = useMemoized(
      () => DiscoverLayout.plan(
        hosts,
        holdLeftoverFeatured: feed.hasMore && plain,
        previous: lastRows.value,
      ),
      [hosts, feed.hasMore, plain],
    );
    final rows = lastRows.value = plan.rows;
    // Row widgets are reused as-is; their sizes are scaled to the window.
    final rowWidgets = useMemoized(Expando<Widget>.new, [
      MediaQuery.sizeOf(context),
    ]);
    final rowIndex = useMemoized(
      () => {for (final (i, r) in rows.indexed) r.key: i},
      [rows],
    );

    // Analytics for a card tap: the cached row widgets call one stable
    // callback that reads the latest feed state.
    final tapState = useRef((hosts: hosts, tab: tab.value, filter: filter))
      ..value = (hosts: hosts, tab: tab.value, filter: filter);
    final onCard = useMemoized(
      () =>
          (
            BuildContext ctx,
            HostCard h, {
            required String action,
            required bool featured,
          }) {
            final s = tapState.value;
            DiscoverEvents.hostCardTapped(
              hostId: h.expertProfileDocumentId ?? h.documentId ?? '${h.id}',
              action: action,
              position: s.hosts.indexOf(h),
              tab: s.tab.kind.name,
              topic: s.tab.isTopic ? s.tab.label : null,
              isOnline: h.isAvailable,
              featured: featured,
              filtered: s.filter.isActive,
              audioRate: h.aPrice > 0 ? h.aPrice : null,
            );
            showHostProfile(ctx, h, source: 'discover');
          },
    );

    // Each page's card photos load and decode the moment the page lands —
    // with loadAhead below, about two screens before its cards scroll in —
    // so they paint on their first frame instead of fading in from a box.
    final listWidth = useRef<double?>(null);
    final warmed = useRef(<String>{});
    useEffect(() {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        final width = listWidth.value;
        if (context.mounted && width != null) {
          _warmCards(context, rows, width, warmed.value);
        }
      });
      return null;
    }, [rows]);

    // Discover tapped again: scroll to the top, or refresh when already there.
    final latestFeed = useRef(feed)..value = feed;
    useEffect(() {
      void onReselect() {
        if (!scroll.hasClients) return;
        if (scroll.offset <= 10) {
          DiscoverEvents.feedRefreshed(
            trigger: 'tab_reselect',
            tab: tab.value.kind.name,
          );
          latestFeed.value.refresh();
        } else {
          scroll.animateTo(
            0,
            duration: const Duration(milliseconds: 350),
            curve: Curves.easeOutCubic,
          );
        }
      }

      home.discoverReselect.addListener(onReselect);
      return () => home.discoverReselect.removeListener(onReselect);
    }, [home]);

    void selectTab(DiscoverTab next) {
      if (TopicTabs.same(next, tab.value)) return;
      tab.value = next;
      if (scroll.hasClients) scroll.jumpTo(0);
    }

    // A `?topic=` link while Home is open selects that topic (RN).
    useEffect(() {
      final next = pinned;
      if (next != null && !TopicTabs.same(next, tab.value)) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (context.mounted) selectTab(next);
        });
      }
      return null;
    }, [pinned]);

    final isPopular = tab.value.isPopular;
    // The next page's shape, as skeleton. Only on the plain feed: a
    // filtered view can't tell how many of the next cards will match.
    final next = plain && !isPopular && feed.isLoadingMore
        ? plan.next(feed.incoming ?? 0)
        : null;
    final loading =
        hosts.isEmpty &&
        (isPopular
            ? popular.isLoading
            : (feed.query.data == null || (feed.query.isFetching && !plain))) &&
        !(isPopular
            ? popular.isError
            : feed.query.isError && feed.query.data == null);
    final error = isPopular
        ? (popular.isError && popular.data == null ? popular.error : null)
        : (feed.query.isError && feed.query.data == null
              ? feed.query.error
              : null);
    // Pull-to-refresh also reloads the wallet balance in the header (RN).
    Future<void> refresh({String trigger = 'pull'}) async {
      DiscoverEvents.feedRefreshed(trigger: trigger, tab: tab.value.kind.name);
      invalidateWalletQueries();
      invalidateStatusFeed();
      invalidatePromoBanners();
      isPopular ? await popular.refetch() : await feed.refresh();
    }

    // Analytics: an empty tab / a load error, once per state change.
    final emptyShown = !loading && error == null && rows.isEmpty;
    useEffect(() {
      if (emptyShown) {
        DiscoverEvents.feedEmpty(
          tab: tab.value.kind.name,
          topic: tab.value.isTopic ? tab.value.label : null,
          filtered: filter.isActive,
        );
      }
      return null;
    }, [emptyShown, tab.value.kind, tab.value.label, filter]);
    useEffect(() {
      if (error != null) {
        DiscoverEvents.feedLoadError(
          tab: tab.value.kind.name,
          error: Analytics.errorCode(error),
        );
      }
      return null;
    }, [error != null, tab.value.kind]);

    // The floating navbar's full height (its safe-area gap included). Not
    // viewPadding: a Scaffold with a bottom bar strips the bottom inset from
    // its body, so here viewPadding is ~0 on phones with a gesture bar, and
    // anything placed by it sinks under the navbar. With `extendBody` the
    // body's padding.bottom is exactly the bar's height.
    final navbar = MediaQuery.paddingOf(context).bottom;
    // Talk Now floats this far above the navbar (its pill is 64 tall).
    final dockGap = 12.ms;
    // RN: 140 above the bottom safe area, clear of the floating navbar; and
    // the last cards scroll clear of the open Talk Now pill too.
    final padding = EdgeInsets.fromLTRB(
      10.ms,
      10.ms,
      10.ms,
      math.max(
        140.ms + MediaQuery.viewPaddingOf(context).bottom,
        navbar + dockGap + 64.ms + 12.ms,
      ),
    );
    // Banners, topics and active filters scroll with the feed (mockup);
    // while the first page loads they sit above its skeleton.
    final header = Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // The admin's promo banners (admin → Banners & popups), if any are
        // live. They replace the old built-in hero (its look is the
        // `spotlight` template).
        PromoBannerCarousel(
          placement: PromoPlacement.home,
          padding: EdgeInsets.fromLTRB(6.ms, 4.ms, 6.ms, 6.ms),
        ),
        TopicTabs(
          tabs: tabs,
          selected: tab.value,
          loading: form.isLoading && formTopics.isEmpty,
          onSelect: (next) {
            if (!TopicTabs.same(next, tab.value)) {
              DiscoverEvents.topicSelected(
                kind: next.kind.name,
                topic: next.isTopic ? next.label : null,
                position: tabs.indexOf(next),
              );
            }
            selectTab(next);
          },
        ),
        if (filter.isActive)
          ActiveFilters(
            filter: filter,
            source: 'discover',
            onChanged: (f) => home.filter.value = f,
          ),
        // Hosts' statuses as circles (a host's own "+" first), narrowed to
        // the selected tab and filters like the list below them.
        StatusRow(include: statusInclude),
      ],
    );
    return Stack(
      children: [
        Column(
          children: [
            Expanded(
              // One scroll view in every state: swapping the tree when the
              // first page landed tore down a Scrollable mid-drag
              // (`_hold == null`).
              child: LayoutBuilder(
                builder: (context, box) {
                  listWidth.value = box.maxWidth;
                  return InfiniteScroll(
                    controller: scroll,
                    padding: padding,
                    hasMore: !loading && !isPopular && feed.hasMore,
                    loadingMore: feed.isLoadingMore,
                    loadMoreFailed: feed.query.isFetchNextPageError,
                    onLoadMore: () {
                      DiscoverEvents.feedLoadMore(
                        page: (feed.query.data?.pages.length ?? 0) + 1,
                        loaded: feed.hosts.length,
                      );
                      feed.loadMore();
                    },
                    // A page is ~8 rows (~2.5 screens): ask while that much is
                    // still below, so it lands before the user gets there.
                    loadAhead: 2.5,
                    onRefresh: () => refresh(),
                    endLabel: loading || rows.isEmpty ? null : 'home:feed.end',
                    onScroll: NavbarCollapse.instance.track,
                    // Filtered view: the count is unknown, so one plain pair
                    // row (never a spinner in a list).
                    loadingBuilder: next == null
                        ? (_) => const Shimmer(child: _SkeletonRow())
                        : (_) => _MoreSkeleton(next),
                    slivers: [
                      SliverToBoxAdapter(child: header),
                      if (loading)
                        const SliverToBoxAdapter(child: _FeedSkeleton())
                      else if (error != null)
                        SliverFillRemaining(
                          hasScrollBody: false,
                          child: _LoadError(
                            error: error,
                            onRetry: () => refresh(trigger: 'retry'),
                          ),
                        )
                      else if (rows.isEmpty)
                        SliverFillRemaining(
                          hasScrollBody: false,
                          child: CStateView.empty(
                            title: tab.value.emptyKey,
                            message: null,
                          ),
                        )
                      else
                        SliverVariedExtentList.builder(
                          itemCount: rows.length,
                          itemExtentBuilder: (i, _) =>
                              i < rows.length ? rows[i].height + 12.ms : null,
                          findChildIndexCallback: (key) =>
                              key is ValueKey<String>
                              ? rowIndex[key.value]
                              : null,
                          itemBuilder: (context, i) {
                            final row = rows[i];
                            // The half row the next card lands in: its empty
                            // slot shows that card's skeleton meanwhile.
                            if ((next?.fillsSlot ?? false) &&
                                i == rows.length - 1) {
                              return _Row(
                                row,
                                key: ValueKey(row.key),
                                pendingSlot: true,
                                onCard: onCard,
                              );
                            }
                            return rowWidgets[row] ??= _Row(
                              row,
                              key: ValueKey(row.key),
                              onCard: onCard,
                            );
                          },
                        ),
                    ],
                  );
                },
              ),
            ),
          ],
        ),
        // Talk Now floats just above the navbar, on Discover only: a pill on
        // arrival, then a round call button at the right.
        Positioned(
          left: 16.ms,
          right: 16.ms,
          bottom: navbar + dockGap,
          child: const TalkNowButton(),
        ),
      ],
    );
  }

  /// Precaches the card photos (placeholder first) of hosts not done yet, at
  /// the size each card decodes them: the list's side padding, the 12 gap
  /// of a pair, and [HostGridCard]'s 1 px border on each side.
  static void _warmCards(
    BuildContext context,
    List<DiscoverRow> rows,
    double listWidth,
    Set<String> done,
  ) {
    final rowWidth = listWidth - 20.ms;
    for (final row in rows) {
      final card = row.featured ? rowWidth : (rowWidth - 12.ms) / 2;
      final imageWidth = card - 2;
      for (final h in row.hosts) {
        final url = h.cardImage ?? (h.images.isEmpty ? null : h.images.first);
        if (url == null || !done.add(url)) continue;
        unawaited(CImage.precache(context, h.cardPlaceholder, imageWidth));
        unawaited(CImage.precache(context, url, imageWidth));
      }
    }
  }

  static List<SupportTopic> _topicsOf(InterestForm? form) => [
    for (final o
        in form?.question(SupportTopicKey.question)?.options ??
            const <InterestOption>[])
      if (!o.isDeprecated && o.value.isNotEmpty)
        SupportTopic(
          label: o.label.isEmpty ? o.value : o.label,
          value: o.value,
        ),
  ];
}

/// A card tap: logs it, then opens the profile sheet.
typedef _CardTap =
    void Function(
      BuildContext context,
      HostCard host, {
      required String action,
      required bool featured,
    });

class _Row extends StatelessWidget {
  const _Row(
    this.row, {
    super.key,
    this.pendingSlot = false,
    required this.onCard,
  });
  final DiscoverRow row;

  /// A half row whose second card is loading: a skeleton in its place.
  final bool pendingSlot;
  final _CardTap onCard;

  @override
  Widget build(BuildContext context) {
    void open(HostCard h) =>
        onCard(context, h, action: 'open', featured: row.featured);
    // Call Now: the same profile sheet as a tap, where the call starts.
    void call(HostCard h) =>
        onCard(context, h, action: 'call', featured: row.featured);
    final gap = SizedBox(width: 12.ms);
    return Padding(
      padding: EdgeInsets.only(bottom: 12.ms),
      child: row.featured
          ? HostGridCard(
              host: row.hosts.first,
              featured: true,
              onTap: open,
              onCall: call,
            )
          : Row(
              children: [
                Expanded(
                  child: HostGridCard(
                    host: row.hosts.first,
                    onTap: open,
                    onCall: call,
                  ),
                ),
                gap,
                Expanded(
                  child: row.hosts.length > 1
                      ? HostGridCard(
                          host: row.hosts[1],
                          onTap: open,
                          onCall: call,
                        )
                      : pendingSlot
                      ? const Shimmer(child: HostGridCardSkeleton())
                      : const SizedBox.shrink(),
                ),
              ],
            ),
    );
  }
}

/// RN copy: "Couldn't load hosts. Check your connection." + TRY AGAIN.
class _LoadError extends StatelessWidget {
  const _LoadError({required this.error, required this.onRetry});
  final ApiException error;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final offline =
        error.type == ApiErrorType.network ||
        error.type == ApiErrorType.timeout;
    return CStateView(
      title: 'home:feed.load_error',
      icon: offline ? LucideIcons.wifiOff : LucideIcons.circleAlert,
      actionLabel: 'home:feed.try_again',
      actionVariant: CButtonVariant.primary,
      onAction: onRetry,
    );
  }
}

/// A skeleton feed row, built like [_Row]: the same height, 12 gap under
/// it, and the same card widths (a lone regular card keeps half the row).
class _SkeletonRow extends StatelessWidget {
  const _SkeletonRow({this.featured = false, this.cards = 2});

  final bool featured;

  /// Regular rows: 1 or 2 cards.
  final int cards;

  @override
  Widget build(BuildContext context) => Padding(
    padding: EdgeInsets.only(bottom: 12.ms),
    child: SizedBox(
      height: DiscoverRow.heightOf(featured: featured),
      child: featured
          ? const HostGridCardSkeleton(featured: true)
          : Row(
              children: [
                const Expanded(child: HostGridCardSkeleton()),
                SizedBox(width: 12.ms),
                Expanded(
                  child: cards > 1
                      ? const HostGridCardSkeleton()
                      : const SizedBox.shrink(),
                ),
              ],
            ),
    ),
  );
}

/// First-load skeleton: the feed's own pattern (a featured card, then
/// pairs), as many rows as fill the viewport.
class _FeedSkeleton extends StatelessWidget {
  const _FeedSkeleton();

  /// A featured row and three pairs: more than a screen below the hero.
  @override
  Widget build(BuildContext context) => const Shimmer(
    child: Column(
      children: [
        _SkeletonRow(featured: true),
        _SkeletonRow(),
        _SkeletonRow(),
        _SkeletonRow(),
      ],
    ),
  );
}

/// Load-more footer: the next row's shape, as a skeleton (nothing when the
/// next card only fills the last row's empty slot).
class _MoreSkeleton extends StatelessWidget {
  const _MoreSkeleton(this.next);
  final DiscoverNext next;

  @override
  Widget build(BuildContext context) => next.cards == 0
      ? const SizedBox.shrink()
      : Shimmer(
          child: _SkeletonRow(featured: next.featured, cards: next.cards),
        );
}
