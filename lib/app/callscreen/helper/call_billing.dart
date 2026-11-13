import 'dart:math' as math;

import 'package:flutter/foundation.dart';

import '../../../core/utils/log.dart';
import '../../api/free_call/free_call_models.dart';
import '../../api/listingflow/listing_queries.dart';
import '../../api/paymentscreen/payment_queries.dart';
import 'call_alerts.dart';
import 'call_analytics.dart';
import 'call_controller.dart';
import 'call_identity.dart';
import 'call_session.dart';
import 'call_timers.dart';
import 'state/call_constants.dart';

/// When a paid call must end (decision 8, spec §9.5). The server bills
/// `max(1, ceil(t/60)) × rate` at Callend and rolls back with a 500 (the
/// call then stays "ongoing" forever, E-83) when the cash wallet can't
/// cover it, so the caller ends inside the last affordable minute.
@immutable
class MaxDuration {
  const MaxDuration({
    required this.end,
    required this.warnAt,
    this.freeLimit = false,
  });

  /// After connect: hang up here.
  final Duration end;

  /// After connect: the "about 5 minutes left" toast ([Duration.zero]:
  /// right away).
  final Duration warnAt;

  /// [end] is a free call's free limit (nothing is paid after it): the call
  /// gets its own "free call ends soon" / "free call ended" words.
  final bool freeLimit;

  /// Null = no cap: a company caller, or no rate (free call). [free]: the
  /// call is a free call (docs/free_calls.md) — its free minutes first.
  static MaxDuration? compute({
    required double cashBalance,
    required double ratePerMin,
    bool company = false,
    FreeCallTerms? free,
  }) {
    if (free != null) {
      return _forFree(
        free,
        cashBalance: cashBalance,
        ratePerMin: ratePerMin,
        company: company,
      );
    }
    if (company || !ratePerMin.isFinite || ratePerMin <= 0) return null;
    final cash = cashBalance.isFinite ? math.max(0.0, cashBalance) : 0.0;
    final affordableMinutes = (cash / ratePerMin).floor();
    return _paidUntil(Duration(minutes: affordableMinutes));
  }

  /// Ends [minutes] after connect, a margin before the next unaffordable
  /// minute is billed; the warning 5 minutes before.
  static MaxDuration _paidUntil(Duration minutes) {
    var end = minutes - CallTimings.maxDurationMargin;
    // The Agora token dies 1 h after initiate anyway (no renew route).
    final tokenCap = CallTimings.tokenLifetime - CallTimings.maxDurationMargin;
    if (end > tokenCap) end = tokenCap;
    if (end.isNegative) end = Duration.zero;
    final warn = end - CallTimings.lowBalanceWarning;
    return MaxDuration(
      end: end,
      warnAt: warn.isNegative ? Duration.zero : warn,
    );
  }

  /// A free call: its free minutes cost nothing. When it goes on paid
  /// ([FreeCallTerms.continuePaid]) the whole minutes the cash pays for come
  /// after them, capped as any paid call; with none (or when it never goes
  /// on paid) it ends at the free limit.
  static MaxDuration? _forFree(
    FreeCallTerms free, {
    required double cashBalance,
    required double ratePerMin,
    required bool company,
  }) {
    final priced = ratePerMin.isFinite && ratePerMin > 0;
    // After the free minutes a company caller (or an unpriced call) pays
    // nothing: no end to keep.
    if (free.continuePaid && (company || !priced)) return null;
    final cash = cashBalance.isFinite ? math.max(0.0, cashBalance) : 0.0;
    final paidMinutes = free.continuePaid ? (cash / ratePerMin).floor() : 0;
    if (paidMinutes > 0) {
      return _paidUntil(Duration(minutes: free.minutes + paidMinutes));
    }
    var end = free.duration - CallTimings.freeEndMargin;
    final tokenCap = CallTimings.tokenLifetime - CallTimings.maxDurationMargin;
    if (end > tokenCap) end = tokenCap;
    if (end.isNegative) end = Duration.zero;
    final warn = end - CallTimings.freeEndWarning;
    return MaxDuration(
      end: end,
      warnAt: warn.isNegative ? Duration.zero : warn,
      freeLimit: true,
    );
  }
}

/// Arms the max-duration timer for the caller at connect.
abstract final class CallBilling {
  /// Per-minute rate of each outgoing call (the host card's), by call id.
  static final _rates = <String, double>{};

  /// Each outgoing free call's terms, as the server stamped them, by call id.
  static final _free = <String, FreeCallTerms>{};
  static String? _warned;
  static String? _freeWarned;

