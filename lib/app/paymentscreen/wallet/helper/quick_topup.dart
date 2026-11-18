import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/analytics/analytics.dart';
import '../../../../core/analytics/events/payment_events.dart';
import '../../../../core/i18n/i18n.dart';
import '../../../../core/network/api_exception.dart';
import '../../../../core/network/strapi.dart';
import '../../../../core/router/app_router.dart';
import '../../../../core/session/session_store.dart';
import '../../../../core/utils/log.dart';
import '../../../api/client/client_queries.dart';
import '../../../api/paymentscreen/checkout_models.dart';
import '../../../api/paymentscreen/payment_queries.dart';
import '../../../api/paymentscreen/runtime_config_queries.dart';
import '../../../component/c_alert.dart';
import '../../../component/c_loader.dart';
import '../widgets/payment_status.dart';
import '../widgets/web_checkout_page.dart';
import 'add_money_flow.dart';
import 'topup_checkout.dart';
import 'wallet_palette.dart';
import 'wallet_amounts.dart';
import 'wallet_offers.dart';

/// A top-up of one amount straight from an offer (the first-top-up popup):
/// the gateway opens at once, with no wallet screen and no Add Money in
/// between. The very same pipeline as the wallet's Add Money
/// ([TopUpCheckout]): the backend creates the order for the amount before
/// GST at the runtime GST percent (what the offer showed), the gateway
/// takes the payment, the backend verifies it, the status dialog shows the
/// outcome, and the wallet is re-read. A checkout closed by the person gets
/// the come-back offer, as on the wallet.
abstract final class QuickTopUp {
  static const _tag = 'QuickTopUp';

  /// The checkout (tests swap it for fakes).
  @visibleForTesting
  static TopUpCheckout Function() newFlow = TopUpCheckout.new;

  /// [amount]: rupees before GST. [source]: what opened it (analytics).
  static Future<void> run(
    BuildContext context, {
    required int amount,
    required String source,
    bool comeback = false,
  }) async {
    if (amount <= 0) return;
    final user = await _me();
    if (!context.mounted) return;
    bool has(String key) => (J.str(user?[key]) ?? '').isNotEmpty;
    if (!has('name') || !has('email') || !has('mobile')) {
      return _profileIncomplete(context);
    }
    final payer = PayerInfo.fromUser(user);
    final config = currentRuntimeConfig();
    final shown = TopUpAmount.breakdown(amount.toDouble(), config.gstPercent);
    final flow = newFlow();
    final backdrop = ValueNotifier<_Backdrop>(_Backdrop.preparing);
    final overlay = OverlayEntry(
      builder: (_) => Stack(
        children: [
          _BackdropView(phase: backdrop),
          Positioned.fill(child: VerifyingOverlay(visible: flow.verifying)),
        ],
      ),
    );
    Overlay.of(context, rootOverlay: true).insert(overlay);
    // Removed once: `mounted` stays true until the next frame, so it cannot
    // tell (a second remove() asserts, and throws in release).
    var removed = false;
    void drop() {
      if (removed) return;
      removed = true;
      overlay.remove();
    }

    RechargeCheckout? order;
    try {
      PaymentEvents.payTapped(
        amount: amount,
        gstPercent: config.gstPercent,
        total: shown.total,
        bonus: null,
      );
      order = await flow.createOrder(
        amount: amount.toDouble(),
        payer: payer,
        description: context.t('payment:add_money.description'),
        gstPercent: config.gstPercent,
      );
      PaymentEvents.orderCreated(
        amount: amount,
        gateway: order.gateway.name,
        orderId: order.txnId,
      );
      // Razorpay's native checkout is a see-through window that leaves the
      // gesture-bar strip at the bottom unpainted: what is behind it shows
      // there. Behind the wallet's checkout that is the wallet's plain page;
      // here it would be Discover's host photos. So the app's plain
      // background goes behind it, as on the wallet.
      backdrop.value = _Backdrop.gateway;
      // The gateway charges the order's amount; the offer showed the same
      // maths. Should they ever differ (GST changed in between), the
      // gateway's figure is the one paid: noted for us to look at.
      final paid = order;
      if (paid is RazorpayCheckout &&
          paid.amountInPaise != (shown.total * 100).round()) {
        Log.w(
          _tag,
          'order ${paid.txnId}: gateway ${paid.amountInPaise} paise, '
          'shown ${(shown.total * 100).round()}',
        );
      }
      if (!context.mounted) return;
      var abandoned = false;
      final status = await flow.pay(
        paid,
        payer,
        onAbandoned: () => abandoned = true,
        // A web checkout is a page of the app: nothing over it.
        web: (request) {
          backdrop.value = _Backdrop.none;
          return WebCheckoutPage.open(context, request);
        },
      );
      if (!context.mounted) return;
      if (status == null) {
        // Closed by them: the come-back offer, once, as on the wallet.
        if (!abandoned || comeback || paid is! RazorpayCheckout) return;
        drop();
        final again = await WalletOffers.afterAbandon(
          context,
          config: config,
          order: paid,
        );
        if (again != null && context.mounted) {
          await run(
            context,
            amount: again.ceil(),
            source: 'abandon_offer',
            comeback: true,
          );
        }
        return;
      }
      invalidateWalletQueries();
      if (status.result != TopUpResult.failure) AddMoneyFlow.forgetPaid();
      final result = status.result.name;
      PaymentEvents.paymentStatusShown(
        status: result,
        source: source,
        amount: paid.baseAmount,
      );
      drop();
      await showPaymentStatus(context, status);
      PaymentEvents.paymentStatusClosed(status: result, source: source);
    } on ApiException catch (e) {
      PaymentEvents.orderFailed(amount: amount, error: Analytics.errorCode(e));
      drop();
      unawaited(CAlert.error(e));
    } finally {
      drop();
      backdrop.dispose();
      flow.dispose();
    }
  }

