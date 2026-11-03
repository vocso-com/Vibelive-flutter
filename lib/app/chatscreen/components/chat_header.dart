import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../core/i18n/i18n.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/utils/scale.dart';
import '../../api/chat/chat_models.dart';
import '../../component/c_back_button.dart';
import '../../component/c_image.dart';
import '../../component/c_text.dart';
import '../../component/pressable.dart';
import '../../component/skeleton.dart';
import '../../component/verification_badge.dart';
import 'chat_palette.dart';

/// The chat's top bar: back, the other person (photo, name, verified,
/// online / "On a call"), the call buttons of the paying side, the menu.
class ChatHeader extends StatelessWidget {
  const ChatHeader({
    super.key,
    required this.open,
    required this.onMenu,
    this.calls,
    this.onPeer,
  });

  final ValueListenable<ChatOpen?> open;
  final VoidCallback onMenu;

  /// Voice / video buttons (paying side, a host with rates).
  final Widget? calls;

  /// Tapping the person (their profile, for a host).
  final VoidCallback? onPeer;

  @override
  Widget build(BuildContext context) {
    final p = ChatPalette.of(context);
    return DecoratedBox(
      decoration: BoxDecoration(
        color: p.bar,
        border: Border(bottom: BorderSide(color: p.barBorder)),
      ),
      child: SafeArea(
        bottom: false,
        child: SizedBox(
          height: 60.ms,
          child: Padding(
            padding: EdgeInsetsDirectional.only(start: 10.ms, end: 6.ms),
            child: ValueListenableBuilder<ChatOpen?>(
              valueListenable: open,
              builder: (context, info, _) => Row(
                children: [
                  const CBackButton(boxSize: 38, size: 22),
                  SizedBox(width: 10.ms),
                  Expanded(
                    child: info == null
                        ? const _PeerSkeleton()
                        : Pressable(
                            onPressed: onPeer,
                            activeOpacity: 0.8,
                            child: _Peer(peer: info.peer),
                          ),
                  ),
                  if (info != null && calls != null) calls!,
                  Pressable(
                    onPressed: info == null ? null : onMenu,
                    semanticLabel: context.t('chat:header.menu'),
                    hitPadding: const EdgeInsets.all(4),
                    child: SizedBox.square(
                      dimension: 40.ms,
                      child: Icon(
                        LucideIcons.ellipsisVertical,
                        size: 21.ms,
                        color: p.text,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _Peer extends StatelessWidget {
  const _Peer({required this.peer});

  final ChatPeer peer;

  @override
  Widget build(BuildContext context) {
    final p = ChatPalette.of(context);
    final name = peer.deleted || peer.name.isEmpty
        ? context.t(
            peer.deleted ? 'chat:list.deleted_user' : 'chat:list.someone',
          )
        : peer.name;
    final (String? status, Color statusColor) = !peer.isHost || peer.deleted
        ? (null, p.muted)
        : peer.busy
        ? ('chat:header.on_call', StatusColors.dangerRed)
        : peer.online
        ? ('chat:header.online', StatusColors.success)
        : ('chat:header.offline', p.muted);
    return Row(
      children: [
        ChatAvatar(
          url: peer.avatar,
          name: name,
          size: 40,
          online: peer.isHost && peer.online && !peer.busy,
          busy: peer.isHost && peer.busy,
        ),
        SizedBox(width: 10.ms),
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
                      size: 16,
                      weight: FontWeight.w800,
                      color: p.text,
                      maxLines: 1,
                    ),
                  ),
                  if (peer.verified) ...[
                    SizedBox(width: 4.ms),
                    const VerificationBadge(user: {'verified': true}, size: 15),
                  ],
                ],
              ),
              if (status != null)
                CText(
                  status,
                  size: 12,
                  weight: FontWeight.w600,
                  color: statusColor,
                  maxLines: 1,
                ),
            ],
          ),
        ),
      ],
    );
  }
}

class _PeerSkeleton extends StatelessWidget {
  const _PeerSkeleton();

  @override
  Widget build(BuildContext context) => Shimmer(
    child: Row(
      children: [
        SkeletonBox(width: 40.ms, height: 40.ms, circle: true),
        SizedBox(width: 10.ms),
        Expanded(child: SkeletonLines(lines: 2, height: 11.ms)),
      ],
    ),
  );
}

/// A round photo with an online (green) or "on a call" (red) dot.
class ChatAvatar extends StatelessWidget {
  const ChatAvatar({
    super.key,
    required this.url,
    required this.name,
    this.size = 48,
    this.online = false,
    this.busy = false,
  });

  final String? url;
  final String? name;
  final double size;
  final bool online;
  final bool busy;

  @override
  Widget build(BuildContext context) {
    final p = ChatPalette.of(context);
    final s = size.ms;
    final dot = s * 0.26;
    return SizedBox.square(
      dimension: s,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          ExcludeSemantics(
            child: CAvatar(url: url, name: name, size: s),
          ),
          if (online || busy)
            PositionedDirectional(
              end: 0,
              bottom: 0,
              child: Container(
                width: dot,
                height: dot,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: busy ? StatusColors.dangerRed : StatusColors.success,
                  border: Border.all(color: p.bar, width: 2),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// A small round call button in the header.
class ChatCallButton extends StatelessWidget {
  const ChatCallButton({
    super.key,
    required this.video,
    required this.onTap,
    this.busy = false,
  });

  final bool video;
  final VoidCallback? onTap;
  final bool busy;

  @override
  Widget build(BuildContext context) {
    final p = ChatPalette.of(context);
    return Pressable(
      onPressed: busy ? null : onTap,
      semanticLabel: context.t(
        video ? 'chat:header.video_call' : 'chat:header.voice_call',
      ),
      child: Container(
        width: 36.ms,
        height: 36.ms,
        margin: EdgeInsetsDirectional.only(start: 6.ms),
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: video ? p.accent : p.chip,
        ),
        child: busy
            ? Padding(
                padding: EdgeInsets.all(9.ms),
                child: RepaintBoundary(
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: video ? p.onAccent : p.text,
                  ),
                ),
              )
            : Icon(
                video ? LucideIcons.video : LucideIcons.phone,
                size: 17.ms,
                color: video ? p.onAccent : p.text,
              ),
      ),
    );
  }
}
