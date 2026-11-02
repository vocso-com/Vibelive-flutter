import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';

import '../../core/analytics/screen_tracker.dart';
import '../../core/network/api_exception.dart';
import '../../core/session/session_store.dart';
import '../../core/theme/vibe_colors.dart';
import '../api/listingflow/listing_queries.dart';
import '../authscreen/helper/deep_links.dart';
import '../banner/top_warn_bar.dart';
import '../callscreen/call/return_to_call_bar.dart';
import '../callscreen/history/history_view.dart';
import '../client/me/helper/me_data.dart';
import '../client/me/me_view.dart';
import '../client/me/widgets/host_availability_sheet.dart';
import '../component/c_toast.dart';
import '../component/exit_on_double_back.dart';
import '../component/status_bar_style.dart';
import '../component/vibe_background.dart';
import '../listingflow/profile/host_profile_sheet.dart';
import '../navbar/bottombar/bottom_navbar.dart';
import '../navbar/topbar/home_top_bar.dart';
import '../promo/popup/promo_popup_controller.dart';
import 'discover/discover_view.dart';
import 'helper/home_controller.dart';
import 'helper/own_host_refresh.dart';

/// Signed-in shell: Discover · History · Me with the floating navbar.
/// Tabs are built on first visit and kept alive (no refetch, no rebuild on
/// switch); hidden tabs stop their animations.
class HomeScreen extends HookWidget {
  const HomeScreen({
    super.key,
    this.initialTab = HomeTab.discover,
    this.topic,
    this.sheet,
  });

  final HomeTab initialTab;

  /// `?topic=` for Discover.
  final String? topic;

  /// `?sheet=availability` (the `online-status` link): a host gets the
  /// online / offline sheet over Home.
  final String? sheet;

  @override
  Widget build(BuildContext context) {
    final home = useMemoized(() => HomeController(initialTab));
    useEffect(() => home.dispose, [home]);
    useEffect(() {
      home.select(initialTab); // `/home?tab=` changed while mounted
      return null;
    }, [initialTab]);
    // Each tab is its own analytics screen (home_discover / _history / _me).
    useEffect(() {
      void track() =>
          ScreenTracker.setSubScreen('/home', 'home_${home.tab.value.name}');
      track();
      home.tab.addListener(track);
      return () {
        home.tab.removeListener(track);
        ScreenTracker.clearSubScreen('/home');
      };
    }, [home]);
    // Hosts: fresh review state for the top bar.
    useOwnHostRefresh(home);
    // The admin's app-open popup (first Home, and back after a while).
    usePromoPopups(context);
    // The `online-status` link: the host's availability sheet.
    useEffect(() {
      if (sheet != 'availability') return null;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!context.mounted) return;
        if (!MeData.of(SessionStore.instance.value).isExpert) return;
        unawaited(showHostAvailabilitySheet(context, source: 'deeplink'));
      });
      return null;
    }, [sheet]);

    // Parked links open now; hosts to open (links, referrer, campaigns)
    // arrive on DeepLinks.openUser.
    useEffect(() {
      final links = DeepLinks.instance;
      Future<void> openPending() async {
        final id = links.takeOpenUser();
        if (id == null) return;
        final known = peekHostLink(id);
        if (known != null) {
          await showHostProfile(context, known, source: 'deeplink');
          return;
        }
        try {
          final host = await ensureHostByLink(id);
          if (context.mounted) {
            await showHostProfile(context, host, source: 'deeplink');
          }
        } on ApiException catch (e) {
          CToast.error(e);
        }
      }

      links.markAppReady();
      links.openUser.addListener(openPending);
      openPending();
      return () => links.openUser.removeListener(openPending);
    }, const []);

    final c = context.colors;
    return ThemedStatusBar(
      // Android back: other tabs → Discover; on Discover press twice to exit.
      child: ExitOnDoubleBack(
        onBack: home.backToDiscover,
        child: Scaffold(
          backgroundColor: c.bg,
          // No field lives on Home itself: a keyboard opened by a sheet on
          // top must not re-layout the feed on every frame.
          resizeToAvoidBottomInset: false,
          // The feed scrolls under the floating navbar; toasts sit above it.
          extendBody: true,
          bottomNavigationBar: BottomNavbar(home: home),
          body: Stack(
            children: [
              const VibeBackground(),
              SafeArea(
                bottom: false,
                child: ValueListenableBuilder<HomeTab>(
                  valueListenable: home.tab,
                  builder: (_, tab, body) => Column(
                    children: [
                      // A minimized call (back on the call screen).
                      const ReturnToCallBar(),
                      if (tab == HomeTab.discover) DiscoverTopBar(home: home),
                      if (tab == HomeTab.me) MeTopBar(home: home),
                      if (tab == HomeTab.history) HistoryTopBar(home: home),
                      if (tab != HomeTab.history)
                        TopWarnBar(moderation: tab == HomeTab.discover),
                      Expanded(child: body!),
                    ],
                  ),
                  child: _Tabs(home: home, topic: topic),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Tabs extends StatefulWidget {
  const _Tabs({required this.home, this.topic});
  final HomeController home;
  final String? topic;

  @override
  State<_Tabs> createState() => _TabsState();
}

class _TabsState extends State<_Tabs> {
  final _built = <HomeTab>{};

  @override
  void initState() {
    super.initState();
    widget.home.tab.addListener(_onTab);
    _built.add(widget.home.tab.value);
  }

  void _onTab() => setState(() => _built.add(widget.home.tab.value));

  @override
  void dispose() {
    widget.home.tab.removeListener(_onTab);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final active = widget.home.tab.value;
    Widget slot(HomeTab tab, Widget Function() build) => TickerMode(
      enabled: tab == active,
      child: _built.contains(tab) ? build() : const SizedBox.shrink(),
    );
    return IndexedStack(
      index: active.index,
      children: [
        slot(
          HomeTab.discover,
          () => DiscoverView(home: widget.home, initialTopic: widget.topic),
        ),
        slot(HomeTab.history, () => HistoryView(home: widget.home)),
        slot(HomeTab.me, () => MeView(home: widget.home)),
      ],
    );
  }
}
