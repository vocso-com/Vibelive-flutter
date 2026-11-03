import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/utils/scale.dart';
import '../../component/c_text.dart';
import '../../component/pressable.dart';
import '../helper/low_balance.dart';
import 'chat_palette.dart';

/// "Only 3 messages left · Add money" above the composer (paying side,
/// when the balance is low). Listens to the balance only.
class LowBalanceBar extends StatelessWidget {
  const LowBalanceBar({
    super.key,
    required this.balance,
    required this.textPrice,
    required this.threshold,
    required this.paying,
    required this.chatEnabled,
    required this.onAdd,
  });

  final ValueListenable<double?> balance;
  final double textPrice;
  final int threshold;
  final bool paying;
  final bool chatEnabled;
  final VoidCallback onAdd;

  @override
  Widget build(BuildContext context) {
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
        if (low == null) return const SizedBox.shrink();
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
                  padding: EdgeInsets.symmetric(
                    horizontal: 10.ms,
                    vertical: 5.ms,
                  ),
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
      },
    );
  }
}