  /// The full profile when it can be read, else the session's user.
  static Future<JsonMap?> _me() async {
    final session = SessionStore.instance.value;
    final uid = session.userDocumentId;
    if (uid == null) return session.user;
    try {
      return (await ensureMyProfile(uid)).user;
    } catch (_) {
      return session.user;
    }
  }

  static Future<void> _profileIncomplete(BuildContext context) async {
    final update = await CAlert.show(
      title: 'payment:wallet.incomplete_title',
      message: 'payment:wallet.incomplete_add',
      primaryLabel: 'payment:wallet.update_profile',
      secondaryLabel: 'actions.cancel',
      variant: CAlertVariant.warning,
    );
    PaymentEvents.profileIncomplete(step: 'add', updateProfile: update == true);
    if (update == true && context.mounted) {
      unawaited(context.push(AppRoutes.personalInfo));
    }
  }
}

enum _Backdrop {
  /// The order is being made: a dim and a spinner (a second or two), so a
  /// tap cannot start a second one.
  preparing,

  /// The native gateway is open: the app's plain background behind it.
  gateway,

  /// A web checkout page is open: nothing.
  none,
}

class _BackdropView extends StatelessWidget {
  const _BackdropView({required this.phase});

  final ValueListenable<_Backdrop> phase;

  @override
  Widget build(BuildContext context) {
    final bg = WalletPalette.of(context).bg;
    return ValueListenableBuilder<_Backdrop>(
      valueListenable: phase,
      builder: (_, at, _) => at == _Backdrop.none
          ? const SizedBox.shrink()
          : Positioned.fill(
              child: AnimatedContainer(
                key: const ValueKey('quick-topup-backdrop'),
                duration: const Duration(milliseconds: 160),
                color: at == _Backdrop.gateway ? bg : const Color(0x66000000),
                child: const Center(child: CLoader(size: 30)),
              ),
            ),
    );
  }
}
