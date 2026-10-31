import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter/services.dart';

import '../../../../core/analytics/events/discover_events.dart';
import '../../../../core/i18n/i18n.dart';
import '../../../../core/network/api_exception.dart';
import '../../../../core/router/app_router.dart';
import '../../../../core/session/session_store.dart';
import '../../../../core/utils/log.dart';
import '../../../api/client/client_queries.dart';
import '../../../api/listingflow/listing_models.dart';
import '../../../api/paymentscreen/call_gate_api.dart';
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
    if (!company && rate > 0) {
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
        DiscoverEvents.balanceGateShown(
          expertId: expertId,
          callType: callType,
          required: gate.required,
          balance: gate.balance,
          gap: gate.gap,
          rate: gate.rate,
          minMinutes: gate.minutes,
          suggestedAmount: gate.suggestedAmount,
        );
        // Started before the sheet, not after it: a caller who kills the app
        // with the sheet open is the most frustrated one there is, and the row
        // has to exist for that to be visible at all. Fails open — the sheet
        // never waits on it. The durable record; the event above is the copy.
        final blockRow = CallGateApi.record(
          gate: gate,
          // NOT `host.documentId`: that one is "user documentId, else
          // expert-profile documentId", so it would fail the expert-profile
          // lookup on almost every row and silently store no host at all.
          expertProfileDocumentId: host.expertProfileDocumentId,
          video: video,
        );
        final action = await _showBalanceGate(gate, host);
        // Deliberately not guarded by `_disposed`: the outcome is worth
        // recording even when the sheet has already gone.
        unawaited(
          blockRow.then(
            (id) => CallGateApi.resolve(
              documentId: id,
              outcome: switch (action) {
                BalanceGateAction.addMoney => CallGateOutcome.addMoney,
                BalanceGateAction.transferEarnings =>
                  CallGateOutcome.transferEarnings,
                null => CallGateOutcome.dismissed,
              },
            ),
          ),
        );
        switch (action) {
          case BalanceGateAction.addMoney:
            DiscoverEvents.balanceGateTopupTapped(
              expertId: expertId,
              gap: gate.gap,
              suggestedAmount: gate.suggestedAmount,
            );
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
    precheck('passed', enoughBalance: company || rate <= 0 ? null : true);
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
