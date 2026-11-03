import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../core/i18n/i18n.dart';
import '../../../core/utils/scale.dart';
import '../../api/chat/chat_models.dart';
import '../../component/c_text.dart';
import '../../component/pressable.dart';
import '../../component/verification_badge.dart';
import '../components/chat_header.dart';
import '../components/chat_palette.dart';
import '../helper/chat_format.dart';

/// One chat in the list: photo (with the host's online dot), name, the
/// last message ("You: …", or Photo / Voice message), time and unread
/// count. Fixed height: the list lays rows out without measuring them.
class ConversationRow extends StatelessWidget {
  const ConversationRow({
    super.key,
    required this.conversation,
    required this.me,
    required this.onTap,
  });

  final ChatConversation conversation;
  final String? me;
  final ValueChanged<ChatConversation> onTap;

  static double get extent => 76.ms;

  @override
  Widget build(BuildContext context) {
    final p = ChatPalette.of(context);
    final c = conversation;
    final peer = c.peer;
    final unread = c.unread > 0;
    final name = peer.deleted || peer.name.isEmpty
        ? context.t(
            peer.deleted ? 'chat:list.deleted_user' : 'chat:list.someone',
          )
        : peer.name;
    final last = c.lastMessage;
    final (IconData? icon, String? key) = switch (last?.type) {
      ChatMessageType.image => (LucideIcons.image, 'chat:list.photo'),
      ChatMessageType.audio => (LucideIcons.mic, 'chat:list.voice'),
      ChatMessageType.privateImage => (
        LucideIcons.lock,
        'chat:list.private_photo',
      ),
      ChatMessageType.unknown => (null, 'chat:list.unsupported'),
      _ => (null, null),
    };
    final mine = last?.senderId != null && last!.senderId == me;
    final preview = key != null ? context.t(key) : (last?.text ?? '');
    final at = c.updatedAt ?? last?.at;
    final time = at == null
        ? null
        : ChatFormat.of(
            Localizations.localeOf(context).toLanguageTag(),
          ).listTime(at);
    final timeText = time == null
        ? ''
        : (time.key != null ? context.t(time.key!) : time.text ?? '');

    return Pressable(
      onPressed: () => onTap(c),
      activeOpacity: 0.8,
      child: SizedBox(
        height: extent,
        child: Padding(
          padding: EdgeInsets.symmetric(horizontal: 20.ms),
          child: Row(
            children: [
              ChatAvatar(
                url: peer.avatar,
                name: name,
                size: 52,
                online: peer.isHost && peer.online && !peer.busy,
                busy: peer.isHost && peer.busy,
              ),
              SizedBox(width: 12.ms),
              Expanded(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: CText.raw(
                            name,
                            size: 15.5,
                            weight: unread ? FontWeight.w900 : FontWeight.w700,
                            color: p.text,
                            maxLines: 1,
                          ),
                        ),
                        if (peer.verified) ...[
                          SizedBox(width: 4.ms),
                          const VerificationBadge(
                            user: {'verified': true},
                            size: 14,
                          ),
                        ],
                      ],
                    ),
                    SizedBox(height: 3.ms),
                    Row(
                      children: [
                        if (icon != null) ...[
                          Icon(icon, size: 14.ms, color: p.muted),
                          SizedBox(width: 4.ms),
                        ],
                        Expanded(
                          child: CText(
                            mine ? 'chat:list.you' : 'chat:list.line',
                            variables: {'text': preview},
                            size: 13,
                            weight: unread ? FontWeight.w700 : FontWeight.w500,
                            color: unread ? p.text : p.muted,
                            maxLines: 1,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              SizedBox(width: 8.ms),
              Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  CText.raw(
                    timeText,
                    size: 11.5,
                    weight: FontWeight.w600,
                    color: unread ? p.accent : p.muted,
                    maxLines: 1,
                  ),
                  SizedBox(height: 6.ms),
                  if (unread)
                    Container(
                      constraints: BoxConstraints(minWidth: 20.ms),
                      height: 20.ms,
                      padding: EdgeInsets.symmetric(horizontal: 6.ms),
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: p.accent,
                        borderRadius: BorderRadius.circular(999),
                      ),
                      child: CText.raw(
                        c.unread > 99 ? '99+' : '${c.unread}',
                        size: 10.5,
                        weight: FontWeight.w900,
                        color: p.onAccent,
                      ),
                    )
                  else
                    SizedBox(height: 20.ms),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
