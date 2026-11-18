import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../core/analytics/events/call_ui_events.dart';
import '../../../core/i18n/i18n.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/utils/scale.dart';
import '../../component/c_text.dart';
import '../../component/pressable.dart';
import '../../paymentscreen/wallet/helper/add_money_flow.dart';
import '../../paymentscreen/wallet/helper/topup_bonus.dart';
import '../../paymentscreen/wallet/helper/topup_checkout.dart';
import '../../api/callscreen/call_api.dart';
import '../helper/call_billing.dart';
import '../helper/call_controller.dart';
import '../helper/call_session.dart';
import '../helper/engine/call_engine.dart';
import 'helper/call_format.dart';
import 'helper/call_select.dart';

/// The wallet's Add Money for a call: [onPaid] the moment the gateway
/// reports a result.
typedef InCallPay =
    Future<TopUpResult?> Function(
      BuildContext context,
      void Function(TopUpResult result) onPaid,
    );

/// "Add money" in the middle of a call (the caller's balance or free
/// minutes run out in [CallBilling.topUpLead]): the wallet's own Add Money
/// over the call, which goes on meanwhile.
///
/// - The call is never cut off while the caller pays: held here
///   ([CallBilling.hold]) and on the server (its low-balance guard), for at
///   most [CallBilling.holdMax].
/// - The moment the gateway says paid, the "Add money" and free-time strips
///   go and the call's end moves to what the wallet now pays for
///   ([CallBilling.rearm]); a payment still being confirmed is re-read a few
///   times, the hold kept meanwhile.
/// - Nothing paid: released, and a call already past its end ends then.
/// - On the speaker while the screen is needed (not over a headset or
///   Bluetooth), back to the earpiece after.
abstract final class InCallTopUp {
  /// A payment the server had not confirmed yet is re-read after these.
  static const pendingRechecks = [
    Duration(seconds: 5),
    Duration(seconds: 10),
    Duration(seconds: 15),
  ];

  static bool _running = false;

  /// The wallet's Add Money (tests swap it).
  @visibleForTesting
  static InCallPay pay = _pay;

  /// The server's hold (tests swap it).
  @visibleForTesting
  static Future<bool> Function(String record, {required bool active})
  serverHold = CallApi.topUpHold;

  /// The first-top-up bonus to promise on the card (tests swap it).
  @visibleForTesting
  static Future<TopUpBonus?> Function() bonus = AddMoneyFlow.firstTopupBonus;

  static Future<TopUpResult?> _pay(
    BuildContext context,
    void Function(TopUpResult) onPaid,
  ) => AddMoneyFlow.run(context, source: 'in_call', onPaid: onPaid);

  @visibleForTesting
  static void debugReset() {
    _running = false;
    pay = _pay;
    serverHold = CallApi.topUpHold;
    bonus = AddMoneyFlow.firstTopupBonus;
  }

  /// The call record's id (Talk Now: the record the host's answer made).
  static String? _record(CallSession s) {
    final id = s.serverCallId ?? s.callId;
    return id != null && RegExp(r'^\d+$').hasMatch(id) ? id : null;
  }

  static bool _paidOk(TopUpResult? r) =>
      r == TopUpResult.success || r == TopUpResult.pending;

  /// [from]: `prompt` / `pill` (analytics). [hold]: the call screen's
  /// post-call step waits for this to finish (a call that ends meanwhile
  /// never pulls the Add Money or a payment out from under the user).
  static Future<void> start(
    BuildContext context, {
    required String from,
    void Function(Future<void> until)? hold,
  }) async {
    if (_running) return;
    final live = CallController.instance.value;
    final callId = live.callId;
    if (callId == null || !live.isCaller || !live.phase.isLive) return;
    _running = true;
    final done = Completer<void>();
    hold?.call(done.future);
    final record = _record(live);
    final engine = CallEngine.instance;
    // The phone leaves the ear to pay: the talk goes on through the speaker
    // (not when a headset or Bluetooth carries it).
    final speaker = !engine.media.value.speakerOn && !engine.audioOnAccessory;
    final before = CallBilling.limit.value?.endsAt;
    TopUpResult? result;
    Future<bool>? moved;
    try {
      // Not cut off while paying: here and on the server.
      CallBilling.hold(callId, on: true);
      if (record != null) unawaited(serverHold(record, active: true));
      if (speaker) await engine.setSpeaker(true);
      CallUiEvents.topUpTapped(from: from, speaker: speaker);
      if (!context.mounted) return;
      result = await pay(context, (paid) {
        if (!_paidOk(paid)) return;
        // Paid: the strips go now, the end moves now.
        CallBilling.markPaid(callId);
        moved = CallBilling.rearm(callId);
      });
      await moved;
      if (result == TopUpResult.pending) {
        // Paid, not confirmed yet: read again while still held.
        for (final wait in pendingRechecks) {
          await Future<void>.delayed(wait);
          final now = CallController.instance.value;
          if (!now.isSameCall(callId) || !now.phase.isLive) break;
          await CallBilling.rearm(callId);
          final l = CallBilling.limit.value;
          if (l != null && l.leftAt(DateTime.now()) > CallBilling.topUpLead) {
            break;
          }
        }
      }
    } finally {
      _running = false;
      final after = CallBilling.limit.value;
      CallUiEvents.topUpFinished(
        result: result?.name ?? 'closed',
        extended:
            after != null &&
            after.callId == callId &&
            before != null &&
            after.endsAt.isAfter(before),
      );
      // Released: an end that came meanwhile is decided on the balance now.
      CallBilling.hold(callId, on: false);
      if (record != null) unawaited(serverHold(record, active: false));
      final now = CallController.instance.value;
      if (speaker &&
          now.isSameCall(callId) &&
          now.phase.isLive &&
          engine.media.value.speakerOn) {
        await engine.setSpeaker(false);
      }
      done.complete();
    }
  }
}

