import 'dart:async';

import 'package:clock/clock.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../core/analytics/events/chat_events.dart';
import '../../../core/i18n/i18n.dart';
import '../../../core/network/api_exception.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/utils/scale.dart';
import '../../api/chat/chat_api.dart';
import '../../component/c_image.dart';
import '../../component/c_loader.dart';
import '../../component/c_text.dart';
import '../../component/pressable.dart';
import '../components/chat_secure_zone.dart';
import '../helper/chat_format.dart';

/// Opens a bought private photo full screen while it can be opened.
/// [viewSeconds]: how long one look lasts (admin); [until]: the photo's
/// own end. [secure]: screenshot protection on.
Future<void> openPrivatePhoto(
  BuildContext context, {
  required String messageId,
  required DateTime until,
  required int viewSeconds,
  required bool secure,
}) => Navigator.of(context, rootNavigator: true).push(
  PageRouteBuilder<void>(
    settings: const RouteSettings(name: 'private_photo_viewer'),
    transitionDuration: const Duration(milliseconds: 200),
    reverseTransitionDuration: const Duration(milliseconds: 160),
    pageBuilder: (_, _, _) => PrivatePhotoViewer(
      messageId: messageId,
      until: until,
      viewSeconds: viewSeconds,
      secure: secure,
    ),
    transitionsBuilder: (_, a, _, child) => FadeTransition(
      opacity: CurvedAnimation(parent: a, curve: Curves.easeOut),
      child: child,
    ),
  ),
);

/// The bought photo, fitted and centred, pinch to zoom, double tap to fit
/// again. Closes by itself when this look is over or the photo's time is
/// up, whichever is first, with the time left on show. The bytes live in
/// this widget's memory only (never on disk, `no-store` on the server).
class PrivatePhotoViewer extends StatefulWidget {
  const PrivatePhotoViewer({
    super.key,
    required this.messageId,
    required this.until,
    required this.viewSeconds,
    required this.secure,
  });

  final String messageId;
  final DateTime until;
  final int viewSeconds;
  final bool secure;

  @override
  State<PrivatePhotoViewer> createState() => _PrivatePhotoViewerState();
}

class _PrivatePhotoViewerState extends State<PrivatePhotoViewer> {
  final _zoom = TransformationController();
  final _left = ValueNotifier<String>('');
  late final DateTime _closeAt;
  late final DateTime _opened;
  Timer? _tick;
  Uint8List? _bytes;
  ApiException? _error;
  bool _closing = false;

  @override
  void initState() {
    super.initState();
    _opened = clock.now();
    final look = _opened.add(
      Duration(seconds: widget.viewSeconds <= 0 ? 300 : widget.viewSeconds),
    );
    _closeAt = look.isBefore(widget.until) ? look : widget.until;
    // Already over: the first tick closes it (never pop during initState).
    _left.value = ChatFormat.countdown(_closeAt, _opened);
    _tick = Timer.periodic(const Duration(seconds: 1), (_) => _onTick());
    unawaited(_load());
  }

  void _onTick() {
    final now = clock.now();
    if (!now.isBefore(_closeAt)) return _close();
    _left.value = ChatFormat.countdown(_closeAt, now);
  }

