import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../api/promo_banner/promo_banner_models.dart';
import '../../promo/promo_banner_carousel.dart';
import '../../../core/analytics/analytics.dart';
import '../../../core/analytics/events/payment_events.dart';
import '../../../core/i18n/i18n.dart';
import '../../../core/network/strapi.dart';
import '../../../core/query/query_hooks.dart';
import '../../../core/router/app_router.dart';
import '../../../core/session/session_store.dart';
import '../../../core/utils/log.dart';
import '../../../core/utils/scale.dart';
import '../../api/client/client_queries.dart';
import '../../api/paymentscreen/checkout_models.dart';
import '../../api/paymentscreen/payment_queries.dart';
import '../../api/paymentscreen/runtime_config_queries.dart';
import '../../api/paymentscreen/wallet_models.dart';
import '../../component/c_alert.dart';
import '../../component/c_text.dart';
import '../../component/status_bar_style.dart';
import '../../component/vibe_background.dart';
import 'helper/topup_bonus.dart';
import 'helper/topup_checkout.dart';
import 'helper/transaction_pager.dart';
import 'helper/transaction_row.dart';
import 'helper/wallet_offers.dart';
import 'helper/wallet_palette.dart';
import 'widgets/add_money_sheet.dart';
import 'widgets/balance_card.dart';
import 'widgets/payment_status.dart';
import 'widgets/transaction_list.dart';
import 'widgets/transaction_tabs.dart';
import 'widgets/transfer_sheet.dart';
import 'widgets/wallet_header.dart';
import 'widgets/web_checkout_page.dart';

/// Wallet (RN `WalletScreen`): balances, Razorpay top-up, earnings → cash
/// transfer and the paged transaction history.
class WalletScreen extends HookWidget {
  const WalletScreen({super.key, this.checkout, this.prefillAmount});

  /// Top-up flow; tests pass one with a fake checkout.
  final TopUpCheckout? checkout;

  /// Opens Add Money pre-filled (the call balance gate's "Add ₹X"): one tap
  /// from the gap to checkout.
  final double? prefillAmount;

  static const _tag = 'Wallet';

  /// RN waits this long before refreshing after a failed payment.
  static const failureRefreshDelay = Duration(seconds: 2);

