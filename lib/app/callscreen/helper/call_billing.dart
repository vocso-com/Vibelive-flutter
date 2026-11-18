import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:vibration/vibration.dart';

import '../../../core/analytics/events/call_ui_events.dart';
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

/// When the live call (the caller's) will be hung up, for the call screen's
/// "Add money": [endsAt] on the phone's clock.
@immutable
class CallLimit {
  const CallLimit({
    required this.callId,
    required this.endsAt,
    required this.freeLimit,
    required this.extendable,
  });

  final String callId;
  final DateTime endsAt;

  /// The end is a free call's free limit (no money in the wallet yet).
  final bool freeLimit;

  /// Money added moves the end: a paid call, or a free call that goes on
  /// paid after its free minutes. A free call that just stops is not.
  final bool extendable;

  /// What is left at [now] (never negative).
  Duration leftAt(DateTime now) {
    final left = endsAt.difference(now);
    return left.isNegative ? Duration.zero : left;
  }
}

/// Arms the max-duration timer for the caller at connect.
abstract final class CallBilling {
  /// "Add money" comes up this long before the call would be hung up.
  static const topUpLead = Duration(minutes: 2);

  /// ...and never sooner than this after connect (a call that can only
  /// afford a minute or two: not on the very first second).
  static const topUpEarliest = Duration(seconds: 3);

  /// RN's in-call buzz: the phone may be at the ear on a voice call.
  static const topUpBuzz = [0, 400, 300, 400];

  /// The live call's end (caller only, while it is capped); null otherwise.
  static final limit = ValueNotifier<CallLimit?>(null);

  /// The call whose "Add money" prompt is due (the call screen shows it).
  static final topUpDue = ValueNotifier<String?>(null);

  /// How each call hangs up at its limit (kept to re-arm after a top-up).
  static final _onLimit = <String, void Function()>{};

  /// Calls whose caller is paying right now: their end waits ([hold]).
  static final _holding = <String>{};

  /// Calls whose end came while they were held: decided on release.
  static final _endDue = <String>{};

  /// Calls the caller paid into: their limit strips are gone ([markPaid]).
  static final _paid = <String>{};

  /// The longest a call waits for a payment (the backend's hold is as long).
  static const holdMax = Duration(minutes: 5);

