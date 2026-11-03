import 'package:flutter/foundation.dart';

import 'chat_pricing.dart';

/// The low-balance bar of the paying side (contract §6): shown when
/// `balance / textPrice < lowBalanceMessages`.
@immutable
class ChatLowBalance {
  const ChatLowBalance._(this.messagesLeft);

  /// Messages the balance still pays for (0: none).
  final int messagesLeft;

  bool get empty => messagesLeft <= 0;

  /// i18n key and variables of the bar's text.
  String get textKey =>
      empty ? 'chat:low_balance.empty' : 'chat:low_balance.left';

  /// Null when no bar is due: not paying, chat off, free messages, the
  /// balance unknown, or enough left.
  static ChatLowBalance? of({
    required bool paying,
    required bool chatEnabled,
    required double? balance,
    required double textPrice,
    required int threshold,
  }) {
    final price = ChatPricing.paise(textPrice);
    if (!paying || !chatEnabled || balance == null || price <= 0) return null;
    final left = countLeft(balance: balance, textPrice: textPrice);
    return left < threshold ? ChatLowBalance._(left) : null;
  }

  /// Whole messages [balance] pays for at [textPrice] (never negative).
  static int countLeft({required double balance, required double textPrice}) {
    final price = ChatPricing.paise(textPrice);
    if (price <= 0) return 0;
    final cash = ChatPricing.paise(balance);
    return cash <= 0 ? 0 : cash ~/ price;
  }

  /// What to put on the recharge sheet's button: what is missing to send
  /// (`required − balance`), never below the wallet's minimum top-up.
  static double gap({required double? required, required double? balance}) {
    final need = ChatPricing.paise(required ?? 0);
    final have = ChatPricing.paise(balance ?? 0);
    return need > have ? (need - have) / 100 : 0;
  }

  @override
  bool operator ==(Object other) =>
      other is ChatLowBalance && other.messagesLeft == messagesLeft;

  @override
  int get hashCode => messagesLeft.hashCode;
}
