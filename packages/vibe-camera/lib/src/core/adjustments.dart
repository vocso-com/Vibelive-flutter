import 'package:flutter/foundation.dart';

import 'color_matrix.dart';

/// Light and colour, each −1…1 (0 = unchanged): what the Adjust sliders set.
/// Applied after the filter, so a look can be brightened without losing it.
@immutable
class VibeAdjustments {
  const VibeAdjustments({
    this.brightness = 0,
    this.contrast = 0,
    this.saturation = 0,
    this.warmth = 0,
  });

  static const none = VibeAdjustments();

  final double brightness;
  final double contrast;
  final double saturation;
  final double warmth;

  bool get isNone =>
      brightness == 0 && contrast == 0 && saturation == 0 && warmth == 0;

  List<double> get matrix => VibeColorMatrix.chain([
    if (brightness != 0) VibeColorMatrix.brightness(brightness),
    if (contrast != 0) VibeColorMatrix.contrast(contrast),
    if (saturation != 0) VibeColorMatrix.saturation(1 + saturation),
    if (warmth != 0) VibeColorMatrix.warmth(warmth),
  ]);

  VibeAdjustments copyWith({
    double? brightness,
    double? contrast,
    double? saturation,
    double? warmth,
  }) => VibeAdjustments(
    brightness: (brightness ?? this.brightness).clamp(-1.0, 1.0),
    contrast: (contrast ?? this.contrast).clamp(-1.0, 1.0),
    saturation: (saturation ?? this.saturation).clamp(-1.0, 1.0),
    warmth: (warmth ?? this.warmth).clamp(-1.0, 1.0),
  );

  @override
  bool operator ==(Object other) =>
      other is VibeAdjustments &&
      other.brightness == brightness &&
      other.contrast == contrast &&
      other.saturation == saturation &&
      other.warmth == warmth;

  @override
  int get hashCode => Object.hash(brightness, contrast, saturation, warmth);
}
