import '../analytics.dart';

/// The call a UI event is about (primitives only; built from a call
/// session by the call screens' `callInfoOf`).
typedef CallInfo = ({
  String? callId,
  String callType,
  String role,
  String? hostId,
  String phase,
  bool instant,
});

/// What users do on the call screens, before and after a call, and in the
/// call log (Firebase + Meta). The call's own lifecycle (initiated,
/// incoming, started, ended, missed…) is `CallAnalytics`. Catalog:
/// docs/analytics_events.md.
abstract final class CallUiEvents {
  static Map<String, Object?> _call(CallInfo? c) => c == null
      ? const {}
      : {
          'call_id': c.callId,
          'call_type': c.callType,
          'role': c.role,
          'host_id': c.hostId,
          'phase': c.phase,
          'instant_call': c.instant,
        };

  static String _type(bool video) => video ? 'video' : 'audio';

  // ── Call screen controls ───────────────────────────────────────────────

  static void muteToggled(CallInfo call, {required bool muted}) =>
      Analytics.log('call_mute_toggled', {..._call(call), 'muted': muted});

  static void speakerToggled(CallInfo call, {required bool on}) =>
      Analytics.log('call_speaker_toggled', {..._call(call), 'enabled': on});

  /// Own camera on / off (video calls).
  static void cameraToggled(CallInfo call, {required bool on}) =>
      Analytics.log('call_camera_toggled', {..._call(call), 'enabled': on});

  static void cameraFlipped(CallInfo call, {required bool front}) =>
      Analytics.log('call_camera_flipped', {..._call(call), 'front': front});

  /// The red hang-up button (not a hang-up from the system UI).
  static void hangupTapped(CallInfo call, {int? elapsedSeconds}) =>
      Analytics.log('call_hangup_tapped', {
        ..._call(call),
        'elapsed_seconds': elapsedSeconds,
      });

  /// Header back during a live call: Home, the call keeps running.
  /// The call screen's "Add money" came up (the caller's balance or free
  /// minutes run out soon). [secondsLeft]: before the call would end.
  static void topUpPromptShown({int? secondsLeft, required bool free}) =>
      Analytics.log('call_topup_prompt_shown', {
        'seconds_left': ?secondsLeft,
        'free': free,
      });

  /// "Add money" tapped on the call screen. [from]: `prompt` / `pill`;
  /// [speaker]: the call was moved to the speaker for it.
  static void topUpTapped({required String from, required bool speaker}) =>
      Analytics.log('call_topup_tapped', {'from': from, 'speaker': speaker});

  /// How the in-call top-up ended: `success` / `pending` / `failure` /
  /// `closed`; [extended]: the call's end moved.
  static void topUpFinished({required String result, required bool extended}) =>
      Analytics.log('call_topup_finished', {
        'result': result,
        'extended': extended,
      });

  static void minimized(CallInfo call) =>
      Analytics.log('call_minimized', _call(call));

  /// The "return to call" bar on Home.
  static void returnTapped(CallInfo call) =>
      Analytics.log('call_return_tapped', _call(call));

  /// The small video tile tapped: own / remote video swap places.
  static void videoSwapped(CallInfo call, {required bool swapped}) =>
      Analytics.log('call_video_swapped', {..._call(call), 'swapped': swapped});

  /// iOS screen recording / mirroring started: the call is hidden.
  static void captureShielded() => Analytics.log('call_capture_shielded');

  // ── Safety (in call, incoming, after the call) ─────────────────────────

  static void safetyPanelOpened(CallInfo call) =>
      Analytics.log('call_safety_panel_opened', _call(call));

  static void safetyPanelClosed(CallInfo call) =>
      Analytics.log('call_safety_panel_closed', _call(call));

  /// A block / report confirm dialog answered. [source]: `incoming` |
  /// `after_call`.
  static void safetyConfirm({
    required String action,
    required String source,
    required bool confirmed,
    CallInfo? call,
  }) => Analytics.log('call_safety_confirm', {
    ..._call(call),
    'action': action,
    'source': source,
    'confirmed': confirmed,
  });