  /// Buzzes the phone (tests swap it).
  @visibleForTesting
  static Future<void> Function() buzz = _buzz;

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
    if (!call.isCaller || callId == null || call.connectedAt == null) return;
    _onLimit[callId] = onLimit;
    await _apply(call, onLimit, rearm: false);
  }

  /// The caller is paying ([on]): the call is not hung up meanwhile, for at
  /// most [holdMax]. Released, an end that came meanwhile is decided again
  /// on the balance now (enough money: it goes on; none: it ends now).
  static void hold(String callId, {required bool on}) {
    final timers = CallTimers.instance;
    if (on) {
      _holding.add(callId);
      timers.arm(
        CallTimers.topUpHoldMax,
        holdMax,
        () => hold(callId, on: false),
      );
      return;
    }
    timers.cancel(CallTimers.topUpHoldMax);
    if (!_holding.remove(callId)) return;
    if (_endDue.remove(callId)) unawaited(rearm(callId));
  }

  static bool holding(String? callId) => _holding.contains(callId);

  /// The caller paid during [callId] (as soon as the gateway says so): the
  /// "Add money" strip and the free-time strip go at once.
  static void markPaid(String callId) {
    _paid.add(callId);
    if (topUpDue.value == callId) topUpDue.value = null;
  }

  /// The caller paid into this call (the call screen drops its limit strips).
  static bool paidDuring(String? callId) => _paid.contains(callId);

  /// Money was added during [callId]: the balance is read again and the
  /// call's end (and its "Add money") moved to what it now pays for. True
  /// when it was re-armed. A call that is no longer live is left alone.
  static Future<bool> rearm(String callId) async {
    final live = CallController.instance.value;
    final onLimit = _onLimit[callId];
    if (onLimit == null ||
        !live.isSameCall(callId) ||
        live.phase != CallPhase.ongoing) {
      return false;
    }
    return _apply(live, onLimit, rearm: true);
  }

  static Future<bool> _apply(
    CallSession call,
    void Function() onLimit, {
    required bool rearm,
  }) async {
    final callId = call.callId;
    final connectedAt = call.connectedAt;
    if (!call.isCaller || callId == null || connectedAt == null) return false;
    final company = call.callerIsCompany || CallIdentity.isCompany;
    final free = _free[callId];
    // A company caller pays nothing: no cap, unless it is a free call that
    // stops at its free limit (testing free calls on a company account).
    if (company && (free == null || free.continuePaid)) return false;
    final uid = CallIdentity.userDocumentId;
    if (uid == null) return false;
    try {
      final rate = _rates[callId] ?? await _lookupRate(call);
      if (free == null && (rate == null || rate <= 0)) return false;
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
      if (!live.isSameCall(callId) || live.phase != CallPhase.ongoing) {
        return false;
      }
      final timers = CallTimers.instance;
      if (cap == null) {
        // Nothing to pay any more (a re-read found a company caller or no
        // rate): no end, no "Add money".
        if (rearm) {
          timers.cancel(CallTimers.maxDuration);
          timers.cancel(CallTimers.lowBalance);
          timers.cancel(CallTimers.topUpPrompt);
          if (limit.value?.callId == callId) limit.value = null;
          if (topUpDue.value == callId) topUpDue.value = null;
        }
        return rearm;
      }
      final now = DateTime.now();
      final elapsed = now.difference(connectedAt);
      timers.arm(CallTimers.maxDuration, cap.end - elapsed, () {
        if (!CallController.instance.value.isSameCall(callId)) return;
        // Paying right now: never cut off mid-payment; decided on release.
        if (_holding.contains(callId)) {
          _endDue.add(callId);
          return;
        }
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
      // "Add money" only where money helps: a company caller and a free
      // call that just stops cannot be extended.
      final extendable = !company && (free == null || free.continuePaid);
      limit.value = CallLimit(
        callId: callId,
        endsAt: connectedAt.add(cap.end),
        freeLimit: cap.freeLimit,
        extendable: extendable,
      );
      _armTopUp(callId, cap, elapsed, extendable: extendable, rearm: rearm);
      return true;
    } catch (e) {
      Log.w('CallBilling', 'max duration skipped: $e');
      return false;
    }
  }

  /// The "Add money" prompt, [topUpLead] before the end ([topUpEarliest]
  /// after connect at the soonest). After a top-up ([rearm]) a prompt still
  /// showing goes when the call now runs past [topUpLead], and stays (no
  /// second buzz) when it still does not.
  static void _armTopUp(
    String callId,
    MaxDuration cap,
    Duration elapsed, {
    required bool extendable,
    required bool rearm,
  }) {
    final timers = CallTimers.instance;
    timers.cancel(CallTimers.topUpPrompt);
    if (!extendable || cap.end <= Duration.zero) {
      if (topUpDue.value == callId) topUpDue.value = null;
      return;
    }
    final left = cap.end - elapsed;
    if (left > topUpLead) {
      if (topUpDue.value == callId) topUpDue.value = null;
      timers.arm(
        CallTimers.topUpPrompt,
        left - topUpLead,
        () => _promptTopUp(callId),
      );
      return;
    }
    // Already up (a top-up that still does not cover [topUpLead]): it stays,
    // with no second buzz.
    if (topUpDue.value == callId) return;
    // Just paid: not straight back up (the money may still be on its way;
    // the call's own end decides).
    if (rearm && _paid.contains(callId)) return;
    final wait = rearm ? Duration.zero : topUpEarliest - elapsed;
    timers.arm(
      CallTimers.topUpPrompt,
      wait.isNegative ? Duration.zero : wait,
      () => _promptTopUp(callId),
    );
  }

  /// Puts "Add money" on the call screen and buzzes the phone (once each
  /// time it comes up).
  static void _promptTopUp(String callId) {
    final live = CallController.instance.value;
    if (!live.isSameCall(callId) || !live.phase.isLive) return;
    if (topUpDue.value == callId) return;
    topUpDue.value = callId;
    final l = limit.value;
    CallUiEvents.topUpPromptShown(
      secondsLeft: l?.callId == callId
          ? l!.leftAt(DateTime.now()).inSeconds
          : null,
      free: l?.freeLimit ?? false,
    );
    unawaited(buzz());
  }

  static Future<void> _buzz() async {
    try {
      await Vibration.vibrate(pattern: topUpBuzz);
    } catch (_) {
      // No vibrator / plugin: the prompt still shows.
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
    _onLimit.clear();
    _holding.clear();
    _endDue.clear();
    _paid.clear();
    _warned = null;
    _freeWarned = null;
    limit.value = null;
    topUpDue.value = null;
    buzz = _buzz;
  }

  static void forget(String? callId) {
    _rates.remove(callId);
    _free.remove(callId);
    _onLimit.remove(callId);
    _holding.remove(callId);
    _endDue.remove(callId);
    _paid.remove(callId);
    if (_warned == callId) _warned = null;
    if (_freeWarned == callId) _freeWarned = null;
    if (callId != null && limit.value?.callId == callId) limit.value = null;
    if (callId != null && topUpDue.value == callId) topUpDue.value = null;
  }
}
