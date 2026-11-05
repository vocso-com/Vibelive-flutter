import 'dart:io';

import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/vibe_colors.dart';
import '../../../core/utils/scale.dart';
import '../../api/chat/chat_models.dart';
import '../../api/listingflow/listing_models.dart';
import '../../component/c_button.dart';
import '../../component/c_text.dart';
import '../../listingflow/profile/helper/host_profile_rules.dart';
import '../../listingflow/profile/profile_sheets.dart';
import '../components/photo_bubble.dart';
import '../helper/chat_device.dart';
import '../helper/chat_pricing.dart';

// The chat's small sheets. Each returns what was picked; the screen acts
// once it has closed.

enum ChatMenuAction { prices, report, block }

/// ⋮: Prices (paying side), Report, Block.
Future<ChatMenuAction?> showChatMenu(
  BuildContext context, {
  required bool prices,
}) => showProfileSheet<ChatMenuAction>(context, (sheet) {
  final redBg = StatusColors.dangerRed.withValues(alpha: 0.12);
  final accent = sheet.colors.accent;
  void pick(ChatMenuAction a) => Navigator.of(sheet).pop(a);
  return SheetCard(
    handle: true,
    child: Padding(
      padding: EdgeInsets.symmetric(horizontal: 20.ms),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (prices)
            SheetActionRow(
              icon: LucideIcons.tag,
              tint: accent,
              label: 'chat:menu.prices',
              onTap: () => pick(ChatMenuAction.prices),
            ),
          SheetActionRow(
            icon: LucideIcons.flag,
            tint: StatusColors.dangerRed,
            iconBg: redBg,
            label: 'chat:menu.report',
            labelColor: StatusColors.dangerRed,
            onTap: () => pick(ChatMenuAction.report),
          ),
          SheetActionRow(
            icon: LucideIcons.userX,
            tint: StatusColors.dangerRed,
            iconBg: redBg,
            label: 'chat:menu.block',
            labelColor: StatusColors.dangerRed,
            onTap: () => pick(ChatMenuAction.block),
          ),
        ],
      ),
    ),
  );
}, name: 'chat_menu_sheet');

enum ChatAttach { gallery, camera, private }

/// The photo button: gallery, camera, and (host side) a private photo.
Future<ChatAttach?> showAttachSheet(
  BuildContext context, {
  required bool canSellPrivate,
}) => showProfileSheet<ChatAttach>(context, (sheet) {
  final accent = sheet.colors.accent;
  void pick(ChatAttach a) => Navigator.of(sheet).pop(a);
  return SheetCard(
    handle: true,
    child: Padding(
      padding: EdgeInsets.symmetric(horizontal: 20.ms),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          SheetActionRow(
            icon: LucideIcons.image,
            tint: accent,
            label: 'chat:composer.gallery',
            onTap: () => pick(ChatAttach.gallery),
          ),
          SheetActionRow(
            icon: LucideIcons.camera,
            tint: accent,
            label: 'chat:composer.camera',
            onTap: () => pick(ChatAttach.camera),
          ),
          if (canSellPrivate)
            SheetActionRow(
              icon: LucideIcons.lockKeyhole,
              tint: BrandColors.lime,
              label: 'chat:composer.private',
              onTap: () => pick(ChatAttach.private),
            ),
        ],
      ),
    ),
  );
}, name: 'chat_attach_sheet');

/// The picked photo; true to send. No price (only the menu's Prices sheet
/// shows chat prices).
Future<bool> confirmPhoto(
  BuildContext context, {
  required ChatPickedPhoto photo,
}) async {
  final ok = await showProfileSheet<bool>(context, (sheet) {
    final w = MediaQuery.sizeOf(sheet).width - 40.ms;
    final h = (w / chatAspect(photo.width, photo.height)).clamp(
      120.0,
      MediaQuery.sizeOf(sheet).height * 0.5,
    );
    return SheetCard(
      handle: true,
      child: Padding(
        padding: EdgeInsets.symmetric(horizontal: 20.ms),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(16.ms),
              child: Image.file(
                File(photo.path),
                width: w,
                height: h,
                fit: BoxFit.cover,
                cacheWidth: (w * MediaQuery.devicePixelRatioOf(sheet)).round(),
              ),
            ),
            SizedBox(height: 16.ms),
            CButton(
              key: const ValueKey('chat-photo-send'),
              title: 'chat:composer.send_photo',
              showArrow: false,
              onPressed: () => Navigator.of(sheet).pop(true),
            ),
          ],
        ),
      ),
    );
  }, name: 'chat_photo_confirm_sheet');
  return ok ?? false;
}

