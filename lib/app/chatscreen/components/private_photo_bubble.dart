import 'dart:async';
import 'dart:io';

import 'package:clock/clock.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../core/i18n/i18n.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/utils/scale.dart';
import '../../api/chat/chat_models.dart';
import '../../component/c_image.dart';
import '../../component/c_loader.dart';
import '../../component/c_text.dart';
import '../../component/c_toast.dart';
import '../../component/pressable.dart';
import '../helper/chat_format.dart';
import '../helper/chat_pricing.dart';
import '../helper/chat_room_controller.dart';
import 'chat_palette.dart';
import 'message_ticks.dart';
import 'photo_bubble.dart';

/// A host's private photo. Everyone sees only the server's blurred copy
/// (the host who sent it too); the photo itself opens only in the viewer,
/// only for the buyer, only for a while:
///  - not bought: a lock and "Unlock · ₹99";
///  - bought: "Tap to view" and the time left, then "Photo expired";
///  - the host's own: the price and whether it sold.
class PrivatePhotoBubble extends StatelessWidget {
  const PrivatePhotoBubble({
    super.key,
    required this.message,
    required this.mine,
    required this.maxWidth,
    required this.receipts,
    required this.onUnlock,
    required this.onOpen,
  });

  final ChatMessage message;
  final bool mine;
  final double maxWidth;
  final ValueListenable<ChatReceiptMarks> receipts;
  final VoidCallback onUnlock;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    final m = message;
    final p = m.privatePhoto ?? const ChatPrivatePhoto(price: 0);
    final width = maxWidth * 0.8 > 250.ms ? 250.ms : maxWidth * 0.8;
    final height = width / chatAspect(p.previewWidth, p.previewHeight);
    final price = ChatPricing.money(p.price);
    final local = m.localPath;
    final sending =
        m.state == ChatSendState.sending || m.state == ChatSendState.queued;

    final Widget overlay;
    if (mine) {
      overlay = _Veil(
        icon: LucideIcons.lock,
        title: 'chat:private.title',
        note: 'chat:private.mine_note',
        onTap: sending ? null : () => CToast.show('chat:private.mine_toast'),
      );
    } else if (!p.unlocked) {
      overlay = _Veil(
        icon: LucideIcons.lock,
        title: 'chat:private.title',
        onTap: onUnlock,
        action: _UnlockButton(price: price, onTap: onUnlock),
      );
    } else {
      overlay = _Bought(photo: p, onOpen: onOpen);
    }

    final label = mine
        ? context.t('chat:private.a11y_mine', variables: {'price': price})
        : p.unlocked
        ? context.t('chat:private.a11y_bought')
        : context.t('chat:private.a11y_locked', variables: {'price': price});

