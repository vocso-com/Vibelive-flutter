import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../core/analytics/events/me_events.dart';
import '../../../core/query/query_client.dart';
import '../../../core/query/query_persist.dart';
import '../../../core/network/api_exception.dart';
import '../../api/client/client_keys.dart';
import '../../api/client/client_models.dart';
import '../../../core/session/session_store.dart';
import '../../../core/utils/scale.dart';
import '../../api/client/client_queries.dart';
import '../../api/hosthub/hosthub_keys.dart';
import '../../api/paymentscreen/payment_queries.dart';
import '../../api/resourcesscreen/resources_queries.dart';
import '../../component/c_toast.dart';
import '../../component/infinite_scroll.dart';
import '../../homescreen/helper/home_controller.dart';
import '../../hosthub/approved/host_status_section.dart';
import '../../navbar/bottombar/navbar_collapse.dart';
import 'helper/me_actions.dart';
import 'helper/me_data.dart';
import 'widgets/host_dashboard.dart';
import 'widgets/me_segmented.dart';
import 'widgets/me_skeleton.dart';
import 'widgets/profile_card.dart';
import 'widgets/settings_list.dart';

enum MeSection { dashboard, settings }

const _sections = [
  // RN Dashboard, now the host's whole hub: the Host Hub options and the
  // dashboard figures.
  MeSegment(MeSection.dashboard, LucideIcons.briefcase, 'hostflow:hub.segment'),
  MeSegment(
    MeSection.settings,
    LucideIcons.settings2,
    'client:me.section.settings',
  ),
];

/// The ME tab (RN `MeCard` + `HostDashboard`): the signed-in user's profile
/// card, then for hosts the availability modes and a Dashboard | Settings
/// switch, for clients the settings list.
///
/// Renders from [SessionStore] (always at hand, kept fresh by the persisted
/// "my profile" query); a skeleton only until the very first profile read.
class MeView extends HookWidget {
  const MeView({super.key, required this.home});
  final HomeController home;

  @override
  Widget build(BuildContext context) {
    final session = useValueListenable(SessionStore.instance);
    final data = useMemoized(() => MeData.of(session), [session]);
    // Hosts land on Dashboard: their numbers are why they open this tab.
    final section = useValueNotifier(MeSection.dashboard);

    useEffect(() {
      // Warm the RESOURCES sub-menu (RN refreshed menu pages on mount).
      ensureMenuPages().ignore();
      return null;
    }, const []);

    // RN `profile_open`: every visit to the tab (built on the first one).
    useEffect(() {
      void opened() {
        final s = SessionStore.instance.value;
        MeEvents.profileOpen(
          userId: s.userDocumentId ?? s.userId?.toString(),
          isExpert: s.isExpert,
        );
      }

      void onTab() {
        if (home.tab.value == HomeTab.me) opened();
      }

      if (home.tab.value == HomeTab.me) opened();
      home.tab.addListener(onTab);
      return () => home.tab.removeListener(onTab);
    }, [home]);

    // RN: 120 under the list inside the bottom safe area, which clears the
    // floating navbar. View padding: fixed while a keyboard is up.
    final bottom = 120.ms + MediaQuery.viewPaddingOf(context).bottom;
    final content = InfiniteScroll(
      padding: EdgeInsets.fromLTRB(10.ms, 0, 10.ms, bottom),
      hasMore: false,
      loadingMore: false,
      onLoadMore: _noop,
      onRefresh: _refresh,
      onScroll: NavbarCollapse.instance.track,
      slivers: [
        SliverToBoxAdapter(child: MeProfileCard(data: data)),
        if (data.isExpert) ...[
          // Moderation news and the review status until approved.
          SliverToBoxAdapter(
            child: HostStatusSection(
              host: data.host!,
              open: (route) {
                MeEvents.itemTapped(
                  item: MeActions.itemName(route),
                  section: 'host_status',
                );
                return MeActions.open(context, route);
              },
            ),
          ),
          SliverToBoxAdapter(
            child: Padding(
              padding: EdgeInsets.only(top: 16.ms),
              child: ValueListenableBuilder<MeSection>(
                valueListenable: section,
                builder: (_, s, _) => MeSegmented<MeSection>(
                  segments: _sections,
                  selected: s,
                  onSelect: (next) {
                    if (next != section.value) {
                      MeEvents.sectionSwitched(next.name);
                    }
                    section.value = next;
                  },
                ),
              ),
            ),
          ),
          // Keyed swap: only this sliver changes with the segment.
          ValueListenableBuilder<MeSection>(
            valueListenable: section,
            builder: (_, s, _) => s == MeSection.dashboard
                ? const MeHostDashboard(key: ValueKey(MeSection.dashboard))
                : MeSettingsList(
                    key: const ValueKey(MeSection.settings),
                    data: data,
                  ),
          ),
        ] else
          MeSettingsList(data: data),
      ],
    );
    return _FirstLoadGate(home: home, child: content);
  }