  /// A block / report went through (or not). [action]: `report` | `block`;
  /// [source]: `in_call` | `incoming` | `after_call`; [outcome]: `done` |
  /// `no_target` | `failed`.
  static void safetyAction({
    required String action,
    required String source,
    required String outcome,
    CallInfo? call,
  }) => Analytics.log('call_safety_action', {
    ..._call(call),
    'action': action,
    'source': source,
    'outcome': outcome,
  });

  // ── Incoming screen ────────────────────────────────────────────────────

  static void acceptTapped(CallInfo call) =>
      Analytics.log('call_accept_tapped', _call(call));

  static void declineTapped(CallInfo call) =>
      Analytics.log('call_decline_tapped', _call(call));

  /// "Block / Report this caller" row tapped (a confirm follows).
  static void incomingSafetyTapped(CallInfo call, {required String action}) =>
      Analytics.log('incoming_safety_tapped', {
        ..._call(call),
        'action': action,
      });

  // ── Placing a call ─────────────────────────────────────────────────────

  /// The user starts a call (after the profile's own checks). [source]:
  /// `host_profile` | `callback`.
  static void attempt({
    required bool video,
    required String source,
    String? hostId,
    double? ratePerMin,
  }) => Analytics.log('call_attempt', {
    'call_type': _type(video),
    'source': source,
    'host_id': hostId,
    'rate_per_min': ratePerMin,
  });

  /// No call started. [reason]: `missing_participants` |
  /// `permission_denied` | `host_busy` | `insufficient_balance` |
  /// `host_offline` | `blocked` | `api_error` | `call_in_progress` |
  /// `exception`.
  static void initiateFailed({
    required String reason,
    required bool video,
    required String source,
    String? hostId,
    String? error,
  }) => Analytics.log('call_initiate_failed', {
    'reason': reason,
    'call_type': _type(video),
    'source': source,
    'host_id': hostId,
    'error': error,
  });

  // ── Instant call ("Talk now") ──────────────────────────────────────────

  static void instantRequested({required bool video}) =>
      Analytics.log('instant_call_requested', {'call_type': _type(video)});

  /// Same reasons as [initiateFailed].
  static void instantFailed({
    required bool video,
    required String reason,
    String? error,
  }) => Analytics.log('instant_call_failed', {
    'call_type': _type(video),
    'reason': reason,
    'error': error,
  });

  /// The ring moved on to the next host (cascade). [attempt]: 1-based.
  static void instantHostAssigned({String? callId, required int attempt}) =>
      Analytics.log('instant_call_host_assigned', {
        'call_id': callId,
        'attempt': attempt,
      });

  static void instantMatched({String? callId, String? hostUserId}) =>
      Analytics.log('instant_call_matched', {
        'call_id': callId,
        'peer_id': hostUserId,
      });

  /// Nobody picked up: the server gave up the search.
  static void instantNoHost({String? callId, int? attempts}) =>
      Analytics.log('instant_call_no_host', {
        'call_id': callId,
        'attempts': attempts,
      });

  /// The caller left before a host answered.
  static void instantCancelled({String? callId, int? attempts}) =>
      Analytics.log('instant_call_cancelled', {
        'call_id': callId,
        'attempts': attempts,
      });

  // ── Permissions ────────────────────────────────────────────────────────

  /// The system mic (+ camera) prompt answered. [permission]: `mic` |
  /// `mic_camera`; [result]: `granted` | `denied` | `blocked` | `unknown`.
  static void permissionRequested({
    required String permission,
    required String result,
    required String context,
  }) => Analytics.log('call_permission_requested', {
    'permission': permission,
    'result': result,
    'context': context,
  });

