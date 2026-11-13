import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../../core/analytics/analytics.dart';
import '../../../../core/analytics/events/payment_events.dart';
import '../../../../core/analytics/screen_tracker.dart';
import '../../../../core/i18n/i18n.dart';
import '../../../../core/network/api_exception.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/utils/scale.dart';
import '../../../api/paymentscreen/checkout_models.dart';
import '../../../api/paymentscreen/payment_queries.dart';
import '../../../api/paymentscreen/runtime_config_queries.dart';
import '../../../component/c_alert.dart';
import '../../../component/c_text.dart';
import '../../../component/vibe_background.dart';
import '../helper/first_topup_offer.dart';
import '../helper/topup_bonus.dart';
import '../helper/topup_checkout.dart';
import '../helper/wallet_amounts.dart';
import '../helper/wallet_format.dart';
import '../helper/wallet_palette.dart';
import 'offer_parts.dart';
import 'wallet_header.dart';

/// How the add-money screen closed: an order to pay, or "profile
/// incomplete" (the wallet shows that alert). Null: closed by the user.
typedef AddMoneyExit = ({RechargeCheckout? checkout, bool profileIncomplete});

/// Full-screen "Add Money" (slides up), in the first-top-up popup's look:
/// the amounts as tiles (lowest first, one always picked), a plain "You pay
/// → Wallet gets" with the GST spelled out, and one "Pay ₹X" button. Then
/// the backend order. [initialAmount] pre-fills it (the call balance gate,
/// the first-top-up and exit-intent offers). [source]: what opened it
/// (analytics).
Future<AddMoneyExit?> showAddMoney(
  BuildContext context, {
  required TopUpCheckout flow,
  required PayerInfo Function() payer,
  double? initialAmount,
  TopUpBonus? bonus,
  String source = 'wallet',
}) => showGeneralDialog<AddMoneyExit>(
  context: context,
  routeSettings: ScreenTracker.sheet('add_money_sheet'),
  barrierDismissible: false,
  barrierColor: AppColors.transparent,
  transitionDuration: const Duration(milliseconds: 280),
  transitionBuilder: (_, anim, _, child) => SlideTransition(
    position: Tween(
      begin: const Offset(0, 1),
      end: Offset.zero,
    ).animate(CurvedAnimation(parent: anim, curve: Curves.easeOutCubic)),
    child: child,
  ),
  pageBuilder: (_, _, _) => _AddMoneyScreen(
    flow: flow,
    payer: payer,
    initialAmount: initialAmount,
    bonus: bonus,
    source: source,
  ),
);

class _AddMoneyScreen extends HookWidget {
  const _AddMoneyScreen({
    required this.flow,
    required this.payer,
    this.initialAmount,
    this.bonus,
    this.source = 'wallet',
  });

  final TopUpCheckout flow;
  final PayerInfo Function() payer;
  final double? initialAmount;
  final String source;

  /// Previewed on the tiles and in the summary (first top-up, come-back).
  final TopUpBonus? bonus;

