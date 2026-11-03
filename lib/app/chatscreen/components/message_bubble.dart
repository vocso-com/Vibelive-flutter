import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart' show Bidi;

import '../../../core/utils/scale.dart';
import '../../api/chat/chat_models.dart';
import '../../component/c_text.dart';
import '../../component/pressable.dart';
import '../helper/chat_room_controller.dart';
import '../helper/chat_rows.dart';
import 'bubble_frame.dart';
import 'chat_palette.dart';
import 'date_separator.dart';
import 'message_ticks.dart';
import 'photo_bubble.dart';
import 'private_photo_bubble.dart';
import 'voice_player.dart';

/// What a bubble can ask the screen to do. One object for the whole list
/// (the screen), so a row never needs a new closure to stay the same.
abstract interface class ChatBubbleActions {
  /// A failed bubble tapped: retry (same clientId) or remove.
  void onFailedTap(ChatMessage m);
  void onCopy(ChatMessage m);
  void onOpenPhoto(ChatMessage m);
  void onUnlock(ChatMessage m);
  void onOpenPrivate(ChatMessage m);
}

/// One row: the date separator when a day starts, then the bubble on my
/// side (end) or theirs (start). RTL-safe: sides follow the reading
/// direction.
class ChatMessageRow extends StatelessWidget {
  const ChatMessageRow({
    super.key,
    required this.row,
    required this.receipts,
    required this.actions,
  });

  final ChatRow row;
  final ValueListenable<ChatReceiptMarks> receipts;
  final ChatBubbleActions actions;

  @override
  Widget build(BuildContext context) {
    final m = row.message;
    final mine = row.mine;
    final max = ChatPalette.bubbleMax(context);
    final failed = m.state == ChatSendState.failed;
    final meta = MessageMeta(message: m, mine: mine, receipts: receipts);

    final Widget bubble = switch (m.type) {
      ChatMessageType.text => _TextBubble(
        message: m,
        mine: mine,
        tail: !row.joinNewer,
        meta: meta,
        onLongPress: failed ? null : () => actions.onCopy(m),
      ),
      ChatMessageType.image => PhotoBubble(
        message: m,
        mine: mine,
        maxWidth: max,
        receipts: receipts,
        onOpen: () => actions.onOpenPhoto(m),
      ),
      ChatMessageType.audio => VoiceBubble(
        message: m,
        mine: mine,
        tail: !row.joinNewer,
        meta: meta,
      ),
      ChatMessageType.privateImage => PrivatePhotoBubble(
        message: m,
        mine: mine,
        maxWidth: max,
        receipts: receipts,
        onUnlock: () => actions.onUnlock(m),
        onOpen: () => actions.onOpenPrivate(m),
      ),
      ChatMessageType.unknown => _TextBubble(
        message: m,
        mine: mine,
        tail: !row.joinNewer,
        meta: meta,
        unsupported: true,
      ),
    };

    final aligned = Align(
      alignment: mine
          ? AlignmentDirectional.centerEnd
          : AlignmentDirectional.centerStart,
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: max),
        child: Column(
          crossAxisAlignment: mine
              ? CrossAxisAlignment.end
              : CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            if (failed)
              Pressable(onPressed: () => actions.onFailedTap(m), child: bubble)
            else
              bubble,
            if (failed) FailedNote(reasonKey: m.errorKey),
          ],
        ),
      ),
    );

    final day = row.dayBreak;
    return Padding(
      padding: EdgeInsetsDirectional.only(
        top: row.joinOlder ? 2.ms : 8.ms,
        start: 12.ms,
        end: 12.ms,
      ),
      child: day == null
          ? aligned
          : Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                ChatDateSeparator(day: day),
                aligned,
              ],
            ),
    );
  }
}

class _TextBubble extends StatelessWidget {
  const _TextBubble({
    required this.message,
    required this.mine,
    required this.tail,
    required this.meta,
    this.onLongPress,
    this.unsupported = false,
  });

  final ChatMessage message;
  final bool mine;
  final bool tail;
  final Widget meta;
  final VoidCallback? onLongPress;
  final bool unsupported;

  @override
  Widget build(BuildContext context) {
    final p = ChatPalette.of(context);
    final text = message.text ?? '';
    final color = mine ? p.onMine : p.onTheirs;
    // Each message reads in its own script's direction (an English line in
    // an Urdu chat, or the other way round).
    final rtl = text.isNotEmpty && Bidi.detectRtlDirectionality(text);
    final body = unsupported
        ? CText(
            'chat:bubble.unsupported',
            size: 14,
            italic: true,
            weight: FontWeight.w500,
            color: color.withValues(alpha: 0.75),
          )
        : Text(
            text,
            textDirection: rtl ? TextDirection.rtl : TextDirection.ltr,
            // Large text is honoured here, up to where bubbles still fit.
            textScaler: ChatPalette.textScaler(context),
            style: TextStyle(
              fontSize: 15.5.ms,
              height: 1.32,
              fontWeight: FontWeight.w500,
              color: color,
            ),
          );
    return GestureDetector(
      onLongPress: onLongPress,
      child: BubbleFrame(
        mine: mine,
        tail: tail,
        child: Wrap(
          alignment: WrapAlignment.end,
          crossAxisAlignment: WrapCrossAlignment.end,
          spacing: 8.ms,
          runSpacing: 2.ms,
          children: [
            body,
            Padding(
              padding: EdgeInsets.only(top: 4.ms),
              child: meta,
            ),
          ],
        ),
      ),
    );
  }
}
