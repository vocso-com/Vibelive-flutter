import '../../../../core/network/strapi.dart';
import '../../../api/paymentscreen/wallet_models.dart';
import '../../../chatscreen/helper/chat_wallet_rows.dart';
import 'wallet_format.dart';

/// Payment status chip of a row. `abandoned`: an old order the backend
/// closed after checkout was left unpaid.
enum TxStatus { success, failure, pending, abandoned }

/// Bonus title per `metadata.bonus.reason` (RN `bonusLabels`).
const _bonusTitles = {
  'joining': 'payment:tx.bonus_joining',
  'first_topup': 'payment:tx.bonus_first_topup',
  'abandon_offer': 'payment:tx.bonus_credit',
  'expiry': 'payment:tx.bonus_expired',
};

/// What one history row shows (RN `renderTransaction`), computed once per
/// row so building the tile does no parsing.
class TransactionRow {
  const TransactionRow({
    required this.key,
    required this.transaction,
    required this.kind,
    required this.isCredit,
    required this.titleKey,
    required this.reference,
    required this.amount,
    required this.status,
    required this.rawStatus,
    required this.hasInvoice,
    this.detailKey,
    this.detailVariables,
    this.date,
    this.time,
  });

  factory TransactionRow.of(WalletTransaction tx, String? myName, int index) {
    final kind = tx.kindFor(myName);
    final credit = tx.isCreditFor(myName);
    final topup = tx.isTopupFor(myName);
    // A bonus is a topup row: without this it reads "Wallet Top Up", telling
    // someone they paid in money the platform gave them (RN).
    final isBonus = (tx.method ?? '').toLowerCase() == 'bonus';
    final bonusReason = J.str(Strapi.map(tx.metadata?['bonus'])?['reason']);

    String? detailKey;
    Map<String, String>? detailVars;
    // Chat and private-photo rows say who and how many (contract §6).
    final chat = isBonus
        ? null
        : ChatWalletRow.of(
            reference: tx.reference,
            note: J.str(tx.raw['Note']),
            metadata: tx.metadata,
          );
    if (chat != null) {
      detailKey = chat.detailKey;
      detailVars = chat.variables;
    } else if (isBonus) {
      detailKey = bonusReason == 'expiry'
          ? 'payment:tx.bonus_expired_detail'
          : 'payment:tx.bonus_added';
    } else if (kind == TransactionKind.walletTransfer) {
      detailKey = 'payment:tx.earnings_to_cash';
    } else if (!topup) {
      if (tx.isCommission) {
        detailKey = 'payment:tx.commission';
      } else {
        detailKey = credit ? 'payment:tx.call_from' : 'payment:tx.call_to';
        detailVars = {
          'type': switch (tx.callKind) {
            CallKind.audio => 'payment:tx.call_audio',
            CallKind.video => 'payment:tx.call_video',
            CallKind.other => 'payment:tx.call_other',
          },
          'name': tx.counterpartyFor(myName) ?? '',
        };
      }
    }

    final raw = tx.paymentStatus;
    final status = switch (raw) {
      'success' => TxStatus.success,
      'failure' => TxStatus.failure,
      'abandoned' => TxStatus.abandoned,
      _ => TxStatus.pending,
    };
    final created = tx.createdAt;
    final at = created == null ? null : WalletFormat.dateTime(created);
    final isCall = tx.raw['call'] != null;

    return TransactionRow(
      key: '${tx.id ?? tx.reference ?? index}',
      transaction: tx,
      kind: kind,
      isCredit: credit,
      titleKey: chat != null
          ? chat.titleKey
          : isBonus
          ? _bonusTitles[bonusReason] ?? 'payment:tx.bonus_credit'
          : switch (kind) {
              TransactionKind.walletTransfer => 'payment:tx.wallet_transfer',
              TransactionKind.topup => 'payment:tx.topup',
              TransactionKind.received => 'payment:tx.received',
              TransactionKind.paid => 'payment:tx.paid',
            },
      detailKey: detailKey,
      detailVariables: detailVars,
      reference: tx.reference ?? (tx.id != null ? '${tx.id}' : 'N/A'),
      amount: WalletFormat.amount2((tx.displayAmountFor(myName) ?? 0).abs()),
      status: status,
      rawStatus: raw,
      hasInvoice:
          tx.invoices.isNotEmpty ||
          ((topup || isCall) && status == TxStatus.success),
      date: at?.date,
      time: at?.time,
    );
  }

  final String key;
  final WalletTransaction transaction;
  final TransactionKind kind;
  final bool isCredit;
  final String titleKey;

  /// Second line; [detailVariables] holds `type` (an i18n key) and `name`
  /// (empty: show "Unknown").
  final String? detailKey;
  final Map<String, String>? detailVariables;

  /// `transaction_Id`, else the row id.
  final String reference;

  /// Absolute amount, two decimals.
  final String amount;
  final TxStatus status;

  /// Unknown statuses are shown as sent (RN uppercases the raw value).
  final String? rawStatus;
  final bool hasInvoice;
  final String? date;
  final String? time;

  bool get isTopupIcon =>
      kind == TransactionKind.topup || kind == TransactionKind.walletTransfer;

  /// Rows the wallet screen shows: commission rows are hidden (RN).
  static List<TransactionRow> visible(
    Iterable<WalletTransaction> rows,
    String? myName,
  ) {
    final out = <TransactionRow>[];
    var i = 0;
    for (final tx in rows) {
      if (!tx.isCommission) out.add(TransactionRow.of(tx, myName, i));
      i++;
    }
    return out;
  }
}
