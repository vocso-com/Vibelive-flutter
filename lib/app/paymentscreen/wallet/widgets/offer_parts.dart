import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/utils/scale.dart';
import '../../../component/c_text.dart';
import '../../../component/pressable.dart';
import '../helper/wallet_format.dart';
import '../helper/wallet_palette.dart';

/// The look the top-up screens share (the first-top-up popup and Add
/// Money), in the app's own colours: the brand gradient for what to tap
/// (purple in light, lime in dark, like the wallet's Add money button), green
/// for money that lands in the wallet, a gold glow for the gift.
@immutable
class OfferColors {
  const OfferColors._({
    required this.gradient,
    required this.accent,
    required this.onAccent,
    required this.ink,
  });

  /// Hero, button, "POPULAR" tag.
  final List<Color> gradient;

  /// A picked tile's border and check; shadows.
  final Color accent;

  /// Text and icons on [gradient].
  final Color onAccent;

  /// An icon on white (the gift) that still reads as the brand.
  final Color ink;

  static const gold = Color(0xFFFFD54F);
  static const green = Color(0xFF16C784);

  static const _light = OfferColors._(
    gradient: [
      BrandColors.purpleLight,
      BrandColors.purple,
      BrandColors.purpleDark,
    ],
    accent: BrandColors.purple,
    onAccent: Colors.white,
    ink: BrandColors.purple,
  );

  static const _dark = OfferColors._(
    gradient: [BrandColors.limeLight, BrandColors.lime, Color(0xFF86C934)],
    accent: BrandColors.lime,
    onAccent: Colors.black,
    ink: Color(0xFF3F7A12),
  );

  static OfferColors of(BuildContext context) =>
      WalletPalette.of(context).dark ? _dark : _light;
}

/// Amount tiles, three to a row (two when there are four), lowest first.
/// Exactly one looks picked: [chosen]. [popular] wears a "POPULAR" tag;
/// [bonusOf] gives each tile's free extra ("+₹150 FREE", none at 0).
/// Each tile is keyed `<keyPrefix>-<amount>`.
class OfferAmountGrid extends StatelessWidget {
  const OfferAmountGrid({
    super.key,
    required this.amounts,
    required this.chosen,
    required this.onPick,
    required this.keyPrefix,
    this.popular,
    this.bonusOf,
    this.tileColor,
  });

  final List<int> amounts;

  /// An unpicked tile's fill (default: a faint tint, for a card's inside).
  final Color? tileColor;
  final int? chosen;
  final int? popular;
  final int Function(int amount)? bonusOf;
  final ValueChanged<int> onPick;
  final String keyPrefix;

