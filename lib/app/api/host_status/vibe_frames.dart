import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:vibe_camera/vibe_camera.dart';

/// Picks a still from a Vibe clip for its preview: the steadiest of a few
/// frames — the most detail, never a black or blown-out one (the first frame
/// is often dark, a middle one may be mid-movement).
abstract final class VibeFrames {
  /// JPEG bytes of the best of [count] frames spread over the clip, at
  /// [size]; null when none could be read.
  static Future<Uint8List?> best(
    File video, {
    int count = 3,
    ui.Size size = const ui.Size(240, 400),
    VibeExporter? exporter,
  }) async {
    final e = exporter ?? ProVideoExporter();
    final info = await e.probe(video);
    final frames = await e.thumbnails(
      video,
      info.duration,
      count: count,
      size: size,
    );
    if (frames.isEmpty) return null;
    if (frames.length == 1) return frames.first;
    Uint8List? pick;
    var top = double.negativeInfinity;
    for (final f in frames) {
      final s = await score(f);
      if (s > top) {
        top = s;
        pick = f;
      }
    }
    return pick;
  }

  /// Higher is better: contrast (spread of brightness, which blur and
  /// darkness both flatten), minus a penalty for a nearly black or nearly
  /// white frame.
  static Future<double> score(Uint8List jpeg) async {
    try {
      final codec = await ui.instantiateImageCodec(jpeg, targetWidth: 48);
      final frame = await codec.getNextFrame();
      final data = await frame.image.toByteData(
        format: ui.ImageByteFormat.rawRgba,
      );
      frame.image.dispose();
      codec.dispose();
      if (data == null) return double.negativeInfinity;
      return scorePixels(data.buffer.asUint8List());
    } catch (_) {
      return double.negativeInfinity;
    }
  }

  /// [rgba] pixels → the score above (separate so tests need no codec).
  static double scorePixels(Uint8List rgba) {
    final n = rgba.length ~/ 4;
    if (n == 0) return double.negativeInfinity;
    var sum = 0.0;
    var sumSq = 0.0;
    for (var i = 0; i < n; i++) {
      final o = i * 4;
      final luma =
          0.299 * rgba[o] + 0.587 * rgba[o + 1] + 0.114 * rgba[o + 2];
      sum += luma;
      sumSq += luma * luma;
    }
    final mean = sum / n;
    final spread = math.sqrt(math.max(0, sumSq / n - mean * mean));
    final penalty = mean < 30 || mean > 230 ? 100.0 : 0.0;
    return spread - penalty;
  }
}
