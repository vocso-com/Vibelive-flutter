import 'dart:async';
import 'dart:io';
import 'dart:math' as math;
import 'dart:ui';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:pro_video_editor/pro_video_editor.dart' as pve;

import '../config.dart';
import '../core/crop.dart';
import '../core/edit.dart';
import '../ui/text_painting.dart';

/// What the editor needs to know about a recording.
@immutable
class VibeVideoInfo {
  const VibeVideoInfo({required this.duration, required this.size, this.fps});

  final Duration duration;

  /// As it plays (rotation applied).
  final Size size;
  final double? fps;
}

/// One render: the recording and everything done to it.
@immutable
class VibeExportJob {
  const VibeExportJob({
    required this.source,
    required this.edit,
    required this.info,
    required this.quality,
    required this.maxFps,
  });

  final File source;
  final VibeEdit edit;
  final VibeVideoInfo info;
  final VibeExportQuality quality;
  final int maxFps;

  /// The exported picture size: the crop, or the whole frame.
  Size get outputSize {
    final crop = edit.cropRect(info.size);
    return VibeCrop.isFull(info.size, crop) ? info.size : crop.size;
  }

  int get bitrate => switch (quality) {
    VibeExportQuality.p480 => 2500000,
    VibeExportQuality.p720 => 5000000,
    VibeExportQuality.p1080 => 8000000,
  };
}

/// Video work the camera needs done natively. Swappable for tests.
abstract class VibeExporter {
  Future<VibeVideoInfo> probe(File file);

  /// [count] frames spread over [duration], each [size] (JPEG bytes).
  Future<List<Uint8List>> thumbnails(
    File file,
    Duration duration, {
    int count = 8,
    Size size = const Size(96, 160),
  });

  /// Bakes [job] into a new file; [onProgress] runs 0→1.
  Future<File> export(VibeExportJob job, {ValueChanged<double>? onProgress});

  Future<void> cancel();
}

/// pro_video_editor: native (Media3 on Android, AVFoundation on iOS), no
/// FFmpeg. Trim, crop, the colour matrix and the captions (one transparent
/// PNG stretched over the cropped frame) in one pass.
class ProVideoExporter implements VibeExporter {
  ProVideoExporter();

  String? _taskId;

  pve.ProVideoEditor get _editor => pve.ProVideoEditor.instance;

  @override
  Future<VibeVideoInfo> probe(File file) async {
    final meta = await _editor.getMetadata(pve.EditorVideo.file(file));
    return VibeVideoInfo(
      duration: meta.duration,
      size: meta.resolution,
      fps: meta.frameRate,
    );
  }

  @override
  Future<List<Uint8List>> thumbnails(
    File file,
    Duration duration, {
    int count = 8,
    Size size = const Size(96, 160),
  }) {
    final step = duration.inMicroseconds / math.max(1, count);
    return _editor.getThumbnails(
      pve.ThumbnailConfigs(
        video: pve.EditorVideo.file(file),
        outputSize: size,
        boxFit: pve.ThumbnailBoxFit.cover,
        outputFormat: pve.ThumbnailFormat.jpeg,
        timestamps: [
          for (var i = 0; i < count; i++)
            Duration(microseconds: (step * (i + 0.5)).round()),
        ],
      ),
    );
  }

  @override
  Future<File> export(VibeExportJob job, {ValueChanged<double>? onProgress}) async {
    final dir = await getTemporaryDirectory();
    final stamp = DateTime.now().microsecondsSinceEpoch;
    final edit = job.edit;
    final info = job.info;
    final crop = edit.cropRect(info.size);
    final cropped = !VibeCrop.isFull(info.size, crop);

    final layers = <pve.ImageLayer>[];
    if (edit.texts.isNotEmpty) {
      final png = await VibeTextPainting.png(edit.texts, job.outputSize);
      final file = File('${dir.path}/vibe_text_$stamp.png');
      await file.writeAsBytes(png, flush: true);
      // No offset: stretched over the (cropped) output, which is the size it
      // was drawn at.
      layers.add(pve.ImageLayer(image: pve.EditorLayerImage.file(file.path)));
    }

    final trimmed = !edit.trim.isFull(info.duration);
    final data = pve.VideoRenderData(
      videoSegments: [pve.VideoSegment(video: pve.EditorVideo.file(job.source))],
      startTime: trimmed ? edit.trim.start : null,
      endTime: trimmed ? edit.trim.end : null,
      transform: cropped
          ? pve.ExportTransform(
              x: crop.left.round(),
              y: crop.top.round(),
              width: crop.width.round(),
              height: crop.height.round(),
            )
          : null,
      colorFilters: edit.hasColor ? [pve.ColorFilter(matrix: edit.matrix)] : const [],
      imageLayers: layers,
      bitrate: job.bitrate,
      maxFrameRate: math.min(job.maxFps, (info.fps ?? job.maxFps).round()),
      shouldOptimizeForNetworkUse: true,
    );

    _taskId = data.id;
    final progress = _editor.progressStreamById(data.id).listen(
      (p) => onProgress?.call(p.progress.clamp(0.0, 1.0)),
    );
    try {
      final out = '${dir.path}/vibe_$stamp.mp4';
      await _editor.renderVideoToFile(out, data);
      onProgress?.call(1);
      return File(out);
    } finally {
      _taskId = null;
      await progress.cancel();
    }
  }

  @override
  Future<void> cancel() async {
    final id = _taskId;
    if (id != null) await _editor.cancel(id);
  }
}
