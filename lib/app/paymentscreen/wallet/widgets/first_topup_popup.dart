import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../../core/analytics/events/payment_events.dart';
import '../../../../core/analytics/screen_tracker.dart';
import '../../../../core/i18n/i18n.dart';
import '../../../../core/utils/scale.dart';
import '../../../api/promo_banner/promo_content.dart';
import '../../../component/c_text.dart';
import '../../../component/pressable.dart';
import '../../../promo/promo_effects.dart';
import '../../../api/paymentscreen/billing_models.dart';
import '../helper/first_topup_offer.dart';
import '../helper/wallet_amounts.dart';
import '../helper/wallet_format.dart';
import '../helper/wallet_palette.dart';
import 'offer_parts.dart';

/// What the first-top-up popup offers: the bonus percent and every amount
/// the wallet sells (the admin's presets).
@immutable
class FirstTopupPlan {
  const FirstTopupPlan({
    required this.percent,
    required this.amounts,
    this.voiceRate = 0,
    this.gstPercent = GstConfig.defaultIgstRate,
  });

  final double percent;
  final List<int> amounts;

  /// The top-up GST (runtime config): what is paid on top of the amount,
  /// exactly as the order is made (the Add Money sheet's maths).
  final double gstPercent;

  /// Per-minute floor, for "about N minutes of talking" (0: not shown).
  final double voiceRate;

  int? get suggested => FirstTopupOffer.suggested(amounts);
}

/// The first-top-up offer as the app-open popup: a bright card that grows in
/// over a dim, a confetti hero with the bonus, every amount the wallet sells
/// (each with its free extra, the middle one marked popular), what the money
/// becomes, and one shimmering button. Resolves with the amount chosen, or
/// null when closed.
Future<int?> showFirstTopupPopup(BuildContext context, FirstTopupPlan plan) {
  final still = MediaQuery.disableAnimationsOf(context);
  return showGeneralDialog<int>(
    context: context,
    routeSettings: ScreenTracker.sheet('first_topup_offer_popup'),
    barrierDismissible: false,
    barrierColor: Colors.black.withValues(alpha: 0.62),
    transitionDuration: Duration(milliseconds: still ? 120 : 460),
    pageBuilder: (ctx, _, _) => _FirstTopupPopup(plan: plan),
    transitionBuilder: (ctx, animation, _, child) {
      if (still) return FadeTransition(opacity: animation, child: child);
      final grow = CurvedAnimation(
        parent: animation,
        curve: const Cubic(0.34, 1.4, 0.64, 1),
        reverseCurve: Curves.easeIn,
      );
      return FadeTransition(
        opacity: CurvedAnimation(parent: animation, curve: Curves.easeOut),
        child: ScaleTransition(
          scale: Tween(begin: 0.82, end: 1.0).animate(grow),
          child: child,
        ),
      );
    },
  );
}

const _gold = OfferColors.gold;
const _green = OfferColors.green;

class _FirstTopupPopup extends HookWidget {
  const _FirstTopupPopup({required this.plan});

  final FirstTopupPlan plan;

