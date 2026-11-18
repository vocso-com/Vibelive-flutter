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
import '../../paymentscreen/wallet/helper/topup_checkout.dart';
import '../helper/call_billing.dart';
import '../helper/call_controller.dart';
import '../helper/engine/call_engine.dart';
import 'helper/call_format.dart';
import 'helper/call_select.dart';

/// "Add money" in the middle of a call (the caller's balance or free
/// minutes run out in [CallBilling.topUpLead]): the wallet's own Add Money
/// over the call, which goes on meanwhile; the call is moved to the speaker
/// while the screen is needed, and back to the earpiece after; money added
/// moves the call's end at once ([CallBilling.rearm]).
abstract final class InCallTopUp {
  /// Re-read once more this long after a payment the server had not
  /// confirmed yet.
  static const pendingRecheck = Duration(seconds: 8);

  static bool _running = false;

  /// The wallet's Add Money (tests swap it).
  @visibleForTesting
  static Future<TopUpResult?> Function(BuildContext context) pay = _pay;

  static Future<TopUpResult?> _pay(BuildContext context) =>
      AddMoneyFlow.run(context, source: 'in_call');

  @visibleForTesting
  static void debugReset() {
    _running = false;
    pay = _pay;
  }

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
    final engine = CallEngine.instance;
    // The phone leaves the ear to pay: the talk goes on through the speaker
    // (not when a headset or Bluetooth carries it).
    final speaker = !engine.media.value.speakerOn && !engine.audioOnAccessory;
    TopUpResult? result;
    var extended = false;
    try {
      if (speaker) await engine.setSpeaker(true);
      CallUiEvents.topUpTapped(from: from, speaker: speaker);
      final before = CallBilling.limit.value?.endsAt;
      if (!context.mounted) return;
      result = await pay(context);
      if (result == TopUpResult.success || result == TopUpResult.pending) {
        await CallBilling.rearm(callId);
        final after = CallBilling.limit.value;
        extended =
            after != null &&
            after.callId == callId &&
            (before == null || after.endsAt.isAfter(before));
        if (result == TopUpResult.pending) {
          // Paid, not confirmed yet: the balance once more, shortly.
          unawaited(
            Future<void>.delayed(
              pendingRecheck,
              () => CallBilling.rearm(callId),
            ),
          );
        }
      }
    } finally {
      _running = false;
      CallUiEvents.topUpFinished(
        result: result?.name ?? 'closed',
        extended: extended,
      );
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
              onAdd: () => add('prompt'),
              onClose: () => open.value = false,
            )
          : _Pill(
              key: const ValueKey('call-topup-pill'),
              left: left,
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
  });

  final String left;
  final bool free;
  final VoidCallback onAdd;
  final VoidCallback onClose;

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
  const _Pill({super.key, required this.left, required this.onAdd});

  final String left;
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
          ],
        ),
      ),
    ),
  );
}
