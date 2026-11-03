import '../analytics.dart';

/// Home shell, Discover feed, search, filter, the host profile sheet and
/// the banners (Firebase + Meta). Catalog: docs/analytics_events.md.
///
/// `host_id` is the expert-profile documentId when known (the reviews /
/// favourites key), else the card's documentId or numeric id.
abstract final class DiscoverEvents {
  // ── Home shell ─────────────────────────────────────────────────────────

  /// A bottom-dock tab tapped; [reselect]: it was already showing.
  static void navTabTapped({required String tab, required bool reselect}) =>
      Analytics.log('nav_tab_tapped', {'tab': tab, 'reselect': reselect});

  /// A top-bar button: `search`, `filter`, `wallet`, `back`, `me_menu`.
  static void topBarTapped({required String button, required String tab}) =>
      Analytics.log('top_bar_button_tapped', {'button': button, 'tab': tab});

  // ── Discover feed ──────────────────────────────────────────────────────

  /// A topic chip: `all`, `popular` or a topic ([topic] = its label).
  static void topicSelected({
    required String kind,
    String? topic,
    int? position,
  }) => Analytics.log('discover_topic_selected', {
    'kind': kind,
    'topic': topic,
    'position': position,
  });

  /// "Talk now" (instant call to any available host).
  static void talkNowTapped({required bool blockedByCall}) =>
      Analytics.log('talk_now_tapped', {'blocked_by_call': blockedByCall});

  /// The folded Talk Now circle tapped open (back to the pill with prices).
  static void talkNowOpened() => Analytics.log('talk_now_opened');

  /// A host's circle in the Home status row: [position] in the row, [seen]
  /// whether all of theirs were already watched.
  static void statusOpened({
    required String hostId,
    required int position,
    required bool seen,
  }) => Analytics.log('status_opened', {
    'host_id': hostId,
    'position': position,
    'seen': seen,
  });

  /// Visit profile, under a status.
  static void statusVisitProfile({required String hostId}) =>
      Analytics.log('status_visit_profile', {'host_id': hostId});

  /// The video intro started playing by itself on a profile (first slide).
  static void videoIntroAutoplayed({required String hostId}) =>
      Analytics.log('video_intro_autoplay', {'host_id': hostId});

  /// Sound on / off on the profile's video intro.
  static void videoIntroMuteToggled({
    required String hostId,
    required bool muted,
  }) => Analytics.log('video_intro_mute', {
    'host_id': hostId,
    'muted': muted,
  });

  /// Call, under a status (then the profile's usual call checks).
  static void statusCallTapped({required String hostId}) =>
      Analytics.log('status_call_tapped', {'host_id': hostId});

  /// A host taps their own circle (or its "+") to record a status.
  static void statusAddTapped({required bool hasLive}) =>
      Analytics.log('status_add_tapped', {'has_live': hasLive});

  /// A host card in the feed: [action] `open` (card) or `call` (Call Now).
  static void hostCardTapped({
    required String hostId,
    required String action,
    required int position,
    required String tab,
    String? topic,
    required bool isOnline,
    required bool featured,
    required bool filtered,
    double? audioRate,
  }) => Analytics.log('host_card_tapped', {
    'host_id': hostId,
    'action': action,
    'position': position,
    'tab': tab,
    'topic': topic,
    'is_online': isOnline,
    'featured': featured,
    'filtered': filtered,
    'audio_rate': audioRate,
    'source': 'discover',
  });

  /// Pull-to-refresh / Discover re-tapped at the top / "Try again".
  static void feedRefreshed({required String trigger, required String tab}) =>
      Analytics.log('discover_refreshed', {'trigger': trigger, 'tab': tab});

  /// The next page of the feed was asked for ([page]: pages loaded so far).
  static void feedLoadMore({required int page, required int loaded}) =>
      Analytics.log('discover_load_more', {'page': page, 'loaded': loaded});

  /// Nothing to show for this tab / filter.
  static void feedEmpty({
    required String tab,
    String? topic,
    required bool filtered,
  }) => Analytics.log('discover_empty_shown', {
    'tab': tab,
    'topic': topic,
    'filtered': filtered,
  });

