import 'dart:async';

import 'package:camera/camera.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import '../config.dart';

/// Camera or microphone access was refused.
class VibeCameraDenied implements Exception {
  const VibeCameraDenied(this.code);
  final String code;
  @override
  String toString() => 'VibeCameraDenied($code)';
}

/// The live camera, as the capture screen uses it. An interface so the screen
/// can be tested without a camera.
abstract class VibeCaptureSession {
  /// The live picture, filling its box (cropped at the edges, never stretched).
  Widget preview();

  /// Frames per second the camera accepted (null: its own default).
  int? get fps;
  VibeLens get lens;
  bool get hasTorch;
  bool get isRecording;
  double get minZoom;
  double get maxZoom;

  /// −1 (darker) … 1 (brighter): the sensor's own exposure, real light.
  Future<void> setLight(double v);
  Future<void> setZoom(double zoom);
  Future<void> setTorch(bool on);

  /// Focus and meter on a point of the preview (0–1 each way).
  Future<void> focusAt(Offset point);
  Future<void> startRecording();

  /// The recorded file's path.
  Future<String> stopRecording();
  Future<void> dispose();
}

/// Opens a session: [lens], the best frame rate up to [preferredFps].
typedef VibeSessionOpener =
    Future<VibeCaptureSession> Function({
      required VibeLens lens,
      required int preferredFps,
      required bool enableAudio,
    });

/// The `camera` plugin, asking for [preferredFps] first and stepping down
/// (120 → 60 → 30 → the device default) until the device accepts one.
class CameraSession implements VibeCaptureSession {
  CameraSession._(this._controller, this.fps, this.lens, this._minLight, this._maxLight, this.minZoom, this.maxZoom);

  final CameraController _controller;
  @override
  final int? fps;
  @override
  final VibeLens lens;
  final double _minLight;
  final double _maxLight;
  @override
  final double minZoom;
  @override
  final double maxZoom;

  /// The rates tried, best first, at a resolution each can usually sustain:
  /// 720p for 120 and 60 fps, 1080p at 30.
  @visibleForTesting
  static List<(ResolutionPreset, int?)> attempts(int preferredFps) => [
    if (preferredFps >= 120) (ResolutionPreset.high, 120),
    if (preferredFps >= 60) (ResolutionPreset.high, 60),
    (ResolutionPreset.veryHigh, 30),
    (ResolutionPreset.high, null),
  ];

  /// Enough for a sharp short clip, not the encoder's default (which is
  /// far higher at 120 fps): smaller files open in the editor, render and
  /// upload faster, and the phone runs cooler while recording.
  @visibleForTesting
  static int videoBitrate(int? fps) => switch (fps) {
    final f? when f >= 120 => 10000000,
    final f? when f >= 60 => 8000000,
    _ => 6000000,
  };

  static Future<VibeCaptureSession> open({
    required VibeLens lens,
    required int preferredFps,
    required bool enableAudio,
  }) async {
    final cameras = await availableCameras();
    if (cameras.isEmpty) throw StateError('No camera on this device');
    final wanted = lens == VibeLens.front
        ? CameraLensDirection.front
        : CameraLensDirection.back;
    final description = cameras.firstWhere(
      (c) => c.lensDirection == wanted,
      orElse: () => cameras.first,
    );
    final actualLens = description.lensDirection == CameraLensDirection.front
        ? VibeLens.front
        : VibeLens.back;

    Object? lastError;
    for (final (preset, fps) in attempts(preferredFps)) {
      final controller = CameraController(
        description,
        preset,
        enableAudio: enableAudio,
        fps: fps,
        videoBitrate: videoBitrate(fps),
        audioBitrate: 128000,
        imageFormatGroup: ImageFormatGroup.unknown,
      );
      try {
        await controller.initialize();
        await controller.lockCaptureOrientation(DeviceOrientation.portraitUp);
        await controller.prepareForVideoRecording();
        final light = await Future.wait([
          controller.getMinExposureOffset(),
          controller.getMaxExposureOffset(),
        ]);
        final zoom = await Future.wait([
          controller.getMinZoomLevel(),
          controller.getMaxZoomLevel(),
        ]);
        return CameraSession._(
          controller,
          fps,
          actualLens,
          light[0],
          light[1],
          zoom[0],
          zoom[1],
        );
      } on CameraException catch (e) {
        await controller.dispose();
        if (_denied(e.code)) throw VibeCameraDenied(e.code);
        lastError = e;
      } catch (e) {
        await controller.dispose();
        lastError = e;
      }
    }
    throw lastError ?? StateError('The camera did not start');
  }

  static bool _denied(String code) => const {
    'CameraAccessDenied',
    'CameraAccessDeniedWithoutPrompt',
    'CameraAccessRestricted',
    'AudioAccessDenied',
    'AudioAccessDeniedWithoutPrompt',
    'AudioAccessRestricted',
    'cameraPermission',
  }.contains(code);

  @override
  Widget preview() => _CoverPreview(controller: _controller);

  @override
  bool get hasTorch => lens == VibeLens.back;

  @override
  bool get isRecording => _controller.value.isRecordingVideo;

  @override
  Future<void> setLight(double v) {
    final x = v.clamp(-1.0, 1.0);
    final offset = x >= 0 ? x * _maxLight : -x * _minLight;
    return _controller.setExposureOffset(offset).then((_) {});
  }

  @override
  Future<void> setZoom(double zoom) =>
      _controller.setZoomLevel(zoom.clamp(minZoom, maxZoom));

  @override
  Future<void> setTorch(bool on) async {
    if (!hasTorch) return;
    await _controller.setFlashMode(on ? FlashMode.torch : FlashMode.off);
  }

  @override
  Future<void> focusAt(Offset point) async {
    try {
      await _controller.setFocusPoint(point);
      await _controller.setExposurePoint(point);
    } catch (_) {
      // Fixed-focus cameras (most front ones) have no focus point: fine.
    }
  }

  @override
  Future<void> startRecording() => _controller.startVideoRecording();

  @override
  Future<String> stopRecording() async =>
      (await _controller.stopVideoRecording()).path;

  @override
  Future<void> dispose() => _controller.dispose();
}

/// The preview filling its box like a phone camera does: cropped at the edges,
/// never stretched. The plugin reports the sensor's landscape size, so it is
/// turned upright for the portrait-locked screen.
class _CoverPreview extends StatelessWidget {
  const _CoverPreview({required this.controller});
  final CameraController controller;

  @override
  Widget build(BuildContext context) {
    final size = controller.value.previewSize;
    if (size == null) return CameraPreview(controller);
    return ClipRect(
      child: FittedBox(
        fit: BoxFit.cover,
        child: SizedBox(
          width: size.shortestSide,
          height: size.longestSide,
          child: CameraPreview(controller),
        ),
      ),
    );
  }
}
