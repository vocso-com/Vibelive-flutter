import 'dart:ui';

import 'package:flutter/foundation.dart';

import 'adjustments.dart';
import 'color_matrix.dart';
import 'crop.dart';
import 'filters.dart';
import 'text_overlay.dart';
import 'trim.dart';

/// Everything the user did to a clip, as data: the preview draws it and the
/// exporter bakes it in from the same values.
@immutable
class VibeEdit {
  const VibeEdit({
    required this.trim,
    this.filter = VibeFilters.normal,
    this.adjustments = VibeAdjustments.none,
    this.aspect = VibeCropAspect.original,
    this.cropCenter = const Offset(0.5, 0.5),
    this.texts = const [],
  });

  final VibeTrim trim;
  final VibeFilter filter;
  final VibeAdjustments adjustments;
  final VibeCropAspect aspect;

  /// Where the crop frame sits (0–1 of the picture).
  final Offset cropCenter;
  final List<VibeTextOverlay> texts;

  /// The filter, then the adjustments: one matrix.
  List<double> get matrix =>
      VibeColorMatrix.concat(filter.matrix, adjustments.matrix);

  bool get hasColor => !VibeColorMatrix.isIdentity(matrix);

  Rect cropRect(Size video) =>
      VibeCrop.rect(video, aspect, center: cropCenter);

  /// Nothing to bake in: the recording can be used as it is.
  bool isUntouched(Duration duration) =>
      !hasColor &&
      aspect == VibeCropAspect.original &&
      texts.isEmpty &&
      trim.isFull(duration);

  VibeEdit copyWith({
    VibeTrim? trim,
    VibeFilter? filter,
    VibeAdjustments? adjustments,
    VibeCropAspect? aspect,
    Offset? cropCenter,
    List<VibeTextOverlay>? texts,
  }) => VibeEdit(
    trim: trim ?? this.trim,
    filter: filter ?? this.filter,
    adjustments: adjustments ?? this.adjustments,
    aspect: aspect ?? this.aspect,
    cropCenter: cropCenter ?? this.cropCenter,
    texts: texts ?? this.texts,
  );
}