  /// The live call's free terms (the call screen's "free" chip); null on a
  /// paid call.
  static FreeCallTerms? freeFor(String? callId) =>
      callId == null ? null : _free[callId];

  /// What the server said about this call's free minutes; null: not free
  /// (a later answer — another host took a Talk Now call — can take it back).
  static void rememberFree(String callId, FreeCallTerms? terms) {
    if (terms == null || terms.minutes <= 0) {
      _free.remove(callId);
    } else {
      _free[callId] = terms;
    }
  }

  /// "Your free call ends soon", once per call.
  static void _freeWarnOnce(String callId) {
    if (_freeWarned == callId) return;
    final live = CallController.instance.value;
    if (!live.isSameCall(callId) || !live.phase.isLive) return;
    _freeWarned = callId;
    CallAlerts.toast(CallFlowKeys.freeEndingSoon);
  }

  /// The "about 5 minutes left" toast, once per call (our timer or the
  /// backend's `LOW_BALANCE_WARNING` hint, whichever comes first).
  static void warnOnce(String callId) {
    if (_warned == callId) return;
    final live = CallController.instance.value;
    if (!live.isSameCall(callId) || !live.phase.isLive) return;
    _warned = callId;
    CallAlerts.toast(CallFlowKeys.lowBalanceWarning);
  }

  static void rememberRate(String callId, double ratePerMin) {
    _rates[callId] = ratePerMin;
    CallAnalytics.rate(callId, ratePerMin);
  }

  /// Caller only; reads the cash balance now. [onLimit] hangs up. A failed
  /// read leaves the call uncapped (the backend's low-balance cron is the
  /// backstop).
  static Future<void> arm(
    CallSession call, {
    required void Function() onLimit,
  }) async {
    final callId = call.callId;
    final connectedAt = call.connectedAt;
    if (!call.isCaller || callId == null || connectedAt == null) return;
    final company = call.callerIsCompany || CallIdentity.isCompany;
    final free = _free[callId];
    // A company caller pays nothing: no cap, unless it is a free call that
    // stops at its free limit (testing free calls on a company account).
    if (company && (free == null || free.continuePaid)) return;
    final uid = CallIdentity.userDocumentId;
    if (uid == null) return;
    try {
      final rate = _rates[callId] ?? await _lookupRate(call);
      if (free == null && (rate == null || rate <= 0)) return;
      // The balance matters only for what is paid: not for a company caller,
      // nor for a free call that ends at its limit.
      final paysAfter = !company && (free == null || free.continuePaid);
      final cash = paysAfter
          ? (await ensureWalletBalance(userDocumentId: uid)).cashBalance
          : 0.0;
      final cap = MaxDuration.compute(
        cashBalance: cash,
        ratePerMin: rate ?? 0,
        company: company,
        free: free,
      );
      final live = CallController.instance.value;
      if (cap == null ||
          !live.isSameCall(callId) ||
          live.phase != CallPhase.ongoing) {
        return;
      }
      final elapsed = DateTime.now().difference(connectedAt);
      final timers = CallTimers.instance;
      timers.arm(CallTimers.maxDuration, cap.end - elapsed, () {
        if (!CallController.instance.value.isSameCall(callId)) return;
        CallAlerts.toast(
          cap.freeLimit ? CallFlowKeys.freeEnded : CallFlowKeys.lowBalanceEnded,
        );
        onLimit();
      });
      if (cap.end > Duration.zero) {
        timers.arm(
          CallTimers.lowBalance,
          cap.warnAt - elapsed,
          () => cap.freeLimit ? _freeWarnOnce(callId) : warnOnce(callId),
        );
      }
    } catch (e) {
      Log.w('CallBilling', 'max duration skipped: $e');
    }
  }

  /// Callback / redial calls have no host card: the host's rates by link.
  static Future<double?> _lookupRate(CallSession call) async {
    final id = call.remote.documentId ?? call.receiverDocId;
    if (id == null) return null;
    final host = await ensureHostByLink(id);
    return call.isVideo ? host.vPrice : host.aPrice;
  }

  @visibleForTesting
  static void debugReset() {
    _rates.clear();
    _free.clear();
    _warned = null;
    _freeWarned = null;
  }

  static void forget(String? callId) {
    _rates.remove(callId);
    _free.remove(callId);
    if (_warned == callId) _warned = null;
    if (_freeWarned == callId) _freeWarned = null;
  }
}