/// The call screen's "Add money", over the call just above the controls:
/// a card when it comes up (what is left, ticking, and one button), then,
/// once closed, a small pill with the time left. Caller only, while the
/// call is live and [CallBilling.topUpDue] names it.
class CallTopUpLayer extends HookWidget {
  const CallTopUpLayer({super.key, this.onHold});

  /// The post-call step's hold (see [InCallTopUp.start]).
  final void Function(Future<void> until)? onHold;

  @override
  Widget build(BuildContext context) {
    final (callId, caller, live, video) = useCallSelect(
      (s) => (s.callId, s.isCaller, s.phase.isLive, s.isVideo),
    );
    final due = useValueListenable(CallBilling.topUpDue);
    final limit = useValueListenable(CallBilling.limit);
    final show =
        callId != null &&
        caller &&
        live &&
        due == callId &&
        limit?.callId == callId &&
        limit!.extendable;
    // The first-top-up bonus, asked once each time it comes up: the card
    // says so before Add Money opens (which shows it too).
    final bonusAsk = useMemoized<Future<TopUpBonus?>>(
      () => show ? InCallTopUp.bonus() : Future<TopUpBonus?>.value(),
      [show, callId],
    );
    final bonus = useFuture(bonusAsk).data;
    final bonusPercent = bonus == null ? null : _percent(bonus.percent);
    // Open as a card each time it comes up; closed to the pill by the user.
    final open = useState(true);
    useEffect(() {
      if (show) open.value = true;
      return null;
    }, [show]);
    // The time left, every second while it shows.
    final now = useState(DateTime.now());
    useEffect(() {
      if (!show) return null;
      now.value = DateTime.now();
      final tick = Timer.periodic(
        const Duration(seconds: 1),
        (_) => now.value = DateTime.now(),
      );
      return tick.cancel;
    }, [show]);

    final pad = MediaQuery.paddingOf(context);
    // Just above the controls bar (its bottom, its height, a gap).
    final bottom =
        math.max(pad.bottom, 10) + 10.vs + (video ? 50 : 58).sw + 24.vs + 10.vs;
    Widget child = const SizedBox.shrink(key: ValueKey('call-topup-none'));
    if (show) {
      final left = formatCallTime(limit.leftAt(now.value).inSeconds);
      void add(String from) =>
          unawaited(InCallTopUp.start(context, from: from, hold: onHold));
      child = open.value
          ? _Card(
              key: const ValueKey('call-topup-card'),
              left: left,
              free: limit.freeLimit,
              bonusPercent: bonusPercent,
              onAdd: () => add('prompt'),
              onClose: () => open.value = false,
            )
          : _Pill(
              key: const ValueKey('call-topup-pill'),
              left: left,
              bonusPercent: bonusPercent,
              onAdd: () => add('pill'),
            );
    }
    return Positioned(
      left: 14.sw,
      right: 14.sw,
      bottom: bottom,
      child: AnimatedSwitcher(
        duration: const Duration(milliseconds: 220),
        switchInCurve: Curves.easeOutCubic,
        switchOutCurve: Curves.easeInCubic,
        transitionBuilder: (c, a) => FadeTransition(
          opacity: a,
          child: SlideTransition(
            position: Tween(
              begin: const Offset(0, 0.25),
              end: Offset.zero,
            ).animate(a),
            child: c,
          ),
        ),
        child: child,
      ),
    );
  }
}

class _Card extends StatelessWidget {
  const _Card({
    super.key,
    required this.left,
    required this.free,
    required this.onAdd,
    required this.onClose,
    this.bonusPercent,
  });

  final String left;
  final bool free;
  final VoidCallback onAdd;
  final VoidCallback onClose;

  /// "100": the first-top-up bonus this user gets; null when none.
  final String? bonusPercent;

