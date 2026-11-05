import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/utils/scale.dart';
import '../../component/c_text.dart';
import '../../component/pressable.dart';
import '../helper/low_balance.dart';
import 'chat_palette.dart';

/// The small strip above the composer, for the paying side (contract §6).
/// It never blocks the chat; it just keeps the user aware of money, quietly:
///  - the free opener → a calm "Your first message is free";
///  - balance low (below the configured threshold) → a red
///    "Only N messages left · Add money".
/// Otherwise nothing: the exact balance in ₹ stays in the menu's Prices sheet,
/// so the chat screen itself carries no money amounts. Nothing shows for a
/// host, when chat is off, or when the balance is unknown.
class LowBalanceBar extends StatelessWidget {
  const LowBalanceBar({
    super.key,
    required this.balance,
    required this.textPrice,
    required this.threshold,
    required this.paying,
    required this.chatEnabled,
    required this.onAdd,
    this.firstMessageFree = false,
  });

  final ValueListenable<double?> balance;
  final double textPrice;
  final int threshold;
  final bool paying;
  final bool chatEnabled;
  final VoidCallback onAdd;

  /// The next message is the free opener: a calm hint, no balance, no warning.
  final bool firstMessageFree;

  @override
  Widget build(BuildContext context) {
    if (!paying || !chatEnabled) return const SizedBox.shrink();
    if (firstMessageFree) return const _FirstFree();
    return ValueListenableBuilder<double?>(
      valueListenable: balance,
      builder: (context, value, _) {
        final low = ChatLowBalance.of(
          paying: paying,
          chatEnabled: chatEnabled,
          balance: value,
          textPrice: textPrice,
          threshold: threshold,
        );
        if (low != null) return _LowPill(low: low, onAdd: onAdd);
        return const SizedBox.shrink();
      },
    );
  }
}

/// The red "Only N messages left · Add money" pill (balance running out).
class _LowPill extends StatelessWidget {
  const _LowPill({required this.low, required this.onAdd});

  final ChatLowBalance low;
  final VoidCallback onAdd;

  @override
  Widget build(BuildContext context) {
    final p = ChatPalette.of(context);
    const red = StatusColors.dangerRed;
    return Container(
      key: const ValueKey('chat-low-balance'),
      margin: EdgeInsetsDirectional.fromSTEB(12.ms, 6.ms, 12.ms, 0),
      padding: EdgeInsetsDirectional.fromSTEB(12.ms, 6.ms, 6.ms, 6.ms),
      decoration: BoxDecoration(
        color: red.withValues(alpha: p.dark ? 0.16 : 0.1),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        children: [
          Icon(LucideIcons.wallet, size: 15.ms, color: red),
          SizedBox(width: 6.ms),
          Expanded(
            child: CText(
              low.textKey,
              count: low.empty ? null : low.messagesLeft,
              size: 12.5,
              weight: FontWeight.w700,
              color: red,
              maxLines: 1,
            ),
          ),
          Pressable(
            onPressed: onAdd,
            child: Container(
              padding: EdgeInsets.symmetric(horizontal: 10.ms, vertical: 5.ms),
              decoration: BoxDecoration(
                color: p.bar,
                borderRadius: BorderRadius.circular(999),
              ),
              child: CText(
                'chat:low_balance.add',
                size: 12,
                weight: FontWeight.w800,
                color: p.accent,
                maxLines: 1,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// The free-opener hint: a calm, positive line, no balance or warning.
class _FirstFree extends StatelessWidget {
  const _FirstFree();

  @override
  Widget build(BuildContext context) {
    final p = ChatPalette.of(context);
    const green = StatusColors.success;
    return Container(
      key: const ValueKey('chat-first-free'),
      margin: EdgeInsetsDirectional.fromSTEB(12.ms, 6.ms, 12.ms, 0),
      padding: EdgeInsetsDirectional.fromSTEB(12.ms, 6.ms, 12.ms, 6.ms),
      decoration: BoxDecoration(
        color: green.withValues(alpha: p.dark ? 0.16 : 0.1),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        children: [
          Icon(LucideIcons.gift, size: 15.ms, color: green),
          SizedBox(width: 6.ms),
          const Expanded(
            child: CText(
              'chat:low_balance.first_free',
              size: 12.5,
              weight: FontWeight.w700,
              color: green,
              maxLines: 1,
            ),
          ),
        ],
      ),
    );
  }
}