  @override
  Widget build(BuildContext context) {
    final p = WalletPalette.of(context);
    final pager = useMemoized(TransactionPager.new);
    useEffect(() => pager.dispose, [pager]);
    final flow = useMemoized(() => checkout ?? TopUpCheckout(), [checkout]);
    useEffect(() => checkout == null ? flow.dispose : null, [flow]);
    final tab = useValueNotifier(TransactionFilter.all);

    // RN `logWalletOpened` on every wallet load (open, refresh, payment),
    // with the first wallet row's balance.
    Future<void> loadBalance({Duration stale = StaleTime.none}) =>
        ensureWalletBalance(staleDuration: stale).then(
          (b) => PaymentEvents.walletOpened(
            userId: SessionStore.instance.value.userDocumentId,
            balance: b.primary?.balance ?? 0,
          ),
          onError: (Object e) => Log.w(_tag, 'balance refresh failed: $e'),
        );

    useEffect(() {
      unawaited(pager.select(TransactionFilter.all));
      unawaited(loadBalance(stale: StaleTime.short));
      return null;
    }, const []);

    // RN `userData`: the full profile, else the session user.
    final profile = useMyProfile(context);
    final user = profile.data?.user ?? SessionStore.instance.value.user;
    final userRef = useRef(user);
    userRef.value = user;
    final myName = J.str(user?['name']);
    final config = useRuntimeConfig(context);
    final configRef = useRef(config);
    configRef.value = config;

    Future<void> refresh() async {
      await Future.wait([loadBalance(), pager.refresh()]);
    }

    // Invalidating already refetches the balance on screen (and the Home
    // chip): only the history needs a fresh page, no second balance call.
    Future<void> afterPayment() {
      invalidateWalletQueries();
      // Joins the refetch the invalidation started.
      unawaited(loadBalance(stale: StaleTime.short));
      return pager.refresh();
    }

    Future<void> profileIncomplete(String message) async {
      final step = message == 'payment:wallet.incomplete_add' ? 'add' : 'pay';
      final update = await CAlert.show(
        title: 'payment:wallet.incomplete_title',
        message: message,
        primaryLabel: 'payment:wallet.update_profile',
        secondaryLabel: 'actions.cancel',
        variant: CAlertVariant.warning,
      );
      PaymentEvents.profileIncomplete(
        step: step,
        updateProfile: update == true,
      );
      if (update == true && context.mounted) {
        unawaited(context.push(AppRoutes.personalInfo));
      }
    }

    // History that can tell "never paid" (all / cash tab, loaded).
    Iterable<WalletTransaction>? paidHistory() {
      final st = pager.value;
      final usable =
          (st.filter == TransactionFilter.all ||
              st.filter == TransactionFilter.cash) &&
          st.page >= 1 &&
          st.error == null;
      return usable ? st.rows : null;
    }

    /// [source]: what opened Add Money (analytics).
    Future<void> addMoney({
      double? initialAmount,
      bool comeback = false,
      String source = 'wallet',
    }) async {
      final u = userRef.value;
      bool has(String key) => (J.str(u?[key]) ?? '').isNotEmpty;
      if (!has('name') || !has('email') || !has('mobile')) {
        return profileIncomplete('payment:wallet.incomplete_add');
      }
      PayerInfo payer() => PayerInfo.fromUser(userRef.value);
      final exit = await showAddMoney(
        context,
        flow: flow,
        payer: payer,
        initialAmount: initialAmount,
        source: source,
        bonus: TopUpBonus.resolve(
          config: configRef.value,
          history: paidHistory(),
          comeback: comeback,
        ),
      );
      if (exit == null || !context.mounted) return;
      final order = exit.checkout;
      if (exit.profileIncomplete || order == null) {
        return profileIncomplete('payment:wallet.incomplete_pay');
      }
      var abandoned = false;
      final status = await flow.pay(
        order,
        payer(),
        onAbandoned: () => abandoned = true,
        web: (request) => WebCheckoutPage.open(context, request),
      );
      if (!context.mounted) return;
      if (status == null) {
        // Closed by the user: offer a reason to come back, before they go.
        if (!abandoned || order is! RazorpayCheckout) return;
        final again = await WalletOffers.afterAbandon(
          context,
          config: configRef.value,
          order: order,
        );
        if (again != null && context.mounted) {
          await addMoney(
            initialAmount: again,
            comeback: true,
            source: 'abandon_offer',
          );
        }
        return;
      }
      if (status.result == TopUpResult.failure) {
        unawaited(
          Future<void>.delayed(failureRefreshDelay, () {
            if (context.mounted) unawaited(afterPayment());
          }),
        );
      } else {
        unawaited(afterPayment());
      }
      final shown = status.result.name;
      PaymentEvents.paymentStatusShown(
        status: shown,
        source: 'wallet',
        amount: order.baseAmount,
      );
      await showPaymentStatus(context, status);
      PaymentEvents.paymentStatusClosed(status: shown, source: 'wallet');
    }

    Future<void> transfer(WalletBalance? balance) async {
      final done = await showTransferSheet(
        context,
        cash: balance?.cashBalance ?? 0,
        earnings: balance?.earningsBalance ?? 0,
        source: 'wallet',
      );
      if (done) await refresh();
    }

    final invoice = useInvoicePdf();
    Future<void> openInvoice(TransactionRow row) async {
      final type = row.kind.name;
      try {
        final lookup = await invoice.mutateAsync(row.transaction);
        if (lookup == null) return;
        final url = lookup.url;
        if (url == null) {
          PaymentEvents.invoiceTapped(
            type: type,
            result: 'not_ready_${lookup.status.name}',
          );
          await CAlert.show(
            title: lookup.status.titleKey,
            message: lookup.status.messageKey,
          );
          return;
        }
        final uri = Uri.tryParse(url);
        final opened =
            uri != null &&
            await launchUrl(uri, mode: LaunchMode.externalApplication);
        PaymentEvents.invoiceTapped(
          type: type,
          result: opened ? 'opened' : 'shown_url',
        );
        if (!opened && context.mounted) {
          await CAlert.show(
            title: context.t('payment:tx.invoice_url_title'),
            message: url,
            translate: false,
          );
        }
      } on ApiException catch (e) {
        PaymentEvents.invoiceTapped(
          type: type,
          result: 'failed',
          error: Analytics.errorCode(e),
        );
        await CAlert.error(e, title: 'payment:tx.download_error_title');
      }
    }

    // Arriving from the call balance gate: straight to Add Money with the
    // amount; the first-top-up offer would only be in the way then.
    final prefill = prefillAmount;
    final offered = useRef(false);
    useEffect(() {
      if (prefill == null || !(prefill > 0)) return null;
      offered.value = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (context.mounted) {
          unawaited(addMoney(initialAmount: prefill, source: 'prefill'));
        }
      });
      return null;
    }, const []);

    // First-top-up offer, once the history shows whether they ever paid.
    // Re-checked when config lands: the flag may arrive after the history.
    final firstTopupOn = config.bonus.firstTopupOn;
    useEffect(() {
      void check() {
        final s = pager.value;
        if (offered.value ||
            !firstTopupOn ||
            s.filter != TransactionFilter.all ||
            s.loading ||
            s.error != null ||
            s.page < 1 ||
            !context.mounted) {
          return;
        }
        offered.value = true;
        // Never push a route mid-build (the effect runs during one).
        WidgetsBinding.instance.addPostFrameCallback((_) async {
          if (!context.mounted) return;
          final amount = await WalletOffers.firstTopup(
            context,
            config: configRef.value,
            history: s.rows,
          );
          if (amount != null && context.mounted) {
            await addMoney(
              initialAmount: amount.toDouble(),
              source: 'first_topup_offer',
            );
          }
        });
      }

      check();
      pager.addListener(check);
      return () => pager.removeListener(check);
    }, [pager, firstTopupOn]);

    // Transaction list analytics: load more, empty tabs, failed pages.
    useEffect(() {
      var prev = pager.value;
      final emptyLogged = <TransactionFilter>{};
      void watch() {
        final s = pager.value;
        final was = prev;
        prev = s;
        final tabName = s.filter.name;
        if (!was.loadingMore && s.loadingMore) {
          PaymentEvents.transactionsLoadMore(tab: tabName, page: s.page + 1);
        }
        if (s.loadMoreFailed && !was.loadMoreFailed) {
          PaymentEvents.transactionsLoadFailed(
            tab: tabName,
            page: s.page + 1,
            error: 'load_more',
          );
        }
        final error = s.error;
        if (error != null && !identical(error, was.error)) {
          PaymentEvents.transactionsLoadFailed(
            tab: tabName,
            page: 1,
            error: Analytics.errorCode(error),
          );
        }
        if (!s.loading &&
            error == null &&
            s.page >= 1 &&
            s.rows.isEmpty &&
            emptyLogged.add(s.filter)) {
          PaymentEvents.transactionsEmpty(tabName);
        }
      }

      pager.addListener(watch);
      return () => pager.removeListener(watch);
    }, [pager]);

    final bottomInset = MediaQuery.viewPaddingOf(context).bottom;
    return ThemedStatusBar(
      child: Scaffold(
        backgroundColor: p.bg,
        resizeToAvoidBottomInset: false,
        body: Stack(
          children: [
            const VibeBackground(),
            SafeArea(
              bottom: false,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const WalletHeader(),
                  _BalanceSection(
                    onAdd: () {
                      PaymentEvents.walletAction('add_money');
                      unawaited(addMoney());
                    },
                    onTransfer: (balance) {
                      PaymentEvents.walletAction(
                        'transfer',
                        balance: balance?.cashBalance,
                      );
                      unawaited(transfer(balance));
                    },
                  ),
                  // The admin's promo banners for the wallet, if any are live.
                  PromoBannerCarousel(
                    placement: PromoPlacement.wallet,
                    padding: EdgeInsets.fromLTRB(16.ms, 4.ms, 16.ms, 10.ms),
                  ),
                  TransactionTabs(
                    selected: tab,
                    onSelect: (filter) {
                      if (filter == tab.value) return;
                      tab.value = filter;
                      PaymentEvents.transactionsTab(filter.name);
                      unawaited(pager.select(filter));
                    },
                  ),
                  Padding(
                    padding: EdgeInsets.fromLTRB(16.ms, 0, 16.ms, 8.ms),
                    child: CText(
                      'payment:wallet.transactions',
                      size: 10,
                      weight: FontWeight.w900,
                      letterSpacing: 2,
                      color: p.muted,
                    ),
                  ),
                  Expanded(
                    child: TransactionList(
                      pager: pager,
                      myName: myName,
                      onRefresh: () {
                        PaymentEvents.walletRefreshed(tab: tab.value.name);
                        return refresh();
                      },
                      onInvoice: openInvoice,
                      bottomPadding: bottomInset,
                    ),
                  ),
                ],
              ),
            ),
            Positioned.fill(child: VerifyingOverlay(visible: flow.verifying)),
          ],
        ),
      ),
    );
  }
}

/// The balance card with its own balance subscription, so a balance update
/// rebuilds only the card.
class _BalanceSection extends HookWidget {
  const _BalanceSection({required this.onAdd, required this.onTransfer});

  final VoidCallback onAdd;
  final void Function(WalletBalance? balance) onTransfer;

  @override
  Widget build(BuildContext context) {
    final query = useWalletBalance(context);
    // RN shows 0 when the balance can't be read.
    final balance =
        query.data ?? (query.isError ? const WalletBalance([]) : null);
    return BalanceCard(
      balance: balance,
      // RN hides the cash / earnings split (and the transfer) on iOS.
      showSplit: defaultTargetPlatform != TargetPlatform.iOS,
      onAdd: onAdd,
      onTransfer: () => onTransfer(balance),
    );
  }
}