  @override
  Widget build(BuildContext context) {
    final p = WalletPalette.of(context);
    final config = useRuntimeConfig(context);
    final balance = useWalletBalance(context).data?.cashBalance;
    final still = MediaQuery.disableAnimationsOf(context);
    // The button's shine.
    final loop = useAnimationController(
      duration: const Duration(milliseconds: 2200),
    );
    useEffect(() {
      if (!still) loop.repeat();
      return null;
    }, [still]);

    // An exact amount handed in (call balance gate, an offer) is picked; one
    // that isn't a preset gets its own tile. Lowest first.
    final initial = initialAmount;
    final prefill = initial != null && initial.isFinite && initial > 0
        ? initial.ceil()
        : null;
    final presets = config.presetAmounts;
    final options = FirstTopupOffer.amounts([...presets, ?prefill]);
    final popular = FirstTopupOffer.suggested(options);
    // Always one picked, so the total and the button are always there.
    final selected = useValueNotifier<int?>(prefill ?? popular);
    final loading = useValueNotifier<bool>(false);
    // Analytics: the last picked amount, and whether an order came out.
    final picked = useRef<int?>(selected.value);
    final ordered = useRef(false);
    useEffect(() {
      final b = bonus;
      final kind = switch (b?.kind) {
        TopUpBonusKind.firstTopup => 'first_topup',
        TopUpBonusKind.comeback => 'comeback',
        null => null,
      };
      PaymentEvents.addMoneyOpened(
        source: source,
        prefillAmount: prefill,
        bonusKind: kind,
        bonusPercent: b?.percent,
        presetCount: options.length,
      );
      if (b != null && kind != null && b.percent > 0) {
        PaymentEvents.topupBonusShown(kind: kind, percent: b.percent);
      }
      return () {
        if (!ordered.value) {
          PaymentEvents.addMoneyClosed(selectedAmount: picked.value);
        }
      };
    }, const []);

    void pick(int value) {
      if (selected.value == value) return;
      selected.value = value;
      picked.value = value;
      PaymentEvents.amountSelected(
        amount: value,
        kind: presets.contains(value) ? 'preset' : 'prefill',
        selected: true,
        bonusPercent: bonus?.percent,
        position: options.indexOf(value),
      );
    }

    Future<void> submit() async {
      final amount = selected.value;
      if (loading.value || amount == null) return;
      final who = payer();
      PaymentEvents.payTapped(
        amount: amount,
        gstPercent: config.gstPercent,
        total: TopUpAmount.breakdown(
          amount.toDouble(),
          config.gstPercent,
        ).total,
        bonus: bonus?.on(amount),
      );
      if ((who.name ?? '').isEmpty || (who.email ?? '').isEmpty) {
        ordered.value = true; // the wallet logs the profile prompt
        Navigator.of(context).pop((checkout: null, profileIncomplete: true));
        return;
      }
      loading.value = true;
      try {
        final checkout = await flow.createOrder(
          amount: amount.toDouble(),
          payer: who,
          description: context.t('payment:add_money.description'),
          gstPercent: config.gstPercent,
        );
        ordered.value = true;
        PaymentEvents.orderCreated(
          amount: amount,
          gateway: checkout.gateway.name,
          orderId: checkout.txnId,
        );
        if (context.mounted) {
          Navigator.of(
            context,
          ).pop((checkout: checkout, profileIncomplete: false));
        }
      } on ApiException catch (e) {
        PaymentEvents.orderFailed(
          amount: amount,
          error: Analytics.errorCode(e),
        );
        unawaited(CAlert.error(e));
      } finally {
        if (context.mounted) loading.value = false;
      }
    }

    final b = bonus;
    return Material(
      color: p.bg,
      child: Stack(
        children: [
          const VibeBackground(),
          SafeArea(
            child: Column(
              children: [
                _Header(balance: balance),
                Expanded(
                  child: SingleChildScrollView(
                    padding: EdgeInsets.fromLTRB(16.ms, 4.ms, 16.ms, 20.ms),
                    child: ValueListenableBuilder<int?>(
                      valueListenable: selected,
                      builder: (_, amount, _) => Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          if (b != null && b.percent > 0) ...[
                            _BonusBanner(bonus: b),
                            SizedBox(height: 18.ms),
                          ],
                          CText(
                            'payment:add_money.pick',
                            size: 12,
                            weight: FontWeight.w800,
                            color: p.muted,
                            letterSpacing: 0.5,
                          ),
                          SizedBox(height: 14.ms),
                          OfferAmountGrid(
                            keyPrefix: 'add-money-amount',
                            // Cards on the screen's tinted background.
                            tileColor: Color.alphaBlend(p.cardBg, p.bg),
                            amounts: options,
                            chosen: amount,
                            popular: popular,
                            bonusOf: b == null || b.percent <= 0 ? null : b.on,
                            onPick: pick,
                          ),
                          if (amount != null) ...[
                            SizedBox(height: 18.ms),
                            _GstNote(
                              amount: amount.toDouble(),
                              gstPercent: config.gstPercent,
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),
                ),
                // Pinned: what you pay and what the wallet gets, and the
                // button, always in view; only the amounts scroll.
                Container(
                  key: const ValueKey('add-money-bar'),
                  padding: EdgeInsets.fromLTRB(16.ms, 12.ms, 16.ms, 8.ms),
                  decoration: BoxDecoration(
                    color: p.bg,
                    border: Border(top: BorderSide(color: p.cardBorder)),
                  ),
                  child: ValueListenableBuilder<int?>(
                    valueListenable: selected,
                    builder: (_, amount, _) {
                      final total = amount == null
                          ? 0.0
                          : TopUpAmount.breakdown(
                              amount.toDouble(),
                              config.gstPercent,
                            ).total;
                      return Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          if (amount != null) ...[
                            _Summary(
                              amount: amount.toDouble(),
                              gstPercent: config.gstPercent,
                              bonus: b,
                            ),
                            SizedBox(height: 10.ms),
                          ],
                          ValueListenableBuilder<bool>(
                            valueListenable: loading,
                            builder: (_, busy, _) => OfferShineButton(
                              key: const ValueKey('add-money-pay'),
                              loop: loop,
                              icon: LucideIcons.lock,
                              label: context.t(
                                'payment:add_money.pay',
                                variables: {
                                  'total': WalletFormat.rupees(total),
                                },
                              ),
                              enabled: amount != null,
                              loading: busy,
                              onTap: submit,
                            ),
                          ),
                          SizedBox(height: 8.ms),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(
                                LucideIcons.shieldCheck,
                                size: 13.ms,
                                color: OfferColors.green,
                              ),
                              SizedBox(width: 5.ms),
                              Flexible(
                                child: CText(
                                  'payment:add_money.secure',
                                  size: 11,
                                  weight: FontWeight.w700,
                                  color: p.muted,
                                  maxLines: 1,
                                ),
                              ),
                            ],
                          ),
                        ],
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Close, the title, and under it what is in the call balance now.
class _Header extends StatelessWidget {
  const _Header({required this.balance});

  final double? balance;

  @override
  Widget build(BuildContext context) {
    final p = WalletPalette.of(context);
    final now = balance;
    return Padding(
      padding: EdgeInsets.fromLTRB(16.ms, 12.ms, 16.ms, 14.ms),
      child: Row(
        children: [
          WalletIconButton(
            icon: LucideIcons.x,
            semanticLabel: context.t('actions.close'),
            onPressed: () => Navigator.of(context).pop(),
          ),
          SizedBox(width: 14.ms),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                CText(
                  'payment:add_money.title',
                  size: 22,
                  weight: FontWeight.w900,
                  letterSpacing: -0.5,
                  color: p.text,
                  maxLines: 1,
                ),
                if (now != null)
                  Padding(
                    key: const ValueKey('add-money-balance'),
                    padding: EdgeInsets.only(top: 2.ms),
                    child: Row(
                      children: [
                        Icon(LucideIcons.wallet, size: 13.ms, color: p.muted),
                        SizedBox(width: 5.ms),
                        // A big balance shrinks to fit the line.
                        Flexible(
                          child: FittedBox(
                            fit: BoxFit.scaleDown,
                            alignment: AlignmentDirectional.centerStart,
                            child: CText(
                              'payment:add_money.balance',
                              variables: {'amount': WalletFormat.amount(now)},
                              size: 12.5,
                              weight: FontWeight.w700,
                              color: p.muted,
                              maxLines: 1,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// The bonus this top-up gets, on the hot gradient (first top-up: the
/// popup's "FIRST RECHARGE OFFER"; come-back: the extra still waiting).
class _BonusBanner extends StatelessWidget {
  const _BonusBanner({required this.bonus});

  final TopUpBonus bonus;

  @override
  Widget build(BuildContext context) {
    final o = OfferColors.of(context);
    final pct = WalletFormat.js(bonus.percent);
    final first = bonus.kind == TopUpBonusKind.firstTopup;
    return Container(
      key: const ValueKey('add-money-bonus'),
      padding: EdgeInsets.fromLTRB(14.ms, 12.ms, 14.ms, 12.ms),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: o.gradient,
        ),
        borderRadius: BorderRadius.circular(18.ms),
        boxShadow: o.glow([
          BoxShadow(
            color: o.accent.withValues(alpha: 0.3),
            blurRadius: 16,
            offset: const Offset(0, 6),
          ),
        ]),
      ),
      child: Row(
        children: [
          Container(
            width: 42.ms,
            height: 42.ms,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: Colors.white,
              boxShadow: o.glow([
                BoxShadow(
                  color: OfferColors.gold.withValues(alpha: 0.7),
                  blurRadius: 14,
                  spreadRadius: 2,
                ),
              ]),
            ),
            child: Icon(LucideIcons.gift, size: 21.ms, color: o.ink),
          ),
          SizedBox(width: 12.ms),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: AlignmentDirectional.centerStart,
                  child: CText(
                    'payment:first_topup.extra',
                    variables: {'percent': pct},
                    size: 20,
                    weight: FontWeight.w900,
                    color: o.onAccent,
                    maxLines: 1,
                  ),
                ),
                SizedBox(height: 2.ms),
                CText(
                  first
                      ? 'payment:add_money.bonus_instant'
                      : 'payment:add_money.bonus_comeback',
                  variables: {'percent': pct},
                  size: 11.5,
                  weight: FontWeight.w600,
                  color: o.onAccent.withValues(alpha: 0.92),
                  maxLines: 2,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Under the amounts: GST is a tax on top of the recharge, and the whole
/// recharge reaches the wallet.
class _GstNote extends StatelessWidget {
  const _GstNote({required this.amount, required this.gstPercent});

  final double amount;
  final double gstPercent;

  @override
  Widget build(BuildContext context) {
    final p = WalletPalette.of(context);
    final b = TopUpAmount.breakdown(amount, gstPercent);
    if (b.base <= 0 || b.gst <= 0) return const SizedBox.shrink();
    return Row(
      key: const ValueKey('add-money-gst-note'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: EdgeInsets.only(top: 1.ms),
          child: Icon(LucideIcons.info, size: 13.ms, color: p.muted),
        ),
        SizedBox(width: 6.ms),
        Expanded(
          child: CText(
            'payment:add_money.gst_note',
            variables: {
              'percent': WalletFormat.js(gstPercent),
              'amount': WalletFormat.whole(b.base),
            },
            size: 11.5,
            weight: FontWeight.w600,
            color: p.muted,
          ),
        ),
      ],
    );
  }
}

/// Pinned above the Pay button: "You pay ₹590 (incl. ₹90 GST) → Wallet gets
/// ₹750 (incl. ₹250 bonus)", the wallet figure counting as the pick changes.
class _Summary extends StatelessWidget {
  const _Summary({required this.amount, required this.gstPercent, this.bonus});

  final double amount;
  final double gstPercent;
  final TopUpBonus? bonus;

  @override
  Widget build(BuildContext context) {
    final p = WalletPalette.of(context);
    final b = TopUpAmount.breakdown(amount, gstPercent);
    if (b.base <= 0) return const SizedBox.shrink();
    final extra = bonus?.on(b.base) ?? 0;
    final gets = b.base + extra;
    const green = OfferColors.green;

    Widget side(String label, Widget value, Widget? note) => Expanded(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          CText(
            label,
            size: 11,
            weight: FontWeight.w700,
            color: p.muted,
            maxLines: 1,
          ),
          SizedBox(height: 1.ms),
          FittedBox(fit: BoxFit.scaleDown, child: value),
          if (note != null) ...[
            SizedBox(height: 1.ms),
            FittedBox(fit: BoxFit.scaleDown, child: note),
          ],
        ],
      ),
    );

    return Container(
      key: const ValueKey('add-money-summary'),
      padding: EdgeInsets.symmetric(vertical: 10.ms, horizontal: 10.ms),
      decoration: BoxDecoration(
        color: Color.alphaBlend(
          green.withValues(alpha: p.dark ? 0.12 : 0.07),
          Color.alphaBlend(p.cardBg, p.bg),
        ),
        borderRadius: BorderRadius.circular(16.ms),
        border: Border.all(color: green.withValues(alpha: 0.35)),
      ),
      // Top-aligned: the two figures line up whether or not a side has a
      // note under it.
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          side(
            'payment:add_money.you_pay',
            CText.raw(
              '₹${WalletFormat.rupees(b.total)}',
              size: 19,
              weight: FontWeight.w900,
              color: p.text,
              maxLines: 1,
            ),
            b.gst > 0
                ? CText(
                    'payment:add_money.incl_gst',
                    variables: {'gst': WalletFormat.rupees(b.gst)},
                    size: 10.5,
                    weight: FontWeight.w600,
                    color: p.muted,
                    maxLines: 1,
                  )
                : null,
          ),
          Padding(
            padding: EdgeInsets.only(top: 18.ms),
            child: Icon(LucideIcons.arrowRight, size: 18.ms, color: green),
          ),
          side(
            'payment:add_money.wallet_gets',
            TweenAnimationBuilder<double>(
              tween: Tween(end: gets),
              duration: const Duration(milliseconds: 380),
              curve: Curves.easeOutCubic,
              builder: (_, value, _) => CText.raw(
                '₹${WalletFormat.whole(value.round())}',
                key: const ValueKey('add-money-gets'),
                size: 21,
                weight: FontWeight.w900,
                color: green,
                maxLines: 1,
              ),
            ),
            // "incl. ₹4,000 bonus", like "incl. ₹90 GST" opposite: never
            // "₹4,000 + ₹4,000", which reads as two of the same.
            extra > 0
                ? CText(
                    'payment:add_money.incl_bonus',
                    variables: {'bonus': WalletFormat.whole(extra)},
                    size: 10.5,
                    weight: FontWeight.w700,
                    color: green,
                    maxLines: 1,
                  )
                : null,
          ),
        ],
      ),
    );
  }
}
