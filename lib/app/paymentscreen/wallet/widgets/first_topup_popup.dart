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
import '../helper/first_topup_offer.dart';
import '../helper/wallet_format.dart';
import '../helper/wallet_palette.dart';

/// What the first-top-up popup offers: the bonus percent and every amount
/// the wallet sells (the admin's presets).
@immutable
class FirstTopupPlan {
  const FirstTopupPlan({
    required this.percent,
    required this.amounts,
    this.voiceRate = 0,
  });

  final double percent;
  final List<int> amounts;

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

/// Hot pink → orange: the offer reads as a celebration in both themes.
const _hero = [Color(0xFFFF2D87), Color(0xFFFF5E3A), Color(0xFFFFA726)];
const _gold = Color(0xFFFFD54F);
const _green = Color(0xFF16C784);

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
    final width = math.min(size.width - 32.ms, 380.0);

    return Center(
      child: Padding(
        padding: EdgeInsets.symmetric(vertical: 24.ms),
        child: Material(
          type: MaterialType.transparency,
          child: ConstrainedBox(
            constraints: BoxConstraints(
              maxWidth: width,
              maxHeight: size.height - 48.ms,
            ),
            child: Container(
              key: const ValueKey('first-topup-popup'),
              clipBehavior: Clip.antiAlias,
              decoration: BoxDecoration(
                // Opaque in both themes (the dark surface is a tint).
                color: Color.alphaBlend(p.cardBg, p.bg),
                borderRadius: BorderRadius.circular(28.ms),
                boxShadow: [
                  BoxShadow(
                    color: _hero.first.withValues(alpha: 0.45),
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
                      padding: EdgeInsets.fromLTRB(16.ms, 16.ms, 16.ms, 10.ms),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          CText(
                            'payment:first_topup.pick',
                            size: 13,
                            weight: FontWeight.w800,
                            color: p.muted,
                            align: TextAlign.center,
                            letterSpacing: 0.4,
                          ),
                          SizedBox(height: 12.ms),
                          _AmountGrid(
                            amounts: plan.amounts,
                            percent: plan.percent,
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
                          SizedBox(height: 14.ms),
                          _Becomes(preview: preview, minutes: minutes),
                          SizedBox(height: 14.ms),
                          _ShineButton(
                            loop: loop,
                            label: context.t(
                              'payment:offer.cta',
                              variables: {
                                'amount': WalletFormat.js(preview.amount),
                                'bonus': '${preview.bonus}',
                              },
                            ),
                            enabled: chosen > 0,
                            onTap: () => Navigator.of(context).pop(chosen),
                          ),
                          SizedBox(height: 4.ms),
                          Pressable(
                            key: const ValueKey('first-topup-later'),
                            onPressed: () => Navigator.of(context).pop(),
                            child: Padding(
                              padding: EdgeInsets.symmetric(vertical: 10.ms),
                              child: CText(
                                'payment:first_topup.not_now',
                                size: 13,
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
    return DecoratedBox(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: _hero,
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
            padding: EdgeInsets.fromLTRB(20.ms, 22.ms, 20.ms, 20.ms),
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
                    width: 74.ms,
                    height: 74.ms,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: Colors.white,
                      boxShadow: [
                        BoxShadow(
                          color: _gold.withValues(alpha: 0.75),
                          blurRadius: 26,
                          spreadRadius: 4,
                        ),
                      ],
                    ),
                    child: Icon(
                      LucideIcons.gift,
                      size: 36.ms,
                      color: _hero.first,
                    ),
                  ),
                ),
                SizedBox(height: 14.ms),
                Container(
                  padding: EdgeInsets.symmetric(
                    horizontal: 12.ms,
                    vertical: 5.ms,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.18),
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: const CText(
                    'payment:first_topup.badge',
                    size: 11,
                    weight: FontWeight.w900,
                    color: Colors.white,
                    letterSpacing: 1.2,
                    maxLines: 1,
                  ),
                ),
                SizedBox(height: 8.ms),
                CText(
                  'payment:first_topup.extra',
                  variables: {'percent': percent},
                  size: 40,
                  weight: FontWeight.w900,
                  color: Colors.white,
                  height: 46,
                  maxLines: 1,
                  align: TextAlign.center,
                  style: const TextStyle(
                    shadows: [
                      Shadow(color: Color(0x55000000), blurRadius: 12),
                    ],
                  ),
                ),
                SizedBox(height: 6.ms),
                CText(
                  'payment:first_topup.hero',
                  variables: {'percent': percent},
                  size: 13.5,
                  weight: FontWeight.w600,
                  color: Colors.white.withValues(alpha: 0.95),
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
                width: 34.ms,
                height: 34.ms,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: Colors.black.withValues(alpha: 0.2),
                ),
                child: Icon(LucideIcons.x, size: 18.ms, color: Colors.white),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Every amount, three to a row, each with its free extra.
class _AmountGrid extends StatelessWidget {
  const _AmountGrid({
    required this.amounts,
    required this.percent,
    required this.chosen,
    required this.popular,
    required this.onPick,
  });

  final List<int> amounts;
  final double percent;
  final int chosen;
  final int? popular;
  final ValueChanged<int> onPick;

  @override
  Widget build(BuildContext context) {
    final perRow = amounts.length == 4 ? 2 : math.min(3, amounts.length);
    final rows = <List<int>>[
      for (var i = 0; i < amounts.length; i += perRow)
        amounts.sublist(i, math.min(i + perRow, amounts.length)),
    ];
    return Column(
      children: [
        for (final (r, row) in rows.indexed) ...[
          if (r > 0) SizedBox(height: 12.ms),
          Row(
            children: [
              for (final (i, value) in row.indexed) ...[
                if (i > 0) SizedBox(width: 10.ms),
                Expanded(
                  child: _AmountTile(
                    amount: value,
                    bonus: BonusPreview.of(value, percent).bonus,
                    active: value == chosen,
                    popular: value == popular,
                    onTap: () => onPick(value),
                  ),
                ),
              ],
              // A short last row keeps the tiles the same width.
              for (var i = row.length; i < perRow; i++) ...[
                SizedBox(width: 10.ms),
                const Expanded(child: SizedBox.shrink()),
              ],
            ],
          ),
        ],
      ],
    );
  }
}

class _AmountTile extends StatelessWidget {
  const _AmountTile({
    required this.amount,
    required this.bonus,
    required this.active,
    required this.popular,
    required this.onTap,
  });

  final int amount;
  final int bonus;
  final bool active;
  final bool popular;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final p = WalletPalette.of(context);
    final tile = AnimatedScale(
      scale: active ? 1.04 : 1,
      duration: const Duration(milliseconds: 180),
      curve: Curves.easeOutBack,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        // The tile fills its column: every tile the same width.
        width: double.infinity,
        padding: EdgeInsets.fromLTRB(6.ms, 16.ms, 6.ms, 10.ms),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16.ms),
          gradient: active
              ? LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    _hero.first.withValues(alpha: 0.14),
                    _hero.last.withValues(alpha: 0.14),
                  ],
                )
              : null,
          color: active ? null : p.soft,
          border: Border.all(
            color: active ? _hero[1] : p.cardBorder,
            width: active ? 2 : 1.2,
          ),
          boxShadow: active
              ? [
                  BoxShadow(
                    color: _hero[1].withValues(alpha: 0.28),
                    blurRadius: 14,
                    offset: const Offset(0, 6),
                  ),
                ]
              : null,
        ),
        child: Column(
          children: [
            FittedBox(
              fit: BoxFit.scaleDown,
              child: CText.raw(
                '₹${WalletFormat.whole(amount)}',
                size: 20,
                weight: FontWeight.w900,
                color: p.text,
                maxLines: 1,
              ),
            ),
            SizedBox(height: 6.ms),
            if (bonus > 0)
              Container(
                padding: EdgeInsets.symmetric(
                  horizontal: 7.ms,
                  vertical: 3.ms,
                ),
                decoration: BoxDecoration(
                  color: _green.withValues(alpha: 0.14),
                  borderRadius: BorderRadius.circular(999),
                ),
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  child: CText(
                    'payment:first_topup.free_extra',
                    variables: {'bonus': WalletFormat.whole(bonus)},
                    size: 11,
                    weight: FontWeight.w900,
                    color: _green,
                    maxLines: 1,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
    return Pressable(
      key: ValueKey('first-topup-amount-$amount'),
      onPressed: onTap,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          tile,
          if (popular)
            Positioned(
              top: -9.ms,
              left: 0,
              right: 0,
              child: Center(
                child: Container(
                  padding: EdgeInsets.symmetric(
                    horizontal: 8.ms,
                    vertical: 2.ms,
                  ),
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(colors: _hero),
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: const CText(
                    'payment:first_topup.popular',
                    size: 9.5,
                    weight: FontWeight.w900,
                    color: Colors.white,
                    letterSpacing: 0.8,
                    maxLines: 1,
                  ),
                ),
              ),
            ),
          if (active)
            Positioned(
              top: 6.ms,
              right: 6.ms,
              child: Icon(
                Icons.check_circle_rounded,
                size: 16.ms,
                color: _hero[1],
              ),
            ),
        ],
      ),
    );
  }
}

/// "You pay ₹199 → You get ₹299", the total counting up as it changes.
class _Becomes extends StatelessWidget {
  const _Becomes({required this.preview, required this.minutes});

  final BonusPreview preview;
  final int minutes;

  @override
  Widget build(BuildContext context) {
    final p = WalletPalette.of(context);
    Widget side(String label, Widget value) => Expanded(
      child: Column(
        children: [
          CText(label, size: 11, weight: FontWeight.w700, color: p.muted),
          SizedBox(height: 2.ms),
          value,
        ],
      ),
    );
    return Container(
      padding: EdgeInsets.symmetric(vertical: 12.ms, horizontal: 10.ms),
      decoration: BoxDecoration(
        color: _green.withValues(alpha: p.dark ? 0.12 : 0.07),
        borderRadius: BorderRadius.circular(16.ms),
        border: Border.all(color: _green.withValues(alpha: 0.35)),
      ),
      child: Column(
        children: [
          Row(
            children: [
              side(
                'payment:first_topup.you_pay',
                CText.raw(
                  '₹${WalletFormat.js(preview.amount)}',
                  size: 18,
                  weight: FontWeight.w800,
                  color: p.text,
                  maxLines: 1,
                ),
              ),
              Icon(LucideIcons.arrowRight, size: 20.ms, color: _green),
              side(
                'payment:first_topup.you_get',
                TweenAnimationBuilder<double>(
                  tween: Tween(end: preview.total),
                  duration: const Duration(milliseconds: 420),
                  curve: Curves.easeOutCubic,
                  builder: (_, value, _) => CText.raw(
                    '₹${WalletFormat.whole(value.round())}',
                    key: const ValueKey('first-topup-total'),
                    size: 22,
                    weight: FontWeight.w900,
                    color: _green,
                    maxLines: 1,
                  ),
                ),
              ),
            ],
          ),
          if (minutes > 0) ...[
            SizedBox(height: 6.ms),
            CText(
              'payment:first_topup.minutes',
              variables: {'minutes': '$minutes'},
              size: 11.5,
              color: p.muted,
              align: TextAlign.center,
            ),
          ],
        ],
      ),
    );
  }
}

/// The hot-gradient button with a light sweeping across it on a loop.
class _ShineButton extends StatelessWidget {
  const _ShineButton({
    required this.loop,
    required this.label,
    required this.enabled,
    required this.onTap,
  });

  final Animation<double> loop;
  final String label;
  final bool enabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Opacity(
      opacity: enabled ? 1 : 0.5,
      child: Pressable(
        key: const ValueKey('first-topup-cta'),
        onPressed: enabled ? onTap : null,
        activeOpacity: 0.9,
        child: Container(
          height: 54.ms,
          clipBehavior: Clip.antiAlias,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(18.ms),
            gradient: const LinearGradient(colors: _hero),
            boxShadow: [
              BoxShadow(
                color: _hero[1].withValues(alpha: 0.4),
                blurRadius: 16,
                offset: const Offset(0, 8),
              ),
            ],
          ),
          child: Stack(
            fit: StackFit.expand,
            children: [
              AnimatedBuilder(
                animation: loop,
                builder: (_, _) => FractionallySizedBox(
                  widthFactor: 0.35,
                  alignment: Alignment(-2.2 + 4.4 * loop.value, 0),
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: [
                          Colors.white.withValues(alpha: 0),
                          Colors.white.withValues(alpha: 0.35),
                          Colors.white.withValues(alpha: 0),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
              Center(
                child: Padding(
                  padding: EdgeInsets.symmetric(horizontal: 12.ms),
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(LucideIcons.zap, size: 18.ms, color: Colors.white),
                        SizedBox(width: 6.ms),
                        CText.raw(
                          label,
                          size: 15.5,
                          weight: FontWeight.w900,
                          color: Colors.white,
                          maxLines: 1,
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
