import 'dart:ui';

import 'package:flutter/foundation.dart';

/// How a caption sits on the clip.
enum VibeTextStyle {
  /// Plain text with a soft shadow.
  plain,

  /// On a solid rounded box (its colour; the text black or white to suit).
  boxed,

  /// On a translucent dark box.
  soft,
}

/// A caption the user placed on the clip. [position] is its centre, 0–1 of
/// the visible (cropped) frame, so it stays put whatever the export size.
@immutable
class VibeTextOverlay {
  const VibeTextOverlay({
    required this.id,
    required this.text,
    this.color = const Color(0xFFFFFFFF),
    this.style = VibeTextStyle.plain,
    this.size = 0.07,
    this.position = const Offset(0.5, 0.45),
  });

  final String id;
  final String text;
  final Color color;
  final VibeTextStyle style;

  /// Font size as a share of the frame's width (0.04–0.14).
  final double size;
  final Offset position;

  VibeTextOverlay copyWith({
    String? text,
    Color? color,
    VibeTextStyle? style,
    double? size,
    Offset? position,
  }) => VibeTextOverlay(
    id: id,
    text: text ?? this.text,
    color: color ?? this.color,
    style: style ?? this.style,
    size: (size ?? this.size).clamp(0.04, 0.14),
    position: position == null
        ? this.position
        : Offset(position.dx.clamp(0.0, 1.0), position.dy.clamp(0.0, 1.0)),
  );

  /// Black or white, whichever reads on [background].
  static Color onColor(Color background) =>
      background.computeLuminance() > 0.55
      ? const Color(0xFF111111)
      : const Color(0xFFFFFFFF);
}