/// "Unlock this photo?": price, where it comes from, what is in the
/// wallet. True to pay.
Future<bool> confirmUnlock(
  BuildContext context, {
  required double price,
  required double? balance,
  required String from,
  required int minutes,
}) async {
  final money = ChatPricing.money(price);
  final ok = await showProfileSheet<bool>(context, (sheet) {
    final accent = sheet.colors.accent;
    return SheetCard(
      handle: true,
      child: Padding(
        padding: EdgeInsets.symmetric(horizontal: 20.ms),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 56.ms,
              height: 56.ms,
              decoration: BoxDecoration(
                color: accent.withValues(alpha: 0.14),
                shape: BoxShape.circle,
              ),
              child: Icon(LucideIcons.lockOpen, color: accent, size: 26.ms),
            ),
            SizedBox(height: 12.ms),
            const CText(
              'chat:private.confirm_title',
              size: 18,
              weight: FontWeight.w800,
              align: TextAlign.center,
            ),
            SizedBox(height: 6.ms),
            CText(
              'chat:private.confirm_body',
              variables: {'name': from, 'price': money},
              size: 13.5,
              weight: FontWeight.w500,
              align: TextAlign.center,
            ),
            if (minutes > 0) ...[
              SizedBox(height: 4.ms),
              CText(
                'chat:private.confirm_minutes',
                count: minutes,
                size: 13,
                weight: FontWeight.w500,
                align: TextAlign.center,
              ),
            ],
            if (balance != null) ...[
              SizedBox(height: 4.ms),
              CText(
                'chat:private.confirm_balance',
                variables: {'balance': ChatPricing.money(balance)},
                size: 12,
                weight: FontWeight.w600,
                align: TextAlign.center,
              ),
            ],
            SizedBox(height: 16.ms),
            CButton(
              key: const ValueKey('chat-unlock-confirm'),
              title: 'chat:private.confirm_button',
              titleVariables: {'price': money},
              showArrow: false,
              onPressed: () => Navigator.of(sheet).pop(true),
            ),
          ],
        ),
      ),
    );
  }, name: 'chat_unlock_sheet');
  return ok ?? false;
}

enum FailedAction { retry, remove }

/// A failed bubble tapped: send again (same clientId) or remove it.
Future<FailedAction?> showFailedActions(BuildContext context) =>
    showProfileSheet<FailedAction>(context, (sheet) {
      final accent = sheet.colors.accent;
      return SheetCard(
        handle: true,
        child: Padding(
          padding: EdgeInsets.symmetric(horizontal: 20.ms),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              SheetActionRow(
                icon: LucideIcons.refreshCw,
                tint: accent,
                label: 'chat:bubble.retry',
                onTap: () => Navigator.of(sheet).pop(FailedAction.retry),
              ),
              SheetActionRow(
                icon: LucideIcons.trash2,
                tint: StatusColors.dangerRed,
                label: 'chat:bubble.delete',
                labelColor: StatusColors.dangerRed,
                onTap: () => Navigator.of(sheet).pop(FailedAction.remove),
              ),
            ],
          ),
        ),
      );
    }, name: 'chat_failed_sheet');

