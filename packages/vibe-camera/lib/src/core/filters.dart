import 'package:flutter/foundation.dart';

import 'color_matrix.dart';

/// A look: one colour matrix, applied live on the camera and baked into the
/// video on export. [id] is stable (save it, compare it); the label shown is
/// the app's ([VibeCameraStrings.filterName]), with [name] as the default.
@immutable
class VibeFilter {
  const VibeFilter(this.id, this.name, this.matrix);

  final String id;
  final String name;
  final List<double> matrix;

  bool get isNone => VibeColorMatrix.isIdentity(matrix);

  @override
  bool operator ==(Object other) => other is VibeFilter && other.id == id;

  @override
  int get hashCode => id.hashCode;
}

/// The built-in looks, in the order the strip shows them.
abstract final class VibeFilters {
  static const normal = VibeFilter('normal', 'Normal', VibeColorMatrix.identity);

  static final List<VibeFilter> all = [
    normal,
    VibeFilter(
      'vivid',
      'Vivid',
      VibeColorMatrix.chain([
        VibeColorMatrix.saturation(1.35),
        VibeColorMatrix.contrast(0.18),
      ]),
    ),
    VibeFilter(
      'glow',
      'Glow',
      VibeColorMatrix.chain([
        VibeColorMatrix.brightness(0.14),
        VibeColorMatrix.contrast(-0.12),
        VibeColorMatrix.saturation(1.1),
      ]),
    ),
    VibeFilter(
      'warm',
      'Warm',
      VibeColorMatrix.chain([
        VibeColorMatrix.warmth(0.7),
        VibeColorMatrix.brightness(0.04),
      ]),
    ),
    VibeFilter(
      'golden',
      'Golden',
      VibeColorMatrix.chain([
        VibeColorMatrix.warmth(0.55),
        VibeColorMatrix.saturation(1.18),
        VibeColorMatrix.brightness(0.05),
      ]),
    ),
    VibeFilter(
      'rose',
      'Rose',
      VibeColorMatrix.chain([
        VibeColorMatrix.tint(1.08, 0.96, 1.04),
        VibeColorMatrix.brightness(0.06),
      ]),
    ),
    VibeFilter(
      'cool',
      'Cool',
      VibeColorMatrix.chain([
        VibeColorMatrix.warmth(-0.7),
        VibeColorMatrix.saturation(1.05),
      ]),
    ),
    VibeFilter(
      'night',
      'Night',
      VibeColorMatrix.chain([
        VibeColorMatrix.warmth(-0.45),
        VibeColorMatrix.contrast(0.22),
        VibeColorMatrix.brightness(-0.06),
      ]),
    ),
    VibeFilter(
      'fade',
      'Fade',
      VibeColorMatrix.chain([
        VibeColorMatrix.fade(0.8),
        VibeColorMatrix.saturation(0.82),
      ]),
    ),
    VibeFilter(
      'mono',
      'Mono',
      VibeColorMatrix.saturation(0),
    ),
    VibeFilter(
      'noir',
      'Noir',
      VibeColorMatrix.chain([
        VibeColorMatrix.saturation(0),
        VibeColorMatrix.contrast(0.45),
        VibeColorMatrix.brightness(-0.05),
      ]),
    ),
    VibeFilter(
      'sepia',
      'Sepia',
      VibeColorMatrix.mix(VibeColorMatrix.sepia, 0.85),
    ),
  ];

  static VibeFilter byId(String? id) =>
      all.firstWhere((f) => f.id == id, orElse: () => normal);
}