  /// The feed could not load.
  static void feedLoadError({required String tab, required String error}) =>
      Analytics.log('discover_load_error', {'tab': tab, 'error': error});

  // ── Filter ─────────────────────────────────────────────────────────────

  static void filterOpened({
    required String source,
    required int activeCount,
  }) => Analytics.log('filter_opened', {
    'source': source,
    'active_count': activeCount,
  });

  /// "Apply" with [languagesCount] languages and an optional topic.
  static void filterApplied({
    required String source,
    required int languagesCount,
    required List<String> languages,
    String? topic,
  }) => Analytics.log('filter_applied', {
    'source': source,
    'languages_count': languagesCount,
    'languages': languages.join(','),
    'has_topic': topic != null && topic.isNotEmpty,
    'topic': topic,
  });

  /// "Clear all" (and closed without applying anything else).
  static void filterCleared({required String source}) =>
      Analytics.log('filter_cleared', {'source': source});

  /// Closed without applying.
  static void filterDismissed({required String source}) =>
      Analytics.log('filter_dismissed', {'source': source});

  /// An active-filter chip's ✕: [kind] `language` / `topic`.
  static void filterChipRemoved({
    required String source,
    required String kind,
    String? value,
  }) => Analytics.log('filter_chip_removed', {
    'source': source,
    'kind': kind,
    'value': value,
  });

  // ── Search ─────────────────────────────────────────────────────────────

  /// RN `search` (also Firebase's recommended name), once per settled
  /// query, plus Meta's standard `fb_mobile_search`.
  static void search({
    required String term,
    required int resultsCount,
    required int categoriesCount,
    required String trigger,
  }) {
    Analytics.log('search', {
      'search_term': term,
      'results_count': resultsCount,
      'categories_count': categoriesCount,
      'trigger': trigger,
    });
    Analytics.meta('fb_mobile_search', {
      'fb_search_string': term,
      'fb_content_type': 'host',
      'fb_success': resultsCount > 0 ? 1 : 0,
    });
  }

  static void searchNoResults({required String term}) =>
      Analytics.log('search_no_results', {'search_term': term});

  static void searchFailed({required String term, required String error}) =>
      Analytics.log('search_failed', {'search_term': term, 'error': error});

  /// A host row in the results ([position] among the shown hosts).
  static void searchResultTapped({
    required String hostId,
    required int position,
    required int resultsCount,
    required bool filtered,
  }) => Analytics.log('search_result_tapped', {
    'host_id': hostId,
    'position': position,
    'results_count': resultsCount,
    'filtered': filtered,
  });

  /// A category / category-by-location row: [kind] `category` / `location`.
  static void searchCategoryTapped({
    required String kind,
    required String category,
    required int position,
  }) => Analytics.log('search_category_tapped', {
    'kind': kind,
    'category': category,
    'position': position,
  });

  static void searchCleared() => Analytics.log('search_cleared');

  /// A search result's full profile could not be read.
  static void searchOpenFailed({required String error}) =>
      Analytics.log('search_open_failed', {'error': error});

  // ── Host profile sheet ─────────────────────────────────────────────────

  /// RN `view_expert` once per profile open, plus Meta's standard
  /// `fb_mobile_content_view` (valueToSum: the per-minute audio rate).
  static void viewExpert({
    required String expertId,
    required String source,
    String? category,
    double? price,
    double? videoPrice,
    required bool isOnline,
    double? rating,
    required bool verified,
    required bool isOwn,
  }) {
    Analytics.log('view_expert', {
      'expert_id': expertId,
      'category': category,
      'price': price,
      'video_price': videoPrice,
      'source': source,
      'is_online': isOnline,
      'rating': rating,
      'verified': verified,
      'is_own': isOwn,
    });
    if (isOwn) return;
    Analytics.meta('fb_mobile_content_view', {
      'fb_content_type': 'host_profile',
      'fb_content_id': expertId,
      'fb_currency': 'INR',
      'category': category,
      'source': source,
    }, valueToSum: price != null && price > 0 ? price : null);
  }

