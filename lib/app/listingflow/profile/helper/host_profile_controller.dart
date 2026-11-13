import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter/services.dart';

import '../../../../core/analytics/analytics.dart';
import '../../../../core/analytics/events/discover_events.dart';
import '../../../../core/i18n/i18n.dart';
import '../../../../core/network/api_exception.dart';
import '../../../../core/router/app_router.dart';
import '../../../../core/session/session_store.dart';
import '../../../../core/utils/log.dart';
import '../../../api/client/client_queries.dart';
import '../../../api/free_call/free_call_queries.dart';
import '../../../api/listingflow/listing_models.dart';
import '../../../api/paymentscreen/payment_queries.dart';
import '../../../api/paymentscreen/runtime_config_queries.dart';
import '../../../api/paymentscreen/wallet_models.dart';
import '../../../component/app_share.dart';
import '../../../component/c_alert.dart';
import '../../../component/c_toast.dart';
import '../../../paymentscreen/wallet/helper/balance_gate.dart';
import '../../../paymentscreen/wallet/widgets/balance_gate_sheet.dart';
import '../../../paymentscreen/wallet/widgets/transfer_sheet.dart';
import 'host_profile_rules.dart';

/// Shows the balance gate for a host; null when dismissed.
typedef BalanceGatePrompt =
    Future<BalanceGateAction?> Function(BalanceGate gate, HostCard host);

/// What the profile sheet does besides drawing (RN `ProfileModal` logic): the
/// pre-call checks before a call is handed off, and the share link.
///
/// State is split into small notifiers so only the piece showing it
/// rebuilds: the photo index, the call buttons' busy state, the status bar.
class HostProfileController {
  HostProfileController({
    this.source = 'profile_sheet',
    required this.close,
    required this.navigate,
    required this.confirmStart,
    required this.handOff,
    BalanceGatePrompt? showBalanceGate,
    Future<void> Function(WalletBalance balance)? transferEarnings,
  }) : _showBalanceGate = showBalanceGate ?? _defaultGate,
       _transferEarnings = transferEarnings ?? _defaultTransfer;

  /// Where the profile was opened from (analytics `source`).
  final String source;

  /// Closes the profile sheet.
  final VoidCallback close;

  /// Opens [route] (called right after [close]).
  final void Function(String route) navigate;

  /// The safety notice shown before connecting; true = start the call.
  final Future<bool> Function(bool video) confirmStart;

  /// The call layer (`startOutgoingCall`).
  final Future<void> Function(HostCard host, bool video) handOff;

  final BalanceGatePrompt _showBalanceGate;

  /// RN opens the earnings → cash transfer in place, over the profile.
  final Future<void> Function(WalletBalance balance) _transferEarnings;

  static Future<BalanceGateAction?> _defaultGate(
    BalanceGate gate,
    HostCard host,
  ) async {
    final ctx = rootNavigatorKey.currentContext;
    if (ctx == null) return null;
    return showBalanceGateSheet(ctx, gate: gate, hostName: host.name);
  }

  static Future<void> _defaultTransfer(WalletBalance balance) async {
    final ctx = rootNavigatorKey.currentContext;
    if (ctx == null) return;
    await showTransferSheet(
      ctx,
      cash: balance.cashBalance,
      earnings: balance.earningsBalance,
      source: 'balance_gate',
    );
  }

  /// Gallery photo shown in the hero.
  final activeImage = ValueNotifier(0);

  /// From the tap until the call is handed off (RN `preparingCall`).
  final preparingCall = ValueNotifier(false);

  /// The photo has scrolled under the status bar.
  final pastHero = ValueNotifier(false);

  static const _tag = 'HostProfile';

  // Sync guard: two taps in the same frame must not both get through.
  bool _callLock = false;
  bool _disposed = false;

  void nextImage(int count) {
    if (count > 1) activeImage.value = (activeImage.value + 1) % count;
  }

  void previousImage(int count) {
    if (count > 1) {
      activeImage.value = (activeImage.value - 1 + count) % count;
    }
  }

  /// Scroll offset of the profile list (status bar style).
  void onScroll(double pixels, double heroEnd) =>
      _set(pastHero, pixels > heroEnd);

  /// OS share sheet with RN's message ("Check out … on Vibe: link").
  Future<void> share(BuildContext context, HostCard host) {
    DiscoverEvents.profileShared(
      hostId: HostProfileRules.expertKey(host),
      method: 'system',
    );
    return AppShare.text(
      context.t(
        'host:share.message',
        variables: {'name': host.name, 'url': HostProfileRules.shareUrl(host)},
      ),
      anchor: context.findRenderObject(),
    );
  }

  Future<void> copyLink(HostCard host) async {
    DiscoverEvents.profileShared(
      hostId: HostProfileRules.expertKey(host),
      method: 'copy_link',
    );
    await Clipboard.setData(
      ClipboardData(text: HostProfileRules.shareUrl(host)),
    );
    CToast.show('host:share.copied', variant: CToastVariant.success);
  }

  /// Audio / video button: every RN check in order, then the hand-off.
  /// Which call button started the current [preparingCall] (spinner).
  bool pendingVideo = false;

