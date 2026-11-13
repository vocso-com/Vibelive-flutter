import 'package:flutter/widgets.dart';

import '../../../../core/analytics/events/payment_events.dart';
import '../../../../core/config/runtime_config.dart';
import '../../../api/paymentscreen/checkout_models.dart';
import '../widgets/abandon_offer_sheet.dart';
import 'first_topup_offer.dart';

/// The wallet's bonus prompt after an abandoned checkout (RN WalletScreen).
/// It derives everything from config: with its flag off, or the percent at
/// 0, it never shows. (The first-top-up offer is the app-open popup now:
/// FirstTopupLaunch.)
abstract final class WalletOffers {
  /// Exit-intent offer right after a dismissed checkout, while the intent is
  /// still warm. The amount to check out again, else null.
  static Future<double?> afterAbandon(
    BuildContext context, {
    required RuntimeConfig config,
    required RazorpayCheckout order,
  }) async {
    final bonus = config.bonus;
    final amount = order.baseAmount;
    if (!bonus.abandonOfferOn || !(amount > 0)) return null;
    final percent = bonus.abandonOfferPercent;
    final offer = BonusPreview.of(amount, percent);
    if (offer.bonus <= 0) return null;
    final orderRef = order.txnId.isNotEmpty ? order.txnId : order.orderId;
    void log(String action) => PaymentEvents.abandonOffer(
      action: action,
      orderId: orderRef,
      amount: amount,
      percent: percent,
    );
    log('shown');
    final accepted = await showAbandonOfferSheet(
      context,
      offer: offer,
      percent: percent,
      windowMinutes: bonus.abandonOfferWindowMinutes,
      gstPercent: config.gstPercent,
    );
    if (!accepted) {
      log('dismissed');
      return null;
    }
    log('accepted');
    return amount;
  }
}