  @override
  Widget build(BuildContext context) {
    if (amounts.isEmpty) return const SizedBox.shrink();
    final perRow = amounts.length == 4 ? 2 : math.min(3, amounts.length);
    final rows = <List<int>>[
      for (var i = 0; i < amounts.length; i += perRow)
        amounts.sublist(i, math.min(i + perRow, amounts.length)),
    ];
    return Column(
      children: [
        for (final (r, row) in rows.indexed) ...[
          if (r > 0) SizedBox(height: 10.ms),
          Row(
            children: [
              for (final (i, value) in row.indexed) ...[
                if (i > 0) SizedBox(width: 8.ms),
                Expanded(
                  child: _AmountTile(
                    key: ValueKey('$keyPrefix-$value'),
                    fill: tileColor,
                    amount: value,
                    bonus: bonusOf?.call(value) ?? 0,
                    active: value == chosen,
                    popular: value == popular,
                    onTap: () => onPick(value),
                  ),
                ),
              ],
              // A short last row keeps the tiles the same width.
              for (var i = row.length; i < perRow; i++) ...[
                SizedBox(width: 8.ms),
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
    super.key,
    this.fill,
    required this.amount,
    required this.bonus,
    required this.active,
    required this.popular,
    required this.onTap,
  });

  final Color? fill;
  final int amount;
  final int bonus;
  final bool active;
  final bool popular;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final p = WalletPalette.of(context);
    final o = OfferColors.of(context);
    final tile = AnimatedScale(
      scale: active ? 1.04 : 1,
      duration: const Duration(milliseconds: 180),
      curve: Curves.easeOutBack,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        // The tile fills its column: every tile the same width.
        width: double.infinity,
        padding: EdgeInsets.fromLTRB(
          5.ms,
          bonus > 0 ? 12.ms : 15.ms,
          5.ms,
          bonus > 0 ? 8.ms : 13.ms,
        ),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(14.ms),
          gradient: active
              ? LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    o.gradient.first.withValues(alpha: 0.16),
                    o.gradient.last.withValues(alpha: 0.16),
                  ],
                )
              : null,
          color: active ? null : (fill ?? p.soft),
          border: Border.all(
            color: active ? o.accent : p.cardBorder,
            width: active ? 2 : 1.2,
          ),
          boxShadow: active
              ? [
                  BoxShadow(
                    color: o.accent.withValues(alpha: 0.28),
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
                size: 17,
                weight: FontWeight.w900,
                color: p.text,
                maxLines: 1,
              ),
            ),
            if (bonus > 0) ...[
              SizedBox(height: 4.ms),
              Container(
                padding: EdgeInsets.symmetric(horizontal: 6.ms, vertical: 2.ms),
                decoration: BoxDecoration(
                  color: OfferColors.green.withValues(alpha: 0.14),
                  borderRadius: BorderRadius.circular(999),
                ),
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  child: CText(
                    'payment:first_topup.bonus_extra',
                    variables: {'bonus': WalletFormat.whole(bonus)},
                    size: 10,
                    weight: FontWeight.w900,
                    color: OfferColors.green,
                    maxLines: 1,
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
    return Pressable(
      onPressed: onTap,
      semanticLabel: '₹${WalletFormat.whole(amount)}',
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          tile,
          if (popular)
            Positioned(
              top: -8.ms,
              left: 0,
              right: 0,
              child: Center(
                child: Container(
                  padding: EdgeInsets.symmetric(
                    horizontal: 8.ms,
                    vertical: 2.ms,
                  ),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(colors: o.gradient),
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: CText(
                    'payment:first_topup.popular',
                    size: 8.5,
                    weight: FontWeight.w900,
                    color: o.onAccent,
                    letterSpacing: 0.8,
                    maxLines: 1,
                  ),
                ),
              ),
            ),
          if (active)
            Positioned(
              top: 5.ms,
              right: 5.ms,
              child: Icon(
                Icons.check_circle_rounded,
                size: 14.ms,
                color: o.accent,
              ),
            ),
        ],
      ),
    );
  }
}

/// The hot-gradient button with a light sweeping across it on a loop
/// ([loop]: a repeating 0 → 1 clock; still when it is not running).
/// [loading]: a spinner in place of the label, taps ignored.
class OfferShineButton extends StatelessWidget {
  const OfferShineButton({
    super.key,
    required this.loop,
    required this.label,
    required this.onTap,
    this.enabled = true,
    this.loading = false,
    this.icon = LucideIcons.zap,
  });

  final Animation<double> loop;
  final String label;
  final bool enabled;
  final bool loading;
  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final o = OfferColors.of(context);
    final tappable = enabled && !loading;
    return Opacity(
      opacity: enabled ? 1 : 0.5,
      child: Pressable(
        onPressed: tappable ? onTap : null,
        activeOpacity: 0.9,
        semanticLabel: label,
        child: Container(
          height: 46.ms,
          clipBehavior: Clip.antiAlias,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16.ms),
            gradient: LinearGradient(colors: o.gradient),
            boxShadow: [
              BoxShadow(
                color: o.accent.withValues(alpha: 0.4),
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
                child: loading
                    ? SizedBox.square(
                        dimension: 20.ms,
                        child: CircularProgressIndicator(
                          strokeWidth: 2.4,
                          color: o.onAccent,
                        ),
                      )
                    : Padding(
                        padding: EdgeInsets.symmetric(horizontal: 12.ms),
                        child: FittedBox(
                          fit: BoxFit.scaleDown,
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(icon, size: 16.ms, color: o.onAccent),
                              SizedBox(width: 6.ms),
                              CText.raw(
                                label,
                                size: 14,
                                weight: FontWeight.w900,
                                color: o.onAccent,
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