  @override
  Widget build(BuildContext context) => Container(
    padding: EdgeInsets.fromLTRB(14.ms, 12.ms, 8.ms, 12.ms),
    decoration: BoxDecoration(
      color: AppColors.blackA(0.92),
      borderRadius: BorderRadius.circular(22.ms),
      border: Border.all(color: BrandColors.lime.withValues(alpha: 0.45)),
      boxShadow: [
        BoxShadow(
          color: AppColors.blackA(0.35),
          blurRadius: 20.ms,
          offset: Offset(0, 8.ms),
        ),
      ],
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 36.ms,
              height: 36.ms,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: BrandColors.lime.withValues(alpha: 0.16),
              ),
              child: Icon(
                LucideIcons.wallet,
                size: 17.ms,
                color: BrandColors.lime,
              ),
            ),
            SizedBox(width: 10.ms),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  CText(
                    free ? 'call:topup.free_title' : 'call:topup.title',
                    variables: {'time': left},
                    size: 14,
                    weight: FontWeight.w800,
                    color: AppColors.white,
                    maxLines: 2,
                  ),
                  SizedBox(height: 2.ms),
                  CText(
                    'call:topup.body',
                    size: 11.5,
                    height: 15,
                    weight: FontWeight.w600,
                    color: AppColors.whiteA(0.7),
                    maxLines: 3,
                  ),
                  if (bonusPercent case final percent?) ...[
                    SizedBox(height: 6.ms),
                    Row(
                      key: const ValueKey('call-topup-bonus'),
                      children: [
                        Icon(
                          LucideIcons.gift,
                          size: 14.ms,
                          color: BrandColors.lime,
                        ),
                        SizedBox(width: 5.ms),
                        Flexible(
                          child: CText(
                            'call:topup.bonus',
                            variables: {'percent': percent},
                            size: 12,
                            weight: FontWeight.w800,
                            color: BrandColors.lime,
                            maxLines: 2,
                          ),
                        ),
                      ],
                    ),
                  ],
                ],
              ),
            ),
            Pressable(
              key: const ValueKey('call-topup-close'),
              onPressed: onClose,
              semanticLabel: context.t('call:topup.close'),
              hitPadding: EdgeInsets.all(6.ms),
              child: Padding(
                padding: EdgeInsets.all(4.ms),
                child: Icon(
                  LucideIcons.x,
                  size: 16.ms,
                  color: AppColors.whiteA(0.6),
                ),
              ),
            ),
          ],
        ),
        SizedBox(height: 10.ms),
        // Full width under the words: room for every language.
        Padding(
          padding: EdgeInsetsDirectional.only(end: 6.ms),
          child: Pressable(
            key: const ValueKey('call-topup-add'),
            onPressed: onAdd,
            child: Container(
              padding: EdgeInsets.symmetric(horizontal: 16.ms, vertical: 9.ms),
              decoration: BoxDecoration(
                color: BrandColors.lime,
                borderRadius: BorderRadius.circular(999),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(LucideIcons.plus, size: 15.ms, color: AppColors.black),
                  SizedBox(width: 5.ms),
                  const Flexible(
                    child: CText(
                      'call:topup.add',
                      size: 13.5,
                      weight: FontWeight.w800,
                      color: AppColors.black,
                      maxLines: 1,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    ),
  );
}

class _Pill extends StatelessWidget {
  const _Pill({
    super.key,
    required this.left,
    required this.onAdd,
    this.bonusPercent,
  });

  final String left;

  /// "+100%" beside the words when there is a first-top-up bonus.
  final String? bonusPercent;
  final VoidCallback onAdd;

  @override
  Widget build(BuildContext context) => Center(
    child: Pressable(
      key: const ValueKey('call-topup-pill-add'),
      onPressed: onAdd,
      child: Container(
        padding: EdgeInsets.symmetric(horizontal: 14.ms, vertical: 8.ms),
        decoration: BoxDecoration(
          color: AppColors.blackA(0.85),
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: BrandColors.lime.withValues(alpha: 0.45)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(LucideIcons.wallet, size: 14.ms, color: BrandColors.lime),
            SizedBox(width: 6.ms),
            Flexible(
              child: CText(
                'call:topup.pill',
                variables: {'time': left},
                size: 12.5,
                weight: FontWeight.w800,
                color: AppColors.white,
                maxLines: 1,
              ),
            ),
            if (bonusPercent case final percent?) ...[
              SizedBox(width: 6.ms),
              Container(
                key: const ValueKey('call-topup-pill-bonus'),
                padding: EdgeInsets.symmetric(horizontal: 6.ms, vertical: 2.ms),
                decoration: BoxDecoration(
                  color: BrandColors.lime,
                  borderRadius: BorderRadius.circular(999),
                ),
                child: CText.raw(
                  '+$percent%',
                  size: 11,
                  weight: FontWeight.w900,
                  color: AppColors.black,
                  maxLines: 1,
                ),
              ),
            ],
          ],
        ),
      ),
    ),
  );
}

/// 100.0 → "100", 12.5 → "12.5".
String _percent(double p) =>
    p == p.roundToDouble() ? p.toInt().toString() : p.toString();
