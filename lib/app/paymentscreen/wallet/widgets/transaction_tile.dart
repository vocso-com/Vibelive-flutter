import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../../core/i18n/i18n.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/utils/scale.dart';
import '../../../component/c_loader.dart';
import '../../../component/c_text.dart';
import '../../../component/pressable.dart';
import '../helper/transaction_row.dart';
import '../helper/wallet_palette.dart';

/// One history card (RN `renderTransaction`).
class TransactionTile extends StatelessWidget {
  const TransactionTile({
    super.key,
    required this.row,
    required this.onInvoice,
  });

  final TransactionRow row;
  final Future<void> Function(TransactionRow row) onInvoice;

  @override
  Widget build(BuildContext context) {
    final p = WalletPalette.of(context);
    final credit = row.isCredit;
    final amountColor = credit ? WalletPalette.success : WalletPalette.error;
    final statusColor = switch (row.status) {
      TxStatus.success => WalletPalette.success,
      TxStatus.failure => WalletPalette.error,
      TxStatus.pending || TxStatus.abandoned => WalletPalette.pending,
    };
    final raw = row.rawStatus;
    final known =
        raw == null ||
        raw == 'success' ||
        raw == 'failure' ||
        raw == 'pending' ||
        raw == 'abandoned';
    final detail = row.detailKey;
    final vars = row.detailVariables;

    // One continuous list: rows flush to the edges, a single line between
    // them (no gaps, no rounded cards). Only the content is inset.
    return Container(
      padding: EdgeInsets.symmetric(horizontal: 16.ms, vertical: 14.ms),
      decoration: BoxDecoration(
        color: p.cardBg,
        border: Border(bottom: BorderSide(color: p.cardBorder)),
      ),
      child: Column(
        children: [
          Row(
            children: [
              Container(
                width: 44.ms,
                height: 44.ms,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: credit
                      ? WalletPalette.creditTile
                      : WalletPalette.debitTile,
                  borderRadius: BorderRadius.circular(14.ms),
                ),
                child: row.isTopupIcon
                    ? Icon(
                        Icons.account_balance_wallet_outlined,
                        size: 24.ms,
                        color: WalletPalette.success,
                      )
                    : credit
                    ? Icon(
                        Icons.payments_outlined,
                        size: 24.ms,
                        color: WalletPalette.success,
                      )
                    : Icon(
                        LucideIcons.arrowUpRight,
                        size: 20.ms,
                        color: WalletPalette.error,
                      ),
              ),
              SizedBox(width: 12.ms),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    CText(
                      row.titleKey,
                      size: 14,
                      weight: FontWeight.w800,
                      color: p.text,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    if (detail != null) ...[
                      SizedBox(height: 3.ms),
                      CText(
                        detail,
                        // Chat rows also carry `count`, and no `type`.
                        variables: vars == null
                            ? null
                            : {
                                ...vars,
                                'type': ?(vars['type'] == null
                                    ? null
                                    : context.t(vars['type']!)),
                                'name': (vars['name'] ?? '').isEmpty
                                    ? context.t('payment:tx.unknown')
                                    : vars['name'],
                              },
                        size: 12,
                        weight: FontWeight.w700,
                        color: p.muted,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                    SizedBox(height: 3.ms),
                    CText.raw(
                      row.reference,
                      size: 10,
                      weight: FontWeight.w700,
                      color: p.subtle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              SizedBox(width: 8.ms),
              ConstrainedBox(
                constraints: BoxConstraints(
                  // RN maxWidth '40%' of the row: screen minus list (16+16)
                  // and card (14+14, borders) insets.
                  maxWidth: (MediaQuery.sizeOf(context).width - 62.ms) * 0.4,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    FittedBox(
                      fit: BoxFit.scaleDown,
                      child: CText.raw(
                        '${credit ? '+' : '-'}₹${row.amount}',
                        size: 16,
                        weight: FontWeight.w900,
                        color: amountColor,
                        maxLines: 1,
                      ),
                    ),
                    SizedBox(height: 4.ms),
                    Container(
                      padding: EdgeInsets.symmetric(
                        horizontal: 8.ms,
                        vertical: 2.ms,
                      ),
                      decoration: BoxDecoration(
                        color: statusColor.withValues(alpha: 0x20 / 255),
                        borderRadius: BorderRadius.circular(6.ms),
                      ),
                      child: known
                          ? CText(
                              'payment:tx.status.${row.status.name}',
                              size: 9,
                              weight: FontWeight.w900,
                              letterSpacing: 1,
                              color: statusColor,
                              maxLines: 1,
                            )
                          : CText.raw(
                              raw.toUpperCase(),
                              size: 9,
                              weight: FontWeight.w900,
                              letterSpacing: 1,
                              color: statusColor,
                              maxLines: 1,
                            ),
                    ),
                    if (row.date != null) ...[
                      SizedBox(height: 7.ms),
                      CText(
                        'payment:tx.datetime',
                        variables: {'date': row.date, 'time': row.time},
                        size: 10,
                        weight: FontWeight.w600,
                        color: p.muted,
                        align: TextAlign.right,
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
          if (row.hasInvoice) _InvoiceAction(row: row, onInvoice: onInvoice),
        ],
      ),
    );
  }
}

/// "Invoice" pill under the row; spinner + "Loading..." while resolving.
class _InvoiceAction extends StatefulWidget {
  const _InvoiceAction({required this.row, required this.onInvoice});

  final TransactionRow row;
  final Future<void> Function(TransactionRow row) onInvoice;

  @override
  State<_InvoiceAction> createState() => _InvoiceActionState();
}

class _InvoiceActionState extends State<_InvoiceAction> {
  bool _busy = false;

  Future<void> _open() async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await widget.onInvoice(widget.row);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = WalletPalette.of(context);
    final dark = p.dark;
    final teal = dark ? BrandColors.teal : BrandColors.tealDark;
    return Container(
      margin: EdgeInsets.only(top: 10.ms),
      padding: EdgeInsets.only(top: 8.ms),
      decoration: BoxDecoration(
        border: Border(top: BorderSide(color: p.cardBorder)),
      ),
      alignment: Alignment.centerRight,
      child: Pressable(
        onPressed: _busy ? null : _open,
        child: Container(
          padding: EdgeInsets.symmetric(horizontal: 10.ms, vertical: 4.ms),
          decoration: BoxDecoration(
            color: dark ? const Color(0x1F2DD4BF) : const Color(0x1A14B8A6),
            borderRadius: BorderRadius.circular(8.ms),
            border: Border.all(
              color: dark ? const Color(0x402DD4BF) : const Color(0x3314B8A6),
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (_busy)
                CLoader(size: 12.ms, strokeWidth: 1.6, color: BrandColors.teal)
              else
                Icon(
                  LucideIcons.fileText,
                  size: 12.ms,
                  color: BrandColors.teal,
                ),
              SizedBox(width: 5.ms),
              CText(
                _busy ? 'payment:tx.invoice_loading' : 'payment:tx.invoice',
                size: 11,
                weight: FontWeight.w800,
                letterSpacing: 0.5,
                color: teal,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
