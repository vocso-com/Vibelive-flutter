import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/analytics/events/payment_events.dart';
import '../../../../core/network/strapi.dart';
import '../../../../core/router/app_router.dart';
import '../../../../core/session/session_store.dart';
import '../../../../core/utils/log.dart';
import '../../../api/client/client_queries.dart';
import '../../../api/paymentscreen/checkout_models.dart';
import '../../../api/paymentscreen/payment_queries.dart';
import '../../../api/paymentscreen/runtime_config_queries.dart';
import '../../../api/paymentscreen/transaction_api.dart';
import '../../../component/c_alert.dart';
import '../../../component/c_loader.dart';
import '../widgets/add_money_sheet.dart';
import '../widgets/payment_status.dart';
import '../widgets/web_checkout_page.dart';
import 'topup_bonus.dart';
import 'topup_checkout.dart';
import 'wallet_offers.dart';
import 'wallet_palette.dart';

/// The wallet's "Add Money", from anywhere that is not the wallet (the call
/// screen's "Add money"): the very same full-screen Add Money (amount tiles,
/// first-top-up bonus, GST), gateway, verification, status dialog and
/// come-back offer as the wallet ([WalletScreen]'s own flow, which stays as
/// it is), over whatever is on screen. Nothing is left behind it: it never
/// navigates away.
abstract final class AddMoneyFlow {
  static const _tag = 'AddMoneyFlow';

  /// The checkout (tests swap it for fakes).
  @visibleForTesting
  static TopUpCheckout Function() newFlow = TopUpCheckout.new;

  /// What came of it: the payment's result, or null when nothing was paid
  /// (closed, profile incomplete, the order refused). [source]: what opened
  /// it (analytics). [initialAmount]: rupees before GST, pre-picked.
  static Future<TopUpResult?> run(
    BuildContext context, {
    required String source,
    double? initialAmount,
    bool comeback = false,
  }) async {
    final user = await _me();
    if (!context.mounted) return null;
    bool has(String key) => (J.str(user?[key]) ?? '').isNotEmpty;
    if (!has('name') || !has('email') || !has('mobile')) {
      await _profileIncomplete(context, 'payment:wallet.incomplete_add');
      return null;
    }
    final payer = PayerInfo.fromUser(user);
    final bonus = await _bonus(comeback: comeback);
    if (!context.mounted) return null;
    final flow = newFlow();
    OverlayEntry? overlay;
    final backdrop = ValueNotifier<bool>(true);
    try {
      final exit = await showAddMoney(
        context,
        flow: flow,
        payer: () => payer,
        initialAmount: initialAmount,
        bonus: bonus,
        source: source,
      );
      if (exit == null || !context.mounted) return null;
      final order = exit.checkout;
      if (exit.profileIncomplete || order == null) {
        await _profileIncomplete(context, 'payment:wallet.incomplete_pay');
        return null;
      }
      // Razorpay's native checkout leaves the gesture-bar strip unpainted:
      // the app's plain background goes behind it (not the screen it was
      // opened over), and the "verifying" veil after it.
      overlay = OverlayEntry(
        builder: (_) => Stack(
          children: [
            _Backdrop(visible: backdrop),
            Positioned.fill(child: VerifyingOverlay(visible: flow.verifying)),
          ],
        ),
      );
      Overlay.of(context, rootOverlay: true).insert(overlay);
      var abandoned = false;
      final status = await flow.pay(
        order,
        payer,
        onAbandoned: () => abandoned = true,
        web: (request) {
          backdrop.value = false;
          return WebCheckoutPage.open(context, request);
        },
      );
      if (overlay.mounted) overlay.remove();
      if (!context.mounted) return status?.result;
      if (status == null) {
        // Closed by them: the come-back offer, once, as on the wallet.
        if (!abandoned || comeback || order is! RazorpayCheckout) return null;
        final again = await WalletOffers.afterAbandon(
          context,
          config: currentRuntimeConfig(),
          order: order,
        );
        if (again == null || !context.mounted) return null;
        return run(
          context,
          source: 'abandon_offer',
          initialAmount: again,
          comeback: true,
        );
      }
      invalidateWalletQueries();
      final shown = status.result.name;
      PaymentEvents.paymentStatusShown(
        status: shown,
        source: source,
        amount: order.baseAmount,
      );
      await showPaymentStatus(context, status);
      PaymentEvents.paymentStatusClosed(status: shown, source: source);
      return status.result;
    } finally {
      if (overlay?.mounted ?? false) overlay!.remove();
      backdrop.dispose();
      flow.dispose();
    }
  }

  /// The bonus as the wallet gives it when its history is not loaded (its
  /// call-balance-gate path): fresh settings, and the server says whether
  /// this user ever paid.
  static Future<TopUpBonus?> _bonus({required bool comeback}) async {
    final config = await ensureFreshRuntimeConfig();
    bool? paidBefore;
    if (config.bonus.firstTopupOn) {
      final uid = SessionStore.instance.value.userDocumentId;
      if (uid != null) {
        try {
          paidBefore = await TransactionApi.hasPaidTopup(uid);
        } catch (e) {
          Log.w(_tag, 'paid-before check failed, no first-top-up bonus: $e');
        }
      }
    }
    return TopUpBonus.resolve(
      config: config,
      history: null,
      comeback: comeback,
      paidBefore: paidBefore,
    );
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

  static Future<void> _profileIncomplete(
    BuildContext context,
    String message,
  ) async {
    final update = await CAlert.show(
      title: 'payment:wallet.incomplete_title',
      message: message,
      primaryLabel: 'payment:wallet.update_profile',
      secondaryLabel: 'actions.cancel',
      variant: CAlertVariant.warning,
    );
    PaymentEvents.profileIncomplete(
      step: message == 'payment:wallet.incomplete_add' ? 'add' : 'pay',
      updateProfile: update == true,
    );
    if (update == true && context.mounted) {
      unawaited(context.push(AppRoutes.personalInfo));
    }
  }
}

/// The plain wallet background behind the native gateway.
class _Backdrop extends StatelessWidget {
  const _Backdrop({required this.visible});

  final ValueListenable<bool> visible;

  @override
  Widget build(BuildContext context) {
    final bg = WalletPalette.of(context).bg;
    return ValueListenableBuilder<bool>(
      valueListenable: visible,
      builder: (_, on, _) => on
          ? Positioned.fill(
              child: ColoredBox(
                key: const ValueKey('add-money-flow-backdrop'),
                color: bg,
                child: const Center(child: CLoader(size: 30)),
              ),
            )
          : const SizedBox.shrink(),
    );
  }
}