  /// The sheet closed: how long it was open and how many photos were seen.
  static void profileClosed({
    required String hostId,
    required String source,
    required int secondsOpen,
    required int photosViewed,
    required int photoCount,
  }) => Analytics.log('host_profile_closed', {
    'host_id': hostId,
    'source': source,
    'seconds_open': secondsOpen,
    'photos_viewed': photosViewed,
    'photo_count': photoCount,
  });

  /// The full-screen photo preview opened from the gallery.
  static void photoPreviewOpened({
    required String hostId,
    required int index,
    required int count,
  }) => Analytics.log('profile_photo_preview_opened', {
    'host_id': hostId,
    'index': index,
    'photo_count': count,
  });

  /// The bio's "Read more" / "Read less".
  static void bioToggled({required bool expanded}) =>
      Analytics.log('profile_bio_toggled', {'expanded': expanded});

  /// The influencer badge (verified platforms sheet).
  static void influencerOpened({required String hostId}) =>
      Analytics.log('profile_influencer_opened', {'host_id': hostId});

  static void voiceIntroPlayed({String? hostId}) =>
      Analytics.log('voice_intro_played', {'host_id': hostId});

  static void voiceIntroStopped({String? hostId, required int seconds}) =>
      Analytics.log('voice_intro_stopped', {
        'host_id': hostId,
        'seconds': seconds,
      });

  static void voiceIntroCompleted({String? hostId, int? seconds}) =>
      Analytics.log('voice_intro_completed', {
        'host_id': hostId,
        'seconds': seconds,
      });

  static void voiceIntroFailed({String? hostId, required String error}) =>
      Analytics.log('voice_intro_failed', {'host_id': hostId, 'error': error});

  /// The reviews strip's "See more" (next page).
  static void reviewsMoreTapped({
    String? hostId,
    required int loaded,
    required int total,
  }) => Analytics.log('profile_reviews_more_tapped', {
    'host_id': hostId,
    'loaded': loaded,
    'total': total,
  });

  /// Favourite added (Meta `fb_mobile_add_to_wishlist`) / removed.
  static void favouriteToggled({
    required String hostId,
    required bool added,
    required String source,
  }) {
    Analytics.log(added ? 'favourite_added' : 'favourite_removed', {
      'host_id': hostId,
      'source': source,
    });
    if (added) {
      Analytics.meta('fb_mobile_add_to_wishlist', {
        'fb_content_id': hostId,
        'fb_content_type': 'host',
        'fb_currency': 'INR',
      });
    }
  }

  static void favouriteFailed({
    required String hostId,
    required bool adding,
    required String error,
  }) => Analytics.log('favourite_failed', {
    'host_id': hostId,
    'adding': adding,
    'error': error,
  });

  /// The share sheet opened from the profile's top bar.
  static void shareOpened({required String hostId}) =>
      Analytics.log('profile_share_opened', {'host_id': hostId});

  /// A host profile shared: [method] `system`, `copy_link` or `qr`
  /// (+ Firebase's recommended `share`).
  static void profileShared({required String hostId, required String method}) {
    Analytics.log('profile_shared', {'host_id': hostId, 'method': method});
    Analytics.firebase('share', {
      'method': method,
      'content_type': 'host_profile',
      'item_id': hostId,
    });
  }

  /// A social / website link: [kind] `instagram`, `facebook`, `snapchat`,
  /// `website`; [opened]: the app / browser accepted it.
  static void externalLinkTapped({
    String? hostId,
    required String kind,
    required String source,
    required bool opened,
  }) => Analytics.log('profile_link_tapped', {
    'host_id': hostId,
    'kind': kind,
    'source': source,
    'opened': opened,
  });

  /// The audio / video call button on a host profile.
  static void callButtonTapped({
    required String hostId,
    required String callType,
    required double rate,
    required String source,
    required bool isCompany,
  }) => Analytics.log('call_button_tapped', {
    'host_id': hostId,
    'call_type': callType,
    'rate': rate,
    'source': source,
    'is_company': isCompany,
  });

