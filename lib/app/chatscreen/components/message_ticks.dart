import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../core/i18n/i18n.dart';
import '../../../core/utils/scale.dart';
import '../../api/chat/chat_models.dart';
import '../../component/c_text.dart';
import '../helper/chat_format.dart';
import '../helper/chat_room_controller.dart';
import '../helper/chat_rows.dart';
import 'chat_palette.dart';

/// Time, then (mine) sent / delivered / read ticks. Only this listens to
/// the conversation's receipt marks, so a "read" repaints ticks, not
/// bubbles.
class MessageMeta extends StatelessWidget {
  const MessageMeta({
    super.key,
    required this.message,
    required this.mine,
    required this.receipts,
    this.onMedia = false,
  });

  final ChatMessage message;
  final bool mine;
  final ValueListenable<ChatReceiptMarks> receipts;

  /// Over a photo: white on a scrim.
  final bool onMedia;

  @override
  Widget build(BuildContext context) {
    final p = ChatPalette.of(context);
    final color = onMedia
        ? const Color(0xFFFFFFFF)
        : (mine ? p.mineMeta : p.theirsMeta);
    final time = ChatFormat.of(
      Localizations.localeOf(context).toLanguageTag(),
    ).time(message.createdAt);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        CText.raw(
          time,
          size: 10.5,
          weight: FontWeight.w600,
          color: color,
          maxLines: 1,
        ),
        if (mine) ...[
          SizedBox(width: 3.ms),
          ValueListenableBuilder<ChatReceiptMarks>(
            valueListenable: receipts,
            builder: (_, marks, _) => MessageTick(
              tick: ChatRows.tickFor(
                message,
                mine: true,
                peerDeliveredAt: marks.delivered,
                peerReadAt: marks.read,
              ),
              color: color,
              readColor: onMedia ? const Color(0xFF7DD3FC) : p.read,
            ),
          ),
        ],
      ],
    );
  }
}

class MessageTick extends StatelessWidget {
  const MessageTick({
    super.key,
    required this.tick,
    required this.color,
    required this.readColor,
  });

  final ChatTick tick;
  final Color color;
  final Color readColor;

  @override
  Widget build(BuildContext context) {
    final p = ChatPalette.of(context);
    final (icon, tint, label) = switch (tick) {
      ChatTick.queued => (LucideIcons.clock3, color, 'chat:bubble.tick_queued'),
      ChatTick.failed => (
        LucideIcons.circleAlert,
        p.failed,
        'chat:bubble.failed',
      ),
      ChatTick.sent => (LucideIcons.check, color, 'chat:bubble.tick_sent'),
      ChatTick.delivered => (
        LucideIcons.checkCheck,
        color,
        'chat:bubble.tick_delivered',
      ),
      ChatTick.read => (
        LucideIcons.checkCheck,
        readColor,
        'chat:bubble.tick_read',
      ),
      ChatTick.none => (null, color, ''),
    };
    if (icon == null) return const SizedBox.shrink();
    return Semantics(
      label: context.t(label),
      child: Icon(icon, size: 14.ms, color: tint),
    );
  }
}

/// "Not sent · tap to retry" under a failed bubble.
class FailedNote extends StatelessWidget {
  const FailedNote({super.key, this.reasonKey});

  final String? reasonKey;

  @override
  Widget build(BuildContext context) {
    final p = ChatPalette.of(context);
    return Padding(
      padding: EdgeInsets.only(top: 3.ms),
      child: CText(
        'chat:bubble.failed',
        size: 11,
        weight: FontWeight.w700,
        color: p.failed,
        maxLines: 1,
      ),
    );
  }
}