  /// "Permission needed" alert after a refusal; [openedSettings]: the user
  /// chose Open Settings.
  static void permissionAlert({
    required String permission,
    required bool blocked,
    required bool openedSettings,
  }) => Analytics.log('call_permission_alert', {
    'permission': permission,
    'blocked': blocked,
    'opened_settings': openedSettings,
  });

  /// The red / amber "mic is off" bar appeared. [screen]: `call` |
  /// `incoming`.
  static void permissionBarShown({
    required String permission,
    required String state,
    required String screen,
  }) => Analytics.log('call_permission_bar_shown', {
    'permission': permission,
    'state': state,
    'screen': screen,
  });

  /// The bar tapped; [result]: the state afterwards.
  static void permissionBarTapped({
    required String permission,
    required String state,
    required String result,
    required String screen,
  }) => Analytics.log('call_permission_bar_tapped', {
    'permission': permission,
    'state': state,
    'result': result,
    'screen': screen,
  });

  /// Hosts: mic + camera asked once after sign-in.
  static void permissionPrimed({required bool mic, required bool camera}) =>
      Analytics.log('call_permission_primed', {'mic': mic, 'camera': camera});

  /// Android 12+ Bluetooth routing permission answered.
  static void bluetoothPermission({required bool granted}) =>
      Analytics.log('bluetooth_permission_result', {'granted': granted});

  /// Hosts on Xiaomi / Samsung / Oppo / OnePlus miss an OEM permission
  /// calls need. [missing]: comma-separated.
  static void devicePermissionNeeded({
    required String brand,
    required String missing,
    required int count,
  }) => Analytics.log('device_permission_needed', {
    'brand': brand,
    'missing': missing,
    'count': count,
  });

  static void devicePermissionOpened({required String brand}) =>
      Analytics.log('device_permission_opened', {'brand': brand});

  static void devicePermissionSnoozed() =>
      Analytics.log('device_permission_snoozed');

  // ── After the call ─────────────────────────────────────────────────────

  /// The ended screen. [next]: `feedback` (rating sheet) | `exit`.
  static void summaryShown(
    CallInfo call, {
    required String next,
    required bool connected,
    int? durationSeconds,
  }) => Analytics.log('call_summary_shown', {
    ..._call(call),
    'next': next,
    'connected': connected,
    'duration_seconds': durationSeconds,
  });

  static void feedbackRatingSelected(CallInfo? call, {required int rating}) =>
      Analytics.log('call_feedback_rating', {..._call(call), 'rating': rating});

  /// The rating went to the server (or not). Meta also gets its standard
  /// "Rated" event on success.
  static void feedbackSubmitted(
    CallInfo? call, {
    required int rating,
    required bool hasComment,
    required int commentLength,
    required bool success,
    String? error,
  }) {
    Analytics.log('call_feedback_submitted', {
      ..._call(call),
      'rating': rating,
      'has_comment': hasComment,
      'comment_length': commentLength,
      'result': success ? 'success' : 'failed',
      'error': error,
    });
    if (success) {
      Analytics.meta('fb_mobile_rate', {
        'fb_content_type': 'call',
        'fb_content_id': call?.hostId ?? call?.callId,
        'fb_max_rating_value': 5,
      }, valueToSum: rating.toDouble());
    }
  }

  static void feedbackSkipped(CallInfo? call, {required int rating}) =>
      Analytics.log('call_feedback_skipped', {
        ..._call(call),
        'rating': rating,
      });

  // ── Callback sheet (a host nudged the client) ──────────────────────────

  static void callbackShown({String? hostId, String? category}) =>
      Analytics.log('callback_shown', {
        'host_id': hostId,
        'category': category,
      });

  static void callbackCallTapped({
    required bool video,
    String? hostId,
    num? ratePerMin,
  }) => Analytics.log('callback_call_tapped', {
    'call_type': _type(video),
    'host_id': hostId,
    'rate_per_min': ratePerMin,
  });

  static void callbackProfileTapped({String? hostId}) =>
      Analytics.log('callback_profile_tapped', {'host_id': hostId});