  static void _noop() {}

  /// Pull-to-refresh (RN `handleMeRefresh`): profile and wallet are awaited;
  /// host stats refresh in place, never driving the spinner.
  static Future<void> _refresh() async {
    final id = SessionStore.instance.value.userDocumentId;
    if (id == null) return;
    MeEvents.refreshed();
    queryCache.invalidateAll([HostHubKeys.stats(id)]);
    await Future.wait([
      ensureMyProfile(
        id,
        staleDuration: StaleTime.none,
      ).then<void>((_) {}, onError: (Object e) => CToast.error(e)),
      ensureWalletBalance().then<void>((_) {}, onError: (Object _) {}),
    ]);
  }
}

/// Owns the "my profile" query so its fetch states rebuild only this gate:
/// the content is passed in prebuilt and returned as the same instance.
class _FirstLoadGate extends HookWidget {
  const _FirstLoadGate({required this.home, required this.child});
  final HomeController home;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    // Only "first load or not" reaches this widget: query ticks (refetches,
    // stale marks) rebuild the tiny watcher, never the page.
    final firstLoad = useValueNotifier(_noProfileYet());

    // RN re-read ME every time the view switched to it (the tab stays alive).
    useEffect(() {
      void onTab() {
        if (home.tab.value == HomeTab.me) MeActions.revalidate();
      }

      home.tab.addListener(onTab);
      return () => home.tab.removeListener(onTab);
    }, [home]);

    return Stack(
      children: [
        _ProfileWatcher(firstLoad: firstLoad),
        ValueListenableBuilder<bool>(
          valueListenable: firstLoad,
          builder: (_, loading, _) => AnimatedSwitcher(
            duration: const Duration(milliseconds: 200),
            child: loading ? const MeSkeleton() : child,
          ),
        ),
      ],
    );
  }
}

/// Owns the "my profile" query; reports only whether the first read is
/// still pending. A failed first read falls back to the session copy (RN).
class _ProfileWatcher extends HookWidget {
  const _ProfileWatcher({required this.firstLoad});
  final ValueNotifier<bool> firstLoad;

  @override
  Widget build(BuildContext context) {
    final profile = useMyProfile(context);
    final loading = profile.data == null && profile.isLoading;
    useEffect(() {
      // Hooks run effects while building: report after the frame.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        firstLoad.value = loading;
      });
      return null;
    }, [loading]);
    return const SizedBox.shrink();
  }
}

/// No copy of "my profile" in memory or on disk yet (the skeleton shows).
bool _noProfileYet() {
  final id = SessionStore.instance.value.userDocumentId;
  if (id == null) return false;
  final key = ClientKeys.myProfile(id);
  return queryCache.getQueryData<UserWithExpert, ApiException>(key) == null &&
      QueryPersist.read<UserWithExpert>(key, UserWithExpert.fromJson) == null;
}
