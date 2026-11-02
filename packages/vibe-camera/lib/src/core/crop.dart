import 'dart:ui';

/// Frame shapes the Crop tool offers. [ratio] is width ÷ height; null keeps
/// the video's own shape.
enum VibeCropAspect {
  original(null),
  portrait(9 / 16),
  fourFive(4 / 5),
  square(1);

  const VibeCropAspect(this.ratio);
  final double? ratio;
}

abstract final class VibeCrop {
  /// The largest [aspect] frame inside a [video]-sized picture, moved towards
  /// [center] (0–1 on each axis, 0.5 = middle) as far as the picture allows.
  /// Whole, even pixels: video encoders want even sizes.
  static Rect rect(Size video, VibeCropAspect aspect, {Offset center = const Offset(0.5, 0.5)}) {
    final w = video.width, h = video.height;
    final ratio = aspect.ratio;
    if (ratio == null || w <= 0 || h <= 0) {
      return Rect.fromLTWH(0, 0, _even(w), _even(h));
    }
    var cw = w, ch = w / ratio;
    if (ch > h) {
      ch = h;
      cw = h * ratio;
    }
    cw = _even(cw);
    ch = _even(ch);
    final left = (center.dx * w - cw / 2).clamp(0.0, w - cw);
    final top = (center.dy * h - ch / 2).clamp(0.0, h - ch);
    return Rect.fromLTWH(_evenFloor(left), _evenFloor(top), cw, ch);
  }

  /// True when [crop] is the whole [video] (nothing to crop).
  static bool isFull(Size video, Rect crop) =>
      crop.left <= 0 && crop.top <= 0 &&
      crop.width >= _even(video.width) && crop.height >= _even(video.height);

  static double _even(double v) => (v ~/ 2 * 2).toDouble();
  static double _evenFloor(double v) => (v.floor() ~/ 2 * 2).toDouble();
}