  @override
  Widget build(BuildContext context) {
    final p = WalletPalette.of(context);
    final still = MediaQuery.disableAnimationsOf(context);
    // One clock for the gift's bob, its glow and the button's shine.
    final loop = useAnimationController(duration: const Duration(seconds: 2));
    useEffect(() {
      if (!still) loop.repeat();
      return null;
    }, [still]);

    final selected = useState<int?>(plan.suggested);
    final chosen = selected.value ?? plan.suggested ?? 0;
    final preview = BonusPreview.of(chosen, plan.percent);
    final pct = WalletFormat.js(plan.percent);
    final minutes = plan.voiceRate > 0
        ? (preview.total / plan.voiceRate).floor()
        : 0;
    final size = MediaQuery.sizeOf(context);
    final width = math.min(size.width - 32.ms, 350.0);

    return Center(
      child: Padding(
        padding: EdgeInsets.symmetric(vertical: 16.ms),
        child: Material(
          type: MaterialType.transparency,
          child: ConstrainedBox(
            constraints: BoxConstraints(
              maxWidth: width,
              maxHeight: size.height - 32.ms,
            ),
            child: Container(
              key: const ValueKey('first-topup-popup'),
              clipBehavior: Clip.antiAlias,
              decoration: BoxDecoration(
                // Opaque in both themes (the dark surface is a tint).
                color: Color.alphaBlend(p.cardBg, p.bg),
                borderRadius: BorderRadius.circular(24.ms),
                boxShadow: [
                  BoxShadow(
                    color: OfferColors.of(
                      context,
                    ).accent.withValues(alpha: 0.4),
                    blurRadius: 40,
                    spreadRadius: -6,
                    offset: const Offset(0, 18),
                  ),
                ],
              ),
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _Hero(
                      percent: pct,
                      loop: loop,
                      onClose: () => Navigator.of(context).pop(),
                    ),
                    Padding(
                      padding: EdgeInsets.fromLTRB(14.ms, 12.ms, 14.ms, 4.ms),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          CText(
                            'payment:first_topup.pick',
                            size: 11,
                            weight: FontWeight.w800,
                            color: p.muted,
                            align: TextAlign.center,
                            letterSpacing: 0.4,
                          ),
                          SizedBox(height: 10.ms),
                          OfferAmountGrid(
                            keyPrefix: 'first-topup-amount',
                            amounts: plan.amounts,
                            bonusOf: (a) =>
                                BonusPreview.of(a, plan.percent).bonus,
                            chosen: chosen,
                            popular: plan.suggested,
                            onPick: (value) {
                              selected.value = value;
                              PaymentEvents.firstTopupOfferOption(
                                amount: value,
                                percent: plan.percent,
                              );
                            },
                          ),
                          SizedBox(height: 10.ms),
                          _Becomes(
                            preview: preview,
                            gst: TopUpAmount.breakdown(
                              preview.amount,
                              plan.gstPercent,
                            ),
                            minutes: minutes,
                          ),
                          SizedBox(height: 10.ms),
                          OfferShineButton(
                            key: const ValueKey('first-topup-cta'),
                            loop: loop,
                            label: context.t(
                              // What the wallet gets, bonus included
                              // ("Add ₹1,000 & get ₹2,000").
                              'payment:offer.cta',
                              variables: {
                                'amount': WalletFormat.whole(preview.amount),
                                'total': WalletFormat.whole(
                                  preview.total.round(),
                                ),
                              },
                            ),
                            enabled: chosen > 0,
                            onTap: () => Navigator.of(context).pop(chosen),
                          ),
                          SizedBox(height: 2.ms),
                          Pressable(
                            key: const ValueKey('first-topup-later'),
                            onPressed: () => Navigator.of(context).pop(),
                            child: Padding(
                              padding: EdgeInsets.symmetric(vertical: 8.ms),
                              child: CText(
                                'payment:first_topup.not_now',
                                size: 12.5,
                                weight: FontWeight.w700,
                                color: p.muted,
                                align: TextAlign.center,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Confetti over the hot gradient, a bobbing gift in a glowing ring, the
/// bonus in big type and a close button.
class _Hero extends StatelessWidget {
  const _Hero({
    required this.percent,
    required this.loop,
    required this.onClose,
  });

  final String percent;
  final Animation<double> loop;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    final o = OfferColors.of(context);
    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: o.gradient,
        ),
      ),
      child: Stack(
        children: [
          const Positioned.fill(
            child: IgnorePointer(
              child: PromoEffectLayer(
                effect: PromoEffect.confetti,
                color: Colors.white,
              ),
            ),
          ),
          Padding(
            padding: EdgeInsets.fromLTRB(18.ms, 14.ms, 18.ms, 14.ms),
            child: Column(
              children: [
                AnimatedBuilder(
                  animation: loop,
                  builder: (_, child) {
                    final t = math.sin(loop.value * math.pi * 2);
                    return Transform.translate(
                      offset: Offset(0, -4 * t),
                      child: Transform.rotate(angle: 0.06 * t, child: child),
                    );
                  },
                  child: Container(
                    width: 54.ms,
                    height: 54.ms,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: Colors.white,
                      boxShadow: [
                        BoxShadow(
                          color: _gold.withValues(alpha: 0.75),
                          blurRadius: 20,
                          spreadRadius: 3,
                        ),
                      ],
                    ),
                    child: Icon(LucideIcons.gift, size: 27.ms, color: o.ink),
                  ),
                ),
                SizedBox(height: 9.ms),
                Container(
                  padding: EdgeInsets.symmetric(
                    horizontal: 10.ms,
                    vertical: 3.ms,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.18),
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: CText(
                    'payment:first_topup.badge',
                    size: 10,
                    weight: FontWeight.w900,
                    color: o.onAccent,
                    letterSpacing: 1.2,
                    maxLines: 1,
                  ),
                ),
                SizedBox(height: 5.ms),
                // A long language shrinks to fit rather than being cut.
                FittedBox(
                  fit: BoxFit.scaleDown,
                  child: CText(
                    'payment:first_topup.extra',
                    variables: {'percent': percent},
                    size: 31,
                    weight: FontWeight.w900,
                    color: o.onAccent,
                    height: 36,
                    maxLines: 1,
                    align: TextAlign.center,
                    style: const TextStyle(
                      shadows: [
                        Shadow(color: Color(0x55000000), blurRadius: 10),
                      ],
                    ),
                  ),
                ),
                SizedBox(height: 3.ms),
                CText(
                  'payment:first_topup.hero',
                  variables: {'percent': percent},
                  maxLines: 2,
                  size: 12,
                  weight: FontWeight.w600,
                  color: o.onAccent.withValues(alpha: 0.92),
                  align: TextAlign.center,
                ),
              ],
            ),
          ),
          Positioned(
            top: 8.ms,
            right: 8.ms,
            child: Pressable(
              key: const ValueKey('first-topup-close'),
              onPressed: onClose,
              child: Container(
                width: 30.ms,
                height: 30.ms,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: Colors.black.withValues(alpha: 0.2),
                ),
                child: Icon(LucideIcons.x, size: 16.ms, color: o.onAccent),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// "You pay ₹1,180 (incl. ₹180 GST) → You get ₹2,000 (incl. ₹1,000 bonus)":
/// what the gateway charges and what lands in the wallet, the total counting
/// up as the pick changes.
class _Becomes extends StatelessWidget {
  const _Becomes({
    required this.preview,
    required this.gst,
    required this.minutes,
  });

  final BonusPreview preview;
  final GstBreakdown gst;
  final int minutes;

  @override
  Widget build(BuildContext context) {
    final p = WalletPalette.of(context);
    Widget side(String label, Widget value, Widget? note) => Expanded(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          CText(
            label,
            size: 10,
            weight: FontWeight.w700,
            color: p.muted,
            maxLines: 1,
          ),
          SizedBox(height: 1.ms),
          FittedBox(fit: BoxFit.scaleDown, child: value),
          if (note != null) FittedBox(fit: BoxFit.scaleDown, child: note),
        ],
      ),
    );
    return Container(
      padding: EdgeInsets.symmetric(vertical: 8.ms, horizontal: 10.ms),
      decoration: BoxDecoration(
        color: _green.withValues(alpha: p.dark ? 0.12 : 0.07),
        borderRadius: BorderRadius.circular(14.ms),
        border: Border.all(color: _green.withValues(alpha: 0.35)),
      ),
      child: Column(
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              side(
                'payment:first_topup.you_pay',
                CText.raw(
                  '₹${WalletFormat.rupees(gst.total)}',
                  key: const ValueKey('first-topup-pay'),
                  size: 15,
                  weight: FontWeight.w800,
                  color: p.text,
                  maxLines: 1,
                ),
                gst.gst > 0
                    ? CText(
                        'payment:add_money.incl_gst',
                        variables: {'gst': WalletFormat.rupees(gst.gst)},
                        size: 9.5,
                        weight: FontWeight.w600,
                        color: p.muted,
                        maxLines: 1,
                      )
                    : null,
              ),
              Padding(
                padding: EdgeInsets.only(top: 14.ms),
                child: Icon(LucideIcons.arrowRight, size: 17.ms, color: _green),
              ),
              side(
                'payment:first_topup.you_get',
                TweenAnimationBuilder<double>(
                  tween: Tween(end: preview.total),
                  duration: const Duration(milliseconds: 420),
                  curve: Curves.easeOutCubic,
                  builder: (_, value, _) => CText.raw(
                    '₹${WalletFormat.whole(value.round())}',
                    key: const ValueKey('first-topup-total'),
                    size: 18,
                    weight: FontWeight.w900,
                    color: _green,
                    maxLines: 1,
                  ),
                ),
                preview.bonus > 0
                    ? CText(
                        'payment:add_money.incl_bonus',
                        variables: {'bonus': WalletFormat.whole(preview.bonus)},
                        size: 9.5,
                        weight: FontWeight.w700,
                        color: _green,
                        maxLines: 1,
                      )
                    : null,
              ),
            ],
          ),
          if (minutes > 0) ...[
            SizedBox(height: 3.ms),
            CText(
              'payment:first_topup.minutes',
              variables: {'minutes': '$minutes'},
              size: 10.5,
              color: p.muted,
              align: TextAlign.center,
            ),
          ],
        ],
      ),
    );
  }
}