/// Menu → Prices (paying side): every message type, the host's call
/// rates when known, and the balance.
Future<bool> showChatPrices(
  BuildContext context, {
  required ChatOpen open,
  required ChatConfig config,
  required double? balance,
  HostCard? host,
}) async {
  final added = await showProfileSheet<bool>(context, (sheet) {
    final v = config.voice;
    // The host sees what they EARN (their share of what the user pays, paid when
    // they reply); the client sees what they PAY. Same split as calls.
    final isHost = open.mySide == ChatSide.host;
    final share = config.hostSharePercent / 100.0;
    String amt(double rupees) =>
        ChatPricing.money(isHost ? rupees * share : rupees);
    final rows = <(IconData, String, String, Map<String, String>?)>[
      (
        LucideIcons.messageCircle,
        'chat:prices.message',
        amt(open.pricePerMessage),
        null,
      ),
      (LucideIcons.image, 'chat:prices.photo', amt(open.imagePrice), null),
      (
        LucideIcons.mic,
        'chat:prices.voice',
        amt(v.shortPrice),
        {
          'short': '${v.shortSec}',
          'shortPrice': amt(v.shortPrice),
          'long': '${v.longSec}',
          'longPrice': amt(v.longPrice),
          'step': '${v.stepSec}',
          'stepPrice': amt(v.stepPrice),
        },
      ),
      // Call rates are what the caller pays to call — only for the paying side.
      if (!isHost && host != null && host.aPrice > 0)
        (
          LucideIcons.phone,
          'chat:prices.voice_call',
          '₹${HostProfileRules.price(host.aPrice)}',
          null,
        ),
      if (!isHost && host != null && host.vPrice > 0)
        (
          LucideIcons.video,
          'chat:prices.video_call',
          '₹${HostProfileRules.price(host.vPrice)}',
          null,
        ),
    ];
    final muted = sheet.colors.textMuted;
    return SheetCard(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SheetHeader(
            icon: LucideIcons.tag,
            iconColor: BrandColors.lime,
            title: isHost ? 'chat:prices.earn_title' : 'chat:prices.title',
          ),
          Padding(
            padding: EdgeInsets.fromLTRB(20.ms, 14.ms, 20.ms, 0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                CText(
                  'chat:prices.with',
                  variables: {'name': open.peer.name},
                  size: 12.5,
                  weight: FontWeight.w600,
                  color: muted,
                  maxLines: 1,
                ),
                SizedBox(height: 8.ms),
                for (final (icon, label, price, ladder) in rows)
                  _PriceRow(
                    icon: icon,
                    label: label,
                    price: price,
                    unit: isHost
                        ? 'chat:prices.you_earn'
                        : label.endsWith('_call')
                        ? 'chat:prices.per_min'
                        : (ladder != null
                              ? 'chat:prices.from'
                              : 'chat:prices.each'),
                    note: ladder == null ? null : 'chat:prices.voice_ladder',
                    noteVariables: ladder,
                  ),
                SizedBox(height: 8.ms),
                // Host: their earnings total, no recharge. Client: cash balance + Add money.
                if (isHost)
                  CText(
                    'chat:prices.your_earnings',
                    variables: {
                      'amount': ChatPricing.money(open.earnings ?? balance ?? 0),
                    },
                    size: 14,
                    weight: FontWeight.w800,
                    maxLines: 1,
                  )
                else
                  Row(
                    children: [
                      Expanded(
                        child: CText(
                          'chat:prices.balance',
                          variables: {
                            'balance': ChatPricing.money(balance ?? 0),
                          },
                          size: 14,
                          weight: FontWeight.w800,
                          maxLines: 1,
                        ),
                      ),
                      SizedBox(width: 10.ms),
                      // A width of its own: in a Row a CButton would take
                      // all of it (infinite) and the sheet failed to lay out.
                      CButton(
                        key: const ValueKey('chat-prices-add-money'),
                        title: 'chat:low_balance.add',
                        variant: CButtonVariant.small,
                        showArrow: false,
                        width: 124.ms,
                        height: 40.ms,
                        onPressed: () => Navigator.of(sheet).pop(true),
                      ),
                    ],
                  ),
                SizedBox(height: 10.ms),
                CText(
                  isHost ? 'chat:prices.earn_note' : 'chat:prices.note',
                  size: 11.5,
                  weight: FontWeight.w500,
                  color: muted,
                  align: TextAlign.center,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }, name: 'chat_prices_sheet');
  return added ?? false;
}

class _PriceRow extends StatelessWidget {
  const _PriceRow({
    required this.icon,
    required this.label,
    required this.price,
    required this.unit,
    this.note,
    this.noteVariables,
  });

  final IconData icon;
  final String label;
  final String price;
  final String unit;
  final String? note;
  final Map<String, String>? noteVariables;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final muted = c.textMuted;
    return Padding(
      padding: EdgeInsets.symmetric(vertical: 7.ms),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 18.ms, color: c.accent),
          SizedBox(width: 12.ms),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                CText(label, size: 14, weight: FontWeight.w700, maxLines: 1),
                if (note != null)
                  CText(
                    note!,
                    variables: noteVariables,
                    size: 11.5,
                    weight: FontWeight.w500,
                    color: muted,
                    maxLines: 3,
                  ),
              ],
            ),
          ),
          SizedBox(width: 8.ms),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              CText.raw(price, size: 15, weight: FontWeight.w900, maxLines: 1),
              CText(
                unit,
                size: 10.5,
                weight: FontWeight.w600,
                color: muted,
                maxLines: 1,
              ),
            ],
          ),
        ],
      ),
    );
  }
}
