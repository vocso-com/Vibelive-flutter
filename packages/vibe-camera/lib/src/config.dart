import 'dart:io';

import 'package:flutter/widgets.dart';

import 'core/filters.dart';
import 'export/exporter.dart';
import 'strings.dart';

/// Which camera to start on.
enum VibeLens { front, back }

/// Export size: the longer side's pixels.
enum VibeExportQuality { p480, p720, p1080 }

/// How the camera behaves. Every limit comes from the app (a server setting,
/// say), so nothing about the clip is hardcoded here.
@immutable
class VibeCameraConfig {
  const VibeCameraConfig({
    this.maxDuration = const Duration(seconds: 30),
    this.minDuration = const Duration(seconds: 1),
    this.preferredFps = 120,
    this.lens = VibeLens.front,
    this.enableAudio = true,
    this.filters,
    this.strings = const VibeCameraStrings(),
    this.accent = const Color(0xFFFF2E7E),
    this.exportQuality = VibeExportQuality.p720,
    this.maxOutputFps = 120,
    this.edit = true,
    this.onOpenSettings,
    this.exporter,
    this.pickFromGallery,
  });

  /// Recording stops itself here; the trim never keeps more.
  final Duration maxDuration;

  /// Shorter recordings are not accepted.
  final Duration minDuration;

  /// Asked of the camera first (120 → 60 → 30 as the device allows).
  final int preferredFps;
  final VibeLens lens;
  final bool enableAudio;

  /// The looks offered; [VibeFilters.all] when null.
  final List<VibeFilter>? filters;
  final VibeCameraStrings strings;

  /// Record button, selected tool, handles.
  final Color accent;
  final VibeExportQuality exportQuality;

  /// The exported clip's frame rate is capped here (the recording's is kept
  /// when lower).
  final int maxOutputFps;

  /// After recording: the editor (filters, light, trim, crop, text). False
  /// returns the recording as it is.
  final bool edit;

  /// "Open settings" when camera or microphone access was refused; hidden
  /// when null.
  final VoidCallback? onOpenSettings;

  /// Rendering, thumbnails and video info; pro_video_editor when null. Tests
  /// pass a fake.
  final VibeExporter? exporter;

  /// Offers a video from the phone's gallery next to the record button (the
  /// app brings its own picker). It goes through the same editor, trimmed to
  /// [maxDuration]. Null: record only — a Vibe must be filmed in the app.
  final Future<File?> Function()? pickFromGallery;

  List<VibeFilter> get looks => filters ?? VibeFilters.all;
  VibeExporter get exporterOrDefault => exporter ?? ProVideoExporter();
}

/// What the camera hands back.
@immutable
class VibeCameraResult {
  const VibeCameraResult({
    required this.file,
    required this.duration,
    required this.recordedAt,
    this.size,
    this.fps,
    this.edited = false,
    this.filterId = 'normal',
  });

  final File file;
  final Duration duration;

  /// When recording started (an upload later must not count as "when").
  final DateTime recordedAt;

  /// The exported frame size, when known.
  final Size? size;

  /// Frames per second the camera was asked for and accepted.
  final int? fps;

  /// Anything baked in (filter, light, trim, crop, text).
  final bool edited;
  final String filterId;
}