  Future<void> _load() async {
    setState(() => _error = null);
    try {
      final bytes = await ChatApi.fetchPrivatePhoto(widget.messageId);
      if (mounted) setState(() => _bytes = bytes);
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e);
    }
  }

  void _close() {
    if (_closing) return;
    _closing = true;
    _tick?.cancel();
    ChatEvents.privatePhotoViewed(
      seconds: clock.now().difference(_opened).inSeconds,
    );
    if (mounted) Navigator.of(context).maybePop();
  }

  @override
  void dispose() {
    _tick?.cancel();
    _zoom.dispose();
    _left.dispose();
    _bytes = null;
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final bytes = _bytes;
    final error = _error;
    final Widget body;
    if (bytes != null) {
      body = LayoutBuilder(
        builder: (context, box) => GestureDetector(
          onDoubleTap: () => _zoom.value = Matrix4.identity(),
          child: InteractiveViewer(
            transformationController: _zoom,
            minScale: 1,
            maxScale: 4,
            child: SizedBox(
              width: box.maxWidth,
              height: box.maxHeight,
              child: Image.memory(
                bytes,
                fit: BoxFit.contain,
                gaplessPlayback: true,
                cacheWidth:
                    (box.maxWidth * MediaQuery.devicePixelRatioOf(context) * 2)
                        .round(),
              ),
            ),
          ),
        ),
      );
    } else if (error != null) {
      final expired =
          ChatRefusal.of(error).code == ChatCodes.photoExpired ||
          error.statusCode == 410;
      body = _Problem(expired: expired, onRetry: _load);
    } else {
      body = const Center(child: CLoader(color: AppColors.white));
    }
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.light,
      child: ChatSecureZone(
        active: widget.secure,
        child: Scaffold(
          backgroundColor: AppColors.black,
          body: Stack(
            fit: StackFit.expand,
            children: [
              body,
              Positioned(
                top: 0,
                left: 0,
                right: 0,
                child: _Bar(left: _left, onClose: _close),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Bar extends StatelessWidget {
  const _Bar({required this.left, required this.onClose});

  final ValueListenable<String> left;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) => DecoratedBox(
    decoration: const BoxDecoration(
      gradient: LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [Color(0x99000000), Color(0x00000000)],
      ),
    ),
    child: SafeArea(
      bottom: false,
      child: Padding(
        padding: EdgeInsetsDirectional.fromSTEB(8.ms, 6.ms, 14.ms, 20.ms),
        child: Row(
          children: [
            Pressable(
              onPressed: onClose,
              semanticLabel: context.t('chat:private.close'),
              child: SizedBox.square(
                dimension: 40.ms,
                child: Icon(LucideIcons.x, color: AppColors.white, size: 22.ms),
              ),
            ),
            Icon(LucideIcons.lock, color: AppColors.whiteA(0.7), size: 15.ms),
            SizedBox(width: 6.ms),
            const Expanded(
              child: CText(
                'chat:private.title',
                size: 15,
                weight: FontWeight.w800,
                color: AppColors.white,
                maxLines: 1,
              ),
            ),
            Container(
              padding: EdgeInsets.symmetric(horizontal: 10.ms, vertical: 5.ms),
              decoration: BoxDecoration(
                color: AppColors.whiteA(0.2),
                borderRadius: BorderRadius.circular(999),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(LucideIcons.clock3, color: AppColors.white, size: 13.ms),
                  SizedBox(width: 4.ms),
                  ValueListenableBuilder<String>(
                    valueListenable: left,
                    builder: (_, t, _) => CText.raw(
                      t,
                      key: const ValueKey('chat-viewer-left'),
                      size: 13,
                      weight: FontWeight.w800,
                      color: AppColors.white,
                      style: const TextStyle(
                        fontFeatures: [FontFeature.tabularFigures()],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

class _Problem extends StatelessWidget {
  const _Problem({required this.expired, required this.onRetry});

  final bool expired;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: EdgeInsets.all(32.ms),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            expired ? LucideIcons.timerOff : LucideIcons.imageOff,
            color: AppColors.whiteA(0.6),
            size: 40.ms,
          ),
          SizedBox(height: 12.ms),
          CText(
            expired ? 'chat:private.cannot_open' : 'chat:private.viewer_failed',
            size: 15,
            weight: FontWeight.w700,
            color: AppColors.white,
            align: TextAlign.center,
          ),
          if (!expired) ...[
            SizedBox(height: 12.ms),
            Pressable(
              onPressed: onRetry,
              child: const CText(
                'chat:private.try_again',
                size: 14,
                weight: FontWeight.w800,
                color: AppColors.white,
              ),
            ),
          ],
        ],
      ),
    ),
  );
}

/// A sent photo full screen (the public one): pinch to zoom.
Future<void> openChatPhoto(
  BuildContext context, {
  required String url,
  required bool secure,
}) => Navigator.of(context, rootNavigator: true).push(
  PageRouteBuilder<void>(
    settings: const RouteSettings(name: 'chat_photo_viewer'),
    transitionDuration: const Duration(milliseconds: 200),
    reverseTransitionDuration: const Duration(milliseconds: 160),
    pageBuilder: (context, _, _) => AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.light,
      child: ChatSecureZone(
        active: secure,
        child: Scaffold(
          backgroundColor: AppColors.black,
          body: Stack(
            fit: StackFit.expand,
            children: [
              InteractiveViewer(
                maxScale: 4,
                child: Center(
                  child: CImage(
                    url: url,
                    width: MediaQuery.sizeOf(context).width,
                    fit: BoxFit.contain,
                  ),
                ),
              ),
              SafeArea(
                child: Align(
                  alignment: AlignmentDirectional.topStart,
                  child: Pressable(
                    onPressed: () => Navigator.of(context).maybePop(),
                    semanticLabel: context.t('chat:private.close'),
                    child: SizedBox.square(
                      dimension: 48.ms,
                      child: Icon(
                        LucideIcons.x,
                        color: AppColors.white,
                        size: 24.ms,
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    ),
    transitionsBuilder: (_, a, _, child) => FadeTransition(
      opacity: CurvedAnimation(parent: a, curve: Curves.easeOut),
      child: child,
    ),
  ),
);