    return Semantics(
      label: label,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(ChatPalette.radius),
        child: SizedBox(
          width: width,
          height: height,
          child: Stack(
            fit: StackFit.expand,
            children: [
              // My own while it sends: decoded tiny, so it is as smoky as
              // the server's copy without a live blur.
              if (local != null)
                Image.file(
                  File(local),
                  fit: BoxFit.cover,
                  cacheWidth: 24,
                  filterQuality: FilterQuality.medium,
                  gaplessPlayback: true,
                )
              else
                CImage(url: p.previewUrl, width: width, height: height),
              overlay,
              if (mine)
                PositionedDirectional(
                  start: 8.ms,
                  top: 8.ms,
                  child: _PriceBadge(price: price, sold: p.unlocked),
                ),
              PositionedDirectional(
                end: 8.ms,
                bottom: 6.ms,
                child: MessageMeta(
                  message: m,
                  mine: mine,
                  receipts: receipts,
                  onMedia: true,
                ),
              ),
              if (sending)
                ColoredBox(
                  color: AppColors.blackA(0.2),
                  child: const Center(
                    child: RepaintBoundary(
                      child: CLoader(color: AppColors.white),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Over the blurred copy: an icon, what it is, a line, maybe a button.
class _Veil extends StatelessWidget {
  const _Veil({
    required this.icon,
    required this.title,
    this.note,
    this.noteVariables,
    this.action,
    this.onTap,
  });

  final IconData icon;
  final String title;
  final String? note;
  final Map<String, dynamic>? noteVariables;
  final Widget? action;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: ColoredBox(
        color: AppColors.blackA(0.22),
        child: Center(
          child: Padding(
            padding: EdgeInsets.symmetric(horizontal: 12.ms),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 44.ms,
                  height: 44.ms,
                  decoration: BoxDecoration(
                    color: AppColors.whiteA(0.22),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(icon, color: AppColors.white, size: 22.ms),
                ),
                SizedBox(height: 8.ms),
                CText(
                  title,
                  size: 14,
                  weight: FontWeight.w800,
                  color: AppColors.white,
                  maxLines: 1,
                  align: TextAlign.center,
                ),
                if (note != null) ...[
                  SizedBox(height: 2.ms),
                  CText(
                    note!,
                    variables: noteVariables,
                    size: 11.5,
                    weight: FontWeight.w600,
                    color: AppColors.whiteA(0.85),
                    maxLines: 2,
                    align: TextAlign.center,
                  ),
                ],
                if (action != null) ...[SizedBox(height: 10.ms), action!],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _UnlockButton extends StatelessWidget {
  const _UnlockButton({required this.price, required this.onTap});

  final String price;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final p = ChatPalette.of(context);
    return Pressable(
      onPressed: onTap,
      activeOpacity: 0.85,
      child: Container(
        padding: EdgeInsets.symmetric(horizontal: 14.ms, vertical: 8.ms),
        decoration: BoxDecoration(
          color: p.accent,
          borderRadius: BorderRadius.circular(999),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(LucideIcons.lockOpen, size: 15.ms, color: p.onAccent),
            SizedBox(width: 6.ms),
            Flexible(
              child: CText(
                'chat:private.unlock',
                variables: {'price': price},
                size: 13,
                weight: FontWeight.w800,
                color: p.onAccent,
                maxLines: 1,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Bought: "Tap to view" with the time left (ticking, this widget only),
/// then "Photo expired" for good.
class _Bought extends StatefulWidget {
  const _Bought({required this.photo, required this.onOpen});

  final ChatPrivatePhoto photo;
  final VoidCallback onOpen;

  @override
  State<_Bought> createState() => _BoughtState();
}

class _BoughtState extends State<_Bought> {
  Timer? _tick;

  @override
  void initState() {
    super.initState();
    _start();
  }

  @override
  void didUpdateWidget(_Bought old) {
    super.didUpdateWidget(old);
    _start();
  }

  void _start() {
    if (_tick != null || !widget.photo.canOpenAt(clock.now())) return;
    _tick = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      if (!widget.photo.canOpenAt(clock.now())) {
        _tick?.cancel();
        _tick = null;
      }
      setState(() {});
    });
  }

  @override
  void dispose() {
    _tick?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final p = widget.photo;
    final now = clock.now();
    if (!p.canOpenAt(now)) {
      return _Veil(
        icon: LucideIcons.timerOff,
        title: 'chat:private.expired',
        note: 'chat:private.expired_note',
        onTap: () => CToast.show('chat:private.cannot_open'),
      );
    }
    return RepaintBoundary(
      child: _Veil(
        icon: LucideIcons.eye,
        title: 'chat:private.tap_view',
        note: 'chat:private.left',
        noteVariables: {'time': ChatFormat.countdown(p.expiresAt!, now)},
        onTap: widget.onOpen,
      ),
    );
  }
}

/// On the host's own: the price, and whether it sold.
class _PriceBadge extends StatelessWidget {
  const _PriceBadge({required this.price, required this.sold});

  final String price;
  final bool sold;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsetsDirectional.fromSTEB(7.ms, 3.ms, 9.ms, 3.ms),
      decoration: BoxDecoration(
        color: AppColors.blackA(0.6),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            sold ? LucideIcons.circleCheck : LucideIcons.lock,
            color: AppColors.white,
            size: 12.ms,
          ),
          SizedBox(width: 4.ms),
          CText(
            sold ? 'chat:private.sold' : 'chat:private.on_sale',
            variables: {'price': price},
            size: 10.5,
            weight: FontWeight.w700,
            color: AppColors.white,
            maxLines: 1,
          ),
        ],
      ),
    );
  }
}
