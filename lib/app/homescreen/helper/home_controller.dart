import 'package:flutter/foundation.dart';

import '../../api/listingflow/filter_models.dart';
import '../../navbar/bottombar/navbar_collapse.dart';

enum HomeTab {
  discover,
  chats,
  history,
  me;

  /// `?tab=` of `/home` (RN used DISCOVER / LOGS / ME).
  static HomeTab fromParam(String? value) => switch (value?.toLowerCase()) {
    'chats' || 'chat' || 'messages' => HomeTab.chats,
    'history' || 'logs' || 'explore' => HomeTab.history,
    'me' || 'profile' => HomeTab.me,
    _ => HomeTab.discover,
  };
}

/// Home's shared state, as small notifiers so each part rebuilds alone:
/// the navbar listens to [tab], the feed to [filter] and [discoverReselect].
class HomeController {
  HomeController([HomeTab initial = HomeTab.discover])
    : tab = ValueNotifier(initial);

  final ValueNotifier<HomeTab> tab;

  /// Language / topic filter from the filter sheet.
  final filter = ValueNotifier(HostFilter.none);

  /// Bumped when Discover is tapped while already shown: the feed scrolls to
  /// the top, or refreshes when it is already there (RN behaviour).
  final discoverReselect = ValueNotifier(0);

  void select(HomeTab next) {
    if (next == tab.value) {
      if (next == HomeTab.discover) discoverReselect.value++;
      return;
    }
    NavbarCollapse.instance.reset();
    tab.value = next;
  }

  /// Android back on History / Me returns to Discover (true = handled).
  bool backToDiscover() {
    if (tab.value == HomeTab.discover) return false;
    select(HomeTab.discover);
    return true;
  }

  void dispose() {
    tab.dispose();
    filter.dispose();
    discoverReselect.dispose();
  }
}
