import 'dart:ui' as ui;

import 'package:flutter/rendering.dart';

import '../core/text_overlay.dart';

/// Lays out and draws a caption. The editor's preview and the exported video
/// use this one function, so a caption lands in the same place, at the same
/// size, in both.
abstract final class VibeTextPainting {
  static const _maxWidthShare = 0.86;

  static TextPainter _painter(VibeTextOverlay t, Size frame) {
    final fontSize = t.size * frame.width;
    final color = switch (t.style) {
      VibeTextStyle.boxed => VibeTextOverlay.onColor(t.color),
      _ => t.color,
    };
    return TextPainter(
      text: TextSpan(
        text: t.text,
        style: TextStyle(
          color: color,
          fontSize: fontSize,
          fontWeight: FontWeight.w800,
          height: 1.15,
          shadows: t.style == VibeTextStyle.plain
              ? [
                  Shadow(
                    color: const Color(0x99000000),
                    blurRadius: fontSize * 0.18,
                    offset: Offset(0, fontSize * 0.04),
                  ),
                ]
              : null,
        ),
      ),
      textAlign: TextAlign.center,
      textDirection: TextDirection.ltr,
    )..layout(maxWidth: frame.width * _maxWidthShare);
  }

  static EdgeInsets _padding(VibeTextOverlay t, Size frame) {
    if (t.style == VibeTextStyle.plain) return EdgeInsets.zero;
    final f = t.size * frame.width;
    return EdgeInsets.symmetric(horizontal: f * 0.42, vertical: f * 0.22);
  }

  /// Where [t] sits in a [frame]-sized picture (its box, padding included):
  /// also the area a finger can grab it by.
  static Rect box(VibeTextOverlay t, Size frame) {
    final p = _painter(t, frame);
    final pad = _padding(t, frame);
    final w = p.width + pad.horizontal;
    final h = p.height + pad.vertical;
    p.dispose();
    final c = Offset(t.position.dx * frame.width, t.position.dy * frame.height);
    return Rect.fromCenter(center: c, width: w, height: h);
  }

  static void paint(Canvas canvas, Size frame, VibeTextOverlay t) {
    if (t.text.trim().isEmpty) return;
    final p = _painter(t, frame);
    final pad = _padding(t, frame);
    final c = Offset(t.position.dx * frame.width, t.position.dy * frame.height);
    final rect = Rect.fromCenter(
      center: c,
      width: p.width + pad.horizontal,
      height: p.height + pad.vertical,
    );
    final radius = Radius.circular(t.size * frame.width * 0.32);
    if (t.style == VibeTextStyle.boxed) {
      canvas.drawRRect(RRect.fromRectAndRadius(rect, radius), Paint()..color = t.color);
    } else if (t.style == VibeTextStyle.soft) {
      canvas.drawRRect(
        RRect.fromRectAndRadius(rect, radius),
        Paint()..color = const Color(0x73000000),
      );
    }
    p.paint(canvas, Offset(rect.left + pad.left, rect.top + pad.top));
    p.dispose();
  }

  /// Every caption on a transparent [frame]-sized PNG: the video overlay.
  static Future<List<int>> png(List<VibeTextOverlay> texts, Size frame) async {
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder, Offset.zero & frame);
    for (final t in texts) {
      paint(canvas, frame, t);
    }
    final image = await recorder.endRecording().toImage(
      frame.width.round(),
      frame.height.round(),
    );
    final data = await image.toByteData(format: ui.ImageByteFormat.png);
    image.dispose();
    return data!.buffer.asUint8List();
  }
}

/// The captions over the editor's preview.
class VibeTextLayerPainter extends CustomPainter {
  VibeTextLayerPainter(this.texts, {this.hiddenId});

  final List<VibeTextOverlay> texts;

  /// Not drawn (being edited in the text box).
  final String? hiddenId;

  @override
  void paint(Canvas canvas, Size size) {
    for (final t in texts) {
      if (t.id != hiddenId) VibeTextPainting.paint(canvas, size, t);
    }
  }

  @override
  bool shouldRepaint(VibeTextLayerPainter old) =>
      old.texts != texts || old.hiddenId != hiddenId;
}
