import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/analytics/events/payment_events.dart';
import '../../../../core/router/app_router.dart';
import '../../../../core/session/session_store.dart';
import '../../../../core/utils/log.dart';
import '../../../api/paymentscreen/runtime_config_queries.dart';
import '../../../api/paymentscreen/transaction_api.dart';
import '../widgets/first_topup_popup.dart';
import 'first_topup_offer.dart';

/// The first-top-up offer as the app-open popup: whether this user gets it
/// on this open, and showing it. It takes the open's one popup slot ahead of
/// the admin's promo popups (PromoPopupController), and only while:
///
/// - the admin has the first-top-up bonus on (`first_topup_bonus_enabled`
///   and a percent above 0, Settings → Wallet & bonus);
/// - the user is a caller: not a host, not a company account (they call for
///   free);
/// - they have never paid in (asked of the server: one successful
///   Razorpay / PayU top-up and it is gone for good);
/// - the caps allow it: once per app session, three times ever, never again
///   after two "not now"s.
///
/// The amounts are the wallet's own (the admin's preset amounts), all of
/// them. A pick opens the wallet with that amount filled in.
abstract final class FirstTopupLaunch {
  /// Whether to offer it on this open (tests swap it).
  static Future<FirstTopupPlan?> Function() prepare = _prepare;

  static Future<FirstTopupPlan?> _prepare() async {
    final session = SessionStore.instance.value;
    final uid = session.userDocumentId;
    if (!session.isAuthenticated || uid == null) return null;
    if (session.isCompanyAccount || session.isExpert) return null;
    try {
      final config = await ensureFreshRuntimeConfig();
      final bonus = config.bonus;
      if (!bonus.firstTopupOn) return null;
      final percent = bonus.firstTopupBonusPercent;
      final amounts = FirstTopupOffer.amounts(config.presetAmounts);
      if (amounts.isEmpty || !FirstTopupOffer.mayShow(percent: percent)) {
        return null;
      }
      if (await TransactionApi.hasPaidTopup(uid)) return null;
      return FirstTopupPlan(
        percent: percent,
        amounts: amounts,
        voiceRate: config.pricing.minVoiceCallRate,
      );
    } catch (e) {
      // Unsure whether they ever paid: no offer this time.
      Log.w('FirstTopup', 'check skipped: $e');
      return null;
    }
  }

  /// Shows it over [context] (Home). A pick opens the wallet with the amount
  /// filled in; "not now" or the X counts a dismissal.
  static Future<void> present(BuildContext context, FirstTopupPlan plan) async {
    final percent = plan.percent;
    if (!FirstTopupOffer.claimShow(enabled: true, percent: percent)) return;
    PaymentEvents.firstTopupOfferShown(
      percent: percent,
      suggested: plan.suggested,
    );
    final chosen = await showFirstTopupPopup(context, plan);
    if (chosen == null) {
      FirstTopupOffer.recordDismissal();
      PaymentEvents.firstTopupOfferDismissed(percent: percent);
      return;
    }
    PaymentEvents.firstTopupOfferTapped(percent: percent, amount: chosen);
    if (!context.mounted) return;
    unawaited(
      context.push(
        '${AppRoutes.wallet}?amount=$chosen&reason=first_topup_offer',
      ),
    );
  }
}
