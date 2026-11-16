import 'package:flutter/foundation.dart';

import '../../../../core/config/runtime_config.dart';
import '../../../api/paymentscreen/wallet_models.dart';
import 'first_topup_offer.dart';

enum TopUpBonusKind { firstTopup, comeback }

/// The extra the server adds to this top-up, shown on the amount cards and
/// in the breakdown. The server grants it; this only previews it.
@immutable
class TopUpBonus {
  const TopUpBonus(this.kind, this.percent);

  final TopUpBonusKind kind;
  final double percent;

  /// Rupees added on top of [amount] (RN `computeFirstTopupPreview`).
  int on(num amount) => BonusPreview.of(amount, percent).bonus;

  /// Which bonus this top-up will get, or null. A first top-up wins over the
  /// come-back offer: they don't stack (RN), and it is the larger one.
  /// [history] null (not loaded yet) never promises a first-top-up bonus,
  /// unless [paidBefore] (the server asked instead) says there was no paid
  /// top-up.
  static TopUpBonus? resolve({
    required RuntimeConfig config,
    required Iterable<WalletTransaction>? history,
    bool comeback = false,
    bool? paidBefore,
  }) {
    final b = config.bonus;
    final firstEver = history != null
        ? !FirstTopupOffer.hasPaidTopup(history)
        : paidBefore == false;
    if (b.firstTopupOn && firstEver) {
      return TopUpBonus(TopUpBonusKind.firstTopup, b.firstTopupBonusPercent);
    }
    if (comeback && b.abandonOfferOn) {
      return TopUpBonus(TopUpBonusKind.comeback, b.abandonOfferPercent);
    }
    return null;
  }
}