  Future<void> placeCall(
    HostCard host, {
    required bool video,
    required bool isMe,
    required bool isCompany,
  }) async {
    if (_callLock) return;
    _callLock = true;
    DiscoverEvents.callButtonTapped(
      hostId: HostProfileRules.expertKey(host),
      callType: video ? 'video' : 'audio',
      rate: video ? host.vPrice : host.aPrice,
      source: source,
      isCompany: isCompany,
    );
    _set(preparingCall, true);
    var handedOff = false;
    try {
      handedOff = await _check(host, video, isMe, isCompany);
    } finally {
      _callLock = false;
      // Handed off: the sheet is closing, keep the spinner (RN).
      if (!handedOff) _set(preparingCall, false);
    }
  }

  Future<bool> _check(
    HostCard host,
    bool video,
    bool isMe,
    bool isCompany,
  ) async {
    final hostId = HostProfileRules.expertKey(host);
    final callType = video ? 'video' : 'audio';
    void precheck(String result, {bool? enoughBalance}) =>
        DiscoverEvents.callPrecheck(
          hostId: hostId,
          callType: callType,
          result: result,
          enoughBalance: enoughBalance,
        );
    if (isMe) {
      precheck('own_profile');
      await CAlert.show(
        title: 'host:call.self_title',
        message: 'host:call.self_message',
      );
      return false;
    }

    final uid = SessionStore.instance.value.userDocumentId;
    if (uid == null) {
      precheck('signed_out');
      final login = await CAlert.show(
        title: 'host:call.login_title',
        message: 'host:call.login_message',
        primaryLabel: 'host:call.login',
        secondaryLabel: 'actions.cancel',
        variant: CAlertVariant.warning,
      );
      DiscoverEvents.callPromptAnswered(
        prompt: 'login',
        accepted: login == true,
      );
      if (login == true) _leaveTo(AppRoutes.login);
      return false;
    }

    // Whether this call starts free (docs/free_calls.md): read alongside.
    // Off when unknown, so the balance gate works as before.
    final freeCall = ensureFreeCallStatus();
    // Started now so it overlaps the profile read. A failed read lets the
    // call through (RN fails open: the wallet never blocks a call).
    final wallet = ensureWalletBalance(userDocumentId: uid)
        .then<WalletBalance?>(
          (balance) => balance,
          onError: (Object e) {
            Log.w(_tag, 'balance read failed, calling anyway: $e');
            return null;
          },
        );

    var company = isCompany;
    try {
      final me = await ensureMyProfile(uid);
      company = company || me.isCompanyAccount;
      if (me.name == null || me.email == null || me.mobile == null) {
        if (_disposed) return false;
        precheck('incomplete_profile');
        final update = await CAlert.show(
          title: 'host:call.incomplete_title',
          message: 'host:call.incomplete_message',
          primaryLabel: 'host:call.update_profile',
          secondaryLabel: 'actions.cancel',
          variant: CAlertVariant.warning,
        );
        DiscoverEvents.callPromptAnswered(
          prompt: 'update_profile',
          accepted: update == true,
        );
        if (update == true) _leaveTo(AppRoutes.personalInfo);
        return false;
      }
    } on ApiException catch (e) {
      // RN: a failed profile read never blocks the call.
      Log.w(_tag, 'profile check skipped: $e');
    }

    final rate = video ? host.vPrice : host.aPrice;
    // A free call needs no balance to start: the server checks the same.
    final free = (await freeCall).covers(video: video, talkNow: false);
    if (!company && rate > 0 && !free) {
      final balance = await wallet;
      // The minimum comes from config (cached, fallback 5 min); a stale
      // block is re-read in the background for the next call.
      unawaited(ensureFreshRuntimeConfig());
      final gate = balance == null
          ? null
          : BalanceGate.check(
              rate: rate,
              cash: balance.cashBalance,
              earnings: balance.earningsBalance,
              config: currentRuntimeConfig(),
            );
      if (balance != null && gate != null) {
        if (_disposed) return false;
        precheck('balance_gate', enoughBalance: false);
        final expertId = host.documentId ?? '${host.id}';
        Analytics.log('balance_gate_shown', {
          'expert_id': expertId,
          'required': gate.required,
          'balance': gate.balance,
          'gap': gate.gap,
        });
        switch (await _showBalanceGate(gate, host)) {
          case BalanceGateAction.addMoney:
            Analytics.log('balance_gate_topup_tapped', {
              'expert_id': expertId,
              'gap': gate.gap,
              'suggested_amount': gate.suggestedAmount,
            });
            // The wallet opens with the amount pre-filled.
            _leaveTo(
              '${AppRoutes.wallet}?amount=${gate.suggestedAmount}'
              '&reason=call_gate',
            );
          case BalanceGateAction.transferEarnings:
            DiscoverEvents.balanceGateTransferTapped(
              expertId: expertId,
              gap: gate.gap,
            );
            if (!_disposed) await _transferEarnings(balance);
          case null:
            DiscoverEvents.balanceGateDismissed(
              expertId: expertId,
              gap: gate.gap,
            );
        }
        return false;
      }
    }

    if (_disposed) return false;
    if (!await confirmStart(video)) {
      precheck('safety_cancelled');
      return false;
    }
    if (_disposed) return false;
    precheck(
      free ? 'passed_free' : 'passed',
      enoughBalance: company || rate <= 0 || free ? null : true,
    );
    close();
    await handOff(host, video);
    return true;
  }

  void _leaveTo(String route) {
    if (_disposed) return;
    close();
    navigate(route);
  }

  void _set<T>(ValueNotifier<T> notifier, T value) {
    if (!_disposed) notifier.value = value;
  }

  void dispose() {
    _disposed = true;
    activeImage.dispose();
    preparingCall.dispose();
    pastHero.dispose();
  }
}
