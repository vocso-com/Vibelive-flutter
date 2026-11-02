import 'dart:math' as math;

/// A 4×5 colour matrix, row-major (20 values): `R' = m0·R + m1·G + m2·B +
/// m3·A + m4` and so on, offsets in 0–255. The same list drives the live
/// preview (Flutter's `ColorFilter.matrix`) and the exported video
/// (pro_video_editor's `ColorFilter`), so what you see is what you get.
abstract final class VibeColorMatrix {
  static const List<double> identity = [
    1, 0, 0, 0, 0, //
    0, 1, 0, 0, 0, //
    0, 0, 1, 0, 0, //
    0, 0, 0, 1, 0, //
  ];

  /// Rec. 709 luminance weights.
  static const _lr = 0.2126, _lg = 0.7152, _lb = 0.0722;

  static bool isIdentity(List<double> m) {
    for (var i = 0; i < 20; i++) {
      if ((m[i] - identity[i]).abs() > 1e-6) return false;
    }
    return true;
  }

  /// [first] then [then]: one matrix doing both.
  static List<double> concat(List<double> first, List<double> then) {
    final out = List<double>.filled(20, 0);
    for (var r = 0; r < 4; r++) {
      for (var c = 0; c < 4; c++) {
        var v = 0.0;
        for (var k = 0; k < 4; k++) {
          v += then[r * 5 + k] * first[k * 5 + c];
        }
        out[r * 5 + c] = v;
      }
      var offset = then[r * 5 + 4];
      for (var k = 0; k < 4; k++) {
        offset += then[r * 5 + k] * first[k * 5 + 4];
      }
      out[r * 5 + 4] = offset;
    }
    return out;
  }

  /// All of [matrices], in order.
  static List<double> chain(Iterable<List<double>> matrices) =>
      matrices.fold(identity, concat);

  /// Adds light evenly: [v] −1…1 (±80 of 255).
  static List<double> brightness(double v) {
    final o = v.clamp(-1.0, 1.0) * 80;
    return [1, 0, 0, 0, o, 0, 1, 0, 0, o, 0, 0, 1, 0, o, 0, 0, 0, 1, 0];
  }

  /// Multiplies light, like opening the aperture: [v] −1…1 (×0.5…×1.5).
  static List<double> exposure(double v) {
    final s = 1 + v.clamp(-1.0, 1.0) * 0.5;
    return [s, 0, 0, 0, 0, 0, s, 0, 0, 0, 0, 0, s, 0, 0, 0, 0, 0, 1, 0];
  }

  /// Around mid-grey: [v] −1…1 (flat … punchy).
  static List<double> contrast(double v) {
    final c = 1 + v.clamp(-1.0, 1.0) * 0.6;
    final o = 128 * (1 - c);
    return [c, 0, 0, 0, o, 0, c, 0, 0, o, 0, 0, c, 0, o, 0, 0, 0, 1, 0];
  }

  /// [s]: 0 grey, 1 unchanged, 2 double.
  static List<double> saturation(double s) {
    final x = s.clamp(0.0, 3.0);
    final ir = (1 - x) * _lr, ig = (1 - x) * _lg, ib = (1 - x) * _lb;
    return [
      ir + x, ig, ib, 0, 0, //
      ir, ig + x, ib, 0, 0, //
      ir, ig, ib + x, 0, 0, //
      0, 0, 0, 1, 0, //
    ];
  }

  /// Colour temperature: [v] −1 (cool, blue) … 1 (warm, amber).
  static List<double> warmth(double v) {
    final w = v.clamp(-1.0, 1.0);
    return [
      1 + 0.14 * w, 0, 0, 0, 10 * w, //
      0, 1 + 0.03 * w, 0, 0, 0, //
      0, 0, 1 - 0.14 * w, 0, -10 * w, //
      0, 0, 0, 1, 0, //
    ];
  }

  /// A colour wash: [r], [g], [b] multipliers.
  static List<double> tint(double r, double g, double b) => [
    r, 0, 0, 0, 0, 0, g, 0, 0, 0, 0, 0, b, 0, 0, 0, 0, 0, 1, 0, //
  ];

  static const List<double> sepia = [
    0.393, 0.769, 0.189, 0, 0, //
    0.349, 0.686, 0.168, 0, 0, //
    0.272, 0.534, 0.131, 0, 0, //
    0, 0, 0, 1, 0, //
  ];

  /// Lifts the blacks (a matte, faded look): [v] 0…1.
  static List<double> fade(double v) {
    final f = v.clamp(0.0, 1.0);
    final s = 1 - 0.25 * f;
    final o = 255 * 0.12 * f;
    return [s, 0, 0, 0, o, 0, s, 0, 0, o, 0, 0, s, 0, o, 0, 0, 0, 1, 0];
  }

  /// [m] with its strength scaled: 0 = none, 1 = full (blends with identity).
  static List<double> mix(List<double> m, double amount) {
    final t = amount.clamp(0.0, 1.0);
    return [
      for (var i = 0; i < 20; i++) identity[i] + (m[i] - identity[i]) * t,
    ];
  }

  /// Applies [m] to one colour (0–255 channels): for tests and thumbnails.
  static List<double> apply(List<double> m, List<double> rgba) {
    return [
      for (var r = 0; r < 4; r++)
        math.max(
          0,
          math.min(
            255,
            m[r * 5] * rgba[0] +
                m[r * 5 + 1] * rgba[1] +
                m[r * 5 + 2] * rgba[2] +
                m[r * 5 + 3] * rgba[3] +
                m[r * 5 + 4],
          ),
        ),
    ];
  }
}