  /// Where the pre-call checks ended: `passed` (call handed off), `own_profile`,
  /// `signed_out`, `incomplete_profile`, `balance_gate`, `safety_cancelled`.
  static void callPrecheck({
    required String hostId,
    required String callType,
    required String result,
    bool? enoughBalance,
  }) => Analytics.log('call_precheck_result', {
    'host_id': hostId,
    'call_type': callType,
    'result': result,
    'enough_balance': enoughBalance,
  });

  /// The pre-call alerts' buttons: [prompt] `login` / `update_profile`,
  /// [accepted]: the primary button.
  static void callPromptAnswered({
    required String prompt,
    required bool accepted,
  }) => Analytics.log('call_prompt_answered', {
    'prompt': prompt,
    'accepted': accepted,
  });

  /// The balance gate's "Transfer earnings" (RN had none).
  static void balanceGateTransferTapped({
    required String expertId,
    double? gap,
  }) => Analytics.log('balance_gate_transfer_tapped', {
    'expert_id': expertId,
    'gap': gap,
  });

  /// The balance gate closed without a choice.
  static void balanceGateDismissed({required String expertId, double? gap}) =>
      Analytics.log('balance_gate_dismissed', {
        'expert_id': expertId,
        'gap': gap,
      });

  /// "Before you connect": [result] `accepted` / `cancelled`.
  static void safetyPromptAnswered({
    required String callType,
    required bool accepted,
  }) => Analytics.log('safety_prompt_answered', {
    'call_type': callType,
    'result': accepted ? 'accepted' : 'cancelled',
  });

  /// The profile's ⋮ menu: [action] `report`, `block` or null (closed).
  static void profileMenuChoice({required String hostId, String? action}) =>
      Analytics.log('profile_menu_choice', {
        'host_id': hostId,
        'action': action ?? 'dismissed',
      });

  // ── Report / block a host (from the profile) ───────────────────────────

  static void reportReasonSelected({
    required String hostId,
    required String reason,
  }) => Analytics.log('host_report_reason_selected', {
    'host_id': hostId,
    'reason': reason,
  });

  /// Submit pressed but held back: [problem] `signed_out`, `no_target`,
  /// `no_reason`.
  static void reportBlocked({
    required String hostId,
    required String problem,
  }) => Analytics.log('host_report_blocked', {
    'host_id': hostId,
    'problem': problem,
  });

  static void reportSubmitted({
    required String hostId,
    required String reason,
    required bool hasNote,
    required int noteLength,
  }) => Analytics.log('host_report_submitted', {
    'host_id': hostId,
    'reason': reason,
    'has_note': hasNote,
    'note_length': noteLength,
    'source': 'profile_sheet',
  });

  static void reportFailed({
    required String hostId,
    required String reason,
    required String error,
  }) => Analytics.log('host_report_failed', {
    'host_id': hostId,
    'reason': reason,
    'error': error,
    'source': 'profile_sheet',
  });

  /// Block from the profile: [step] `confirmed`, `cancelled`, `success`,
  /// `failed`, `no_target`.
  static void block({
    required String hostId,
    required String step,
    String? error,
  }) => Analytics.log('host_block', {
    'host_id': hostId,
    'step': step,
    'error': error,
    'source': 'profile_sheet',
  });

  // ── Banners ────────────────────────────────────────────────────────────

  /// A profile / host-review warning bar showed (once per type a session).
  static void topWarnShown({required String type, required int missing}) =>
      Analytics.logOnce('top_warn_shown_$type', 'top_warn_shown', {
        'type': type,
        'missing_count': missing,
      });

  static void topWarnTapped({required String type, required String route}) =>
      Analytics.log('top_warn_tapped', {'type': type, 'route': route});

  /// The "No internet" strip appeared / went ([seconds] offline).
  static void offlineBanner({required bool shown, int? seconds}) =>
      Analytics.log(shown ? 'offline_banner_shown' : 'offline_banner_hidden', {
        'seconds_offline': seconds,
      });
}
