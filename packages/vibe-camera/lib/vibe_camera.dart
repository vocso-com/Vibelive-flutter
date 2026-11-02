/// An in-app camera for short vertical clips — live looks and light, up to
/// 120 fps where the device allows — and an editor (filters, light, trim,
/// crop, captions) whose result is baked into the exported video.
///
/// ```dart
/// final clip = await VibeCamera.open(
///   context,
///   config: VibeCameraConfig(maxDuration: Duration(seconds: 30)),
/// );
/// if (clip != null) upload(clip.file);
/// ```
library;

import 'package:flutter/material.dart';

import 'src/capture/camera_session.dart';
import 'src/capture/capture_screen.dart';
import 'src/config.dart';
import 'src/ui/theme.dart';

export 'src/capture/camera_session.dart'
    show VibeCaptureSession, VibeSessionOpener, VibeCameraDenied;
export 'src/config.dart';
export 'src/core/adjustments.dart';
export 'src/core/color_matrix.dart';
export 'src/core/crop.dart';
export 'src/core/edit.dart';
export 'src/core/filters.dart';
export 'src/core/text_overlay.dart';
export 'src/core/trim.dart';
export 'src/export/exporter.dart';
export 'src/strings.dart';
export 'src/ui/filter_thumb.dart';
export 'src/ui/text_painting.dart' show VibeTextPainting;
export 'src/ui/theme.dart';

abstract final class VibeCamera {
  /// Opens the camera full screen; resolves with the finished clip, or null
  /// when the user closed it. [opener] replaces the real camera (tests).
  static Future<VibeCameraResult?> open(
    BuildContext context, {
    VibeCameraConfig config = const VibeCameraConfig(),
    VibeSessionOpener? opener,
  }) => Navigator.of(context, rootNavigator: true).push<VibeCameraResult>(
    PageRouteBuilder<VibeCameraResult>(
      settings: const RouteSettings(name: 'vibe_camera'),
      pageBuilder: (_, _, _) => VibeTheme.wrap(
        config.accent,
        VibeCaptureScreen(config: config, opener: opener),
      ),
      transitionsBuilder: (_, animation, _, child) => SlideTransition(
        position: Tween(begin: const Offset(0, 1), end: Offset.zero)
            .chain(CurveTween(curve: Curves.easeOutCubic))
            .animate(animation),
        child: child,
      ),
    ),
  );
}
