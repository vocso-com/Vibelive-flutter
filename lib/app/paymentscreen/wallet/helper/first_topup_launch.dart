import 'dart:async';

import 'package:flutter/widgets.dart';

import '../../../../core/analytics/events/payment_events.dart';
import '../../../../core/session/session_store.dart';
import '../../../../core/utils/log.dart';
import '../../../component/c_toast.dart';
import '../../../api/paymentscreen/runtime_config_queries.dart';
import '../../../api/paymentscreen/transaction_api.dart';
import '../widgets/first_topup_popup.dart';
import 'first_topup_offer.dart';
import 'quick_topup.dart';

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
/// them. A pick opens the payment gateway for that amount at once
/// (QuickTopUp), the GST on top exactly as the popup showed it.
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
        gstPercent: config.gstPercent,
      );
    } catch (e) {
      // Unsure whether they ever paid: no offer this time.
      Log.w('FirstTopup', 'check skipped: $e');
      return null;
    }
  }

  /// The offer as it looks now, for testers (Profile → "Preview first top-up
  /// offer", debug builds and company accounts only): the admin's percent and
  /// the wallet's amounts, with none of the checks or the caps and nothing
  /// counted. With the bonus off in the admin it shows at 50% and says that
  /// real users would not see it.
  static Future<void> demo(BuildContext context) async {
    final config = await ensureFreshRuntimeConfig();
    final bonus = config.bonus;
    final off = !bonus.firstTopupOn;
    final amounts = FirstTopupOffer.amounts(config.presetAmounts);
    final plan = FirstTopupPlan(
      percent: off ? 50 : bonus.firstTopupBonusPercent,
      amounts: amounts.isEmpty ? const [99, 199, 499] : amounts,
      voiceRate: config.pricing.minVoiceCallRate,
      gstPercent: config.gstPercent,
    );
    if (!context.mounted) return;
    if (off) {
      CToast.show(
        'client:me.first_topup_demo.off',
        duration: const Duration(seconds: 5),
      );
    }
    final chosen = await showFirstTopupPopup(context, plan);
    if (chosen == null || !context.mounted) return;
    // The real payment, as an eligible user's tap would.
    await QuickTopUp.run(context, amount: chosen, source: 'first_topup_demo');
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
    // The gateway opens from here: no wallet screen, no Add Money between.
    await QuickTopUp.run(context, amount: chosen, source: 'first_topup_offer');
  }
}
