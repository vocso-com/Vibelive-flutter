import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../../core/i18n/i18n.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/utils/scale.dart';
import '../../api/chat/chat_models.dart';
import '../../component/c_image.dart';
import '../../component/c_loader.dart';
import '../../component/pressable.dart';
import '../helper/chat_room_controller.dart';
import 'chat_palette.dart';
import 'message_ticks.dart';

/// Width over height of a chat picture, kept in a sane range so a strip or
/// a tower never takes over the list.
double chatAspect(int? width, int? height) {
  if (width == null || height == null || width <= 0 || height <= 0) {
    return 0.8;
  }
  return (width / height).clamp(0.6, 1.6);
}

/// A photo: decoded at its display size (never the full upload), the time
/// on a scrim in the corner, a spinner while it uploads. Tap: full screen.
class PhotoBubble extends StatelessWidget {
  const PhotoBubble({
    super.key,
    required this.message,
    required this.mine,
    required this.maxWidth,
    required this.receipts,
    required this.onOpen,
  });

  final ChatMessage message;
  final bool mine;
  final double maxWidth;
  final ValueListenable<ChatReceiptMarks> receipts;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    final m = message;
    final media = m.media;
    final width = maxWidth * 0.8 > 260.ms ? 260.ms : maxWidth * 0.8;
    final height = width / chatAspect(media?.width, media?.height);
    final dpr = MediaQuery.devicePixelRatioOf(context);
    final local = m.localPath;
    final Widget picture = local != null
        ? Image.file(
            File(local),
            width: width,
            height: height,
            fit: BoxFit.cover,
            cacheWidth: (width * dpr).round(),
            gaplessPlayback: true,
          )
        : CImage(url: media?.thumb ?? media?.url, width: width, height: height);
    final sending =
        m.state == ChatSendState.sending || m.state == ChatSendState.queued;
    return Semantics(
      image: true,
      label: context.t('chat:bubble.photo'),
      child: Pressable(
        onPressed: media?.url == null ? null : onOpen,
        activeOpacity: 0.9,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(ChatPalette.radius),
          child: SizedBox(
            width: width,
            height: height,
            child: Stack(
              fit: StackFit.expand,
              children: [
                picture,
                const _Scrim(),
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
                    color: AppColors.blackA(0.25),
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
      ),
    );
  }
}

/// A soft dark band at the bottom, under the time.
class _Scrim extends StatelessWidget {
  const _Scrim();

  @override
  Widget build(BuildContext context) => const Align(
    alignment: Alignment.bottomCenter,
    child: FractionallySizedBox(
      heightFactor: 0.32,
      widthFactor: 1,
      child: DecoratedBox(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Color(0x00000000), Color(0x73000000)],
          ),
        ),
      ),
    ),
  );
}
