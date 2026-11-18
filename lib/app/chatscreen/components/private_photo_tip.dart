import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../core/i18n/i18n.dart';
import '../../../core/utils/scale.dart';
import '../../component/c_text.dart';
import '../../component/pressable.dart';
import '../helper/chat_pricing.dart';
import 'chat_palette.dart';

/// Points a host at private photos (see `PrivatePhotoPromo`): the card above
/// the composer ([onAction]: "Send one") or, with [onAction] null, the banner
/// at the top of the Chats list. [min]/[max]: what the host may choose to earn
/// per photo (admin's private photo rules). Always closable.
class PrivatePhotoTip extends StatelessWidget {
  const PrivatePhotoTip({
    super.key,
    required this.min,
    required this.max,
    required this.onClose,
    this.onAction,
  });

  final double min;
  final double max;
  final VoidCallback onClose;
  final VoidCallback? onAction;

  bool get _inChat => onAction != null;

  @override
  Widget build(BuildContext context) {
    final p = ChatPalette.of(context);
    final vars = {'min': ChatPricing.money(min), 'max': ChatPricing.money(max)};
    final title = _inChat
        ? 'chat:private_promo.tip_title'
        : 'chat:private_promo.list_title';
    final body = _inChat
        ? 'chat:private_promo.tip_body'
        : 'chat:private_promo.list_body';
    return Container(
      key: ValueKey(_inChat ? 'private-promo-tip' : 'private-promo-list'),
      margin: _inChat
          ? EdgeInsetsDirectional.fromSTEB(12.ms, 8.ms, 12.ms, 2.ms)
          : EdgeInsetsDirectional.fromSTEB(16.ms, 4.ms, 16.ms, 10.ms),
      padding: EdgeInsetsDirectional.fromSTEB(12.ms, 12.ms, 6.ms, 12.ms),
      decoration: BoxDecoration(
        color: p.accent.withValues(alpha: p.dark ? 0.12 : 0.07),
        borderRadius: BorderRadius.circular(16.ms),
        border: Border.all(color: p.accent.withValues(alpha: 0.28)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 36.ms,
            height: 36.ms,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: p.accent.withValues(alpha: p.dark ? 0.2 : 0.12),
              borderRadius: BorderRadius.circular(12.ms),
            ),
            child: Icon(LucideIcons.lockKeyhole, size: 18.ms, color: p.accent),
          ),
          SizedBox(width: 10.ms),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                CText(title, size: 14, weight: FontWeight.w800, color: p.text),
                SizedBox(height: 3.ms),
                CText(
                  body,
                  variables: vars,
                  size: 12.5,
                  height: 17,
                  weight: FontWeight.w500,
                  color: p.muted,
                ),
                if (_inChat) ...[
                  SizedBox(height: 9.ms),
                  Pressable(
                    key: const ValueKey('private-promo-send'),
                    onPressed: onAction,
                    child: Container(
                      padding: EdgeInsets.symmetric(
                        horizontal: 14.ms,
                        vertical: 7.ms,
                      ),
                      decoration: BoxDecoration(
                        color: p.accent,
                        borderRadius: BorderRadius.circular(999),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            LucideIcons.imagePlus,
                            size: 14.ms,
                            color: p.onAccent,
                          ),
                          SizedBox(width: 6.ms),
                          CText(
                            'chat:private_promo.tip_action',
                            size: 12.5,
                            weight: FontWeight.w800,
                            color: p.onAccent,
                            maxLines: 1,
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
          Pressable(
            key: ValueKey(
              _inChat ? 'private-promo-tip-close' : 'private-promo-list-close',
            ),
            onPressed: onClose,
            semanticLabel: context.t('chat:private_promo.close'),
            hitPadding: EdgeInsets.all(6.ms),
            child: Padding(
              padding: EdgeInsets.all(4.ms),
              child: Icon(LucideIcons.x, size: 16.ms, color: p.muted),
            ),
          ),
        ],
      ),
    );
  }
}

/// The small "New" pill (the attach sheet's private photo row).
class PrivatePhotoNewPill extends StatelessWidget {
  const PrivatePhotoNewPill({super.key, required this.color, this.onColor});

  final Color color;
  final Color? onColor;

  @override
  Widget build(BuildContext context) => Container(
    key: const ValueKey('private-promo-new'),
    padding: EdgeInsets.symmetric(horizontal: 8.ms, vertical: 3.ms),
    decoration: BoxDecoration(
      color: color,
      borderRadius: BorderRadius.circular(999),
    ),
    child: CText(
      'chat:private_promo.new',
      size: 11,
      weight: FontWeight.w800,
      color: onColor ?? Colors.white,
      maxLines: 1,
    ),
  );
}