  /// [method]: `close` | `backdrop`.
  static void callbackDismissed({required String method, String? hostId}) =>
      Analytics.log('callback_dismissed', {
        'method': method,
        'host_id': hostId,
      });

  // ── Call log (History tab) ─────────────────────────────────────────────

  static void historyLoaded({required int count, required bool hasMore}) =>
      Analytics.log('call_history_loaded', {
        'count': count,
        'has_more': hasMore,
      });

  static void historyEmpty() => Analytics.log('call_history_empty');

  static void historyLoadFailed({String? error}) =>
      Analytics.log('call_history_load_failed', {'error': error});

  static void historyLoadMore({required int count}) =>
      Analytics.log('call_history_load_more', {'count': count});

  static void historyLoadMoreFailed({String? error}) =>
      Analytics.log('call_history_load_more_failed', {'error': error});

  static void historyRefreshed({required bool success, String? error}) =>
      Analytics.log('call_history_refreshed', {
        'result': success ? 'success' : 'failed',
        'error': error,
      });

  /// A row tapped (opens the host's profile).
  static void historyRowTapped({
    required String direction,
    required String outcome,
    required bool video,
    String? peerId,
  }) => Analytics.log('call_history_row_tapped', {
    'direction': direction,
    'outcome': outcome,
    'call_type': _type(video),
    'peer_id': peerId,
  });

  static void historyProfileFailed({String? error}) =>
      Analytics.log('call_history_profile_failed', {'error': error});

  static void historyMenuOpened({
    required bool canRate,
    required bool isHost,
    String? peerId,
  }) => Analytics.log('call_history_menu_opened', {
    'can_rate': canRate,
    'is_host': isHost,
    'peer_id': peerId,
  });

  /// [action]: `rate` | `profile` | `report` | `dismissed`.
  static void historyMenuAction({required String action, String? peerId}) =>
      Analytics.log('call_history_menu_action', {
        'action': action,
        'peer_id': peerId,
      });

  /// A report category chip picked (history report sheet).
  static void reportReasonSelected({required String categoryId}) =>
      Analytics.log('call_report_reason_selected', {
        'category_id': categoryId,
      });

  static void reportSubmitted({
    required bool success,
    String? categoryId,
    required bool hasNote,
    String? peerId,
    String? error,
  }) => Analytics.log('call_report_submitted', {
    'result': success ? 'success' : 'failed',
    'category_id': categoryId,
    'has_note': hasNote,
    'peer_id': peerId,
    'error': error,
  });

  /// Closed with X, nothing sent.
  static void reportClosed({String? categoryId}) =>
      Analytics.log('call_report_closed', {'category_id': categoryId});

  static void reviewRatingSelected({required int rating}) =>
      Analytics.log('call_review_rating', {'rating': rating});

  /// History "Rate this Call" saved (or not); Meta "Rated" on success.
  static void reviewSubmitted({
    required bool success,
    required int rating,
    required bool hasComment,
    String? hostId,
    String? callId,
    String? error,
  }) {
    Analytics.log('call_review_submitted', {
      'result': success ? 'success' : 'failed',
      'rating': rating,
      'has_comment': hasComment,
      'host_id': hostId,
      'call_id': callId,
      'error': error,
    });
    if (success) {
      Analytics.meta('fb_mobile_rate', {
        'fb_content_type': 'call',
        'fb_content_id': hostId ?? callId,
        'fb_max_rating_value': 5,
      }, valueToSum: rating.toDouble());
    }
  }

  static void reviewSkipped({required int rating, required bool hasComment}) =>
      Analytics.log('call_review_skipped', {
        'rating': rating,
        'has_comment': hasComment,
      });

  /// Hosts: NUDGE (ask a client who missed the call to call back).
  static void nudgeSent({
    required bool success,
    String? clientId,
    String? error,
  }) => Analytics.log('host_nudge_sent', {
    'result': success ? 'success' : 'failed',
    'client_id': clientId,
    'error': error,
  });
}
